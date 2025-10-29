-- =============================================
-- File: 11_create_reporting_views_and_procedures.sql
-- Purpose: Create useful reporting views and diagnostic stored procedures
-- Created: 2025-10-27
-- =============================================

USE DBATools
GO

PRINT 'Creating reporting views and diagnostic procedures...'
GO

-- =============================================
-- SECTION 1: SUMMARY VIEWS
-- =============================================

-- View: Current System Health Overview
PRINT 'Creating vw_SystemHealthCurrent...'
GO

CREATE OR ALTER VIEW dbo.vw_SystemHealthCurrent
AS
    SELECT TOP 1
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
    ORDER BY r.PerfSnapshotRunID DESC
GO

-- View: Last 24 Hours System Health Trend
PRINT 'Creating vw_SystemHealthLast24Hours...'
GO

CREATE OR ALTER VIEW dbo.vw_SystemHealthLast24Hours
AS
    SELECT
        r.PerfSnapshotRunID,
        r.SnapshotUTC,
        r.CpuSignalWaitPct,
        r.TopWaitType,
        r.SessionsCount,
        r.RequestsCount,
        r.BlockingSessionCount,
        r.DeadlockCountRecent,
        CASE
            WHEN r.CpuSignalWaitPct > 40 OR r.BlockingSessionCount > 20 OR r.DeadlockCountRecent > 5
            THEN 'ISSUE'
            ELSE 'OK'
        END AS Status
    FROM dbo.PerfSnapshotRun r
    WHERE r.SnapshotUTC >= DATEADD(HOUR, -24, SYSUTCDATETIME())
GO

-- View: Top Slowest Queries (All Time)
PRINT 'Creating vw_TopSlowestQueries...'
GO

CREATE OR ALTER VIEW dbo.vw_TopSlowestQueries
AS
    SELECT TOP 100
        qs.DatabaseName,
        qs.SqlText,
        qs.QueryHash,
        qs.ExecutionCount,
        qs.AvgCpuMs,
        qs.AvgLogicalReads,
        qs.AvgElapsedMs,
        qs.TotalCpuMs,
        qs.TotalLogicalReads,
        qs.TotalElapsedMs,
        -- Impact score: execution count × average elapsed time
        (qs.ExecutionCount * qs.AvgElapsedMs) AS ImpactScore,
        r.SnapshotUTC AS CapturedAt,
        r.PerfSnapshotRunID
    FROM dbo.PerfSnapshotQueryStats qs
    INNER JOIN dbo.PerfSnapshotRun r ON qs.PerfSnapshotRunID = r.PerfSnapshotRunID
    ORDER BY qs.AvgElapsedMs DESC
GO

-- View: Top CPU Consuming Queries
PRINT 'Creating vw_TopCpuQueries...'
GO

CREATE OR ALTER VIEW dbo.vw_TopCpuQueries
AS
    SELECT TOP 100
        qs.DatabaseName,
        qs.SqlText,
        qs.QueryHash,
        qs.ExecutionCount,
        qs.AvgCpuMs,
        qs.TotalCpuMs,
        qs.AvgElapsedMs,
        (qs.ExecutionCount * qs.AvgCpuMs) AS CpuImpactScore,
        r.SnapshotUTC AS CapturedAt
    FROM dbo.PerfSnapshotQueryStats qs
    INNER JOIN dbo.PerfSnapshotRun r ON qs.PerfSnapshotRunID = r.PerfSnapshotRunID
    ORDER BY qs.TotalCpuMs DESC
GO

-- View: Top Missing Indexes by Impact
PRINT 'Creating vw_TopMissingIndexes...'
GO

CREATE OR ALTER VIEW dbo.vw_TopMissingIndexes
AS
    SELECT TOP 50
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
        r.SnapshotUTC AS CapturedAt,
        -- Generate CREATE INDEX statement
        'CREATE NONCLUSTERED INDEX [IX_' +
            REPLACE(REPLACE(mi.ObjectName, '[', ''), ']', '') + '_' +
            CAST(CHECKSUM(mi.EqualityColumns, mi.InequalityColumns) AS VARCHAR(20)) +
            '] ON ' + mi.ObjectName +
            ' (' + ISNULL(mi.EqualityColumns, '') +
            CASE WHEN mi.EqualityColumns IS NOT NULL AND mi.InequalityColumns IS NOT NULL THEN ', ' ELSE '' END +
            ISNULL(mi.InequalityColumns, '') + ')' +
            CASE WHEN mi.IncludedColumns IS NOT NULL
                 THEN ' INCLUDE (' + mi.IncludedColumns + ')'
                 ELSE ''
            END AS CreateIndexStatement
    FROM dbo.PerfSnapshotMissingIndexes mi
    INNER JOIN dbo.PerfSnapshotRun r ON mi.PerfSnapshotRunID = r.PerfSnapshotRunID
    ORDER BY mi.ImpactScore DESC
