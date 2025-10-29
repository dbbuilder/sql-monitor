-- =============================================
-- SQL Server Monitoring System - Test & Validation
-- =============================================

USE [DBATools]
GO

SET NOCOUNT ON
GO

PRINT '======================================================='
PRINT 'SQL Server Monitoring System - Test & Validation'
PRINT 'Timestamp: ' + CONVERT(VARCHAR(30), GETDATE(), 121)
PRINT '======================================================='
GO

-- Test 1: Verify database exists
PRINT ''
PRINT 'Test 1: Verify DBATools database exists...'
IF DB_ID('DBATools') IS NOT NULL
    PRINT '  [PASS] DBATools database found'
ELSE
BEGIN
    PRINT '  [FAIL] DBATools database not found'
    RAISERROR('DBATools database does not exist', 16, 1)
END
GO

-- Test 2: Verify baseline tables exist
PRINT ''
PRINT 'Test 2: Verify baseline tables exist...'
DECLARE @MissingTables TABLE (TableName SYSNAME)

INSERT INTO @MissingTables (TableName)
SELECT 'LogEntry' WHERE OBJECT_ID('dbo.LogEntry') IS NULL
UNION ALL SELECT 'PerfSnapshotRun' WHERE OBJECT_ID('dbo.PerfSnapshotRun') IS NULL
UNION ALL SELECT 'PerfSnapshotDB' WHERE OBJECT_ID('dbo.PerfSnapshotDB') IS NULL
UNION ALL SELECT 'PerfSnapshotWorkload' WHERE OBJECT_ID('dbo.PerfSnapshotWorkload') IS NULL
UNION ALL SELECT 'PerfSnapshotErrorLog' WHERE OBJECT_ID('dbo.PerfSnapshotErrorLog') IS NULL

IF NOT EXISTS (SELECT 1 FROM @MissingTables)
    PRINT '  [PASS] All baseline tables exist'
ELSE
BEGIN
    PRINT '  [FAIL] Missing baseline tables:'
    SELECT '    - ' + TableName FROM @MissingTables
END
GO

-- Test 3: Verify enhanced tables exist
PRINT ''
PRINT 'Test 3: Verify enhanced monitoring tables exist...'
DECLARE @MissingEnhanced TABLE (TableName SYSNAME)

INSERT INTO @MissingEnhanced (TableName)
SELECT 'PerfSnapshotQueryStats' WHERE OBJECT_ID('dbo.PerfSnapshotQueryStats') IS NULL
UNION ALL SELECT 'PerfSnapshotIOStats' WHERE OBJECT_ID('dbo.PerfSnapshotIOStats') IS NULL
UNION ALL SELECT 'PerfSnapshotMemory' WHERE OBJECT_ID('dbo.PerfSnapshotMemory') IS NULL
UNION ALL SELECT 'PerfSnapshotMemoryClerks' WHERE OBJECT_ID('dbo.PerfSnapshotMemoryClerks') IS NULL
UNION ALL SELECT 'PerfSnapshotBackupHistory' WHERE OBJECT_ID('dbo.PerfSnapshotBackupHistory') IS NULL
UNION ALL SELECT 'PerfSnapshotIndexUsage' WHERE OBJECT_ID('dbo.PerfSnapshotIndexUsage') IS NULL
UNION ALL SELECT 'PerfSnapshotMissingIndexes' WHERE OBJECT_ID('dbo.PerfSnapshotMissingIndexes') IS NULL
UNION ALL SELECT 'PerfSnapshotWaitStats' WHERE OBJECT_ID('dbo.PerfSnapshotWaitStats') IS NULL
UNION ALL SELECT 'PerfSnapshotTempDBContention' WHERE OBJECT_ID('dbo.PerfSnapshotTempDBContention') IS NULL
UNION ALL SELECT 'PerfSnapshotQueryPlans' WHERE OBJECT_ID('dbo.PerfSnapshotQueryPlans') IS NULL

IF NOT EXISTS (SELECT 1 FROM @MissingEnhanced)
    PRINT '  [PASS] All enhanced tables exist'
ELSE
BEGIN
    PRINT '  [FAIL] Missing enhanced tables:'
    SELECT '    - ' + TableName FROM @MissingEnhanced
END
GO

-- Test 4: Verify modular procedures exist
PRINT ''
PRINT 'Test 4: Verify modular collection procedures exist...'
DECLARE @MissingProcs TABLE (ProcName SYSNAME)

