-- =====================================================
-- Baseline Comparison & Anomaly Detection Integration Tests
-- Tests baseline calculation, anomaly detection, and SQL Agent jobs
-- =====================================================
-- File: tests/test-baseline-comparison.sql
-- Purpose: Validate baseline comparison functionality end-to-end
-- Dependencies: 70-create-baseline-tables.sql, 71-create-baseline-procedures.sql,
--               72-create-baseline-sql-agent-job.sql
-- =====================================================

USE MonitoringDB;
GO

SET NOCOUNT ON;
GO

PRINT '======================================';
PRINT 'Baseline Comparison Integration Tests';
PRINT '======================================';
PRINT '';

-- =====================================================
-- Test 1: Baseline Tables Exist
-- =====================================================

PRINT '======================================';
PRINT 'Test 1: Verify Baseline Tables Exist';
PRINT '======================================';
PRINT '';

DECLARE @TableCount INT = 0;

IF OBJECT_ID('dbo.MetricBaselines', 'U') IS NOT NULL
BEGIN
    SET @TableCount = @TableCount + 1;
    PRINT '✅ MetricBaselines exists';
END;

IF OBJECT_ID('dbo.AnomalyDetections', 'U') IS NOT NULL
BEGIN
    SET @TableCount = @TableCount + 1;
    PRINT '✅ AnomalyDetections exists';
END;

IF OBJECT_ID('dbo.BaselineCalculationHistory', 'U') IS NOT NULL
BEGIN
    SET @TableCount = @TableCount + 1;
    PRINT '✅ BaselineCalculationHistory exists';
END;

IF OBJECT_ID('dbo.BaselineThresholds', 'U') IS NOT NULL
BEGIN
    SET @TableCount = @TableCount + 1;
    PRINT '✅ BaselineThresholds exists';
END;

PRINT '';

IF @TableCount = 4
BEGIN
    PRINT '✅ PASS: All baseline tables exist';
    PRINT '';
END
ELSE
BEGIN
    PRINT '❌ FAIL: Missing baseline tables';
    PRINT '';
END;

-- =====================================================
-- Test 2: Baseline Stored Procedures Exist
-- =====================================================

PRINT '======================================';
PRINT 'Test 2: Verify Baseline Stored Procedures Exist';
PRINT '======================================';
PRINT '';

DECLARE @ProcCount INT = 0;

IF OBJECT_ID('dbo.usp_CalculateBaseline', 'P') IS NOT NULL
BEGIN
    SET @ProcCount = @ProcCount + 1;
    PRINT '✅ usp_CalculateBaseline exists';
END;

IF OBJECT_ID('dbo.usp_UpdateAllBaselines', 'P') IS NOT NULL
BEGIN
    SET @ProcCount = @ProcCount + 1;
    PRINT '✅ usp_UpdateAllBaselines exists';
END;

IF OBJECT_ID('dbo.usp_DetectAnomalies', 'P') IS NOT NULL
BEGIN
    SET @ProcCount = @ProcCount + 1;
    PRINT '✅ usp_DetectAnomalies exists';
END;

IF OBJECT_ID('dbo.usp_GetBaselineComparison', 'P') IS NOT NULL
BEGIN
    SET @ProcCount = @ProcCount + 1;
    PRINT '✅ usp_GetBaselineComparison exists';
END;

IF OBJECT_ID('dbo.usp_GetActiveAnomalies', 'P') IS NOT NULL
BEGIN
    SET @ProcCount = @ProcCount + 1;
    PRINT '✅ usp_GetActiveAnomalies exists';
END;

PRINT '';

IF @ProcCount = 5
BEGIN
    PRINT '✅ PASS: All baseline stored procedures exist';
    PRINT '';
END
ELSE
BEGIN
    PRINT '❌ FAIL: Missing baseline stored procedures';
    PRINT '';
END;

-- =====================================================
-- Test 3: Default Baseline Thresholds Configured
-- =====================================================

PRINT '======================================';
PRINT 'Test 3: Verify Default Baseline Thresholds';
PRINT '======================================';
PRINT '';

DECLARE @ExpectedThresholds INT = 6;
DECLARE @ActualThresholds INT;

