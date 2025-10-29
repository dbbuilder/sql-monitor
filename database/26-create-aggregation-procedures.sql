-- =====================================================
-- Script: 26-create-aggregation-procedures.sql
-- Description: Cross-server aggregation stored procedures
-- Author: SQL Server Monitor Project
-- Date: 2025-10-28
-- Phase: 1.9 - Integration (Days 4-5)
-- Purpose: Efficient multi-server queries for API layer
-- =====================================================

PRINT '========================================================================='
PRINT 'Phase 1.9 Days 4-5: Cross-Server Aggregation Procedures'
PRINT '========================================================================='
PRINT ''
PRINT 'This script creates stored procedures for efficient cross-server queries:'
PRINT '  - Server health status'
PRINT '  - Metric aggregation (avg, min, max, percentiles)'
PRINT '  - Top N queries (worst performers across all servers)'
PRINT '  - Resource utilization trends'
PRINT ''
PRINT '========================================================================='
PRINT ''
GO

-- =====================================================
-- Procedure 1: Get Server Health Status
-- =====================================================

PRINT 'Creating procedure: usp_GetServerHealthStatus'
PRINT '-------------------------------------------'
GO

IF OBJECT_ID('dbo.usp_GetServerHealthStatus', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetServerHealthStatus
GO

CREATE PROCEDURE dbo.usp_GetServerHealthStatus
    @ServerID INT = NULL,         -- NULL = all servers
    @Environment NVARCHAR(50) = NULL,  -- Filter by environment
    @IncludeInactive BIT = 0      -- Include inactive servers
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        s.ServerID,
        s.ServerName,
        s.Environment,
        s.IsActive,
        s.CreatedUTC,
        s.LastModifiedUTC,

        -- Latest collection metrics
        psr_latest.SnapshotUTC AS LastCollectionTime,
        psr_latest.CpuSignalWaitPct AS LatestCpuPct,
        psr_latest.TopWaitType AS LatestTopWaitType,
        psr_latest.TopWaitMsPerSec AS LatestTopWaitMsPerSec,
        psr_latest.SessionsCount AS LatestSessionsCount,
        psr_latest.RequestsCount AS LatestRequestsCount,
        psr_latest.BlockingSessionCount AS LatestBlockingCount,

        -- Total snapshots collected
        snapshot_counts.TotalSnapshots,
        snapshot_counts.SnapshotsLast24Hours,

        -- 24-hour averages
        avg_24h.AvgCpuPct AS Avg24HrCpuPct,
        avg_24h.AvgSessions AS Avg24HrSessionsCount,
        avg_24h.AvgBlockingSessions AS Avg24HrBlockingCount,

        -- Health status
        CASE
            WHEN s.IsActive = 0 THEN 'Inactive'
            WHEN psr_latest.SnapshotUTC IS NULL THEN 'No Data'
            WHEN psr_latest.SnapshotUTC < DATEADD(MINUTE, -10, SYSUTCDATETIME()) THEN 'Stale'
            WHEN psr_latest.CpuSignalWaitPct > 80 THEN 'Critical'
            WHEN psr_latest.BlockingSessionCount > 5 THEN 'Warning'
            ELSE 'Healthy'
        END AS HealthStatus,

        -- Time since last collection
        DATEDIFF(MINUTE, psr_latest.SnapshotUTC, SYSUTCDATETIME()) AS MinutesSinceLastCollection

    FROM dbo.Servers s

    -- Latest snapshot
    OUTER APPLY (
        SELECT TOP 1 *
        FROM dbo.PerfSnapshotRun psr
        WHERE psr.ServerID = s.ServerID
        ORDER BY psr.SnapshotUTC DESC
    ) psr_latest

    -- Snapshot counts
    OUTER APPLY (
        SELECT
            COUNT(*) AS TotalSnapshots,
            SUM(CASE WHEN psr.SnapshotUTC >= DATEADD(HOUR, -24, SYSUTCDATETIME()) THEN 1 ELSE 0 END) AS SnapshotsLast24Hours
        FROM dbo.PerfSnapshotRun psr
        WHERE psr.ServerID = s.ServerID
    ) snapshot_counts

    -- 24-hour averages
    OUTER APPLY (
        SELECT
            AVG(psr.CpuSignalWaitPct) AS AvgCpuPct,
            AVG(CAST(psr.SessionsCount AS DECIMAL(18,2))) AS AvgSessions,
            AVG(CAST(psr.BlockingSessionCount AS DECIMAL(18,2))) AS AvgBlockingSessions
        FROM dbo.PerfSnapshotRun psr
        WHERE psr.ServerID = s.ServerID
          AND psr.SnapshotUTC >= DATEADD(HOUR, -24, SYSUTCDATETIME())
    ) avg_24h

    WHERE (@ServerID IS NULL OR s.ServerID = @ServerID)
      AND (@Environment IS NULL OR s.Environment = @Environment)
      AND (@IncludeInactive = 1 OR s.IsActive = 1)

    ORDER BY
        CASE
            WHEN s.IsActive = 0 THEN 3
            WHEN psr_latest.SnapshotUTC < DATEADD(MINUTE, -10, SYSUTCDATETIME()) THEN 2
            WHEN psr_latest.CpuSignalWaitPct > 80 OR psr_latest.BlockingSessionCount > 5 THEN 1
            ELSE 4
        END,
        s.ServerName;
END
GO

PRINT '  ✓ Created procedure: dbo.usp_GetServerHealthStatus'
PRINT ''
GO

-- =====================================================
-- Procedure 2: Get Metric History (with aggregation)
-- =====================================================

PRINT 'Creating procedure: usp_GetMetricHistory'
PRINT '-------------------------------------------'
GO

IF OBJECT_ID('dbo.usp_GetMetricHistory', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetMetricHistory
GO

CREATE PROCEDURE dbo.usp_GetMetricHistory
    @ServerID INT = NULL,             -- NULL = all servers
    @MetricCategory NVARCHAR(50) = NULL,  -- Filter by category
    @MetricName NVARCHAR(100) = NULL,     -- Filter by metric name
    @StartDate DATETIME2 = NULL,      -- Default: 24 hours ago
    @EndDate DATETIME2 = NULL,        -- Default: now
    @Granularity VARCHAR(20) = 'RAW'  -- RAW, HOURLY, DAILY
AS
BEGIN
    SET NOCOUNT ON;

    -- Default date range
    SET @StartDate = ISNULL(@StartDate, DATEADD(HOUR, -24, SYSUTCDATETIME()));
    SET @EndDate = ISNULL(@EndDate, SYSUTCDATETIME());

    IF @Granularity = 'RAW'
    BEGIN
        -- Return raw metrics (no aggregation)
        SELECT
            MetricID,
            ServerID,
            CollectionTime,
            MetricCategory,
            MetricName,
            MetricValue,
            ServerName,
            MetricSource
        FROM dbo.vw_PerformanceMetrics_Unified
        WHERE CollectionTime >= @StartDate
          AND CollectionTime <= @EndDate
          AND (@ServerID IS NULL OR ServerID = @ServerID)
          AND (@MetricCategory IS NULL OR MetricCategory = @MetricCategory)
          AND (@MetricName IS NULL OR MetricName = @MetricName)
        ORDER BY CollectionTime DESC, ServerName, MetricCategory, MetricName;
    END
    ELSE IF @Granularity = 'HOURLY'
    BEGIN
        -- Hourly aggregation
        SELECT
            ServerID,
            ServerName,
            MetricCategory,
            MetricName,
            MetricSource,
            DATEADD(HOUR, DATEDIFF(HOUR, 0, CollectionTime), 0) AS HourBucket,
            COUNT(*) AS DataPoints,
            AVG(MetricValue) AS AvgValue,
            MIN(MetricValue) AS MinValue,
            MAX(MetricValue) AS MaxValue,
            STDEV(MetricValue) AS StdDevValue
        FROM dbo.vw_PerformanceMetrics_Unified
        WHERE CollectionTime >= @StartDate
          AND CollectionTime <= @EndDate
          AND (@ServerID IS NULL OR ServerID = @ServerID)
          AND (@MetricCategory IS NULL OR MetricCategory = @MetricCategory)
          AND (@MetricName IS NULL OR MetricName = @MetricName)
        GROUP BY
            ServerID,
            ServerName,
            MetricCategory,
            MetricName,
            MetricSource,
            DATEADD(HOUR, DATEDIFF(HOUR, 0, CollectionTime), 0)
        ORDER BY HourBucket DESC, ServerName, MetricCategory, MetricName;
    END
    ELSE IF @Granularity = 'DAILY'
    BEGIN
        -- Daily aggregation
        SELECT
            ServerID,
            ServerName,
            MetricCategory,
            MetricName,
            MetricSource,
            CAST(CollectionTime AS DATE) AS DayBucket,
            COUNT(*) AS DataPoints,
            AVG(MetricValue) AS AvgValue,
            MIN(MetricValue) AS MinValue,
            MAX(MetricValue) AS MaxValue,
            STDEV(MetricValue) AS StdDevValue
        FROM dbo.vw_PerformanceMetrics_Unified
        WHERE CollectionTime >= @StartDate
          AND CollectionTime <= @EndDate
          AND (@ServerID IS NULL OR ServerID = @ServerID)
          AND (@MetricCategory IS NULL OR MetricCategory = @MetricCategory)
          AND (@MetricName IS NULL OR MetricName = @MetricName)
        GROUP BY
            ServerID,
            ServerName,
            MetricCategory,
            MetricName,
            MetricSource,
            CAST(CollectionTime AS DATE)
        ORDER BY DayBucket DESC, ServerName, MetricCategory, MetricName;
    END
END
GO

PRINT '  ✓ Created procedure: dbo.usp_GetMetricHistory'
PRINT ''
GO

-- =====================================================
-- Procedure 3: Get Top Queries (Cross-Server)
-- =====================================================

PRINT 'Creating procedure: usp_GetTopQueries'
PRINT '-------------------------------------------'
GO

IF OBJECT_ID('dbo.usp_GetTopQueries', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetTopQueries
GO

CREATE PROCEDURE dbo.usp_GetTopQueries
    @ServerID INT = NULL,           -- NULL = all servers
    @OrderBy VARCHAR(50) = 'TotalCpu',  -- TotalCpu, AvgCpu, TotalReads, AvgDuration
    @TopN INT = 50,                 -- Number of queries to return
    @MinExecutionCount INT = 10     -- Minimum executions to include
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH QueryStats AS (
        SELECT
            psr.ServerID,
            psr.ServerName,
            qs.DatabaseName,
            qs.ObjectName,
            qs.SqlText,
            qs.ExecutionCount,
            qs.TotalCpuMs,
            qs.AvgCpuMs,
            qs.MaxCpuMs,
            qs.TotalLogicalReads,
            qs.AvgLogicalReads,
            qs.TotalDurationMs,
            qs.AvgDurationMs,
            qs.MaxDurationMs,
            psr.SnapshotUTC AS CollectionTime,
            ROW_NUMBER() OVER (
                PARTITION BY psr.ServerID, qs.QueryHash
                ORDER BY psr.SnapshotUTC DESC
            ) AS RowNum
        FROM dbo.PerfSnapshotQueryStats qs
        INNER JOIN dbo.PerfSnapshotRun psr ON qs.PerfSnapshotRunID = psr.PerfSnapshotRunID
        WHERE (@ServerID IS NULL OR psr.ServerID = @ServerID)
          AND qs.ExecutionCount >= @MinExecutionCount
    )
    SELECT TOP (@TopN)
        ServerID,
        ServerName,
        DatabaseName,
        ObjectName,
        LEFT(SqlText, 200) AS SqlText,  -- Truncate for display
        ExecutionCount,
        TotalCpuMs,
        AvgCpuMs,
        MaxCpuMs,
        TotalLogicalReads,
        AvgLogicalReads,
        TotalDurationMs,
        AvgDurationMs,
        MaxDurationMs,
        CollectionTime
    FROM QueryStats
    WHERE RowNum = 1  -- Most recent collection per query
    ORDER BY
        CASE @OrderBy
            WHEN 'TotalCpu' THEN TotalCpuMs
            WHEN 'AvgCpu' THEN AvgCpuMs
            WHEN 'TotalReads' THEN TotalLogicalReads
            WHEN 'AvgDuration' THEN AvgDurationMs
            ELSE TotalCpuMs
        END DESC;
END
GO

PRINT '  ✓ Created procedure: dbo.usp_GetTopQueries'
PRINT ''
GO

-- =====================================================
-- Procedure 4: Get Resource Utilization Trends
-- =====================================================

PRINT 'Creating procedure: usp_GetResourceTrends'
PRINT '-------------------------------------------'
GO

IF OBJECT_ID('dbo.usp_GetResourceTrends', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetResourceTrends
GO

CREATE PROCEDURE dbo.usp_GetResourceTrends
    @ServerID INT = NULL,        -- NULL = all servers
    @Days INT = 7                -- Number of days of history
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartDate DATETIME2 = DATEADD(DAY, -@Days, SYSUTCDATETIME());

    SELECT
        s.ServerID,
        s.ServerName,
        s.Environment,
        CAST(psr.SnapshotUTC AS DATE) AS CollectionDate,

        -- CPU metrics
        AVG(psr.CpuSignalWaitPct) AS AvgCpuPct,
        MAX(psr.CpuSignalWaitPct) AS MaxCpuPct,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY psr.CpuSignalWaitPct) AS P95CpuPct,

        -- Session metrics
        AVG(CAST(psr.SessionsCount AS DECIMAL(18,2))) AS AvgSessionsCount,
        MAX(psr.SessionsCount) AS MaxSessionsCount,

        -- Blocking metrics
        AVG(CAST(psr.BlockingSessionCount AS DECIMAL(18,2))) AS AvgBlockingCount,
        MAX(psr.BlockingSessionCount) AS MaxBlockingCount,

        -- Data points
        COUNT(*) AS DataPoints

    FROM dbo.Servers s
    INNER JOIN dbo.PerfSnapshotRun psr ON s.ServerID = psr.ServerID
    WHERE psr.SnapshotUTC >= @StartDate
      AND (@ServerID IS NULL OR s.ServerID = @ServerID)
      AND s.IsActive = 1
    GROUP BY
        s.ServerID,
        s.ServerName,
        s.Environment,
        CAST(psr.SnapshotUTC AS DATE)
    ORDER BY
        s.ServerName,
        CollectionDate DESC;
END
GO

PRINT '  ✓ Created procedure: dbo.usp_GetResourceTrends'
PRINT ''
GO

-- =====================================================
-- Procedure 5: Get Database Summary (Cross-Server)
-- =====================================================

PRINT 'Creating procedure: usp_GetDatabaseSummary'
PRINT '-------------------------------------------'
GO

IF OBJECT_ID('dbo.usp_GetDatabaseSummary', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetDatabaseSummary
GO

CREATE PROCEDURE dbo.usp_GetDatabaseSummary
    @ServerID INT = NULL,           -- NULL = all servers
    @DatabaseName SYSNAME = NULL    -- Filter by database name
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH LatestSnapshots AS (
        SELECT
            psd.PerfSnapshotRunID,
            psr.ServerID,
            psr.ServerName,
            psd.DatabaseName,
            psd.DataSizeMB,
            psd.LogSizeMB,
            psd.LogUsedPct,
            psd.RecoveryModel,
            psd.State,
            psd.LastFullBackupUTC,
            psd.LastLogBackupUTC,
            psr.SnapshotUTC,
            ROW_NUMBER() OVER (
                PARTITION BY psr.ServerID, psd.DatabaseName
                ORDER BY psr.SnapshotUTC DESC
            ) AS RowNum
        FROM dbo.PerfSnapshotDB psd
        INNER JOIN dbo.PerfSnapshotRun psr ON psd.PerfSnapshotRunID = psr.PerfSnapshotRunID
        WHERE (@ServerID IS NULL OR psr.ServerID = @ServerID)
          AND (@DatabaseName IS NULL OR psd.DatabaseName = @DatabaseName)
    )
    SELECT
        ServerID,
        ServerName,
        DatabaseName,
        DataSizeMB,
        LogSizeMB,
        DataSizeMB + LogSizeMB AS TotalSizeMB,
        LogUsedPct,
        RecoveryModel,
        State,
        LastFullBackupUTC,
        LastLogBackupUTC,
        DATEDIFF(HOUR, LastFullBackupUTC, SYSUTCDATETIME()) AS HoursSinceLastFullBackup,
        DATEDIFF(HOUR, LastLogBackupUTC, SYSUTCDATETIME()) AS HoursSinceLastLogBackup,
        SnapshotUTC AS LastCollectionTime,

        -- Backup health status
        CASE
            WHEN LastFullBackupUTC IS NULL THEN 'No Full Backup'
            WHEN DATEDIFF(HOUR, LastFullBackupUTC, SYSUTCDATETIME()) > 24 THEN 'Full Backup Overdue'
            WHEN RecoveryModel IN ('FULL', 'BULK_LOGGED') AND
                 (LastLogBackupUTC IS NULL OR DATEDIFF(HOUR, LastLogBackupUTC, SYSUTCDATETIME()) > 1) THEN 'Log Backup Overdue'
            ELSE 'Healthy'
        END AS BackupHealthStatus

    FROM LatestSnapshots
    WHERE RowNum = 1
    ORDER BY
        CASE
            WHEN LastFullBackupUTC IS NULL THEN 1
            WHEN DATEDIFF(HOUR, LastFullBackupUTC, SYSUTCDATETIME()) > 24 THEN 2
            ELSE 3
        END,
        ServerName,
        DatabaseName;
END
GO

PRINT '  ✓ Created procedure: dbo.usp_GetDatabaseSummary'
PRINT ''
GO

-- =====================================================
-- Summary
-- =====================================================

PRINT '========================================================================='
PRINT 'Cross-Server Aggregation Procedures Complete'
PRINT '========================================================================='
PRINT ''
PRINT 'Procedures Created:'
PRINT '  1. usp_GetServerHealthStatus - Server health with 24hr averages'
PRINT '  2. usp_GetMetricHistory - Time-series metrics (RAW/HOURLY/DAILY)'
PRINT '  3. usp_GetTopQueries - Top N queries across all servers'
PRINT '  4. usp_GetResourceTrends - CPU/Sessions/Blocking trends by day'
PRINT '  5. usp_GetDatabaseSummary - Database size and backup status'
PRINT ''
PRINT 'Usage Examples:'
PRINT ''
PRINT '  -- Get health status for all servers'
PRINT '  EXEC dbo.usp_GetServerHealthStatus;'
PRINT ''
PRINT '  -- Get CPU metrics for last 7 days (hourly aggregation)'
PRINT '  EXEC dbo.usp_GetMetricHistory'
PRINT '      @MetricCategory = ''CPU'','
PRINT '      @MetricName = ''CpuSignalWaitPct'','
PRINT '      @StartDate = ''2025-10-21'','
PRINT '      @Granularity = ''HOURLY'';'
PRINT ''
PRINT '  -- Get top 25 queries by total CPU (all servers)'
PRINT '  EXEC dbo.usp_GetTopQueries @TopN = 25, @OrderBy = ''TotalCpu'';'
PRINT ''
PRINT '  -- Get 30-day resource trends for specific server'
PRINT '  EXEC dbo.usp_GetResourceTrends @ServerID = 1, @Days = 30;'
PRINT ''
PRINT '  -- Get database summary with backup status'
PRINT '  EXEC dbo.usp_GetDatabaseSummary;'
PRINT ''
PRINT '========================================================================='
PRINT ''
GO
