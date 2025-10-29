-- =====================================================
-- Script: test-phase-1.9-views.sql
-- Description: Unit tests for Phase 1.9 mapping views
-- Author: SQL Server Monitor Project
-- Date: 2025-10-28
-- Phase: 1.9 - Integration (Day 2)
-- Purpose: Validate WIDE → TALL transformation correctness
-- =====================================================

PRINT '========================================================================='
PRINT 'Phase 1.9 View Validation Tests'
PRINT '========================================================================='
PRINT ''
GO

-- =====================================================
-- Test Setup: Create sample data for testing
-- =====================================================

PRINT 'Setting up test data...'
PRINT '-------------------------------------------'
GO

-- Clean up any existing test data
DELETE FROM dbo.PerfSnapshotQueryStats WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM dbo.PerfSnapshotRun WHERE ServerName LIKE 'TEST-%');
DELETE FROM dbo.PerfSnapshotIOStats WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM dbo.PerfSnapshotRun WHERE ServerName LIKE 'TEST-%');
DELETE FROM dbo.PerfSnapshotMemory WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM dbo.PerfSnapshotRun WHERE ServerName LIKE 'TEST-%');
DELETE FROM dbo.PerfSnapshotWaitStats WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM dbo.PerfSnapshotRun WHERE ServerName LIKE 'TEST-%');
DELETE FROM dbo.PerfSnapshotRun WHERE ServerName LIKE 'TEST-%';
DELETE FROM dbo.Servers WHERE ServerName LIKE 'TEST-%';

-- Insert test server
INSERT INTO dbo.Servers (ServerName, Environment, IsActive)
VALUES ('TEST-SERVER-01', 'Test', 1);

DECLARE @TestServerID INT = SCOPE_IDENTITY();
DECLARE @TestRunID BIGINT;

-- Insert test PerfSnapshotRun
INSERT INTO dbo.PerfSnapshotRun (
    SnapshotUTC, ServerID, ServerName, SqlVersion,
    CpuSignalWaitPct, TopWaitType, TopWaitMsPerSec,
    SessionsCount, RequestsCount, BlockingSessionCount,
    DeadlockCountRecent, MemoryGrantWarningCount
)
VALUES (
    SYSUTCDATETIME(), @TestServerID, 'TEST-SERVER-01', '16.0.4095.4',
    25.5, 'PAGEIOLATCH_SH', 150.75,
    100, 25, 3,
    2, 5
);

SET @TestRunID = SCOPE_IDENTITY();

-- Insert test QueryStats
INSERT INTO dbo.PerfSnapshotQueryStats (
    PerfSnapshotRunID, QueryHash, DatabaseName, ObjectName,
    ExecutionCount, TotalCpuMs, AvgCpuMs, MaxCpuMs,
    TotalLogicalReads, AvgLogicalReads, MaxLogicalReads,
    TotalDurationMs, AvgDurationMs, MaxDurationMs
)
VALUES (
    @TestRunID, 0x1234567890ABCDEF, 'TestDB', 'usp_TestProcedure',
    1000, 50000, 50.0, 200.0,
    5000000, 5000.0, 25000.0,
    75000, 75.0, 350.0
);

-- Insert test IOStats
INSERT INTO dbo.PerfSnapshotIOStats (
    PerfSnapshotRunID, DatabaseName, PhysicalFileName,
    NumReads, BytesRead, IoStallReadMs, AvgReadLatencyMs,
    NumWrites, BytesWritten, IoStallWriteMs, AvgWriteLatencyMs,
    TotalIoStallMs
)
VALUES (
    @TestRunID, 'TestDB', 'C:\Data\TestDB.mdf',
    10000, 81920000, 5000, 0.5,
    5000, 40960000, 2500, 0.5,
    7500
);

-- Insert test Memory
INSERT INTO dbo.PerfSnapshotMemory (
    PerfSnapshotRunID,
    PageLifeExpectancySec, BufferCacheSizeMB, TargetServerMemoryMB,
    TotalServerMemoryMB, BufferCacheHitRatioPct,
    PendingMemoryGrantsCount, ActiveMemoryGrantsMB,
    MemoryGrantsWaitingCount, MaxServerMemoryMB, AvailablePhysicalMemoryMB
)
VALUES (
    @TestRunID,
    3600, 8192, 16384,
    16384, 99.5,
    2, 512,
    0, 16384, 4096
);

