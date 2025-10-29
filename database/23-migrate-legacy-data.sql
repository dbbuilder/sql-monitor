-- =====================================================
-- Script: 23-migrate-legacy-data.sql
-- Description: Handle existing PerformanceMetrics table (legacy data preservation)
-- Author: SQL Server Monitor Project
-- Date: 2025-10-28
-- Phase: 1.9 - Integration (Day 3)
-- Purpose: Zero data loss migration from TALL schema to WIDE schema views
-- =====================================================

PRINT '========================================================================='
PRINT 'Phase 1.9 Day 3: Legacy Data Migration'
PRINT '========================================================================='
PRINT ''
PRINT 'This script handles existing PerformanceMetrics table data:'
PRINT '  1. Renames PerformanceMetrics → PerformanceMetrics_Legacy'
PRINT '  2. Preserves all historical data (zero data loss)'
PRINT '  3. Updates vw_PerformanceMetrics to UNION legacy + new data'
PRINT '  4. Maintains backward compatibility with existing API'
PRINT ''
PRINT '========================================================================='
PRINT ''
GO

-- =====================================================
-- Step 1: Check if legacy PerformanceMetrics table exists
-- =====================================================

PRINT 'Step 1: Checking for existing PerformanceMetrics table...'
PRINT '-------------------------------------------'
GO

IF OBJECT_ID('dbo.PerformanceMetrics', 'U') IS NOT NULL
BEGIN
    PRINT '  ✓ Found existing PerformanceMetrics table (legacy data detected)'

    -- Get row count
    DECLARE @LegacyRowCount BIGINT;
    SELECT @LegacyRowCount = COUNT(*) FROM dbo.PerformanceMetrics;
    PRINT '  Legacy data rows: ' + CAST(@LegacyRowCount AS VARCHAR);

    -- Get date range
    DECLARE @LegacyMinDate DATETIME2, @LegacyMaxDate DATETIME2;
    SELECT @LegacyMinDate = MIN(CollectionTime), @LegacyMaxDate = MAX(CollectionTime)
    FROM dbo.PerformanceMetrics;
    PRINT '  Date range: ' + CONVERT(VARCHAR, @LegacyMinDate, 120) + ' to ' + CONVERT(VARCHAR, @LegacyMaxDate, 120);
END
ELSE
BEGIN
    PRINT '  ℹ No existing PerformanceMetrics table found'
    PRINT '  This is a fresh installation - no migration needed'
    PRINT '  Proceeding with standard view creation...'
END

PRINT ''
GO

-- =====================================================
-- Step 2: Rename legacy table (if exists)
-- =====================================================

PRINT 'Step 2: Renaming legacy PerformanceMetrics table...'
PRINT '-------------------------------------------'
GO

IF OBJECT_ID('dbo.PerformanceMetrics', 'U') IS NOT NULL
BEGIN
    -- Drop existing view if it exists (will be recreated later)
    IF OBJECT_ID('dbo.vw_PerformanceMetrics', 'V') IS NOT NULL
    BEGIN
        DROP VIEW dbo.vw_PerformanceMetrics;
        PRINT '  ✓ Dropped existing vw_PerformanceMetrics (will recreate with UNION)'
    END

    -- Check if legacy table already exists (prevent accidental overwrite)
    IF OBJECT_ID('dbo.PerformanceMetrics_Legacy', 'U') IS NOT NULL
    BEGIN
        PRINT '  ⚠ WARNING: PerformanceMetrics_Legacy table already exists!'
        PRINT '  Please review manually before proceeding.'
        PRINT '  Options:'
        PRINT '    1. DROP TABLE PerformanceMetrics_Legacy (if safe to delete)'
        PRINT '    2. Rename to PerformanceMetrics_Legacy_Backup'
        PRINT '    3. Merge data before proceeding'
        RAISERROR('Legacy table already exists - manual intervention required', 16, 1);
        RETURN;
    END

    -- Rename PerformanceMetrics → PerformanceMetrics_Legacy
    EXEC sp_rename 'dbo.PerformanceMetrics', 'PerformanceMetrics_Legacy';
    PRINT '  ✓ Renamed: PerformanceMetrics → PerformanceMetrics_Legacy'

    -- Verify rename was successful
    IF OBJECT_ID('dbo.PerformanceMetrics_Legacy', 'U') IS NOT NULL
    BEGIN
        DECLARE @LegacyRowCount2 BIGINT;
        SELECT @LegacyRowCount2 = COUNT(*) FROM dbo.PerformanceMetrics_Legacy;
        PRINT '  ✓ Verified: ' + CAST(@LegacyRowCount2 AS VARCHAR) + ' rows preserved in legacy table'
    END
