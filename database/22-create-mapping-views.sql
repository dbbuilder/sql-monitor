-- =====================================================
-- Script: 22-create-mapping-views.sql
-- Description: Schema unification views (WIDE → TALL transformation)
-- Author: SQL Server Monitor Project
-- Date: 2025-10-28
-- Phase: 1.9 - Integration (Day 2)
-- Purpose: Transform sql-monitor-agent WIDE schema → sql-monitor TALL schema
-- =====================================================

-- This script creates views that map between:
--   - sql-monitor-agent schema (WIDE: many typed columns per row)
--   - sql-monitor API schema (TALL: one metric per row)
--
-- Key Design Patterns:
--   1. CROSS APPLY unpivoting for WIDE → TALL transformation
--   2. ServerID NULL → 0 for backward compatibility
--   3. MetricID generation: (RunID * 1000) + MetricOrdinal
--   4. UNION ALL for combining multiple sources
--   5. Aggregation views for API consumption

PRINT '========================================================================='
PRINT 'Phase 1.9 Day 2: Creating Schema Mapping Views'
PRINT '========================================================================='
PRINT ''
GO

USE [DBATools]  -- Works in both DBATools and MonitoringDB
GO

-- =====================================================
-- View 1: vw_PerformanceMetrics_Core
-- Purpose: Unpivot PerfSnapshotRun (core metrics)
-- Transforms: 1 PerfSnapshotRun row → 7+ PerformanceMetrics rows
-- =====================================================

IF OBJECT_ID('dbo.vw_PerformanceMetrics_Core', 'V') IS NOT NULL
    DROP VIEW dbo.vw_PerformanceMetrics_Core
GO

PRINT 'Creating view: dbo.vw_PerformanceMetrics_Core'
GO

CREATE VIEW dbo.vw_PerformanceMetrics_Core AS
SELECT
    -- MetricID: Unique identifier (RunID * 1000 + MetricOrdinal)
    CAST((psr.PerfSnapshotRunID * 1000) + m.MetricOrdinal AS BIGINT) AS MetricID,

    -- ServerID: NULL → 0 for backward compatibility
    ISNULL(psr.ServerID, 0) AS ServerID,

    -- CollectionTime: Match API expected column name
    psr.SnapshotUTC AS CollectionTime,

    -- Metric dimensions
    m.MetricCategory,
    m.MetricName,
    m.MetricValue,

    -- Additional context (not in original PerformanceMetrics, but useful)
    psr.ServerName,
    psr.SqlVersion,
    psr.PerfSnapshotRunID AS RunID  -- For joins back to enhanced tables

FROM dbo.PerfSnapshotRun psr
CROSS APPLY (
    VALUES
        -- Server-level metrics
        (1,  'Server', 'SessionsCount',          CAST(psr.SessionsCount AS DECIMAL(18,4))),
        (2,  'Server', 'RequestsCount',          CAST(psr.RequestsCount AS DECIMAL(18,4))),
        (3,  'Server', 'BlockingSessionCount',   CAST(psr.BlockingSessionCount AS DECIMAL(18,4))),

        -- CPU metrics
        (4,  'CPU',    'CpuSignalWaitPct',       psr.CpuSignalWaitPct),

        -- Wait statistics
        (5,  'Waits',  'TopWaitType',            CAST(0 AS DECIMAL(18,4))),  -- Text stored separately
        (6,  'Waits',  'TopWaitMsPerSec',        psr.TopWaitMsPerSec),

        -- Memory metrics
        (7,  'Memory', 'DeadlockCountRecent',    CAST(psr.DeadlockCountRecent AS DECIMAL(18,4))),
        (8,  'Memory', 'MemoryGrantWarningCount', CAST(psr.MemoryGrantWarningCount AS DECIMAL(18,4)))
) AS m(MetricOrdinal, MetricCategory, MetricName, MetricValue)
WHERE m.MetricValue IS NOT NULL;  -- Exclude NULL metrics
GO