-- Insert test WaitStats
INSERT INTO dbo.PerfSnapshotWaitStats (
    PerfSnapshotRunID, WaitType,
    WaitingTasksCount, WaitTimeMs, MaxWaitTimeMs,
    SignalWaitTimeMs, ResourceWaitTimeMs, WaitTimeMsPerSec
)
VALUES (
    @TestRunID, 'PAGEIOLATCH_SH',
    150, 150000, 5000,
    5000, 145000, 150.75
);

PRINT '  ✓ Test data created'
PRINT ''
GO

-- =====================================================
-- TEST CATEGORY 1: View Existence
-- =====================================================

PRINT 'TEST CATEGORY 1: View Existence'
PRINT '-------------------------------------------'
GO

DECLARE @TestsPassed INT = 0;
DECLARE @TestsFailed INT = 0;
DECLARE @TestName NVARCHAR(200);
DECLARE @Result NVARCHAR(10);

-- Test 1.1: vw_PerformanceMetrics_Core exists
SET @TestName = 'Test 1.1: vw_PerformanceMetrics_Core exists';
IF OBJECT_ID('dbo.vw_PerformanceMetrics_Core', 'V') IS NOT NULL
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

-- Test 1.2: vw_PerformanceMetrics_QueryStats exists
SET @TestName = 'Test 1.2: vw_PerformanceMetrics_QueryStats exists';
IF OBJECT_ID('dbo.vw_PerformanceMetrics_QueryStats', 'V') IS NOT NULL
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

-- Test 1.3: vw_PerformanceMetrics_IOStats exists
SET @TestName = 'Test 1.3: vw_PerformanceMetrics_IOStats exists';
IF OBJECT_ID('dbo.vw_PerformanceMetrics_IOStats', 'V') IS NOT NULL
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

-- Test 1.4: vw_PerformanceMetrics_Memory exists
SET @TestName = 'Test 1.4: vw_PerformanceMetrics_Memory exists';
IF OBJECT_ID('dbo.vw_PerformanceMetrics_Memory', 'V') IS NOT NULL
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

-- Test 1.5: vw_PerformanceMetrics_WaitStats exists
SET @TestName = 'Test 1.5: vw_PerformanceMetrics_WaitStats exists';
IF OBJECT_ID('dbo.vw_PerformanceMetrics_WaitStats', 'V') IS NOT NULL
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

-- Test 1.6: vw_PerformanceMetrics_Unified exists
SET @TestName = 'Test 1.6: vw_PerformanceMetrics_Unified exists';
IF OBJECT_ID('dbo.vw_PerformanceMetrics_Unified', 'V') IS NOT NULL
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

-- Test 1.7: vw_PerformanceMetrics exists (backward compat)
SET @TestName = 'Test 1.7: vw_PerformanceMetrics exists (backward compat)';
IF OBJECT_ID('dbo.vw_PerformanceMetrics', 'V') IS NOT NULL
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

-- Test 1.8: vw_ServerSummary exists
SET @TestName = 'Test 1.8: vw_ServerSummary exists';
IF OBJECT_ID('dbo.vw_ServerSummary', 'V') IS NOT NULL
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

-- Test 1.9: vw_DatabaseSummary exists
SET @TestName = 'Test 1.9: vw_DatabaseSummary exists';
IF OBJECT_ID('dbo.vw_DatabaseSummary', 'V') IS NOT NULL
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

-- Test 1.10: vw_MetricCategories exists
SET @TestName = 'Test 1.10: vw_MetricCategories exists';
IF OBJECT_ID('dbo.vw_MetricCategories', 'V') IS NOT NULL
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

PRINT ''
GO

-- =====================================================
-- TEST CATEGORY 2: Column Structure
-- =====================================================

PRINT 'TEST CATEGORY 2: Column Structure (API Compatibility)'
PRINT '-------------------------------------------'
GO

DECLARE @TestsPassed INT = 0;
DECLARE @TestsFailed INT = 0;
DECLARE @TestName NVARCHAR(200);
DECLARE @Result NVARCHAR(10);
DECLARE @ColumnCount INT;

