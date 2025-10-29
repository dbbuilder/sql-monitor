USE [DBATools]
GO

SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Reporting and Monitoring Procedures
-- =============================================

-- =============================================
-- 1. Check System Health
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_CheckSystemHealth
AS
BEGIN
    SET NOCOUNT ON

    PRINT '=========================================='
    PRINT 'SQL Server Monitoring System - Health Check'
    PRINT '=========================================='
    PRINT ''

    -- Check if collection is running
    DECLARE @LatestSnapshot DATETIME2(3)
    DECLARE @MinutesAgo INT
    DECLARE @SnapshotCount INT

    SELECT TOP 1
        @LatestSnapshot = SnapshotUTC,
        @MinutesAgo = DATEDIFF(MINUTE, SnapshotUTC, SYSUTCDATETIME())
    FROM dbo.PerfSnapshotRun
    ORDER BY PerfSnapshotRunID DESC

    SELECT @SnapshotCount = COUNT(*) FROM dbo.PerfSnapshotRun

    PRINT '1. Collection Status:'
    PRINT '   Total Snapshots: ' + ISNULL(CAST(@SnapshotCount AS VARCHAR(20)), '0')

    IF @LatestSnapshot IS NULL
    BEGIN
        PRINT '   Status: NOT RUNNING - No snapshots collected yet'
        PRINT '   Action: Run EXEC DBA_CollectPerformanceSnapshot @Debug = 1'
    END
    ELSE IF @MinutesAgo <= 10
    BEGIN
        PRINT '   Status: RUNNING - Latest snapshot ' + CAST(@MinutesAgo AS VARCHAR(10)) + ' minutes ago'
        PRINT '   Latest: ' + CONVERT(VARCHAR(30), dbo.fn_ConvertToReportingTime(@LatestSnapshot), 120)
    END
    ELSE IF @MinutesAgo <= 30
    BEGIN
        PRINT '   Status: WARNING - Latest snapshot ' + CAST(@MinutesAgo AS VARCHAR(10)) + ' minutes ago'
        PRINT '   Latest: ' + CONVERT(VARCHAR(30), dbo.fn_ConvertToReportingTime(@LatestSnapshot), 120)
        PRINT '   Action: Check SQL Agent job is running'
    END
    ELSE
    BEGIN
        PRINT '   Status: STOPPED - Latest snapshot ' + CAST(@MinutesAgo AS VARCHAR(10)) + ' minutes ago'
        PRINT '   Latest: ' + CONVERT(VARCHAR(30), dbo.fn_ConvertToReportingTime(@LatestSnapshot), 120)
        PRINT '   Action: Check SQL Agent job and LogEntry for errors'
    END

    PRINT ''

    -- Check SQL Agent job
    IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'DBA Collect Perf Snapshot')
    BEGIN
        DECLARE @JobEnabled BIT
        DECLARE @LastRunDate INT
        DECLARE @LastRunTime INT
        DECLARE @LastRunOutcome INT

        SELECT TOP 1
            @JobEnabled = j.enabled,
            @LastRunDate = js.last_run_date,
            @LastRunTime = js.last_run_time,
            @LastRunOutcome = js.last_run_outcome
        FROM msdb.dbo.sysjobs j
        LEFT JOIN msdb.dbo.sysjobservers js ON j.job_id = js.job_id
        WHERE j.name = 'DBA Collect Perf Snapshot'

        PRINT '2. SQL Agent Job:'
        PRINT '   Enabled: ' + CASE WHEN @JobEnabled = 1 THEN 'YES' ELSE 'NO - ENABLE IT!' END

        IF @LastRunDate IS NOT NULL
        BEGIN
            DECLARE @LastRun DATETIME = CAST(
                CAST(@LastRunDate AS VARCHAR(8)) + ' ' +
                STUFF(STUFF(RIGHT('000000' + CAST(@LastRunTime AS VARCHAR(6)), 6), 5, 0, ':'), 3, 0, ':')
                AS DATETIME)

            PRINT '   Last Run: ' + CONVERT(VARCHAR(30), @LastRun, 120)
            PRINT '   Outcome: ' + CASE @LastRunOutcome
                WHEN 0 THEN 'Failed'
                WHEN 1 THEN 'Succeeded'
                WHEN 3 THEN 'Cancelled'
                ELSE 'Unknown'
            END
        END
        ELSE
        BEGIN
            PRINT '   Last Run: Never'
        END
    END
    ELSE
    BEGIN
        PRINT '2. SQL Agent Job: NOT FOUND'
        PRINT '   Action: Run 04_create_agent_job_FIXED.sql'
    END

    PRINT ''

    -- Check for errors
    DECLARE @ErrorCount INT
    SELECT @ErrorCount = COUNT(*)
    FROM dbo.LogEntry
    WHERE IsError = 1
      AND DateTime_Occurred >= DATEADD(HOUR, -24, SYSUTCDATETIME())

    PRINT '3. Recent Errors (Last 24 hours):'
    PRINT '   Error Count: ' + CAST(@ErrorCount AS VARCHAR(20))

    IF @ErrorCount > 0
    BEGIN
        PRINT ''
        PRINT '   Recent Errors:'
        SELECT TOP 5
            CONVERT(VARCHAR(20), dbo.fn_ConvertToReportingTime(DateTime_Occurred), 120) AS ErrorTime,
            ProcedureName,
            ProcedureSection,
            LEFT(ErrDescription, 80) AS Error
        FROM dbo.LogEntry
        WHERE IsError = 1
        ORDER BY LogEntryID DESC
    END

    PRINT ''

    -- Data collection counts
    PRINT '4. Data Collection Summary:'

    SELECT
        'PerfSnapshotRun' AS TableName,
        CAST(COUNT(*) AS VARCHAR(20)) AS RowCnt,
        CONVERT(VARCHAR(20), dbo.fn_ConvertToReportingTime(MIN(SnapshotUTC)), 120) AS OldestSnapshot,
        CONVERT(VARCHAR(20), dbo.fn_ConvertToReportingTime(MAX(SnapshotUTC)), 120) AS NewestSnapshot
    FROM dbo.PerfSnapshotRun
    UNION ALL
    SELECT 'QueryStats', CAST(COUNT(*) AS VARCHAR(20)), '', '' FROM dbo.PerfSnapshotQueryStats
    UNION ALL
    SELECT 'IOStats', CAST(COUNT(*) AS VARCHAR(20)), '', '' FROM dbo.PerfSnapshotIOStats
    UNION ALL
    SELECT 'Memory', CAST(COUNT(*) AS VARCHAR(20)), '', '' FROM dbo.PerfSnapshotMemory
    UNION ALL
    SELECT 'BackupHistory', CAST(COUNT(*) AS VARCHAR(20)), '', '' FROM dbo.PerfSnapshotBackupHistory
    UNION ALL
    SELECT 'IndexUsage', CAST(COUNT(*) AS VARCHAR(20)), '', '' FROM dbo.PerfSnapshotIndexUsage
    UNION ALL
    SELECT 'WaitStats', CAST(COUNT(*) AS VARCHAR(20)), '', '' FROM dbo.PerfSnapshotWaitStats

    PRINT ''
    PRINT '=========================================='
    PRINT 'Health Check Complete'
    PRINT '=========================================='