PRINT '  ✓ View created: dbo.vw_PerformanceMetrics_Core'
PRINT ''
GO

-- =====================================================
-- View 2: vw_PerformanceMetrics_QueryStats
-- Purpose: Unpivot PerfSnapshotQueryStats (P0 priority)
-- Transforms: 1 QueryStats row → 6+ PerformanceMetrics rows
-- =====================================================

IF OBJECT_ID('dbo.vw_PerformanceMetrics_QueryStats', 'V') IS NOT NULL
    DROP VIEW dbo.vw_PerformanceMetrics_QueryStats
GO

PRINT 'Creating view: dbo.vw_PerformanceMetrics_QueryStats'
GO

CREATE VIEW dbo.vw_PerformanceMetrics_QueryStats AS
SELECT
    -- MetricID: Unique identifier (QueryStatsID * 100000 + MetricOrdinal)
    CAST((qs.PerfSnapshotQueryStatsID * 100000) + m.MetricOrdinal AS BIGINT) AS MetricID,

    -- ServerID: Inherited from PerfSnapshotRun
    ISNULL(psr.ServerID, 0) AS ServerID,

    -- CollectionTime: From parent snapshot
    psr.SnapshotUTC AS CollectionTime,

    -- Metric dimensions
    m.MetricCategory,
    m.MetricName,
    m.MetricValue,

    -- Additional context
    psr.ServerName,
    qs.DatabaseName,
    qs.ObjectName,
    psr.PerfSnapshotRunID AS RunID

FROM dbo.PerfSnapshotQueryStats qs
INNER JOIN dbo.PerfSnapshotRun psr ON qs.PerfSnapshotRunID = psr.PerfSnapshotRunID
CROSS APPLY (
    VALUES
        -- Query execution metrics
        (1, 'Query', 'ExecutionCount',    CAST(qs.ExecutionCount AS DECIMAL(18,4))),
        (2, 'Query', 'TotalCpuMs',        CAST(qs.TotalCpuMs AS DECIMAL(18,4))),
        (3, 'Query', 'AvgCpuMs',          qs.AvgCpuMs),
        (4, 'Query', 'MaxCpuMs',          qs.MaxCpuMs),

        -- I/O metrics
        (5, 'Query', 'TotalLogicalReads', CAST(qs.TotalLogicalReads AS DECIMAL(18,4))),
        (6, 'Query', 'AvgLogicalReads',   qs.AvgLogicalReads),
        (7, 'Query', 'MaxLogicalReads',   qs.MaxLogicalReads),

        -- Duration metrics
        (8, 'Query', 'TotalDurationMs',   CAST(qs.TotalDurationMs AS DECIMAL(18,4))),
        (9, 'Query', 'AvgDurationMs',     qs.AvgDurationMs),
        (10, 'Query', 'MaxDurationMs',    qs.MaxDurationMs)
) AS m(MetricOrdinal, MetricCategory, MetricName, MetricValue)
WHERE m.MetricValue IS NOT NULL;
GO

PRINT '  ✓ View created: dbo.vw_PerformanceMetrics_QueryStats'
PRINT ''
GO

-- =====================================================
-- View 3: vw_PerformanceMetrics_IOStats
-- Purpose: Unpivot PerfSnapshotIOStats (P0 priority)
-- Transforms: 1 IOStats row → 8+ PerformanceMetrics rows
-- =====================================================

IF OBJECT_ID('dbo.vw_PerformanceMetrics_IOStats', 'V') IS NOT NULL
    DROP VIEW dbo.vw_PerformanceMetrics_IOStats
GO

PRINT 'Creating view: dbo.vw_PerformanceMetrics_IOStats'
GO

