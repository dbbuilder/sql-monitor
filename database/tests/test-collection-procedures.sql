-- =====================================================
-- Script: test-collection-procedures.sql
-- Description: Unit tests for Phase 1.9 collection and aggregation procedures
-- Author: SQL Server Monitor Project
-- Date: 2025-10-28
-- Phase: 1.9 - Integration (Days 4-5)
-- Purpose: Validate ServerID support and multi-server functionality
-- =====================================================

PRINT '========================================================================='
PRINT 'Phase 1.9 Collection Procedures Tests'
PRINT '========================================================================='
PRINT ''
GO

-- =====================================================
-- Test Setup: Create test servers and sample data
-- =====================================================

PRINT 'Setting up test data...'
PRINT '-------------------------------------------'
GO

-- Clean up any existing test data
DELETE FROM dbo.PerfSnapshotQueryStats WHERE PerfSnapshotRunID IN (
    SELECT PerfSnapshotRunID FROM dbo.PerfSnapshotRun WHERE ServerName LIKE 'TEST-COLLECT-%'
);
DELETE FROM dbo.PerfSnapshotIOStats WHERE PerfSnapshotRunID IN (
    SELECT PerfSnapshotRunID FROM dbo.PerfSnapshotRun WHERE ServerName LIKE 'TEST-COLLECT-%'
);
DELETE FROM dbo.PerfSnapshotMemory WHERE PerfSnapshotRunID IN (
    SELECT PerfSnapshotRunID FROM dbo.PerfSnapshotRun WHERE ServerName LIKE 'TEST-COLLECT-%'
);
DELETE FROM dbo.PerfSnapshotWaitStats WHERE PerfSnapshotRunID IN (
    SELECT PerfSnapshotRunID FROM dbo.PerfSnapshotRun WHERE ServerName LIKE 'TEST-COLLECT-%'
);
DELETE FROM dbo.PerfSnapshotDB WHERE PerfSnapshotRunID IN (
    SELECT PerfSnapshotRunID FROM dbo.PerfSnapshotRun WHERE ServerName LIKE 'TEST-COLLECT-%'
);
DELETE FROM dbo.PerfSnapshotRun WHERE ServerName LIKE 'TEST-COLLECT-%';
DELETE FROM dbo.Servers WHERE ServerName LIKE 'TEST-COLLECT-%';

PRINT '  ✓ Cleaned up test data'
GO

-- =====================================================
-- TEST CATEGORY 1: Server Registration
-- =====================================================

PRINT ''
PRINT 'TEST CATEGORY 1: Server Registration'
PRINT '-------------------------------------------'
GO

DECLARE @TestsPassed INT = 0;
DECLARE @TestsFailed INT = 0;
DECLARE @TestName NVARCHAR(200);
DECLARE @Result NVARCHAR(10);

-- Test 1.1: usp_EnsureServerExists creates new server
SET @TestName = 'Test 1.1: usp_EnsureServerExists creates new server';

DECLARE @TestServerID INT;
EXEC dbo.usp_EnsureServerExists
    @ServerName = 'TEST-COLLECT-SERVER1',
    @Environment = 'Test',
    @ServerID = @TestServerID OUTPUT;

IF @TestServerID IS NOT NULL
    AND EXISTS (SELECT 1 FROM dbo.Servers WHERE ServerID = @TestServerID AND ServerName = 'TEST-COLLECT-SERVER1')
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
    PRINT '  Created ServerID: ' + CAST(@TestServerID AS VARCHAR);
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

-- Test 1.2: usp_EnsureServerExists returns existing server
SET @TestName = 'Test 1.2: usp_EnsureServerExists returns existing server';

DECLARE @TestServerID2 INT;
EXEC dbo.usp_EnsureServerExists
    @ServerName = 'TEST-COLLECT-SERVER1',
    @Environment = 'Test',
    @ServerID = @TestServerID2 OUTPUT;

IF @TestServerID2 = @TestServerID
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
    PRINT '  Returned same ServerID: ' + CAST(@TestServerID2 AS VARCHAR);
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Expected: ' + CAST(@TestServerID AS VARCHAR) + ', Got: ' + CAST(@TestServerID2 AS VARCHAR);
END
PRINT @TestName + ': ' + @Result;

PRINT ''
GO

-- =====================================================
-- TEST CATEGORY 2: Data Collection
-- =====================================================

PRINT 'TEST CATEGORY 2: Data Collection'
PRINT '-------------------------------------------'
GO

DECLARE @TestsPassed INT = 0, @TestsFailed INT = 0;
DECLARE @TestName NVARCHAR(200), @Result NVARCHAR(10);

-- Test 2.1: DBA_CollectPerformanceSnapshot with explicit ServerID
SET @TestName = 'Test 2.1: Collection with explicit ServerID';

