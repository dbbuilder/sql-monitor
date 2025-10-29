-- =====================================================
-- Script: benchmark-phase-1.9-views.sql
-- Description: Performance benchmarks for Phase 1.9 mapping views
-- Author: SQL Server Monitor Project
-- Date: 2025-10-28
-- Phase: 1.9 - Integration (Day 2)
-- Target: < 500ms for 90-day queries
-- =====================================================

PRINT '========================================================================='
PRINT 'Phase 1.9 Performance Benchmarks: Mapping Views'
PRINT '========================================================================='
PRINT ''
PRINT 'Database: ' + DB_NAME()
PRINT 'Test Date: ' + CONVERT(VARCHAR, GETDATE(), 120)
PRINT ''
PRINT 'Performance Targets:'
PRINT '  - 24-hour queries: < 100ms'
PRINT '  - 7-day queries: < 250ms'
PRINT '  - 30-day queries: < 500ms'
PRINT '  - 90-day queries: < 500ms (CRITICAL)'
PRINT ''
PRINT '========================================================================='
PRINT ''
GO

-- =====================================================
-- Setup: Record test environment
-- =====================================================

DECLARE @RowCount_PerfSnapshotRun BIGINT;
DECLARE @RowCount_QueryStats BIGINT;
DECLARE @RowCount_IOStats BIGINT;
DECLARE @RowCount_Memory BIGINT;
DECLARE @RowCount_WaitStats BIGINT;
DECLARE @DateRange_Start DATETIME2;
DECLARE @DateRange_End DATETIME2;

SELECT @RowCount_PerfSnapshotRun = COUNT(*) FROM dbo.PerfSnapshotRun;
SELECT @RowCount_QueryStats = COUNT(*) FROM dbo.PerfSnapshotQueryStats;
SELECT @RowCount_IOStats = COUNT(*) FROM dbo.PerfSnapshotIOStats;
SELECT @RowCount_Memory = COUNT(*) FROM dbo.PerfSnapshotMemory;
SELECT @RowCount_WaitStats = COUNT(*) FROM dbo.PerfSnapshotWaitStats;
SELECT @DateRange_Start = MIN(SnapshotUTC), @DateRange_End = MAX(SnapshotUTC) FROM dbo.PerfSnapshotRun;

PRINT 'Test Environment:'
PRINT '  PerfSnapshotRun rows:    ' + CAST(@RowCount_PerfSnapshotRun AS VARCHAR)
PRINT '  QueryStats rows:         ' + CAST(@RowCount_QueryStats AS VARCHAR)
PRINT '  IOStats rows:            ' + CAST(@RowCount_IOStats AS VARCHAR)
PRINT '  Memory rows:             ' + CAST(@RowCount_Memory AS VARCHAR)
PRINT '  WaitStats rows:          ' + CAST(@RowCount_WaitStats AS VARCHAR)
PRINT '  Date range:              ' + CONVERT(VARCHAR, @DateRange_Start, 120) + ' to ' + CONVERT(VARCHAR, @DateRange_End, 120)
PRINT '  Days of data:            ' + CAST(DATEDIFF(DAY, @DateRange_Start, @DateRange_End) AS VARCHAR)
PRINT ''
GO

-- =====================================================
-- Benchmark 1: vw_PerformanceMetrics_Core (24 hours)
-- =====================================================

PRINT '========================================================================='
PRINT 'Benchmark 1: vw_PerformanceMetrics_Core (24 hours)'
PRINT '========================================================================='
PRINT ''
PRINT 'Query: Aggregate core metrics by category (last 24 hours)'
PRINT 'Target: < 100ms'
PRINT ''
GO

SET STATISTICS TIME ON;
SET STATISTICS IO ON;
GO

SELECT
    MetricCategory,
    MetricName,
    COUNT(*) AS DataPoints,
    AVG(MetricValue) AS AvgValue,
    MIN(MetricValue) AS MinValue,
    MAX(MetricValue) AS MaxValue,
    STDEV(MetricValue) AS StdDevValue
FROM dbo.vw_PerformanceMetrics_Core
WHERE CollectionTime >= DATEADD(HOUR, -24, SYSUTCDATETIME())
GROUP BY MetricCategory, MetricName
ORDER BY MetricCategory, MetricName;
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

PRINT ''
PRINT '  ✓ Benchmark 1 complete - Review CPU time above'
PRINT ''
GO