END
GO

-- =============================================
-- 2. Show Latest Snapshot
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_ShowLatestSnapshot
AS
BEGIN
    SET NOCOUNT ON

    PRINT '=========================================='
    PRINT 'Latest Performance Snapshot'
    PRINT '=========================================='
    PRINT ''

    SELECT TOP 1
        PerfSnapshotRunID,
        dbo.fn_ConvertToReportingTime(SnapshotUTC) AS SnapshotTime_ET,
        ServerName,
        CpuSignalWaitPct,
        TopWaitType,
        TopWaitMsPerSec,
        SessionsCount,
        RequestsCount,
        BlockingSessionCount,
        DeadlockCountRecent,
        MemoryGrantWarningCount
    FROM dbo.PerfSnapshotRun
    ORDER BY PerfSnapshotRunID DESC
END
GO

-- =============================================
-- 3. Show Top Queries
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_ShowTopQueries
    @TopN INT = 10
AS
BEGIN
    SET NOCOUNT ON

    SELECT TOP (@TopN)
        dbo.fn_ConvertToReportingTime(r.SnapshotUTC) AS SnapshotTime_ET,
        qs.DatabaseName,
        qs.AvgCpuMs,
        qs.AvgElapsedMs,
        qs.AvgLogicalReads,
        qs.ExecutionCount,
        LEFT(qs.SqlText, 100) AS SqlText
    FROM dbo.PerfSnapshotQueryStats qs
    INNER JOIN dbo.PerfSnapshotRun r ON qs.PerfSnapshotRunID = r.PerfSnapshotRunID
    ORDER BY qs.AvgCpuMs DESC