GO

-- View: Top Wait Statistics
PRINT 'Creating vw_TopWaitStats...'
GO

CREATE OR ALTER VIEW dbo.vw_TopWaitStats
AS
    SELECT TOP 50
        ws.WaitType,
        SUM(ws.WaitTimeMs) AS TotalWaitTimeMs,
        SUM(ws.WaitingTasksCount) AS TotalWaitingTasks,
        AVG(ws.WaitTimeMs) AS AvgWaitTimeMs,
        COUNT(DISTINCT ws.PerfSnapshotRunID) AS SnapshotCount,
        MAX(r.SnapshotUTC) AS LastSeenAt,
        -- Common wait type descriptions
        CASE
            WHEN ws.WaitType LIKE 'PAGEIOLATCH%' THEN 'Disk I/O - Check for slow storage'
            WHEN ws.WaitType LIKE 'LCK_M%' THEN 'Lock contention - Review blocking queries'
            WHEN ws.WaitType LIKE 'CXPACKET%' THEN 'Parallelism - Consider MAXDOP tuning'
            WHEN ws.WaitType LIKE 'SOS_SCHEDULER_YIELD%' THEN 'CPU pressure - High CPU workload'
            WHEN ws.WaitType LIKE 'ASYNC_NETWORK_IO%' THEN 'Network - Slow client or large result sets'
            WHEN ws.WaitType LIKE 'WRITELOG%' THEN 'Transaction log writes - Check log disk performance'
            ELSE 'See SQL Server documentation'
        END AS WaitTypeDescription
    FROM dbo.PerfSnapshotWaitStats ws
    INNER JOIN dbo.PerfSnapshotRun r ON ws.PerfSnapshotRunID = r.PerfSnapshotRunID
    GROUP BY ws.WaitType
    ORDER BY SUM(ws.WaitTimeMs) DESC
GO

-- View: Database Growth Trend
PRINT 'Creating vw_DatabaseGrowthTrend...'
GO

CREATE OR ALTER VIEW dbo.vw_DatabaseGrowthTrend
AS
    SELECT
        db.DatabaseName,
        db.TotalSizeMB,
        db.DataFileSizeMB,
        db.LogFileSizeMB,
        r.SnapshotUTC,
        r.PerfSnapshotRunID,
        -- Calculate growth from previous snapshot (if available)
        LAG(db.TotalSizeMB) OVER (PARTITION BY db.DatabaseName ORDER BY r.SnapshotUTC) AS PreviousSizeMB,
        db.TotalSizeMB - LAG(db.TotalSizeMB) OVER (PARTITION BY db.DatabaseName ORDER BY r.SnapshotUTC) AS GrowthMB,
        CASE
            WHEN LAG(db.TotalSizeMB) OVER (PARTITION BY db.DatabaseName ORDER BY r.SnapshotUTC) IS NOT NULL
            THEN CAST((db.TotalSizeMB - LAG(db.TotalSizeMB) OVER (PARTITION BY db.DatabaseName ORDER BY r.SnapshotUTC)) /
                 NULLIF(DATEDIFF(HOUR, LAG(r.SnapshotUTC) OVER (PARTITION BY db.DatabaseName ORDER BY r.SnapshotUTC), r.SnapshotUTC), 0)
                 AS DECIMAL(10,2))
            ELSE NULL
        END AS GrowthMBPerHour
    FROM dbo.PerfSnapshotDB db
    INNER JOIN dbo.PerfSnapshotRun r ON db.PerfSnapshotRunID = r.PerfSnapshotRunID
GO

-- =============================================
-- SECTION 2: DIAGNOSTIC STORED PROCEDURES
-- =============================================

-- Procedure: Get System Health Report
PRINT 'Creating DBA_GetSystemHealthReport...'
GO