-- =====================================================
-- Benchmark 2: vw_PerformanceMetrics_Unified (7 days)
-- =====================================================

PRINT '========================================================================='
PRINT 'Benchmark 2: vw_PerformanceMetrics_Unified (7 days)'
PRINT '========================================================================='
PRINT ''
PRINT 'Query: Count metrics by source and category (last 7 days)'
PRINT 'Target: < 250ms'
PRINT ''
GO

SET STATISTICS TIME ON;
SET STATISTICS IO ON;
GO

SELECT
    MetricSource,
    MetricCategory,
    COUNT(*) AS DataPoints,
    COUNT(DISTINCT ServerName) AS UniqueServers,
    MIN(CollectionTime) AS EarliestCollection,
    MAX(CollectionTime) AS LatestCollection
FROM dbo.vw_PerformanceMetrics_Unified
WHERE CollectionTime >= DATEADD(DAY, -7, SYSUTCDATETIME())
GROUP BY MetricSource, MetricCategory
ORDER BY MetricSource, MetricCategory;
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

PRINT ''
PRINT '  ✓ Benchmark 2 complete - Review CPU time above'
PRINT ''
GO

-- =====================================================
-- Benchmark 3: vw_PerformanceMetrics (30 days, API query)
-- =====================================================

PRINT '========================================================================='
PRINT 'Benchmark 3: vw_PerformanceMetrics (30 days, API query pattern)'
PRINT '========================================================================='
PRINT ''
PRINT 'Query: Aggregate metrics by server and category (last 30 days)'
PRINT 'Target: < 500ms'
PRINT ''
GO

SET STATISTICS TIME ON;
SET STATISTICS IO ON;
GO

SELECT
    ServerID,
    MetricCategory,
    MetricName,
    COUNT(*) AS DataPoints,
    AVG(MetricValue) AS AvgValue,
    MIN(MetricValue) AS MinValue,
    MAX(MetricValue) AS MaxValue,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY MetricValue) AS MedianValue,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY MetricValue) AS P95Value
FROM dbo.vw_PerformanceMetrics
WHERE CollectionTime >= DATEADD(DAY, -30, SYSUTCDATETIME())
GROUP BY ServerID, MetricCategory, MetricName
ORDER BY ServerID, MetricCategory, MetricName;
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

PRINT ''
PRINT '  ✓ Benchmark 3 complete - Review CPU time above'
PRINT ''
GO

-- =====================================================
-- Benchmark 4: vw_PerformanceMetrics (90 days, CRITICAL)
-- =====================================================

PRINT '========================================================================='
PRINT 'Benchmark 4: vw_PerformanceMetrics (90 days, CRITICAL TEST)'
PRINT '========================================================================='
PRINT ''
PRINT 'Query: Time-series metrics for charting (last 90 days)'
PRINT 'Target: < 500ms (CRITICAL - API timeout threshold)'
PRINT ''
GO

SET STATISTICS TIME ON;
SET STATISTICS IO ON;
GO

SELECT
    CAST(CollectionTime AS DATE) AS CollectionDate,
    DATEPART(HOUR, CollectionTime) AS CollectionHour,
    MetricCategory,
    MetricName,
    AVG(MetricValue) AS AvgValue,
    MAX(MetricValue) AS MaxValue
FROM dbo.vw_PerformanceMetrics
WHERE CollectionTime >= DATEADD(DAY, -90, SYSUTCDATETIME())
  AND MetricCategory IN ('CPU', 'Memory', 'Waits')  -- Most common dashboard metrics
GROUP BY
    CAST(CollectionTime AS DATE),
    DATEPART(HOUR, CollectionTime),
    MetricCategory,
    MetricName
ORDER BY
    CollectionDate DESC,
    CollectionHour DESC,
    MetricCategory,
    MetricName;
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

PRINT ''
PRINT '  ✓ Benchmark 4 complete (CRITICAL) - Review CPU time above'
PRINT '  ⚠ WARNING: If CPU time > 500ms, consider adding indexes or partitioning'
PRINT ''
GO

-- =====================================================
-- Benchmark 5: vw_ServerSummary (aggregation view)
-- =====================================================

PRINT '========================================================================='
PRINT 'Benchmark 5: vw_ServerSummary (dashboard aggregation)'
PRINT '========================================================================='
PRINT ''
PRINT 'Query: Server health summary with 24-hour averages'
PRINT 'Target: < 200ms'
PRINT ''
GO

