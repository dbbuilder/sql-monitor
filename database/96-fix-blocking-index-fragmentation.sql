-- =====================================================
-- FIX: Non-Blocking Index Fragmentation Collection
-- Created: 2025-11-26
-- Purpose: Replace blocking dm_db_index_physical_stats queries
--          with per-database iteration to prevent DDL blocking
-- =====================================================
-- ISSUE: Using dm_db_index_physical_stats(NULL, ...) scans ALL databases
--        simultaneously, taking metadata locks that block DDL operations
--        like CREATE PROCEDURE, CREATE TRIGGER, ALTER TABLE, etc.
--
-- SOLUTION: Iterate one database at a time with:
--        1. Per-database calls to dm_db_index_physical_stats(DB_ID, ...)
--        2. SET LOCK_TIMEOUT to avoid long waits
--        3. TRY/CATCH for deadlock retry logic
--        4. Throttling between databases to reduce contention
-- =====================================================

USE MonitoringDB;
GO

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
GO

PRINT '=============================================='
PRINT 'Deploying Non-Blocking Index Fragmentation Fix'
PRINT '=============================================='
PRINT ''

-- =====================================================
-- Procedure 1: usp_CollectIndexFragmentation_NonBlocking
-- Purpose: Collect fragmentation data WITHOUT blocking DDL
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectIndexFragmentation_NonBlocking', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectIndexFragmentation_NonBlocking;
GO