-- Test 2.1: vw_PerformanceMetrics has required columns
SET @TestName = 'Test 2.1: vw_PerformanceMetrics has required columns';
SELECT @ColumnCount = COUNT(*)
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'vw_PerformanceMetrics'
  AND COLUMN_NAME IN ('MetricID', 'ServerID', 'CollectionTime', 'MetricCategory', 'MetricName', 'MetricValue');

IF @ColumnCount = 6
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Expected: 6 columns, Found: ' + CAST(@ColumnCount AS VARCHAR);
END
PRINT @TestName + ': ' + @Result;

-- Test 2.2: vw_PerformanceMetrics_Unified has MetricSource column
SET @TestName = 'Test 2.2: vw_PerformanceMetrics_Unified has MetricSource';
IF EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = 'vw_PerformanceMetrics_Unified'
      AND COLUMN_NAME = 'MetricSource'
)
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

-- Test 2.3: vw_ServerSummary has health status column
SET @TestName = 'Test 2.3: vw_ServerSummary has HealthStatus column';
IF EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = 'vw_ServerSummary'
      AND COLUMN_NAME = 'HealthStatus'
)
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

PRINT ''
GO

-- =====================================================
-- TEST CATEGORY 3: Data Transformation (WIDE → TALL)
-- =====================================================

PRINT 'TEST CATEGORY 3: Data Transformation (WIDE → TALL Unpivoting)'
PRINT '-------------------------------------------'
GO

DECLARE @TestsPassed INT = 0;
DECLARE @TestsFailed INT = 0;
DECLARE @TestName NVARCHAR(200);
DECLARE @Result NVARCHAR(10);
DECLARE @RowCount INT;
DECLARE @TestRunID BIGINT;

-- Get test run ID
SELECT @TestRunID = PerfSnapshotRunID
FROM dbo.PerfSnapshotRun
WHERE ServerName = 'TEST-SERVER-01';

-- Test 3.1: Core view unpivots to multiple rows
SET @TestName = 'Test 3.1: Core view unpivots 1 row → N rows';
SELECT @RowCount = COUNT(*)
FROM dbo.vw_PerformanceMetrics_Core
WHERE RunID = @TestRunID;

IF @RowCount >= 7  -- Should create at least 7 metrics from 1 PerfSnapshotRun row
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
    PRINT '  1 PerfSnapshotRun row → ' + CAST(@RowCount AS VARCHAR) + ' metric rows';
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Expected: >= 7 rows, Found: ' + CAST(@RowCount AS VARCHAR);
END
PRINT @TestName + ': ' + @Result;

-- Test 3.2: QueryStats view creates metrics
SET @TestName = 'Test 3.2: QueryStats view unpivots correctly';
SELECT @RowCount = COUNT(*)
FROM dbo.vw_PerformanceMetrics_QueryStats
WHERE RunID = @TestRunID;

IF @RowCount >= 10  -- Should create ~10 metrics from 1 QueryStats row
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
    PRINT '  1 QueryStats row → ' + CAST(@RowCount AS VARCHAR) + ' metric rows';
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Expected: >= 10 rows, Found: ' + CAST(@RowCount AS VARCHAR);
END
PRINT @TestName + ': ' + @Result;

-- Test 3.3: IOStats view creates metrics
SET @TestName = 'Test 3.3: IOStats view unpivots correctly';
SELECT @RowCount = COUNT(*)
FROM dbo.vw_PerformanceMetrics_IOStats
WHERE RunID = @TestRunID;

IF @RowCount >= 9  -- Should create ~9 metrics from 1 IOStats row
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
    PRINT '  1 IOStats row → ' + CAST(@RowCount AS VARCHAR) + ' metric rows';
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Expected: >= 9 rows, Found: ' + CAST(@RowCount AS VARCHAR);
END
PRINT @TestName + ': ' + @Result;

-- Test 3.4: Memory view creates metrics
SET @TestName = 'Test 3.4: Memory view unpivots correctly';
SELECT @RowCount = COUNT(*)
FROM dbo.vw_PerformanceMetrics_Memory
WHERE RunID = @TestRunID;