CREATE OR ALTER PROCEDURE dbo.DBA_GetSystemHealthReport
    @HoursBack INT = 24
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @StartTime DATETIME2(3) = DATEADD(HOUR, -@HoursBack, SYSUTCDATETIME())

    -- Summary statistics
    SELECT
        'Summary' AS ReportSection,
        COUNT(*) AS TotalSnapshots,
        AVG(CpuSignalWaitPct) AS AvgCpuSignalWaitPct,
        MAX(CpuSignalWaitPct) AS MaxCpuSignalWaitPct,
        AVG(CAST(BlockingSessionCount AS FLOAT)) AS AvgBlockingSessions,
        MAX(BlockingSessionCount) AS MaxBlockingSessions,
        SUM(DeadlockCountRecent) AS TotalDeadlocks,
        MAX(SessionsCount) AS PeakSessions,
        MAX(RequestsCount) AS PeakRequests
    FROM dbo.PerfSnapshotRun
    WHERE SnapshotUTC >= @StartTime

    -- Issues found (high CPU, blocking, deadlocks)
    SELECT
        'Issues' AS ReportSection,
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
        END AS IssueType
    FROM dbo.PerfSnapshotRun
    WHERE SnapshotUTC >= @StartTime
      AND (CpuSignalWaitPct > 40
           OR BlockingSessionCount > 20
           OR DeadlockCountRecent > 0)
    ORDER BY SnapshotUTC DESC

    -- Top wait types in time window
    SELECT TOP 10
        'TopWaits' AS ReportSection,
        ws.WaitType,
        SUM(ws.WaitTimeMs) AS TotalWaitTimeMs,
        SUM(ws.WaitingTasksCount) AS TotalWaitingTasks,
        COUNT(DISTINCT ws.PerfSnapshotRunID) AS ObservationCount
    FROM dbo.PerfSnapshotWaitStats ws
    INNER JOIN dbo.PerfSnapshotRun r ON ws.PerfSnapshotRunID = r.PerfSnapshotRunID
    WHERE r.SnapshotUTC >= @StartTime
    GROUP BY ws.WaitType
    ORDER BY SUM(ws.WaitTimeMs) DESC
END
GO

-- Procedure: Find Slow Queries by Database
PRINT 'Creating DBA_FindSlowQueries...'
GO

CREATE OR ALTER PROCEDURE dbo.DBA_FindSlowQueries
    @DatabaseName SYSNAME = NULL,
    @MinAvgElapsedMs INT = 1000,
    @TopN INT = 20
AS
BEGIN
    SET NOCOUNT ON

    SELECT TOP (@TopN)
        qs.DatabaseName,
        qs.SqlText,
        qs.ExecutionCount,
        qs.AvgElapsedMs,
        qs.AvgCpuMs,
        qs.AvgLogicalReads,
        qs.TotalElapsedMs,
        qs.TotalCpuMs,
        (qs.ExecutionCount * qs.AvgElapsedMs) AS ImpactScore,
        r.SnapshotUTC AS CapturedAt,
        qs.QueryHash,
        qs.QueryPlanHash
    FROM dbo.PerfSnapshotQueryStats qs
    INNER JOIN dbo.PerfSnapshotRun r ON qs.PerfSnapshotRunID = r.PerfSnapshotRunID
    WHERE qs.AvgElapsedMs >= @MinAvgElapsedMs
      AND (@DatabaseName IS NULL OR qs.DatabaseName = @DatabaseName)
    ORDER BY qs.AvgElapsedMs DESC
END
GO

-- Procedure: Find Blocking History
PRINT 'Creating DBA_FindBlockingHistory...'
GO

CREATE OR ALTER PROCEDURE dbo.DBA_FindBlockingHistory
    @HoursBack INT = 24,
    @MinBlockingCount INT = 10
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @StartTime DATETIME2(3) = DATEADD(HOUR, -@HoursBack, SYSUTCDATETIME())

    -- Summary of blocking periods
    SELECT
        r.SnapshotUTC,
        r.BlockingSessionCount,
        r.SessionsCount,
        r.RequestsCount,
        r.TopWaitType,
        CAST((r.BlockingSessionCount * 100.0 / NULLIF(r.RequestsCount, 0)) AS DECIMAL(5,2)) AS BlockingPct
    FROM dbo.PerfSnapshotRun r
    WHERE r.SnapshotUTC >= @StartTime
      AND r.BlockingSessionCount >= @MinBlockingCount
    ORDER BY r.BlockingSessionCount DESC, r.SnapshotUTC DESC
END
GO

-- Procedure: Get Database Growth Report
PRINT 'Creating DBA_GetDatabaseGrowthReport...'
GO