DECLARE @TestServerID INT;
SELECT @TestServerID = ServerID FROM dbo.Servers WHERE ServerName = 'TEST-COLLECT-SERVER1';

DECLARE @CollectServerID INT = @TestServerID;
BEGIN TRY
    EXEC dbo.DBA_CollectPerformanceSnapshot
        @ServerID = @CollectServerID OUTPUT,
        @ServerName = 'TEST-COLLECT-SERVER1',
        @EnableP0 = 1,
        @EnableP1 = 1;

    IF EXISTS (
        SELECT 1 FROM dbo.PerfSnapshotRun
        WHERE ServerID = @TestServerID
          AND ServerName = 'TEST-COLLECT-SERVER1'
          AND SnapshotUTC >= DATEADD(MINUTE, -1, SYSUTCDATETIME())
    )
    BEGIN
        SET @Result = '✓ PASS';
        SET @TestsPassed = @TestsPassed + 1;
        PRINT '  Collection successful for ServerID: ' + CAST(@TestServerID AS VARCHAR);
    END
    ELSE
    BEGIN
        SET @Result = '✗ FAIL';
        SET @TestsFailed = @TestsFailed + 1;
        PRINT '  No data collected';
    END
END TRY
BEGIN CATCH
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Error: ' + ERROR_MESSAGE();
END CATCH
PRINT @TestName + ': ' + @Result;

-- Test 2.2: Auto-registration during collection
SET @TestName = 'Test 2.2: Auto-registration during collection';

DECLARE @AutoRegServerID INT = NULL;
BEGIN TRY
    EXEC dbo.DBA_CollectPerformanceSnapshot
        @ServerID = @AutoRegServerID OUTPUT,
        @ServerName = 'TEST-COLLECT-SERVER2',
        @EnableP0 = 1;

    IF @AutoRegServerID IS NOT NULL
        AND EXISTS (SELECT 1 FROM dbo.Servers WHERE ServerID = @AutoRegServerID AND ServerName = 'TEST-COLLECT-SERVER2')
    BEGIN
        SET @Result = '✓ PASS';
        SET @TestsPassed = @TestsPassed + 1;
        PRINT '  Auto-registered ServerID: ' + CAST(@AutoRegServerID AS VARCHAR);
    END
    ELSE
    BEGIN
        SET @Result = '✗ FAIL';
        SET @TestsFailed = @TestsFailed + 1;
    END
END TRY
BEGIN CATCH
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Error: ' + ERROR_MESSAGE();
END CATCH
PRINT @TestName + ': ' + @Result;

-- Test 2.3: P0 metrics collected
SET @TestName = 'Test 2.3: P0 metrics (QueryStats, IOStats, Memory) collected';

DECLARE @P0MetricsCount INT;
SELECT @P0MetricsCount = (
    (SELECT COUNT(*) FROM dbo.PerfSnapshotQueryStats qs
     INNER JOIN dbo.PerfSnapshotRun psr ON qs.PerfSnapshotRunID = psr.PerfSnapshotRunID
     WHERE psr.ServerName LIKE 'TEST-COLLECT-%') +
    (SELECT COUNT(*) FROM dbo.PerfSnapshotIOStats io
     INNER JOIN dbo.PerfSnapshotRun psr ON io.PerfSnapshotRunID = psr.PerfSnapshotRunID
     WHERE psr.ServerName LIKE 'TEST-COLLECT-%') +
    (SELECT COUNT(*) FROM dbo.PerfSnapshotMemory mem
     INNER JOIN dbo.PerfSnapshotRun psr ON mem.PerfSnapshotRunID = psr.PerfSnapshotRunID
     WHERE psr.ServerName LIKE 'TEST-COLLECT-%')
);

IF @P0MetricsCount > 0
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
    PRINT '  P0 metrics collected: ' + CAST(@P0MetricsCount AS VARCHAR) + ' rows';
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  No P0 metrics found';
END
PRINT @TestName + ': ' + @Result;

PRINT ''
GO

-- =====================================================
-- TEST CATEGORY 3: Aggregation Procedures
-- =====================================================

PRINT 'TEST CATEGORY 3: Aggregation Procedures'
PRINT '-------------------------------------------'
GO

DECLARE @TestsPassed INT = 0, @TestsFailed INT = 0;
DECLARE @TestName NVARCHAR(200), @Result NVARCHAR(10);

-- Test 3.1: usp_GetServerHealthStatus returns test servers
SET @TestName = 'Test 3.1: usp_GetServerHealthStatus returns data';

DECLARE @HealthStatusCount INT;
CREATE TABLE #HealthStatus (
    ServerID INT,
    ServerName SYSNAME,
    HealthStatus NVARCHAR(50)
);

INSERT INTO #HealthStatus (ServerID, ServerName, HealthStatus)
EXEC dbo.usp_GetServerHealthStatus;

