-- =====================================================
-- Script: 00-install-tsqlt.sql
-- Description: Installs tSQLt testing framework for TDD
-- Author: SQL Server Monitor Project
-- Date: 2025-10-25
-- =====================================================

USE master;
GO

-- Enable CLR (required for tSQLt)
EXEC sp_configure 'clr enabled', 1;
RECONFIGURE;
GO

EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
GO

-- Create MonitoringDB if it doesn't exist
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'MonitoringDB')
BEGIN
    PRINT 'Creating MonitoringDB database...';

    CREATE DATABASE MonitoringDB
    ON PRIMARY
    (
        NAME = N'MonitoringDB_Data',
        FILENAME = N'MonitoringDB_Data.mdf',
        SIZE = 512MB,
        MAXSIZE = UNLIMITED,
        FILEGROWTH = 256MB
    )
    LOG ON
    (
        NAME = N'MonitoringDB_Log',
        FILENAME = N'MonitoringDB_Log.ldf',
        SIZE = 256MB,
        MAXSIZE = UNLIMITED,
        FILEGROWTH = 128MB
    );

    PRINT 'MonitoringDB database created successfully.';
END
ELSE
BEGIN
    PRINT 'MonitoringDB database already exists.';
END
GO

-- Set database options for optimal performance and testing
USE MonitoringDB;
GO

-- Set recovery model to SIMPLE for development
ALTER DATABASE MonitoringDB SET RECOVERY SIMPLE;
GO

ALTER DATABASE MonitoringDB SET AUTO_UPDATE_STATISTICS ON;
GO

ALTER DATABASE MonitoringDB SET AUTO_CREATE_STATISTICS ON;
GO

ALTER DATABASE MonitoringDB SET PAGE_VERIFY CHECKSUM;
GO

-- Enable read committed snapshot isolation for better concurrency
ALTER DATABASE MonitoringDB SET READ_COMMITTED_SNAPSHOT ON;
GO

-- Make database trustworthy (required for tSQLt CLR assemblies)
ALTER DATABASE MonitoringDB SET TRUSTWORTHY ON;
GO

PRINT 'Database configuration completed.';
GO

-- =====================================================
-- MANUAL STEP: Download and install tSQLt
-- =====================================================
/*
IMPORTANT: You must manually install tSQLt before running tests.

Steps:
1. Download tSQLt from https://tsqlt.org/downloads/
2. Extract tSQLt.class.sql
3. Execute tSQLt.class.sql on MonitoringDB:

   USE MonitoringDB;
   GO
   :r path\to\tSQLt.class.sql

4. Verify installation:
   EXEC tSQLt.Info;

Alternative: Use the provided installation command below after downloading.
*/

PRINT '';
PRINT '========================================================';
PRINT 'tSQLt Framework Installation Required';
PRINT '========================================================';
PRINT 'Download tSQLt from: https://tsqlt.org/downloads/';
PRINT 'Extract and run: :r tSQLt.class.sql';
PRINT 'Verify with: EXEC tSQLt.Info;';
PRINT '========================================================';
PRINT '';

-- =====================================================
-- Verification Query
-- =====================================================
-- Run this after installing tSQLt to verify:
-- SELECT * FROM sys.assemblies WHERE name LIKE '%tSQLt%';
-- EXEC tSQLt.Info;
GO
