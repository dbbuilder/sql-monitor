-- =============================================
-- Phase 1.25 Day 2: Metadata Collection Procedures
-- Part 1: TableMetadata and ColumnMetadata collectors
-- Created: 2025-10-26
-- =============================================

USE [MonitoringDB];
GO

SET QUOTED_IDENTIFIER ON;
GO

PRINT 'Creating Phase 1.25 metadata collection procedures...';
PRINT '';
GO

-- =============================================
-- Procedure 1: usp_CollectTableMetadata
-- Purpose: Collect table metadata from a specific database
-- Called by: usp_RefreshMetadataCache
-- =============================================

IF OBJECT_ID('dbo.usp_CollectTableMetadata', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectTableMetadata;
GO

CREATE PROCEDURE dbo.usp_CollectTableMetadata
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

    PRINT CONCAT('  Collecting table metadata for: ', @ServerName, '.', @DatabaseName);

    -- Build dynamic SQL to query the target database
    DECLARE @SQL NVARCHAR(MAX) = N'
    INSERT INTO dbo.TableMetadata (
        ServerID, DatabaseName, SchemaName, TableName, ObjectID,
        [RowCount], TotalSizeMB, DataSizeMB, IndexSizeMB,
        ColumnCount, IndexCount, PartitionCount,
        IsPartitioned, CompressionType, CreatedDate, ModifiedDate, LastRefreshTime
    )
    SELECT
        @ServerID,
        @DatabaseName,
        SCHEMA_NAME(t.schema_id) AS SchemaName,
        t.name AS TableName,
        t.object_id AS ObjectID,

        -- Row count (sum across all partitions)
        SUM(p.rows) AS [RowCount],

        -- Total size (data + indexes) in MB
        CAST(SUM(a.total_pages) * 8 / 1024.0 AS DECIMAL(18,2)) AS TotalSizeMB,

        -- Data size in MB (used pages)
        CAST(SUM(a.used_pages) * 8 / 1024.0 AS DECIMAL(18,2)) AS DataSizeMB,

        -- Index size in MB (total - used)
        CAST((SUM(a.total_pages) - SUM(a.used_pages)) * 8 / 1024.0 AS DECIMAL(18,2)) AS IndexSizeMB,

        -- Column count
        (SELECT COUNT(*) FROM ' + QUOTENAME(@DatabaseName) + '.sys.columns c WHERE c.object_id = t.object_id) AS ColumnCount,

        -- Index count (excluding heap, index_id = 0)
        (SELECT COUNT(*) FROM ' + QUOTENAME(@DatabaseName) + '.sys.indexes i WHERE i.object_id = t.object_id AND i.index_id > 0) AS IndexCount,

        -- Partition count
        COUNT(DISTINCT p.partition_number) AS PartitionCount,

        -- Is partitioned (more than 1 partition)
        CASE WHEN COUNT(DISTINCT p.partition_number) > 1 THEN 1 ELSE 0 END AS IsPartitioned,

        -- Compression type (from partitions, may vary per partition)
        MAX(p.data_compression_desc) AS CompressionType,

        -- Created and modified dates
        t.create_date AS CreatedDate,
        t.modify_date AS ModifiedDate,

        -- Refresh timestamp
        GETUTCDATE() AS LastRefreshTime

    FROM ' + QUOTENAME(@DatabaseName) + '.sys.tables t
    INNER JOIN ' + QUOTENAME(@DatabaseName) + '.sys.partitions p
        ON t.object_id = p.object_id AND p.index_id IN (0, 1) -- Heap or clustered index only
    INNER JOIN ' + QUOTENAME(@DatabaseName) + '.sys.allocation_units a
        ON p.partition_id = a.container_id
    WHERE t.is_ms_shipped = 0 -- Exclude system tables
    GROUP BY t.schema_id, t.name, t.object_id, t.create_date, t.modify_date;
    ';

    -- Execute dynamic SQL
    BEGIN TRY
        EXEC sp_executesql @SQL,
            N'@ServerID INT, @DatabaseName NVARCHAR(128)',
            @ServerID = @ServerID,
            @DatabaseName = @DatabaseName;

        DECLARE @RowCount INT = @@ROWCOUNT;
        PRINT CONCAT('    Collected ', @RowCount, ' tables');
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        PRINT CONCAT('    ERROR: ', @ErrorMessage);
        THROW;
    END CATCH;
END;
GO

PRINT 'Created procedure: dbo.usp_CollectTableMetadata';
GO

-- =============================================
-- Procedure 2: usp_CollectColumnMetadata
-- Purpose: Collect column metadata from a specific database
-- Called by: usp_RefreshMetadataCache
-- =============================================

IF OBJECT_ID('dbo.usp_CollectColumnMetadata', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectColumnMetadata;
GO

CREATE PROCEDURE dbo.usp_CollectColumnMetadata
    @ServerID INT,
    @DatabaseName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = NULL, -- NULL = all schemas
    @TableName NVARCHAR(128) = NULL   -- NULL = all tables
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

    PRINT CONCAT('  Collecting column metadata for: ', @ServerName, '.', @DatabaseName);

    -- Build dynamic SQL to query the target database
    DECLARE @SQL NVARCHAR(MAX) = N'
    INSERT INTO dbo.ColumnMetadata (
        ServerID, DatabaseName, SchemaName, TableName, ColumnName,
        DataType, MaxLength, Precision, Scale, IsNullable, IsIdentity, IsComputed,
        IsPrimaryKey, IsForeignKey, DefaultConstraint, OrdinalPosition, LastRefreshTime
    )
    SELECT
        @ServerID,
        @DatabaseName,
        SCHEMA_NAME(t.schema_id) AS SchemaName,
        t.name AS TableName,
        c.name AS ColumnName,

        -- Data type
        TYPE_NAME(c.user_type_id) AS DataType,

        -- Max length (in bytes)
        c.max_length AS MaxLength,

        -- Precision and scale (for numeric types)
        c.precision AS Precision,
        c.scale AS Scale,

        -- Nullability, identity, computed
        c.is_nullable AS IsNullable,
        c.is_identity AS IsIdentity,
        c.is_computed AS IsComputed,

        -- Is primary key column?
        CASE WHEN pk.column_id IS NOT NULL THEN 1 ELSE 0 END AS IsPrimaryKey,

        -- Is foreign key column?
        CASE WHEN fk.parent_column_id IS NOT NULL THEN 1 ELSE 0 END AS IsForeignKey,

        -- Default constraint definition
        dc.definition AS DefaultConstraint,

        -- Ordinal position in table
        c.column_id AS OrdinalPosition,

        -- Refresh timestamp
        GETUTCDATE() AS LastRefreshTime

    FROM ' + QUOTENAME(@DatabaseName) + '.sys.tables t
    INNER JOIN ' + QUOTENAME(@DatabaseName) + '.sys.columns c
        ON t.object_id = c.object_id

    -- Primary key columns
    LEFT JOIN (
        SELECT ic.object_id, ic.column_id
        FROM ' + QUOTENAME(@DatabaseName) + '.sys.indexes i
        INNER JOIN ' + QUOTENAME(@DatabaseName) + '.sys.index_columns ic
            ON i.object_id = ic.object_id AND i.index_id = ic.index_id
        WHERE i.is_primary_key = 1
    ) pk ON c.object_id = pk.object_id AND c.column_id = pk.column_id

    -- Foreign key columns
    LEFT JOIN ' + QUOTENAME(@DatabaseName) + '.sys.foreign_key_columns fk
        ON c.object_id = fk.parent_object_id AND c.column_id = fk.parent_column_id

    -- Default constraints
    LEFT JOIN ' + QUOTENAME(@DatabaseName) + '.sys.default_constraints dc
        ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id

    WHERE t.is_ms_shipped = 0 -- Exclude system tables
      AND (@SchemaName IS NULL OR SCHEMA_NAME(t.schema_id) = @SchemaName)
      AND (@TableName IS NULL OR t.name = @TableName)
    ORDER BY t.schema_id, t.name, c.column_id;
    ';

    -- Execute dynamic SQL
    BEGIN TRY
        EXEC sp_executesql @SQL,
            N'@ServerID INT, @DatabaseName NVARCHAR(128), @SchemaName NVARCHAR(128), @TableName NVARCHAR(128)',
            @ServerID = @ServerID,
            @DatabaseName = @DatabaseName,
            @SchemaName = @SchemaName,
            @TableName = @TableName;

        DECLARE @RowCount INT = @@ROWCOUNT;
        PRINT CONCAT('    Collected ', @RowCount, ' columns');
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        PRINT CONCAT('    ERROR: ', @ErrorMessage);
        THROW;
    END CATCH;
END;
GO

PRINT 'Created procedure: dbo.usp_CollectColumnMetadata';
GO

-- =============================================
-- Update usp_RefreshMetadataCache to call collectors
-- =============================================

PRINT 'Updating usp_RefreshMetadataCache to integrate metadata collectors...';
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
        -- Note: IndexMetadata, PartitionMetadata, etc. will be added in later days

        -- Collect fresh metadata
        BEGIN TRY
            EXEC dbo.usp_CollectTableMetadata @ServerID = @CurServerID, @DatabaseName = @CurDatabaseName;
            EXEC dbo.usp_CollectColumnMetadata @ServerID = @CurServerID, @DatabaseName = @CurDatabaseName;

            -- Update cache status
            UPDATE dbo.DatabaseMetadataCache
            SET LastRefreshTime = GETUTCDATE(),
                IsCurrent = 1,
                TableCount = (SELECT COUNT(*) FROM dbo.TableMetadata WHERE ServerID = @CurServerID AND DatabaseName = @CurDatabaseName)
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
        (SELECT SUM(TableCount) FROM dbo.DatabaseMetadataCache WHERE IsCurrent = 1) AS TotalTablesCached;
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
PRINT 'Testing Metadata Collection';
PRINT '========================================';
PRINT '';

-- Test: Collect metadata for MonitoringDB
DECLARE @TestServerID INT = 1;

-- Register MonitoringDB for tracking
IF NOT EXISTS (SELECT 1 FROM dbo.DatabaseMetadataCache WHERE ServerID = @TestServerID AND DatabaseName = 'MonitoringDB')
BEGIN
    INSERT INTO dbo.DatabaseMetadataCache (ServerID, DatabaseName, LastRefreshTime, IsCurrent)
    VALUES (@TestServerID, 'MonitoringDB', GETUTCDATE(), 0);
    PRINT 'Registered MonitoringDB for metadata tracking';
END;

-- Collect table metadata
PRINT '';
PRINT 'Test 1: Collect table metadata for MonitoringDB';
EXEC dbo.usp_CollectTableMetadata @ServerID = @TestServerID, @DatabaseName = 'MonitoringDB';

-- Verify table metadata collected
DECLARE @TableCount INT;
SELECT @TableCount = COUNT(*) FROM dbo.TableMetadata WHERE ServerID = @TestServerID AND DatabaseName = 'MonitoringDB';

PRINT '';
IF @TableCount > 0
    PRINT CONCAT('✓ SUCCESS: Collected ', @TableCount, ' tables from MonitoringDB');
ELSE
    PRINT '✗ FAILED: No tables collected';

-- Show sample table metadata
PRINT '';
PRINT 'Sample table metadata (top 5 by size):';
SELECT TOP 5
    SchemaName,
    TableName,
    [RowCount],
    TotalSizeMB,
    ColumnCount,
    IndexCount,
    IsPartitioned
FROM dbo.TableMetadata
WHERE ServerID = @TestServerID AND DatabaseName = 'MonitoringDB'
ORDER BY TotalSizeMB DESC;

-- Collect column metadata
PRINT '';
PRINT 'Test 2: Collect column metadata for MonitoringDB';
EXEC dbo.usp_CollectColumnMetadata @ServerID = @TestServerID, @DatabaseName = 'MonitoringDB';

-- Verify column metadata collected
DECLARE @ColumnCount INT;
SELECT @ColumnCount = COUNT(*) FROM dbo.ColumnMetadata WHERE ServerID = @TestServerID AND DatabaseName = 'MonitoringDB';

PRINT '';
IF @ColumnCount > 0
    PRINT CONCAT('✓ SUCCESS: Collected ', @ColumnCount, ' columns from MonitoringDB');
ELSE
    PRINT '✗ FAILED: No columns collected';

-- Show sample column metadata
PRINT '';
PRINT 'Sample column metadata (Servers table):';
SELECT TOP 10
    TableName,
    ColumnName,
    DataType,
    MaxLength,
    IsNullable,
    IsPrimaryKey,
    IsForeignKey
FROM dbo.ColumnMetadata
WHERE ServerID = @TestServerID
  AND DatabaseName = 'MonitoringDB'
  AND TableName = 'Servers'
ORDER BY OrdinalPosition;

-- Test full refresh workflow
PRINT '';
PRINT 'Test 3: Full refresh workflow (usp_RefreshMetadataCache)';
UPDATE dbo.DatabaseMetadataCache SET IsCurrent = 0 WHERE ServerID = @TestServerID AND DatabaseName = 'MonitoringDB';
EXEC dbo.usp_RefreshMetadataCache @ServerID = @TestServerID, @DatabaseName = 'MonitoringDB';

PRINT '';
PRINT '========================================';
PRINT 'Day 2 Metadata Collection Summary';
PRINT '========================================';
PRINT 'Procedures created:';
PRINT '  1. usp_CollectTableMetadata - Collect table metadata';
PRINT '  2. usp_CollectColumnMetadata - Collect column metadata';
PRINT '  3. usp_RefreshMetadataCache - Updated with metadata collectors';
PRINT '';
PRINT 'Test results shown above.';
PRINT '';
PRINT 'Next steps (Day 3):';
PRINT '  1. Create usp_CollectIndexMetadata';
PRINT '  2. Create usp_CollectPartitionMetadata';
PRINT '  3. Create usp_CollectForeignKeyMetadata';
PRINT '========================================';
GO
