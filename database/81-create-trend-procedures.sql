-- =====================================================
-- Phase 3 - Feature #5: Predictive Analytics
-- Stored Procedures for Trend Calculation (Linear Regression)
-- =====================================================
-- File: 81-create-trend-procedures.sql
-- Purpose: Calculate trends using linear regression (least squares method)
-- Dependencies: 80-create-predictive-analytics-tables.sql
-- =====================================================

USE MonitoringDB;
GO

SET NOCOUNT ON;
GO

PRINT '======================================';
PRINT 'Creating Trend Calculation Procedures';
PRINT '======================================';
PRINT '';

-- =====================================================
-- Stored Procedure: Calculate Trend for Single Metric
-- =====================================================

IF OBJECT_ID('dbo.usp_CalculateTrend', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CalculateTrend;
GO

CREATE PROCEDURE dbo.usp_CalculateTrend
    @ServerID INT,
    @MetricCategory VARCHAR(50),
    @MetricName VARCHAR(100),
    @TrendPeriod VARCHAR(20) -- '7day', '14day', '30day', '90day'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @DaysBack INT;
    DECLARE @TrendDate DATE = CAST(GETUTCDATE() AS DATE);
    DECLARE @StartTime DATETIME2(7);
    DECLARE @EndTime DATETIME2(7) = GETUTCDATE();

    -- Determine lookback period
    SET @DaysBack = CASE @TrendPeriod
        WHEN '7day' THEN 7
        WHEN '14day' THEN 14
        WHEN '30day' THEN 30
        WHEN '90day' THEN 90
        ELSE 7
    END;

    SET @StartTime = DATEADD(DAY, -@DaysBack, @EndTime);

    -- Collect metric data with day numbers (X values)
    ;WITH MetricData AS (
        SELECT
            MetricValue AS Y,
            DATEDIFF(DAY, @StartTime, CollectionTime) AS X, -- Days since start
            CollectionTime
        FROM dbo.PerformanceMetrics
        WHERE ServerID = @ServerID
          AND MetricCategory = @MetricCategory
          AND MetricName = @MetricName
          AND CollectionTime >= @StartTime
          AND CollectionTime < @EndTime
    ),
    -- Calculate sums for linear regression
    Sums AS (
        SELECT
            COUNT(*) AS N,
            SUM(X) AS SumX,
            SUM(Y) AS SumY,
            SUM(X * Y) AS SumXY,
            SUM(X * X) AS SumX2,
            SUM(Y * Y) AS SumY2,
            AVG(Y) AS AvgY,
            MIN(Y) AS MinY,
            MAX(Y) AS MaxY,
            STDEV(Y) AS StdDevY
        FROM MetricData
    ),
    -- Get first and last values
    FirstLast AS (
        SELECT
            MIN(CASE WHEN RowNum = 1 THEN Y END) AS FirstValue,
            MIN(CASE WHEN RowNum = MaxRow THEN Y END) AS LastValue
        FROM (
            SELECT
                Y,
                ROW_NUMBER() OVER (ORDER BY X) AS RowNum,
                COUNT(*) OVER () AS MaxRow
            FROM MetricData
        ) numbered
    )
    -- Calculate linear regression parameters
    INSERT INTO dbo.MetricTrends (
        ServerID,
        MetricCategory,
        MetricName,
        TrendPeriod,
        CalculationDate,
        Slope,
        Intercept,
        RSquared,
        TrendDirection,
        GrowthPercentPerDay,
        GrowthAbsolutePerDay,
        SampleCount,
        StartValue,
        EndValue,
        AverageValue,
        StandardDeviation,
        MinValue,
        MaxValue
    )
    SELECT
        @ServerID,
        @MetricCategory,
        @MetricName,
        @TrendPeriod,
        @TrendDate,

        -- Slope: m = (n*Σ(xy) - Σx*Σy) / (n*Σ(x²) - (Σx)²)
        CASE
            WHEN s.N * s.SumX2 - s.SumX * s.SumX = 0 THEN 0
            ELSE (s.N * s.SumXY - s.SumX * s.SumY) / (s.N * s.SumX2 - s.SumX * s.SumX)
        END AS Slope,

        -- Intercept: b = (Σy - m*Σx) / n
        CASE
            WHEN s.N * s.SumX2 - s.SumX * s.SumX = 0 THEN s.AvgY
            ELSE (s.SumY - ((s.N * s.SumXY - s.SumX * s.SumY) / (s.N * s.SumX2 - s.SumX * s.SumX)) * s.SumX) / s.N
        END AS Intercept,

        -- R²: coefficient of determination (0-1, higher = better fit)
        CASE
            WHEN s.SumY2 - (s.SumY * s.SumY / s.N) = 0 THEN NULL
            ELSE 1 - (
                (s.SumY2 -
                 ((s.N * s.SumXY - s.SumX * s.SumY) / (s.N * s.SumX2 - s.SumX * s.SumX)) * s.SumXY -
                 ((s.SumY - ((s.N * s.SumXY - s.SumX * s.SumY) / (s.N * s.SumX2 - s.SumX * s.SumX)) * s.SumX) / s.N) * s.SumY)
                / (s.SumY2 - (s.SumY * s.SumY / s.N))
            )
        END AS RSquared,

        -- Trend direction
        CASE
            WHEN s.N * s.SumX2 - s.SumX * s.SumX = 0 THEN 'Stable'
            WHEN ABS((s.N * s.SumXY - s.SumX * s.SumY) / (s.N * s.SumX2 - s.SumX * s.SumX)) < 0.01 THEN 'Stable'
            WHEN (s.N * s.SumXY - s.SumX * s.SumY) / (s.N * s.SumX2 - s.SumX * s.SumX) > 0 THEN 'Increasing'
            ELSE 'Decreasing'
        END AS TrendDirection,

        -- Growth percent per day
        CASE
            WHEN s.AvgY = 0 OR s.N * s.SumX2 - s.SumX * s.SumX = 0 THEN 0
            ELSE (((s.N * s.SumXY - s.SumX * s.SumY) / (s.N * s.SumX2 - s.SumX * s.SumX)) / s.AvgY) * 100
        END AS GrowthPercentPerDay,

        -- Growth absolute per day (slope)
        CASE
            WHEN s.N * s.SumX2 - s.SumX * s.SumX = 0 THEN 0
            ELSE (s.N * s.SumXY - s.SumX * s.SumY) / (s.N * s.SumX2 - s.SumX * s.SumX)
        END AS GrowthAbsolutePerDay,

        s.N AS SampleCount,
        fl.FirstValue AS StartValue,
        fl.LastValue AS EndValue,
        s.AvgY AS AverageValue,
        s.StdDevY AS StandardDeviation,
        s.MinY AS MinValue,
        s.MaxY AS MaxValue
    FROM Sums s
    CROSS JOIN FirstLast fl
    WHERE s.N >= 10; -- Minimum sample size for meaningful regression

    -- Return trend summary
    SELECT
        TrendID,
        ServerID,
        MetricCategory,
        MetricName,
        TrendPeriod,
        Slope,
        Intercept,
        RSquared,
        TrendDirection,
        GrowthAbsolutePerDay,
        SampleCount
    FROM dbo.MetricTrends
    WHERE ServerID = @ServerID
      AND MetricCategory = @MetricCategory
      AND MetricName = @MetricName
      AND TrendPeriod = @TrendPeriod
      AND CalculationDate = @TrendDate;
END;
GO

PRINT '✅ Created: dbo.usp_CalculateTrend';
PRINT '';

-- =====================================================
-- Stored Procedure: Update All Trends
-- =====================================================

IF OBJECT_ID('dbo.usp_UpdateAllTrends', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_UpdateAllTrends;
GO

CREATE PROCEDURE dbo.usp_UpdateAllTrends
    @TrendPeriod VARCHAR(20) = NULL -- NULL = all periods
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartTime DATETIME2(7) = GETUTCDATE();
    DECLARE @TrendDate DATE = CAST(@StartTime AS DATE);
    DECLARE @ServersProcessed INT = 0;
    DECLARE @MetricsProcessed INT = 0;
    DECLARE @TrendsCalculated INT = 0;
    DECLARE @ErrorCount INT = 0;

    PRINT 'Starting trend calculation for period: ' + ISNULL(@TrendPeriod, 'ALL');
    PRINT '';

    -- Delete old trends for today (recalculation)
    DELETE FROM dbo.MetricTrends
    WHERE CalculationDate = @TrendDate
      AND (@TrendPeriod IS NULL OR TrendPeriod = @TrendPeriod);

    PRINT 'Deleted existing trends for today';
    PRINT '';

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
        PRINT 'Processing server: ' + @ServerName;

        BEGIN TRY
            -- Get distinct metrics for this server (from recent data)
            DECLARE @MetricCategory VARCHAR(50);
            DECLARE @MetricName VARCHAR(100);

            DECLARE metric_cursor CURSOR LOCAL FAST_FORWARD FOR
                SELECT DISTINCT MetricCategory, MetricName
                FROM dbo.PerformanceMetrics
                WHERE ServerID = @ServerID
                  AND CollectionTime >= DATEADD(DAY, -90, GETUTCDATE())
                ORDER BY MetricCategory, MetricName;

            OPEN metric_cursor;
            FETCH NEXT FROM metric_cursor INTO @MetricCategory, @MetricName;

            WHILE @@FETCH_STATUS = 0
            BEGIN
                BEGIN TRY
                    SET @MetricsProcessed = @MetricsProcessed + 1;

                    -- Calculate trend for each period (or specified period)
                    IF @TrendPeriod IS NULL OR @TrendPeriod = '7day'
                    BEGIN
                        EXEC dbo.usp_CalculateTrend @ServerID, @MetricCategory, @MetricName, '7day';
                        SET @TrendsCalculated = @TrendsCalculated + @@ROWCOUNT;
                    END;

                    IF @TrendPeriod IS NULL OR @TrendPeriod = '14day'
                    BEGIN
                        EXEC dbo.usp_CalculateTrend @ServerID, @MetricCategory, @MetricName, '14day';
                        SET @TrendsCalculated = @TrendsCalculated + @@ROWCOUNT;
                    END;

                    IF @TrendPeriod IS NULL OR @TrendPeriod = '30day'
                    BEGIN
                        EXEC dbo.usp_CalculateTrend @ServerID, @MetricCategory, @MetricName, '30day';
                        SET @TrendsCalculated = @TrendsCalculated + @@ROWCOUNT;
                    END;

                    IF @TrendPeriod IS NULL OR @TrendPeriod = '90day'
                    BEGIN
                        EXEC dbo.usp_CalculateTrend @ServerID, @MetricCategory, @MetricName, '90day';
                        SET @TrendsCalculated = @TrendsCalculated + @@ROWCOUNT;
                    END;
                END TRY
                BEGIN CATCH
                    PRINT '  Error calculating trend for ' + @MetricCategory + '.' + @MetricName + ': ' + ERROR_MESSAGE();
                    SET @ErrorCount = @ErrorCount + 1;
                END CATCH;

                FETCH NEXT FROM metric_cursor INTO @MetricCategory, @MetricName;
            END;

            CLOSE metric_cursor;
            DEALLOCATE metric_cursor;

            SET @ServersProcessed = @ServersProcessed + 1;
            PRINT '  ✅ Completed server: ' + @ServerName;
        END TRY
        BEGIN CATCH
            PRINT '  Error processing server ' + @ServerName + ': ' + ERROR_MESSAGE();
            SET @ErrorCount = @ErrorCount + 1;

            IF CURSOR_STATUS('local', 'metric_cursor') >= 0
            BEGIN
                CLOSE metric_cursor;
                DEALLOCATE metric_cursor;
            END;
        END CATCH;

        FETCH NEXT FROM server_cursor INTO @ServerID, @ServerName;
    END;

    CLOSE server_cursor;
    DEALLOCATE server_cursor;

    DECLARE @DurationSeconds INT = DATEDIFF(SECOND, @StartTime, GETUTCDATE());

    -- Log execution
    INSERT INTO dbo.TrendCalculationHistory (
        CalculationType,
        TrendPeriod,
        ServersProcessed,
        MetricsProcessed,
        TrendsCalculated,
        ForecastsGenerated,
        AlertsRaised,
        DurationSeconds,
        Status,
        ErrorMessage
    )
    VALUES (
        'Trends',
        @TrendPeriod,
        @ServersProcessed,
        @MetricsProcessed,
        @TrendsCalculated,
        0,
        0,
        @DurationSeconds,
        CASE WHEN @ErrorCount = 0 THEN 'Success' ELSE 'Partial' END,
        CASE WHEN @ErrorCount > 0 THEN CAST(@ErrorCount AS VARCHAR) + ' errors occurred' ELSE NULL END
    );

    PRINT '';
    PRINT '======================================';
    PRINT 'Trend Calculation Summary';
    PRINT '======================================';
    PRINT 'Servers processed: ' + CAST(@ServersProcessed AS VARCHAR);
    PRINT 'Metrics processed: ' + CAST(@MetricsProcessed AS VARCHAR);
    PRINT 'Trends calculated: ' + CAST(@TrendsCalculated AS VARCHAR);
    PRINT 'Errors: ' + CAST(@ErrorCount AS VARCHAR);
    PRINT 'Duration: ' + CAST(@DurationSeconds AS VARCHAR) + ' seconds';
    PRINT '======================================';
END;
GO

PRINT '✅ Created: dbo.usp_UpdateAllTrends';
PRINT '';

-- =====================================================
-- Stored Procedure: Get Trend Summary for Server
-- =====================================================

IF OBJECT_ID('dbo.usp_GetTrendSummary', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetTrendSummary;
GO

CREATE PROCEDURE dbo.usp_GetTrendSummary
    @ServerID INT,
    @TrendPeriod VARCHAR(20) = '30day',
    @MinConfidence DECIMAL(10,2) = 0.7 -- Minimum R² for reliable trends
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        MetricCategory,
        MetricName,
        TrendDirection,
        Slope AS DailyGrowthRate,
        GrowthPercentPerDay,
        RSquared AS Confidence,
        SampleCount,
        StartValue,
        EndValue,
        AverageValue,
        CalculationDate
    FROM dbo.MetricTrends
    WHERE ServerID = @ServerID
      AND TrendPeriod = @TrendPeriod
      AND CalculationDate = (
          SELECT MAX(CalculationDate)
          FROM dbo.MetricTrends
          WHERE ServerID = @ServerID
            AND TrendPeriod = @TrendPeriod
      )
      AND (RSquared IS NULL OR RSquared >= @MinConfidence)
    ORDER BY
        CASE TrendDirection
            WHEN 'Increasing' THEN 1
            WHEN 'Decreasing' THEN 2
            WHEN 'Stable' THEN 3
        END,
        ABS(Slope) DESC;
END;
GO

PRINT '✅ Created: dbo.usp_GetTrendSummary';
PRINT '';

-- =====================================================
-- Summary and Verification
-- =====================================================

PRINT '======================================';
PRINT 'Trend Calculation Procedures Created';
PRINT '======================================';
PRINT '';

PRINT 'Stored Procedures:';
PRINT '  ✅ usp_CalculateTrend - Calculate trend for single metric (linear regression)';
PRINT '  ✅ usp_UpdateAllTrends - Calculate all trends (all servers/metrics)';
PRINT '  ✅ usp_GetTrendSummary - Retrieve trend summary for server';
PRINT '';

PRINT 'Usage Examples:';
PRINT '';
PRINT '  -- Calculate trend for specific metric';
PRINT '  EXEC dbo.usp_CalculateTrend @ServerID = 1, @MetricCategory = ''Disk'', @MetricName = ''UsedSpaceGB'', @TrendPeriod = ''30day'';';
PRINT '';
PRINT '  -- Calculate all trends (run daily at 2:00 AM)';
PRINT '  EXEC dbo.usp_UpdateAllTrends;';
PRINT '';
PRINT '  -- Get trend summary for server';
PRINT '  EXEC dbo.usp_GetTrendSummary @ServerID = 1, @TrendPeriod = ''30day'', @MinConfidence = 0.7;';
PRINT '';

PRINT 'Next Steps:';
PRINT '  1. Run initial trend calculation';
PRINT '  2. Create capacity forecasting procedures (82-create-forecasting-procedures.sql)';
PRINT '  3. Create SQL Agent jobs for automation';
PRINT '======================================';
PRINT '';

GO
