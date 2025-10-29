-- =====================================================
-- Script: migrate-dbatools-to-monitoringdb.sql
-- Description: Migrate data from DBATools (single-server) to MonitoringDB (multi-server)
-- Author: SQL Server Monitor Project
-- Date: 2025-10-28
-- Phase: 1.9 - Integration (Day 3)
-- Purpose: Consolidate multiple DBATools databases into central MonitoringDB
-- =====================================================

-- ⚠ IMPORTANT PREREQUISITES:
--   1. MonitoringDB database must exist and have Phase 1.9 schema deployed
--   2. Source DBATools database must be accessible (same server or linked server)
--   3. Target server must be registered in MonitoringDB.dbo.Servers table
--   4. Run with appropriate permissions (db_datareader on source, db_datawriter on target)

PRINT '========================================================================='
PRINT 'DBATools → MonitoringDB Migration Script'
PRINT '========================================================================='
PRINT ''
PRINT 'This script migrates performance data from a DBATools database (single-'
PRINT 'server mode) to MonitoringDB (multi-server mode).'
PRINT ''
PRINT 'Migration Process:'
PRINT '  1. Verify prerequisites (databases, tables, server registration)'
PRINT '  2. Map source server to MonitoringDB.Servers.ServerID'
PRINT '  3. Copy PerfSnapshotRun data (with ServerID mapping)'
PRINT '  4. Copy enhanced table data (P0-P3)'
PRINT '  5. Validate data integrity (row counts, date ranges)'
PRINT '  6. Mark source data as migrated (optional)'
PRINT ''
PRINT '========================================================================='
PRINT ''
GO

-- =====================================================
-- Configuration Parameters (CUSTOMIZE THESE)
-- =====================================================

-- Source database (DBATools instance)
DECLARE @SourceDatabase SYSNAME = 'DBATools';  -- Database name
DECLARE @SourceServerName SYSNAME = 'SQL-PROD-01';  -- Actual SQL Server instance name

-- Target database (MonitoringDB)
DECLARE @TargetDatabase SYSNAME = 'MonitoringDB';

-- Migration options
DECLARE @StartDate DATETIME2 = NULL;  -- NULL = migrate all data
DECLARE @EndDate DATETIME2 = NULL;    -- NULL = migrate all data
DECLARE @BatchSize INT = 1000;        -- Rows per batch
DECLARE @MarkSourceAsMigrated BIT = 0;  -- 1 = mark source data, 0 = leave untouched
DECLARE @DryRun BIT = 1;              -- 1 = preview only, 0 = actual migration

-- =====================================================
-- Variables
-- =====================================================

DECLARE @TargetServerID INT;
DECLARE @SourceRowCount BIGINT;
DECLARE @TargetRowCount BIGINT;
DECLARE @RowsMigrated INT = 0;
DECLARE @TotalRowsMigrated BIGINT = 0;
DECLARE @SQL NVARCHAR(MAX);
DECLARE @ErrorMessage NVARCHAR(4000);

-- =====================================================
-- Step 1: Prerequisites Check
-- =====================================================

PRINT 'Step 1: Checking prerequisites...'
PRINT '-------------------------------------------'
GO

-- Check source database exists
DECLARE @SourceDatabase SYSNAME = 'DBATools';
DECLARE @TargetDatabase SYSNAME = 'MonitoringDB';
DECLARE @SourceServerName SYSNAME = 'SQL-PROD-01';
DECLARE @DryRun BIT = 1;

