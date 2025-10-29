-- =====================================================
-- Script: deploy-and-test-views.sql
-- Description: Deploy Phase 1.9 mapping views and run validation tests
-- Author: SQL Server Monitor Project
-- Date: 2025-10-28
-- Phase: 1.9 - Integration (Day 2)
-- Target: Both DBATools and MonitoringDB
-- =====================================================

PRINT '========================================================================='
PRINT 'Phase 1.9 View Deployment Test: Mapping Views (Day 2)'
PRINT '========================================================================='
PRINT ''
GO

-- =====================================================
-- Prerequisites Check
-- =====================================================

PRINT 'Checking prerequisites...'
PRINT '-------------------------------------------'
GO

-- Verify core tables exist
IF OBJECT_ID('dbo.PerfSnapshotRun', 'U') IS NULL
BEGIN
    PRINT '✗ ERROR: PerfSnapshotRun table does not exist'
    PRINT '  Please run 20-create-dbatools-tables.sql first'
    RAISERROR('Prerequisites not met', 16, 1)
    RETURN
END

-- Verify enhanced tables exist
IF OBJECT_ID('dbo.PerfSnapshotQueryStats', 'U') IS NULL
BEGIN
    PRINT '✗ ERROR: Enhanced tables do not exist'
    PRINT '  Please run 21-create-enhanced-tables.sql first'
    RAISERROR('Prerequisites not met', 16, 1)
    RETURN
END

PRINT '  ✓ Core tables exist'
PRINT '  ✓ Enhanced tables exist'
PRINT ''
GO

-- =====================================================
-- Step 1: Deploy mapping views
-- =====================================================

PRINT 'Step 1: Deploying mapping views...'
PRINT '-------------------------------------------'
GO

-- Execute the mapping views script
:r ../22-create-mapping-views.sql

PRINT ''
PRINT '  ✓ Mapping views deployment complete'
PRINT ''
GO

-- =====================================================
-- Step 2: Run validation tests
-- =====================================================

PRINT 'Step 2: Running validation tests...'
PRINT '-------------------------------------------'
PRINT ''
GO

-- Execute the view test script
:r test-phase-1.9-views.sql

GO

-- =====================================================
-- Step 3: Performance Benchmarks
-- =====================================================

PRINT ''
PRINT 'Step 3: Running performance benchmarks...'
PRINT '-------------------------------------------'
GO

-- Benchmark 1: Core view query performance
PRINT 'Benchmark 1: vw_PerformanceMetrics_Core (last 24 hours)'
SET STATISTICS TIME ON;
GO

SELECT
    MetricCategory,
    MetricName,
    COUNT(*) AS DataPoints,
    AVG(MetricValue) AS AvgValue,
    MIN(MetricValue) AS MinValue,
    MAX(MetricValue) AS MaxValue
FROM dbo.vw_PerformanceMetrics_Core
WHERE CollectionTime >= DATEADD(HOUR, -24, SYSUTCDATETIME())
GROUP BY MetricCategory, MetricName
ORDER BY MetricCategory, MetricName;
GO

SET STATISTICS TIME OFF;
GO

-- Benchmark 2: Unified view query performance
PRINT ''
PRINT 'Benchmark 2: vw_PerformanceMetrics_Unified (last 7 days)'
SET STATISTICS TIME ON;
GO

SELECT
    MetricSource,
    MetricCategory,
    COUNT(*) AS DataPoints
FROM dbo.vw_PerformanceMetrics_Unified
WHERE CollectionTime >= DATEADD(DAY, -7, SYSUTCDATETIME())
GROUP BY MetricSource, MetricCategory
ORDER BY MetricSource, MetricCategory;
GO

SET STATISTICS TIME OFF;
GO

-- Benchmark 3: Backward compatibility view (API query pattern)
PRINT ''
PRINT 'Benchmark 3: vw_PerformanceMetrics (API query pattern)'
SET STATISTICS TIME ON;
GO

SELECT
    ServerID,
    MetricCategory,
    MetricName,
    AVG(MetricValue) AS AvgValue
FROM dbo.vw_PerformanceMetrics
WHERE CollectionTime >= DATEADD(DAY, -30, SYSUTCDATETIME())
GROUP BY ServerID, MetricCategory, MetricName
ORDER BY ServerID, MetricCategory, MetricName;
GO

SET STATISTICS TIME OFF;
GO

-- Benchmark 4: ServerSummary aggregation
PRINT ''
PRINT 'Benchmark 4: vw_ServerSummary (dashboard query)'
SET STATISTICS TIME ON;
GO

