-- =============================================
-- Phase 1.25 Day 3: Remaining Metadata Collectors
-- Part 2: IndexMetadata, PartitionMetadata, ForeignKeyMetadata
-- Created: 2025-10-26
-- =============================================

USE [MonitoringDB];
GO

SET QUOTED_IDENTIFIER ON;
GO

PRINT 'Creating Phase 1.25 remaining metadata collectors...';
PRINT '';
GO

-- =============================================
-- Procedure 1: usp_CollectIndexMetadata
-- Purpose: Collect index metadata with fragmentation stats
-- Called by: usp_RefreshMetadataCache
-- =============================================

IF OBJECT_ID('dbo.usp_CollectIndexMetadata', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectIndexMetadata;
GO

CREATE PROCEDURE dbo.usp_CollectIndexMetadata
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

    PRINT CONCAT('  Collecting index metadata for: ', @ServerName, '.', @DatabaseName);

    -- Build dynamic SQL to query the target database
    DECLARE @SQL NVARCHAR(MAX) = N'
    INSERT INTO dbo.IndexMetadata (
        ServerID, DatabaseName, SchemaName, TableName, IndexName,
        IndexType, KeyColumns, IncludedColumns, FilterDefinition,
        IsUnique, IsPrimaryKey, [FillFactor],
        SizeMB, [RowCount], FragmentationPercent, PageCount, CompressionType,
        LastRefreshTime
    )
    SELECT
        @ServerID,
        @DatabaseName,
        SCHEMA_NAME(t.schema_id) AS SchemaName,
        t.name AS TableName,
        i.name AS IndexName,

        -- Index type
        i.type_desc AS IndexType,

        -- Key columns (comma-separated)
        STUFF((
            SELECT '','' + c.name
            FROM ' + QUOTENAME(@DatabaseName) + '.sys.index_columns ic
            INNER JOIN ' + QUOTENAME(@DatabaseName) + '.sys.columns c
                ON ic.object_id = c.object_id AND ic.column_id = c.column_id
            WHERE ic.object_id = i.object_id
              AND ic.index_id = i.index_id
              AND ic.is_included_column = 0
            ORDER BY ic.key_ordinal
            FOR XML PATH('''')
        ), 1, 1, '''') AS KeyColumns,

        -- Included columns (comma-separated)
        STUFF((
            SELECT '','' + c.name
            FROM ' + QUOTENAME(@DatabaseName) + '.sys.index_columns ic
            INNER JOIN ' + QUOTENAME(@DatabaseName) + '.sys.columns c
                ON ic.object_id = c.object_id AND ic.column_id = c.column_id
            WHERE ic.object_id = i.object_id
              AND ic.index_id = i.index_id
              AND ic.is_included_column = 1
            FOR XML PATH('''')
        ), 1, 1, '''') AS IncludedColumns,

        -- Filter definition (for filtered indexes)
        i.filter_definition AS FilterDefinition,

        -- Index properties
        i.is_unique AS IsUnique,
        i.is_primary_key AS IsPrimaryKey,
        CASE WHEN i.fill_factor = 0 THEN 100 ELSE i.fill_factor END AS [FillFactor],

        -- Size and row count
        CAST(SUM(ps.used_page_count) * 8 / 1024.0 AS DECIMAL(18,2)) AS SizeMB,
        SUM(ps.row_count) AS [RowCount],

        -- Fragmentation (from sys.dm_db_index_physical_stats - expensive, use LIMITED mode)
        AVG(ips.avg_fragmentation_in_percent) AS FragmentationPercent,

        -- Page count
        SUM(ps.used_page_count) AS PageCount,

        -- Compression type
        MAX(p.data_compression_desc) AS CompressionType,

        -- Refresh timestamp
        GETUTCDATE() AS LastRefreshTime

    FROM ' + QUOTENAME(@DatabaseName) + '.sys.tables t
    INNER JOIN ' + QUOTENAME(@DatabaseName) + '.sys.indexes i
        ON t.object_id = i.object_id
    INNER JOIN ' + QUOTENAME(@DatabaseName) + '.sys.dm_db_partition_stats ps
        ON i.object_id = ps.object_id AND i.index_id = ps.index_id
    LEFT JOIN ' + QUOTENAME(@DatabaseName) + '.sys.dm_db_index_physical_stats(DB_ID(@DatabaseName), NULL, NULL, NULL, ''LIMITED'') ips
        ON i.object_id = ips.object_id AND i.index_id = ips.index_id
    LEFT JOIN ' + QUOTENAME(@DatabaseName) + '.sys.partitions p
        ON i.object_id = p.object_id AND i.index_id = p.index_id

    WHERE t.is_ms_shipped = 0
      AND i.index_id > 0  -- Exclude heap (index_id = 0)

    GROUP BY
        t.schema_id, t.name, i.object_id, i.index_id, i.name, i.type_desc,
        i.filter_definition, i.is_unique, i.is_primary_key, i.fill_factor;
    ';

    -- Execute dynamic SQL
    BEGIN TRY
        EXEC sp_executesql @SQL,
            N'@ServerID INT, @DatabaseName NVARCHAR(128)',
            @ServerID = @ServerID,
            @DatabaseName = @DatabaseName;

        DECLARE @RowCount INT = @@ROWCOUNT;
        PRINT CONCAT('    Collected ', @RowCount, ' indexes');
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        PRINT CONCAT('    ERROR: ', @ErrorMessage);
        THROW;
    END CATCH;
END;
GO

PRINT 'Created procedure: dbo.usp_CollectIndexMetadata';
GO

-- =============================================
-- Procedure 2: usp_CollectPartitionMetadata
-- Purpose: Collect partition statistics for partitioned tables
-- Called by: usp_RefreshMetadataCache
-- =============================================

IF OBJECT_ID('dbo.usp_CollectPartitionMetadata', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectPartitionMetadata;
GO

CREATE PROCEDURE dbo.usp_CollectPartitionMetadata
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

    PRINT CONCAT('  Collecting partition metadata for: ', @ServerName, '.', @DatabaseName);

    -- Build dynamic SQL to query the target database
    DECLARE @SQL NVARCHAR(MAX) = N'
    INSERT INTO dbo.PartitionMetadata (
        ServerID, DatabaseName, SchemaName, TableName, IndexName, PartitionNumber,
        BoundaryValue, [RowCount], SizeMB, CompressionType, DataSpace,
        LastRefreshTime
    )
    SELECT
        @ServerID,
        @DatabaseName,
        SCHEMA_NAME(t.schema_id) AS SchemaName,
        t.name AS TableName,
        i.name AS IndexName,
        p.partition_number AS PartitionNumber,

        -- Partition boundary value (convert to string for storage)
        CAST(prv.value AS NVARCHAR(MAX)) AS BoundaryValue,

        -- Row count per partition
        p.rows AS [RowCount],

        -- Size per partition in MB
        CAST(SUM(a.total_pages) * 8 / 1024.0 AS DECIMAL(18,2)) AS SizeMB,

        -- Compression type
        p.data_compression_desc AS CompressionType,

        -- Data space (filegroup)
        ds.name AS DataSpace,

        -- Refresh timestamp
        GETUTCDATE() AS LastRefreshTime

    FROM ' + QUOTENAME(@DatabaseName) + '.sys.tables t
    INNER JOIN ' + QUOTENAME(@DatabaseName) + '.sys.indexes i
        ON t.object_id = i.object_id
    INNER JOIN ' + QUOTENAME(@DatabaseName) + '.sys.partitions p
        ON i.object_id = p.object_id AND i.index_id = p.index_id
    INNER JOIN ' + QUOTENAME(@DatabaseName) + '.sys.allocation_units a
        ON p.partition_id = a.container_id
    INNER JOIN ' + QUOTENAME(@DatabaseName) + '.sys.data_spaces ds
        ON i.data_space_id = ds.data_space_id

    -- Join to partition function and range values
    LEFT JOIN ' + QUOTENAME(@DatabaseName) + '.sys.partition_schemes ps
        ON i.data_space_id = ps.data_space_id
    LEFT JOIN ' + QUOTENAME(@DatabaseName) + '.sys.partition_functions pf
        ON ps.function_id = pf.function_id
    LEFT JOIN ' + QUOTENAME(@DatabaseName) + '.sys.partition_range_values prv
        ON ps.function_id = prv.function_id
        AND p.partition_number = CASE pf.boundary_value_on_right
            WHEN 1 THEN prv.boundary_id + 1  -- RIGHT boundary
            ELSE prv.boundary_id              -- LEFT boundary
        END

    WHERE t.is_ms_shipped = 0
      AND i.index_id IN (0, 1)  -- Heap or clustered index only
      AND p.partition_number > 1  -- Only partitioned tables (more than 1 partition)

    GROUP BY
        t.schema_id, t.name, i.name, p.partition_number, prv.value,
        p.rows, p.data_compression_desc, ds.name;
    ';

    -- Execute dynamic SQL
    BEGIN TRY
        EXEC sp_executesql @SQL,
            N'@ServerID INT, @DatabaseName NVARCHAR(128)',
            @ServerID = @ServerID,
            @DatabaseName = @DatabaseName;

        DECLARE @RowCount INT = @@ROWCOUNT;
        PRINT CONCAT('    Collected ', @RowCount, ' partitions');
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        PRINT CONCAT('    ERROR: ', @ErrorMessage);
        THROW;
    END CATCH;
END;
GO

PRINT 'Created procedure: dbo.usp_CollectPartitionMetadata';
GO

-- =============================================
-- Procedure 3: usp_CollectForeignKeyMetadata
-- Purpose: Collect foreign key relationships
-- Called by: usp_RefreshMetadataCache
-- =============================================

IF OBJECT_ID('dbo.usp_CollectForeignKeyMetadata', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectForeignKeyMetadata;
GO

CREATE PROCEDURE dbo.usp_CollectForeignKeyMetadata
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

    PRINT CONCAT('  Collecting foreign key metadata for: ', @ServerName, '.', @DatabaseName);

    -- Build dynamic SQL to query the target database
    DECLARE @SQL NVARCHAR(MAX) = N'
    INSERT INTO dbo.ForeignKeyMetadata (
        ServerID, DatabaseName, ForeignKeyName,
        ParentSchemaName, ParentTableName, ParentColumns,
        ReferencedSchemaName, ReferencedTableName, ReferencedColumns,
        DeleteRule, UpdateRule, IsDisabled, IsNotTrusted,
        LastRefreshTime
    )
    SELECT
        @ServerID,
        @DatabaseName,
        fk.name AS ForeignKeyName,

        -- Parent (referencing) side
        SCHEMA_NAME(pt.schema_id) AS ParentSchemaName,
        pt.name AS ParentTableName,

        -- Parent columns (comma-separated)
        STUFF((
            SELECT '','' + c.name
            FROM ' + QUOTENAME(@DatabaseName) + '.sys.foreign_key_columns fkc
            INNER JOIN ' + QUOTENAME(@DatabaseName) + '.sys.columns c
                ON fkc.parent_object_id = c.object_id AND fkc.parent_column_id = c.column_id
            WHERE fkc.constraint_object_id = fk.object_id
            ORDER BY fkc.constraint_column_id
            FOR XML PATH('''')
        ), 1, 1, '''') AS ParentColumns,

        -- Referenced side
        SCHEMA_NAME(rt.schema_id) AS ReferencedSchemaName,
        rt.name AS ReferencedTableName,

        -- Referenced columns (comma-separated)
        STUFF((
            SELECT '','' + c.name
            FROM ' + QUOTENAME(@DatabaseName) + '.sys.foreign_key_columns fkc
            INNER JOIN ' + QUOTENAME(@DatabaseName) + '.sys.columns c
                ON fkc.referenced_object_id = c.object_id AND fkc.referenced_column_id = c.column_id
            WHERE fkc.constraint_object_id = fk.object_id
            ORDER BY fkc.constraint_column_id
            FOR XML PATH('''')
        ), 1, 1, '''') AS ReferencedColumns,

        -- Rules
        fk.delete_referential_action_desc AS DeleteRule,
        fk.update_referential_action_desc AS UpdateRule,

        -- Status
        fk.is_disabled AS IsDisabled,
        fk.is_not_trusted AS IsNotTrusted,

        -- Refresh timestamp
        GETUTCDATE() AS LastRefreshTime

    FROM ' + QUOTENAME(@DatabaseName) + '.sys.foreign_keys fk
    INNER JOIN ' + QUOTENAME(@DatabaseName) + '.sys.tables pt
        ON fk.parent_object_id = pt.object_id
    INNER JOIN ' + QUOTENAME(@DatabaseName) + '.sys.tables rt
        ON fk.referenced_object_id = rt.object_id

    WHERE pt.is_ms_shipped = 0;  -- Exclude system tables
    ';

    -- Execute dynamic SQL
    BEGIN TRY
        EXEC sp_executesql @SQL,
            N'@ServerID INT, @DatabaseName NVARCHAR(128)',
            @ServerID = @ServerID,
            @DatabaseName = @DatabaseName;

        DECLARE @RowCount INT = @@ROWCOUNT;
        PRINT CONCAT('    Collected ', @RowCount, ' foreign keys');
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        PRINT CONCAT('    ERROR: ', @ErrorMessage);
        THROW;
    END CATCH;
END;
GO

PRINT 'Created procedure: dbo.usp_CollectForeignKeyMetadata';
GO

-- =============================================
-- Update usp_RefreshMetadataCache to call all collectors
-- =============================================

PRINT 'Updating usp_RefreshMetadataCache to integrate all metadata collectors...';
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

        -- Collect fresh metadata
        BEGIN TRY
            EXEC dbo.usp_CollectTableMetadata @ServerID = @CurServerID, @DatabaseName = @CurDatabaseName;
            EXEC dbo.usp_CollectColumnMetadata @ServerID = @CurServerID, @DatabaseName = @CurDatabaseName;
            EXEC dbo.usp_CollectIndexMetadata @ServerID = @CurServerID, @DatabaseName = @CurDatabaseName;
            EXEC dbo.usp_CollectPartitionMetadata @ServerID = @CurServerID, @DatabaseName = @CurDatabaseName;
            EXEC dbo.usp_CollectForeignKeyMetadata @ServerID = @CurServerID, @DatabaseName = @CurDatabaseName;

            -- Update cache status with counts
            UPDATE dbo.DatabaseMetadataCache
            SET LastRefreshTime = GETUTCDATE(),
                IsCurrent = 1,
                TableCount = (SELECT COUNT(*) FROM dbo.TableMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName),
                ViewCount = 0,  -- Will be populated when code object collectors are added
                ProcedureCount = 0,
                FunctionCount = 0
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
        (SELECT COUNT(*) FROM dbo.IndexMetadata) AS TotalIndexesCached,
        (SELECT COUNT(*) FROM dbo.ForeignKeyMetadata) AS TotalForeignKeysCached;
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
PRINT 'Testing Day 3 Metadata Collectors';
PRINT '========================================';
PRINT '';

DECLARE @TestServerID INT = 1;

-- Test 1: Collect index metadata
PRINT 'Test 1: Collect index metadata for MonitoringDB';
EXEC dbo.usp_CollectIndexMetadata @ServerID = @TestServerID, @DatabaseName = 'MonitoringDB';

DECLARE @IndexCount INT;
SELECT @IndexCount = COUNT(*) FROM dbo.IndexMetadata WHERE ServerID = @TestServerID AND DatabaseName = 'MonitoringDB';

PRINT '';
IF @IndexCount > 0
    PRINT CONCAT('✓ SUCCESS: Collected ', @IndexCount, ' indexes from MonitoringDB');
ELSE
    PRINT '✗ FAILED: No indexes collected';

-- Show sample index metadata
PRINT '';
PRINT 'Sample index metadata (top 5 by fragmentation):';
SELECT TOP 5
    TableName,
    IndexName,
    IndexType,
    KeyColumns,
    [RowCount],
    SizeMB,
    FragmentationPercent
FROM dbo.IndexMetadata
WHERE ServerID = @TestServerID AND DatabaseName = 'MonitoringDB'
ORDER BY FragmentationPercent DESC;

-- Test 2: Collect partition metadata
PRINT '';
PRINT 'Test 2: Collect partition metadata for MonitoringDB';
EXEC dbo.usp_CollectPartitionMetadata @ServerID = @TestServerID, @DatabaseName = 'MonitoringDB';

DECLARE @PartitionCount INT;
SELECT @PartitionCount = COUNT(*) FROM dbo.PartitionMetadata WHERE ServerID = @TestServerID AND DatabaseName = 'MonitoringDB';

PRINT '';
PRINT CONCAT('Partitions collected: ', @PartitionCount, ' (0 expected for non-partitioned tables)');

-- Test 3: Collect foreign key metadata
PRINT '';
PRINT 'Test 3: Collect foreign key metadata for MonitoringDB';
EXEC dbo.usp_CollectForeignKeyMetadata @ServerID = @TestServerID, @DatabaseName = 'MonitoringDB';

DECLARE @FKCount INT;
SELECT @FKCount = COUNT(*) FROM dbo.ForeignKeyMetadata WHERE ServerID = @TestServerID AND DatabaseName = 'MonitoringDB';

PRINT '';
IF @FKCount > 0
    PRINT CONCAT('✓ SUCCESS: Collected ', @FKCount, ' foreign keys from MonitoringDB');
ELSE
    PRINT '✗ FAILED: No foreign keys collected';

-- Show sample FK metadata
PRINT '';
PRINT 'Sample foreign key metadata:';
SELECT TOP 5
    ForeignKeyName,
    ParentTableName,
    ParentColumns,
    ReferencedTableName,
    ReferencedColumns,
    DeleteRule
FROM dbo.ForeignKeyMetadata
WHERE ServerID = @TestServerID AND DatabaseName = 'MonitoringDB';

-- Test 4: Full refresh workflow
PRINT '';
PRINT 'Test 4: Full refresh workflow (all collectors)';
UPDATE dbo.DatabaseMetadataCache SET IsCurrent = 0 WHERE ServerID = @TestServerID AND DatabaseName = 'MonitoringDB';
EXEC dbo.usp_RefreshMetadataCache @ServerID = @TestServerID, @DatabaseName = 'MonitoringDB';

PRINT '';
PRINT '========================================';
PRINT 'Day 3 Metadata Collection Summary';
PRINT '========================================';
PRINT 'Procedures created:';
PRINT '  1. usp_CollectIndexMetadata - Collect index details + fragmentation';
PRINT '  2. usp_CollectPartitionMetadata - Collect partition statistics';
PRINT '  3. usp_CollectForeignKeyMetadata - Collect FK relationships';
PRINT '  4. usp_RefreshMetadataCache - Updated with all 5 collectors';
PRINT '';
PRINT 'Test results shown above.';
PRINT '';
PRINT 'Next steps (Day 4):';
PRINT '  1. Create usp_CollectCodeObjectMetadata (SPs, views, functions)';
PRINT '  2. Create usp_CollectDependencyMetadata';
PRINT '  3. Create Grafana dashboards for schema browsing';
PRINT '========================================';
GO