CREATE OR ALTER PROCEDURE dbo.DBA_GetDatabaseGrowthReport
    @DatabaseName SYSNAME = NULL,
    @DaysBack INT = 7
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @StartTime DATETIME2(3) = DATEADD(DAY, -@DaysBack, SYSUTCDATETIME())

    ;WITH GrowthData AS
    (
        SELECT
            db.DatabaseName,
            db.TotalSizeMB,
            db.DataFileSizeMB,
            db.LogFileSizeMB,
            r.SnapshotUTC,
            FIRST_VALUE(db.TotalSizeMB) OVER (PARTITION BY db.DatabaseName ORDER BY r.SnapshotUTC) AS FirstSizeMB,
            FIRST_VALUE(r.SnapshotUTC) OVER (PARTITION BY db.DatabaseName ORDER BY r.SnapshotUTC) AS FirstSnapshot,
            ROW_NUMBER() OVER (PARTITION BY db.DatabaseName ORDER BY r.SnapshotUTC DESC) AS RowNum
        FROM dbo.PerfSnapshotDB db
        INNER JOIN dbo.PerfSnapshotRun r ON db.PerfSnapshotRunID = r.PerfSnapshotRunID
        WHERE r.SnapshotUTC >= @StartTime
          AND (@DatabaseName IS NULL OR db.DatabaseName = @DatabaseName)
    )
    SELECT
        DatabaseName,
        TotalSizeMB AS CurrentSizeMB,
        DataFileSizeMB AS CurrentDataMB,
        LogFileSizeMB AS CurrentLogMB,
        FirstSizeMB AS StartingSizeMB,
        (TotalSizeMB - FirstSizeMB) AS GrowthMB,
        CAST((TotalSizeMB - FirstSizeMB) * 100.0 / NULLIF(FirstSizeMB, 0) AS DECIMAL(10,2)) AS GrowthPct,
        DATEDIFF(HOUR, FirstSnapshot, SnapshotUTC) AS HoursObserved,
        CASE
            WHEN DATEDIFF(HOUR, FirstSnapshot, SnapshotUTC) > 0
            THEN CAST((TotalSizeMB - FirstSizeMB) / DATEDIFF(HOUR, FirstSnapshot, SnapshotUTC) AS DECIMAL(10,2))
            ELSE 0
        END AS AvgGrowthMBPerHour
    FROM GrowthData
    WHERE RowNum = 1
    ORDER BY GrowthMB DESC
END
GO

-- Procedure: Get Missing Index Recommendations
PRINT 'Creating DBA_GetMissingIndexRecommendations...'
GO

CREATE OR ALTER PROCEDURE dbo.DBA_GetMissingIndexRecommendations
    @DatabaseName SYSNAME = NULL,
    @MinImpactScore FLOAT = 1000,
    @TopN INT = 20
AS
BEGIN
    SET NOCOUNT ON

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
        WHERE mi.ImpactScore >= @MinImpactScore
          AND (@DatabaseName IS NULL OR mi.DatabaseName = @DatabaseName)
    )
    SELECT TOP (@TopN)
        DatabaseName,
        ObjectName,
        EqualityColumns,
        InequalityColumns,
        IncludedColumns,
        UserSeeks,
        UserScans,
        CAST(AvgTotalUserCost AS DECIMAL(10,2)) AS AvgCost,
        CAST(AvgUserImpact AS DECIMAL(10,2)) AS AvgImpact,
        CAST(ImpactScore AS DECIMAL(15,2)) AS ImpactScore,
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
END
GO

-- Procedure: Get Wait Statistics Breakdown
PRINT 'Creating DBA_GetWaitStatsBreakdown...'
GO

CREATE OR ALTER PROCEDURE dbo.DBA_GetWaitStatsBreakdown
    @HoursBack INT = 24,
    @TopN INT = 20
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @StartTime DATETIME2(3) = DATEADD(HOUR, -@HoursBack, SYSUTCDATETIME())

    SELECT TOP (@TopN)
        ws.WaitType,
        COUNT(DISTINCT ws.PerfSnapshotRunID) AS ObservationCount,
        SUM(ws.WaitTimeMs) AS TotalWaitTimeMs,
        SUM(ws.WaitingTasksCount) AS TotalWaitingTasks,
        AVG(ws.WaitTimeMs) AS AvgWaitTimeMs,
        MAX(ws.WaitTimeMs) AS MaxWaitTimeMs,
        MIN(r.SnapshotUTC) AS FirstSeen,
        MAX(r.SnapshotUTC) AS LastSeen,
        -- Calculate percentage of total wait time
        CAST(SUM(ws.WaitTimeMs) * 100.0 /
             SUM(SUM(ws.WaitTimeMs)) OVER () AS DECIMAL(5,2)) AS PctOfTotalWaits
    FROM dbo.PerfSnapshotWaitStats ws
    INNER JOIN dbo.PerfSnapshotRun r ON ws.PerfSnapshotRunID = r.PerfSnapshotRunID
    WHERE r.SnapshotUTC >= @StartTime
    GROUP BY ws.WaitType
    ORDER BY SUM(ws.WaitTimeMs) DESC