IF @RowCount >= 10  -- Should create ~10 metrics from 1 Memory row
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
    PRINT '  1 Memory row → ' + CAST(@RowCount AS VARCHAR) + ' metric rows';
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Expected: >= 10 rows, Found: ' + CAST(@RowCount AS VARCHAR);
END
PRINT @TestName + ': ' + @Result;

-- Test 3.5: WaitStats view creates metrics
SET @TestName = 'Test 3.5: WaitStats view unpivots correctly';
SELECT @RowCount = COUNT(*)
FROM dbo.vw_PerformanceMetrics_WaitStats
WHERE RunID = @TestRunID;

IF @RowCount >= 6  -- Should create ~6 metrics from 1 WaitStats row
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
    PRINT '  1 WaitStats row → ' + CAST(@RowCount AS VARCHAR) + ' metric rows';
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Expected: >= 6 rows, Found: ' + CAST(@RowCount AS VARCHAR);
END
PRINT @TestName + ': ' + @Result;

PRINT ''
GO

-- =====================================================
-- TEST CATEGORY 4: Data Accuracy
-- =====================================================

PRINT 'TEST CATEGORY 4: Data Accuracy (Value Preservation)'
PRINT '-------------------------------------------'
GO

DECLARE @TestsPassed INT = 0;
DECLARE @TestsFailed INT = 0;
DECLARE @TestName NVARCHAR(200);
DECLARE @Result NVARCHAR(10);
DECLARE @ExpectedValue DECIMAL(18,4);
DECLARE @ActualValue DECIMAL(18,4);
DECLARE @TestRunID BIGINT;

SELECT @TestRunID = PerfSnapshotRunID
FROM dbo.PerfSnapshotRun
WHERE ServerName = 'TEST-SERVER-01';

-- Test 4.1: CPU metric value preserved
SET @TestName = 'Test 4.1: CPU metric value preserved (25.5)';
SELECT @ExpectedValue = CpuSignalWaitPct
FROM dbo.PerfSnapshotRun
WHERE PerfSnapshotRunID = @TestRunID;

SELECT @ActualValue = MetricValue
FROM dbo.vw_PerformanceMetrics_Core
WHERE RunID = @TestRunID
  AND MetricName = 'CpuSignalWaitPct';

IF ABS(@ExpectedValue - @ActualValue) < 0.01
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
    PRINT '  Expected: ' + CAST(@ExpectedValue AS VARCHAR) + ', Actual: ' + CAST(@ActualValue AS VARCHAR);
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Expected: ' + CAST(@ExpectedValue AS VARCHAR) + ', Actual: ' + CAST(@ActualValue AS VARCHAR);
END
PRINT @TestName + ': ' + @Result;

-- Test 4.2: SessionsCount metric value preserved
SET @TestName = 'Test 4.2: SessionsCount value preserved (100)';
SELECT @ExpectedValue = SessionsCount
FROM dbo.PerfSnapshotRun
WHERE PerfSnapshotRunID = @TestRunID;

SELECT @ActualValue = MetricValue
FROM dbo.vw_PerformanceMetrics_Core
WHERE RunID = @TestRunID
  AND MetricName = 'SessionsCount';

IF ABS(@ExpectedValue - @ActualValue) < 0.01
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
    PRINT '  Expected: ' + CAST(@ExpectedValue AS VARCHAR) + ', Actual: ' + CAST(@ActualValue AS VARCHAR);
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Expected: ' + CAST(@ExpectedValue AS VARCHAR) + ', Actual: ' + CAST(@ActualValue AS VARCHAR);
END
PRINT @TestName + ': ' + @Result;

-- Test 4.3: TopWaitMsPerSec metric value preserved
SET @TestName = 'Test 4.3: TopWaitMsPerSec value preserved (150.75)';
SELECT @ExpectedValue = TopWaitMsPerSec
FROM dbo.PerfSnapshotRun
WHERE PerfSnapshotRunID = @TestRunID;

SELECT @ActualValue = MetricValue
FROM dbo.vw_PerformanceMetrics_Core
WHERE RunID = @TestRunID
  AND MetricName = 'TopWaitMsPerSec';

IF ABS(@ExpectedValue - @ActualValue) < 0.01
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
    PRINT '  Expected: ' + CAST(@ExpectedValue AS VARCHAR) + ', Actual: ' + CAST(@ActualValue AS VARCHAR);
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Expected: ' + CAST(@ExpectedValue AS VARCHAR) + ', Actual: ' + CAST(@ActualValue AS VARCHAR);
END
PRINT @TestName + ': ' + @Result;

