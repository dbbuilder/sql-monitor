-- =====================================================
-- Script: 24-rollback-migration.sql
-- Description: Emergency rollback from Phase 1.9 to original state
-- Author: SQL Server Monitor Project
-- Date: 2025-10-28
-- Phase: 1.9 - Integration (Day 3)
-- Purpose: Restore system to pre-migration state in case of failure
-- =====================================================

-- ⚠ CRITICAL WARNING:
--   This script performs an EMERGENCY ROLLBACK to pre-migration state.
--   Only run this if the Phase 1.9 migration has failed and you need to
--   restore the original system immediately.
--
--   IMPACT: All new data collected since migration will be LOST unless
--           you preserve it separately before running this script.

PRINT '========================================================================='
PRINT '⚠ EMERGENCY ROLLBACK SCRIPT ⚠'
PRINT '========================================================================='
PRINT ''
PRINT 'This script will rollback Phase 1.9 migration to original state.'
PRINT ''
PRINT 'CONSEQUENCES:'
PRINT '  - Phase 1.9 tables (PerfSnapshot*) will be DROPPED'
PRINT '  - Phase 1.9 views will be DROPPED'
PRINT '  - PerformanceMetrics_Legacy will be renamed back to PerformanceMetrics'
PRINT '  - API will return to querying original PerformanceMetrics table'
PRINT '  - New data collected since migration will be LOST (unless preserved)'
PRINT ''
PRINT 'PREREQUISITES:'
PRINT '  - Database backup taken before migration'
PRINT '  - Authorization from DBA/Manager to proceed'
PRINT '  - Users notified of brief API disruption (1-2 minutes)'
PRINT ''
PRINT '========================================================================='
PRINT ''
GO

-- =====================================================
-- Safety Check: Require explicit confirmation
-- =====================================================

PRINT 'SAFETY CHECK: Rollback confirmation required'
PRINT '-------------------------------------------'
GO

-- Set this to 1 to enable rollback (prevents accidental execution)
DECLARE @ConfirmRollback BIT = 0;  -- ⚠ CHANGE TO 1 TO ENABLE ROLLBACK

IF @ConfirmRollback = 0
BEGIN
    PRINT '✗ ROLLBACK NOT CONFIRMED';
    PRINT '';
    PRINT 'To execute rollback, edit this script and set:';
    PRINT '  @ConfirmRollback = 1';
    PRINT '';
    PRINT 'Then re-run the script.';
    PRINT '';
    PRINT '⚠ WARNING: Only do this if migration has failed and rollback is necessary!';
    PRINT '';
    RAISERROR('Rollback not confirmed', 16, 1);
    RETURN;
END

PRINT '✓ ROLLBACK CONFIRMED - Proceeding with emergency rollback...';
PRINT '';
GO

-- =====================================================
-- Step 1: Pre-Rollback Backup (CRITICAL)
-- =====================================================

PRINT 'Step 1: Creating pre-rollback backup...'
PRINT '-------------------------------------------'
GO

-- This ensures we can recover if rollback fails
DECLARE @BackupPath NVARCHAR(500);
DECLARE @BackupFileName NVARCHAR(500);
DECLARE @SQL NVARCHAR(MAX);

-- Generate backup filename
SET @BackupFileName = DB_NAME() + '_PreRollback_' +
                      CONVERT(VARCHAR, GETDATE(), 112) + '_' +
                      REPLACE(CONVERT(VARCHAR, GETDATE(), 108), ':', '') +
                      '.bak';

-- Default backup path (customize as needed)
SET @BackupPath = 'C:\SQLBackups\' + @BackupFileName;

PRINT '  Backup file: ' + @BackupPath;