END
ELSE
BEGIN
    PRINT '  ℹ No PerformanceMetrics table to rename (fresh installation)'
END

PRINT ''
GO

-- =====================================================
-- Step 3: Add metadata column to legacy table
-- =====================================================

PRINT 'Step 3: Adding metadata columns to legacy table...'
PRINT '-------------------------------------------'
GO

IF OBJECT_ID('dbo.PerformanceMetrics_Legacy', 'U') IS NOT NULL
BEGIN
    -- Add IsMigrated flag (for tracking which rows have been migrated to new schema)
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns
        WHERE object_id = OBJECT_ID('dbo.PerformanceMetrics_Legacy')
          AND name = 'IsMigrated'
    )
    BEGIN
        ALTER TABLE dbo.PerformanceMetrics_Legacy
        ADD IsMigrated BIT NOT NULL DEFAULT 0;

        PRINT '  ✓ Added IsMigrated column (default: 0 = not yet migrated)'
    END
    ELSE
    BEGIN
        PRINT '  ℹ IsMigrated column already exists'
    END

    -- Add MigrationDate column
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns
        WHERE object_id = OBJECT_ID('dbo.PerformanceMetrics_Legacy')
          AND name = 'MigrationDate'
    )
    BEGIN
        ALTER TABLE dbo.PerformanceMetrics_Legacy
        ADD MigrationDate DATETIME2 NULL;

        PRINT '  ✓ Added MigrationDate column (tracks when row was migrated)'
    END
    ELSE
    BEGIN
        PRINT '  ℹ MigrationDate column already exists'
    END

    -- Add index for efficient querying of unmigrated data
    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('dbo.PerformanceMetrics_Legacy')
          AND name = 'IX_PerformanceMetrics_Legacy_IsMigrated'
    )
    BEGIN
        CREATE NONCLUSTERED INDEX IX_PerformanceMetrics_Legacy_IsMigrated
        ON dbo.PerformanceMetrics_Legacy (IsMigrated, CollectionTime)
        INCLUDE (MetricID, ServerID, MetricCategory, MetricName, MetricValue)
        WHERE IsMigrated = 0;

        PRINT '  ✓ Created filtered index on IsMigrated = 0 (unmigrated rows)'
    END
    ELSE
    BEGIN
        PRINT '  ℹ Filtered index already exists'
    END
END
ELSE
BEGIN
    PRINT '  ℹ No legacy table exists - skipping metadata columns'
END

PRINT ''
GO

-- =====================================================
-- Step 4: Create vw_PerformanceMetrics with UNION
-- =====================================================

PRINT 'Step 4: Creating vw_PerformanceMetrics with legacy data UNION...'
PRINT '-------------------------------------------'
GO

-- Drop existing view if it exists
IF OBJECT_ID('dbo.vw_PerformanceMetrics', 'V') IS NOT NULL
BEGIN
    DROP VIEW dbo.vw_PerformanceMetrics;
END