PRINT ''
GO

-- =====================================================
-- TEST CATEGORY 5: UNION ALL Correctness
-- =====================================================

PRINT 'TEST CATEGORY 5: UNION ALL Correctness'
PRINT '-------------------------------------------'
GO

DECLARE @TestsPassed INT = 0;
DECLARE @TestsFailed INT = 0;
DECLARE @TestName NVARCHAR(200);
DECLARE @Result NVARCHAR(10);
DECLARE @SourceCount INT;
DECLARE @TestRunID BIGINT;

SELECT @TestRunID = PerfSnapshotRunID
FROM dbo.PerfSnapshotRun
WHERE ServerName = 'TEST-SERVER-01';

-- Test 5.1: Unified view contains all sources
SET @TestName = 'Test 5.1: Unified view contains all metric sources';
SELECT @SourceCount = COUNT(DISTINCT MetricSource)
FROM dbo.vw_PerformanceMetrics_Unified
WHERE RunID = @TestRunID;

IF @SourceCount = 5  -- Core, QueryStats, IOStats, Memory, WaitStats
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
    PRINT '  Found ' + CAST(@SourceCount AS VARCHAR) + ' distinct sources';
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Expected: 5 sources, Found: ' + CAST(@SourceCount AS VARCHAR);
END
PRINT @TestName + ': ' + @Result;

-- Test 5.2: Backward compat view omits MetricSource
SET @TestName = 'Test 5.2: Backward compat view omits MetricSource';
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = 'vw_PerformanceMetrics'
      AND COLUMN_NAME = 'MetricSource'
)
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  MetricSource column should not exist in backward compat view';
END
PRINT @TestName + ': ' + @Result;

-- Test 5.3: Unified view row count matches sum of sources
SET @TestName = 'Test 5.3: Unified view row count = sum of sources';
DECLARE @UnifiedCount INT, @SumSourcesCount INT;

SELECT @UnifiedCount = COUNT(*)
FROM dbo.vw_PerformanceMetrics_Unified
WHERE RunID = @TestRunID;

SELECT @SumSourcesCount = (
    (SELECT COUNT(*) FROM dbo.vw_PerformanceMetrics_Core WHERE RunID = @TestRunID) +
    (SELECT COUNT(*) FROM dbo.vw_PerformanceMetrics_QueryStats WHERE RunID = @TestRunID) +
    (SELECT COUNT(*) FROM dbo.vw_PerformanceMetrics_IOStats WHERE RunID = @TestRunID) +
    (SELECT COUNT(*) FROM dbo.vw_PerformanceMetrics_Memory WHERE RunID = @TestRunID) +
    (SELECT COUNT(*) FROM dbo.vw_PerformanceMetrics_WaitStats WHERE RunID = @TestRunID)
);

IF @UnifiedCount = @SumSourcesCount
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
    PRINT '  Unified: ' + CAST(@UnifiedCount AS VARCHAR) + ' rows = Sum: ' + CAST(@SumSourcesCount AS VARCHAR) + ' rows';
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Unified: ' + CAST(@UnifiedCount AS VARCHAR) + ' rows ≠ Sum: ' + CAST(@SumSourcesCount AS VARCHAR) + ' rows';
END
PRINT @TestName + ': ' + @Result;

PRINT ''
GO

-- =====================================================
-- TEST CATEGORY 6: Aggregation Views
-- =====================================================

PRINT 'TEST CATEGORY 6: Aggregation Views'
PRINT '-------------------------------------------'
GO

DECLARE @TestsPassed INT = 0;
DECLARE @TestsFailed INT = 0;
DECLARE @TestName NVARCHAR(200);
DECLARE @Result NVARCHAR(10);
DECLARE @RowCount INT;

-- Test 6.1: ServerSummary returns test server
SET @TestName = 'Test 6.1: ServerSummary returns test server';
SELECT @RowCount = COUNT(*)
FROM dbo.vw_ServerSummary
WHERE ServerName = 'TEST-SERVER-01';

IF @RowCount = 1
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Expected: 1 row, Found: ' + CAST(@RowCount AS VARCHAR);
END
PRINT @TestName + ': ' + @Result;

