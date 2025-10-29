-- =============================================
-- File: 14_enhance_daily_overview_with_feedback.sql
-- Purpose: Enhance DBA_DailyHealthOverview with feedback system
-- Created: 2025-10-27
-- =============================================

USE DBATools
GO

PRINT 'Enhancing DBA_DailyHealthOverview with feedback system...'
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
    DECLARE @DaysOfData INT = DATEDIFF(DAY, @OldestSnapshot, @NewestSnapshot)

    SELECT
        'DAILY HEALTH OVERVIEW REPORT' AS ReportTitle,
        @ServerName AS ServerName,
        @ReportTime AS ReportGeneratedUTC,
        @TotalSnapshots AS TotalSnapshotsCollected,
        @OldestSnapshot AS OldestSnapshotUTC,
        @NewestSnapshot AS NewestSnapshotUTC,
        @DaysOfData AS DaysOfData,
        CASE
            WHEN @TotalSnapshots = 0 THEN 'NO DATA - Check if collections are running'
            WHEN DATEDIFF(MINUTE, @NewestSnapshot, @ReportTime) > 10 THEN 'STALE DATA - Collections may have stopped'
            ELSE 'DATA CURRENT'
        END AS DataStatus,
        -- Add feedback
        (SELECT TOP 1 FeedbackText FROM dbo.fn_GetMetricFeedback('DBA_DailyHealthOverview', 1, 'DaysOfData', @DaysOfData)) AS DataMaturityAnalysis,
        (SELECT TOP 1 Recommendation FROM dbo.fn_GetMetricFeedback('DBA_DailyHealthOverview', 1, 'DaysOfData', @DaysOfData)) AS DataMaturityRecommendation

    -- Result Set 1a: Metadata
    SELECT
        'REPORT HEADER - FIELD GUIDE' AS Section,
        'TotalSnapshotsCollected' AS FieldName,
        'Total number of 5-minute snapshots in the database' AS FieldDescription,
        'Expected: 12/hour × 24 hours = 288/day. Lower count indicates collection gaps.' AS Interpretation
    UNION ALL SELECT '', 'DaysOfData', 'Number of days between oldest and newest snapshot',
        'More days = better trend analysis. Need 7+ days for weekly patterns, 14+ for reliable trends.'
    UNION ALL SELECT '', 'DataStatus', 'Whether monitoring data is current, stale, or missing',
        'DATA CURRENT = good. STALE = collections stopped recently. NO DATA = collections never ran or failed.'

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
            WHEN r.BlockingSessionCount > 10 THEN 'ATTENTION - Moderate Blocking'
            ELSE 'HEALTHY'
        END AS HealthStatus,
        DATEDIFF(MINUTE, r.SnapshotUTC, SYSUTCDATETIME()) AS MinutesSinceSnapshot,
        -- Add feedback for key metrics
        (SELECT TOP 1 FeedbackText FROM dbo.fn_GetMetricFeedback('DBA_DailyHealthOverview', 2, 'CpuSignalWaitPct', r.CpuSignalWaitPct)) AS CpuAnalysis,
        (SELECT TOP 1 Recommendation FROM dbo.fn_GetMetricFeedback('DBA_DailyHealthOverview', 2, 'CpuSignalWaitPct', r.CpuSignalWaitPct)) AS CpuRecommendation,
        (SELECT TOP 1 FeedbackText FROM dbo.fn_GetMetricFeedback('DBA_DailyHealthOverview', 2, 'BlockingSessionCount', r.BlockingSessionCount)) AS BlockingAnalysis,
        (SELECT TOP 1 Recommendation FROM dbo.fn_GetMetricFeedback('DBA_DailyHealthOverview', 2, 'BlockingSessionCount', r.BlockingSessionCount)) AS BlockingRecommendation,
        (SELECT TOP 1 FeedbackText FROM dbo.fn_GetMetricFeedback('DBA_DailyHealthOverview', 2, 'DeadlockCountRecent', r.DeadlockCountRecent)) AS DeadlockAnalysis,
        (SELECT TOP 1 Recommendation FROM dbo.fn_GetMetricFeedback('DBA_DailyHealthOverview', 2, 'DeadlockCountRecent', r.DeadlockCountRecent)) AS DeadlockRecommendation
    FROM dbo.PerfSnapshotRun r
    WHERE r.PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM dbo.PerfSnapshotRun)

    -- Result Set 2a: Field Guide
    SELECT
        'CURRENT HEALTH - FIELD GUIDE' AS Section,
        'CpuSignalWaitPct' AS FieldName,
        'Percentage of time SQL Server is waiting for CPU (signal waits)' AS FieldDescription,
        'Higher = CPU pressure. 0-10% = healthy, 10-20% = moderate, 20-40% = elevated, 40%+ = critical.' AS Interpretation
    UNION ALL SELECT '', 'BlockingSessionCount', 'Number of sessions currently blocked by other sessions',
        'Higher = lock contention. 0-5 = normal, 6-15 = watch, 16-30 = investigate, 31+ = critical.'
    UNION ALL SELECT '', 'DeadlockCountRecent', 'Deadlocks in last 10 minutes (from system_health)',
        '0 = good. Any deadlocks warrant investigation. 10+ = deadlock storm requiring immediate action.'
    UNION ALL SELECT '', 'TopWaitType', 'The wait type consuming the most time',
        'PAGEIOLATCH = disk I/O, LCK_M = locking, SOS_SCHEDULER_YIELD = CPU, CXPACKET = parallelism.'
    UNION ALL SELECT '', 'HealthStatus', 'Overall health assessment based on all metrics',
        'HEALTHY = no issues. ATTENTION = watch. WARNING = investigate soon. CRITICAL = immediate action.'
    UNION ALL SELECT '', 'MinutesSinceSnapshot', 'How old the current data is',
        '0-6 min = current. 7-15 min = slight delay. 16-60 min = stale. 60+ min = collections stopped.'

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

    -- Result Set 3a: Interpretation Guide
    SELECT
        'ISSUES - INTERPRETATION GUIDE' AS Section,
        'This result set shows every 5-minute snapshot where problems were detected.' AS Analysis,
        'Look for PATTERNS: Are issues constant (every snapshot) or intermittent (specific times)? Constant issues indicate systemic problems. Intermittent issues may correlate with batch jobs or peak usage times.' AS KeyInsight1,
        'Check TIMING: Do issues occur at the same time daily? This suggests scheduled jobs or user activity patterns.' AS KeyInsight2,
        'Review ISSUE TYPE: If all rows show same IssueType (e.g., HIGH BLOCKING), you have a focused problem to solve. Mixed types suggest multiple independent issues.' AS KeyInsight3

    -- =============================================
    -- RESULT SET 4: 24-Hour Summary Statistics
    -- =============================================
    DECLARE @AvgCpu DECIMAL(5,2), @MaxCpu DECIMAL(5,2)
    DECLARE @AvgBlocking INT, @MaxBlocking INT
    DECLARE @TotalDeadlocks INT

    SELECT
        @AvgCpu = AVG(CpuSignalWaitPct),
        @MaxCpu = MAX(CpuSignalWaitPct),
        @AvgBlocking = AVG(BlockingSessionCount),
        @MaxBlocking = MAX(BlockingSessionCount),
        @TotalDeadlocks = SUM(DeadlockCountRecent)
    FROM dbo.PerfSnapshotRun
    WHERE SnapshotUTC >= DATEADD(HOUR, -@HoursBackForIssues, SYSUTCDATETIME())

    SELECT
        '24-HOUR SUMMARY STATISTICS' AS Section,
        COUNT(*) AS TotalSnapshots,
        @AvgCpu AS AvgCpuSignalWaitPct,
        @MaxCpu AS MaxCpuSignalWaitPct,
        @AvgBlocking AS AvgBlockingSessions,
        @MaxBlocking AS MaxBlockingSessions,
        @TotalDeadlocks AS TotalDeadlocks,
        MAX(SessionsCount) AS PeakSessions,
        MAX(RequestsCount) AS PeakRequests,
        SUM(CASE WHEN CpuSignalWaitPct > 20 THEN 1 ELSE 0 END) AS HighCpuSnapshots,
        SUM(CASE WHEN BlockingSessionCount > 10 THEN 1 ELSE 0 END) AS HighBlockingSnapshots,
        SUM(CASE WHEN DeadlockCountRecent > 0 THEN 1 ELSE 0 END) AS DeadlockSnapshots,
        -- Add feedback
        (SELECT TOP 1 FeedbackText FROM dbo.fn_GetMetricFeedback('DBA_DailyHealthOverview', 4, 'AvgCpuSignalWaitPct', @AvgCpu)) AS AvgCpuAnalysis,
        (SELECT TOP 1 Recommendation FROM dbo.fn_GetMetricFeedback('DBA_DailyHealthOverview', 4, 'AvgCpuSignalWaitPct', @AvgCpu)) AS AvgCpuRecommendation,
        (SELECT TOP 1 FeedbackText FROM dbo.fn_GetMetricFeedback('DBA_DailyHealthOverview', 4, 'TotalDeadlocks', @TotalDeadlocks)) AS DeadlockSummaryAnalysis,
        (SELECT TOP 1 Recommendation FROM dbo.fn_GetMetricFeedback('DBA_DailyHealthOverview', 4, 'TotalDeadlocks', @TotalDeadlocks)) AS DeadlockSummaryRecommendation
    FROM dbo.PerfSnapshotRun
    WHERE SnapshotUTC >= DATEADD(HOUR, -@HoursBackForIssues, SYSUTCDATETIME())

    -- Result Set 4a: Statistics Field Guide
    SELECT
        'STATISTICS - FIELD GUIDE' AS Section,
        'AvgCpuSignalWaitPct vs MaxCpuSignalWaitPct' AS Comparison,
        'If AVG is low but MAX is high, CPU spikes are intermittent. If both are high, CPU is constantly busy. Large gap suggests batch jobs or irregular workload.' AS Interpretation
    UNION ALL SELECT '', 'HighCpuSnapshots / TotalSnapshots',
        'Percentage of time with CPU issues. Example: 50 high snapshots out of 288 = 17% of the day had CPU problems.'
    UNION ALL SELECT '', 'TotalDeadlocks',
        'Sum of ALL deadlocks across ALL snapshots. One busy snapshot can have many deadlocks, inflating this number.'
    UNION ALL SELECT '', 'PeakSessions vs PeakRequests',
        'Sessions = connections. Requests = active queries. High sessions but low requests = many idle connections.'

    -- =============================================
    -- RESULT SET 5: Top Slowest Queries (Recent)
    -- =============================================
    SELECT TOP (@TopSlowQueries)
        'TOP ' + CAST(@TopSlowQueries AS VARCHAR(10)) + ' SLOWEST QUERIES (RECENT)' AS Section,
        qs.DatabaseName,
        CASE
            WHEN LEN(qs.SqlText) > 150 THEN LEFT(qs.SqlText, 147) + '...'
            ELSE qs.SqlText
        END AS SqlText,
        qs.ExecutionCount,
        CAST(qs.AvgElapsedMs AS DECIMAL(15,2)) AS AvgElapsedMs,
        CAST(qs.AvgCpuMs AS DECIMAL(15,2)) AS AvgCpuMs,
        CAST(qs.AvgLogicalReads AS DECIMAL(15,2)) AS AvgLogicalReads,
        CAST(qs.ExecutionCount * qs.AvgElapsedMs AS DECIMAL(18,2)) AS ImpactScore,
        r.SnapshotUTC AS CapturedAt,
        qs.QueryHash,
        -- Add feedback
        (SELECT TOP 1 FeedbackText FROM dbo.fn_GetMetricFeedback('DBA_DailyHealthOverview', 5, 'AvgElapsedMs', qs.AvgElapsedMs)) AS ElapsedTimeAnalysis,
        (SELECT TOP 1 Recommendation FROM dbo.fn_GetMetricFeedback('DBA_DailyHealthOverview', 5, 'AvgElapsedMs', qs.AvgElapsedMs)) AS ElapsedTimeRecommendation,
        (SELECT TOP 1 FeedbackText FROM dbo.fn_GetMetricFeedback('DBA_DailyHealthOverview', 5, 'ImpactScore', qs.ExecutionCount * qs.AvgElapsedMs)) AS ImpactAnalysis
    FROM dbo.PerfSnapshotQueryStats qs
    INNER JOIN dbo.PerfSnapshotRun r ON qs.PerfSnapshotRunID = r.PerfSnapshotRunID
    WHERE r.SnapshotUTC >= DATEADD(HOUR, -@HoursBackForIssues, SYSUTCDATETIME())
    ORDER BY qs.AvgElapsedMs DESC

    -- Result Set 5a: Slow Query Field Guide
    SELECT
        'SLOW QUERIES - FIELD GUIDE' AS Section,
        'AvgElapsedMs' AS FieldName,
        'Average total time for query to complete (milliseconds)' AS FieldDescription,
        'Includes CPU time + wait time. 1000ms = 1 second. Queries > 5000ms (5 sec) need optimization.' AS Interpretation
    UNION ALL SELECT '', 'AvgCpuMs', 'Average CPU time consumed per execution',
        'If AvgCpuMs ≈ AvgElapsedMs, query is CPU-bound. If AvgCpuMs << AvgElapsedMs, query is waiting (I/O, locks, etc).'
    UNION ALL SELECT '', 'AvgLogicalReads', 'Average pages read from memory per execution',
        'Higher = more data scanned. 1000+ reads suggests missing index or table scan. Check execution plan.'
    UNION ALL SELECT '', 'ImpactScore', 'ExecutionCount × AvgElapsedMs = total time consumed',
        'Higher score = bigger problem. A slow query run 1000 times has more impact than slower query run once.'
    UNION ALL SELECT '', 'QueryHash', 'Unique identifier for query pattern (ignores literal values)',
        'Same hash = same query with different parameters. Track this to see if same query appears multiple times.'

    -- =============================================
    -- RESULT SET 6: Top CPU Queries (Recent)
    -- =============================================
    SELECT TOP (@TopSlowQueries)
        'TOP ' + CAST(@TopSlowQueries AS VARCHAR(10)) + ' CPU QUERIES (RECENT)' AS Section,
        qs.DatabaseName,
        CASE
            WHEN LEN(qs.SqlText) > 150 THEN LEFT(qs.SqlText, 147) + '...'
            ELSE qs.SqlText
        END AS SqlText,
        qs.ExecutionCount,
        CAST(qs.AvgCpuMs AS DECIMAL(15,2)) AS AvgCpuMs,
        CAST(qs.AvgCpuMs * qs.ExecutionCount AS DECIMAL(18,2)) AS TotalCpuMs,
        CAST(qs.ExecutionCount * qs.AvgCpuMs AS DECIMAL(18,2)) AS CpuImpactScore,
        r.SnapshotUTC AS CapturedAt
    FROM dbo.PerfSnapshotQueryStats qs
    INNER JOIN dbo.PerfSnapshotRun r ON qs.PerfSnapshotRunID = r.PerfSnapshotRunID
    WHERE r.SnapshotUTC >= DATEADD(HOUR, -@HoursBackForIssues, SYSUTCDATETIME())
      AND qs.AvgCpuMs > 100  -- Focus on queries consuming meaningful CPU
    ORDER BY qs.AvgCpuMs DESC

    -- Result Set 6a: CPU Query Field Guide
    SELECT
        'CPU QUERIES - INTERPRETATION' AS Section,
        'High AvgCpuMs with low AvgElapsedMs (from Result Set #5)' AS Pattern,
        'Query is CPU-intensive with minimal waiting. Likely needs algorithmic optimization or better indexes.' AS Meaning
    UNION ALL SELECT '', 'TotalCpuMs > 1,000,000 (1000 seconds)',
        'Query consumed 16+ minutes of CPU time. Top priority for optimization.'
    UNION ALL SELECT '', 'Same query in both Slowest (Set #5) and CPU (Set #6)',
        'Query is both slow AND CPU-intensive. Primary optimization target.'

    -- =============================================
    -- RESULT SET 7: Top Missing Indexes
    -- =============================================
    SELECT TOP (@TopMissingIndexes)
        'TOP ' + CAST(@TopMissingIndexes AS VARCHAR(10)) + ' MISSING INDEXES' AS Section,
        mi.DatabaseName,
        mi.ObjectName,
        mi.EqualityColumns,
        mi.InequalityColumns,
        mi.IncludedColumns,
        mi.UserSeeks,
        mi.UserScans,
        CAST(mi.AvgTotalUserCost AS DECIMAL(15,2)) AS AvgTotalUserCost,
        CAST(mi.AvgUserImpact AS DECIMAL(15,2)) AS AvgUserImpact,
        CAST(mi.UserSeeks * mi.AvgTotalUserCost * mi.AvgUserImpact AS DECIMAL(18,2)) AS ImpactScore,
        r.SnapshotUTC AS LastObserved,
        -- Build CREATE INDEX statement dynamically
        'CREATE NONCLUSTERED INDEX [IX_' + mi.ObjectName + '_' + CAST(mi.PerfSnapshotMissingIndexID AS VARCHAR(20)) + ']' + CHAR(13) + CHAR(10) +
        'ON ' + mi.ObjectName + ' (' +
        ISNULL(mi.EqualityColumns, '') +
        CASE WHEN mi.EqualityColumns IS NOT NULL AND mi.InequalityColumns IS NOT NULL THEN ', ' ELSE '' END +
        ISNULL(mi.InequalityColumns, '') + ')' +
        CASE WHEN mi.IncludedColumns IS NOT NULL THEN CHAR(13) + CHAR(10) + 'INCLUDE (' + mi.IncludedColumns + ')' ELSE '' END AS CreateIndexStatement,
        -- Add feedback
        (SELECT TOP 1 FeedbackText FROM dbo.fn_GetMetricFeedback('DBA_DailyHealthOverview', 7, 'ImpactScore', mi.UserSeeks * mi.AvgTotalUserCost * mi.AvgUserImpact)) AS ImpactAnalysis,
        (SELECT TOP 1 Recommendation FROM dbo.fn_GetMetricFeedback('DBA_DailyHealthOverview', 7, 'ImpactScore', mi.UserSeeks * mi.AvgTotalUserCost * mi.AvgUserImpact)) AS ImpactRecommendation,
        (SELECT TOP 1 FeedbackText FROM dbo.fn_GetMetricFeedback('DBA_DailyHealthOverview', 7, 'UserSeeks', mi.UserSeeks)) AS UsageAnalysis
    FROM dbo.PerfSnapshotMissingIndexes mi
    INNER JOIN dbo.PerfSnapshotRun r ON mi.PerfSnapshotRunID = r.PerfSnapshotRunID
    WHERE r.SnapshotUTC >= DATEADD(HOUR, -@HoursBackForIssues, SYSUTCDATETIME())
    ORDER BY (mi.UserSeeks * mi.AvgTotalUserCost * mi.AvgUserImpact) DESC

    -- Result Set 7a: Missing Index Field Guide
    SELECT
        'MISSING INDEXES - FIELD GUIDE' AS Section,
        'EqualityColumns' AS FieldName,
        'Columns used in WHERE clause with = operator' AS FieldDescription,
        'These become index KEY columns. Order matters - most selective column should be first.' AS Interpretation
    UNION ALL SELECT '', 'InequalityColumns', 'Columns used with >, <, >=, <=, BETWEEN, LIKE',
        'These also become KEY columns but less efficient than equality. Consider separate indexes if needed.'
    UNION ALL SELECT '', 'IncludedColumns', 'Columns SELECTed but not filtered',
        'These become INCLUDE columns (leaf level only). Allows index to "cover" query without key lookups.'
    UNION ALL SELECT '', 'UserSeeks', 'How many times SQL Server looked for matching rows',
        'Higher = index would be used frequently. Seek > 10,000 indicates heavy usage.'
    UNION ALL SELECT '', 'ImpactScore', 'UserSeeks × AvgTotalUserCost × AvgUserImpact',
        'Higher = bigger performance gain expected. Score > 10 million = high priority. ALWAYS test first!'
    UNION ALL SELECT '', 'CreateIndexStatement', 'Ready-to-run CREATE INDEX command',
        '⚠️ WARNING: NEVER run in production without testing! Test in dev, verify queries use it, monitor performance.'

    -- =============================================
    -- RESULT SET 8: Top Wait Types (Last 24 Hours)
    -- =============================================
    SELECT TOP 10
        'TOP 10 WAIT TYPES (LAST ' + CAST(@HoursBackForIssues AS VARCHAR(10)) + ' HOURS)' AS Section,
        ws.WaitType,
        SUM(ws.WaitTimeMs) AS TotalWaitTimeMs,
        SUM(ws.WaitingTasksCount) AS TotalWaitingTasks,
        COUNT(*) AS ObservationCount,
        CAST(100.0 * SUM(ws.WaitTimeMs) / NULLIF(SUM(SUM(ws.WaitTimeMs)) OVER(), 0) AS DECIMAL(5,2)) AS PctOfTotalWaits,
        CASE ws.WaitType
            WHEN 'PAGEIOLATCH_SH' THEN 'Disk I/O - Check for slow storage or memory pressure'
            WHEN 'PAGEIOLATCH_EX' THEN 'Disk I/O - Check for slow storage or memory pressure'
            WHEN 'WRITELOG' THEN 'Log writes - Check log disk performance'
            WHEN 'LCK_M_S' THEN 'Lock contention - Review blocking queries and transaction patterns'
            WHEN 'LCK_M_X' THEN 'Lock contention - Review blocking queries and transaction patterns'
            WHEN 'LCK_M_U' THEN 'Lock contention - Review blocking queries and transaction patterns'
            WHEN 'CXPACKET' THEN 'Parallelism - Consider MAXDOP tuning or query optimization'
            WHEN 'CXCONSUMER' THEN 'Parallelism - Consider MAXDOP tuning or query optimization'
            WHEN 'SOS_SCHEDULER_YIELD' THEN 'CPU pressure - High workload, review CPU queries'
            WHEN 'ASYNC_NETWORK_IO' THEN 'Network/client wait - Check client performance or result set size'
            WHEN 'OLEDB' THEN 'Linked server or external call wait'
            ELSE 'See SQL Server documentation'
        END AS WaitTypeDescription
    FROM dbo.PerfSnapshotWaitStats ws
    INNER JOIN dbo.PerfSnapshotRun r ON ws.PerfSnapshotRunID = r.PerfSnapshotRunID
    WHERE r.SnapshotUTC >= DATEADD(HOUR, -@HoursBackForIssues, SYSUTCDATETIME())
      AND ws.WaitType NOT LIKE 'SLEEP%'  -- Exclude benign waits
      AND ws.WaitType NOT LIKE 'BROKER%'
      AND ws.WaitType NOT LIKE 'XE%'
      AND ws.WaitType NOT LIKE 'QDS%'
    GROUP BY ws.WaitType
    ORDER BY SUM(ws.WaitTimeMs) DESC

    -- Result Set 8a: Wait Types Field Guide
    SELECT
        'WAIT TYPES - INTERPRETATION GUIDE' AS Section,
        'Wait Types reveal WHERE SQL Server is spending time waiting.' AS Overview,
        'PAGEIOLATCH_*: Data file I/O. Fix: Faster storage, more memory, or reduce data scanned (indexes).' AS IOWaits,
        'WRITELOG: Transaction log writes. Fix: Faster log disk, fewer transactions, or larger batches.' AS LogWaits,
        'LCK_M_*: Lock waits. Fix: Shorter transactions, better indexes, or READ_COMMITTED_SNAPSHOT isolation.' AS LockWaits,
        'CXPACKET/CXCONSUMER: Parallel query coordination. Fix: MAXDOP tuning, query optimization, or better stats.' AS ParallelismWaits,
        'SOS_SCHEDULER_YIELD: CPU saturation. Fix: Optimize CPU-intensive queries or add more CPU.' AS CPUWaits,
        'Focus on top 3-5 wait types. Optimizing these gives biggest impact.' AS Strategy

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
        r.SnapshotUTC AS AsOfDate,
        -- Add feedback
        (SELECT TOP 1 FeedbackText FROM dbo.fn_GetMetricFeedback('DBA_DailyHealthOverview', 9, 'TotalSizeMB', db.TotalDataMB + db.TotalLogMB)) AS SizeAnalysis,
        CASE db.LogReuseWaitDesc
            WHEN 'NOTHING' THEN 'Normal - Log space can be reused.'
            WHEN 'CHECKPOINT' THEN 'Waiting for checkpoint. Run CHECKPOINT command if log is growing.'
            WHEN 'LOG_BACKUP' THEN 'CRITICAL: Full/Bulk recovery without log backups. Log will grow indefinitely!'
            WHEN 'ACTIVE_BACKUP_OR_RESTORE' THEN 'Backup/restore in progress. Temporary condition.'
            WHEN 'ACTIVE_TRANSACTION' THEN 'Long-running transaction preventing log reuse. Investigate open transactions.'
            WHEN 'DATABASE_MIRRORING' THEN 'Mirroring/AG sync lagging. Check replica status.'
            WHEN 'REPLICATION' THEN 'Replication not reading log. Check replication health.'
            WHEN 'DATABASE_SNAPSHOT_CREATION' THEN 'Snapshot creation in progress. Temporary.'
            WHEN 'LOG_SCAN' THEN 'Log reader slow. Check log reader job.'
            WHEN 'AVAILABILITY_REPLICA' THEN 'AG replica sync lagging. Check replica health.'
            WHEN 'OLDEST_PAGE' THEN 'Normal for databases with activity.'
            ELSE 'Unknown condition - investigate.'
        END AS LogReuseAnalysis
    FROM dbo.PerfSnapshotDB db
    INNER JOIN dbo.PerfSnapshotRun r ON db.PerfSnapshotRunID = r.PerfSnapshotRunID
    WHERE r.PerfSnapshotRunID = (SELECT MAX(PerfSnapshotRunID) FROM dbo.PerfSnapshotRun)
    ORDER BY (db.TotalDataMB + db.TotalLogMB) DESC

    -- Result Set 9a: Database Size Field Guide
    SELECT
        'DATABASE SIZE - FIELD GUIDE' AS Section,
        'LogReuseWaitDesc' AS CriticalField,
        'Indicates why transaction log space cannot be reused.' AS Purpose,
        'NOTHING or OLDEST_PAGE = healthy. LOG_BACKUP = CRITICAL (no log backups with Full recovery). ACTIVE_TRANSACTION = long transaction blocking log truncation.' AS KeyInsights

    -- =============================================
    -- RESULT SET 10: Recent Errors (If Any)
    -- =============================================
    IF EXISTS (SELECT 1 FROM dbo.LogEntry
               WHERE IsError = 1
               AND DateTime_Occurred >= DATEADD(HOUR, -@HoursBackForIssues, SYSUTCDATETIME()))
    BEGIN
        SELECT
            'RECENT ERRORS (LAST ' + CAST(@HoursBackForIssues AS VARCHAR(10)) + ' HOURS)' AS Section,
            DateTime_Occurred AS DateTime_Occurred,
            ProcedureName,
            ProcedureSection,
            ErrNumber AS ErrNumber,
            ErrDescription AS ErrorDescription,
            DATEDIFF(MINUTE, DateTime_Occurred, SYSUTCDATETIME()) AS MinutesAgo
        FROM dbo.LogEntry
        WHERE IsError = 1
          AND DateTime_Occurred >= DATEADD(HOUR, -@HoursBackForIssues, SYSUTCDATETIME())
        ORDER BY LogEntryID DESC
    END
    ELSE
    BEGIN
        SELECT
            'RECENT ERRORS (LAST ' + CAST(@HoursBackForIssues AS VARCHAR(10)) + ' HOURS)' AS Section,
            'No errors found in the last ' + CAST(@HoursBackForIssues AS VARCHAR(10)) + ' hours' AS Status,
            'Monitoring system is collecting data successfully with no errors.' AS Analysis
    END

    -- =============================================
    -- RESULT SET 11: Collection Job Status
    -- =============================================
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
        js.last_run_time AS LastRunTime,
        CASE
            WHEN j.enabled = 0 THEN 'CRITICAL: Job is disabled. Monitoring data will not be collected.'
            WHEN js.last_run_outcome = 0 THEN 'ERROR: Last run failed. Check job history and error logs.'
            WHEN js.last_run_outcome = 1 THEN 'SUCCESS: Job running normally.'
            ELSE 'UNKNOWN: Verify job status manually.'
        END AS JobAnalysis
    FROM msdb.dbo.sysjobs j
    INNER JOIN msdb.dbo.sysjobservers js ON j.job_id = js.job_id
    WHERE j.name LIKE 'DBA%'

    -- =============================================
    -- RESULT SET 12: Action Items & Recommendations
    -- =============================================
    DECLARE @Recommendations TABLE
    (
        Priority VARCHAR(20),
        ActionItem VARCHAR(200),
        Details NVARCHAR(MAX)
    )

    -- Check for stale data
    IF DATEDIFF(MINUTE, @NewestSnapshot, @ReportTime) > 60
    BEGIN
        INSERT INTO @Recommendations VALUES (
            'CRITICAL',
            'Monitoring Data is Stale',
            'Last snapshot was ' + CAST(DATEDIFF(MINUTE, @NewestSnapshot, @ReportTime) AS VARCHAR(10)) +
            ' minutes ago. Check collection job status and error logs immediately.'
        )
    END

    -- Check for high CPU
    IF EXISTS (SELECT 1 FROM dbo.PerfSnapshotRun
               WHERE CpuSignalWaitPct > 40
               AND SnapshotUTC >= DATEADD(HOUR, -@HoursBackForIssues, SYSUTCDATETIME()))
    BEGIN
        INSERT INTO @Recommendations VALUES (
            'HIGH',
            'Investigate High CPU Usage',
            'CPU signal wait percentage exceeded 40% in the last ' + CAST(@HoursBackForIssues AS VARCHAR(10)) +
            ' hours. Review top CPU queries (Result Set #6) and consider optimization or capacity upgrade.'
        )
    END

    -- Check for blocking
    IF EXISTS (SELECT 1 FROM dbo.PerfSnapshotRun
               WHERE BlockingSessionCount > 20
               AND SnapshotUTC >= DATEADD(HOUR, -@HoursBackForIssues, SYSUTCDATETIME()))
    BEGIN
        INSERT INTO @Recommendations VALUES (
            'HIGH',
            'Investigate Blocking Sessions',
            'More than 20 blocking sessions detected in the last ' + CAST(@HoursBackForIssues AS VARCHAR(10)) +
            ' hours. Review blocking queries using: EXEC DBA_FindBlockingHistory @HoursBack = ' + CAST(@HoursBackForIssues AS VARCHAR(10))
        )
    END

    -- Check for deadlocks
    IF EXISTS (SELECT 1 FROM dbo.PerfSnapshotRun
               WHERE DeadlockCountRecent > 0
               AND SnapshotUTC >= DATEADD(HOUR, -@HoursBackForIssues, SYSUTCDATETIME()))
    BEGIN
        DECLARE @TotalDL INT
        SELECT @TotalDL = SUM(DeadlockCountRecent)
        FROM dbo.PerfSnapshotRun
        WHERE SnapshotUTC >= DATEADD(HOUR, -@HoursBackForIssues, SYSUTCDATETIME())

        INSERT INTO @Recommendations VALUES (
            CASE WHEN @TotalDL > 50 THEN 'CRITICAL' ELSE 'MEDIUM' END,
            'Review Deadlock Graphs',
            CAST(@TotalDL AS VARCHAR(10)) + ' deadlocks detected in the last ' + CAST(@HoursBackForIssues AS VARCHAR(10)) +
            ' hours. Check SQL Server Error Log for deadlock graphs. Trace flags 1222/1204 are auto-enabled.'
        )
    END

    -- Check for high-impact missing indexes
    IF EXISTS (SELECT 1 FROM dbo.PerfSnapshotMissingIndexes mi
               INNER JOIN dbo.PerfSnapshotRun r ON mi.PerfSnapshotRunID = r.PerfSnapshotRunID
               WHERE (mi.UserSeeks * mi.AvgTotalUserCost * mi.AvgUserImpact) > 10000000
               AND r.SnapshotUTC >= DATEADD(HOUR, -@HoursBackForIssues, SYSUTCDATETIME()))
    BEGIN
        INSERT INTO @Recommendations VALUES (
            'MEDIUM',
            'Consider Creating Missing Indexes',
            'High-impact missing indexes detected (impact score > 10 million). Review CREATE INDEX statements in Result Set #7. ' +
            'ALWAYS test in non-production first and monitor index usage after creation.'
        )
    END

    -- Check for slow queries
    IF EXISTS (SELECT 1 FROM dbo.PerfSnapshotQueryStats qs
               INNER JOIN dbo.PerfSnapshotRun r ON qs.PerfSnapshotRunID = r.PerfSnapshotRunID
               WHERE qs.AvgElapsedMs > 10000
               AND r.SnapshotUTC >= DATEADD(HOUR, -@HoursBackForIssues, SYSUTCDATETIME()))
    BEGIN
        INSERT INTO @Recommendations VALUES (
            'MEDIUM',
            'Optimize Slow Queries',
            'Queries with average elapsed time > 10 seconds detected. Review Result Set #5 for optimization opportunities. ' +
            'Check execution plans, statistics, and missing indexes.'
        )
    END

    -- If no issues, all is well
    IF NOT EXISTS (SELECT 1 FROM @Recommendations)
    BEGIN
        INSERT INTO @Recommendations VALUES (
            'INFO',
            'System Healthy',
            'No critical, high, or medium priority issues detected in the last ' + CAST(@HoursBackForIssues AS VARCHAR(10)) +
            ' hours. Continue monitoring daily.'
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
        END

    -- Final summary message
    SELECT
        '' AS Section,
        '==========================================' AS Message
    UNION ALL SELECT '', 'Daily Health Overview Report Completed'
    UNION ALL SELECT '', '=========================================='
    UNION ALL SELECT '', 'Total Result Sets: 12 (plus field guides)'
    UNION ALL SELECT '', '  1. Report Header (with data maturity analysis)'
    UNION ALL SELECT '', '  2. Current System Health (with metric feedback)'
    UNION ALL SELECT '', '  3. Issues Found (with pattern analysis)'
    UNION ALL SELECT '', '  4. Summary Statistics (with trend analysis)'
    UNION ALL SELECT '', '  5. Top Slow Queries (with optimization guidance)'
    UNION ALL SELECT '', '  6. Top CPU Queries (with interpretation)'
    UNION ALL SELECT '', '  7. Top Missing Indexes (with creation warnings)'
    UNION ALL SELECT '', '  8. Top Wait Types (with descriptions)'
    UNION ALL SELECT '', '  9. Database Sizes (with log reuse analysis)'
    UNION ALL SELECT '', ' 10. Recent Errors (with context)'
    UNION ALL SELECT '', ' 11. Collection Job Status (with health check)'
    UNION ALL SELECT '', ' 12. Action Items & Recommendations (prioritized)'
    UNION ALL SELECT '', ''
    UNION ALL SELECT '', 'Each result set includes field guides and feedback'
    UNION ALL SELECT '', 'based on configurable rules in FeedbackRule table.'
    UNION ALL SELECT '', '=========================================='

END
GO

PRINT ''
PRINT '=========================================='
PRINT 'DBA_DailyHealthOverview Enhanced Successfully'
PRINT '=========================================='
PRINT ''
PRINT 'The procedure now includes:'
PRINT '  - Inline feedback for key metrics'
PRINT '  - Field guides explaining each metric'
PRINT '  - Interpretation guidelines'
PRINT '  - Actionable recommendations'
PRINT '  - All driven by FeedbackRule table'
PRINT ''
PRINT 'Usage: EXEC DBA_DailyHealthOverview'
PRINT '       EXEC DBA_DailyHealthOverview @TopSlowQueries = 20, @TopMissingIndexes = 20'
PRINT '=========================================='
GO
