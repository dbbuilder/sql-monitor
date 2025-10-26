-- =====================================================
-- Script: 01-create-database.sql
-- Description: Creates MonitoringDB database and schemas
-- Author: SQL Server Monitor Project
-- Date: 2025-10-25
-- TDD: This script is required before any tests can run
-- =====================================================

USE master;
GO

-- Create MonitoringDB if it doesn't exist
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'MonitoringDB')
BEGIN
    PRINT 'Creating MonitoringDB database...';

    -- Let SQL Server use default file locations
    CREATE DATABASE MonitoringDB;

    PRINT 'MonitoringDB database created successfully.';
END
ELSE
BEGIN
    PRINT 'MonitoringDB database already exists.';
END
GO

-- Set database options
USE MonitoringDB;
GO

ALTER DATABASE MonitoringDB SET RECOVERY SIMPLE;
GO

ALTER DATABASE MonitoringDB SET AUTO_UPDATE_STATISTICS ON;
GO

ALTER DATABASE MonitoringDB SET AUTO_CREATE_STATISTICS ON;
GO

ALTER DATABASE MonitoringDB SET PAGE_VERIFY CHECKSUM;
GO

ALTER DATABASE MonitoringDB SET READ_COMMITTED_SNAPSHOT ON;
GO

-- For tSQLt (if not already set)
ALTER DATABASE MonitoringDB SET TRUSTWORTHY ON;
GO

PRINT 'Database configuration completed.';
GO

-- =====================================================
-- Create Schemas
-- =====================================================

-- Core schema for tables and procedures
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'dbo')
BEGIN
    CREATE SCHEMA dbo;
    PRINT 'Schema [dbo] created.';
END
ELSE
BEGIN
    PRINT 'Schema [dbo] already exists.';
END
GO

-- Test schema for tSQLt test classes
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'tests')
BEGIN
    CREATE SCHEMA tests;
    PRINT 'Schema [tests] created for tSQLt test classes.';
END
ELSE
BEGIN
    PRINT 'Schema [tests] already exists.';
END
GO

PRINT '';
PRINT '========================================================';
PRINT 'MonitoringDB database and schemas created successfully';
PRINT '========================================================';
PRINT 'Next steps:';
PRINT '1. Install tSQLt framework: :r 00-install-tsqlt.sql';
PRINT '2. Run tests: :r database/tests/*.sql';
PRINT '3. Create schema: :r 02-create-tables.sql';
PRINT '========================================================';
GO