SELECT
    ServerName,
    Environment,
    HealthStatus,
    LastCollectionTime,
    LatestCpuPct,
    LatestSessionsCount,
    Avg24HrCpuPct,
    Avg24HrSessions
FROM dbo.vw_ServerSummary
ORDER BY ServerName;
GO

SET STATISTICS TIME OFF;
GO

PRINT ''
PRINT '  ✓ Performance benchmarks complete'
PRINT '  Note: Review STATISTICS TIME output above'
PRINT '  Target: < 500ms for queries with 90 days of data'
PRINT ''
GO

-- =====================================================
-- Step 4: Sample Data Queries
-- =====================================================

PRINT 'Step 4: Sample data queries (verify view output)...'
PRINT '-------------------------------------------'
GO

-- Sample 1: Show metric categories available
PRINT ''
PRINT 'Sample 1: Available metric categories and names'
SELECT
    MetricCategory,
    COUNT(DISTINCT MetricName) AS MetricCount,
    STRING_AGG(DISTINCT MetricSource, ', ') AS Sources
FROM dbo.vw_PerformanceMetrics_Unified
GROUP BY MetricCategory
ORDER BY MetricCategory;
GO

-- Sample 2: Latest metrics for each server
PRINT ''
PRINT 'Sample 2: Latest metrics for each server (top 5 per server)'
SELECT TOP 20
    ServerName,
    CollectionTime,
    MetricCategory,
    MetricName,
    MetricValue,
    MetricSource
FROM dbo.vw_PerformanceMetrics_Unified
ORDER BY CollectionTime DESC;
GO

-- Sample 3: Server health summary
PRINT ''
PRINT 'Sample 3: Server health summary'
SELECT
    ServerName,
    Environment,
    HealthStatus,
    LastCollectionTime,
    TotalSnapshots,
    LatestCpuPct,
    LatestSessionsCount,
    LatestBlockingCount
FROM dbo.vw_ServerSummary
ORDER BY
    CASE HealthStatus
        WHEN 'Stale' THEN 1
        WHEN 'Inactive' THEN 2
        WHEN 'Healthy' THEN 3
    END,
    ServerName;
GO

PRINT ''
GO

-- =====================================================
-- Step 5: API Compatibility Verification
-- =====================================================

PRINT 'Step 5: API compatibility verification...'
PRINT '-------------------------------------------'
GO

-- Verify view returns same structure as original PerformanceMetrics table
PRINT ''
PRINT 'API Compatibility Check:'
PRINT '  Original API expected columns: MetricID, ServerID, CollectionTime, MetricCategory, MetricName, MetricValue'
PRINT ''

SELECT
    COLUMN_NAME,
    DATA_TYPE,
    IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'vw_PerformanceMetrics'
ORDER BY ORDINAL_POSITION;
GO

PRINT ''
PRINT '  ✓ Verify above columns match API expectations'
PRINT ''
GO

-- =====================================================
-- Summary and Next Steps
-- =====================================================

PRINT '========================================================================='
PRINT 'View Deployment Test Complete'
PRINT '========================================================================='
PRINT ''
PRINT 'Database: ' + DB_NAME()
PRINT 'Views created: 10 total'
PRINT ''
PRINT 'Mapping Views (WIDE → TALL transformation):'
PRINT '  - vw_PerformanceMetrics_Core'
PRINT '  - vw_PerformanceMetrics_QueryStats'
PRINT '  - vw_PerformanceMetrics_IOStats'
PRINT '  - vw_PerformanceMetrics_Memory'
PRINT '  - vw_PerformanceMetrics_WaitStats'
PRINT ''
PRINT 'Unified Views (API Interface):'
PRINT '  - vw_PerformanceMetrics_Unified (primary)'
PRINT '  - vw_PerformanceMetrics (backward compatibility)'
PRINT ''
PRINT 'Aggregation Views:'
PRINT '  - vw_ServerSummary'
PRINT '  - vw_DatabaseSummary'
PRINT '  - vw_MetricCategories'
PRINT ''
PRINT 'Validation Tests: 27 tests executed'
PRINT 'Performance Benchmarks: 4 queries benchmarked'
PRINT ''
PRINT 'Next Steps (Day 3):'
PRINT '  1. Data migration strategy (handle existing PerformanceMetrics table)'
PRINT '  2. Update API to use new views'
PRINT '  3. Test with real workload data'
PRINT '  4. Document Day 2 completion'
PRINT ''
PRINT '========================================================================='
GO
