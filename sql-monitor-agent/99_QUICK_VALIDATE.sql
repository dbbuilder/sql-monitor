-- =============================================
-- SQL Server Monitoring System - QUICK VALIDATION
-- Fast schema validation only (< 5 seconds)
-- Skips actual data collection test
-- =============================================

USE [DBATools]
GO

SET NOCOUNT ON
GO

PRINT '======================================================='
PRINT 'SQL Server Monitoring System - QUICK VALIDATION'
PRINT 'Timestamp: ' + CONVERT(VARCHAR(30), GETDATE(), 121)
PRINT 'This is a fast schema-only check (no data collection)'
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
UNION ALL SELECT 'PerfSnapshotWaitStats' WHERE OBJECT_ID('dbo.PerfSnapshotWaitStats') IS NULL

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
PRINT 'Test 4: Verify collection procedures exist...'
DECLARE @MissingProcs TABLE (ProcName SYSNAME)

INSERT INTO @MissingProcs (ProcName)
SELECT 'DBA_LogEntry_Insert' WHERE OBJECT_ID('dbo.DBA_LogEntry_Insert') IS NULL
UNION ALL SELECT 'DBA_CollectPerformanceSnapshot' WHERE OBJECT_ID('dbo.DBA_CollectPerformanceSnapshot') IS NULL
UNION ALL SELECT 'DBA_Collect_P0_Memory' WHERE OBJECT_ID('dbo.DBA_Collect_P0_Memory') IS NULL
UNION ALL SELECT 'DBA_Collect_P1_WaitStats' WHERE OBJECT_ID('dbo.DBA_Collect_P1_WaitStats') IS NULL
UNION ALL SELECT 'DBA_Collect_P2_VLFCounts' WHERE OBJECT_ID('dbo.DBA_Collect_P2_VLFCounts') IS NULL
UNION ALL SELECT 'DBA_PurgeOldSnapshots' WHERE OBJECT_ID('dbo.DBA_PurgeOldSnapshots') IS NULL

IF NOT EXISTS (SELECT 1 FROM @MissingProcs)
    PRINT '  [PASS] All required procedures exist'
ELSE
BEGIN
    PRINT '  [FAIL] Missing procedures:'
    SELECT '    - ' + ProcName FROM @MissingProcs
END
GO

-- Test 5: Verify VLF collector uses DMV approach
PRINT ''
PRINT 'Test 5: Verify VLF collector uses fast DMV approach...'
DECLARE @VLFProcDef NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID('dbo.DBA_Collect_P2_VLFCounts'))

IF @VLFProcDef LIKE '%sys.dm_db_log_info%'
    PRINT '  [PASS] VLF collector uses sys.dm_db_log_info() (fast, non-blocking)'
ELSE IF @VLFProcDef LIKE '%DBCC LOGINFO%'
    PRINT '  [WARN] VLF collector still uses DBCC LOGINFO (slow, may block)'
ELSE
    PRINT '  [WARN] Cannot determine VLF collection method'
GO

-- Test 6: Verify functions exist
PRINT ''
PRINT 'Test 6: Verify configuration functions exist...'
DECLARE @MissingFuncs TABLE (FuncName SYSNAME)

INSERT INTO @MissingFuncs (FuncName)
SELECT 'fn_GetConfigValue' WHERE OBJECT_ID('dbo.fn_GetConfigValue') IS NULL
UNION ALL SELECT 'fn_GetConfigInt' WHERE OBJECT_ID('dbo.fn_GetConfigInt') IS NULL
UNION ALL SELECT 'fn_ConvertToReportingTime' WHERE OBJECT_ID('dbo.fn_ConvertToReportingTime') IS NULL

IF NOT EXISTS (SELECT 1 FROM @MissingFuncs)
    PRINT '  [PASS] All configuration functions exist'
ELSE
BEGIN
    PRINT '  [FAIL] Missing functions:'
    SELECT '    - ' + FuncName FROM @MissingFuncs
END
GO

-- Test 7: Verify config table populated
PRINT ''
PRINT 'Test 7: Verify configuration table populated...'
DECLARE @ConfigCount INT = (SELECT COUNT(*) FROM dbo.MonitoringConfig)

IF @ConfigCount >= 28
    PRINT '  [PASS] Configuration table has ' + CAST(@ConfigCount AS VARCHAR) + ' settings'
ELSE IF @ConfigCount > 0
    PRINT '  [WARN] Configuration table has only ' + CAST(@ConfigCount AS VARCHAR) + ' settings (expected 28)'
ELSE
    PRINT '  [FAIL] Configuration table is empty'
GO

-- Test 8: Check SQL Agent job (if exists)
PRINT ''
PRINT 'Test 8: Check SQL Agent job...'

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'DBA Collect Perf Snapshot')
BEGIN
    DECLARE @JobEnabled BIT
    SELECT @JobEnabled = enabled FROM msdb.dbo.sysjobs WHERE name = 'DBA Collect Perf Snapshot'

    IF @JobEnabled = 1
        PRINT '  [PASS] SQL Agent job exists and is ENABLED'
    ELSE
        PRINT '  [WARN] SQL Agent job exists but is DISABLED'
END
ELSE
    PRINT '  [INFO] SQL Agent job not found (optional - can be created later)'
GO

-- Test 9: Count all objects
PRINT ''
PRINT 'Test 9: Object count summary...'
DECLARE @TableCount INT = (SELECT COUNT(*) FROM sys.tables WHERE schema_id = SCHEMA_ID('dbo'))
DECLARE @ProcCount INT = (SELECT COUNT(*) FROM sys.procedures WHERE schema_id = SCHEMA_ID('dbo') AND name LIKE 'DBA_%')
DECLARE @FuncCount INT = (SELECT COUNT(*) FROM sys.objects WHERE type IN ('FN', 'IF', 'TF') AND schema_id = SCHEMA_ID('dbo'))
DECLARE @ViewCount INT = (SELECT COUNT(*) FROM sys.views WHERE schema_id = SCHEMA_ID('dbo'))

PRINT '  [INFO] Tables created: ' + CAST(@TableCount AS VARCHAR)
PRINT '  [INFO] Procedures created: ' + CAST(@ProcCount AS VARCHAR)
PRINT '  [INFO] Functions created: ' + CAST(@FuncCount AS VARCHAR)
PRINT '  [INFO] Views created: ' + CAST(@ViewCount AS VARCHAR)

IF @TableCount >= 24 AND @ProcCount >= 20 AND @FuncCount >= 5
    PRINT '  [PASS] Object counts look good'
ELSE
    PRINT '  [WARN] Object counts lower than expected'
GO

PRINT ''
PRINT '======================================================='
PRINT 'QUICK VALIDATION COMPLETE'
PRINT 'Timestamp: ' + CONVERT(VARCHAR(30), GETDATE(), 121)
PRINT '======================================================='
PRINT ''
PRINT 'Summary:'
PRINT '  - Schema validation: Complete'
PRINT '  - Data collection test: SKIPPED (run manually to test)'
PRINT ''
PRINT 'To test data collection manually:'
PRINT '  EXEC DBATools.dbo.DBA_CollectPerformanceSnapshot @Debug = 1'
PRINT ''
PRINT 'To view system health:'
PRINT '  EXEC DBATools.dbo.DBA_CheckSystemHealth'
PRINT ''
GO
