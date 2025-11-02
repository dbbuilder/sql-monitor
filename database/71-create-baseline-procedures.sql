-- =====================================================
-- Phase 3 - Feature #4: Historical Baseline Comparison
-- Stored Procedures for Baseline Calculation and Anomaly Detection
-- =====================================================
-- File: 71-create-baseline-procedures.sql
-- Purpose: Calculate statistical baselines and detect anomalies
-- Dependencies: 70-create-baseline-tables.sql
-- =====================================================

USE MonitoringDB;
GO

SET QUOTED_IDENTIFIER ON;
GO

PRINT '======================================';
PRINT 'Creating Baseline Calculation Procedures';
PRINT '======================================';
PRINT '';

-- =====================================================
-- Stored Procedure: Calculate Baseline for Metric
-- =====================================================

IF OBJECT_ID('dbo.usp_CalculateBaseline', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CalculateBaseline;
GO

CREATE PROCEDURE dbo.usp_CalculateBaseline
    @ServerID INT,
    @MetricCategory VARCHAR(50),
    @MetricName VARCHAR(100),
    @BaselinePeriod VARCHAR(20) -- '7day', '14day', '30day', '90day'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @DaysBack INT;
    DECLARE @BaselineDate DATE = CAST(GETUTCDATE() AS DATE);
    DECLARE @SampleStartTime DATETIME2(7);
    DECLARE @SampleEndTime DATETIME2(7);

    -- Determine lookback period
    SET @DaysBack = CASE @BaselinePeriod
        WHEN '7day' THEN 7
        WHEN '14day' THEN 14
        WHEN '30day' THEN 30
        WHEN '90day' THEN 90
        ELSE 7
    END;

    SET @SampleStartTime = DATEADD(DAY, -@DaysBack, GETUTCDATE());
    SET @SampleEndTime = GETUTCDATE();

    -- Calculate baseline statistics
    ;WITH MetricData AS (
        SELECT
            MetricValue,
            ROW_NUMBER() OVER (ORDER BY MetricValue) AS RowNum,
            COUNT(*) OVER () AS TotalRows
        FROM dbo.PerformanceMetrics
        WHERE ServerID = @ServerID
          AND MetricCategory = @MetricCategory
          AND MetricName = @MetricName
          AND CollectionTime >= @SampleStartTime
          AND CollectionTime < @SampleEndTime
    ),
    Stats AS (
        SELECT
            AVG(MetricValue) AS AvgValue,
            MIN(MetricValue) AS MinValue,
            MAX(MetricValue) AS MaxValue,
            STDEV(MetricValue) AS StdDevValue,
            COUNT(*) AS SampleCount
        FROM MetricData
    ),
    Percentiles AS (
        SELECT
            MAX(CASE WHEN RowNum = CAST(TotalRows * 0.50 AS INT) THEN MetricValue END) AS P50Value,
            MAX(CASE WHEN RowNum = CAST(TotalRows * 0.95 AS INT) THEN MetricValue END) AS P95Value,
            MAX(CASE WHEN RowNum = CAST(TotalRows * 0.99 AS INT) THEN MetricValue END) AS P99Value
        FROM MetricData
    )
    INSERT INTO dbo.MetricBaselines (
        ServerID,
        MetricCategory,
        MetricName,
        BaselinePeriod,
        BaselineDate,
        AvgValue,
        MinValue,
        MaxValue,
        StdDevValue,
        MedianValue,
        P95Value,
        P99Value,
        SampleCount,
        SampleStartTime,
        SampleEndTime
    )
    SELECT
        @ServerID,
        @MetricCategory,
        @MetricName,
        @BaselinePeriod,
        @BaselineDate,
        s.AvgValue,
        s.MinValue,
        s.MaxValue,
        s.StdDevValue,
        p.P50Value AS MedianValue,
        p.P95Value,
        p.P99Value,
        s.SampleCount,
        @SampleStartTime,
        @SampleEndTime
    FROM Stats s
    CROSS JOIN Percentiles p
    WHERE s.SampleCount >= 100; -- Minimum sample size

END;
GO

PRINT '✅ Created: dbo.usp_CalculateBaseline';
PRINT '';

-- =====================================================
-- Stored Procedure: Update All Baselines
-- =====================================================

IF OBJECT_ID('dbo.usp_UpdateAllBaselines', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_UpdateAllBaselines;
GO

CREATE PROCEDURE dbo.usp_UpdateAllBaselines
    @BaselinePeriod VARCHAR(20) = NULL -- NULL = all periods
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartTime DATETIME2(7) = GETUTCDATE();
    DECLARE @ServersProcessed INT = 0;
    DECLARE @MetricsProcessed INT = 0;
    DECLARE @BaselinesCreated INT = 0;
    DECLARE @ErrorCount INT = 0;

    PRINT 'Starting baseline calculation for period: ' + ISNULL(@BaselinePeriod, 'ALL');
    PRINT '';

    -- Delete old baselines for today (recalculation)
    -- First, nullify BaselineID in AnomalyDetections to avoid FK constraint violation
    UPDATE dbo.AnomalyDetections
    SET BaselineID = NULL
    WHERE BaselineID IN (
        SELECT BaselineID FROM dbo.MetricBaselines
        WHERE BaselineDate = CAST(GETUTCDATE() AS DATE)
          AND (@BaselinePeriod IS NULL OR BaselinePeriod = @BaselinePeriod)
    );

    -- Now delete old baselines
    DELETE FROM dbo.MetricBaselines
    WHERE BaselineDate = CAST(GETUTCDATE() AS DATE)
      AND (@BaselinePeriod IS NULL OR BaselinePeriod = @BaselinePeriod);

    -- Cursor for each active server
    DECLARE @ServerID INT;
    DECLARE @ServerName NVARCHAR(255);

    DECLARE server_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT ServerID, ServerName
        FROM dbo.Servers
        WHERE IsActive = 1
        ORDER BY ServerID;

    OPEN server_cursor;
    FETCH NEXT FROM server_cursor INTO @ServerID, @ServerName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            -- Get distinct metrics for this server
            DECLARE @MetricCategory VARCHAR(50);
            DECLARE @MetricName VARCHAR(100);

            DECLARE metric_cursor CURSOR LOCAL FAST_FORWARD FOR
                SELECT DISTINCT MetricCategory, MetricName
                FROM dbo.PerformanceMetrics
                WHERE ServerID = @ServerID
                  AND CollectionTime >= DATEADD(DAY, -90, GETUTCDATE()) -- Only recent metrics
                ORDER BY MetricCategory, MetricName;

            OPEN metric_cursor;
            FETCH NEXT FROM metric_cursor INTO @MetricCategory, @MetricName;

            WHILE @@FETCH_STATUS = 0
            BEGIN
                BEGIN TRY
                    -- Calculate baseline for each period (or specified period)
                    IF @BaselinePeriod IS NULL OR @BaselinePeriod = '7day'
                        EXEC dbo.usp_CalculateBaseline @ServerID, @MetricCategory, @MetricName, '7day';

                    IF @BaselinePeriod IS NULL OR @BaselinePeriod = '14day'
                        EXEC dbo.usp_CalculateBaseline @ServerID, @MetricCategory, @MetricName, '14day';

                    IF @BaselinePeriod IS NULL OR @BaselinePeriod = '30day'
                        EXEC dbo.usp_CalculateBaseline @ServerID, @MetricCategory, @MetricName, '30day';

                    IF @BaselinePeriod IS NULL OR @BaselinePeriod = '90day'
                        EXEC dbo.usp_CalculateBaseline @ServerID, @MetricCategory, @MetricName, '90day';

                    SET @MetricsProcessed = @MetricsProcessed + 1;
                END TRY
                BEGIN CATCH
                    SET @ErrorCount = @ErrorCount + 1;
                    PRINT 'Error calculating baseline for ' + @ServerName + '.' + @MetricCategory + '.' + @MetricName + ': ' + ERROR_MESSAGE();
                END CATCH;

                FETCH NEXT FROM metric_cursor INTO @MetricCategory, @MetricName;
            END;

            CLOSE metric_cursor;
            DEALLOCATE metric_cursor;

            SET @ServersProcessed = @ServersProcessed + 1;
            PRINT '✅ ' + @ServerName + ': ' + CAST(@MetricsProcessed AS VARCHAR) + ' metrics processed';
        END TRY
        BEGIN CATCH
            SET @ErrorCount = @ErrorCount + 1;
            PRINT '❌ ' + @ServerName + ': ' + ERROR_MESSAGE();
        END CATCH;

        FETCH NEXT FROM server_cursor INTO @ServerID, @ServerName;
    END;

    CLOSE server_cursor;
    DEALLOCATE server_cursor;

    -- Count baselines created
    SELECT @BaselinesCreated = COUNT(*)
    FROM dbo.MetricBaselines
    WHERE BaselineDate = CAST(GETUTCDATE() AS DATE)
      AND (@BaselinePeriod IS NULL OR BaselinePeriod = @BaselinePeriod);

    -- Log calculation history
    DECLARE @DurationSeconds INT = DATEDIFF(SECOND, @StartTime, GETUTCDATE());

    INSERT INTO dbo.BaselineCalculationHistory (
        CalculationTime,
        BaselinePeriod,
        ServersProcessed,
        MetricsProcessed,
        BaselinesCreated,
        AnomaliesDetected,
        DurationSeconds,
        ErrorCount,
        Status
    )
    VALUES (
        GETUTCDATE(),
        ISNULL(@BaselinePeriod, 'ALL'),
        @ServersProcessed,
        @MetricsProcessed,
        @BaselinesCreated,
        0, -- Anomalies detected separately
        @DurationSeconds,
        @ErrorCount,
        CASE WHEN @ErrorCount = 0 THEN 'Success' WHEN @BaselinesCreated > 0 THEN 'Partial' ELSE 'Failed' END
    );

    PRINT '';
    PRINT '======================================';
    PRINT 'Baseline Calculation Summary';
    PRINT '======================================';
    PRINT 'Servers processed: ' + CAST(@ServersProcessed AS VARCHAR);
    PRINT 'Metrics processed: ' + CAST(@MetricsProcessed AS VARCHAR);
    PRINT 'Baselines created: ' + CAST(@BaselinesCreated AS VARCHAR);
    PRINT 'Errors: ' + CAST(@ErrorCount AS VARCHAR);
    PRINT 'Duration: ' + CAST(@DurationSeconds AS VARCHAR) + ' seconds';
    PRINT '======================================';
END;
GO

PRINT '✅ Created: dbo.usp_UpdateAllBaselines';
PRINT '';

-- =====================================================
-- Stored Procedure: Detect Anomalies
-- =====================================================

IF OBJECT_ID('dbo.usp_DetectAnomalies', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_DetectAnomalies;
GO

CREATE PROCEDURE dbo.usp_DetectAnomalies
    @ServerID INT = NULL, -- NULL = all servers
    @BaselinePeriod VARCHAR(20) = '7day'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @AnomaliesDetected INT = 0;
    DECLARE @StartTime DATETIME2(7) = GETUTCDATE();

    PRINT 'Detecting anomalies using ' + @BaselinePeriod + ' baseline...';
    PRINT '';

    -- Get recent metrics (last 15 minutes) and compare to baseline
    INSERT INTO dbo.AnomalyDetections (
        ServerID,
        MetricCategory,
        MetricName,
        DetectionTime,
        CurrentValue,
        BaselineValue,
        BaselineStdDev,
        DeviationScore,
        Severity,
        AnomalyType,
        BaselinePeriod,
        BaselineID
    )
    SELECT
        pm.ServerID,
        pm.MetricCategory,
        pm.MetricName,
        GETUTCDATE() AS DetectionTime,
        AVG(pm.MetricValue) AS CurrentValue,
        mb.AvgValue AS BaselineValue,
        mb.StdDevValue AS BaselineStdDev,
        -- Calculate z-score (standard deviations from mean)
        CASE
            WHEN mb.StdDevValue > 0 THEN ABS(AVG(pm.MetricValue) - mb.AvgValue) / mb.StdDevValue
            ELSE 0
        END AS DeviationScore,
        -- Determine severity based on deviation and thresholds
        CASE
            WHEN CASE WHEN mb.StdDevValue > 0 THEN ABS(AVG(pm.MetricValue) - mb.AvgValue) / mb.StdDevValue ELSE 0 END >= bt.CriticalSeverityThreshold THEN 'Critical'
            WHEN CASE WHEN mb.StdDevValue > 0 THEN ABS(AVG(pm.MetricValue) - mb.AvgValue) / mb.StdDevValue ELSE 0 END >= bt.HighSeverityThreshold THEN 'High'
            WHEN CASE WHEN mb.StdDevValue > 0 THEN ABS(AVG(pm.MetricValue) - mb.AvgValue) / mb.StdDevValue ELSE 0 END >= bt.MediumSeverityThreshold THEN 'Medium'
            ELSE 'Low'
        END AS Severity,
        -- Determine anomaly type
        CASE
            WHEN AVG(pm.MetricValue) > mb.AvgValue + (mb.StdDevValue * 2) AND bt.DetectSpikes = 1 THEN 'Spike'
            WHEN AVG(pm.MetricValue) < mb.AvgValue - (mb.StdDevValue * 2) AND bt.DetectDrops = 1 THEN 'Drop'
            ELSE 'Outlier'
        END AS AnomalyType,
        @BaselinePeriod AS BaselinePeriod,
        mb.BaselineID
    FROM dbo.PerformanceMetrics pm
    INNER JOIN dbo.MetricBaselines mb
        ON pm.ServerID = mb.ServerID
        AND pm.MetricCategory = mb.MetricCategory
        AND pm.MetricName = mb.MetricName
        AND mb.BaselinePeriod = @BaselinePeriod
        AND mb.BaselineDate = CAST(GETUTCDATE() AS DATE)
    INNER JOIN dbo.BaselineThresholds bt
        ON pm.MetricCategory = bt.MetricCategory
        AND (bt.MetricName IS NULL OR bt.MetricName = pm.MetricName)
        AND bt.IsEnabled = 1
    WHERE pm.CollectionTime >= DATEADD(MINUTE, -15, GETUTCDATE())
      AND (@ServerID IS NULL OR pm.ServerID = @ServerID)
      AND mb.StdDevValue > 0 -- Must have valid standard deviation
      AND mb.SampleCount >= bt.MinSampleCount -- Sufficient samples
    GROUP BY
        pm.ServerID,
        pm.MetricCategory,
        pm.MetricName,
        mb.AvgValue,
        mb.StdDevValue,
        mb.BaselineID,
        bt.LowSeverityThreshold,
        bt.MediumSeverityThreshold,
        bt.HighSeverityThreshold,
        bt.CriticalSeverityThreshold,
        bt.DetectSpikes,
        bt.DetectDrops
    HAVING
        -- Only insert if deviation exceeds Low threshold
        CASE
            WHEN mb.StdDevValue > 0 THEN ABS(AVG(pm.MetricValue) - mb.AvgValue) / mb.StdDevValue
            ELSE 0
        END >= bt.LowSeverityThreshold
        -- And not already detected in last hour
        AND NOT EXISTS (
            SELECT 1
            FROM dbo.AnomalyDetections ad
            WHERE ad.ServerID = pm.ServerID
              AND ad.MetricCategory = pm.MetricCategory
              AND ad.MetricName = pm.MetricName
              AND ad.DetectionTime >= DATEADD(HOUR, -1, GETUTCDATE())
              AND ad.IsResolved = 0
        );

    SET @AnomaliesDetected = @@ROWCOUNT;

    -- Automatically resolve anomalies that have returned to normal
    UPDATE ad
    SET IsResolved = 1,
        ResolvedAt = GETUTCDATE(),
        ResolutionNotes = 'Auto-resolved: Metric returned to normal range'
    FROM dbo.AnomalyDetections ad
    INNER JOIN dbo.MetricBaselines mb
        ON ad.ServerID = mb.ServerID
        AND ad.MetricCategory = mb.MetricCategory
        AND ad.MetricName = mb.MetricName
        AND ad.BaselinePeriod = mb.BaselinePeriod
        AND mb.BaselineDate = CAST(GETUTCDATE() AS DATE)
    WHERE ad.IsResolved = 0
      AND ad.DetectionTime < DATEADD(HOUR, -1, GETUTCDATE())
      AND EXISTS (
          SELECT 1
          FROM dbo.PerformanceMetrics pm
          WHERE pm.ServerID = ad.ServerID
            AND pm.MetricCategory = ad.MetricCategory
            AND pm.MetricName = ad.MetricName
            AND pm.CollectionTime >= DATEADD(MINUTE, -15, GETUTCDATE())
          GROUP BY pm.ServerID, pm.MetricCategory, pm.MetricName
          HAVING ABS(AVG(pm.MetricValue) - mb.AvgValue) / NULLIF(mb.StdDevValue, 0) < 2.0
      );

    PRINT 'Anomalies detected: ' + CAST(@AnomaliesDetected AS VARCHAR);
    PRINT 'Anomalies auto-resolved: ' + CAST(@@ROWCOUNT AS VARCHAR);
    PRINT '';

END;
GO

PRINT '✅ Created: dbo.usp_DetectAnomalies';
PRINT '';

-- =====================================================
-- Stored Procedure: Get Baseline Comparison
-- =====================================================

IF OBJECT_ID('dbo.usp_GetBaselineComparison', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetBaselineComparison;
GO

CREATE PROCEDURE dbo.usp_GetBaselineComparison
    @ServerID INT,
    @MetricCategory VARCHAR(50),
    @MetricName VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    -- Get current value (last 15 minutes average)
    DECLARE @CurrentValue DECIMAL(18,4);

    SELECT @CurrentValue = AVG(MetricValue)
    FROM dbo.PerformanceMetrics
    WHERE ServerID = @ServerID
      AND MetricCategory = @MetricCategory
      AND MetricName = @MetricName
      AND CollectionTime >= DATEADD(MINUTE, -15, GETUTCDATE());

    -- Return comparison across all baseline periods
    SELECT
        @ServerID AS ServerID,
        @MetricCategory AS MetricCategory,
        @MetricName AS MetricName,
        @CurrentValue AS CurrentValue,
        mb.BaselinePeriod,
        mb.AvgValue AS BaselineAvg,
        mb.MinValue AS BaselineMin,
        mb.MaxValue AS BaselineMax,
        mb.StdDevValue AS BaselineStdDev,
        mb.P95Value AS BaselineP95,
        mb.P99Value AS BaselineP99,
        -- Calculate deviation
        CASE
            WHEN mb.StdDevValue > 0 THEN (@CurrentValue - mb.AvgValue) / mb.StdDevValue
            ELSE 0
        END AS DeviationScore,
        -- Percent change from baseline
        CASE
            WHEN mb.AvgValue > 0 THEN ((@CurrentValue - mb.AvgValue) / mb.AvgValue) * 100
            ELSE 0
        END AS PercentChange,
        -- Status
        CASE
            WHEN @CurrentValue IS NULL THEN 'No Data'
            WHEN mb.AvgValue IS NULL THEN 'No Baseline'
            WHEN CASE WHEN mb.StdDevValue > 0 THEN ABS(@CurrentValue - mb.AvgValue) / mb.StdDevValue ELSE 0 END >= 3.0 THEN 'Abnormal'
            WHEN CASE WHEN mb.StdDevValue > 0 THEN ABS(@CurrentValue - mb.AvgValue) / mb.StdDevValue ELSE 0 END >= 2.0 THEN 'Warning'
            ELSE 'Normal'
        END AS Status,
        mb.SampleCount,
        mb.BaselineDate
    FROM dbo.MetricBaselines mb
    WHERE mb.ServerID = @ServerID
      AND mb.MetricCategory = @MetricCategory
      AND mb.MetricName = @MetricName
      AND mb.BaselineDate = CAST(GETUTCDATE() AS DATE)
    ORDER BY
        CASE mb.BaselinePeriod
            WHEN '7day' THEN 1
            WHEN '14day' THEN 2
            WHEN '30day' THEN 3
            WHEN '90day' THEN 4
        END;

END;
GO

PRINT '✅ Created: dbo.usp_GetBaselineComparison';
PRINT '';

-- =====================================================
-- Stored Procedure: Get Active Anomalies
-- =====================================================

IF OBJECT_ID('dbo.usp_GetActiveAnomalies', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetActiveAnomalies;
GO

CREATE PROCEDURE dbo.usp_GetActiveAnomalies
    @ServerID INT = NULL,
    @Severity VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        ad.AnomalyID,
        s.ServerName,
        ad.MetricCategory,
        ad.MetricName,
        ad.DetectionTime,
        ad.CurrentValue,
        ad.BaselineValue,
        ad.DeviationScore,
        ad.Severity,
        ad.AnomalyType,
        ad.BaselinePeriod,
        DATEDIFF(MINUTE, ad.DetectionTime, GETUTCDATE()) AS DurationMinutes
    FROM dbo.AnomalyDetections ad
    INNER JOIN dbo.Servers s ON ad.ServerID = s.ServerID
    WHERE ad.IsResolved = 0
      AND (@ServerID IS NULL OR ad.ServerID = @ServerID)
      AND (@Severity IS NULL OR ad.Severity = @Severity)
    ORDER BY
        CASE ad.Severity
            WHEN 'Critical' THEN 1
            WHEN 'High' THEN 2
            WHEN 'Medium' THEN 3
            WHEN 'Low' THEN 4
        END,
        ad.DetectionTime DESC;

END;
GO

PRINT '✅ Created: dbo.usp_GetActiveAnomalies';
PRINT '';

-- =====================================================
-- Summary
-- =====================================================

PRINT '======================================';
PRINT 'Baseline Procedures Created Successfully';
PRINT '======================================';
PRINT '';
PRINT 'Stored Procedures:';
PRINT '  ✅ usp_CalculateBaseline - Calculate baseline for single metric';
PRINT '  ✅ usp_UpdateAllBaselines - Calculate all baselines (all servers/metrics)';
PRINT '  ✅ usp_DetectAnomalies - Detect anomalies using baseline comparison';
PRINT '  ✅ usp_GetBaselineComparison - Compare current vs baseline values';
PRINT '  ✅ usp_GetActiveAnomalies - Retrieve active anomalies';
PRINT '';
PRINT 'Usage Examples:';
PRINT '  -- Calculate all baselines (run daily)';
PRINT '  EXEC dbo.usp_UpdateAllBaselines;';
PRINT '';
PRINT '  -- Detect anomalies (run every 15 minutes)';
PRINT '  EXEC dbo.usp_DetectAnomalies @BaselinePeriod = ''7day'';';
PRINT '';
PRINT '  -- Get baseline comparison for specific metric';
PRINT '  EXEC dbo.usp_GetBaselineComparison @ServerID = 1, @MetricCategory = ''CPU'', @MetricName = ''Percent'';';
PRINT '';
PRINT '  -- Get active anomalies';
PRINT '  EXEC dbo.usp_GetActiveAnomalies;';
PRINT '';
PRINT 'Next Steps:';
PRINT '1. Run initial baseline calculation';
PRINT '2. Create SQL Agent jobs for automation';
PRINT '3. Create Grafana dashboards';
PRINT '======================================';
PRINT '';

GO
