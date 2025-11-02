-- =====================================================
-- Phase 3 - Feature #5: Predictive Analytics
-- Stored Procedures for Capacity Forecasting
-- =====================================================
-- File: 82-create-forecasting-procedures.sql
-- Purpose: Generate capacity predictions based on trends
-- Dependencies: 80-create-predictive-analytics-tables.sql
--               81-create-trend-procedures.sql
-- =====================================================

USE MonitoringDB;
GO

SET NOCOUNT ON;
GO

PRINT '======================================'
PRINT 'Creating Capacity Forecasting Procedures'
PRINT '======================================'
PRINT ''

-- =====================================================
-- Create Generic Predictive Alert Rule (if not exists)
-- =====================================================
IF NOT EXISTS (SELECT 1 FROM dbo.AlertRules WHERE RuleName = 'Predictive Capacity Alert')
BEGIN
    INSERT INTO dbo.AlertRules (
        RuleName,
        MetricCategory,
        MetricName,
        HighThreshold,
        CriticalThreshold,
        HighDurationSeconds,
        CriticalDurationSeconds,
        IsEnabled,
        CustomMetricQuery
    )
    VALUES (
        'Predictive Capacity Alert',
        'Capacity',
        'PredictiveAlert',
        30.0,  -- Warning: 30 days to capacity
        7.0,   -- Critical: 7 days to capacity
        300,   -- 5 minutes
        180,   -- 3 minutes
        1,
        NULL
    );

    PRINT 'Created generic Predictive Alert rule'
    PRINT ''
END;
GO

-- =====================================================
-- Stored Procedure: Generate Capacity Forecasts
-- =====================================================