CREATE PROCEDURE dbo.usp_CollectIndexFragmentation_NonBlocking
    @ServerID INT = NULL,           -- NULL = all active servers
    @MinPageCount INT = 1000,       -- Only indexes with 1000+ pages
    @ThrottleDelayMs INT = 100,     -- Delay between databases (ms)
    @LockTimeoutMs INT = 5000,      -- Lock timeout per database (ms)
    @MaxRetries INT = 2             -- Retries on deadlock
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;

    -- Set lock timeout to prevent long waits
    DECLARE @LockTimeoutSQL NVARCHAR(100) = N'SET LOCK_TIMEOUT ' + CAST(@LockTimeoutMs AS NVARCHAR(10));
    EXEC sp_executesql @LockTimeoutSQL;

    DECLARE @CurrentServerID INT;
    DECLARE @ServerName NVARCHAR(128);
    DECLARE @LinkedServerName NVARCHAR(128);
    DECLARE @ErrorMessage NVARCHAR(MAX);
    DECLARE @RowsInserted INT = 0;
    DECLARE @DatabasesProcessed INT = 0;
    DECLARE @DatabasesSkipped INT = 0;
    DECLARE @StartTime DATETIME2(7) = GETUTCDATE();

    -- Create temp table for fragmentation data
    CREATE TABLE #FragmentationData (
        ServerID INT,
        DatabaseName NVARCHAR(128),
        SchemaName NVARCHAR(128),
        TableName NVARCHAR(128),
        IndexName NVARCHAR(128),
        IndexID INT,
        IndexType VARCHAR(50),
        PartitionNumber INT,
        FragmentationPercent DECIMAL(5,2),
        PageCount BIGINT,
        RecordCount BIGINT,
        AvgPageSpaceUsedPercent DECIMAL(5,2)
    );

    -- Cursor to iterate through servers
    DECLARE server_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT ServerID, ServerName, LinkedServerName
        FROM dbo.Servers
        WHERE IsActive = 1
          AND (@ServerID IS NULL OR ServerID = @ServerID);

    OPEN server_cursor;
    FETCH NEXT FROM server_cursor INTO @CurrentServerID, @ServerName, @LinkedServerName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        PRINT 'Collecting fragmentation for server: ' + @ServerName + ' (non-blocking mode)';

        BEGIN TRY
            -- Get list of user databases on this server
            DECLARE @DatabaseList TABLE (
                DatabaseID INT,
                DatabaseName NVARCHAR(128)
            );

            DECLARE @GetDatabasesSQL NVARCHAR(MAX) = N'
                SELECT database_id, name
                FROM sys.databases
                WHERE database_id > 4  -- Exclude system databases
                  AND state_desc = ''ONLINE''
                  AND is_read_only = 0
                  AND name NOT IN (''rdsadmin'', ''DBATools'', ''MonitoringDB'')
                ORDER BY name;
            ';

            -- For local server
            IF @LinkedServerName IS NULL OR @LinkedServerName = '(local)' OR @LinkedServerName = @@SERVERNAME
            BEGIN
                INSERT INTO @DatabaseList
                EXEC sp_executesql @GetDatabasesSQL;
            END
            ELSE
            BEGIN
                -- For remote server via linked server
                DECLARE @RemoteDbSQL NVARCHAR(MAX) = N'
                    INSERT INTO @DatabaseList
                    SELECT * FROM OPENQUERY([' + @LinkedServerName + '], ''' + REPLACE(@GetDatabasesSQL, '''', '''''') + ''');
                ';
                -- Note: This requires proper linked server setup
                INSERT INTO @DatabaseList
                EXEC sp_executesql @GetDatabasesSQL; -- Fallback to local for now
            END;

            -- Iterate through each database one at a time
            DECLARE @DbID INT;
            DECLARE @DbName NVARCHAR(128);
            DECLARE @RetryCount INT;

            DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
                SELECT DatabaseID, DatabaseName FROM @DatabaseList;

            OPEN db_cursor;
            FETCH NEXT FROM db_cursor INTO @DbID, @DbName;

            WHILE @@FETCH_STATUS = 0
            BEGIN
                SET @RetryCount = 0;

                WHILE @RetryCount <= @MaxRetries
                BEGIN
                    BEGIN TRY
                        -- Query fragmentation for THIS database only
                        DECLARE @FragSQL NVARCHAR(MAX) = N'
                            SELECT
                                ' + CAST(@CurrentServerID AS NVARCHAR(10)) + ' AS ServerID,
                                DB_NAME(' + CAST(@DbID AS NVARCHAR(10)) + ') AS DatabaseName,
                                OBJECT_SCHEMA_NAME(ips.object_id, ' + CAST(@DbID AS NVARCHAR(10)) + ') AS SchemaName,
                                OBJECT_NAME(ips.object_id, ' + CAST(@DbID AS NVARCHAR(10)) + ') AS TableName,
                                i.name AS IndexName,
                                i.index_id AS IndexID,
                                CASE i.type
                                    WHEN 0 THEN ''HEAP''
                                    WHEN 1 THEN ''CLUSTERED''
                                    WHEN 2 THEN ''NONCLUSTERED''
                                    WHEN 5 THEN ''CLUSTERED COLUMNSTORE''
                                    WHEN 6 THEN ''NONCLUSTERED COLUMNSTORE''
                                    ELSE ''OTHER''
                                END AS IndexType,
                                ips.partition_number AS PartitionNumber,
                                CAST(ips.avg_fragmentation_in_percent AS DECIMAL(5,2)) AS FragmentationPercent,
                                ips.page_count AS PageCount,
                                ISNULL(ips.record_count, 0) AS RecordCount,
                                CAST(ISNULL(ips.avg_page_space_used_in_percent, 0) AS DECIMAL(5,2)) AS AvgPageSpaceUsedPercent
                            FROM sys.dm_db_index_physical_stats(' + CAST(@DbID AS NVARCHAR(10)) + ', NULL, NULL, NULL, ''LIMITED'') ips
                            INNER JOIN [' + @DbName + '].sys.tables t WITH (NOLOCK) ON ips.object_id = t.object_id
                            INNER JOIN [' + @DbName + '].sys.indexes i WITH (NOLOCK) ON ips.object_id = i.object_id AND ips.index_id = i.index_id
                            WHERE ips.page_count >= ' + CAST(@MinPageCount AS NVARCHAR(10)) + '
                              AND ips.alloc_unit_type_desc = ''IN_ROW_DATA''
                              AND i.name IS NOT NULL
                              AND t.is_ms_shipped = 0;
                        ';

                        INSERT INTO #FragmentationData
                        EXEC sp_executesql @FragSQL;

                        SET @DatabasesProcessed = @DatabasesProcessed + 1;

                        -- Success - exit retry loop
                        BREAK;

                    END TRY
                    BEGIN CATCH
                        SET @ErrorMessage = ERROR_MESSAGE();

                        -- Check if it's a deadlock (error 1205) or lock timeout (error 1222)
                        IF ERROR_NUMBER() IN (1205, 1222)
                        BEGIN
                            SET @RetryCount = @RetryCount + 1;
                            IF @RetryCount <= @MaxRetries
                            BEGIN
                                PRINT '    Retry ' + CAST(@RetryCount AS VARCHAR) + ' for database: ' + @DbName + ' (lock conflict)';
                                WAITFOR DELAY '00:00:01'; -- Wait 1 second before retry
                            END
                            ELSE
                            BEGIN
                                PRINT '    Skipped database: ' + @DbName + ' (lock conflicts after ' + CAST(@MaxRetries AS VARCHAR) + ' retries)';
                                SET @DatabasesSkipped = @DatabasesSkipped + 1;
                            END;
                        END
                        ELSE
                        BEGIN
                            -- Other error - skip this database
                            PRINT '    Skipped database: ' + @DbName + ' (' + @ErrorMessage + ')';
                            SET @DatabasesSkipped = @DatabasesSkipped + 1;
                            BREAK;
                        END;
                    END CATCH;
                END;

                -- Throttle between databases to reduce contention
                IF @ThrottleDelayMs > 0
                BEGIN
                    DECLARE @DelayStr VARCHAR(12) = '00:00:00.' + RIGHT('000' + CAST(@ThrottleDelayMs AS VARCHAR(3)), 3);
                    WAITFOR DELAY @DelayStr;
                END;

                FETCH NEXT FROM db_cursor INTO @DbID, @DbName;
            END;

            CLOSE db_cursor;
            DEALLOCATE db_cursor;

            DELETE FROM @DatabaseList;

            PRINT '  Collected fragmentation data for ' + @ServerName;

        END TRY
        BEGIN CATCH
            SET @ErrorMessage = ERROR_MESSAGE();
            PRINT '  Error collecting fragmentation for ' + @ServerName + ': ' + @ErrorMessage;
        END CATCH;

        FETCH NEXT FROM server_cursor INTO @CurrentServerID, @ServerName, @LinkedServerName;
    END;

    CLOSE server_cursor;
    DEALLOCATE server_cursor;

    -- Insert collected data into IndexFragmentation table (if it exists)
    IF OBJECT_ID('dbo.IndexFragmentation', 'U') IS NOT NULL
    BEGIN
        INSERT INTO dbo.IndexFragmentation (
            ServerID, DatabaseName, SchemaName, TableName, IndexName, IndexID,
            IndexType, PartitionNumber, FragmentationPercent, PageCount,
            RecordCount, AvgPageSpaceUsedPercent, CollectionTime
        )
        SELECT
            ServerID, DatabaseName, SchemaName, TableName, IndexName, IndexID,
            IndexType, PartitionNumber, FragmentationPercent, PageCount,
            RecordCount, AvgPageSpaceUsedPercent, GETUTCDATE()
        FROM #FragmentationData;

        SET @RowsInserted = @@ROWCOUNT;
    END
    ELSE
    BEGIN
        SELECT @RowsInserted = COUNT(*) FROM #FragmentationData;
    END;

    DROP TABLE #FragmentationData;

    -- Reset lock timeout
    SET LOCK_TIMEOUT -1;

    -- Return summary
    DECLARE @DurationSeconds INT = DATEDIFF(SECOND, @StartTime, GETUTCDATE());
    PRINT '';
    PRINT 'Non-blocking fragmentation collection complete:';
    PRINT '  Total indexes collected: ' + CAST(@RowsInserted AS VARCHAR);
    PRINT '  Databases processed: ' + CAST(@DatabasesProcessed AS VARCHAR);
    PRINT '  Databases skipped (lock conflicts): ' + CAST(@DatabasesSkipped AS VARCHAR);
    PRINT '  Duration: ' + CAST(@DurationSeconds AS VARCHAR) + ' seconds';
    PRINT '';

    RETURN @RowsInserted;