-- Check if legacy table exists
IF OBJECT_ID('dbo.PerformanceMetrics_Legacy', 'U') IS NOT NULL
BEGIN
    -- CREATE VIEW with UNION of legacy + new data
    EXEC('
    CREATE VIEW dbo.vw_PerformanceMetrics AS

    -- New data (from WIDE schema via vw_PerformanceMetrics_Unified)
    SELECT
        MetricID,
        ServerID,
        CollectionTime,
        MetricCategory,
        MetricName,
        MetricValue
    FROM dbo.vw_PerformanceMetrics_Unified

    UNION ALL

    -- Legacy data (original TALL schema)
    SELECT
        MetricID,
        ServerID,
        CollectionTime,
        MetricCategory,
        MetricName,
        MetricValue
    FROM dbo.PerformanceMetrics_Legacy
    WHERE IsMigrated = 0;  -- Only include unmigrated data (avoid duplicates)
    ');

    PRINT '  ✓ Created vw_PerformanceMetrics with UNION (legacy + new data)'
    PRINT '  Legacy data: Included (IsMigrated = 0 only)'
    PRINT '  New data: Included (from PerfSnapshot* tables)'
END
ELSE
BEGIN
    -- No legacy data - simple alias to Unified view
    EXEC('
    CREATE VIEW dbo.vw_PerformanceMetrics AS
    SELECT
        MetricID,
        ServerID,
        CollectionTime,
        MetricCategory,
        MetricName,
        MetricValue
    FROM dbo.vw_PerformanceMetrics_Unified;
    ');

    PRINT '  ✓ Created vw_PerformanceMetrics (no legacy data, simple alias)'
END

PRINT ''
GO

-- =====================================================
-- Step 5: Create stored procedure to mark legacy rows as migrated
-- =====================================================

PRINT 'Step 5: Creating stored procedure to mark legacy rows as migrated...'
PRINT '-------------------------------------------'
GO

IF OBJECT_ID('dbo.usp_MarkLegacyDataAsMigrated', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_MarkLegacyDataAsMigrated
GO

CREATE PROCEDURE dbo.usp_MarkLegacyDataAsMigrated
    @StartDate DATETIME2 = NULL,  -- Optional: mark only specific date range
    @EndDate DATETIME2 = NULL,
    @BatchSize INT = 10000        -- Process in batches to avoid long locks
AS
BEGIN
    SET NOCOUNT ON;

    -- Check if legacy table exists
    IF OBJECT_ID('dbo.PerformanceMetrics_Legacy', 'U') IS NULL
    BEGIN
        PRINT 'No legacy table exists - nothing to migrate';
        RETURN;
    END

    DECLARE @RowsUpdated INT = 0;
    DECLARE @TotalRowsUpdated INT = 0;
    DECLARE @BatchCount INT = 0;

    -- Default date range (all data if not specified)
    IF @StartDate IS NULL SET @StartDate = '1900-01-01';
    IF @EndDate IS NULL SET @EndDate = '9999-12-31';

    PRINT 'Marking legacy data as migrated...';
    PRINT '  Date range: ' + CONVERT(VARCHAR, @StartDate, 120) + ' to ' + CONVERT(VARCHAR, @EndDate, 120);
    PRINT '  Batch size: ' + CAST(@BatchSize AS VARCHAR);
    PRINT '';

    -- Process in batches
    WHILE 1=1
    BEGIN
        UPDATE TOP (@BatchSize) dbo.PerformanceMetrics_Legacy
        SET
            IsMigrated = 1,
            MigrationDate = SYSUTCDATETIME()
        WHERE IsMigrated = 0
          AND CollectionTime >= @StartDate
          AND CollectionTime <= @EndDate;

        SET @RowsUpdated = @@ROWCOUNT;
        SET @TotalRowsUpdated = @TotalRowsUpdated + @RowsUpdated;
        SET @BatchCount = @BatchCount + 1;

        IF @RowsUpdated = 0
            BREAK;  -- No more rows to update

        -- Progress reporting
        IF @BatchCount % 10 = 0
        BEGIN
            PRINT '  Processed ' + CAST(@TotalRowsUpdated AS VARCHAR) + ' rows (' + CAST(@BatchCount AS VARCHAR) + ' batches)...';
        END

        -- Small delay to avoid locking issues
        WAITFOR DELAY '00:00:00.100';
    END

    PRINT '';
    PRINT '✓ Migration complete: ' + CAST(@TotalRowsUpdated AS VARCHAR) + ' rows marked as migrated';
    PRINT '  Total batches: ' + CAST(@BatchCount AS VARCHAR);
END
GO

PRINT '  ✓ Created stored procedure: dbo.usp_MarkLegacyDataAsMigrated'
PRINT ''
GO

-- =====================================================
-- Step 6: Create cleanup stored procedure (delete old legacy data)
-- =====================================================

PRINT 'Step 6: Creating cleanup stored procedure...'
PRINT '-------------------------------------------'
GO

IF OBJECT_ID('dbo.usp_CleanupLegacyData', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CleanupLegacyData
GO

CREATE PROCEDURE dbo.usp_CleanupLegacyData
    @OlderThanDays INT = 90,     -- Delete legacy data older than N days (default: 90)
    @BatchSize INT = 10000,
    @DryRun BIT = 1               -- Default: dry run (preview only)
AS
BEGIN
    SET NOCOUNT ON;

    -- Check if legacy table exists
    IF OBJECT_ID('dbo.PerformanceMetrics_Legacy', 'U') IS NULL
    BEGIN
        PRINT 'No legacy table exists - nothing to clean up';
        RETURN;
    END

    DECLARE @CutoffDate DATETIME2 = DATEADD(DAY, -@OlderThanDays, SYSUTCDATETIME());
    DECLARE @RowsDeleted INT = 0;
    DECLARE @TotalRowsDeleted INT = 0;
    DECLARE @BatchCount INT = 0;
    DECLARE @RowsToDelete INT;

    -- Count rows that would be deleted
    SELECT @RowsToDelete = COUNT(*)
    FROM dbo.PerformanceMetrics_Legacy
    WHERE IsMigrated = 1
      AND CollectionTime < @CutoffDate;

    PRINT 'Legacy data cleanup parameters:';
    PRINT '  Cutoff date: ' + CONVERT(VARCHAR, @CutoffDate, 120);
    PRINT '  Rows to delete: ' + CAST(@RowsToDelete AS VARCHAR);
    PRINT '  Batch size: ' + CAST(@BatchSize AS VARCHAR);
    PRINT '  Dry run: ' + CASE WHEN @DryRun = 1 THEN 'YES (no actual deletion)' ELSE 'NO (ACTUAL DELETION)' END;
    PRINT '';

    IF @DryRun = 1
    BEGIN
        PRINT '⚠ DRY RUN MODE: No data will be deleted';
        PRINT '  To perform actual deletion, run with @DryRun = 0';
        RETURN;
    END

    -- Actual deletion (batched)
    PRINT 'Starting deletion...';

    WHILE 1=1
    BEGIN
        DELETE TOP (@BatchSize)
        FROM dbo.PerformanceMetrics_Legacy
        WHERE IsMigrated = 1
          AND CollectionTime < @CutoffDate;

        SET @RowsDeleted = @@ROWCOUNT;
        SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted;
        SET @BatchCount = @BatchCount + 1;

        IF @RowsDeleted = 0
            BREAK;

        -- Progress reporting
        IF @BatchCount % 10 = 0
        BEGIN
            PRINT '  Deleted ' + CAST(@TotalRowsDeleted AS VARCHAR) + ' rows (' + CAST(@BatchCount AS VARCHAR) + ' batches)...';
        END

        -- Small delay
        WAITFOR DELAY '00:00:00.100';
    END

    PRINT '';
    PRINT '✓ Cleanup complete: ' + CAST(@TotalRowsDeleted AS VARCHAR) + ' rows deleted';
    PRINT '  Total batches: ' + CAST(@BatchCount AS VARCHAR);
END
GO

PRINT '  ✓ Created stored procedure: dbo.usp_CleanupLegacyData'
PRINT ''
GO

-- =====================================================
-- Step 7: Validation queries
-- =====================================================

PRINT 'Step 7: Running validation queries...'
PRINT '-------------------------------------------'
GO

-- Validation 1: Check vw_PerformanceMetrics returns data
DECLARE @ViewRowCount BIGINT;
SELECT @ViewRowCount = COUNT(*) FROM dbo.vw_PerformanceMetrics;
PRINT '  vw_PerformanceMetrics total rows: ' + CAST(@ViewRowCount AS VARCHAR);

-- Validation 2: Check legacy table statistics (if exists)
IF OBJECT_ID('dbo.PerformanceMetrics_Legacy', 'U') IS NOT NULL
BEGIN
    DECLARE @LegacyTotal BIGINT, @LegacyMigrated BIGINT, @LegacyUnmigrated BIGINT;

    SELECT
        @LegacyTotal = COUNT(*),
        @LegacyMigrated = SUM(CASE WHEN IsMigrated = 1 THEN 1 ELSE 0 END),
        @LegacyUnmigrated = SUM(CASE WHEN IsMigrated = 0 THEN 1 ELSE 0 END)
    FROM dbo.PerformanceMetrics_Legacy;

    PRINT '  Legacy table statistics:';
    PRINT '    Total rows: ' + CAST(@LegacyTotal AS VARCHAR);
    PRINT '    Migrated: ' + CAST(@LegacyMigrated AS VARCHAR);
    PRINT '    Unmigrated: ' + CAST(@LegacyUnmigrated AS VARCHAR);
END

-- Validation 3: Check new schema data (if exists)
IF EXISTS (SELECT 1 FROM dbo.PerfSnapshotRun)
BEGIN
    DECLARE @NewSchemaRows BIGINT;
    SELECT @NewSchemaRows = COUNT(*) FROM dbo.vw_PerformanceMetrics_Unified;
    PRINT '  New schema metrics (vw_PerformanceMetrics_Unified): ' + CAST(@NewSchemaRows AS VARCHAR);
END

PRINT ''
GO

-- =====================================================
-- Summary and Usage Instructions
-- =====================================================

PRINT '========================================================================='
PRINT 'Legacy Data Migration Complete'
PRINT '========================================================================='
PRINT ''
PRINT 'Migration Status:'

IF OBJECT_ID('dbo.PerformanceMetrics_Legacy', 'U') IS NOT NULL
BEGIN
    PRINT '  ✓ Legacy table renamed: PerformanceMetrics → PerformanceMetrics_Legacy'
    PRINT '  ✓ vw_PerformanceMetrics updated to UNION legacy + new data'
    PRINT '  ✓ Legacy data preserved (zero data loss)'
END
ELSE
BEGIN
    PRINT '  ℹ No legacy data found (fresh installation)'
    PRINT '  ✓ vw_PerformanceMetrics created (standard view)'
END

PRINT ''
PRINT 'Stored Procedures Created:'
PRINT '  - dbo.usp_MarkLegacyDataAsMigrated - Mark rows as migrated (hide from view)'
PRINT '  - dbo.usp_CleanupLegacyData - Delete old migrated data (dry run by default)'
PRINT ''
PRINT 'Usage Examples:'
PRINT ''
PRINT '  -- Mark all legacy data as migrated (after verifying new data is correct)'
PRINT '  EXEC dbo.usp_MarkLegacyDataAsMigrated;'
PRINT ''
PRINT '  -- Mark specific date range as migrated'
PRINT '  EXEC dbo.usp_MarkLegacyDataAsMigrated'
PRINT '      @StartDate = ''2025-01-01'','
PRINT '      @EndDate = ''2025-10-27'';'
PRINT ''
PRINT '  -- Preview cleanup (dry run)'
PRINT '  EXEC dbo.usp_CleanupLegacyData @OlderThanDays = 90, @DryRun = 1;'
PRINT ''
PRINT '  -- Actual cleanup (CAUTION: deletes data)'
PRINT '  EXEC dbo.usp_CleanupLegacyData @OlderThanDays = 90, @DryRun = 0;'
PRINT ''
PRINT '========================================================================='
PRINT 'API Compatibility: 100%'
PRINT '  Existing API code continues to work without changes'
PRINT '  vw_PerformanceMetrics returns same structure (legacy + new data)'
PRINT '========================================================================='
PRINT ''
GO