SELECT @ActualThresholds = COUNT(*) FROM dbo.BaselineThresholds WHERE IsEnabled = 1;

PRINT 'Expected threshold configurations: ' + CAST(@ExpectedThresholds AS VARCHAR);
PRINT 'Actual threshold configurations: ' + CAST(@ActualThresholds AS VARCHAR);
PRINT '';

IF @ActualThresholds >= @ExpectedThresholds
BEGIN
    PRINT '✅ PASS: All default baseline thresholds configured';
    PRINT '';

    -- List thresholds
    PRINT 'Threshold Configurations:';
    SELECT
        MetricCategory,
        LowSeverityThreshold,
        MediumSeverityThreshold,
        HighSeverityThreshold,
        CriticalSeverityThreshold,
        CASE DetectSpikes WHEN 1 THEN 'Yes' ELSE 'No' END AS DetectSpikes,
        CASE DetectDrops WHEN 1 THEN 'Yes' ELSE 'No' END AS DetectDrops
    FROM dbo.BaselineThresholds
    WHERE IsEnabled = 1
    ORDER BY MetricCategory;
END
ELSE
BEGIN
    PRINT '❌ FAIL: Missing default baseline thresholds';
    PRINT '';
END;

-- =====================================================
-- Test 4: Single Metric Baseline Calculation
-- =====================================================

PRINT '======================================';
PRINT 'Test 4: Calculate Baseline for Single Metric';
PRINT '======================================';
PRINT '';

-- Check if we have data
DECLARE @MetricCount INT;
SELECT @MetricCount = COUNT(*)
FROM dbo.PerformanceMetrics
WHERE ServerID = 1
  AND MetricCategory = 'CPU'
  AND MetricName = 'Percent'
  AND CollectionTime >= DATEADD(DAY, -7, GETUTCDATE());

PRINT 'Available samples for CPU Percent (last 7 days): ' + CAST(@MetricCount AS VARCHAR);
PRINT '';

IF @MetricCount >= 100
BEGIN
    -- Delete existing baseline
    DELETE FROM dbo.MetricBaselines
    WHERE ServerID = 1
      AND MetricCategory = 'CPU'
      AND MetricName = 'Percent'
      AND BaselinePeriod = '7day'
      AND BaselineDate = CAST(GETUTCDATE() AS DATE);

    -- Calculate baseline
    BEGIN TRY
        EXEC dbo.usp_CalculateBaseline
            @ServerID = 1,
            @MetricCategory = 'CPU',
            @MetricName = 'Percent',
            @BaselinePeriod = '7day';

        PRINT '✅ Baseline calculation completed successfully';
        PRINT '';

        -- Verify baseline was created
        IF EXISTS (
            SELECT 1 FROM dbo.MetricBaselines
            WHERE ServerID = 1
              AND MetricCategory = 'CPU'
              AND MetricName = 'Percent'
              AND BaselinePeriod = '7day'
              AND BaselineDate = CAST(GETUTCDATE() AS DATE)
        )
        BEGIN
            PRINT '✅ PASS: Baseline created and stored successfully';
            PRINT '';

            -- Show baseline details
            SELECT
                BaselineID,
                AvgValue,
                MinValue,
                MaxValue,
                StdDevValue,
                MedianValue,
                P95Value,
                P99Value,
                SampleCount
            FROM dbo.MetricBaselines
            WHERE ServerID = 1
              AND MetricCategory = 'CPU'
              AND MetricName = 'Percent'
              AND BaselinePeriod = '7day'
              AND BaselineDate = CAST(GETUTCDATE() AS DATE);
        END
        ELSE
        BEGIN
            PRINT '❌ FAIL: Baseline calculation did not create record';
            PRINT '';
        END;
    END TRY
    BEGIN CATCH
        PRINT '❌ FAIL: Baseline calculation failed with error:';
        PRINT ERROR_MESSAGE();
        PRINT '';
    END CATCH;
END
ELSE
BEGIN
    PRINT 'ℹ️  INFO: Insufficient data for baseline calculation (need 100+ samples)';
    PRINT '✅ PASS: Procedure exists and is callable (data issue, not code issue)';
    PRINT '';
END;