CREATE VIEW dbo.vw_PerformanceMetrics_IOStats AS
SELECT
    -- MetricID: Unique identifier (IOStatsID * 100000 + MetricOrdinal)
    CAST((io.PerfSnapshotIOStatsID * 100000) + m.MetricOrdinal AS BIGINT) AS MetricID,

    -- ServerID: Inherited from PerfSnapshotRun
    ISNULL(psr.ServerID, 0) AS ServerID,

    -- CollectionTime
    psr.SnapshotUTC AS CollectionTime,

    -- Metric dimensions
    m.MetricCategory,
    m.MetricName,
    m.MetricValue,

    -- Additional context
    psr.ServerName,
    io.DatabaseName,
    io.PhysicalFileName,
    psr.PerfSnapshotRunID AS RunID

FROM dbo.PerfSnapshotIOStats io
INNER JOIN dbo.PerfSnapshotRun psr ON io.PerfSnapshotRunID = psr.PerfSnapshotRunID
CROSS APPLY (
    VALUES
        -- Read I/O metrics
        (1, 'IO', 'NumReads',           CAST(io.NumReads AS DECIMAL(18,4))),
        (2, 'IO', 'BytesRead',          CAST(io.BytesRead AS DECIMAL(18,4))),
        (3, 'IO', 'IoStallReadMs',      CAST(io.IoStallReadMs AS DECIMAL(18,4))),
        (4, 'IO', 'AvgReadLatencyMs',   io.AvgReadLatencyMs),

        -- Write I/O metrics
        (5, 'IO', 'NumWrites',          CAST(io.NumWrites AS DECIMAL(18,4))),
        (6, 'IO', 'BytesWritten',       CAST(io.BytesWritten AS DECIMAL(18,4))),
        (7, 'IO', 'IoStallWriteMs',     CAST(io.IoStallWriteMs AS DECIMAL(18,4))),
        (8, 'IO', 'AvgWriteLatencyMs',  io.AvgWriteLatencyMs),

        -- Total I/O metrics
        (9, 'IO', 'TotalIoStallMs',     CAST(io.TotalIoStallMs AS DECIMAL(18,4)))
) AS m(MetricOrdinal, MetricCategory, MetricName, MetricValue)
WHERE m.MetricValue IS NOT NULL;
GO

PRINT '  ✓ View created: dbo.vw_PerformanceMetrics_IOStats'
PRINT ''
GO

-- =====================================================
-- View 4: vw_PerformanceMetrics_Memory
-- Purpose: Unpivot PerfSnapshotMemory (P0 priority)
-- Transforms: 1 Memory row → 10+ PerformanceMetrics rows
-- =====================================================

IF OBJECT_ID('dbo.vw_PerformanceMetrics_Memory', 'V') IS NOT NULL
    DROP VIEW dbo.vw_PerformanceMetrics_Memory
GO

PRINT 'Creating view: dbo.vw_PerformanceMetrics_Memory'
GO

CREATE VIEW dbo.vw_PerformanceMetrics_Memory AS
SELECT
    -- MetricID: Unique identifier (MemoryID * 100000 + MetricOrdinal)
    CAST((mem.PerfSnapshotMemoryID * 100000) + m.MetricOrdinal AS BIGINT) AS MetricID,

    -- ServerID: Inherited from PerfSnapshotRun
    ISNULL(psr.ServerID, 0) AS ServerID,

    -- CollectionTime
    psr.SnapshotUTC AS CollectionTime,

    -- Metric dimensions
    m.MetricCategory,
    m.MetricName,
    m.MetricValue,

    -- Additional context
    psr.ServerName,
    psr.PerfSnapshotRunID AS RunID