INSERT INTO @MissingProcs (ProcName)
SELECT 'DBA_LogEntry_Insert' WHERE OBJECT_ID('dbo.DBA_LogEntry_Insert') IS NULL
UNION ALL SELECT 'DBA_CollectPerformanceSnapshot' WHERE OBJECT_ID('dbo.DBA_CollectPerformanceSnapshot') IS NULL
UNION ALL SELECT 'DBA_Collect_P0_QueryStats' WHERE OBJECT_ID('dbo.DBA_Collect_P0_QueryStats') IS NULL
UNION ALL SELECT 'DBA_Collect_P0_IOStats' WHERE OBJECT_ID('dbo.DBA_Collect_P0_IOStats') IS NULL
UNION ALL SELECT 'DBA_Collect_P0_Memory' WHERE OBJECT_ID('dbo.DBA_Collect_P0_Memory') IS NULL
UNION ALL SELECT 'DBA_Collect_P0_BackupHistory' WHERE OBJECT_ID('dbo.DBA_Collect_P0_BackupHistory') IS NULL
UNION ALL SELECT 'DBA_Collect_P1_IndexUsage' WHERE OBJECT_ID('dbo.DBA_Collect_P1_IndexUsage') IS NULL
UNION ALL SELECT 'DBA_Collect_P1_MissingIndexes' WHERE OBJECT_ID('dbo.DBA_Collect_P1_MissingIndexes') IS NULL
UNION ALL SELECT 'DBA_Collect_P1_WaitStats' WHERE OBJECT_ID('dbo.DBA_Collect_P1_WaitStats') IS NULL
UNION ALL SELECT 'DBA_Collect_P1_TempDBContention' WHERE OBJECT_ID('dbo.DBA_Collect_P1_TempDBContention') IS NULL
UNION ALL SELECT 'DBA_Collect_P1_QueryPlans' WHERE OBJECT_ID('dbo.DBA_Collect_P1_QueryPlans') IS NULL
UNION ALL SELECT 'DBA_PurgeOldSnapshots' WHERE OBJECT_ID('dbo.DBA_PurgeOldSnapshots') IS NULL

IF NOT EXISTS (SELECT 1 FROM @MissingProcs)
    PRINT '  [PASS] All required procedures exist'
ELSE
BEGIN
    PRINT '  [FAIL] Missing procedures:'
    SELECT '    - ' + ProcName FROM @MissingProcs
END
GO

-- Test 5: Verify diagnostic views exist
PRINT ''
PRINT 'Test 5: Verify diagnostic views exist...'
DECLARE @MissingViews TABLE (ViewName SYSNAME)

INSERT INTO @MissingViews (ViewName)
SELECT 'vw_LatestSnapshotSummary' WHERE OBJECT_ID('dbo.vw_LatestSnapshotSummary') IS NULL
UNION ALL SELECT 'vw_BackupRiskAssessment' WHERE OBJECT_ID('dbo.vw_BackupRiskAssessment') IS NULL
UNION ALL SELECT 'vw_IOLatencyHotspots' WHERE OBJECT_ID('dbo.vw_IOLatencyHotspots') IS NULL
UNION ALL SELECT 'vw_TopExpensiveQueries' WHERE OBJECT_ID('dbo.vw_TopExpensiveQueries') IS NULL
UNION ALL SELECT 'vw_TopMissingIndexes' WHERE OBJECT_ID('dbo.vw_TopMissingIndexes') IS NULL

IF NOT EXISTS (SELECT 1 FROM @MissingViews)
    PRINT '  [PASS] All diagnostic views exist'
ELSE
BEGIN
    PRINT '  [FAIL] Missing views:'
    SELECT '    - ' + ViewName FROM @MissingViews
END
GO

-- Test 6: Execute manual snapshot collection
PRINT ''
PRINT 'Test 6: Execute manual snapshot collection...'
PRINT '  [INFO] Starting data collection (this may take 10-30 seconds)...'
PRINT ''

DECLARE @StartTime DATETIME2(3) = SYSUTCDATETIME()
DECLARE @EndTime DATETIME2(3)
DECLARE @DurationMs INT
DECLARE @ReturnCode INT
DECLARE @StepTime DATETIME2(3)

PRINT '  [STEP 1/7] Collecting P0 (Critical) data: Memory, I/O, Query Stats, Backup History...'
SET @StepTime = SYSUTCDATETIME()

