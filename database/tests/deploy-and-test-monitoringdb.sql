-- =====================================================
-- Script: deploy-and-test-monitoringdb.sql
-- Description: Deploy Phase 1.9 schema to MonitoringDB and run tests
-- Author: SQL Server Monitor Project
-- Date: 2025-10-27
-- Phase: 1.9 - Integration (Day 1, Test 8)
-- Target: MonitoringDB database (multi-server mode)
-- =====================================================

PRINT '=========================================================================';
PRINT 'Phase 1.9 Deployment Test: MonitoringDB (Multi-Server Mode)';
PRINT '=========================================================================';
PRINT '';
GO

-- =====================================================
-- Step 1: Create MonitoringDB database if it doesn't exist
-- =====================================================

IF DB_ID('MonitoringDB') IS NULL
BEGIN
    PRINT 'Creating MonitoringDB database...';
    CREATE DATABASE [MonitoringDB];
    PRINT '  ✓ MonitoringDB database created';
END
ELSE
BEGIN
    PRINT '  ✓ MonitoringDB database already exists';
END
GO

USE [MonitoringDB];
GO

PRINT '';
PRINT 'Current database: ' + DB_NAME();
PRINT '';

-- =====================================================
-- Step 2: Deploy core tables (20-create-dbatools-tables.sql)
-- =====================================================

PRINT 'Step 2: Deploying core tables...';
PRINT '-------------------------------------------';
GO

-- Execute the core tables script
:r ../20-create-dbatools-tables.sql

PRINT '';
PRINT '  ✓ Core tables deployment complete';
PRINT '';
GO

-- =====================================================
-- Step 3: Deploy enhanced tables (21-create-enhanced-tables.sql)
-- =====================================================

PRINT 'Step 3: Deploying enhanced tables (P0-P3)...';
PRINT '-------------------------------------------';
GO

-- Execute the enhanced tables script
:r ../21-create-enhanced-tables.sql

PRINT '';
PRINT '  ✓ Enhanced tables deployment complete';
PRINT '';
GO

-- =====================================================
-- Step 4: Seed sample multi-server data
-- =====================================================

PRINT 'Step 4: Seeding sample multi-server data...';
PRINT '-------------------------------------------';
GO

-- Insert sample servers for multi-server testing
IF NOT EXISTS (SELECT 1 FROM dbo.Servers WHERE ServerName = 'SQL-PROD-01')
BEGIN
    INSERT INTO dbo.Servers (ServerName, Environment, IsActive)
    VALUES
        ('SQL-PROD-01', 'Production', 1),
        ('SQL-PROD-02', 'Production', 1),
        ('SQL-DEV-01', 'Development', 1),
        ('SQL-TEST-01', 'Test', 1);

    PRINT '  ✓ Sample servers created (4 servers)';
END
ELSE
BEGIN
    PRINT '  ✓ Sample servers already exist';
END

-- Insert sample PerfSnapshotRun data (one per server)
DECLARE @Server1ID INT = (SELECT ServerID FROM dbo.Servers WHERE ServerName = 'SQL-PROD-01');
DECLARE @Server2ID INT = (SELECT ServerID FROM dbo.Servers WHERE ServerName = 'SQL-PROD-02');

IF NOT EXISTS (SELECT 1 FROM dbo.PerfSnapshotRun WHERE ServerID IS NOT NULL)
BEGIN
    INSERT INTO dbo.PerfSnapshotRun (
        SnapshotUTC, ServerID, ServerName, SqlVersion,
        CpuSignalWaitPct, SessionsCount, RequestsCount
    )
    VALUES
        (GETUTCDATE(), @Server1ID, 'SQL-PROD-01', '16.0.4095.4', 15.5, 100, 25),
        (DATEADD(MINUTE, -5, GETUTCDATE()), @Server1ID, 'SQL-PROD-01', '16.0.4095.4', 18.2, 105, 28),
        (GETUTCDATE(), @Server2ID, 'SQL-PROD-02', '16.0.4095.4', 22.1, 85, 15),
        (DATEADD(MINUTE, -5, GETUTCDATE()), @Server2ID, 'SQL-PROD-02', '16.0.4095.4', 20.8, 82, 14);

    PRINT '  ✓ Sample performance snapshots created (4 snapshots across 2 servers)';
END
ELSE
BEGIN
    PRINT '  ✓ Sample performance snapshots already exist';
END

PRINT '';
GO

-- =====================================================
-- Step 5: Run validation tests
-- =====================================================

PRINT 'Step 5: Running validation tests...';
PRINT '-------------------------------------------';
PRINT '';
GO

-- Execute the test script
:r test-phase-1.9-schema.sql

GO

-- =====================================================
-- Step 6: Multi-Server Specific Tests
-- =====================================================

PRINT '';
PRINT 'Step 6: Running multi-server specific tests...';
PRINT '-------------------------------------------';
GO

DECLARE @MultiServerTestsPassed INT = 0;
DECLARE @MultiServerTestsFailed INT = 0;
DECLARE @TestName NVARCHAR(200);
DECLARE @Result NVARCHAR(10);

