USE [DBATools]
GO

-- =============================================
-- Diagnostic Views for Quick Analysis
-- =============================================

-- Latest snapshot summary
CREATE OR ALTER VIEW dbo.vw_LatestSnapshotSummary
AS
SELECT TOP 1
    r.PerfSnapshotRunID,
    r.SnapshotUTC,
    r.ServerName,
    r.SqlVersion,
    r.CpuSignalWaitPct,
    r.TopWaitType,
    r.TopWaitMsPerSec,
    r.SessionsCount,
    r.RequestsCount,
    r.BlockingSessionCount,
    r.DeadlockCountRecent,
    r.MemoryGrantWarningCount,
    m.PageLifeExpectancy,
    m.BufferCacheHitRatio,
    m.TotalServerMemoryMB,
    m.TargetServerMemoryMB
FROM dbo.PerfSnapshotRun r
LEFT JOIN dbo.PerfSnapshotMemory m ON r.PerfSnapshotRunID = m.PerfSnapshotRunID
ORDER BY r.PerfSnapshotRunID DESC
GO

-- Backup risk assessment
CREATE OR ALTER VIEW dbo.vw_BackupRiskAssessment
AS
SELECT TOP 100
    bh.DatabaseName,
    bh.RecoveryModel,
    bh.LastFullBackupDate,
    bh.LastLogBackupDate,
    bh.HoursSinceFullBackup,
    bh.MinutesSinceLogBackup,
    bh.BackupRiskLevel,
    r.SnapshotUTC
FROM dbo.PerfSnapshotBackupHistory bh
INNER JOIN dbo.PerfSnapshotRun r ON bh.PerfSnapshotRunID = r.PerfSnapshotRunID
WHERE bh.BackupRiskLevel IN ('WARNING', 'CRITICAL')
ORDER BY r.SnapshotUTC DESC, bh.BackupRiskLevel DESC
GO

-- I/O latency hotspots
CREATE OR ALTER VIEW dbo.vw_IOLatencyHotspots
AS
SELECT TOP 100
    io.DatabaseName,
    io.FileType,
    io.PhysicalName,
    io.AvgReadLatencyMs,
    io.AvgWriteLatencyMs,
    io.SizeOnDiskMB,
    r.SnapshotUTC,
    CASE
        WHEN io.AvgReadLatencyMs > 25 OR io.AvgWriteLatencyMs > 25 THEN 'CRITICAL'
        WHEN io.AvgReadLatencyMs > 15 OR io.AvgWriteLatencyMs > 15 THEN 'WARNING'
        ELSE 'OK'
    END AS LatencyStatus
FROM dbo.PerfSnapshotIOStats io
INNER JOIN dbo.PerfSnapshotRun r ON io.PerfSnapshotRunID = r.PerfSnapshotRunID
WHERE io.AvgReadLatencyMs > 15 OR io.AvgWriteLatencyMs > 15
ORDER BY r.SnapshotUTC DESC, GREATEST(io.AvgReadLatencyMs, io.AvgWriteLatencyMs) DESC
GO

-- Top expensive queries
CREATE OR ALTER VIEW dbo.vw_TopExpensiveQueries
AS
SELECT TOP 100
    qs.DatabaseName,
    qs.ObjectName,
    LEFT(qs.SqlText, 200) AS SqlTextPreview,
    qs.ExecutionCount,
    qs.AvgCpuMs,
    qs.AvgLogicalReads,
    qs.AvgElapsedMs,
    qs.TotalCpuMs,
    qs.TotalLogicalReads,
    r.SnapshotUTC,
    qs.QueryHash
FROM dbo.PerfSnapshotQueryStats qs
INNER JOIN dbo.PerfSnapshotRun r ON qs.PerfSnapshotRunID = r.PerfSnapshotRunID
ORDER BY r.SnapshotUTC DESC, qs.AvgCpuMs DESC
GO