FROM dbo.PerfSnapshotMemory mem
INNER JOIN dbo.PerfSnapshotRun psr ON mem.PerfSnapshotRunID = psr.PerfSnapshotRunID
CROSS APPLY (
    VALUES
        -- Page Life Expectancy
        (1,  'Memory', 'PageLifeExpectancySec',     CAST(mem.PageLifeExpectancySec AS DECIMAL(18,4))),

        -- Buffer cache metrics
        (2,  'Memory', 'BufferCacheSizeMB',         mem.BufferCacheSizeMB),
        (3,  'Memory', 'TargetServerMemoryMB',      mem.TargetServerMemoryMB),
        (4,  'Memory', 'TotalServerMemoryMB',       mem.TotalServerMemoryMB),
        (5,  'Memory', 'BufferCacheHitRatioPct',    mem.BufferCacheHitRatioPct),

        -- Memory grants
        (6,  'Memory', 'PendingMemoryGrantsCount',  CAST(mem.PendingMemoryGrantsCount AS DECIMAL(18,4))),
        (7,  'Memory', 'ActiveMemoryGrantsMB',      mem.ActiveMemoryGrantsMB),

        -- Memory pressure indicators
        (8,  'Memory', 'MemoryGrantsWaitingCount',  CAST(mem.MemoryGrantsWaitingCount AS DECIMAL(18,4))),
        (9,  'Memory', 'MaxServerMemoryMB',         mem.MaxServerMemoryMB),
        (10, 'Memory', 'AvailablePhysicalMemoryMB', mem.AvailablePhysicalMemoryMB)
) AS m(MetricOrdinal, MetricCategory, MetricName, MetricValue)
WHERE m.MetricValue IS NOT NULL;
GO

PRINT '  ✓ View created: dbo.vw_PerformanceMetrics_Memory'
PRINT ''
GO

-- =====================================================
-- View 5: vw_PerformanceMetrics_WaitStats
-- Purpose: Unpivot PerfSnapshotWaitStats (P1 priority)
-- Transforms: 1 WaitStats row → 4+ PerformanceMetrics rows
-- =====================================================

IF OBJECT_ID('dbo.vw_PerformanceMetrics_WaitStats', 'V') IS NOT NULL
    DROP VIEW dbo.vw_PerformanceMetrics_WaitStats
GO

PRINT 'Creating view: dbo.vw_PerformanceMetrics_WaitStats'
GO

CREATE VIEW dbo.vw_PerformanceMetrics_WaitStats AS
SELECT
    -- MetricID: Unique identifier (WaitStatsID * 100000 + MetricOrdinal)
    CAST((ws.PerfSnapshotWaitStatsID * 100000) + m.MetricOrdinal AS BIGINT) AS MetricID,

    -- ServerID: Inherited from PerfSnapshotRun
    ISNULL(psr.ServerID, 0) AS ServerID,

    -- CollectionTime
    psr.SnapshotUTC AS CollectionTime,

    -- Metric dimensions
    m.MetricCategory,
    m.MetricName,
    m.MetricValue,

    -- Additional context
    psr.ServerName,
    ws.WaitType,
    psr.PerfSnapshotRunID AS RunID

FROM dbo.PerfSnapshotWaitStats ws
INNER JOIN dbo.PerfSnapshotRun psr ON ws.PerfSnapshotRunID = psr.PerfSnapshotRunID
CROSS APPLY (
    VALUES
        -- Wait statistics
        (1, 'Waits', 'WaitingTasksCount',     CAST(ws.WaitingTasksCount AS DECIMAL(18,4))),
        (2, 'Waits', 'WaitTimeMs',            CAST(ws.WaitTimeMs AS DECIMAL(18,4))),
        (3, 'Waits', 'MaxWaitTimeMs',         CAST(ws.MaxWaitTimeMs AS DECIMAL(18,4))),
        (4, 'Waits', 'SignalWaitTimeMs',      CAST(ws.SignalWaitTimeMs AS DECIMAL(18,4))),
        (5, 'Waits', 'ResourceWaitTimeMs',    CAST(ws.ResourceWaitTimeMs AS DECIMAL(18,4))),
        (6, 'Waits', 'WaitTimeMsPerSec',      ws.WaitTimeMsPerSec)
) AS m(MetricOrdinal, MetricCategory, MetricName, MetricValue)
WHERE m.MetricValue IS NOT NULL;
GO

PRINT '  ✓ View created: dbo.vw_PerformanceMetrics_WaitStats'
PRINT ''
GO

-- =====================================================
-- View 6: vw_PerformanceMetrics_Unified
-- Purpose: UNION ALL of all metric sources
-- This is the PRIMARY view that the API queries
-- =====================================================