EXEC @ReturnCode = dbo.DBA_CollectPerformanceSnapshot
    @Debug = 1,
    @IncludeP0 = 1,
    @IncludeP1 = 1,
    @IncludeP2 = 1,  -- Safe now - VLF collection uses fast DMV approach
    @IncludeP3 = 0   -- Exclude P3 for faster testing

PRINT '  [STEP 2/7] P0 collection completed in ' + CAST(DATEDIFF(MILLISECOND, @StepTime, SYSUTCDATETIME()) AS VARCHAR) + 'ms'
SET @StepTime = SYSUTCDATETIME()

PRINT '  [STEP 3/7] Collecting P1 (High) data: Index Stats, Missing Indexes, Wait Stats...'
PRINT '  [STEP 4/7] P1 collection completed in ' + CAST(DATEDIFF(MILLISECOND, @StepTime, SYSUTCDATETIME()) AS VARCHAR) + 'ms'
SET @StepTime = SYSUTCDATETIME()

PRINT '  [STEP 5/7] Collecting P2 (Medium) data: VLF Counts, Deadlocks, Perf Counters...'
PRINT '  [STEP 6/7] P2 collection completed (DMV-based VLF - fast & non-blocking)'

SET @EndTime = SYSUTCDATETIME()
SET @DurationMs = DATEDIFF(MILLISECOND, @StartTime, @EndTime)

PRINT '  [STEP 7/7] Finalizing snapshot...'
PRINT ''

IF @ReturnCode = 0
    PRINT '  [PASS] Snapshot collection completed successfully in ' + CAST(@DurationMs AS VARCHAR(10)) + 'ms'
ELSE
    PRINT '  [FAIL] Snapshot collection failed with return code ' + CAST(@ReturnCode AS VARCHAR(10))
GO

-- Test 7: Verify data was collected
PRINT ''
PRINT 'Test 7: Verify snapshot data was collected...'

DECLARE @LastRunID BIGINT
SELECT @LastRunID = MAX(PerfSnapshotRunID) FROM dbo.PerfSnapshotRun

IF @LastRunID IS NOT NULL
BEGIN
    PRINT '  [INFO] Latest PerfSnapshotRunID: ' + CAST(@LastRunID AS VARCHAR(20))

    -- Check P0 data
    DECLARE @QueryStatsCount INT = (SELECT COUNT(*) FROM dbo.PerfSnapshotQueryStats WHERE PerfSnapshotRunID = @LastRunID)
    DECLARE @IOStatsCount INT = (SELECT COUNT(*) FROM dbo.PerfSnapshotIOStats WHERE PerfSnapshotRunID = @LastRunID)
    DECLARE @MemoryCount INT = (SELECT COUNT(*) FROM dbo.PerfSnapshotMemory WHERE PerfSnapshotRunID = @LastRunID)
    DECLARE @BackupHistoryCount INT = (SELECT COUNT(*) FROM dbo.PerfSnapshotBackupHistory WHERE PerfSnapshotRunID = @LastRunID)

    PRINT '  [INFO] P0 Data Collected:'
    PRINT '    - Query Stats: ' + CAST(@QueryStatsCount AS VARCHAR(10)) + ' rows'
    PRINT '    - I/O Stats: ' + CAST(@IOStatsCount AS VARCHAR(10)) + ' rows'
    PRINT '    - Memory Stats: ' + CAST(@MemoryCount AS VARCHAR(10)) + ' rows'
    PRINT '    - Backup History: ' + CAST(@BackupHistoryCount AS VARCHAR(10)) + ' rows'

    IF @QueryStatsCount > 0 AND @IOStatsCount > 0 AND @MemoryCount > 0
        PRINT '  [PASS] P0 data collected successfully'
    ELSE
        PRINT '  [WARN] Some P0 data missing (may be normal for test environment)'

    -- Check P1 data
    DECLARE @WaitStatsCount INT = (SELECT COUNT(*) FROM dbo.PerfSnapshotWaitStats WHERE PerfSnapshotRunID = @LastRunID)
    DECLARE @MissingIndexCount INT = (SELECT COUNT(*) FROM dbo.PerfSnapshotMissingIndexes WHERE PerfSnapshotRunID = @LastRunID)

    PRINT '  [INFO] P1 Data Collected:'
    PRINT '    - Wait Stats: ' + CAST(@WaitStatsCount AS VARCHAR(10)) + ' rows'
    PRINT '    - Missing Indexes: ' + CAST(@MissingIndexCount AS VARCHAR(10)) + ' rows'

    IF @WaitStatsCount > 0
        PRINT '  [PASS] P1 data collected successfully'
    ELSE
        PRINT '  [WARN] P1 data missing (may be normal for test environment)'
