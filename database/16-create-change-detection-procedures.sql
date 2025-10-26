-- =============================================
-- Phase 1.25: Change Detection Stored Procedures
-- Part 2: usp_DetectSchemaChanges and usp_RefreshMetadataCache
-- Created: 2025-10-26
-- =============================================

USE [MonitoringDB];
GO

-- Fix for filtered indexes
SET QUOTED_IDENTIFIER ON;
GO

PRINT 'Creating Phase 1.25 change detection stored procedures...';
GO

-- =============================================
-- Procedure 1: usp_DetectSchemaChanges
-- Purpose: Detect pending schema changes and mark databases for refresh
-- Called by: SQL Agent job (every 5 minutes)
-- =============================================

IF OBJECT_ID('dbo.usp_DetectSchemaChanges', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_DetectSchemaChanges;
GO

CREATE PROCEDURE dbo.usp_DetectSchemaChanges
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @AffectedDatabases INT = 0;

    -- Mark databases that have pending schema changes
    UPDATE dmc
    SET IsCurrent = 0,
        LastSchemaChangeTime = (
            SELECT MAX(EventTime)
            FROM dbo.SchemaChangeLog scl
            WHERE scl.ServerName = (SELECT ServerName FROM dbo.Servers WHERE ServerID = dmc.ServerID)
              AND scl.DatabaseName = dmc.DatabaseName
              AND scl.ProcessedAt IS NULL
        )
    FROM dbo.DatabaseMetadataCache dmc
    WHERE EXISTS (
        SELECT 1
        FROM dbo.SchemaChangeLog scl
        WHERE scl.ServerName = (SELECT ServerName FROM dbo.Servers WHERE ServerID = dmc.ServerID)
          AND scl.DatabaseName = dmc.DatabaseName
          AND scl.ProcessedAt IS NULL
    );

    SET @AffectedDatabases = @@ROWCOUNT;

    PRINT CONCAT('Schema change detection completed. Databases marked for refresh: ', @AffectedDatabases);

    -- Return summary
    SELECT
        @AffectedDatabases AS DatabasesNeedingRefresh,
        COUNT(*) AS TotalPendingChanges
    FROM dbo.SchemaChangeLog
    WHERE ProcessedAt IS NULL;
END;
GO

PRINT 'Created procedure: dbo.usp_DetectSchemaChanges';
GO

-- =============================================
-- Procedure 2: usp_RefreshMetadataCache
-- Purpose: Refresh metadata cache for databases marked as stale
-- Called by: SQL Agent job (daily at 2 AM), or manually
-- =============================================

IF OBJECT_ID('dbo.usp_RefreshMetadataCache', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_RefreshMetadataCache;
GO

CREATE PROCEDURE dbo.usp_RefreshMetadataCache
    @ServerID INT = NULL, -- NULL = all servers
    @DatabaseName NVARCHAR(128) = NULL, -- NULL = all databases needing refresh
    @ForceRefresh BIT = 0 -- 1 = refresh even if current
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RefreshCount INT = 0;
    DECLARE @StartTime DATETIME2(7) = GETUTCDATE();

    PRINT CONCAT('Starting metadata cache refresh at ', CONVERT(VARCHAR, @StartTime, 120));
    PRINT CONCAT('  ForceRefresh: ', CASE WHEN @ForceRefresh = 1 THEN 'Yes' ELSE 'No (incremental)' END);

    -- Cursor for databases needing refresh
    DECLARE @CurServerID INT, @CurDatabaseName NVARCHAR(128), @CurServerName NVARCHAR(128);

    DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT dmc.ServerID, dmc.DatabaseName, s.ServerName
        FROM dbo.DatabaseMetadataCache dmc
        INNER JOIN dbo.Servers s ON dmc.ServerID = s.ServerID
        WHERE (@ServerID IS NULL OR dmc.ServerID = @ServerID)
          AND (@DatabaseName IS NULL OR dmc.DatabaseName = @DatabaseName)
          AND (@ForceRefresh = 1 OR dmc.IsCurrent = 0);

    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @CurServerID, @CurDatabaseName, @CurServerName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        PRINT CONCAT('  Refreshing metadata for: ', @CurServerName, '.', @CurDatabaseName);

        -- Delete old metadata for this database
        DELETE FROM dbo.TableMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName;
        DELETE FROM dbo.ColumnMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName;
        DELETE FROM dbo.IndexMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName;
        DELETE FROM dbo.PartitionMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName;
        DELETE FROM dbo.ForeignKeyMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName;
        DELETE FROM dbo.CodeObjectMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName;
        DELETE FROM dbo.DependencyMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName;

        -- Collect fresh metadata (will call individual collection procedures when they exist)
        -- NOTE: Collection procedures (usp_CollectTableMetadata, etc.) will be created in next steps
        -- For now, we just mark as refreshed

        -- Update cache status
        UPDATE dbo.DatabaseMetadataCache
        SET LastRefreshTime = GETUTCDATE(),
            IsCurrent = 1
        WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName;

        -- Mark schema changes as processed
        UPDATE dbo.SchemaChangeLog
        SET ProcessedAt = GETUTCDATE()
        WHERE ServerName = @CurServerName
          AND DatabaseName = @CurDatabaseName
          AND ProcessedAt IS NULL;

        SET @RefreshCount = @RefreshCount + 1;

        FETCH NEXT FROM db_cursor INTO @CurServerID, @CurDatabaseName, @CurServerName;
    END;

    CLOSE db_cursor;
    DEALLOCATE db_cursor;

    DECLARE @Duration INT = DATEDIFF(MILLISECOND, @StartTime, GETUTCDATE());

    PRINT '';
    PRINT CONCAT('Metadata cache refresh completed. Databases refreshed: ', @RefreshCount);
    PRINT CONCAT('Duration: ', @Duration, ' ms');

    -- Return summary
    SELECT
        @RefreshCount AS DatabasesRefreshed,
        @Duration AS DurationMs,
        (SELECT COUNT(*) FROM dbo.DatabaseMetadataCache WHERE IsCurrent = 0) AS StillNeedingRefresh;
END;
GO

PRINT 'Created procedure: dbo.usp_RefreshMetadataCache';
GO

-- =============================================
-- Procedure 3: usp_RegisterDatabaseForMonitoring
-- Purpose: Add a database to the metadata cache for tracking
-- Called by: Admin when adding new database to monitor
-- =============================================

IF OBJECT_ID('dbo.usp_RegisterDatabaseForMonitoring', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_RegisterDatabaseForMonitoring;
GO

CREATE PROCEDURE dbo.usp_RegisterDatabaseForMonitoring
    @ServerID INT,
    @DatabaseName NVARCHAR(128),
    @PerformInitialRefresh BIT = 1 -- 1 = immediately refresh metadata
AS
BEGIN
    SET NOCOUNT ON;

    -- Check if database already registered
    IF EXISTS (SELECT 1 FROM dbo.DatabaseMetadataCache WHERE ServerID = @ServerID AND DatabaseName = @DatabaseName)
    BEGIN
        PRINT CONCAT('Database already registered: ', @DatabaseName);
        RETURN;
    END;

    -- Register database
    INSERT INTO dbo.DatabaseMetadataCache (ServerID, DatabaseName, LastRefreshTime, IsCurrent)
    VALUES (@ServerID, @DatabaseName, GETUTCDATE(), CASE WHEN @PerformInitialRefresh = 1 THEN 0 ELSE 1 END);

    PRINT CONCAT('Database registered for metadata tracking: ', @DatabaseName);

    -- Perform initial refresh if requested
    IF @PerformInitialRefresh = 1
    BEGIN
        PRINT 'Performing initial metadata refresh...';
        EXEC dbo.usp_RefreshMetadataCache @ServerID = @ServerID, @DatabaseName = @DatabaseName, @ForceRefresh = 1;
    END;
END;
GO

PRINT 'Created procedure: dbo.usp_RegisterDatabaseForMonitoring';
GO

-- =============================================
-- Inline Testing (Manual Test Cases)
-- =============================================

-- Fix for filtered index operations
SET QUOTED_IDENTIFIER ON;
GO

PRINT '';
PRINT '========================================';
PRINT 'Manual Test Cases';
PRINT '========================================';
PRINT '';

-- Test 1: Register MonitoringDB for metadata tracking
PRINT 'Test 1: Register MonitoringDB for metadata tracking';

DECLARE @TestServerID INT = 1;

-- Ensure clean slate
DELETE FROM dbo.DatabaseMetadataCache WHERE ServerID = @TestServerID AND DatabaseName = 'MonitoringDB';

-- Register database (without immediate refresh for testing)
EXEC dbo.usp_RegisterDatabaseForMonitoring
    @ServerID = @TestServerID,
    @DatabaseName = 'MonitoringDB',
    @PerformInitialRefresh = 0;

-- Verify registration
DECLARE @Registered INT;
SELECT @Registered = COUNT(*)
FROM dbo.DatabaseMetadataCache
WHERE ServerID = @TestServerID AND DatabaseName = 'MonitoringDB';

IF @Registered = 1
    PRINT '  ✓ PASSED: Database registered successfully';
ELSE
    PRINT '  ✗ FAILED: Database not registered';

PRINT '';

-- Test 2: Simulate schema change and detect it
PRINT 'Test 2: Simulate schema change and detect it';

DECLARE @TestServerName NVARCHAR(128);
SELECT @TestServerName = ServerName FROM dbo.Servers WHERE ServerID = @TestServerID;

-- Simulate a DDL event
INSERT INTO dbo.SchemaChangeLog (ServerName, DatabaseName, SchemaName, ObjectName, EventType, EventTime, ProcessedAt)
VALUES (@TestServerName, 'MonitoringDB', 'dbo', 'TestTable', 'CREATE_TABLE', GETUTCDATE(), NULL);

-- Run change detection
EXEC dbo.usp_DetectSchemaChanges;

-- Verify database marked as stale
DECLARE @IsCurrent BIT;
SELECT @IsCurrent = IsCurrent
FROM dbo.DatabaseMetadataCache
WHERE ServerID = @TestServerID AND DatabaseName = 'MonitoringDB';

IF @IsCurrent = 0
    PRINT '  ✓ PASSED: Database marked as stale (IsCurrent=0) after schema change';
ELSE
    PRINT '  ✗ FAILED: Database should be marked as stale';

PRINT '';

-- Test 3: Refresh metadata cache
PRINT 'Test 3: Refresh metadata cache';

EXEC dbo.usp_RefreshMetadataCache
    @ServerID = @TestServerID,
    @DatabaseName = 'MonitoringDB',
    @ForceRefresh = 0;

-- Verify database marked as current after refresh
SELECT @IsCurrent = IsCurrent
FROM dbo.DatabaseMetadataCache
WHERE ServerID = @TestServerID AND DatabaseName = 'MonitoringDB';

IF @IsCurrent = 1
    PRINT '  ✓ PASSED: Database marked as current (IsCurrent=1) after refresh';
ELSE
    PRINT '  ✗ FAILED: Database should be marked as current after refresh';

-- Verify schema changes marked as processed
DECLARE @PendingChanges INT;
SELECT @PendingChanges = COUNT(*)
FROM dbo.SchemaChangeLog
WHERE ServerName = @TestServerName
  AND DatabaseName = 'MonitoringDB'
  AND ProcessedAt IS NULL;

IF @PendingChanges = 0
    PRINT '  ✓ PASSED: Schema changes marked as processed';
ELSE
    PRINT '  ✗ FAILED: Schema changes should be marked as processed';

PRINT '';

-- Cleanup test data
DELETE FROM dbo.SchemaChangeLog WHERE ServerName = @TestServerName AND DatabaseName = 'MonitoringDB';
DELETE FROM dbo.DatabaseMetadataCache WHERE ServerID = @TestServerID AND DatabaseName = 'MonitoringDB';

PRINT '';
PRINT '========================================';
PRINT 'Phase 1.25 Change Detection Summary';
PRINT '========================================';
PRINT 'Stored procedures created:';
PRINT '  1. usp_DetectSchemaChanges - Detect pending schema changes';
PRINT '  2. usp_RefreshMetadataCache - Refresh metadata for stale databases';
PRINT '  3. usp_RegisterDatabaseForMonitoring - Register new database';
PRINT '';
PRINT 'Manual test results shown above.';
PRINT '';
PRINT 'Next steps:';
PRINT '  1. Create metadata collection procedures (usp_CollectTableMetadata, etc.)';
PRINT '  2. Create DDL triggers on monitored databases';
PRINT '  3. Create SQL Agent jobs for automation';
PRINT '========================================';
GO