IF OBJECT_ID('dbo.vw_PerformanceMetrics_Unified', 'V') IS NOT NULL
    DROP VIEW dbo.vw_PerformanceMetrics_Unified
GO

PRINT 'Creating view: dbo.vw_PerformanceMetrics_Unified (PRIMARY API VIEW)'
GO

CREATE VIEW dbo.vw_PerformanceMetrics_Unified AS

-- Core metrics (from PerfSnapshotRun)
SELECT
    MetricID,
    ServerID,
    CollectionTime,
    MetricCategory,
    MetricName,
    MetricValue,
    ServerName,
    'Core' AS MetricSource
FROM dbo.vw_PerformanceMetrics_Core

UNION ALL

-- Query performance metrics (P0)
SELECT
    MetricID,
    ServerID,
    CollectionTime,
    MetricCategory,
    MetricName,
    MetricValue,
    ServerName,
    'QueryStats' AS MetricSource
FROM dbo.vw_PerformanceMetrics_QueryStats

UNION ALL

-- I/O performance metrics (P0)
SELECT
    MetricID,
    ServerID,
    CollectionTime,
    MetricCategory,
    MetricName,
    MetricValue,
    ServerName,
    'IOStats' AS MetricSource
FROM dbo.vw_PerformanceMetrics_IOStats

UNION ALL

-- Memory metrics (P0)
SELECT
    MetricID,
    ServerID,
    CollectionTime,
    MetricCategory,
    MetricName,
    MetricValue,
    ServerName,
    'Memory' AS MetricSource
FROM dbo.vw_PerformanceMetrics_Memory

UNION ALL

-- Wait statistics (P1)
SELECT
    MetricID,
    ServerID,
    CollectionTime,
    MetricCategory,
    MetricName,
    MetricValue,
    ServerName,
    'WaitStats' AS MetricSource
FROM dbo.vw_PerformanceMetrics_WaitStats;

GO

PRINT '  ✓ View created: dbo.vw_PerformanceMetrics_Unified'
PRINT '    This is the PRIMARY view for API queries'
PRINT ''
GO

-- =====================================================
-- View 7: vw_PerformanceMetrics
-- Purpose: Backward compatibility alias
-- API expects table named "PerformanceMetrics"
-- =====================================================

IF OBJECT_ID('dbo.vw_PerformanceMetrics', 'V') IS NOT NULL
    DROP VIEW dbo.vw_PerformanceMetrics
GO

PRINT 'Creating view: dbo.vw_PerformanceMetrics (BACKWARD COMPATIBILITY ALIAS)'
GO

CREATE VIEW dbo.vw_PerformanceMetrics AS
SELECT
    MetricID,
    ServerID,
    CollectionTime,
    MetricCategory,
    MetricName,
    MetricValue
    -- Omit ServerName, MetricSource for exact compatibility
FROM dbo.vw_PerformanceMetrics_Unified;

GO

PRINT '  ✓ View created: dbo.vw_PerformanceMetrics'
PRINT '    This view provides exact compatibility with existing API code'
PRINT ''
GO

-- =====================================================
-- View 8: vw_ServerSummary
-- Purpose: Server-level aggregates (for dashboard overview)
-- =====================================================

IF OBJECT_ID('dbo.vw_ServerSummary', 'V') IS NOT NULL
    DROP VIEW dbo.vw_ServerSummary
GO

PRINT 'Creating view: dbo.vw_ServerSummary'
GO