END
GO

-- =============================================
-- 4. Show Backup Status
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_ShowBackupStatus
AS
BEGIN
    SET NOCOUNT ON

    SELECT
        DatabaseName,
        RecoveryModel,
        dbo.fn_ConvertToReportingTime(LastFullBackupDate) AS LastFullBackup_ET,
        HoursSinceFullBackup,
        dbo.fn_ConvertToReportingTime(LastLogBackupDate) AS LastLogBackup_ET,
        MinutesSinceLogBackup,
        BackupRiskLevel
    FROM dbo.PerfSnapshotBackupHistory
    WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM dbo.PerfSnapshotRun)
    ORDER BY HoursSinceFullBackup DESC
END
GO

-- =============================================
-- 5. Show Wait Statistics
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_ShowWaitStats
    @TopN INT = 10
AS
BEGIN
    SET NOCOUNT ON

    SELECT TOP (@TopN)
        dbo.fn_ConvertToReportingTime(r.SnapshotUTC) AS SnapshotTime_ET,
        ws.WaitType,
        ws.WaitTimeMs,
        ws.WaitingTasksCount,
        ws.AvgWaitTimeMs
    FROM dbo.PerfSnapshotWaitStats ws
    INNER JOIN dbo.PerfSnapshotRun r ON ws.PerfSnapshotRunID = r.PerfSnapshotRunID
    WHERE r.PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM dbo.PerfSnapshotRun)
    ORDER BY ws.WaitTimeMs DESC
END
GO

-- =============================================
-- 6. Show I/O Statistics
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_ShowIOStats
AS
BEGIN
    SET NOCOUNT ON

    SELECT
        DatabaseName,
        FileType,
        AvgReadLatencyMs,
        AvgWriteLatencyMs,
        BytesRead / 1024.0 / 1024.0 AS TotalReadsMB,
        BytesWritten / 1024.0 / 1024.0 AS TotalWritesMB,
        CASE
            WHEN AvgReadLatencyMs > 50 OR AvgWriteLatencyMs > 50 THEN 'SLOW'
            WHEN AvgReadLatencyMs > 20 OR AvgWriteLatencyMs > 20 THEN 'WARNING'
            ELSE 'OK'
        END AS Status
    FROM dbo.PerfSnapshotIOStats
    WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM dbo.PerfSnapshotRun)
    ORDER BY AvgReadLatencyMs + AvgWriteLatencyMs DESC
END
GO

-- =============================================
-- 7. Show Memory Usage
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_ShowMemoryUsage
AS
BEGIN
    SET NOCOUNT ON

    SELECT
        PageLifeExpectancy,
        BufferCacheHitRatio,
        TotalServerMemoryMB,
        TargetServerMemoryMB,
        FreeMemoryMB,
        BufferPoolSizeMB,
        MemoryGrantsPending,
        MemoryGrantsOutstanding
    FROM dbo.PerfSnapshotMemory
    WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM dbo.PerfSnapshotRun)
END
GO

-- =============================================
-- 8. Show Collection History
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_ShowCollectionHistory
    @Hours INT = 24