SET STATISTICS TIME ON;
SET STATISTICS IO ON;
GO

SELECT
    ServerName,
    Environment,
    HealthStatus,
    LastCollectionTime,
    TotalSnapshots,
    LatestCpuPct,
    LatestSessionsCount,
    LatestBlockingCount,
    Avg24HrCpuPct,
    Avg24HrSessions
FROM dbo.vw_ServerSummary
ORDER BY
    CASE HealthStatus
        WHEN 'Stale' THEN 1
        WHEN 'Inactive' THEN 2
        WHEN 'Healthy' THEN 3
    END,
    ServerName;
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

PRINT ''
PRINT '  ✓ Benchmark 5 complete - Review CPU time above'
PRINT ''
GO

-- =====================================================
-- Benchmark 6: vw_PerformanceMetrics_QueryStats (7 days)
-- =====================================================

PRINT '========================================================================='
PRINT 'Benchmark 6: vw_PerformanceMetrics_QueryStats (7 days, detailed)'
PRINT '========================================================================='
PRINT ''
PRINT 'Query: Query performance metrics (last 7 days)'
PRINT 'Target: < 300ms'
PRINT ''
GO

SET STATISTICS TIME ON;
SET STATISTICS IO ON;
GO

SELECT
    ServerName,
    MetricName,
    COUNT(*) AS DataPoints,
    AVG(MetricValue) AS AvgValue,
    MAX(MetricValue) AS MaxValue
FROM dbo.vw_PerformanceMetrics_QueryStats
WHERE CollectionTime >= DATEADD(DAY, -7, SYSUTCDATETIME())
GROUP BY ServerName, MetricName
ORDER BY ServerName, MetricName;
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

PRINT ''
PRINT '  ✓ Benchmark 6 complete - Review CPU time above'
PRINT ''
GO

-- =====================================================
-- Benchmark 7: Cross-view JOIN (complex query)
-- =====================================================

PRINT '========================================================================='
PRINT 'Benchmark 7: Cross-view JOIN (complex dashboard query)'
PRINT '========================================================================='
PRINT ''
PRINT 'Query: Combine server summary with latest metrics (30 days)'
PRINT 'Target: < 400ms'
PRINT ''
GO

SET STATISTICS TIME ON;
SET STATISTICS IO ON;
GO

SELECT
    ss.ServerName,
    ss.Environment,
    ss.HealthStatus,
    ss.LatestCpuPct,
    cpu_avg.AvgCpu30Days,
    mem_avg.AvgMemory30Days,
    waits_avg.AvgWaits30Days
FROM dbo.vw_ServerSummary ss
LEFT JOIN (
    SELECT
        ServerID,
        AVG(MetricValue) AS AvgCpu30Days
    FROM dbo.vw_PerformanceMetrics
    WHERE MetricCategory = 'CPU'
      AND MetricName = 'CpuSignalWaitPct'
      AND CollectionTime >= DATEADD(DAY, -30, SYSUTCDATETIME())
    GROUP BY ServerID
) cpu_avg ON ss.ServerID = cpu_avg.ServerID
LEFT JOIN (
    SELECT
        ServerID,
        AVG(MetricValue) AS AvgMemory30Days
    FROM dbo.vw_PerformanceMetrics
    WHERE MetricCategory = 'Memory'
      AND MetricName = 'PageLifeExpectancySec'
      AND CollectionTime >= DATEADD(DAY, -30, SYSUTCDATETIME())
    GROUP BY ServerID
) mem_avg ON ss.ServerID = mem_avg.ServerID
LEFT JOIN (
    SELECT
        ServerID,
        AVG(MetricValue) AS AvgWaits30Days
    FROM dbo.vw_PerformanceMetrics
    WHERE MetricCategory = 'Waits'
      AND MetricName = 'TopWaitMsPerSec'
      AND CollectionTime >= DATEADD(DAY, -30, SYSUTCDATETIME())
    GROUP BY ServerID
) waits_avg ON ss.ServerID = waits_avg.ServerID
ORDER BY ss.ServerName;
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

PRINT ''
PRINT '  ✓ Benchmark 7 complete - Review CPU time above'
PRINT ''
GO

-- =====================================================
-- Benchmark 8: Row count estimation (planning query)
-- =====================================================

