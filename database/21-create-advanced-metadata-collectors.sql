-- =============================================
-- Phase 1.25 Day 4: Advanced Metadata Collection Procedures
-- Part 1: CodeObjectMetadata and DependencyMetadata collectors
-- Created: 2025-10-26
-- =============================================

USE [MonitoringDB];
GO

SET QUOTED_IDENTIFIER ON;
GO

PRINT 'Creating Phase 1.25 Day 4 advanced metadata collection procedures...';
PRINT '';
GO

-- =============================================
-- Procedure 1: usp_CollectCodeObjectMetadata
-- Purpose: Collect code object metadata (SPs, views, functions, triggers)
-- Called by: usp_RefreshMetadataCache
-- =============================================

IF OBJECT_ID('dbo.usp_CollectCodeObjectMetadata', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectCodeObjectMetadata;
GO

CREATE PROCEDURE dbo.usp_CollectCodeObjectMetadata
    @ServerID INT,
    @DatabaseName NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ServerName NVARCHAR(128);
    SELECT @ServerName = ServerName FROM dbo.Servers WHERE ServerID = @ServerID;

    IF @ServerName IS NULL
    BEGIN
        RAISERROR('ServerID %d not found in Servers table', 16, 1, @ServerID);
        RETURN;
    END;

    PRINT CONCAT('  Collecting code object metadata for: ', @ServerName, '.', @DatabaseName);

    -- Build dynamic SQL to query the target database
    DECLARE @SQL NVARCHAR(MAX) = N'
    INSERT INTO dbo.CodeObjectMetadata (
        ServerID, DatabaseName, SchemaName, ObjectName, ObjectType,
        CodeID, LineCount, CharacterCount,
        CreatedDate, ModifiedDate, LastRefreshTime
    )
    SELECT
        @ServerID,
        @DatabaseName,
        SCHEMA_NAME(o.schema_id) AS SchemaName,
        o.name AS ObjectName,

        -- Object type (friendly name)
        CASE o.type
            WHEN ''P'' THEN ''Stored Procedure''
            WHEN ''V'' THEN ''View''
            WHEN ''FN'' THEN ''Scalar Function''
            WHEN ''IF'' THEN ''Inline Table Function''
            WHEN ''TF'' THEN ''Table Function''
            WHEN ''TR'' THEN ''Trigger''
            ELSE o.type_desc
        END AS ObjectType,

        -- Link to ObjectCode table (if exists)
        oc.CodeID,

        -- Line count (count newlines in definition)
        CASE
            WHEN sm.definition IS NOT NULL
            THEN LEN(sm.definition) - LEN(REPLACE(sm.definition, CHAR(10), '''')) + 1
            ELSE 0
        END AS LineCount,

        -- Character count
        CASE
            WHEN sm.definition IS NOT NULL
            THEN LEN(sm.definition)
            ELSE 0
        END AS CharacterCount,

        -- Created and modified dates
        o.create_date AS CreatedDate,
        o.modify_date AS ModifiedDate,

        -- Refresh timestamp
        GETUTCDATE() AS LastRefreshTime

    FROM ' + QUOTENAME(@DatabaseName) + '.sys.objects o

    -- SQL module definition
    LEFT JOIN ' + QUOTENAME(@DatabaseName) + '.sys.sql_modules sm
        ON o.object_id = sm.object_id

    -- Link to existing ObjectCode table (if code is tracked)
    LEFT JOIN dbo.ObjectCode oc
        ON oc.ServerID = @ServerID
        AND oc.DatabaseName COLLATE DATABASE_DEFAULT = @DatabaseName COLLATE DATABASE_DEFAULT
        AND oc.SchemaName COLLATE DATABASE_DEFAULT = SCHEMA_NAME(o.schema_id) COLLATE DATABASE_DEFAULT
        AND oc.ObjectName COLLATE DATABASE_DEFAULT = o.name COLLATE DATABASE_DEFAULT
        AND oc.ObjectType COLLATE DATABASE_DEFAULT = o.type COLLATE DATABASE_DEFAULT

    WHERE o.type IN (''P'', ''V'', ''FN'', ''IF'', ''TF'', ''TR'')  -- Procedures, views, functions, triggers
      AND o.is_ms_shipped = 0  -- Exclude system objects

    ORDER BY SCHEMA_NAME(o.schema_id), o.name;
    ';

    -- Execute dynamic SQL
    BEGIN TRY
        EXEC sp_executesql @SQL,
            N'@ServerID INT, @DatabaseName NVARCHAR(128)',
            @ServerID = @ServerID,
            @DatabaseName = @DatabaseName;

        DECLARE @RowCount INT = @@ROWCOUNT;
        PRINT CONCAT('    Collected ', @RowCount, ' code objects');
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        PRINT CONCAT('    ERROR: ', @ErrorMessage);
        THROW;
    END CATCH;
END;
GO

PRINT 'Created procedure: dbo.usp_CollectCodeObjectMetadata';
GO

-- =============================================
-- Procedure 2: usp_CollectDependencyMetadata
-- Purpose: Collect object-to-object dependency metadata
-- Called by: usp_RefreshMetadataCache
-- =============================================

IF OBJECT_ID('dbo.usp_CollectDependencyMetadata', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectDependencyMetadata;
GO

CREATE PROCEDURE dbo.usp_CollectDependencyMetadata
    @ServerID INT,
    @DatabaseName NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ServerName NVARCHAR(128);
    SELECT @ServerName = ServerName FROM dbo.Servers WHERE ServerID = @ServerID;

    IF @ServerName IS NULL
    BEGIN
        RAISERROR('ServerID %d not found in Servers table', 16, 1, @ServerID);
        RETURN;
    END;

    PRINT CONCAT('  Collecting dependency metadata for: ', @ServerName, '.', @DatabaseName);

    -- Build dynamic SQL to query the target database
    DECLARE @SQL NVARCHAR(MAX) = N'
    INSERT INTO dbo.DependencyMetadata (
        ServerID, DatabaseName,
        ReferencingSchemaName, ReferencingObjectName, ReferencingObjectType,
        ReferencedSchemaName, ReferencedObjectName, ReferencedObjectType,
        IsSchemaDependent, IsAmbiguous,
        LastRefreshTime
    )
    SELECT DISTINCT
        @ServerID,
        @DatabaseName,

        -- Referencing object (the one that depends on another)
        SCHEMA_NAME(o_ref.schema_id) AS ReferencingSchemaName,
        o_ref.name AS ReferencingObjectName,
        CASE o_ref.type
            WHEN ''P'' THEN ''Stored Procedure''
            WHEN ''V'' THEN ''View''
            WHEN ''FN'' THEN ''Scalar Function''
            WHEN ''IF'' THEN ''Inline Table Function''
            WHEN ''TF'' THEN ''Table Function''
            WHEN ''TR'' THEN ''Trigger''
            ELSE o_ref.type_desc
        END AS ReferencingObjectType,

        -- Referenced object (the dependency)
        sed.referenced_schema_name AS ReferencedSchemaName,
        sed.referenced_entity_name AS ReferencedObjectName,

        -- Referenced type (may be NULL if object not found)
        CASE o_dep.type
            WHEN ''U'' THEN ''Table''
            WHEN ''V'' THEN ''View''
            WHEN ''P'' THEN ''Stored Procedure''
            WHEN ''FN'' THEN ''Scalar Function''
            WHEN ''IF'' THEN ''Inline Table Function''
            WHEN ''TF'' THEN ''Table Function''
            WHEN ''TR'' THEN ''Trigger''
            ELSE COALESCE(o_dep.type_desc, ''Unknown'')
        END AS ReferencedObjectType,

        -- Dependency flags
        sed.is_schema_bound_reference AS IsSchemaDependent,
        sed.is_ambiguous AS IsAmbiguous,

        -- Refresh timestamp
        GETUTCDATE() AS LastRefreshTime

    FROM ' + QUOTENAME(@DatabaseName) + '.sys.sql_expression_dependencies sed

    -- Referencing object (the one WITH the dependency)
    INNER JOIN ' + QUOTENAME(@DatabaseName) + '.sys.objects o_ref
        ON sed.referencing_id = o_ref.object_id

    -- Referenced object (the dependency itself) - may not exist if cross-database
    LEFT JOIN ' + QUOTENAME(@DatabaseName) + '.sys.objects o_dep
        ON sed.referenced_id = o_dep.object_id

    WHERE o_ref.is_ms_shipped = 0  -- Exclude system objects
      AND sed.referenced_database_name IS NULL  -- Only same-database dependencies

    ORDER BY
        SCHEMA_NAME(o_ref.schema_id),
        o_ref.name,
        sed.referenced_schema_name,
        sed.referenced_entity_name;
    ';

    -- Execute dynamic SQL
    BEGIN TRY
        EXEC sp_executesql @SQL,
            N'@ServerID INT, @DatabaseName NVARCHAR(128)',
            @ServerID = @ServerID,
            @DatabaseName = @DatabaseName;

        DECLARE @RowCount INT = @@ROWCOUNT;
        PRINT CONCAT('    Collected ', @RowCount, ' dependencies');
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        PRINT CONCAT('    ERROR: ', @ErrorMessage);
        THROW;
    END CATCH;
END;
GO

PRINT 'Created procedure: dbo.usp_CollectDependencyMetadata';
GO

-- =============================================
-- Procedure 3: usp_CollectAllAdvancedMetrics (Convenience wrapper)
-- Purpose: Collect all advanced metadata in one call
-- =============================================

IF OBJECT_ID('dbo.usp_CollectAllAdvancedMetrics', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectAllAdvancedMetrics;
GO

CREATE PROCEDURE dbo.usp_CollectAllAdvancedMetrics
    @ServerID INT,
    @DatabaseName NVARCHAR(128) = NULL  -- NULL = MonitoringDB
AS
BEGIN
    SET NOCOUNT ON;

    IF @DatabaseName IS NULL
        SET @DatabaseName = DB_NAME();

    PRINT CONCAT('Collecting all advanced metadata for ServerID ', @ServerID, ', Database: ', @DatabaseName);
    PRINT '';

    -- Collect code objects
    EXEC dbo.usp_CollectCodeObjectMetadata
        @ServerID = @ServerID,
        @DatabaseName = @DatabaseName;

    -- Collect dependencies
    EXEC dbo.usp_CollectDependencyMetadata
        @ServerID = @ServerID,
        @DatabaseName = @DatabaseName;

    PRINT '';
    PRINT 'All advanced metadata collected successfully.';
END;
GO

PRINT 'Created procedure: dbo.usp_CollectAllAdvancedMetrics';
GO

-- =============================================
-- Update usp_RefreshMetadataCache to include advanced collectors
-- =============================================

PRINT 'Updating usp_RefreshMetadataCache to integrate advanced metadata collectors...';
GO

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
        PRINT CONCAT('Refreshing metadata for: ', @CurServerName, '.', @CurDatabaseName);

        -- Delete old metadata for this database
        DELETE FROM dbo.TableMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName;
        DELETE FROM dbo.ColumnMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName;
        DELETE FROM dbo.IndexMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName;
        DELETE FROM dbo.PartitionMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName;
        DELETE FROM dbo.ForeignKeyMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName;
        DELETE FROM dbo.CodeObjectMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName;
        DELETE FROM dbo.DependencyMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName;

        -- Collect fresh metadata
        BEGIN TRY
            -- Day 2 collectors
            EXEC dbo.usp_CollectTableMetadata @ServerID = @CurServerID, @DatabaseName = @CurDatabaseName;
            EXEC dbo.usp_CollectColumnMetadata @ServerID = @CurServerID, @DatabaseName = @CurDatabaseName;

            -- Day 3 collectors
            EXEC dbo.usp_CollectIndexMetadata @ServerID = @CurServerID, @DatabaseName = @CurDatabaseName;
            EXEC dbo.usp_CollectPartitionMetadata @ServerID = @CurServerID, @DatabaseName = @CurDatabaseName;
            EXEC dbo.usp_CollectForeignKeyMetadata @ServerID = @CurServerID, @DatabaseName = @CurDatabaseName;

            -- Day 4 collectors (NEW)
            EXEC dbo.usp_CollectCodeObjectMetadata @ServerID = @CurServerID, @DatabaseName = @CurDatabaseName;
            EXEC dbo.usp_CollectDependencyMetadata @ServerID = @CurServerID, @DatabaseName = @CurDatabaseName;

            -- Update cache status with counts
            UPDATE dbo.DatabaseMetadataCache
            SET LastRefreshTime = GETUTCDATE(),
                IsCurrent = 1,
                TableCount = (SELECT COUNT(*) FROM dbo.TableMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName),
                ViewCount = (SELECT COUNT(*) FROM dbo.CodeObjectMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName AND ObjectType = 'View'),
                ProcedureCount = (SELECT COUNT(*) FROM dbo.CodeObjectMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName AND ObjectType = 'Stored Procedure'),
                FunctionCount = (SELECT COUNT(*) FROM dbo.CodeObjectMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName AND ObjectType LIKE '%Function%')
            WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName;

            -- Mark schema changes as processed
            UPDATE dbo.SchemaChangeLog
            SET ProcessedAt = GETUTCDATE()
            WHERE ServerName = @CurServerName
              AND DatabaseName = @CurDatabaseName
              AND ProcessedAt IS NULL;

            SET @RefreshCount = @RefreshCount + 1;
        END TRY
        BEGIN CATCH
            PRINT CONCAT('  ERROR refreshing ', @CurDatabaseName, ': ', ERROR_MESSAGE());
            -- Continue with next database despite error
        END CATCH;

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
        (SELECT COUNT(*) FROM dbo.DatabaseMetadataCache WHERE IsCurrent = 0) AS StillNeedingRefresh,
        (SELECT SUM(TableCount) FROM dbo.DatabaseMetadataCache WHERE IsCurrent = 1) AS TotalTablesCached,
        (SELECT SUM(ViewCount) FROM dbo.DatabaseMetadataCache WHERE IsCurrent = 1) AS TotalViewsCached,
        (SELECT SUM(ProcedureCount) FROM dbo.DatabaseMetadataCache WHERE IsCurrent = 1) AS TotalProceduresCached,
        (SELECT SUM(FunctionCount) FROM dbo.DatabaseMetadataCache WHERE IsCurrent = 1) AS TotalFunctionsCached;
END;
GO

PRINT 'Updated procedure: dbo.usp_RefreshMetadataCache';
GO

-- =============================================
-- Inline Testing
-- =============================================

SET QUOTED_IDENTIFIER ON;
GO

PRINT '';
PRINT '========================================';
PRINT 'Testing Advanced Metadata Collection';
PRINT '========================================';
PRINT '';

-- Test: Collect metadata for MonitoringDB
DECLARE @TestServerID INT = 1;

-- Register MonitoringDB for tracking (if not already)
IF NOT EXISTS (SELECT 1 FROM dbo.DatabaseMetadataCache WHERE ServerID = @TestServerID AND DatabaseName = 'MonitoringDB')
BEGIN
    INSERT INTO dbo.DatabaseMetadataCache (ServerID, DatabaseName, LastRefreshTime, IsCurrent)
    VALUES (@TestServerID, 'MonitoringDB', GETUTCDATE(), 0);
    PRINT 'Registered MonitoringDB for metadata tracking';
END;

-- Collect code object metadata
PRINT '';
PRINT 'Test 1: Collect code object metadata for MonitoringDB';
EXEC dbo.usp_CollectCodeObjectMetadata @ServerID = @TestServerID, @DatabaseName = 'MonitoringDB';

-- Verify code objects collected
DECLARE @CodeObjectCount INT;
SELECT @CodeObjectCount = COUNT(*) FROM dbo.CodeObjectMetadata WHERE ServerID = @TestServerID AND DatabaseName = 'MonitoringDB';

PRINT '';
IF @CodeObjectCount > 0
    PRINT CONCAT('✓ SUCCESS: Collected ', @CodeObjectCount, ' code objects from MonitoringDB');
ELSE
    PRINT '✗ FAILED: No code objects collected';

-- Show sample code objects
PRINT '';
PRINT 'Sample code objects (top 10 by line count):';
SELECT TOP 10
    SchemaName,
    ObjectName,
    ObjectType,
    LineCount,
    CharacterCount,
    ModifiedDate
FROM dbo.CodeObjectMetadata
WHERE ServerID = @TestServerID AND DatabaseName = 'MonitoringDB'
ORDER BY LineCount DESC;

-- Collect dependency metadata
PRINT '';
PRINT 'Test 2: Collect dependency metadata for MonitoringDB';
EXEC dbo.usp_CollectDependencyMetadata @ServerID = @TestServerID, @DatabaseName = 'MonitoringDB';

-- Verify dependencies collected
DECLARE @DependencyCount INT;
SELECT @DependencyCount = COUNT(*) FROM dbo.DependencyMetadata WHERE ServerID = @TestServerID AND DatabaseName = 'MonitoringDB';

PRINT '';
IF @DependencyCount > 0
    PRINT CONCAT('✓ SUCCESS: Collected ', @DependencyCount, ' dependencies from MonitoringDB');
ELSE
    PRINT '✗ FAILED: No dependencies collected';

-- Show sample dependencies
PRINT '';
PRINT 'Sample dependencies (stored procedures referencing tables):';
SELECT TOP 10
    ReferencingSchemaName,
    ReferencingObjectName,
    ReferencingObjectType,
    ReferencedSchemaName,
    ReferencedObjectName,
    ReferencedObjectType
FROM dbo.DependencyMetadata
WHERE ServerID = @TestServerID
  AND DatabaseName = 'MonitoringDB'
  AND ReferencingObjectType = 'Stored Procedure'
  AND ReferencedObjectType = 'Table'
ORDER BY ReferencingObjectName;

-- Test full refresh workflow (all 7 collectors)
PRINT '';
PRINT 'Test 3: Full refresh workflow (all collectors including Day 4)';
UPDATE dbo.DatabaseMetadataCache SET IsCurrent = 0 WHERE ServerID = @TestServerID AND DatabaseName = 'MonitoringDB';
EXEC dbo.usp_RefreshMetadataCache @ServerID = @TestServerID, @DatabaseName = 'MonitoringDB';

PRINT '';
PRINT '========================================';
PRINT 'Day 4 Advanced Metadata Summary';
PRINT '========================================';
PRINT 'Procedures created:';
PRINT '  1. usp_CollectCodeObjectMetadata - Collect SPs, views, functions, triggers';
PRINT '  2. usp_CollectDependencyMetadata - Collect object dependencies';
PRINT '  3. usp_CollectAllAdvancedMetrics - Convenience wrapper';
PRINT '  4. usp_RefreshMetadataCache - Updated with Day 4 collectors';
PRINT '';
PRINT 'Test results shown above.';
PRINT '';
PRINT 'Next steps (Day 5):';
PRINT '  1. Create SQL Agent job: Schema Change Detection (every 5 min)';
PRINT '  2. Create SQL Agent job: Metadata Refresh (daily at 2 AM)';
PRINT '  3. Create Grafana dashboards for schema browsing';
PRINT '========================================';
GO