CREATE VIEW dbo.vw_ServerSummary AS
SELECT
    s.ServerID,
    s.ServerName,
    s.Environment,
    s.IsActive,

    -- Latest snapshot time
    MAX(psr.SnapshotUTC) AS LastCollectionTime,

    -- Total snapshots collected
    COUNT(DISTINCT psr.PerfSnapshotRunID) AS TotalSnapshots,

    -- Latest metrics (from most recent snapshot)
    (
        SELECT TOP 1 psr2.CpuSignalWaitPct
        FROM dbo.PerfSnapshotRun psr2
        WHERE psr2.ServerID = s.ServerID
        ORDER BY psr2.SnapshotUTC DESC
    ) AS LatestCpuPct,

    (
        SELECT TOP 1 psr2.SessionsCount
        FROM dbo.PerfSnapshotRun psr2
        WHERE psr2.ServerID = s.ServerID
        ORDER BY psr2.SnapshotUTC DESC
    ) AS LatestSessionsCount,

    (
        SELECT TOP 1 psr2.BlockingSessionCount
        FROM dbo.PerfSnapshotRun psr2
        WHERE psr2.ServerID = s.ServerID
        ORDER BY psr2.SnapshotUTC DESC
    ) AS LatestBlockingCount,

    -- Average metrics (last 24 hours)
    (
        SELECT AVG(psr24.CpuSignalWaitPct)
        FROM dbo.PerfSnapshotRun psr24
        WHERE psr24.ServerID = s.ServerID
          AND psr24.SnapshotUTC >= DATEADD(HOUR, -24, SYSUTCDATETIME())
    ) AS Avg24HrCpuPct,

    (
        SELECT AVG(CAST(psr24.SessionsCount AS DECIMAL(18,2)))
        FROM dbo.PerfSnapshotRun psr24
        WHERE psr24.ServerID = s.ServerID
          AND psr24.SnapshotUTC >= DATEADD(HOUR, -24, SYSUTCDATETIME())
    ) AS Avg24HrSessions,

    -- Health indicators
    CASE
        WHEN MAX(psr.SnapshotUTC) < DATEADD(MINUTE, -10, SYSUTCDATETIME()) THEN 'Stale'
        WHEN s.IsActive = 0 THEN 'Inactive'
        ELSE 'Healthy'
    END AS HealthStatus

FROM dbo.Servers s
LEFT JOIN dbo.PerfSnapshotRun psr ON s.ServerID = psr.ServerID
GROUP BY
    s.ServerID,
    s.ServerName,
    s.Environment,
    s.IsActive;

GO

PRINT '  ✓ View created: dbo.vw_ServerSummary'
PRINT ''
GO

-- =====================================================
-- View 9: vw_DatabaseSummary
-- Purpose: Database-level aggregates (for database dashboard)
-- =====================================================

IF OBJECT_ID('dbo.vw_DatabaseSummary', 'V') IS NOT NULL
    DROP VIEW dbo.vw_DatabaseSummary
GO

PRINT 'Creating view: dbo.vw_DatabaseSummary'
GO

CREATE VIEW dbo.vw_DatabaseSummary AS
SELECT
    psd.PerfSnapshotRunID,
    psr.ServerID,
    psr.ServerName,
    psr.SnapshotUTC AS CollectionTime,
    psd.DatabaseName,

    -- Size metrics
    psd.DataSizeMB,
    psd.LogSizeMB,
    psd.LogUsedMB,
    psd.LogUsedPct,

    -- Activity metrics
    psd.ActiveTransactions,
    psd.LogFlushesPerSec,
    psd.LogBytesPerSec,

    -- Recovery status
    psd.RecoveryModel,
    psd.State,
    psd.LastFullBackupUTC,
    psd.LastLogBackupUTC,

    -- Calculated fields
    DATEDIFF(HOUR, psd.LastFullBackupUTC, SYSUTCDATETIME()) AS HoursSinceLastFullBackup,
    DATEDIFF(HOUR, psd.LastLogBackupUTC, SYSUTCDATETIME()) AS HoursSinceLastLogBackup,

    -- Backup health status
    CASE
        WHEN psd.LastFullBackupUTC IS NULL THEN 'No Backup'
        WHEN DATEDIFF(HOUR, psd.LastFullBackupUTC, SYSUTCDATETIME()) > 24 THEN 'Overdue'
        ELSE 'Healthy'
    END AS BackupHealthStatus

FROM dbo.PerfSnapshotDB psd
INNER JOIN dbo.PerfSnapshotRun psr ON psd.PerfSnapshotRunID = psr.PerfSnapshotRunID;