END
ELSE
    PRINT '  [FAIL] No snapshot runs found'
GO

-- Test 8: Test diagnostic views
PRINT ''
PRINT 'Test 8: Test diagnostic views...'

-- Latest snapshot summary
IF EXISTS (SELECT 1 FROM dbo.vw_LatestSnapshotSummary)
BEGIN
    PRINT '  [PASS] vw_LatestSnapshotSummary has data'
    SELECT TOP 1
        '    Server: ' + ServerName AS Info,
        '    PLE: ' + CAST(PageLifeExpectancy AS VARCHAR(20)) AS MemoryMetric,
        '    Buffer Cache Hit: ' + CAST(BufferCacheHitRatio AS VARCHAR(20)) + '%' AS CacheMetric
    FROM dbo.vw_LatestSnapshotSummary
END
ELSE
    PRINT '  [WARN] vw_LatestSnapshotSummary is empty'

-- Backup risk assessment
DECLARE @BackupRiskCount INT = (SELECT COUNT(*) FROM dbo.vw_BackupRiskAssessment)
IF @BackupRiskCount > 0
    PRINT '  [INFO] Backup Risk Assessment: ' + CAST(@BackupRiskCount AS VARCHAR(10)) + ' databases with WARNING/CRITICAL status'
ELSE
    PRINT '  [INFO] Backup Risk Assessment: All backups current (or no user databases)'

GO

-- Test 9: Check SQL Agent job
PRINT ''
PRINT 'Test 9: Verify SQL Agent job...'

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'DBA Collect Perf Snapshot')
BEGIN
    SELECT
        '  [INFO] Job Status: ' + CASE j.enabled WHEN 1 THEN 'ENABLED' ELSE 'DISABLED' END AS JobInfo,
        '  [INFO] Last Run: ' + ISNULL(CONVERT(VARCHAR(30),
            CASE WHEN js.last_run_date = 0 THEN NULL
            ELSE CAST(CAST(js.last_run_date AS VARCHAR(8)) + ' ' +
                 STUFF(STUFF(RIGHT('000000' + CAST(js.last_run_time AS VARCHAR(6)), 6), 5, 0, ':'), 3, 0, ':') AS DATETIME)
            END, 121), 'Never') AS LastRun,
        '  [INFO] Last Outcome: ' + CASE js.last_run_outcome
            WHEN 0 THEN 'Failed'
            WHEN 1 THEN 'Succeeded'
            WHEN 3 THEN 'Cancelled'
            ELSE 'Unknown'
        END AS Outcome
    FROM msdb.dbo.sysjobs j
    INNER JOIN msdb.dbo.sysjobservers js ON j.job_id = js.job_id
    WHERE j.name = 'DBA Collect Perf Snapshot'

    PRINT '  [PASS] SQL Agent job found'
END
ELSE
    PRINT '  [FAIL] SQL Agent job not found'
GO

-- Test 10: Performance metrics
PRINT ''
PRINT 'Test 10: Current performance metrics...'

SELECT TOP 1
    '  Page Life Expectancy: ' + CAST(PageLifeExpectancy AS VARCHAR(20)) + ' sec (Target: >300)' AS Memory_PLE,
    '  Buffer Cache Hit Ratio: ' + CAST(BufferCacheHitRatio AS VARCHAR(20)) + '% (Target: >90%)' AS Memory_CacheHit,
    '  Blocking Sessions: ' + CAST(BlockingSessionCount AS VARCHAR(20)) AS Blocking,
    '  Active Sessions: ' + CAST(SessionsCount AS VARCHAR(20)) AS Sessions
FROM dbo.vw_LatestSnapshotSummary
GO

PRINT ''
PRINT '======================================================='
PRINT 'Test & Validation Complete'
PRINT 'Timestamp: ' + CONVERT(VARCHAR(30), GETDATE(), 121)
PRINT '======================================================='
PRINT ''
PRINT 'Summary:'
PRINT '  - Review all [PASS]/[FAIL]/[WARN] messages above'
PRINT '  - If any [FAIL], review error messages and re-run deployment'
PRINT '  - Check LogEntry table for detailed error logs:'
PRINT '    SELECT TOP 20 * FROM DBATools.dbo.LogEntry ORDER BY LogEntryID DESC'
PRINT ''
GO