-- Test 6.2: ServerSummary calculates LatestCpuPct
SET @TestName = 'Test 6.2: ServerSummary calculates LatestCpuPct';
DECLARE @LatestCpu DECIMAL(9,4);
SELECT @LatestCpu = LatestCpuPct
FROM dbo.vw_ServerSummary
WHERE ServerName = 'TEST-SERVER-01';

IF @LatestCpu IS NOT NULL AND @LatestCpu > 0
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
    PRINT '  Latest CPU: ' + CAST(@LatestCpu AS VARCHAR) + '%';
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Latest CPU is NULL or 0';
END
PRINT @TestName + ': ' + @Result;

-- Test 6.3: MetricCategories lists all categories
SET @TestName = 'Test 6.3: MetricCategories lists metric catalog';
SELECT @RowCount = COUNT(DISTINCT MetricCategory)
FROM dbo.vw_MetricCategories;

IF @RowCount >= 5  -- CPU, Memory, Waits, Query, IO
BEGIN
    SET @Result = '✓ PASS';
    SET @TestsPassed = @TestsPassed + 1;
    PRINT '  Found ' + CAST(@RowCount AS VARCHAR) + ' metric categories';
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @TestsFailed = @TestsFailed + 1;
    PRINT '  Expected: >= 5 categories, Found: ' + CAST(@RowCount AS VARCHAR);
END
PRINT @TestName + ': ' + @Result;

PRINT ''
GO

-- =====================================================
-- TEST SUMMARY
-- =====================================================

DECLARE @TotalTests INT;
DECLARE @TotalPassed INT;
DECLARE @TotalFailed INT;

-- Count total tests (sum of all categories)
-- Category 1: 10 tests
-- Category 2: 3 tests
-- Category 3: 5 tests
-- Category 4: 3 tests
-- Category 5: 3 tests
-- Category 6: 3 tests
SET @TotalTests = 27;

-- Calculate totals from all test blocks
-- Note: This is approximate due to variable scope limitations
-- In practice, run this script to get actual counts

PRINT '========================================================================='
PRINT 'TEST SUMMARY'
PRINT '========================================================================='
PRINT ''
PRINT 'Test Categories:'
PRINT '  Category 1: View Existence (10 tests)'
PRINT '  Category 2: Column Structure (3 tests)'
PRINT '  Category 3: Data Transformation (5 tests)'
PRINT '  Category 4: Data Accuracy (3 tests)'
PRINT '  Category 5: UNION ALL Correctness (3 tests)'
PRINT '  Category 6: Aggregation Views (3 tests)'
PRINT ''
PRINT 'Total Tests: 27'
PRINT ''
PRINT 'If all tests passed, you should see 27 ✓ PASS results above.'
PRINT ''
PRINT '========================================================================='
PRINT 'Phase 1.9 View Validation Complete'
PRINT '========================================================================='
PRINT ''
PRINT 'Next Steps:'
PRINT '  1. Run performance benchmarks (query execution time)'
PRINT '  2. Test API compatibility with new views'
PRINT '  3. Deploy to DBATools and MonitoringDB'
PRINT '  4. Document Day 2 completion'
PRINT ''
GO

-- =====================================================
-- Cleanup: Remove test data
-- =====================================================

PRINT 'Cleaning up test data...'
GO

DELETE FROM dbo.PerfSnapshotQueryStats WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM dbo.PerfSnapshotRun WHERE ServerName LIKE 'TEST-%');
DELETE FROM dbo.PerfSnapshotIOStats WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM dbo.PerfSnapshotRun WHERE ServerName LIKE 'TEST-%');
DELETE FROM dbo.PerfSnapshotMemory WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM dbo.PerfSnapshotRun WHERE ServerName LIKE 'TEST-%');
DELETE FROM dbo.PerfSnapshotWaitStats WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM dbo.PerfSnapshotRun WHERE ServerName LIKE 'TEST-%');
DELETE FROM dbo.PerfSnapshotRun WHERE ServerName LIKE 'TEST-%';
DELETE FROM dbo.Servers WHERE ServerName LIKE 'TEST-%';

PRINT '  ✓ Test data cleaned up'
PRINT ''
GO