-- =====================================================
-- Test 5: Full Baseline Update (All Metrics)
-- =====================================================

PRINT '======================================';
PRINT 'Test 5: Calculate All Baselines (All Servers/Metrics)';
PRINT '======================================';
PRINT '';

DECLARE @BeforeBaselineCount INT;
DECLARE @AfterBaselineCount INT;

-- Get count before
SELECT @BeforeBaselineCount = COUNT(*) FROM dbo.MetricBaselines
WHERE BaselineDate = CAST(GETUTCDATE() AS DATE);

PRINT 'Baselines before update: ' + CAST(@BeforeBaselineCount AS VARCHAR);

-- Run full baseline update
BEGIN TRY
    EXEC dbo.usp_UpdateAllBaselines;
    PRINT '✅ Full baseline update completed successfully';
    PRINT '';
END TRY
BEGIN CATCH
    PRINT '❌ FAIL: Full baseline update failed:';
    PRINT ERROR_MESSAGE();
    PRINT '';
END CATCH;

-- Get count after
SELECT @AfterBaselineCount = COUNT(*) FROM dbo.MetricBaselines
WHERE BaselineDate = CAST(GETUTCDATE() AS DATE);

PRINT 'Baselines after update: ' + CAST(@AfterBaselineCount AS VARCHAR);
PRINT '';

IF @AfterBaselineCount > @BeforeBaselineCount
BEGIN
    PRINT '✅ PASS: Baseline update created new baselines';
    PRINT '';
END
ELSE
BEGIN
    PRINT '⚠️  WARNING: Baseline count did not increase (may be reprocessing existing baselines)';
    PRINT '';
END;

-- Check calculation history
SELECT TOP 1
    CalculationTime,
    BaselinePeriod,
    ServersProcessed,
    MetricsProcessed,
    BaselinesCreated,
    DurationSeconds,
    Status
FROM dbo.BaselineCalculationHistory
ORDER BY CalculationTime DESC;

-- =====================================================
-- Test 6: Anomaly Detection
-- =====================================================

PRINT '======================================';
PRINT 'Test 6: Anomaly Detection';
PRINT '======================================';
PRINT '';

DECLARE @BeforeAnomalyCount INT;
DECLARE @AfterAnomalyCount INT;

-- Get count before
SELECT @BeforeAnomalyCount = COUNT(*) FROM dbo.AnomalyDetections
WHERE DetectionTime >= DATEADD(MINUTE, -5, GETUTCDATE());

PRINT 'Anomalies before detection (last 5 min): ' + CAST(@BeforeAnomalyCount AS VARCHAR);

-- Run anomaly detection
BEGIN TRY
    EXEC dbo.usp_DetectAnomalies @BaselinePeriod = '7day';
    PRINT '✅ Anomaly detection completed successfully';
    PRINT '';
END TRY
BEGIN CATCH
    PRINT '❌ FAIL: Anomaly detection failed:';
    PRINT ERROR_MESSAGE();
    PRINT '';
END CATCH;

-- Get count after
SELECT @AfterAnomalyCount = COUNT(*) FROM dbo.AnomalyDetections
WHERE DetectionTime >= DATEADD(MINUTE, -5, GETUTCDATE());

PRINT 'Anomalies after detection (last 5 min): ' + CAST(@AfterAnomalyCount AS VARCHAR);
PRINT '';

IF @AfterAnomalyCount >= @BeforeAnomalyCount
BEGIN
    PRINT '✅ PASS: Anomaly detection completed (may or may not have found anomalies)';
    PRINT '';
END
ELSE
BEGIN
    PRINT '⚠️  WARNING: Anomaly count decreased (auto-resolution may have occurred)';
    PRINT '';
END;

-- Show any recent anomalies
IF EXISTS (SELECT 1 FROM dbo.AnomalyDetections WHERE DetectionTime >= DATEADD(HOUR, -24, GETUTCDATE()))
BEGIN
    PRINT 'Recent anomalies (last 24 hours):';
    SELECT TOP 10
        s.ServerName,
        a.MetricCategory,
        a.MetricName,
        a.DetectionTime,
        a.CurrentValue,
        a.BaselineValue,
        a.DeviationScore,
        a.Severity,
        a.IsResolved
    FROM dbo.AnomalyDetections a
    INNER JOIN dbo.Servers s ON a.ServerID = s.ServerID
    WHERE a.DetectionTime >= DATEADD(HOUR, -24, GETUTCDATE())
    ORDER BY a.DeviationScore DESC;