AS
BEGIN
    SET NOCOUNT ON

    SELECT
        dbo.fn_ConvertToReportingTime(SnapshotUTC) AS SnapshotTime_ET,
        ServerName,
        CpuSignalWaitPct,
        SessionsCount,
        RequestsCount,
        BlockingSessionCount
    FROM dbo.PerfSnapshotRun
    WHERE SnapshotUTC >= DATEADD(HOUR, -@Hours, SYSUTCDATETIME())
    ORDER BY PerfSnapshotRunID DESC
END
GO

-- =============================================
-- 9. Show Missing Indexes
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_ShowMissingIndexes
    @TopN INT = 10
AS
BEGIN
    SET NOCOUNT ON

    SELECT TOP (@TopN)
        DatabaseName,
        ObjectName,
        EqualityColumns,
        InequalityColumns,
        IncludedColumns,
        UserSeeks,
        UserScans,
        AvgTotalUserCost,
        AvgUserImpact,
        ImpactScore
    FROM dbo.PerfSnapshotMissingIndexes
    WHERE PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM dbo.PerfSnapshotRun)
    ORDER BY ImpactScore DESC
END
GO

-- =============================================
-- 10. Test Collection
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_TestCollection
AS
BEGIN
    SET NOCOUNT ON

    PRINT '=========================================='
    PRINT 'Running Test Collection...'
    PRINT '=========================================='
    PRINT ''

    DECLARE @StartTime DATETIME2(3) = SYSUTCDATETIME()
    DECLARE @RunID BIGINT

    -- Get count before
    DECLARE @CountBefore INT = (SELECT COUNT(*) FROM dbo.PerfSnapshotRun)

    -- Run collection
    EXEC dbo.DBA_CollectPerformanceSnapshot @Debug = 1

    -- Get count after
    DECLARE @CountAfter INT = (SELECT COUNT(*) FROM dbo.PerfSnapshotRun)
    DECLARE @ElapsedMs INT = DATEDIFF(MILLISECOND, @StartTime, SYSUTCDATETIME())

    PRINT ''
    PRINT '=========================================='
    PRINT 'Test Results:'
    PRINT '=========================================='
    PRINT '  Snapshots Before: ' + CAST(@CountBefore AS VARCHAR(20))
    PRINT '  Snapshots After:  ' + CAST(@CountAfter AS VARCHAR(20))
    PRINT '  New Snapshots:    ' + CAST(@CountAfter - @CountBefore AS VARCHAR(20))
    PRINT '  Elapsed Time:     ' + CAST(@ElapsedMs AS VARCHAR(20)) + ' ms'

    IF @CountAfter > @CountBefore
    BEGIN
        PRINT '  Status: SUCCESS - Collection is working!'

        -- Show latest snapshot
        PRINT ''
        EXEC dbo.DBA_ShowLatestSnapshot
    END
    ELSE
    BEGIN
        PRINT '  Status: FAILED - No new snapshots created'
        PRINT ''
        PRINT 'Check for errors:'
        SELECT TOP 5
            dbo.fn_ConvertToReportingTime(DateTime_Occurred) AS ErrorTime,
            ProcedureName,
            ErrDescription
        FROM dbo.LogEntry
        WHERE IsError = 1
        ORDER BY LogEntryID DESC
    END
END
GO

-- =============================================
-- 11. Run All Reports
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_Monitor_RunAll
    @TopN INT = 10,
    @Hours INT = 24