PRINT '========================================================================='
PRINT 'Benchmark 8: Row count estimation (query planning)'
PRINT '========================================================================='
PRINT ''
PRINT 'Query: Estimate data volume for different time ranges'
PRINT 'Target: < 50ms'
PRINT ''
GO

SET STATISTICS TIME ON;
GO

SELECT
    '24 hours' AS TimeRange,
    COUNT(*) AS TotalMetrics,
    COUNT(DISTINCT ServerID) AS UniqueServers,
    COUNT(DISTINCT MetricCategory) AS UniqueCategories
FROM dbo.vw_PerformanceMetrics_Unified
WHERE CollectionTime >= DATEADD(HOUR, -24, SYSUTCDATETIME())

UNION ALL

SELECT
    '7 days' AS TimeRange,
    COUNT(*) AS TotalMetrics,
    COUNT(DISTINCT ServerID) AS UniqueServers,
    COUNT(DISTINCT MetricCategory) AS UniqueCategories
FROM dbo.vw_PerformanceMetrics_Unified
WHERE CollectionTime >= DATEADD(DAY, -7, SYSUTCDATETIME())

UNION ALL

SELECT
    '30 days' AS TimeRange,
    COUNT(*) AS TotalMetrics,
    COUNT(DISTINCT ServerID) AS UniqueServers,
    COUNT(DISTINCT MetricCategory) AS UniqueCategories
FROM dbo.vw_PerformanceMetrics_Unified
WHERE CollectionTime >= DATEADD(DAY, -30, SYSUTCDATETIME())

UNION ALL

SELECT
    '90 days' AS TimeRange,
    COUNT(*) AS TotalMetrics,
    COUNT(DISTINCT ServerID) AS UniqueServers,
    COUNT(DISTINCT MetricCategory) AS UniqueCategories
FROM dbo.vw_PerformanceMetrics_Unified
WHERE CollectionTime >= DATEADD(DAY, -90, SYSUTCDATETIME());
GO

SET STATISTICS TIME OFF;
GO

PRINT ''
PRINT '  ✓ Benchmark 8 complete - Review CPU time above'
PRINT ''
GO

-- =====================================================
-- Performance Summary
-- =====================================================

PRINT '========================================================================='
PRINT 'PERFORMANCE BENCHMARK SUMMARY'
PRINT '========================================================================='
PRINT ''
PRINT 'Benchmarks Completed: 8 queries'
PRINT ''
PRINT 'Review STATISTICS TIME output above for each benchmark:'
PRINT ''
PRINT '  Benchmark 1: Core view (24h)              Target: < 100ms'
PRINT '  Benchmark 2: Unified view (7d)            Target: < 250ms'
PRINT '  Benchmark 3: API query (30d)              Target: < 500ms'
PRINT '  Benchmark 4: Time-series (90d) ⚠ CRITICAL Target: < 500ms'
PRINT '  Benchmark 5: Server summary               Target: < 200ms'
PRINT '  Benchmark 6: QueryStats (7d)              Target: < 300ms'
PRINT '  Benchmark 7: Complex JOIN (30d)           Target: < 400ms'
PRINT '  Benchmark 8: Row count estimation         Target: < 50ms'
PRINT ''
PRINT 'Performance Tuning Recommendations:'
PRINT ''
PRINT '  If Benchmark 4 > 500ms (CRITICAL):'
PRINT '    1. Add filtered index: CREATE NONCLUSTERED INDEX IX_PerfSnapshotRun_SnapshotUTC'
PRINT '       ON dbo.PerfSnapshotRun (SnapshotUTC DESC) INCLUDE (ServerID, CpuSignalWaitPct, ...)'
PRINT '    2. Consider partitioning PerfSnapshotRun by SnapshotUTC (monthly)'
PRINT '    3. Enable page compression on large tables'
PRINT ''
PRINT '  If any benchmark > 2x target:'
PRINT '    1. Run UPDATE STATISTICS on PerfSnapshot* tables'
PRINT '    2. Rebuild indexes if fragmentation > 30%'
PRINT '    3. Check for missing indexes in DMVs'
PRINT ''
PRINT '  For production deployment:'
PRINT '    1. Test with realistic data volume (millions of rows)'
PRINT '    2. Monitor actual query plans for view queries'
PRINT '    3. Consider indexed views for frequently-accessed aggregations'
PRINT ''
PRINT '========================================================================='
PRINT 'Benchmark Complete'
PRINT '========================================================================='
PRINT ''
GO