IF DB_ID(@SourceDatabase) IS NULL
BEGIN
    PRINT '✗ ERROR: Source database ''' + @SourceDatabase + ''' does not exist';
    RAISERROR('Source database not found', 16, 1);
    RETURN;
END

PRINT '  ✓ Source database exists: ' + @SourceDatabase;

-- Check target database exists
IF DB_ID(@TargetDatabase) IS NULL
BEGIN
    PRINT '✗ ERROR: Target database ''' + @TargetDatabase + ''' does not exist';
    RAISERROR('Target database not found', 16, 1);
    RETURN;
END

PRINT '  ✓ Target database exists: ' + @TargetDatabase;

-- Check source tables exist
DECLARE @SourcePerfSnapshotRunExists BIT = 0;
EXEC('USE [' + @SourceDatabase + '];
      IF OBJECT_ID(''dbo.PerfSnapshotRun'', ''U'') IS NOT NULL
         SELECT @SourcePerfSnapshotRunExists = 1', @SourcePerfSnapshotRunExists OUTPUT);

IF @SourcePerfSnapshotRunExists = 0
BEGIN
    PRINT '✗ ERROR: Source table dbo.PerfSnapshotRun does not exist in ' + @SourceDatabase;
    RAISERROR('Source table not found', 16, 1);
    RETURN;
END

PRINT '  ✓ Source tables exist in ' + @SourceDatabase;

-- Check target tables exist
DECLARE @TargetPerfSnapshotRunExists BIT = 0;
DECLARE @SQL NVARCHAR(MAX) = N'USE [' + @TargetDatabase + N'];
                                IF OBJECT_ID(''dbo.PerfSnapshotRun'', ''U'') IS NOT NULL
                                   SELECT @TargetPerfSnapshotRunExists = 1';
EXEC sp_executesql @SQL, N'@TargetPerfSnapshotRunExists BIT OUTPUT', @TargetPerfSnapshotRunExists OUTPUT;

IF @TargetPerfSnapshotRunExists = 0
BEGIN
    PRINT '✗ ERROR: Target table dbo.PerfSnapshotRun does not exist in ' + @TargetDatabase;
    PRINT '  Please deploy Phase 1.9 schema to ' + @TargetDatabase + ' first';
    RAISERROR('Target table not found', 16, 1);
    RETURN;
END

PRINT '  ✓ Target tables exist in ' + @TargetDatabase;
PRINT '';
GO

-- =====================================================
-- Step 2: Server Registration Check
-- =====================================================

PRINT 'Step 2: Checking server registration...'
PRINT '-------------------------------------------'
GO

DECLARE @TargetServerID INT;
DECLARE @TargetDatabase SYSNAME = 'MonitoringDB';
DECLARE @SourceServerName SYSNAME = 'SQL-PROD-01';
DECLARE @SQL NVARCHAR(MAX);

-- Check if server is registered in MonitoringDB.dbo.Servers
SET @SQL = N'USE [' + @TargetDatabase + N'];
             SELECT @TargetServerID = ServerID
             FROM dbo.Servers
             WHERE ServerName = @SourceServerName AND IsActive = 1';

EXEC sp_executesql @SQL,
     N'@TargetServerID INT OUTPUT, @SourceServerName SYSNAME',
     @TargetServerID OUTPUT,
     @SourceServerName;

IF @TargetServerID IS NULL
BEGIN
    PRINT '  ⚠ WARNING: Server ''' + @SourceServerName + ''' not registered in ' + @TargetDatabase + '.dbo.Servers';
    PRINT '';
    PRINT '  To register this server, run:';
    PRINT '    USE [' + @TargetDatabase + '];';
    PRINT '    INSERT INTO dbo.Servers (ServerName, Environment, IsActive)';
    PRINT '    VALUES (''' + @SourceServerName + ''', ''Production'', 1);';
    PRINT '';
    RAISERROR('Server not registered', 16, 1);
    RETURN;
END

PRINT '  ✓ Server registered: ' + @SourceServerName + ' (ServerID = ' + CAST(@TargetServerID AS VARCHAR) + ')';
PRINT '';
GO

-- =====================================================
-- Step 3: Data Analysis (Source)
-- =====================================================

PRINT 'Step 3: Analyzing source data...'
PRINT '-------------------------------------------'
GO

DECLARE @SourceDatabase SYSNAME = 'DBATools';
DECLARE @SourceRowCount BIGINT;
DECLARE @SourceMinDate DATETIME2;
DECLARE @SourceMaxDate DATETIME2;
DECLARE @SQL NVARCHAR(MAX);

-- Get source data statistics
SET @SQL = N'USE [' + @SourceDatabase + N'];
             SELECT
                 @SourceRowCount = COUNT(*),
                 @SourceMinDate = MIN(SnapshotUTC),
                 @SourceMaxDate = MAX(SnapshotUTC)
             FROM dbo.PerfSnapshotRun';

EXEC sp_executesql @SQL,
     N'@SourceRowCount BIGINT OUTPUT, @SourceMinDate DATETIME2 OUTPUT, @SourceMaxDate DATETIME2 OUTPUT',
     @SourceRowCount OUTPUT,
     @SourceMinDate OUTPUT,
     @SourceMaxDate OUTPUT;

PRINT '  Source: ' + @SourceDatabase;
PRINT '    Total PerfSnapshotRun rows: ' + CAST(@SourceRowCount AS VARCHAR);
PRINT '    Date range: ' + CONVERT(VARCHAR, @SourceMinDate, 120) + ' to ' + CONVERT(VARCHAR, @SourceMaxDate, 120);
PRINT '    Days of data: ' + CAST(DATEDIFF(DAY, @SourceMinDate, @SourceMaxDate) AS VARCHAR);

-- Check enhanced tables
DECLARE @SourceQueryStatsCount BIGINT;
SET @SQL = N'USE [' + @SourceDatabase + N']; SELECT @Count = COUNT(*) FROM dbo.PerfSnapshotQueryStats';
EXEC sp_executesql @SQL, N'@Count BIGINT OUTPUT', @SourceQueryStatsCount OUTPUT;
PRINT '    QueryStats rows: ' + CAST(@SourceQueryStatsCount AS VARCHAR);

DECLARE @SourceIOStatsCount BIGINT;
SET @SQL = N'USE [' + @SourceDatabase + N']; SELECT @Count = COUNT(*) FROM dbo.PerfSnapshotIOStats';
EXEC sp_executesql @SQL, N'@Count BIGINT OUTPUT', @SourceIOStatsCount OUTPUT;
PRINT '    IOStats rows: ' + CAST(@SourceIOStatsCount AS VARCHAR);

DECLARE @SourceMemoryCount BIGINT;
SET @SQL = N'USE [' + @SourceDatabase + N']; SELECT @Count = COUNT(*) FROM dbo.PerfSnapshotMemory';
EXEC sp_executesql @SQL, N'@Count BIGINT OUTPUT', @SourceMemoryCount OUTPUT;
PRINT '    Memory rows: ' + CAST(@SourceMemoryCount AS VARCHAR);

PRINT '';
GO

-- =====================================================
-- Step 4: Dry Run Preview
-- =====================================================

PRINT 'Step 4: Migration preview...'
PRINT '-------------------------------------------'
GO

DECLARE @DryRun BIT = 1;
DECLARE @TargetServerID INT = 1;  -- Example value
DECLARE @SourceDatabase SYSNAME = 'DBATools';
DECLARE @TargetDatabase SYSNAME = 'MonitoringDB';

IF @DryRun = 1
BEGIN
    PRINT '  ⚠ DRY RUN MODE ACTIVE';
    PRINT '  No data will be migrated in this run';
    PRINT '';
    PRINT '  Migration Plan:';
    PRINT '    Source: ' + @SourceDatabase + ' (single-server mode)';
    PRINT '    Target: ' + @TargetDatabase + ' (multi-server mode)';
    PRINT '    Target ServerID: ' + CAST(@TargetServerID AS VARCHAR);
    PRINT '';
    PRINT '  Tables to migrate:';
    PRINT '    1. PerfSnapshotRun (core metrics)';
    PRINT '    2. PerfSnapshotDB (database stats)';
    PRINT '    3. PerfSnapshotWorkload (active sessions)';
    PRINT '    4. PerfSnapshotErrorLog (SQL error log)';
    PRINT '    5. PerfSnapshotQueryStats (P0 - query performance)';
    PRINT '    6. PerfSnapshotIOStats (P0 - I/O metrics)';
    PRINT '    7. PerfSnapshotMemory (P0 - memory metrics)';
    PRINT '    8. PerfSnapshotMemoryClerks (P0 - memory details)';
    PRINT '    9. PerfSnapshotBackupHistory (P0 - backup validation)';
    PRINT '   10. PerfSnapshotWaitStats (P1 - wait statistics)';
    PRINT '   ... and 9 more enhanced tables (P1-P3)';
    PRINT '';
    PRINT '  To perform actual migration:';
    PRINT '    1. Review this preview carefully';
    PRINT '    2. Set @DryRun = 0 at the top of this script';
    PRINT '    3. Re-run the script';
    PRINT '';
    PRINT '  ⚠ CAUTION: Actual migration will modify MonitoringDB';
    PRINT '';
    RETURN;  -- Exit in dry run mode
END

PRINT '  ✓ ACTUAL MIGRATION MODE';
PRINT '  Data will be copied from ' + @SourceDatabase + ' to ' + @TargetDatabase;
PRINT '';
GO

-- =====================================================
-- Step 5: Migrate PerfSnapshotRun (Core Table)
-- =====================================================

PRINT 'Step 5: Migrating PerfSnapshotRun...'
PRINT '-------------------------------------------'
GO

-- Migration template (actual implementation would use cursor/batching)
-- This is a simplified example showing the pattern

/*
DECLARE @SourceDatabase SYSNAME = 'DBATools';
DECLARE @TargetDatabase SYSNAME = 'MonitoringDB';
DECLARE @TargetServerID INT = 1;
DECLARE @BatchSize INT = 1000;
DECLARE @SQL NVARCHAR(MAX);

-- Build INSERT...SELECT statement
SET @SQL = N'
USE [' + @TargetDatabase + N'];

INSERT INTO dbo.PerfSnapshotRun (
    SnapshotUTC,
    ServerID,  -- NEW: Multi-server support
    ServerName,
    SqlVersion,
    CpuSignalWaitPct,
    TopWaitType,
    TopWaitMsPerSec,
    SessionsCount,
    RequestsCount,
    BlockingSessionCount,
    DeadlockCountRecent,
    MemoryGrantWarningCount
)
SELECT TOP (@BatchSize)
    src.SnapshotUTC,
    @TargetServerID AS ServerID,  -- Map NULL → specific ServerID
    src.ServerName,
    src.SqlVersion,
    src.CpuSignalWaitPct,
    src.TopWaitType,
    src.TopWaitMsPerSec,
    src.SessionsCount,
    src.RequestsCount,
    src.BlockingSessionCount,
    src.DeadlockCountRecent,
    src.MemoryGrantWarningCount
FROM [' + @SourceDatabase + N'].dbo.PerfSnapshotRun src
LEFT JOIN [' + @TargetDatabase + N'].dbo.PerfSnapshotRun tgt
    ON src.SnapshotUTC = tgt.SnapshotUTC
   AND tgt.ServerID = @TargetServerID
WHERE tgt.PerfSnapshotRunID IS NULL  -- Only copy non-existent rows
ORDER BY src.SnapshotUTC;
';

EXEC sp_executesql @SQL,
     N'@BatchSize INT, @TargetServerID INT',
     @BatchSize,
     @TargetServerID;

PRINT '  ✓ PerfSnapshotRun migration complete';
*/

PRINT '  ℹ See actual migration implementation in full script';
PRINT '  Pattern: INSERT...SELECT with ServerID mapping + duplicate detection';
PRINT '';
GO

-- =====================================================
-- Summary and Next Steps
-- =====================================================

PRINT '========================================================================='
PRINT 'Migration Script Preview Complete'
PRINT '========================================================================='
PRINT ''
PRINT 'This is a TEMPLATE migration script. For production use:'
PRINT ''
PRINT '1. Customize configuration parameters at top of script:'
PRINT '   - @SourceDatabase (e.g., ''DBATools'')'
PRINT '   - @TargetDatabase (e.g., ''MonitoringDB'')'
PRINT '   - @SourceServerName (e.g., ''SQL-PROD-01'')'
PRINT '   - @StartDate / @EndDate (date range filter)'
PRINT ''
PRINT '2. Run in DRY RUN mode first (@DryRun = 1)'
PRINT '   - Review preview output'
PRINT '   - Verify server registration'
PRINT '   - Check data volumes'
PRINT ''
PRINT '3. Run actual migration (@DryRun = 0)'
PRINT '   - Monitor progress'
PRINT '   - Validate data integrity'
PRINT '   - Test API queries'
PRINT ''
PRINT '4. Post-migration validation:'
PRINT '   - Compare row counts (source vs target)'
PRINT '   - Verify date ranges match'
PRINT '   - Test Grafana dashboards'
PRINT '   - Check API performance'
PRINT ''
PRINT 'Alternative Migration Approaches:'
PRINT ''
PRINT '  A. Manual BCP export/import (fastest for large datasets)'
PRINT '     bcp "SELECT * FROM DBATools.dbo.PerfSnapshotRun" queryout data.dat'
PRINT '     bcp MonitoringDB.dbo.PerfSnapshotRun in data.dat'
PRINT ''
PRINT '  B. SSIS package (for complex transformations)'
PRINT '  C. Linked server INSERT...SELECT (simpler but slower)'
PRINT '  D. Log shipping / replication (continuous sync)'
PRINT ''
PRINT '========================================================================='
PRINT ''
GO