GO

PRINT '  ✓ View created: dbo.vw_DatabaseSummary'
PRINT ''
GO

-- =====================================================
-- View 10: vw_MetricCategories
-- Purpose: List all available metric categories and names
-- Useful for API discoverability
-- =====================================================

IF OBJECT_ID('dbo.vw_MetricCategories', 'V') IS NOT NULL
    DROP VIEW dbo.vw_MetricCategories
GO

PRINT 'Creating view: dbo.vw_MetricCategories'
GO

CREATE VIEW dbo.vw_MetricCategories AS
SELECT DISTINCT
    MetricCategory,
    MetricName,
    MetricSource,
    COUNT(*) OVER (PARTITION BY MetricCategory, MetricName, MetricSource) AS SampleCount
FROM dbo.vw_PerformanceMetrics_Unified;

GO

PRINT '  ✓ View created: dbo.vw_MetricCategories'
PRINT ''
GO

-- =====================================================
-- Summary and Validation
-- =====================================================

PRINT '========================================================================='
PRINT 'Views Created Successfully'
PRINT '========================================================================='
PRINT ''
PRINT 'Core Mapping Views (WIDE → TALL transformation):'
PRINT '  1. vw_PerformanceMetrics_Core      - PerfSnapshotRun unpivot'
PRINT '  2. vw_PerformanceMetrics_QueryStats - Query performance metrics'
PRINT '  3. vw_PerformanceMetrics_IOStats    - I/O performance metrics'
PRINT '  4. vw_PerformanceMetrics_Memory     - Memory utilization metrics'
PRINT '  5. vw_PerformanceMetrics_WaitStats  - Wait statistics'
PRINT ''
PRINT 'Unified Views (API Interface):'
PRINT '  6. vw_PerformanceMetrics_Unified    - UNION ALL of all sources (PRIMARY)'
PRINT '  7. vw_PerformanceMetrics            - Backward compatibility alias'
PRINT ''
PRINT 'Aggregation Views (Dashboard Support):'
PRINT '  8. vw_ServerSummary                 - Server-level health and metrics'
PRINT '  9. vw_DatabaseSummary               - Database-level metrics and backup status'
PRINT ' 10. vw_MetricCategories              - Available metric catalog'
PRINT ''
PRINT 'Next Steps:'
PRINT '  1. Run test queries against views'
PRINT '  2. Benchmark query performance (<500ms target)'
PRINT '  3. Test API compatibility with new views'
PRINT '  4. Create unit tests for view correctness'
PRINT ''
PRINT '========================================================================='
GO

-- =====================================================
-- Quick Validation Queries (commented out - for testing)
-- =====================================================

-- Test 1: Count metrics from each source
-- SELECT MetricSource, COUNT(*) AS MetricCount
-- FROM dbo.vw_PerformanceMetrics_Unified
-- GROUP BY MetricSource
-- ORDER BY MetricCount DESC;

-- Test 2: Verify backward compatibility (same columns as original)
-- SELECT TOP 10 *
-- FROM dbo.vw_PerformanceMetrics
-- ORDER BY CollectionTime DESC;

-- Test 3: Server summary (all servers)
-- SELECT * FROM dbo.vw_ServerSummary
-- ORDER BY ServerName;

-- Test 4: Database summary (last 24 hours)
-- SELECT * FROM dbo.vw_DatabaseSummary
-- WHERE CollectionTime >= DATEADD(HOUR, -24, SYSUTCDATETIME())
-- ORDER BY CollectionTime DESC, ServerName, DatabaseName;

-- Test 5: Performance test (should be <500ms for 90 days)
-- SET STATISTICS TIME ON;
-- SELECT MetricCategory, MetricName, AVG(MetricValue) AS AvgValue
-- FROM dbo.vw_PerformanceMetrics
-- WHERE CollectionTime >= DATEADD(DAY, -90, SYSUTCDATETIME())
-- GROUP BY MetricCategory, MetricName;
-- SET STATISTICS TIME OFF;