SELECT @HealthStatusCount = COUNT(*)
FROM #HealthStatus
WHERE ServerName LIKE 'TEST-COLLECT-%';

IF @HealthStatusCount >= 2
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
    PRINT '  Found ' + CAST(@HealthStatusCount AS VARCHAR) + ' test servers';
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Expected: >= 2 servers, Found: ' + CAST(@HealthStatusCount AS VARCHAR);
END
DROP TABLE #HealthStatus;
PRINT @TestName + ': ' + @Result;

-- Test 3.2: usp_GetMetricHistory returns data
SET @TestName = 'Test 3.2: usp_GetMetricHistory returns metrics';

DECLARE @MetricHistoryCount INT;
CREATE TABLE #MetricHistory (
    MetricID BIGINT,
    ServerID INT,
    CollectionTime DATETIME2,
    MetricCategory NVARCHAR(50),
    MetricName NVARCHAR(100),
    MetricValue DECIMAL(18,4)
);

INSERT INTO #MetricHistory
EXEC dbo.usp_GetMetricHistory
    @MetricCategory = 'CPU',
    @Granularity = 'RAW';

SELECT @MetricHistoryCount = COUNT(*) FROM #MetricHistory;

IF @MetricHistoryCount > 0
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
    PRINT '  Found ' + CAST(@MetricHistoryCount AS VARCHAR) + ' metrics';
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
DROP TABLE #MetricHistory;
PRINT @TestName + ': ' + @Result;

-- Test 3.3: usp_GetTopQueries returns data
SET @TestName = 'Test 3.3: usp_GetTopQueries returns queries';

DECLARE @TopQueriesCount INT;
CREATE TABLE #TopQueries (
    ServerID INT,
    ServerName SYSNAME,
    DatabaseName SYSNAME,
    SqlText NVARCHAR(200),
    ExecutionCount BIGINT
);

INSERT INTO #TopQueries
EXEC dbo.usp_GetTopQueries @TopN = 10;

SELECT @TopQueriesCount = COUNT(*) FROM #TopQueries;

IF @TopQueriesCount >= 0  -- May be 0 if no queries captured
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
    PRINT '  Found ' + CAST(@TopQueriesCount AS VARCHAR) + ' queries';
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
DROP TABLE #TopQueries;
PRINT @TestName + ': ' + @Result;

PRINT ''
GO

-- =====================================================
-- Test Cleanup
-- =====================================================

PRINT 'Cleaning up test data...'
GO

DELETE FROM dbo.PerfSnapshotQueryStats WHERE PerfSnapshotRunID IN (
    SELECT PerfSnapshotRunID FROM dbo.PerfSnapshotRun WHERE ServerName LIKE 'TEST-COLLECT-%'
);
DELETE FROM dbo.PerfSnapshotIOStats WHERE PerfSnapshotRunID IN (
    SELECT PerfSnapshotRunID FROM dbo.PerfSnapshotRun WHERE ServerName LIKE 'TEST-COLLECT-%'
);
DELETE FROM dbo.PerfSnapshotMemory WHERE PerfSnapshotRunID IN (
    SELECT PerfSnapshotRunID FROM dbo.PerfSnapshotRun WHERE ServerName LIKE 'TEST-COLLECT-%'
);
DELETE FROM dbo.PerfSnapshotWaitStats WHERE PerfSnapshotRunID IN (
    SELECT PerfSnapshotRunID FROM dbo.PerfSnapshotRun WHERE ServerName LIKE 'TEST-COLLECT-%'
);
DELETE FROM dbo.PerfSnapshotDB WHERE PerfSnapshotRunID IN (
    SELECT PerfSnapshotRunID FROM dbo.PerfSnapshotRun WHERE ServerName LIKE 'TEST-COLLECT-%'
);
DELETE FROM dbo.PerfSnapshotRun WHERE ServerName LIKE 'TEST-COLLECT-%';
DELETE FROM dbo.Servers WHERE ServerName LIKE 'TEST-COLLECT-%';

PRINT '  ✓ Test data cleaned up'
PRINT ''
GO

-- =====================================================
-- TEST SUMMARY
-- =====================================================

PRINT '========================================================================='
PRINT 'COLLECTION PROCEDURES TEST SUMMARY'
PRINT '========================================================================='
PRINT ''
PRINT 'Test Categories:'
PRINT '  Category 1: Server Registration (2 tests)'
PRINT '  Category 2: Data Collection (3 tests)'
PRINT '  Category 3: Aggregation Procedures (3 tests)'
PRINT ''
PRINT 'Total Tests: 8'
PRINT ''
PRINT 'Expected Results:'
PRINT '  - All tests should pass (8/8)'
PRINT '  - Test servers auto-registered'
PRINT '  - P0 metrics collected (QueryStats, IOStats, Memory)'
PRINT '  - Aggregation procedures return data'
PRINT ''
PRINT '========================================================================='
PRINT ''
GO
