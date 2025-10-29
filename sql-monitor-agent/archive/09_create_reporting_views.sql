USE [DBATools]
GO

-- =============================================
-- Reporting Views with Timezone Conversion
-- These views depend on tables created by collector scripts
-- Must be run AFTER collectors (P0, P1, P2, P3)
-- =============================================

-- Latest snapshot summary with Eastern Time
CREATE OR ALTER VIEW dbo.vw_LatestSnapshotSummary_ET
AS
SELECT TOP 1
    r.PerfSnapshotRunID,
    r.SnapshotUTC,
    dbo.fn_ConvertToReportingTime(r.SnapshotUTC) AS SnapshotLocalTime,
    DATENAME(TZ, r.SnapshotUTC AT TIME ZONE 'UTC' AT TIME ZONE dbo.fn_GetConfigValue('ReportingTimeZone')) AS TimeZoneAbbr,
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
    m.TargetServerMemoryMB,
    -- Add status indicators based on config thresholds
    CASE
        WHEN m.PageLifeExpectancy < dbo.fn_GetConfigInt('PageLifeExpectancyCritical') THEN 'CRITICAL'
        WHEN m.PageLifeExpectancy < dbo.fn_GetConfigInt('PageLifeExpectancyWarning') THEN 'WARNING'
        ELSE 'OK'
    END AS MemoryPressureStatus,
    CASE
        WHEN m.BufferCacheHitRatio < dbo.fn_GetConfigInt('BufferCacheHitRatioCritical') THEN 'CRITICAL'
        WHEN m.BufferCacheHitRatio < dbo.fn_GetConfigInt('BufferCacheHitRatioWarning') THEN 'WARNING'
        ELSE 'OK'
    END AS CacheHitStatus,
    CASE
        WHEN r.BlockingSessionCount >= dbo.fn_GetConfigInt('BlockingSessionsCritical') THEN 'CRITICAL'
        WHEN r.BlockingSessionCount >= dbo.fn_GetConfigInt('BlockingSessionsWarning') THEN 'WARNING'
        ELSE 'OK'
    END AS BlockingStatus
FROM dbo.PerfSnapshotRun r
LEFT JOIN dbo.PerfSnapshotMemory m ON r.PerfSnapshotRunID = m.PerfSnapshotRunID
ORDER BY r.PerfSnapshotRunID DESC
GO

-- Backup risk assessment with Eastern Time
CREATE OR ALTER VIEW dbo.vw_BackupRiskAssessment_ET
AS
SELECT TOP 100
    bh.DatabaseName,
    bh.RecoveryModel,
    bh.LastFullBackupDate,
    dbo.fn_ConvertToReportingTime(bh.LastFullBackupDate) AS LastFullBackupLocalTime,
    bh.LastLogBackupDate,
    dbo.fn_ConvertToReportingTime(bh.LastLogBackupDate) AS LastLogBackupLocalTime,
    bh.HoursSinceFullBackup,
    bh.MinutesSinceLogBackup,
    -- Use config-based risk calculation
    CASE
        WHEN bh.LastFullBackupDate IS NULL THEN 'CRITICAL'
        WHEN bh.HoursSinceFullBackup > dbo.fn_GetConfigInt('BackupCriticalHours') THEN 'CRITICAL'
        WHEN bh.HoursSinceFullBackup > dbo.fn_GetConfigInt('BackupWarningHours') THEN 'WARNING'
        WHEN bh.RecoveryModel = 'FULL' AND bh.MinutesSinceLogBackup > dbo.fn_GetConfigInt('LogBackupWarningMinutes') THEN 'WARNING'
        ELSE 'OK'
    END AS BackupRiskLevel,
    r.SnapshotUTC,
    dbo.fn_ConvertToReportingTime(r.SnapshotUTC) AS SnapshotLocalTime
FROM dbo.PerfSnapshotBackupHistory bh
INNER JOIN dbo.PerfSnapshotRun r ON bh.PerfSnapshotRunID = r.PerfSnapshotRunID
WHERE bh.BackupRiskLevel IN ('WARNING', 'CRITICAL')
   OR (bh.RecoveryModel = 'FULL' AND bh.MinutesSinceLogBackup > dbo.fn_GetConfigInt('LogBackupWarningMinutes'))
ORDER BY r.SnapshotUTC DESC,
    CASE WHEN bh.LastFullBackupDate IS NULL THEN 0 ELSE bh.HoursSinceFullBackup END DESC
GO

-- I/O Latency with config-based thresholds
CREATE OR ALTER VIEW dbo.vw_IOLatencyHotspots_ET
AS
SELECT TOP 100
    io.DatabaseName,
    io.FileType,
    io.PhysicalName,
    io.AvgReadLatencyMs,
    io.AvgWriteLatencyMs,
    io.SizeOnDiskMB,
    r.SnapshotUTC,
    dbo.fn_ConvertToReportingTime(r.SnapshotUTC) AS SnapshotLocalTime,
    -- Use CASE instead of GREATEST for SQL Server 2019 compatibility
    CASE
        WHEN io.AvgReadLatencyMs > io.AvgWriteLatencyMs THEN io.AvgReadLatencyMs
        ELSE io.AvgWriteLatencyMs
    END AS MaxLatencyMs,
    CASE
        WHEN io.AvgReadLatencyMs > dbo.fn_GetConfigInt('IOLatencyCriticalMs')
          OR io.AvgWriteLatencyMs > dbo.fn_GetConfigInt('IOLatencyCriticalMs') THEN 'CRITICAL'
        WHEN io.AvgReadLatencyMs > dbo.fn_GetConfigInt('IOLatencyWarningMs')
          OR io.AvgWriteLatencyMs > dbo.fn_GetConfigInt('IOLatencyWarningMs') THEN 'WARNING'
        ELSE 'OK'
    END AS LatencyStatus
FROM dbo.PerfSnapshotIOStats io
INNER JOIN dbo.PerfSnapshotRun r ON io.PerfSnapshotRunID = r.PerfSnapshotRunID
WHERE io.AvgReadLatencyMs > dbo.fn_GetConfigInt('IOLatencyWarningMs')
   OR io.AvgWriteLatencyMs > dbo.fn_GetConfigInt('IOLatencyWarningMs')
ORDER BY r.SnapshotUTC DESC,
    CASE WHEN io.AvgReadLatencyMs > io.AvgWriteLatencyMs
         THEN io.AvgReadLatencyMs
         ELSE io.AvgWriteLatencyMs END DESC
GO

PRINT 'Reporting views with timezone conversion created successfully'
PRINT '  - vw_LatestSnapshotSummary_ET'
PRINT '  - vw_BackupRiskAssessment_ET'
PRINT '  - vw_IOLatencyHotspots_ET'
GO