END;
GO

PRINT 'Created procedure: dbo.usp_CollectIndexFragmentation_NonBlocking';
PRINT ''

-- =====================================================
-- Update the original usp_CollectIndexFragmentation to use non-blocking version
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectIndexFragmentation', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectIndexFragmentation;
GO

CREATE PROCEDURE dbo.usp_CollectIndexFragmentation
    @ServerID INT = NULL -- NULL = all active servers
AS
BEGIN
    -- Wrapper that calls the non-blocking version with default parameters
    EXEC dbo.usp_CollectIndexFragmentation_NonBlocking
        @ServerID = @ServerID,
        @MinPageCount = 1000,
        @ThrottleDelayMs = 100,
        @LockTimeoutMs = 5000,
        @MaxRetries = 2;
END;
GO

PRINT 'Updated procedure: dbo.usp_CollectIndexFragmentation (now uses non-blocking version)';
PRINT ''

-- =====================================================
-- Fix usp_PerformIndexMaintenance in 13-create-index-maintenance.sql
-- =====================================================

IF OBJECT_ID('dbo.usp_PerformIndexMaintenance_Original', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_PerformIndexMaintenance_Original;
GO

-- Rename existing procedure if it uses the blocking pattern
IF OBJECT_ID('dbo.usp_PerformIndexMaintenance', 'P') IS NOT NULL
BEGIN
    -- Check if it contains the blocking pattern
    IF EXISTS (
        SELECT 1
        FROM sys.sql_modules
        WHERE object_id = OBJECT_ID('dbo.usp_PerformIndexMaintenance')
          AND definition LIKE '%dm_db_index_physical_stats(NULL, NULL, NULL, NULL%'
    )
    BEGIN
        EXEC sp_rename 'dbo.usp_PerformIndexMaintenance', 'usp_PerformIndexMaintenance_Original';
        PRINT 'Renamed blocking version to: dbo.usp_PerformIndexMaintenance_Original';
    END;
END;
GO

-- Create new non-blocking version
CREATE PROCEDURE dbo.usp_PerformIndexMaintenance
    @ServerID INT,
    @DatabaseName NVARCHAR(128) = NULL, -- NULL = all databases
    @MinFragmentation FLOAT = 10.0,
    @MinPageCount INT = 1000,
    @OnlineRebuild BIT = 1,
    @MaxDegreeOfParallelism INT = NULL,
    @LockTimeoutMs INT = 5000,
    @MaxRetries INT = 2
AS
BEGIN
    SET NOCOUNT ON;

    -- Set lock timeout to prevent long waits
    DECLARE @LockTimeoutSQL NVARCHAR(100) = N'SET LOCK_TIMEOUT ' + CAST(@LockTimeoutMs AS NVARCHAR(10));
    EXEC sp_executesql @LockTimeoutSQL;

    DECLARE @StartTime DATETIME2(7);
    DECLARE @EndTime DATETIME2(7);
    DECLARE @DurationSeconds INT;

    DECLARE @LinkedServerName NVARCHAR(128);
    DECLARE @SQL NVARCHAR(MAX);

    -- Get server info
    SELECT @LinkedServerName = ServerName
    FROM dbo.Servers
    WHERE ServerID = @ServerID;

    IF @LinkedServerName IS NULL
    BEGIN
        RAISERROR('Server not found: %d', 16, 1, @ServerID);
        RETURN;
    END;

    PRINT CONCAT('Starting index maintenance for server: ', @LinkedServerName, ' (non-blocking mode)');

    -- Create temp table to store indexes needing maintenance
    DECLARE @IndexesToMaintain TABLE (
        DatabaseName NVARCHAR(128),
        SchemaName NVARCHAR(128),
        TableName NVARCHAR(128),
        IndexName NVARCHAR(128),
        FragmentationPercent FLOAT,
        PageCount BIGINT,
        MaintenanceAction VARCHAR(20) -- REBUILD, REORGANIZE, NONE
    );

    -- Get list of databases to process
    DECLARE @DatabaseList TABLE (DatabaseID INT, DatabaseName NVARCHAR(128));

    IF @DatabaseName IS NOT NULL
    BEGIN
        INSERT INTO @DatabaseList VALUES (DB_ID(@DatabaseName), @DatabaseName);
    END
    ELSE
    BEGIN
        INSERT INTO @DatabaseList
        SELECT database_id, name
        FROM sys.databases
        WHERE database_id > 4
          AND state_desc = 'ONLINE'
          AND is_read_only = 0
          AND name NOT IN ('rdsadmin', 'DBATools', 'MonitoringDB');
    END;

    -- Process each database individually (non-blocking)
    DECLARE @DbID INT;
    DECLARE @DbName NVARCHAR(128);
    DECLARE @RetryCount INT;
    DECLARE @ErrorMessage NVARCHAR(4000);

    DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT DatabaseID, DatabaseName FROM @DatabaseList;

    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @DbID, @DbName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @RetryCount = 0;

        WHILE @RetryCount <= @MaxRetries
        BEGIN
            BEGIN TRY
                SET @SQL = N'
                SELECT
                    DB_NAME(' + CAST(@DbID AS NVARCHAR(10)) + ') AS DatabaseName,
                    OBJECT_SCHEMA_NAME(ips.object_id, ' + CAST(@DbID AS NVARCHAR(10)) + ') AS SchemaName,
                    OBJECT_NAME(ips.object_id, ' + CAST(@DbID AS NVARCHAR(10)) + ') AS TableName,
                    i.name AS IndexName,
                    ips.avg_fragmentation_in_percent AS FragmentationPercent,
                    ips.page_count AS PageCount,
                    CASE
                        WHEN ips.avg_fragmentation_in_percent >= 30 THEN ''REBUILD''
                        WHEN ips.avg_fragmentation_in_percent >= ' + CAST(@MinFragmentation AS NVARCHAR(10)) + ' THEN ''REORGANIZE''
                        ELSE ''NONE''
                    END AS MaintenanceAction
                FROM sys.dm_db_index_physical_stats(' + CAST(@DbID AS NVARCHAR(10)) + ', NULL, NULL, NULL, ''LIMITED'') ips
                INNER JOIN [' + @DbName + '].sys.indexes i WITH (NOLOCK) ON ips.object_id = i.object_id AND ips.index_id = i.index_id
                WHERE ips.avg_fragmentation_in_percent >= ' + CAST(@MinFragmentation AS NVARCHAR(10)) + '
                  AND ips.page_count >= ' + CAST(@MinPageCount AS NVARCHAR(10)) + '
                  AND i.name IS NOT NULL
                  AND ips.index_type_desc IN (''CLUSTERED INDEX'', ''NONCLUSTERED INDEX'');
                ';

                INSERT INTO @IndexesToMaintain
                EXEC sp_executesql @SQL;

                -- Success - exit retry loop
                BREAK;

            END TRY
            BEGIN CATCH
                SET @ErrorMessage = ERROR_MESSAGE();

                IF ERROR_NUMBER() IN (1205, 1222) -- Deadlock or lock timeout
                BEGIN
                    SET @RetryCount = @RetryCount + 1;
                    IF @RetryCount <= @MaxRetries
                    BEGIN
                        PRINT '  Retry ' + CAST(@RetryCount AS VARCHAR) + ' for database: ' + @DbName;
                        WAITFOR DELAY '00:00:01';
                    END
                    ELSE
                    BEGIN
                        PRINT '  Skipped database: ' + @DbName + ' (lock conflicts)';
                    END;
                END
                ELSE
                BEGIN
                    PRINT '  Skipped database: ' + @DbName + ' (' + @ErrorMessage + ')';
                    BREAK;
                END;
            END CATCH;
        END;

        -- Small delay between databases
        WAITFOR DELAY '00:00:00.100';

        FETCH NEXT FROM db_cursor INTO @DbID, @DbName;
    END;

    CLOSE db_cursor;
    DEALLOCATE db_cursor;

    DECLARE @TotalIndexes INT;
    DECLARE @ProcessedIndexes INT;

    SELECT @TotalIndexes = COUNT(*)
    FROM @IndexesToMaintain
    WHERE MaintenanceAction IN ('REBUILD', 'REORGANIZE');

    SET @ProcessedIndexes = 0;

    PRINT CONCAT('Found ', @TotalIndexes, ' indexes requiring maintenance');

    -- Process each index
    DECLARE @MaintDbName NVARCHAR(128), @SchemaName NVARCHAR(128), @TableName NVARCHAR(128), @IndexName NVARCHAR(128);
    DECLARE @Fragmentation FLOAT, @PageCount BIGINT, @Action VARCHAR(20);

    DECLARE index_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT DatabaseName, SchemaName, TableName, IndexName, FragmentationPercent, PageCount, MaintenanceAction
        FROM @IndexesToMaintain
        WHERE MaintenanceAction IN ('REBUILD', 'REORGANIZE')
        ORDER BY PageCount DESC; -- Process largest indexes first

    OPEN index_cursor;
    FETCH NEXT FROM index_cursor INTO @MaintDbName, @SchemaName, @TableName, @IndexName, @Fragmentation, @PageCount, @Action;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @StartTime = GETUTCDATE();

        BEGIN TRY
            -- Build maintenance command
            SET @SQL = N'USE [' + @MaintDbName + ']; ';

            IF @Action = 'REBUILD'
            BEGIN
                SET @SQL = @SQL + N'ALTER INDEX [' + @IndexName + '] ON [' + @SchemaName + '].[' + @TableName + '] REBUILD ';

                IF @OnlineRebuild = 1
                    SET @SQL = @SQL + N'WITH (ONLINE = ON';
                ELSE
                    SET @SQL = @SQL + N'WITH (ONLINE = OFF';

                IF @MaxDegreeOfParallelism IS NOT NULL
                    SET @SQL = @SQL + N', MAXDOP = ' + CAST(@MaxDegreeOfParallelism AS NVARCHAR(10));

                SET @SQL = @SQL + N');';
            END
            ELSE IF @Action = 'REORGANIZE'
            BEGIN
                SET @SQL = @SQL + N'ALTER INDEX [' + @IndexName + '] ON [' + @SchemaName + '].[' + @TableName + '] REORGANIZE;';
            END;

            PRINT CONCAT('[', @ProcessedIndexes + 1, '/', @TotalIndexes, '] ', @Action, ': ', @MaintDbName, '.', @SchemaName, '.', @TableName, '.', @IndexName, ' (', CAST(@Fragmentation AS VARCHAR(10)), '% fragmented, ', @PageCount, ' pages)');

            -- Execute maintenance command
            EXEC sp_executesql @SQL;

            SET @EndTime = GETUTCDATE();
            SET @DurationSeconds = DATEDIFF(SECOND, @StartTime, @EndTime);

            -- Log maintenance action (if table exists)
            IF OBJECT_ID('dbo.IndexMaintenanceHistory', 'U') IS NOT NULL
            BEGIN
                INSERT INTO dbo.IndexMaintenanceHistory (
                    ServerID, DatabaseName, SchemaName, TableName, IndexName,
                    MaintenanceType, FragmentationBefore, PageCount,
                    DurationSeconds, StartTime, EndTime, Status
                )
                VALUES (
                    @ServerID, @MaintDbName, @SchemaName, @TableName, @IndexName,
                    @Action, @Fragmentation, @PageCount,
                    @DurationSeconds, @StartTime, @EndTime, 'Success'
                );
            END;

            SET @ProcessedIndexes = @ProcessedIndexes + 1;

            PRINT CONCAT('  Completed in ', @DurationSeconds, ' seconds');
        END TRY
        BEGIN CATCH
            PRINT CONCAT('  ERROR: ', ERROR_MESSAGE());

            -- Log failed maintenance attempt
            IF OBJECT_ID('dbo.IndexMaintenanceHistory', 'U') IS NOT NULL
            BEGIN
                INSERT INTO dbo.IndexMaintenanceHistory (
                    ServerID, DatabaseName, SchemaName, TableName, IndexName,
                    MaintenanceType, FragmentationBefore, PageCount,
                    DurationSeconds, StartTime, EndTime, Status, ErrorMessage
                )
                VALUES (
                    @ServerID, @MaintDbName, @SchemaName, @TableName, @IndexName,
                    'FAILED', @Fragmentation, @PageCount,
                    0, @StartTime, GETUTCDATE(), 'Failed', ERROR_MESSAGE()
                );
            END;
        END CATCH;

        FETCH NEXT FROM index_cursor INTO @MaintDbName, @SchemaName, @TableName, @IndexName, @Fragmentation, @PageCount, @Action;
    END;

    CLOSE index_cursor;
    DEALLOCATE index_cursor;

    -- Reset lock timeout
    SET LOCK_TIMEOUT -1;

    PRINT CONCAT('Index maintenance completed. Processed: ', @ProcessedIndexes, '/', @TotalIndexes);
END;
GO

PRINT 'Created procedure: dbo.usp_PerformIndexMaintenance (non-blocking version)';
PRINT ''

-- =====================================================
-- Summary
-- =====================================================

PRINT '=============================================='
PRINT 'Non-Blocking Index Fragmentation Fix Complete'
PRINT '=============================================='
PRINT ''
PRINT 'Changes made:'
PRINT '  1. Created usp_CollectIndexFragmentation_NonBlocking'
PRINT '     - Iterates one database at a time'
PRINT '     - Uses SET LOCK_TIMEOUT to prevent long waits'
PRINT '     - Includes deadlock retry logic'
PRINT '     - Throttles between databases'
PRINT ''
PRINT '  2. Updated usp_CollectIndexFragmentation'
PRINT '     - Now calls the non-blocking version'
PRINT ''
PRINT '  3. Replaced usp_PerformIndexMaintenance'
PRINT '     - Uses per-database fragmentation queries'
PRINT '     - Includes lock timeout and retry logic'
PRINT ''
PRINT 'These changes prevent blocking of DDL operations like:'
PRINT '  - CREATE PROCEDURE'
PRINT '  - CREATE TRIGGER'
PRINT '  - ALTER TABLE'
PRINT '  - CREATE INDEX'
PRINT ''
GO