-- Top missing indexes by impact
CREATE OR ALTER VIEW dbo.vw_TopMissingIndexes
AS
SELECT TOP 100
    mi.DatabaseName,
    mi.ObjectName,
    mi.EqualityColumns,
    mi.InequalityColumns,
    mi.IncludedColumns,
    mi.UserSeeks,
    mi.AvgTotalUserCost,
    mi.AvgUserImpact,
    mi.ImpactScore,
    r.SnapshotUTC,
    'CREATE NONCLUSTERED INDEX IX_' + REPLACE(REPLACE(mi.ObjectName, '[', ''), ']', '') + '_Missing ON ' + mi.ObjectName +
    ' (' + ISNULL(mi.EqualityColumns, '') +
    CASE WHEN mi.EqualityColumns IS NOT NULL AND mi.InequalityColumns IS NOT NULL THEN ', ' ELSE '' END +
    ISNULL(mi.InequalityColumns, '') + ')' +
    CASE WHEN mi.IncludedColumns IS NOT NULL THEN ' INCLUDE (' + mi.IncludedColumns + ')' ELSE '' END AS IndexCreateStatement
FROM dbo.PerfSnapshotMissingIndexes mi
INNER JOIN dbo.PerfSnapshotRun r ON mi.PerfSnapshotRunID = r.PerfSnapshotRunID
ORDER BY r.SnapshotUTC DESC, mi.ImpactScore DESC
GO

-- Wait statistics analysis
CREATE OR ALTER VIEW dbo.vw_TopWaitStats
AS
SELECT TOP 100
    ws.WaitType,
    ws.WaitingTasksCount,
    ws.WaitTimeMs,
    ws.ResourceWaitTimeMs,
    ws.AvgWaitTimeMs,
    r.SnapshotUTC,
    CASE ws.WaitType
        WHEN 'PAGEIOLATCH_SH' THEN 'Storage I/O - Read from disk'
        WHEN 'PAGEIOLATCH_EX' THEN 'Storage I/O - Write to disk'
        WHEN 'WRITELOG' THEN 'Transaction log I/O'
        WHEN 'CXPACKET' THEN 'Parallelism - Tune MAXDOP'
        WHEN 'CXCONSUMER' THEN 'Parallelism - Consumer wait'
        WHEN 'ASYNC_NETWORK_IO' THEN 'Client not consuming results'
        WHEN 'LCK_M_S' THEN 'Shared lock contention'
        WHEN 'LCK_M_X' THEN 'Exclusive lock contention'
        WHEN 'SOS_SCHEDULER_YIELD' THEN 'CPU pressure'
        ELSE 'See documentation'
    END AS WaitTypeDescription
FROM dbo.PerfSnapshotWaitStats ws
INNER JOIN dbo.PerfSnapshotRun r ON ws.PerfSnapshotRunID = r.PerfSnapshotRunID
ORDER BY r.SnapshotUTC DESC, ws.WaitTimeMs DESC
GO

-- VLF health check
CREATE OR ALTER VIEW dbo.vw_VLFHealthCheck
AS
SELECT TOP 100
    db.DatabaseName,
    db.RecoveryModelDesc,
    db.TotalLogMB,
    db.LogSpaceUsedPercent,
    db.VLFCount,
    r.SnapshotUTC,
    CASE
        WHEN db.VLFCount > 10000 THEN 'CRITICAL'
        WHEN db.VLFCount > 1000 THEN 'WARNING'
        ELSE 'OK'
    END AS VLFStatus
FROM dbo.PerfSnapshotDB db
INNER JOIN dbo.PerfSnapshotRun r ON db.PerfSnapshotRunID = r.PerfSnapshotRunID
WHERE db.VLFCount > 1000
ORDER BY r.SnapshotUTC DESC, db.VLFCount DESC
GO

-- Scheduler health (CPU pressure detection)
CREATE OR ALTER VIEW dbo.vw_SchedulerHealthCheck
AS
SELECT TOP 100
    s.SchedulerID,
    s.CpuID,
    s.RunnableTasksCount,
    s.CurrentTasksCount,
    s.WorkQueueCount,
    s.LoadFactor,
    r.SnapshotUTC,
    CASE
        WHEN s.RunnableTasksCount > 5 THEN 'CRITICAL'
        WHEN s.RunnableTasksCount > 2 THEN 'WARNING'
        ELSE 'OK'
    END AS CPUPressureStatus