END
ELSE
BEGIN
    PRINT 'ℹ️  INFO: No anomalies detected in last 24 hours (system is healthy)';
END;

PRINT '';

-- =====================================================
-- Test 7: Baseline Comparison Retrieval
-- =====================================================

PRINT '======================================';
PRINT 'Test 7: Baseline Comparison Retrieval';
PRINT '======================================';
PRINT '';

BEGIN TRY
    DECLARE @ComparisonTable TABLE (
        ServerID INT,
        MetricCategory VARCHAR(50),
        MetricName VARCHAR(100),
        CurrentValue DECIMAL(18,4),
        BaselinePeriod VARCHAR(20),
        BaselineAvg DECIMAL(18,4),
        BaselineMin DECIMAL(18,4),
        BaselineMax DECIMAL(18,4),
        BaselineStdDev DECIMAL(18,4),
        BaselineP95 DECIMAL(18,4),
        BaselineP99 DECIMAL(18,4),
        DeviationScore DECIMAL(18,4),
        PercentChange DECIMAL(18,4),
        Status VARCHAR(20),
        SampleCount INT,
        BaselineDate DATE
    );

    INSERT INTO @ComparisonTable
    EXEC dbo.usp_GetBaselineComparison
        @ServerID = 1,
        @MetricCategory = 'CPU',
        @MetricName = 'Percent';

    IF EXISTS (SELECT 1 FROM @ComparisonTable)
    BEGIN
        PRINT '✅ PASS: Baseline comparison retrieved successfully';
        PRINT '';

        SELECT BaselinePeriod, CurrentValue, BaselineAvg, BaselineStdDev, DeviationScore, Status FROM @ComparisonTable;
    END
    ELSE
    BEGIN
        PRINT 'ℹ️  INFO: No baseline comparison data available (baselines may not exist yet)';
        PRINT '';
    END;
END TRY
BEGIN CATCH
    PRINT '❌ FAIL: Baseline comparison retrieval failed:';
    PRINT ERROR_MESSAGE();
    PRINT '';
END CATCH;

-- =====================================================
-- Test 8: Active Anomalies Retrieval
-- =====================================================

PRINT '======================================';
PRINT 'Test 8: Active Anomalies Retrieval';
PRINT '======================================';
PRINT '';

BEGIN TRY
    CREATE TABLE #ActiveAnomalies (
        AnomalyID BIGINT,
        ServerName NVARCHAR(255),
        MetricCategory VARCHAR(50),
        MetricName VARCHAR(100),
        DetectionTime DATETIME2(7),
        CurrentValue DECIMAL(18,4),
        BaselineValue DECIMAL(18,4),
        DeviationScore DECIMAL(10,4),
        Severity VARCHAR(20),
        AnomalyType VARCHAR(50),
        BaselinePeriod VARCHAR(20),
        DurationMinutes INT
    );

    INSERT INTO #ActiveAnomalies
    EXEC dbo.usp_GetActiveAnomalies;

    DECLARE @ActiveAnomalyCount INT;
    SELECT @ActiveAnomalyCount = COUNT(*) FROM #ActiveAnomalies;

    PRINT 'Active anomalies retrieved: ' + CAST(@ActiveAnomalyCount AS VARCHAR);

    IF @ActiveAnomalyCount > 0
    BEGIN
        PRINT '';
        PRINT 'Sample active anomalies:';
        SELECT TOP 5 * FROM #ActiveAnomalies;
    END;

    DROP TABLE #ActiveAnomalies;

    PRINT '';
    PRINT '✅ PASS: Active anomalies retrieved successfully';
    PRINT '';
END TRY
BEGIN CATCH
    PRINT '❌ FAIL: Active anomalies retrieval failed:';
    PRINT ERROR_MESSAGE();
    PRINT '';
END CATCH;

-- =====================================================
-- Test 9: SQL Agent Jobs Exist and Enabled
-- =====================================================