AS
BEGIN
    SET NOCOUNT ON

    PRINT '=============================================================='
    PRINT 'SQL SERVER MONITORING - COMPREHENSIVE REPORT'
    PRINT '=============================================================='
    PRINT ''

    -- 1. System Health
    PRINT '=============================================================='
    PRINT '1. SYSTEM HEALTH CHECK'
    PRINT '=============================================================='
    EXEC dbo.DBA_CheckSystemHealth

    PRINT ''
    PRINT ''

    -- 2. Latest Snapshot
    PRINT '=============================================================='
    PRINT '2. LATEST SNAPSHOT'
    PRINT '=============================================================='
    EXEC dbo.DBA_ShowLatestSnapshot

    PRINT ''
    PRINT ''

    -- 3. Backup Status
    PRINT '=============================================================='
    PRINT '3. BACKUP STATUS'
    PRINT '=============================================================='
    EXEC dbo.DBA_ShowBackupStatus

    PRINT ''
    PRINT ''

    -- 4. Top Queries
    PRINT '=============================================================='
    PRINT '4. TOP EXPENSIVE QUERIES'
    PRINT '=============================================================='
    EXEC dbo.DBA_ShowTopQueries @TopN

    PRINT ''
    PRINT ''

    -- 5. Wait Statistics
    PRINT '=============================================================='
    PRINT '5. WAIT STATISTICS'
    PRINT '=============================================================='
    EXEC dbo.DBA_ShowWaitStats @TopN

    PRINT ''
    PRINT ''

    -- 6. I/O Statistics
    PRINT '=============================================================='
    PRINT '6. I/O STATISTICS'
    PRINT '=============================================================='
    EXEC dbo.DBA_ShowIOStats

    PRINT ''
    PRINT ''

    -- 7. Memory Usage
    PRINT '=============================================================='
    PRINT '7. MEMORY USAGE'
    PRINT '=============================================================='
    EXEC dbo.DBA_ShowMemoryUsage

    PRINT ''
    PRINT ''

    -- 8. Missing Indexes
    PRINT '=============================================================='
    PRINT '8. MISSING INDEX RECOMMENDATIONS'
    PRINT '=============================================================='
    EXEC dbo.DBA_ShowMissingIndexes @TopN

    PRINT ''
    PRINT ''

    -- 9. Collection History
    PRINT '=============================================================='
    PRINT '9. COLLECTION HISTORY (Last ' + CAST(@Hours AS VARCHAR(10)) + ' hours)'
    PRINT '=============================================================='
    EXEC dbo.DBA_ShowCollectionHistory @Hours

    PRINT ''
    PRINT ''
    PRINT '=============================================================='
    PRINT 'COMPREHENSIVE REPORT COMPLETE'
    PRINT '=============================================================='
    PRINT ''
    PRINT 'Report Parameters:'
    PRINT '  TopN: ' + CAST(@TopN AS VARCHAR(10))
    PRINT '  Hours: ' + CAST(@Hours AS VARCHAR(10))
    PRINT ''
END
GO

PRINT ''
PRINT '=========================================='
PRINT 'Reporting Procedures Created Successfully'
PRINT '=========================================='
PRINT ''
PRINT 'Quick Commands:'
PRINT ''
PRINT '  -- Run ALL reports at once (START HERE!)'
PRINT '  EXEC DBA_Monitor_RunAll'
PRINT '  EXEC DBA_Monitor_RunAll @TopN = 20, @Hours = 48'
PRINT ''
PRINT '  -- Check if monitoring is working'
PRINT '  EXEC DBA_CheckSystemHealth'
PRINT ''
PRINT '  -- Test collection manually'
PRINT '  EXEC DBA_TestCollection'
PRINT ''
PRINT '  -- Show latest snapshot'
PRINT '  EXEC DBA_ShowLatestSnapshot'
PRINT ''
PRINT '  -- Show top queries'
PRINT '  EXEC DBA_ShowTopQueries @TopN = 10'
PRINT ''
PRINT '  -- Show backup status'
PRINT '  EXEC DBA_ShowBackupStatus'
PRINT ''
PRINT '  -- Show wait statistics'
PRINT '  EXEC DBA_ShowWaitStats @TopN = 10'
PRINT ''
PRINT '  -- Show I/O statistics'
PRINT '  EXEC DBA_ShowIOStats'
PRINT ''
PRINT '  -- Show memory usage'
PRINT '  EXEC DBA_ShowMemoryUsage'
PRINT ''
PRINT '  -- Show collection history'
PRINT '  EXEC DBA_ShowCollectionHistory @Hours = 24'
PRINT ''
PRINT '  -- Show missing indexes'
PRINT '  EXEC DBA_ShowMissingIndexes @TopN = 10'
PRINT ''
GO