FROM dbo.PerfSnapshotSchedulers s
INNER JOIN dbo.PerfSnapshotRun r ON s.PerfSnapshotRunID = r.PerfSnapshotRunID
WHERE s.RunnableTasksCount > 0
ORDER BY r.SnapshotUTC DESC, s.RunnableTasksCount DESC
GO

-- Unused indexes
CREATE OR ALTER VIEW dbo.vw_UnusedIndexes
AS
SELECT TOP 100
    iu.DatabaseName,
    iu.ObjectName,
    iu.IndexName,
    iu.UserSeeks,
    iu.UserScans,
    iu.UserLookups,
    iu.UserUpdates,
    iu.LastSeek,
    iu.LastScan,
    iu.LastLookup,
    r.SnapshotUTC,
    'DROP INDEX ' + iu.IndexName + ' ON ' + iu.ObjectName AS DropStatement
FROM dbo.PerfSnapshotIndexUsage iu
INNER JOIN dbo.PerfSnapshotRun r ON iu.PerfSnapshotRunID = r.PerfSnapshotRunID
WHERE (iu.UserSeeks + iu.UserScans + iu.UserLookups) = 0
  AND iu.UserUpdates > 0
  AND iu.IndexID > 1  -- Exclude clustered indexes
ORDER BY r.SnapshotUTC DESC, iu.UserUpdates DESC
GO

-- Memory pressure trends
CREATE OR ALTER VIEW dbo.vw_MemoryPressureTrends
AS
SELECT TOP 100
    r.SnapshotUTC,
    m.PageLifeExpectancy,
    m.BufferCacheHitRatio,
    m.TotalServerMemoryMB,
    m.TargetServerMemoryMB,
    m.MemoryGrantsPending,
    CASE
        WHEN m.PageLifeExpectancy < 300 THEN 'CRITICAL'
        WHEN m.PageLifeExpectancy < 500 THEN 'WARNING'
        ELSE 'OK'
    END AS MemoryPressureStatus
FROM dbo.PerfSnapshotMemory m
INNER JOIN dbo.PerfSnapshotRun r ON m.PerfSnapshotRunID = r.PerfSnapshotRunID
ORDER BY r.SnapshotUTC DESC
GO

-- Configuration drift detection
CREATE OR ALTER VIEW dbo.vw_ConfigurationChanges
AS
WITH ConfigWithPrevious AS
(
    SELECT
        c.ConfigName,
        c.ConfigValueInUse,
        r.SnapshotUTC,
        LAG(c.ConfigValueInUse) OVER (PARTITION BY c.ConfigName ORDER BY r.SnapshotUTC) AS PreviousValue
    FROM dbo.PerfSnapshotConfig c
    INNER JOIN dbo.PerfSnapshotRun r ON c.PerfSnapshotRunID = r.PerfSnapshotRunID
)
SELECT TOP 100
    ConfigName,
    CAST(PreviousValue AS VARCHAR(100)) AS OldValue,
    CAST(ConfigValueInUse AS VARCHAR(100)) AS NewValue,
    SnapshotUTC AS ChangedAt
FROM ConfigWithPrevious
WHERE ConfigValueInUse <> PreviousValue
  AND PreviousValue IS NOT NULL
ORDER BY SnapshotUTC DESC
GO

PRINT 'Diagnostic views created successfully'
PRINT 'Available views:'
PRINT '  - vw_LatestSnapshotSummary'
PRINT '  - vw_BackupRiskAssessment'
PRINT '  - vw_IOLatencyHotspots'
PRINT '  - vw_TopExpensiveQueries'
PRINT '  - vw_TopMissingIndexes'
PRINT '  - vw_TopWaitStats'
PRINT '  - vw_VLFHealthCheck'
PRINT '  - vw_SchedulerHealthCheck'
PRINT '  - vw_UnusedIndexes'
PRINT '  - vw_MemoryPressureTrends'
PRINT '  - vw_ConfigurationChanges'
GO