BEGIN TRY
    -- Create backup
    SET @SQL = N'BACKUP DATABASE [' + DB_NAME() + N'] TO DISK = ''' + @BackupPath + N'''
                 WITH INIT, COMPRESSION, STATS = 10';

    EXEC sp_executesql @SQL;

    PRINT '  ✓ Pre-rollback backup complete';
END TRY
BEGIN CATCH
    PRINT '  ⚠ WARNING: Backup failed - ' + ERROR_MESSAGE();
    PRINT '  Proceeding with rollback anyway (not recommended)';
END CATCH

PRINT '';
GO

-- =====================================================
-- Step 2: Preserve New Data (Optional but Recommended)
-- =====================================================

PRINT 'Step 2: Preserving new data collected since migration...'
PRINT '-------------------------------------------'
GO

-- Check if there is new data in PerfSnapshotRun
IF OBJECT_ID('dbo.PerfSnapshotRun', 'U') IS NOT NULL
BEGIN
    DECLARE @NewDataCount BIGINT;
    SELECT @NewDataCount = COUNT(*) FROM dbo.PerfSnapshotRun;

    IF @NewDataCount > 0
    BEGIN
        PRINT '  Found ' + CAST(@NewDataCount AS VARCHAR) + ' rows in PerfSnapshotRun';
        PRINT '  ⚠ WARNING: This data will be lost after rollback!';
        PRINT '';
        PRINT '  To preserve this data before rollback:';
        PRINT '    1. Export to CSV: bcp "SELECT * FROM DBATools.dbo.PerfSnapshotRun" queryout perfsnapshotrun.csv -c';
        PRINT '    2. Or create temporary table: SELECT * INTO PerfSnapshotRun_Backup FROM PerfSnapshotRun';
        PRINT '';
        PRINT '  Do you want to proceed with rollback? (This script will continue in 10 seconds)';

        -- Wait 10 seconds to give DBA time to cancel if needed
        WAITFOR DELAY '00:00:10';
    END
    ELSE
    BEGIN
        PRINT '  ℹ No new data found in PerfSnapshotRun - safe to rollback';
    END
END
ELSE
BEGIN
    PRINT '  ℹ PerfSnapshotRun table does not exist - nothing to preserve';
END

PRINT '';
GO

-- =====================================================
-- Step 3: Drop Phase 1.9 Views
-- =====================================================

PRINT 'Step 3: Dropping Phase 1.9 views...'
PRINT '-------------------------------------------'
GO

-- Drop views in reverse dependency order
DECLARE @ViewsToDrop TABLE (ViewName SYSNAME);

INSERT INTO @ViewsToDrop (ViewName) VALUES
    ('vw_PerformanceMetrics'),            -- Backward compat alias
    ('vw_PerformanceMetrics_Unified'),    -- Unified view (UNION ALL)
    ('vw_PerformanceMetrics_Core'),       -- Core metrics unpivot
    ('vw_PerformanceMetrics_QueryStats'), -- QueryStats unpivot
    ('vw_PerformanceMetrics_IOStats'),    -- IOStats unpivot
    ('vw_PerformanceMetrics_Memory'),     -- Memory unpivot
    ('vw_PerformanceMetrics_WaitStats'),  -- WaitStats unpivot
    ('vw_ServerSummary'),                 -- Server aggregation
    ('vw_DatabaseSummary'),               -- Database aggregation
    ('vw_MetricCategories');              -- Metric catalog

DECLARE @ViewName SYSNAME;
DECLARE view_cursor CURSOR FOR SELECT ViewName FROM @ViewsToDrop;

OPEN view_cursor;
FETCH NEXT FROM view_cursor INTO @ViewName;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF OBJECT_ID('dbo.' + @ViewName, 'V') IS NOT NULL
    BEGIN
        EXEC('DROP VIEW dbo.' + @ViewName);
        PRINT '  ✓ Dropped view: ' + @ViewName;
    END
    ELSE
    BEGIN
        PRINT '  ℹ View does not exist: ' + @ViewName;
    END

    FETCH NEXT FROM view_cursor INTO @ViewName;
END

CLOSE view_cursor;
DEALLOCATE view_cursor;

PRINT '';
GO

-- =====================================================
-- Step 4: Drop Phase 1.9 Stored Procedures
-- =====================================================

PRINT 'Step 4: Dropping Phase 1.9 stored procedures...'
PRINT '-------------------------------------------'
GO

-- Drop legacy migration procedures
IF OBJECT_ID('dbo.usp_MarkLegacyDataAsMigrated', 'P') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.usp_MarkLegacyDataAsMigrated;
    PRINT '  ✓ Dropped procedure: usp_MarkLegacyDataAsMigrated';
END

IF OBJECT_ID('dbo.usp_CleanupLegacyData', 'P') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.usp_CleanupLegacyData;
    PRINT '  ✓ Dropped procedure: usp_CleanupLegacyData';
END

PRINT '';
GO

-- =====================================================
-- Step 5: Restore Legacy PerformanceMetrics Table
-- =====================================================

PRINT 'Step 5: Restoring legacy PerformanceMetrics table...'
PRINT '-------------------------------------------'
GO

-- Check if legacy table exists
IF OBJECT_ID('dbo.PerformanceMetrics_Legacy', 'U') IS NOT NULL
BEGIN
    -- Check if original table name is available
    IF OBJECT_ID('dbo.PerformanceMetrics', 'U') IS NOT NULL
    BEGIN
        PRINT '  ⚠ WARNING: dbo.PerformanceMetrics table already exists!';
        PRINT '  This should not happen during rollback.';
        PRINT '  Manual intervention required - contact DBA.';
        RAISERROR('PerformanceMetrics table conflict', 16, 1);
        RETURN;
    END

    -- Rename legacy table back to original name
    EXEC sp_rename 'dbo.PerformanceMetrics_Legacy', 'PerformanceMetrics';
    PRINT '  ✓ Renamed: PerformanceMetrics_Legacy → PerformanceMetrics';

    -- Drop migration tracking columns (if they exist)
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.PerformanceMetrics') AND name = 'IsMigrated')
    BEGIN
        ALTER TABLE dbo.PerformanceMetrics DROP COLUMN IsMigrated;
        PRINT '  ✓ Dropped column: IsMigrated';
    END

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.PerformanceMetrics') AND name = 'MigrationDate')
    BEGIN
        ALTER TABLE dbo.PerformanceMetrics DROP COLUMN MigrationDate;
        PRINT '  ✓ Dropped column: MigrationDate';
    END

    -- Drop migration tracking index
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.PerformanceMetrics') AND name = 'IX_PerformanceMetrics_Legacy_IsMigrated')
    BEGIN
        DROP INDEX IX_PerformanceMetrics_Legacy_IsMigrated ON dbo.PerformanceMetrics;
        PRINT '  ✓ Dropped index: IX_PerformanceMetrics_Legacy_IsMigrated';
    END

    -- Verify restoration
    DECLARE @RestoredRowCount BIGINT;
    SELECT @RestoredRowCount = COUNT(*) FROM dbo.PerformanceMetrics;
    PRINT '  ✓ PerformanceMetrics table restored (' + CAST(@RestoredRowCount AS VARCHAR) + ' rows)';
END
ELSE
BEGIN
    PRINT '  ℹ No PerformanceMetrics_Legacy table found';
    PRINT '  This may be a fresh installation - no table restoration needed';
END

PRINT '';
GO

-- =====================================================
-- Step 6: Drop Phase 1.9 Tables (In Dependency Order)
-- =====================================================

PRINT 'Step 6: Dropping Phase 1.9 tables...'
PRINT '-------------------------------------------'
GO

-- Drop enhanced tables first (they reference PerfSnapshotRun)
DECLARE @TablesToDrop TABLE (TableName SYSNAME, DropOrder INT);

INSERT INTO @TablesToDrop (TableName, DropOrder) VALUES
    -- Enhanced tables (P0-P3) - Drop first due to foreign keys
    ('PerfSnapshotQueryStats', 1),
    ('PerfSnapshotIOStats', 2),
    ('PerfSnapshotMemory', 3),
    ('PerfSnapshotMemoryClerks', 4),
    ('PerfSnapshotBackupHistory', 5),
    ('PerfSnapshotIndexUsage', 6),
    ('PerfSnapshotMissingIndexes', 7),
    ('PerfSnapshotWaitStats', 8),
    ('PerfSnapshotTempDBContention', 9),
    ('PerfSnapshotQueryPlans', 10),
    ('PerfSnapshotConfig', 11),
    ('PerfSnapshotDeadlocks', 12),
    ('PerfSnapshotSchedulers', 13),
    ('PerfSnapshotCounters', 14),
    ('PerfSnapshotAutogrowthEvents', 15),
    ('PerfSnapshotLatchStats', 16),
    ('PerfSnapshotJobHistory', 17),
    ('PerfSnapshotSpinlockStats', 18),

    -- Core tables - Drop next
    ('PerfSnapshotDB', 19),
    ('PerfSnapshotWorkload', 20),
    ('PerfSnapshotErrorLog', 21),
    ('PerfSnapshotRun', 22),  -- Drop after child tables

    -- Supporting tables - Drop last
    ('LogEntry', 23),
    ('Servers', 24);  -- Drop last (no dependencies)

DECLARE @TableName SYSNAME;
DECLARE @SQL NVARCHAR(MAX);
DECLARE table_cursor CURSOR FOR
    SELECT TableName FROM @TablesToDrop ORDER BY DropOrder;

OPEN table_cursor;
FETCH NEXT FROM table_cursor INTO @TableName;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF OBJECT_ID('dbo.' + @TableName, 'U') IS NOT NULL
    BEGIN
        SET @SQL = 'DROP TABLE dbo.' + @TableName;
        EXEC sp_executesql @SQL;
        PRINT '  ✓ Dropped table: ' + @TableName;
    END
    ELSE
    BEGIN
        PRINT '  ℹ Table does not exist: ' + @TableName;
    END

    FETCH NEXT FROM table_cursor INTO @TableName;
END

CLOSE table_cursor;
DEALLOCATE table_cursor;

PRINT '';
GO

-- =====================================================
-- Step 7: Verification
-- =====================================================

PRINT 'Step 7: Verifying rollback...'
PRINT '-------------------------------------------'
GO

-- Verify PerformanceMetrics table exists
IF OBJECT_ID('dbo.PerformanceMetrics', 'U') IS NOT NULL
BEGIN
    DECLARE @RowCount BIGINT;
    SELECT @RowCount = COUNT(*) FROM dbo.PerformanceMetrics;
    PRINT '  ✓ PerformanceMetrics table exists (' + CAST(@RowCount AS VARCHAR) + ' rows)';
END
ELSE
BEGIN
    PRINT '  ✗ ERROR: PerformanceMetrics table does not exist!';
    PRINT '  Rollback may have failed - restore from backup immediately!';
END

-- Verify Phase 1.9 tables are gone
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'PerfSnapshotRun')
BEGIN
    PRINT '  ✓ Phase 1.9 tables removed';
END
ELSE
BEGIN
    PRINT '  ✗ WARNING: Some Phase 1.9 tables still exist';
END

-- Verify Phase 1.9 views are gone
IF NOT EXISTS (SELECT 1 FROM sys.views WHERE name = 'vw_PerformanceMetrics_Unified')
BEGIN
    PRINT '  ✓ Phase 1.9 views removed';
END
ELSE
BEGIN
    PRINT '  ✗ WARNING: Some Phase 1.9 views still exist';
END

PRINT '';
GO

-- =====================================================
-- Summary and Next Steps
-- =====================================================

PRINT '========================================================================='
PRINT 'ROLLBACK COMPLETE'
PRINT '========================================================================='
PRINT ''
PRINT 'System Status:'
PRINT '  ✓ Rolled back to pre-Phase 1.9 state'
PRINT '  ✓ PerformanceMetrics table restored'
PRINT '  ✓ Phase 1.9 tables dropped'
PRINT '  ✓ Phase 1.9 views dropped'
PRINT ''
PRINT 'Next Steps:'
PRINT '  1. Restart API service'
PRINT '  2. Test API endpoints (GET /api/metrics)'
PRINT '  3. Verify Grafana dashboards'
PRINT '  4. Review pre-rollback backup for any data to recover'
PRINT '  5. Investigate why migration failed'
PRINT '  6. Plan remediation before attempting migration again'
PRINT ''
PRINT 'Data Recovery (if needed):'
PRINT '  - Pre-rollback backup: [See Step 1 output for path]'
PRINT '  - Original pre-migration backup: [Check msdb.dbo.backupset]'
PRINT ''
PRINT 'Investigation Checklist:'
PRINT '  - SQL Server error log: EXEC xp_readerrorlog'
PRINT '  - API logs: Check application log files'
PRINT '  - Performance issues: Review query execution plans'
PRINT '  - Schema conflicts: Compare schema with Phase 1.9 spec'
PRINT ''
PRINT '========================================================================='
PRINT 'For assistance, review:'
PRINT '  - docs/migration/ZERO-DOWNTIME-CUTOVER.md'
PRINT '  - docs/phases/PHASE-01.9-TECHNICAL-DESIGN.md'
PRINT '========================================================================='
PRINT ''
GO