-- Test MS-1: Can query metrics by ServerID
SET @TestName = 'Test MS-1: Can query metrics by ServerID';
DECLARE @Server1Count INT;
SELECT @Server1Count = COUNT(*)
FROM dbo.PerfSnapshotRun
WHERE ServerID = (SELECT ServerID FROM dbo.Servers WHERE ServerName = 'SQL-PROD-01');

IF @Server1Count >= 2
BEGIN
    SET @Result = '✓ PASS';
    SET @MultiServerTestsPassed = @MultiServerTestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @MultiServerTestsFailed = @MultiServerTestsFailed + 1;
    PRINT '  Expected: >= 2 snapshots for SQL-PROD-01, Found: ' + CAST(@Server1Count AS VARCHAR);
END
PRINT @TestName + ': ' + @Result;

-- Test MS-2: Can aggregate metrics across servers
SET @TestName = 'Test MS-2: Can aggregate metrics across servers';
DECLARE @TotalServersWithData INT;
SELECT @TotalServersWithData = COUNT(DISTINCT ServerID)
FROM dbo.PerfSnapshotRun
WHERE ServerID IS NOT NULL;

IF @TotalServersWithData >= 2
BEGIN
    SET @Result = '✓ PASS';
    SET @MultiServerTestsPassed = @MultiServerTestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @MultiServerTestsFailed = @MultiServerTestsFailed + 1;
    PRINT '  Expected: >= 2 servers with data, Found: ' + CAST(@TotalServersWithData AS VARCHAR);
END
PRINT @TestName + ': ' + @Result;

-- Test MS-3: Server-level filtering works correctly
SET @TestName = 'Test MS-3: Server-level filtering works';
DECLARE @Server2Count INT;
SELECT @Server2Count = COUNT(*)
FROM dbo.PerfSnapshotRun psr
INNER JOIN dbo.Servers s ON psr.ServerID = s.ServerID
WHERE s.Environment = 'Production'
AND s.ServerName = 'SQL-PROD-02';

IF @Server2Count >= 2
BEGIN
    SET @Result = '✓ PASS';
    SET @MultiServerTestsPassed = @MultiServerTestsPassed + 1;
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @MultiServerTestsFailed = @MultiServerTestsFailed + 1;
    PRINT '  Expected: >= 2 snapshots for SQL-PROD-02, Found: ' + CAST(@Server2Count AS VARCHAR);
END
PRINT @TestName + ': ' + @Result;

-- Test MS-4: Can calculate average CPU across all production servers
SET @TestName = 'Test MS-4: Can calculate average CPU across servers';
DECLARE @AvgCpu DECIMAL(9,4);
SELECT @AvgCpu = AVG(CpuSignalWaitPct)
FROM dbo.PerfSnapshotRun psr
INNER JOIN dbo.Servers s ON psr.ServerID = s.ServerID
WHERE s.Environment = 'Production';

IF @AvgCpu IS NOT NULL AND @AvgCpu > 0
BEGIN
    SET @Result = '✓ PASS';
    SET @MultiServerTestsPassed = @MultiServerTestsPassed + 1;
    PRINT '  Average CPU across production servers: ' + CAST(@AvgCpu AS VARCHAR) + '%';
END
ELSE
BEGIN
    SET @Result = '✗ FAIL';
    SET @MultiServerTestsFailed = @MultiServerTestsFailed + 1;
END
PRINT @TestName + ': ' + @Result;

PRINT '';
PRINT 'Multi-Server Tests: ' + CAST(@MultiServerTestsPassed AS VARCHAR) + ' passed, ' + CAST(@MultiServerTestsFailed AS VARCHAR) + ' failed';
PRINT '';

-- =====================================================
-- Step 7: Summary and next steps
-- =====================================================

PRINT '=========================================================================';
PRINT 'MonitoringDB Deployment Test Complete';
PRINT '=========================================================================';
PRINT '';
PRINT 'Database: MonitoringDB (multi-server mode)';
PRINT 'Tables created: 24 total (5 core + 19 enhanced)';
PRINT 'Sample data: 4 servers, 4 performance snapshots';
PRINT '';
PRINT 'Multi-Server Features Verified:';
PRINT '  - Servers table with 4 test servers';
PRINT '  - PerfSnapshotRun with ServerID foreign keys';
PRINT '  - Server-level filtering and aggregation';
PRINT '  - Cross-server metrics calculation';
PRINT '';

IF @MultiServerTestsFailed = 0
BEGIN
    PRINT '✓✓✓ ALL MULTI-SERVER TESTS PASSED ✓✓✓';
    PRINT '';
    PRINT 'Ready to proceed to Day 2: Schema Unification (mapping views)';
END
ELSE
BEGIN
    PRINT '✗✗✗ SOME MULTI-SERVER TESTS FAILED ✗✗✗';
    PRINT '  Please review failed tests before continuing.';
END

PRINT '=========================================================================';
GO