IF OBJECT_ID('dbo.usp_GenerateCapacityForecasts', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GenerateCapacityForecasts;
GO

CREATE PROCEDURE dbo.usp_GenerateCapacityForecasts
    @ServerID INT = NULL,
    @ResourceType VARCHAR(50) = NULL,  -- 'Disk', 'Memory', 'Connections', 'Database', 'TempDB'
    @MinConfidence DECIMAL(10,2) = 0.7 -- Minimum R² for reliable predictions
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ForecastDate DATE = CAST(GETUTCDATE() AS DATE);
    DECLARE @ForecastsGenerated INT = 0;

    -- Delete old forecasts for today (recalculation)
    DELETE FROM dbo.CapacityForecasts
    WHERE ForecastDate = @ForecastDate
      AND (@ServerID IS NULL OR ServerID = @ServerID)
      AND (@ResourceType IS NULL OR ResourceType = @ResourceType);

    PRINT 'Deleted existing forecasts for today';
    PRINT ''

    -- =====================================================
    -- 1. Disk Space Forecasts
    -- =====================================================
    IF @ResourceType IS NULL OR @ResourceType = 'Disk'
    BEGIN
        PRINT 'Generating Disk Space forecasts...'

        INSERT INTO dbo.CapacityForecasts (
            ServerID,
            ResourceType,
            ResourceName,
            ForecastDate,
            CurrentValue,
            CurrentUtilization,
            MaxCapacity,
            WarningThreshold,
            CriticalThreshold,
            DailyGrowthRate,
            PredictedWarningDate,
            PredictedCriticalDate,
            PredictedFullDate,
            DaysToWarning,
            DaysToCritical,
            DaysToFull,
            Confidence,
            PredictionModel,
            TrendID
        )
        SELECT
            t.ServerID,
            'Disk' AS ResourceType,
            t.MetricName AS ResourceName, -- Drive letter (C:, D:, etc.)
            @ForecastDate,

            -- Current state (latest value)
            t.EndValue AS CurrentValue,
            CASE
                WHEN t.MetricName LIKE '%Percent%' THEN t.EndValue
                ELSE NULL
            END AS CurrentUtilization,

            -- Capacity limits
            CASE
                WHEN t.MetricName LIKE '%Percent%' THEN 100.0
                ELSE NULL
            END AS MaxCapacity,
            80.0 AS WarningThreshold,
            90.0 AS CriticalThreshold,

            -- Growth rate
            t.Slope AS DailyGrowthRate,

            -- Predictions (only for increasing trends)
            CASE
                WHEN t.Slope > 0 AND t.MetricName LIKE '%Percent%' THEN
                    DATEADD(DAY, CAST((80.0 - t.EndValue) / t.Slope AS INT), @ForecastDate)
                ELSE NULL
            END AS PredictedWarningDate,

            CASE
                WHEN t.Slope > 0 AND t.MetricName LIKE '%Percent%' THEN
                    DATEADD(DAY, CAST((90.0 - t.EndValue) / t.Slope AS INT), @ForecastDate)
                ELSE NULL
            END AS PredictedCriticalDate,

            CASE
                WHEN t.Slope > 0 AND t.MetricName LIKE '%Percent%' THEN
                    DATEADD(DAY, CAST((100.0 - t.EndValue) / t.Slope AS INT), @ForecastDate)
                ELSE NULL
            END AS PredictedFullDate,

            -- Days to thresholds
            CASE
                WHEN t.Slope > 0 AND t.MetricName LIKE '%Percent%' THEN
                    CAST((80.0 - t.EndValue) / t.Slope AS INT)
                ELSE NULL
            END AS DaysToWarning,

            CASE
                WHEN t.Slope > 0 AND t.MetricName LIKE '%Percent%' THEN
                    CAST((90.0 - t.EndValue) / t.Slope AS INT)
                ELSE NULL
            END AS DaysToCritical,

            CASE
                WHEN t.Slope > 0 AND t.MetricName LIKE '%Percent%' THEN
                    CAST((100.0 - t.EndValue) / t.Slope AS INT)
                ELSE NULL
            END AS DaysToFull,

            -- Confidence
            t.RSquared * 100 AS Confidence,
            'Linear' AS PredictionModel,
            t.TrendID
        FROM dbo.MetricTrends t
        WHERE t.MetricCategory = 'Disk'
          AND t.TrendPeriod = '30day' -- Use 30-day trends for capacity planning
          AND t.CalculationDate = (SELECT MAX(CalculationDate) FROM dbo.MetricTrends)
          AND t.RSquared >= @MinConfidence
          AND t.Slope > 0 -- Only forecast increasing usage
          AND (@ServerID IS NULL OR t.ServerID = @ServerID)
          AND t.EndValue < 100.0; -- Not already full

        SET @ForecastsGenerated = @ForecastsGenerated + @@ROWCOUNT;
        PRINT '  ' + CAST(@@ROWCOUNT AS VARCHAR) + ' Disk forecasts generated'
    END;

    -- =====================================================
    -- 2. Memory Forecasts
    -- =====================================================
    IF @ResourceType IS NULL OR @ResourceType = 'Memory'
    BEGIN
        PRINT 'Generating Memory forecasts...'

        INSERT INTO dbo.CapacityForecasts (
            ServerID,
            ResourceType,
            ResourceName,
            ForecastDate,
            CurrentValue,
            CurrentUtilization,
            MaxCapacity,
            WarningThreshold,
            CriticalThreshold,
            DailyGrowthRate,
            PredictedWarningDate,
            PredictedCriticalDate,
            PredictedFullDate,
            DaysToWarning,
            DaysToCritical,
            DaysToFull,
            Confidence,
            PredictionModel,
            TrendID
        )
        SELECT
            t.ServerID,
            'Memory' AS ResourceType,
            NULL AS ResourceName,
            @ForecastDate,
            t.EndValue AS CurrentValue,
            t.EndValue AS CurrentUtilization,
            100.0 AS MaxCapacity,
            85.0 AS WarningThreshold,
            95.0 AS CriticalThreshold,
            t.Slope AS DailyGrowthRate,

            -- Predictions
            CASE
                WHEN t.Slope > 0 THEN
                    DATEADD(DAY, CAST((85.0 - t.EndValue) / t.Slope AS INT), @ForecastDate)
                ELSE NULL
            END AS PredictedWarningDate,

            CASE
                WHEN t.Slope > 0 THEN
                    DATEADD(DAY, CAST((95.0 - t.EndValue) / t.Slope AS INT), @ForecastDate)
                ELSE NULL
            END AS PredictedCriticalDate,

            CASE
                WHEN t.Slope > 0 THEN
                    DATEADD(DAY, CAST((100.0 - t.EndValue) / t.Slope AS INT), @ForecastDate)
                ELSE NULL
            END AS PredictedFullDate,

            -- Days to thresholds
            CASE
                WHEN t.Slope > 0 THEN CAST((85.0 - t.EndValue) / t.Slope AS INT)
                ELSE NULL
            END AS DaysToWarning,

            CASE
                WHEN t.Slope > 0 THEN CAST((95.0 - t.EndValue) / t.Slope AS INT)
                ELSE NULL
            END AS DaysToCritical,

            CASE
                WHEN t.Slope > 0 THEN CAST((100.0 - t.EndValue) / t.Slope AS INT)
                ELSE NULL
            END AS DaysToFull,

            t.RSquared * 100 AS Confidence,
            'Linear' AS PredictionModel,
            t.TrendID
        FROM dbo.MetricTrends t
        WHERE t.MetricCategory = 'Memory'
          AND t.MetricName = 'Percent'
          AND t.TrendPeriod = '30day'
          AND t.CalculationDate = (SELECT MAX(CalculationDate) FROM dbo.MetricTrends)
          AND t.RSquared >= @MinConfidence
          AND t.Slope > 0
          AND (@ServerID IS NULL OR t.ServerID = @ServerID)
          AND t.EndValue < 100.0;

        SET @ForecastsGenerated = @ForecastsGenerated + @@ROWCOUNT;
        PRINT '  ' + CAST(@@ROWCOUNT AS VARCHAR) + ' Memory forecasts generated'
    END;

    -- =====================================================
    -- 3. Connection Pool Forecasts
    -- =====================================================
    IF @ResourceType IS NULL OR @ResourceType = 'Connections'
    BEGIN
        PRINT 'Generating Connection forecasts...'

        INSERT INTO dbo.CapacityForecasts (
            ServerID,
            ResourceType,
            ResourceName,
            ForecastDate,
            CurrentValue,
            CurrentUtilization,
            MaxCapacity,
            WarningThreshold,
            CriticalThreshold,
            DailyGrowthRate,
            PredictedWarningDate,
            PredictedCriticalDate,
            PredictedFullDate,
            DaysToWarning,
            DaysToCritical,
            DaysToFull,
            Confidence,
            PredictionModel,
            TrendID
        )
        SELECT
            t.ServerID,
            'Connections' AS ResourceType,
            NULL AS ResourceName,
            @ForecastDate,
            t.EndValue AS CurrentValue,

            -- Calculate utilization (assuming max connections from config)
            CASE
                WHEN t.EndValue > 0 THEN (t.EndValue / 32767.0) * 100 -- SQL Server default max
                ELSE 0
            END AS CurrentUtilization,

            32767.0 AS MaxCapacity, -- SQL Server default max connections
            80.0 AS WarningThreshold,
            90.0 AS CriticalThreshold,
            t.Slope AS DailyGrowthRate,

            -- Predictions
            CASE
                WHEN t.Slope > 0 THEN
                    DATEADD(DAY, CAST((32767.0 * 0.80 - t.EndValue) / t.Slope AS INT), @ForecastDate)
                ELSE NULL
            END AS PredictedWarningDate,

            CASE
                WHEN t.Slope > 0 THEN
                    DATEADD(DAY, CAST((32767.0 * 0.90 - t.EndValue) / t.Slope AS INT), @ForecastDate)
                ELSE NULL
            END AS PredictedCriticalDate,

            CASE
                WHEN t.Slope > 0 THEN
                    DATEADD(DAY, CAST((32767.0 - t.EndValue) / t.Slope AS INT), @ForecastDate)
                ELSE NULL
            END AS PredictedFullDate,

            -- Days to thresholds
            CASE
                WHEN t.Slope > 0 THEN CAST((32767.0 * 0.80 - t.EndValue) / t.Slope AS INT)
                ELSE NULL
            END AS DaysToWarning,

            CASE
                WHEN t.Slope > 0 THEN CAST((32767.0 * 0.90 - t.EndValue) / t.Slope AS INT)
                ELSE NULL
            END AS DaysToCritical,

            CASE
                WHEN t.Slope > 0 THEN CAST((32767.0 - t.EndValue) / t.Slope AS INT)
                ELSE NULL
            END AS DaysToFull,

            t.RSquared * 100 AS Confidence,
            'Linear' AS PredictionModel,
            t.TrendID
        FROM dbo.MetricTrends t
        WHERE t.MetricCategory = 'Connections'
          AND t.MetricName = 'UserConnections'
          AND t.TrendPeriod = '30day'
          AND t.CalculationDate = (SELECT MAX(CalculationDate) FROM dbo.MetricTrends)
          AND t.RSquared >= @MinConfidence
          AND t.Slope > 0
          AND (@ServerID IS NULL OR t.ServerID = @ServerID);

        SET @ForecastsGenerated = @ForecastsGenerated + @@ROWCOUNT;
        PRINT '  ' + CAST(@@ROWCOUNT AS VARCHAR) + ' Connection forecasts generated'
    END;

    -- =====================================================
    -- 4. Database Size Forecasts
    -- =====================================================
    IF @ResourceType IS NULL OR @ResourceType = 'Database'
    BEGIN
        PRINT 'Generating Database Size forecasts...'

        INSERT INTO dbo.CapacityForecasts (
            ServerID,
            ResourceType,
            ResourceName,
            ForecastDate,
            CurrentValue,
            CurrentUtilization,
            MaxCapacity,
            WarningThreshold,
            CriticalThreshold,
            DailyGrowthRate,
            PredictedWarningDate,
            PredictedCriticalDate,
            PredictedFullDate,
            DaysToWarning,
            DaysToCritical,
            DaysToFull,
            Confidence,
            PredictionModel,
            TrendID
        )
        SELECT
            t.ServerID,
            'Database' AS ResourceType,
            t.MetricName AS ResourceName, -- Database name
            @ForecastDate,
            t.EndValue AS CurrentValue,
            NULL AS CurrentUtilization, -- Unknown without max size config
            NULL AS MaxCapacity,
            80.0 AS WarningThreshold,
            90.0 AS CriticalThreshold,
            t.Slope AS DailyGrowthRate,
            NULL AS PredictedWarningDate,   -- Can't predict without max capacity
            NULL AS PredictedCriticalDate,
            NULL AS PredictedFullDate,
            NULL AS DaysToWarning,
            NULL AS DaysToCritical,
            NULL AS DaysToFull,
            t.RSquared * 100 AS Confidence,
            'Linear' AS PredictionModel,
            t.TrendID
        FROM dbo.MetricTrends t
        WHERE t.MetricCategory = 'Database'
          AND t.MetricName LIKE '%Size%'
          AND t.TrendPeriod = '30day'
          AND t.CalculationDate = (SELECT MAX(CalculationDate) FROM dbo.MetricTrends)
          AND t.RSquared >= @MinConfidence
          AND t.Slope > 0.1 -- Only if growing >100MB/day
          AND (@ServerID IS NULL OR t.ServerID = @ServerID);

        SET @ForecastsGenerated = @ForecastsGenerated + @@ROWCOUNT;
        PRINT '  ' + CAST(@@ROWCOUNT AS VARCHAR) + ' Database Size forecasts generated'
    END;

    -- =====================================================
    -- 5. TempDB Forecasts
    -- =====================================================
    IF @ResourceType IS NULL OR @ResourceType = 'TempDB'
    BEGIN
        PRINT 'Generating TempDB forecasts...'

        INSERT INTO dbo.CapacityForecasts (
            ServerID,
            ResourceType,
            ResourceName,
            ForecastDate,
            CurrentValue,
            CurrentUtilization,
            MaxCapacity,
            WarningThreshold,
            CriticalThreshold,
            DailyGrowthRate,
            PredictedWarningDate,
            PredictedCriticalDate,
            PredictedFullDate,
            DaysToWarning,
            DaysToCritical,
            DaysToFull,
            Confidence,
            PredictionModel,
            TrendID
        )
        SELECT
            t.ServerID,
            'TempDB' AS ResourceType,
            'TempDB' AS ResourceName,
            @ForecastDate,
            t.EndValue AS CurrentValue,
            NULL AS CurrentUtilization,
            NULL AS MaxCapacity,
            80.0 AS WarningThreshold,
            90.0 AS CriticalThreshold,
            t.Slope AS DailyGrowthRate,
            NULL AS PredictedWarningDate,
            NULL AS PredictedCriticalDate,
            NULL AS PredictedFullDate,
            NULL AS DaysToWarning,
            NULL AS DaysToCritical,
            NULL AS DaysToFull,
            t.RSquared * 100 AS Confidence,
            'Linear' AS PredictionModel,
            t.TrendID
        FROM dbo.MetricTrends t
        WHERE t.MetricCategory = 'TempDB'
          AND t.MetricName LIKE '%Size%'
          AND t.TrendPeriod = '14day' -- Shorter window for TempDB (more volatile)
          AND t.CalculationDate = (SELECT MAX(CalculationDate) FROM dbo.MetricTrends)
          AND t.RSquared >= @MinConfidence
          AND t.Slope > 0.05
          AND (@ServerID IS NULL OR t.ServerID = @ServerID);

        SET @ForecastsGenerated = @ForecastsGenerated + @@ROWCOUNT;
        PRINT '  ' + CAST(@@ROWCOUNT AS VARCHAR) + ' TempDB forecasts generated'
    END;

    PRINT ''
    PRINT 'Total forecasts generated: ' + CAST(@ForecastsGenerated AS VARCHAR)

    -- Return summary
    SELECT
        ResourceType,
        COUNT(*) AS ForecastCount,
        AVG(Confidence) AS AvgConfidence,
        MIN(DaysToWarning) AS MinDaysToWarning,
        MIN(DaysToCritical) AS MinDaysToCritical,
        MIN(DaysToFull) AS MinDaysToFull
    FROM dbo.CapacityForecasts
    WHERE ForecastDate = @ForecastDate
      AND (@ServerID IS NULL OR ServerID = @ServerID)
      AND (@ResourceType IS NULL OR ResourceType = @ResourceType)
    GROUP BY ResourceType
    ORDER BY MinDaysToWarning;
END;
GO

PRINT 'Created: dbo.usp_GenerateCapacityForecasts'
PRINT ''

-- =====================================================
-- Stored Procedure: Evaluate Predictive Alerts
-- =====================================================

IF OBJECT_ID('dbo.usp_EvaluatePredictiveAlerts', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_EvaluatePredictiveAlerts;
GO

CREATE PROCEDURE dbo.usp_EvaluatePredictiveAlerts
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @AlertsRaised INT = 0;
    DECLARE @Now DATETIME2(7) = GETUTCDATE();
    DECLARE @TodayDate DATE = CAST(@Now AS DATE);
    DECLARE @PredictiveRuleID INT;

    -- Get the Predictive Alert RuleID
    SELECT @PredictiveRuleID = RuleID
    FROM dbo.AlertRules
    WHERE RuleName = 'Predictive Capacity Alert';

    IF @PredictiveRuleID IS NULL
    BEGIN
        RAISERROR('Predictive Capacity Alert rule not found. Run 82-create-forecasting-procedures.sql', 16, 1);
        RETURN;
    END;

    PRINT 'Evaluating predictive alerts...'
    PRINT ''

    -- Cursor for each enabled predictive alert
    DECLARE @AlertID INT;
    DECLARE @AlertName NVARCHAR(255);
    DECLARE @ResourceType VARCHAR(50);
    DECLARE @WarningDaysThreshold INT;
    DECLARE @CriticalDaysThreshold INT;
    DECLARE @MinimumConfidence DECIMAL(10,2);

    DECLARE alert_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT
            PredictiveAlertID,
            AlertName,
            ResourceType,
            WarningDaysThreshold,
            CriticalDaysThreshold,
            MinimumConfidence
        FROM dbo.PredictiveAlerts
        WHERE IsEnabled = 1
        ORDER BY ResourceType;

    OPEN alert_cursor;
    FETCH NEXT FROM alert_cursor INTO @AlertID, @AlertName, @ResourceType, @WarningDaysThreshold, @CriticalDaysThreshold, @MinimumConfidence;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Check for critical threshold violations
        DECLARE @ServerID INT;
        DECLARE @DaysToCritical INT;
        DECLARE @PredictedDate DATE;
        DECLARE @Confidence DECIMAL(10,2);
        DECLARE @ResourceName VARCHAR(200);
        DECLARE @AlertMessage NVARCHAR(MAX);
        DECLARE @NewAlertID BIGINT;

        DECLARE forecast_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT
                cf.ServerID,
                cf.DaysToCritical,
                cf.PredictedCriticalDate,
                cf.Confidence,
                cf.ResourceName
            FROM dbo.CapacityForecasts cf
            WHERE cf.ForecastDate = @TodayDate
              AND cf.ResourceType = @ResourceType
              AND cf.DaysToCritical IS NOT NULL
              AND cf.DaysToCritical <= @CriticalDaysThreshold
              AND cf.DaysToCritical > 0
              AND cf.Confidence >= @MinimumConfidence
              AND NOT EXISTS (
                  SELECT 1
                  FROM dbo.AlertHistory ah
                  WHERE ah.ServerID = cf.ServerID
                    AND ah.Message LIKE '%' + cf.ResourceType + '%critical capacity%'
                    AND ah.RaisedAt >= DATEADD(HOUR, -24, @Now)
              );

        OPEN forecast_cursor;
        FETCH NEXT FROM forecast_cursor INTO @ServerID, @DaysToCritical, @PredictedDate, @Confidence, @ResourceName;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @AlertMessage = 'CAPACITY WARNING: ' + @ResourceType +
                CASE WHEN @ResourceName IS NOT NULL THEN ' (' + @ResourceName + ')' ELSE '' END +
                ' will reach critical capacity (90%) in ' + CAST(@DaysToCritical AS VARCHAR) + ' days' +
                ' (Predicted: ' + CONVERT(VARCHAR(10), @PredictedDate, 120) + ')' +
                ' - Confidence: ' + CAST(CAST(@Confidence AS INT) AS VARCHAR) + '%';

            -- Create ActiveAlert
            INSERT INTO dbo.ActiveAlerts (
                RuleID,
                ServerID,
                Severity,
                CurrentValue,
                ThresholdValue,
                Message,
                RaisedAt
            )
            VALUES (
                @PredictiveRuleID,
                @ServerID,
                'Critical',
                @DaysToCritical,
                @CriticalDaysThreshold,
                @AlertMessage,
                @Now
            );

            SET @NewAlertID = SCOPE_IDENTITY();

            -- Log to AlertHistory
            INSERT INTO dbo.AlertHistory (
                AlertID,
                RuleID,
                ServerID,
                Severity,
                MaxValue,
                ThresholdValue,
                Message,
                RaisedAt,
                ResolvedAt,
                DurationMinutes
            )
            VALUES (
                @NewAlertID,
                @PredictiveRuleID,
                @ServerID,
                'Critical',
                @DaysToCritical,
                @CriticalDaysThreshold,
                @AlertMessage,
                @Now,
                @Now,  -- Initially set to RaisedAt (active alert)
                0      -- Duration is 0 for new alerts
            );

            SET @AlertsRaised = @AlertsRaised + 1;

            FETCH NEXT FROM forecast_cursor INTO @ServerID, @DaysToCritical, @PredictedDate, @Confidence, @ResourceName;
        END;

        CLOSE forecast_cursor;
        DEALLOCATE forecast_cursor;

        -- Check for warning threshold violations
        DECLARE @DaysToWarning INT;
        DECLARE @PredictedWarningDate DATE;

        DECLARE warning_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT
                cf.ServerID,
                cf.DaysToWarning,
                cf.PredictedWarningDate,
                cf.Confidence,
                cf.ResourceName
            FROM dbo.CapacityForecasts cf
            WHERE cf.ForecastDate = @TodayDate
              AND cf.ResourceType = @ResourceType
              AND cf.DaysToWarning IS NOT NULL
              AND cf.DaysToWarning <= @WarningDaysThreshold
              AND cf.DaysToWarning > @CriticalDaysThreshold
              AND cf.DaysToCritical > @CriticalDaysThreshold
              AND cf.Confidence >= @MinimumConfidence
              AND NOT EXISTS (
                  SELECT 1
                  FROM dbo.AlertHistory ah
                  WHERE ah.ServerID = cf.ServerID
                    AND ah.Message LIKE '%' + cf.ResourceType + '%warning capacity%'
                    AND ah.RaisedAt >= DATEADD(HOUR, -24, @Now)
              );

        OPEN warning_cursor;
        FETCH NEXT FROM warning_cursor INTO @ServerID, @DaysToWarning, @PredictedWarningDate, @Confidence, @ResourceName;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @AlertMessage = 'CAPACITY ADVISORY: ' + @ResourceType +
                CASE WHEN @ResourceName IS NOT NULL THEN ' (' + @ResourceName + ')' ELSE '' END +
                ' will reach warning capacity (80%) in ' + CAST(@DaysToWarning AS VARCHAR) + ' days' +
                ' (Predicted: ' + CONVERT(VARCHAR(10), @PredictedWarningDate, 120) + ')' +
                ' - Confidence: ' + CAST(CAST(@Confidence AS INT) AS VARCHAR) + '%';

            -- Create ActiveAlert
            INSERT INTO dbo.ActiveAlerts (
                RuleID,
                ServerID,
                Severity,
                CurrentValue,
                ThresholdValue,
                Message,
                RaisedAt
            )
            VALUES (
                @PredictiveRuleID,
                @ServerID,
                'High',
                @DaysToWarning,
                @WarningDaysThreshold,
                @AlertMessage,
                @Now
            );

            SET @NewAlertID = SCOPE_IDENTITY();

            -- Log to AlertHistory
            INSERT INTO dbo.AlertHistory (
                AlertID,
                RuleID,
                ServerID,
                Severity,
                MaxValue,
                ThresholdValue,
                Message,
                RaisedAt,
                ResolvedAt,
                DurationMinutes
            )
            VALUES (
                @NewAlertID,
                @PredictiveRuleID,
                @ServerID,
                'High',
                @DaysToWarning,
                @WarningDaysThreshold,
                @AlertMessage,
                @Now,
                @Now,  -- Initially set to RaisedAt (active alert)
                0      -- Duration is 0 for new alerts
            );

            SET @AlertsRaised = @AlertsRaised + 1;

            FETCH NEXT FROM warning_cursor INTO @ServerID, @DaysToWarning, @PredictedWarningDate, @Confidence, @ResourceName;
        END;

        CLOSE warning_cursor;
        DEALLOCATE warning_cursor;

        FETCH NEXT FROM alert_cursor INTO @AlertID, @AlertName, @ResourceType, @WarningDaysThreshold, @CriticalDaysThreshold, @MinimumConfidence;
    END;

    CLOSE alert_cursor;
    DEALLOCATE alert_cursor;

    PRINT 'Predictive alerts raised: ' + CAST(@AlertsRaised AS VARCHAR)
    PRINT ''

    -- Return summary
    SELECT
        Severity,
        COUNT(*) AS AlertCount
    FROM dbo.AlertHistory
    WHERE RaisedAt >= DATEADD(MINUTE, -5, @Now)
      AND Message LIKE 'CAPACITY%'
    GROUP BY Severity
    ORDER BY
        CASE Severity
            WHEN 'Critical' THEN 1
            WHEN 'High' THEN 2
            WHEN 'Medium' THEN 3
            WHEN 'Low' THEN 4
        END;
END;
GO

PRINT 'Created: dbo.usp_EvaluatePredictiveAlerts'
PRINT ''

-- =====================================================
-- Stored Procedure: Get Capacity Summary
-- =====================================================

IF OBJECT_ID('dbo.usp_GetCapacitySummary', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetCapacitySummary;
GO

CREATE PROCEDURE dbo.usp_GetCapacitySummary
    @ServerID INT = NULL,
    @MaxDaysToWarning INT = 90 -- Only show resources within 90 days of warning
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        s.ServerName,
        cf.ResourceType,
        cf.ResourceName,
        cf.CurrentValue,
        cf.CurrentUtilization,
        cf.DailyGrowthRate,
        cf.DaysToWarning,
        cf.DaysToCritical,
        cf.DaysToFull,
        cf.PredictedWarningDate,
        cf.PredictedCriticalDate,
        cf.PredictedFullDate,
        cf.Confidence,
        CASE
            WHEN cf.DaysToCritical IS NOT NULL AND cf.DaysToCritical <= 7 THEN 'Critical'
            WHEN cf.DaysToWarning IS NOT NULL AND cf.DaysToWarning <= 14 THEN 'High'
            WHEN cf.DaysToWarning IS NOT NULL AND cf.DaysToWarning <= 30 THEN 'Medium'
            ELSE 'Low'
        END AS UrgencyLevel
    FROM dbo.CapacityForecasts cf
    INNER JOIN dbo.Servers s ON cf.ServerID = s.ServerID
    WHERE cf.ForecastDate = (SELECT MAX(ForecastDate) FROM dbo.CapacityForecasts)
      AND (@ServerID IS NULL OR cf.ServerID = @ServerID)
      AND (cf.DaysToWarning IS NULL OR cf.DaysToWarning <= @MaxDaysToWarning)
    ORDER BY
        CASE
            WHEN cf.DaysToCritical IS NOT NULL THEN cf.DaysToCritical
            WHEN cf.DaysToWarning IS NOT NULL THEN cf.DaysToWarning
            ELSE 9999
        END,
        s.ServerName,
        cf.ResourceType;
END;
GO

PRINT 'Created: dbo.usp_GetCapacitySummary'
PRINT ''

-- =====================================================
-- Summary and Verification
-- =====================================================

PRINT '======================================'
PRINT 'Capacity Forecasting Procedures Created'
PRINT '======================================'
PRINT ''

PRINT 'Stored Procedures:'
PRINT '  usp_GenerateCapacityForecasts - Generate capacity predictions'
PRINT '  usp_EvaluatePredictiveAlerts - Raise alerts for capacity warnings'
PRINT '  usp_GetCapacitySummary - Retrieve capacity summary for all servers'
PRINT ''

PRINT 'Usage Examples:'
PRINT ''
PRINT '  -- Generate forecasts for all servers/resources'
PRINT '  EXEC dbo.usp_GenerateCapacityForecasts;'
PRINT ''
PRINT '  -- Generate forecasts for specific server'
PRINT '  EXEC dbo.usp_GenerateCapacityForecasts @ServerID = 1;'
PRINT ''
PRINT '  -- Generate forecasts for specific resource type'
PRINT '  EXEC dbo.usp_GenerateCapacityForecasts @ResourceType = ''Disk'';'
PRINT ''
PRINT '  -- Evaluate predictive alerts'
PRINT '  EXEC dbo.usp_EvaluatePredictiveAlerts;'
PRINT ''
PRINT '  -- Get capacity summary (resources within 90 days of warning)'
PRINT '  EXEC dbo.usp_GetCapacitySummary;'
PRINT ''

PRINT 'Next Steps:'
PRINT '  1. Run initial forecast generation'
PRINT '  2. Create SQL Agent jobs for automation (83-create-predictive-sql-agent-jobs.sql)'
PRINT '  3. Create Grafana dashboards for visualization'
PRINT '======================================'
PRINT ''

GO
