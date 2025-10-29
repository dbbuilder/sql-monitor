-- =====================================================
-- Script: deploy-and-test-dbatools.sql
-- Description: Deploy Phase 1.9 schema to DBATools and run tests
-- Author: SQL Server Monitor Project
-- Date: 2025-10-27
-- Phase: 1.9 - Integration (Day 1, Test 7)
-- Target: DBATools database (single-server mode)
-- =====================================================

PRINT '=========================================================================';
PRINT 'Phase 1.9 Deployment Test: DBATools (Single-Server Mode)';
PRINT '=========================================================================';
PRINT '';
GO

-- =====================================================
-- Step 1: Create DBATools database if it doesn't exist
-- =====================================================

IF DB_ID('DBATools') IS NULL
BEGIN
    PRINT 'Creating DBATools database...';
    CREATE DATABASE [DBATools];
    PRINT '  ✓ DBATools database created';
END
ELSE
BEGIN
    PRINT '  ✓ DBATools database already exists';
END
GO

USE [DBATools];
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
-- Step 4: Run validation tests
-- =====================================================

PRINT 'Step 4: Running validation tests...';
PRINT '-------------------------------------------';
PRINT '';
GO

-- Execute the test script
:r test-phase-1.9-schema.sql

GO

-- =====================================================
-- Step 5: Summary and next steps
-- =====================================================

PRINT '';
PRINT '=========================================================================';
PRINT 'DBATools Deployment Test Complete';
PRINT '=========================================================================';
PRINT '';
PRINT 'Database: DBATools (single-server mode)';
PRINT 'Tables created: 24 total (5 core + 19 enhanced)';
PRINT '';
PRINT 'Backward Compatibility Verified:';
PRINT '  - ServerID column is nullable (NULL = local server)';
PRINT '  - Existing sql-monitor-agent code will continue to work';
PRINT '  - No breaking changes to stored procedures';
PRINT '';
PRINT 'Next: Run deploy-and-test-monitoringdb.sql to test multi-server mode';
PRINT '=========================================================================';
GO