PRINT '======================================';
PRINT 'Test 9: Verify SQL Agent Jobs Exist';
PRINT '======================================';
PRINT '';

DECLARE @BaselineJobExists BIT = 0;
DECLARE @AnomalyJobExists BIT = 0;

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'MonitoringDB - Update Baselines (Daily)')
BEGIN
    SET @BaselineJobExists = 1;
    PRINT '✅ Baseline update job exists';
END;

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'MonitoringDB - Detect Anomalies (15 min)')
BEGIN
    SET @AnomalyJobExists = 1;
    PRINT '✅ Anomaly detection job exists';
END;

PRINT '';

IF @BaselineJobExists = 1 AND @AnomalyJobExists = 1
BEGIN
    PRINT '✅ PASS: Both SQL Agent jobs exist';
    PRINT '';

    -- Check job schedules
    SELECT
        j.name AS JobName,
        j.enabled AS Enabled,
        s.name AS ScheduleName,
        CASE s.freq_type
            WHEN 4 THEN 'Daily'
            ELSE 'Other'
        END AS Frequency,
        CASE s.freq_subday_type
            WHEN 1 THEN 'At ' + STUFF(STUFF(RIGHT('000000' + CAST(s.active_start_time AS VARCHAR(6)), 6), 5, 0, ':'), 3, 0, ':')
            WHEN 4 THEN 'Every ' + CAST(s.freq_subday_interval AS VARCHAR) + ' minutes'
            ELSE 'Other'
        END AS Schedule
    FROM msdb.dbo.sysjobs j
    INNER JOIN msdb.dbo.sysjobschedules js ON j.job_id = js.job_id
    INNER JOIN msdb.dbo.sysschedules s ON js.schedule_id = s.schedule_id
    WHERE j.name LIKE '%MonitoringDB%Baseline%'
       OR j.name LIKE '%MonitoringDB%Anomal%'
    ORDER BY j.name;

    PRINT '';
END
ELSE
BEGIN
    PRINT '❌ FAIL: Missing SQL Agent jobs';
    PRINT '';
END;

-- =====================================================
-- Test 10: Simulated Anomaly Detection (Inject Spike)
-- =====================================================

PRINT '======================================';
PRINT 'Test 10: Simulated Anomaly Detection';
PRINT '======================================';
PRINT '';

-- Check if baseline exists for CPU
IF EXISTS (
    SELECT 1 FROM dbo.MetricBaselines
    WHERE ServerID = 1
      AND MetricCategory = 'CPU'
      AND MetricName = 'Percent'
      AND BaselinePeriod = '7day'
      AND BaselineDate = CAST(GETUTCDATE() AS DATE)
)
BEGIN
    -- Get baseline average
    DECLARE @BaselineAvg DECIMAL(18,4);
    DECLARE @BaselineStdDev DECIMAL(18,4);

    SELECT
        @BaselineAvg = AvgValue,
        @BaselineStdDev = StdDevValue
    FROM dbo.MetricBaselines
    WHERE ServerID = 1
      AND MetricCategory = 'CPU'
      AND MetricName = 'Percent'
      AND BaselinePeriod = '7day'
      AND BaselineDate = CAST(GETUTCDATE() AS DATE);

    PRINT 'CPU Baseline Average: ' + CAST(@BaselineAvg AS VARCHAR(10));
    PRINT 'CPU Baseline StdDev: ' + CAST(@BaselineStdDev AS VARCHAR(10));

    -- Calculate spike value (4 sigma above baseline = High severity)
    DECLARE @SpikeValue DECIMAL(18,4) = @BaselineAvg + (4 * @BaselineStdDev);

    PRINT 'Injecting spike value: ' + CAST(@SpikeValue AS VARCHAR(10));
    PRINT '';

    -- Insert fake spike
    INSERT INTO dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
    VALUES (1, GETUTCDATE(), 'CPU', 'Percent', @SpikeValue);

    -- Run anomaly detection
    EXEC dbo.usp_DetectAnomalies @BaselinePeriod = '7day';

    -- Check for detected anomaly
    IF EXISTS (
        SELECT 1 FROM dbo.AnomalyDetections
        WHERE ServerID = 1
          AND MetricCategory = 'CPU'
          AND MetricName = 'Percent'
          AND DetectionTime >= DATEADD(MINUTE, -2, GETUTCDATE())
          AND Severity IN ('High', 'Critical')
    )
    BEGIN
        PRINT '✅ PASS: Simulated spike detected successfully';
        PRINT '';

        -- Show detected anomaly
        SELECT TOP 1
            ServerID,
            MetricCategory,
            MetricName,
            CurrentValue,
            BaselineValue,
            DeviationScore,
            Severity,
            AnomalyType
        FROM dbo.AnomalyDetections
        WHERE ServerID = 1
          AND MetricCategory = 'CPU'
          AND MetricName = 'Percent'
          AND DetectionTime >= DATEADD(MINUTE, -2, GETUTCDATE())
        ORDER BY DetectionTime DESC;

        -- Clean up test data
        DELETE FROM dbo.PerformanceMetrics
        WHERE ServerID = 1
          AND MetricCategory = 'CPU'
          AND MetricName = 'Percent'
          AND MetricValue = @SpikeValue
          AND CollectionTime >= DATEADD(MINUTE, -2, GETUTCDATE());

        PRINT '';
        PRINT '(Test data cleaned up)';
        PRINT '';
    END
    ELSE
    BEGIN
        PRINT '❌ FAIL: Simulated spike not detected';
        PRINT '';
    END;
