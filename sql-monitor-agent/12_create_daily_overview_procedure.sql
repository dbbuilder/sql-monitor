-- =============================================
-- File: 12_create_daily_overview_procedure.sql
-- Purpose: Create comprehensive daily health overview procedure
-- Created: 2025-10-27
-- =============================================

USE DBATools
GO

PRINT 'Creating DBA_DailyHealthOverview procedure...'
GO

CREATE OR ALTER PROCEDURE dbo.DBA_DailyHealthOverview
    @TopSlowQueries INT = 10,
    @TopMissingIndexes INT = 10,
    @HoursBackForIssues INT = 24
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @ServerName SYSNAME = CAST(SERVERPROPERTY('ServerName') AS SYSNAME)
    DECLARE @ReportTime DATETIME2(3) = SYSUTCDATETIME()
    DECLARE @TotalSnapshots INT
    DECLARE @OldestSnapshot DATETIME2(3)
    DECLARE @NewestSnapshot DATETIME2(3)

    -- Get snapshot statistics
    SELECT
        @TotalSnapshots = COUNT(*),
        @OldestSnapshot = MIN(SnapshotUTC),
        @NewestSnapshot = MAX(SnapshotUTC)
    FROM dbo.PerfSnapshotRun

    -- =============================================
    -- RESULT SET 1: Report Header
    -- =============================================
    SELECT
        'DAILY HEALTH OVERVIEW REPORT' AS ReportTitle,
        @ServerName AS ServerName,
        @ReportTime AS ReportGeneratedUTC,
        @TotalSnapshots AS TotalSnapshotsCollected,
        @OldestSnapshot AS OldestSnapshotUTC,
        @NewestSnapshot AS NewestSnapshotUTC,
        DATEDIFF(DAY, @OldestSnapshot, @NewestSnapshot) AS DaysOfData,
        CASE
            WHEN @TotalSnapshots = 0 THEN 'NO DATA - Check if collections are running'
            WHEN DATEDIFF(MINUTE, @NewestSnapshot, @ReportTime) > 10 THEN 'STALE DATA - Collections may have stopped'
            ELSE 'DATA CURRENT'
        END AS DataStatus

    -- =============================================
    -- RESULT SET 2: Current System Health
    -- =============================================
    SELECT
        'CURRENT SYSTEM HEALTH' AS Section,
        r.PerfSnapshotRunID,
        r.SnapshotUTC,
        r.ServerName,
        r.CpuSignalWaitPct,
        r.TopWaitType,
        r.TopWaitMsPerSec,
        r.SessionsCount,
        r.RequestsCount,
        r.BlockingSessionCount,
        r.DeadlockCountRecent,
        r.MemoryGrantWarningCount,
        CASE
            WHEN r.CpuSignalWaitPct > 40 THEN 'CRITICAL - CPU Pressure'
            WHEN r.BlockingSessionCount > 20 THEN 'WARNING - High Blocking'
            WHEN r.DeadlockCountRecent > 5 THEN 'WARNING - Deadlocks Detected'
            WHEN r.CpuSignalWaitPct > 20 THEN 'ATTENTION - Elevated CPU'
            ELSE 'HEALTHY'
        END AS HealthStatus,
        DATEDIFF(MINUTE, r.SnapshotUTC, SYSUTCDATETIME()) AS MinutesSinceSnapshot
    FROM dbo.PerfSnapshotRun r
    WHERE r.PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM dbo.PerfSnapshotRun)

    -- =============================================
    -- RESULT SET 3: Issues Found in Last 24 Hours
    -- =============================================
    SELECT
        'ISSUES LAST ' + CAST(@HoursBackForIssues AS VARCHAR(10)) + ' HOURS' AS Section,
        SnapshotUTC,
        CpuSignalWaitPct,
        BlockingSessionCount,
        DeadlockCountRecent,
        TopWaitType,
        TopWaitMsPerSec,
        CASE
            WHEN CpuSignalWaitPct > 40 THEN 'HIGH CPU'
            WHEN BlockingSessionCount > 20 THEN 'HIGH BLOCKING'
            WHEN DeadlockCountRecent > 0 THEN 'DEADLOCKS'
            ELSE 'OTHER'
        END AS IssueType,
        DATEDIFF(MINUTE, SnapshotUTC, SYSUTCDATETIME()) AS MinutesAgo
    FROM dbo.PerfSnapshotRun
    WHERE SnapshotUTC >= DATEADD(HOUR, -@HoursBackForIssues, SYSUTCDATETIME())
      AND (CpuSignalWaitPct > 20
           OR BlockingSessionCount > 10
           OR DeadlockCountRecent > 0)
    ORDER BY SnapshotUTC DESC

    -- =============================================
    -- RESULT SET 4: 24-Hour Summary Statistics
    -- =============================================
    SELECT
        '24-HOUR SUMMARY STATISTICS' AS Section,
        COUNT(*) AS TotalSnapshots,
        CAST(AVG(CpuSignalWaitPct) AS DECIMAL(5,2)) AS AvgCpuSignalWaitPct,
        CAST(MAX(CpuSignalWaitPct) AS DECIMAL(5,2)) AS MaxCpuSignalWaitPct,
        CAST(AVG(CAST(BlockingSessionCount AS FLOAT)) AS DECIMAL(10,2)) AS AvgBlockingSessions,
        MAX(BlockingSessionCount) AS MaxBlockingSessions,
        SUM(DeadlockCountRecent) AS TotalDeadlocks,
        MAX(SessionsCount) AS PeakSessions,
        MAX(RequestsCount) AS PeakRequests,
        COUNT(CASE WHEN CpuSignalWaitPct > 40 THEN 1 END) AS HighCpuSnapshots,
        COUNT(CASE WHEN BlockingSessionCount > 20 THEN 1 END) AS HighBlockingSnapshots,
        COUNT(CASE WHEN DeadlockCountRecent > 0 THEN 1 END) AS DeadlockSnapshots
    FROM dbo.PerfSnapshotRun
    WHERE SnapshotUTC >= DATEADD(HOUR, -24, SYSUTCDATETIME())

    -- =============================================
    -- RESULT SET 5: Top Slow Queries (Recent)
    -- =============================================
    SELECT TOP (@TopSlowQueries)
        'TOP ' + CAST(@TopSlowQueries AS VARCHAR(10)) + ' SLOWEST QUERIES (RECENT)' AS Section,
        qs.DatabaseName,
        LEFT(qs.SqlText, 150) AS SqlTextPreview,
        qs.ExecutionCount,
        CAST(qs.AvgElapsedMs AS DECIMAL(15,2)) AS AvgElapsedMs,
        CAST(qs.AvgCpuMs AS DECIMAL(15,2)) AS AvgCpuMs,
        CAST(qs.AvgLogicalReads AS DECIMAL(15,2)) AS AvgLogicalReads,
        CAST((qs.ExecutionCount * qs.AvgElapsedMs) AS DECIMAL(20,2)) AS ImpactScore,
        r.SnapshotUTC AS CapturedAt,
        qs.QueryHash
    FROM dbo.PerfSnapshotQueryStats qs
    INNER JOIN dbo.PerfSnapshotRun r ON qs.PerfSnapshotRunID = r.PerfSnapshotRunID
    WHERE r.SnapshotUTC >= DATEADD(HOUR, -24, SYSUTCDATETIME())
    ORDER BY qs.AvgElapsedMs DESC

    -- =============================================
    -- RESULT SET 6: Top CPU Queries (Recent)
    -- =============================================
    SELECT TOP (@TopSlowQueries)
        'TOP ' + CAST(@TopSlowQueries AS VARCHAR(10)) + ' CPU QUERIES (RECENT)' AS Section,
        qs.DatabaseName,
        LEFT(qs.SqlText, 150) AS SqlTextPreview,
        qs.ExecutionCount,
        CAST(qs.AvgCpuMs AS DECIMAL(15,2)) AS AvgCpuMs,
        CAST(qs.TotalCpuMs AS DECIMAL(15,2)) AS TotalCpuMs,
        CAST((qs.ExecutionCount * qs.AvgCpuMs) AS DECIMAL(20,2)) AS CpuImpactScore,
        r.SnapshotUTC AS CapturedAt
    FROM dbo.PerfSnapshotQueryStats qs
    INNER JOIN dbo.PerfSnapshotRun r ON qs.PerfSnapshotRunID = r.PerfSnapshotRunID
    WHERE r.SnapshotUTC >= DATEADD(HOUR, -24, SYSUTCDATETIME())
    ORDER BY qs.TotalCpuMs DESC

    -- =============================================
    -- RESULT SET 7: Top Missing Indexes
    -- =============================================
    ;WITH LatestIndexes AS
    (
        SELECT
            mi.DatabaseName,
            mi.ObjectName,
            mi.EqualityColumns,
            mi.InequalityColumns,
            mi.IncludedColumns,
            mi.UserSeeks,
            mi.UserScans,
            mi.AvgTotalUserCost,
            mi.AvgUserImpact,
            mi.ImpactScore,
            r.SnapshotUTC,
            ROW_NUMBER() OVER (PARTITION BY mi.DatabaseName, mi.ObjectName,
                              mi.EqualityColumns, mi.InequalityColumns
                              ORDER BY r.SnapshotUTC DESC) AS RowNum
        FROM dbo.PerfSnapshotMissingIndexes mi
        INNER JOIN dbo.PerfSnapshotRun r ON mi.PerfSnapshotRunID = r.PerfSnapshotRunID
        WHERE mi.ImpactScore >= 1000
    )
    SELECT TOP (@TopMissingIndexes)
        'TOP ' + CAST(@TopMissingIndexes AS VARCHAR(10)) + ' MISSING INDEXES' AS Section,
        DatabaseName,
        ObjectName,
        EqualityColumns,
        InequalityColumns,
        IncludedColumns,
        UserSeeks,
        UserScans,
        CAST(AvgTotalUserCost AS DECIMAL(10,2)) AS AvgCost,
        CAST(AvgUserImpact AS DECIMAL(10,2)) AS AvgImpact,
        CAST(ImpactScore AS DECIMAL(15,0)) AS ImpactScore,
        SnapshotUTC AS LastObserved,
        -- Generate CREATE INDEX statement
        'CREATE NONCLUSTERED INDEX [IX_' +
            REPLACE(REPLACE(ObjectName, '[', ''), ']', '') + '_' +
            CAST(CHECKSUM(EqualityColumns, InequalityColumns) AS VARCHAR(20)) +
            '] ON ' + ObjectName +
            ' (' + ISNULL(EqualityColumns, '') +
            CASE WHEN EqualityColumns IS NOT NULL AND InequalityColumns IS NOT NULL THEN ', ' ELSE '' END +
            ISNULL(InequalityColumns, '') + ')' +
            CASE WHEN IncludedColumns IS NOT NULL
                 THEN ' INCLUDE (' + IncludedColumns + ')'
                 ELSE ''
            END AS CreateIndexStatement
    FROM LatestIndexes
    WHERE RowNum = 1
    ORDER BY ImpactScore DESC

    -- =============================================
    -- RESULT SET 8: Top Wait Types (Last 24 Hours)
    -- =============================================
    SELECT TOP 10
        'TOP 10 WAIT TYPES (LAST 24 HOURS)' AS Section,
        ws.WaitType,
        SUM(ws.WaitTimeMs) AS TotalWaitTimeMs,
        SUM(ws.WaitingTasksCount) AS TotalWaitingTasks,
        COUNT(DISTINCT ws.PerfSnapshotRunID) AS ObservationCount,
        CAST(SUM(ws.WaitTimeMs) * 100.0 /
             SUM(SUM(ws.WaitTimeMs)) OVER () AS DECIMAL(5,2)) AS PctOfTotalWaits,
        -- Common wait type descriptions
        CASE
            WHEN ws.WaitType LIKE 'PAGEIOLATCH%' THEN 'Disk I/O - Check storage performance'
            WHEN ws.WaitType LIKE 'LCK_M%' THEN 'Lock contention - Review blocking queries'
            WHEN ws.WaitType LIKE 'CXPACKET%' THEN 'Parallelism - Consider MAXDOP tuning'
            WHEN ws.WaitType LIKE 'SOS_SCHEDULER_YIELD%' THEN 'CPU pressure - High workload'
            WHEN ws.WaitType LIKE 'ASYNC_NETWORK_IO%' THEN 'Network - Slow client or large results'
            WHEN ws.WaitType LIKE 'WRITELOG%' THEN 'Log writes - Check log disk performance'
            ELSE 'See SQL Server documentation'
        END AS WaitTypeDescription
    FROM dbo.PerfSnapshotWaitStats ws
    INNER JOIN dbo.PerfSnapshotRun r ON ws.PerfSnapshotRunID = r.PerfSnapshotRunID
    WHERE r.SnapshotUTC >= DATEADD(HOUR, -24, SYSUTCDATETIME())
    GROUP BY ws.WaitType
    ORDER BY SUM(ws.WaitTimeMs) DESC

    -- =============================================
    -- RESULT SET 9: Database Size Summary
    -- =============================================
    SELECT
        'DATABASE SIZE SUMMARY (LATEST)' AS Section,
        db.DatabaseName,
        CAST(db.TotalDataMB + db.TotalLogMB AS DECIMAL(15,2)) AS TotalSizeMB,
        CAST(db.TotalDataMB AS DECIMAL(15,2)) AS DataFileSizeMB,
        CAST(db.TotalLogMB AS DECIMAL(15,2)) AS LogFileSizeMB,
        db.FileCount,
        db.StateDesc AS State,
        db.RecoveryModelDesc AS RecoveryModel,
        db.LogReuseWaitDesc,
        r.SnapshotUTC AS AsOfDate
    FROM dbo.PerfSnapshotDB db
    INNER JOIN dbo.PerfSnapshotRun r ON db.PerfSnapshotRunID = r.PerfSnapshotRunID
    WHERE r.PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM dbo.PerfSnapshotRun)
    ORDER BY (db.TotalDataMB + db.TotalLogMB) DESC

    -- =============================================
    -- RESULT SET 10: Recent Errors (If Any)
    -- =============================================
    IF EXISTS (SELECT 1 FROM dbo.LogEntry WHERE IsError = 1 AND DateTime_Occurred >= DATEADD(HOUR, -24, GETDATE()))
    BEGIN
        SELECT TOP 20
            'RECENT ERRORS (LAST 24 HOURS)' AS Section,
            DateTime_Occurred,
            ProcedureName,
            ProcedureSection,
            ErrNumber,
            LEFT(ErrDescription, 200) AS ErrorDescription,
            DATEDIFF(MINUTE, DateTime_Occurred, GETDATE()) AS MinutesAgo
        FROM dbo.LogEntry
        WHERE IsError = 1
          AND DateTime_Occurred >= DATEADD(HOUR, -24, GETDATE())
        ORDER BY LogEntryID DESC
    END
    ELSE
    BEGIN
        SELECT
            'RECENT ERRORS (LAST 24 HOURS)' AS Section,
            'No errors found in the last 24 hours' AS Status,
            GETDATE() AS CheckedAt
    END

    -- =============================================
    -- RESULT SET 11: Collection Job Status
    -- =============================================
    IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'DBA Collect Perf Snapshot')
    BEGIN
        SELECT
            'COLLECTION JOB STATUS' AS Section,
            j.name AS JobName,
            j.enabled AS IsEnabled,
            CASE js.last_run_outcome
                WHEN 0 THEN 'Failed'
                WHEN 1 THEN 'Succeeded'
                WHEN 3 THEN 'Canceled'
                WHEN 5 THEN 'Unknown'
                ELSE 'Other'
            END AS LastRunStatus,
            js.last_run_date AS LastRunDate,
            js.last_run_time AS LastRunTime
        FROM msdb.dbo.sysjobs j
        INNER JOIN msdb.dbo.sysjobservers js ON j.job_id = js.job_id
        WHERE j.name LIKE 'DBA%'
    END

    -- =============================================
    -- RESULT SET 12: Action Items / Recommendations
    -- =============================================
    DECLARE @Recommendations TABLE (
        Priority VARCHAR(10),
        ActionItem VARCHAR(500),
        Details VARCHAR(1000)
    )

    -- Check for high CPU
    IF EXISTS (SELECT 1 FROM dbo.PerfSnapshotRun WHERE CpuSignalWaitPct > 40
               AND SnapshotUTC >= DATEADD(HOUR, -24, SYSUTCDATETIME()))
    BEGIN
        INSERT INTO @Recommendations VALUES (
            'HIGH',
            'Investigate High CPU Usage',
            'CPU signal wait percentage exceeded 40% in the last 24 hours. Review top CPU queries and consider optimization.'
        )
    END

    -- Check for blocking
    IF EXISTS (SELECT 1 FROM dbo.PerfSnapshotRun WHERE BlockingSessionCount > 20
               AND SnapshotUTC >= DATEADD(HOUR, -24, SYSUTCDATETIME()))
    BEGIN
        INSERT INTO @Recommendations VALUES (
            'HIGH',
            'Investigate Blocking Sessions',
            'More than 20 blocking sessions detected in the last 24 hours. Review blocking queries and transaction patterns.'
        )
    END

    -- Check for deadlocks
    IF EXISTS (SELECT 1 FROM dbo.PerfSnapshotRun WHERE DeadlockCountRecent > 0
               AND SnapshotUTC >= DATEADD(HOUR, -24, SYSUTCDATETIME()))
    BEGIN
        INSERT INTO @Recommendations VALUES (
            'MEDIUM',
            'Review Deadlock Graphs',
            'Deadlocks detected in the last 24 hours. Check SQL Server error log for deadlock graphs (trace flags 1222/1204 auto-enabled).'
        )
    END

    -- Check for high-impact missing indexes
    IF EXISTS (SELECT 1 FROM dbo.PerfSnapshotMissingIndexes WHERE ImpactScore > 10000000)
    BEGIN
        INSERT INTO @Recommendations VALUES (
            'MEDIUM',
            'Consider Creating Missing Indexes',
            'High-impact missing indexes detected (score > 10 million). Review CREATE INDEX statements in result set #7.'
        )
    END

    -- Check for slow queries
    IF EXISTS (SELECT 1 FROM dbo.PerfSnapshotQueryStats
               WHERE AvgElapsedMs > 10000
               AND PerfSnapshotRunID IN (
                   SELECT PerfSnapshotRunID FROM dbo.PerfSnapshotRun
                   WHERE SnapshotUTC >= DATEADD(HOUR, -24, SYSUTCDATETIME())
               ))
    BEGIN
        INSERT INTO @Recommendations VALUES (
            'MEDIUM',
            'Optimize Slow Queries',
            'Queries with average elapsed time > 10 seconds detected. Review result set #5 for optimization opportunities.'
        )
    END

    -- Check data age
    IF DATEDIFF(MINUTE, @NewestSnapshot, @ReportTime) > 10
    BEGIN
        INSERT INTO @Recommendations VALUES (
            'CRITICAL',
            'Check Collection Job',
            'Data appears stale (last snapshot > 10 minutes old). Verify collection job is running.'
        )
    END

    -- If no issues, add positive message
    IF NOT EXISTS (SELECT 1 FROM @Recommendations)
    BEGIN
        INSERT INTO @Recommendations VALUES (
            'INFO',
            'System Healthy',
            'No critical issues detected. Continue normal monitoring.'
        )
    END

    SELECT
        'ACTION ITEMS & RECOMMENDATIONS' AS Section,
        Priority,
        ActionItem,
        Details
    FROM @Recommendations
    ORDER BY
        CASE Priority
            WHEN 'CRITICAL' THEN 1
            WHEN 'HIGH' THEN 2
            WHEN 'MEDIUM' THEN 3
            WHEN 'LOW' THEN 4
            ELSE 5
        END,
        ActionItem

    PRINT ''
    PRINT '=========================================='
    PRINT 'Daily Health Overview Report Completed'
    PRINT '=========================================='
    PRINT 'Total Result Sets: 12'
    PRINT '  1. Report Header'
    PRINT '  2. Current System Health'
    PRINT '  3. Issues Found (Last 24 Hours)'
    PRINT '  4. Summary Statistics'
    PRINT '  5. Top Slow Queries'
    PRINT '  6. Top CPU Queries'
    PRINT '  7. Top Missing Indexes'
    PRINT '  8. Top Wait Types'
    PRINT '  9. Database Sizes'
    PRINT ' 10. Recent Errors'
    PRINT ' 11. Collection Job Status'
    PRINT ' 12. Action Items & Recommendations'
    PRINT ''
END
GO

PRINT ''
PRINT '=========================================='
PRINT 'DBA_DailyHealthOverview Created Successfully'
PRINT '=========================================='
PRINT ''
PRINT 'USAGE:'
PRINT '  -- Run with defaults (10 queries, 10 indexes, 24 hours)'
PRINT '  EXEC DBA_DailyHealthOverview'
PRINT ''
PRINT '  -- Customize result counts'
PRINT '  EXEC DBA_DailyHealthOverview'
PRINT '    @TopSlowQueries = 20,'
PRINT '    @TopMissingIndexes = 15,'
PRINT '    @HoursBackForIssues = 48'
PRINT ''
PRINT 'RETURNS: 12 result sets with comprehensive health overview'
PRINT ''
GO