END
GO

-- Procedure: Check System Health (Quick diagnostic)
PRINT 'Creating DBA_CheckSystemHealth...'
GO

CREATE OR ALTER PROCEDURE dbo.DBA_CheckSystemHealth
AS
BEGIN
    SET NOCOUNT ON

    -- Current status
    SELECT
        'CURRENT STATUS' AS Section,
        *
    FROM dbo.vw_SystemHealthCurrent

    -- Recent issues (last hour)
    SELECT
        'RECENT ISSUES (Last Hour)' AS Section,
        SnapshotUTC,
        CpuSignalWaitPct,
        BlockingSessionCount,
        DeadlockCountRecent,
        TopWaitType
    FROM dbo.PerfSnapshotRun
    WHERE SnapshotUTC >= DATEADD(HOUR, -1, SYSUTCDATETIME())
      AND (CpuSignalWaitPct > 20
           OR BlockingSessionCount > 10
           OR DeadlockCountRecent > 0)
    ORDER BY SnapshotUTC DESC

    -- Top 5 slowest queries (recent)
    SELECT TOP 5
        'TOP 5 SLOWEST QUERIES' AS Section,
        DatabaseName,
        LEFT(SqlText, 100) AS SqlTextPreview,
        AvgElapsedMs,
        ExecutionCount,
        (ExecutionCount * AvgElapsedMs) AS ImpactScore
    FROM dbo.PerfSnapshotQueryStats qs
    INNER JOIN dbo.PerfSnapshotRun r ON qs.PerfSnapshotRunID = r.PerfSnapshotRunID
    WHERE r.SnapshotUTC >= DATEADD(HOUR, -1, SYSUTCDATETIME())
    ORDER BY qs.AvgElapsedMs DESC

    -- Top 5 missing indexes
    SELECT TOP 5
        'TOP 5 MISSING INDEXES' AS Section,
        DatabaseName,
        ObjectName,
        ImpactScore,
        EqualityColumns,
        IncludedColumns
    FROM dbo.PerfSnapshotMissingIndexes mi
    INNER JOIN dbo.PerfSnapshotRun r ON mi.PerfSnapshotRunID = r.PerfSnapshotRunID
    WHERE r.SnapshotUTC >= DATEADD(HOUR, -1, SYSUTCDATETIME())
    ORDER BY mi.ImpactScore DESC
END
GO

PRINT ''
PRINT '=========================================='
PRINT 'Reporting Views and Procedures Created Successfully'
PRINT '=========================================='
PRINT ''
PRINT 'VIEWS:'
PRINT '  - vw_SystemHealthCurrent (current health snapshot)'
PRINT '  - vw_SystemHealthLast24Hours (24-hour trend)'
PRINT '  - vw_TopSlowestQueries (all-time slowest)'
PRINT '  - vw_TopCpuQueries (CPU intensive queries)'
PRINT '  - vw_TopMissingIndexes (index recommendations with CREATE statements)'
PRINT '  - vw_TopWaitStats (wait type summary)'
PRINT '  - vw_DatabaseGrowthTrend (size growth over time)'
PRINT ''
PRINT 'PROCEDURES:'
PRINT '  - DBA_CheckSystemHealth (quick diagnostic - run first!)'
PRINT '  - DBA_GetSystemHealthReport @HoursBack=24'
PRINT '  - DBA_FindSlowQueries @DatabaseName=NULL, @MinAvgElapsedMs=1000, @TopN=20'
PRINT '  - DBA_FindBlockingHistory @HoursBack=24, @MinBlockingCount=10'
PRINT '  - DBA_GetDatabaseGrowthReport @DatabaseName=NULL, @DaysBack=7'
PRINT '  - DBA_GetMissingIndexRecommendations @DatabaseName=NULL, @MinImpactScore=1000, @TopN=20'
PRINT '  - DBA_GetWaitStatsBreakdown @HoursBack=24, @TopN=20'
PRINT ''
PRINT 'QUICK START:'
PRINT '  EXEC DBA_CheckSystemHealth  -- Overall health check'
PRINT '  SELECT * FROM vw_SystemHealthCurrent  -- Current status'
PRINT '  EXEC DBA_FindSlowQueries @TopN=10  -- Top 10 slow queries'
PRINT '  EXEC DBA_GetMissingIndexRecommendations @TopN=10  -- Index suggestions'
PRINT ''
GO