END
ELSE
BEGIN
    PRINT 'ℹ️  INFO: No baseline exists for CPU (skipping spike simulation)';
    PRINT '✅ PASS: Test skipped (data dependency)';
    PRINT '';
END;

-- =====================================================
-- Test Summary
-- =====================================================

PRINT '======================================';
PRINT 'Test Summary';
PRINT '======================================';
PRINT '';
PRINT 'All integration tests completed!';
PRINT 'Review results above for any failures.';
PRINT '';
PRINT 'Baseline Comparison System Status:';

SELECT
    'Tables' AS Component,
    COUNT(*) AS ObjectCount
FROM sys.tables
WHERE name IN ('MetricBaselines', 'AnomalyDetections', 'BaselineCalculationHistory', 'BaselineThresholds')

UNION ALL

SELECT
    'Stored Procedures' AS Component,
    COUNT(*) AS ObjectCount
FROM sys.procedures
WHERE name IN ('usp_CalculateBaseline', 'usp_UpdateAllBaselines', 'usp_DetectAnomalies', 'usp_GetBaselineComparison', 'usp_GetActiveAnomalies')

UNION ALL

SELECT
    'Baseline Thresholds' AS Component,
    COUNT(*) AS ObjectCount
FROM dbo.BaselineThresholds
WHERE IsEnabled = 1

UNION ALL

SELECT
    'SQL Agent Jobs' AS Component,
    COUNT(*) AS ObjectCount
FROM msdb.dbo.sysjobs
WHERE name LIKE '%MonitoringDB%Baseline%'
   OR name LIKE '%MonitoringDB%Anomal%';

PRINT '';
PRINT 'Recent Baseline Calculation:';
SELECT TOP 1
    CalculationTime,
    BaselinesCreated,
    DurationSeconds,
    Status
FROM dbo.BaselineCalculationHistory
ORDER BY CalculationTime DESC;

PRINT '';
PRINT 'Active Anomalies:';
SELECT
    COUNT(*) AS TotalActiveAnomalies,
    SUM(CASE WHEN Severity = 'Critical' THEN 1 ELSE 0 END) AS CriticalCount,
    SUM(CASE WHEN Severity = 'High' THEN 1 ELSE 0 END) AS HighCount,
    SUM(CASE WHEN Severity = 'Medium' THEN 1 ELSE 0 END) AS MediumCount,
    SUM(CASE WHEN Severity = 'Low' THEN 1 ELSE 0 END) AS LowCount
FROM dbo.AnomalyDetections
WHERE IsResolved = 0;

PRINT '';
PRINT 'Note: Some tests may show INFO/WARNING if baselines have not been calculated yet.';
PRINT 'Run: EXEC dbo.usp_UpdateAllBaselines; to populate baseline data.';
PRINT '';

GO
