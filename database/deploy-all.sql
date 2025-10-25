-- =====================================================
-- Master Deployment Script: deploy-all.sql
-- Description: Deploys complete MonitoringDB schema in correct order
-- Author: SQL Server Monitor Project
-- Date: 2025-10-25
-- Usage: sqlcmd -S SERVER -U USER -P PASSWORD -C -i deploy-all.sql
-- =====================================================

PRINT '';
PRINT '========================================================';
PRINT 'SQL Server Monitor - Database Deployment';
PRINT '========================================================';
PRINT 'Target: MonitoringDB';
PRINT 'Started: ' + CONVERT(VARCHAR(23), GETUTCDATE(), 121) + ' UTC';
PRINT '========================================================';
PRINT '';

-- =====================================================
-- Step 1: Create Database and Schemas
-- =====================================================

PRINT 'Step 1/4: Creating database and schemas...';
:r 01-create-database.sql
GO

-- =====================================================
-- Step 2: Create Partition Function and Scheme
-- =====================================================

PRINT '';
PRINT 'Step 2/4: Creating partition function and scheme...';
:r 03-create-partitions.sql
GO

-- =====================================================
-- Step 3: Create Tables
-- =====================================================

PRINT '';
PRINT 'Step 3/5: Creating tables...';
:r 02-create-tables.sql
GO

-- =====================================================
-- Step 4: Create Stored Procedures
-- =====================================================

PRINT '';
PRINT 'Step 4/5: Creating stored procedures...';
:r 04-create-procedures.sql
GO

-- =====================================================
-- Step 5: Deployment Summary
-- =====================================================

USE MonitoringDB;
GO

PRINT '';
PRINT '========================================================';
PRINT 'Deployment Complete';
PRINT '========================================================';
PRINT '';

-- Summary of created objects
SELECT 'Tables' AS ObjectType, COUNT(*) AS Count
FROM sys.tables
WHERE name IN ('Servers', 'PerformanceMetrics')
UNION ALL
SELECT 'Stored Procedures', COUNT(*)
FROM sys.procedures
WHERE name IN ('usp_GetServers', 'usp_InsertMetrics', 'usp_GetMetrics')
UNION ALL
SELECT 'Partition Functions', COUNT(*)
FROM sys.partition_functions
WHERE name = 'PF_MonitoringByMonth'
UNION ALL
SELECT 'Partition Schemes', COUNT(*)
FROM sys.partition_schemes
WHERE name = 'PS_MonitoringByMonth'
UNION ALL
SELECT 'Indexes', COUNT(*)
FROM sys.indexes
WHERE object_id IN (OBJECT_ID('dbo.Servers'), OBJECT_ID('dbo.PerformanceMetrics'))
  AND index_id > 0;

PRINT '';
PRINT 'Finished: ' + CONVERT(VARCHAR(23), GETUTCDATE(), 121) + ' UTC';
PRINT '';
PRINT '========================================================';
PRINT 'Next Steps (TDD Workflow)';
PRINT '========================================================';
PRINT '1. Install tSQLt framework:';
PRINT '   Download from https://tsqlt.org/downloads/';
PRINT '   :r 00-install-tsqlt.sql';
PRINT '   :r path\to\tSQLt.class.sql';
PRINT '';
PRINT '2. Load test suites:';
PRINT '   :r database/tests/test_Servers.sql';
PRINT '   :r database/tests/test_PerformanceMetrics.sql';
PRINT '   :r database/tests/test_usp_GetServers.sql';
PRINT '   :r database/tests/test_usp_InsertMetrics.sql';
PRINT '   :r database/tests/test_usp_GetMetrics.sql';
PRINT '';
PRINT '3. Run all tests:';
PRINT '   EXEC tSQLt.RunAll;';
PRINT '';
PRINT '4. Expected Result: ALL TESTS PASS ✓';
PRINT '   - ServerTests: 10 tests';
PRINT '   - PerformanceMetricsTests: 10 tests';
PRINT '   - usp_GetServersTests: 7 tests';
PRINT '   - usp_InsertMetricsTests: 7 tests';
PRINT '   - usp_GetMetricsTests: 7 tests';
PRINT '   TOTAL: 41 tests';
PRINT '========================================================';
GO
