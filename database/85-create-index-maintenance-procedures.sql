-- =====================================================
-- Phase 3 - Feature #6: Automated Index Maintenance
-- Stored Procedures for Index Maintenance and Statistics Management
-- =====================================================
-- File: 85-create-index-maintenance-procedures.sql
-- Purpose: Create procedures for fragmentation collection, index maintenance, and statistics updates
-- Dependencies: 84-create-index-maintenance-tables.sql
-- =====================================================

USE MonitoringDB;
GO

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
GO

PRINT '======================================'
PRINT 'Creating Index Maintenance Procedures'
PRINT '======================================'
PRINT ''

-- =====================================================
-- Procedure 1: usp_CollectIndexFragmentation
-- Purpose: Collect fragmentation data from remote SQL Server instances
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectIndexFragmentation', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectIndexFragmentation;
GO

CREATE PROCEDURE dbo.usp_CollectIndexFragmentation
    @ServerID INT = NULL -- NULL = all active servers
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;

    DECLARE @CurrentServerID INT;
    DECLARE @ServerName NVARCHAR(128);
    DECLARE @LinkedServerName NVARCHAR(128);
    DECLARE @ErrorMessage NVARCHAR(MAX);
    DECLARE @RowsInserted INT = 0;
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
        PRINT 'Collecting fragmentation for server: ' + @ServerName;

        BEGIN TRY
            -- Build dynamic SQL to query remote server
            DECLARE @SQL NVARCHAR(MAX) = N'
            SELECT
                ' + CAST(@CurrentServerID AS NVARCHAR(10)) + ' AS ServerID,
                DB_NAME(ips.database_id) AS DatabaseName,
                SCHEMA_NAME(t.schema_id) AS SchemaName,
                t.name AS TableName,
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
                ips.record_count AS RecordCount,
                CAST(ips.avg_page_space_used_in_percent AS DECIMAL(5,2)) AS AvgPageSpaceUsedPercent
            FROM sys.dm_db_index_physical_stats(NULL, NULL, NULL, NULL, ''LIMITED'') ips
            INNER JOIN sys.tables t ON ips.object_id = t.object_id
            INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
            WHERE ips.database_id > 4 -- Exclude system databases
              AND ips.page_count >= 1000 -- Only indexes with 1000+ pages (~8MB)
              AND t.is_ms_shipped = 0 -- Exclude system tables
            ORDER BY ips.database_id, t.name, i.name;
            ';

            -- For local server (monitoring server itself)
            IF @LinkedServerName IS NULL OR @LinkedServerName = '(local)' OR @LinkedServerName = @@SERVERNAME
            BEGIN
                INSERT INTO #FragmentationData
                EXEC sp_executesql @SQL;
            END
            ELSE
            BEGIN
                -- For remote server via linked server
                DECLARE @RemoteSQL NVARCHAR(MAX) = N'
                INSERT INTO #FragmentationData
                SELECT * FROM OPENQUERY([' + @LinkedServerName + '], ''' + REPLACE(@SQL, '''', '''''') + ''');
                ';
                EXEC sp_executesql @RemoteSQL;
            END;

            PRINT '  ✓ Collected fragmentation data for ' + @ServerName;

        END TRY
        BEGIN CATCH
            SET @ErrorMessage = ERROR_MESSAGE();
            PRINT '  ✗ Error collecting fragmentation for ' + @ServerName + ': ' + @ErrorMessage;
        END CATCH;

        FETCH NEXT FROM server_cursor INTO @CurrentServerID, @ServerName, @LinkedServerName;
    END;

    CLOSE server_cursor;
    DEALLOCATE server_cursor;

    -- Insert collected data into IndexFragmentation table
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

    DROP TABLE #FragmentationData;

    -- Return summary
    DECLARE @DurationSeconds INT = DATEDIFF(SECOND, @StartTime, GETUTCDATE());
    PRINT '';
    PRINT 'Fragmentation collection complete:';
    PRINT '  Total indexes collected: ' + CAST(@RowsInserted AS VARCHAR);
    PRINT '  Duration: ' + CAST(@DurationSeconds AS VARCHAR) + ' seconds';
    PRINT '';

    RETURN @RowsInserted;
END;
GO

PRINT 'Created procedure: dbo.usp_CollectIndexFragmentation';
PRINT ''

-- =====================================================
-- Procedure 2: usp_CollectStatisticsInfo
-- Purpose: Collect statistics freshness from remote SQL Server instances
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectStatisticsInfo', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectStatisticsInfo;
GO

CREATE PROCEDURE dbo.usp_CollectStatisticsInfo
    @ServerID INT = NULL -- NULL = all active servers
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;

    DECLARE @CurrentServerID INT;
    DECLARE @ServerName NVARCHAR(128);
    DECLARE @LinkedServerName NVARCHAR(128);
    DECLARE @ErrorMessage NVARCHAR(MAX);
    DECLARE @RowsInserted INT = 0;
    DECLARE @StartTime DATETIME2(7) = GETUTCDATE();

    -- Create temp table for statistics data
    CREATE TABLE #StatisticsData (
        ServerID INT,
        DatabaseName NVARCHAR(128),
        SchemaName NVARCHAR(128),
        TableName NVARCHAR(128),
        StatisticsName NVARCHAR(128),
        StatisticsID INT,
        IsClustered BIT,
        IsUnique BIT,
        LastUpdated DATETIME2(7),
        RowCount BIGINT,
        ModificationCounter BIGINT,
        SamplePercent DECIMAL(5,2)
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
        PRINT 'Collecting statistics info for server: ' + @ServerName;

        BEGIN TRY
            -- Build dynamic SQL to query remote server
            DECLARE @SQL NVARCHAR(MAX) = N'
            SELECT
                ' + CAST(@CurrentServerID AS NVARCHAR(10)) + ' AS ServerID,
                DB_NAME(s.object_id) AS DatabaseName,
                SCHEMA_NAME(t.schema_id) AS SchemaName,
                t.name AS TableName,
                s.name AS StatisticsName,
                s.stats_id AS StatisticsID,
                CASE WHEN i.type = 1 THEN 1 ELSE 0 END AS IsClustered,
                CASE WHEN i.is_unique = 1 THEN 1 ELSE 0 END AS IsUnique,
                sp.last_updated AS LastUpdated,
                sp.rows AS RowCount,
                sp.modification_counter AS ModificationCounter,
                CAST(sp.rows_sampled * 100.0 / NULLIF(sp.rows, 0) AS DECIMAL(5,2)) AS SamplePercent
            FROM sys.stats s
            INNER JOIN sys.tables t ON s.object_id = t.object_id
            LEFT JOIN sys.indexes i ON s.object_id = i.object_id AND s.name = i.name
            CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
            WHERE DB_NAME(s.object_id) NOT IN (''master'', ''tempdb'', ''model'', ''msdb'')
              AND t.is_ms_shipped = 0
              AND sp.rows > 0 -- Only tables with data
            ORDER BY DB_NAME(s.object_id), t.name, s.name;
            ';

            -- For local server
            IF @LinkedServerName IS NULL OR @LinkedServerName = '(local)' OR @LinkedServerName = @@SERVERNAME
            BEGIN
                INSERT INTO #StatisticsData
                EXEC sp_executesql @SQL;
            END
            ELSE
            BEGIN
                -- For remote server via linked server
                DECLARE @RemoteSQL NVARCHAR(MAX) = N'
                INSERT INTO #StatisticsData
                SELECT * FROM OPENQUERY([' + @LinkedServerName + '], ''' + REPLACE(@SQL, '''', '''''') + ''');
                ';
                EXEC sp_executesql @RemoteSQL;
            END;

            PRINT '  ✓ Collected statistics info for ' + @ServerName;

        END TRY
        BEGIN CATCH
            SET @ErrorMessage = ERROR_MESSAGE();
            PRINT '  ✗ Error collecting statistics for ' + @ServerName + ': ' + @ErrorMessage;
        END CATCH;

        FETCH NEXT FROM server_cursor INTO @CurrentServerID, @ServerName, @LinkedServerName;
    END;

    CLOSE server_cursor;
    DEALLOCATE server_cursor;

    -- Insert collected data into StatisticsInfo table
    INSERT INTO dbo.StatisticsInfo (
        ServerID, DatabaseName, SchemaName, TableName, StatisticsName, StatisticsID,
        IsClustered, IsUnique, LastUpdated, RowCount, ModificationCounter,
        SamplePercent, CollectionTime
    )
    SELECT
        ServerID, DatabaseName, SchemaName, TableName, StatisticsName, StatisticsID,
        IsClustered, IsUnique, LastUpdated, RowCount, ModificationCounter,
        SamplePercent, GETUTCDATE()
    FROM #StatisticsData;

    SET @RowsInserted = @@ROWCOUNT;

    DROP TABLE #StatisticsData;

    -- Return summary
    DECLARE @DurationSeconds INT = DATEDIFF(SECOND, @StartTime, GETUTCDATE());
    PRINT '';
    PRINT 'Statistics collection complete:';
    PRINT '  Total statistics collected: ' + CAST(@RowsInserted AS VARCHAR);
    PRINT '  Duration: ' + CAST(@DurationSeconds AS VARCHAR) + ' seconds';
    PRINT '';

    RETURN @RowsInserted;
END;
GO

PRINT 'Created procedure: dbo.usp_CollectStatisticsInfo';
PRINT ''

-- =====================================================
-- Procedure 3: usp_PerformIndexMaintenance
-- Purpose: Execute intelligent index maintenance (rebuild/reorganize)
-- =====================================================

IF OBJECT_ID('dbo.usp_PerformIndexMaintenance', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_PerformIndexMaintenance;
GO

CREATE PROCEDURE dbo.usp_PerformIndexMaintenance
    @ServerID INT = NULL, -- NULL = all servers
    @DatabaseName NVARCHAR(128) = NULL, -- NULL = all databases
    @MinFragmentationPercent DECIMAL(5,2) = 5.0,
    @RebuildThreshold DECIMAL(5,2) = 30.0,
    @MinPageCount INT = 1000,
    @DryRun BIT = 0, -- 1 = preview only, don't execute
    @MaxDurationMinutes INT = 240 -- 4 hours default
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;

    DECLARE @StartTime DATETIME2(7) = GETUTCDATE();
    DECLARE @MaintenanceCommand NVARCHAR(MAX);
    DECLARE @ErrorMessage NVARCHAR(MAX);
    DECLARE @TotalActions INT = 0;
    DECLARE @SuccessCount INT = 0;
    DECLARE @FailCount INT = 0;

    -- Decision logic: Build list of maintenance actions
    DECLARE @MaintenanceActions TABLE (
        ActionID INT IDENTITY(1,1),
        ServerID INT,
        ServerName NVARCHAR(128),
        LinkedServerName NVARCHAR(128),
        DatabaseName NVARCHAR(128),
        SchemaName NVARCHAR(128),
        TableName NVARCHAR(128),
        IndexName NVARCHAR(128),
        IndexID INT,
        PartitionNumber INT,
        FragmentationPercent DECIMAL(5,2),
        PageCount BIGINT,
        MaintenanceType VARCHAR(20), -- REBUILD or REORGANIZE
        Priority INT -- Higher fragmentation = higher priority
    );

    -- Get latest fragmentation snapshot and determine maintenance actions
    INSERT INTO @MaintenanceActions (
        ServerID, ServerName, LinkedServerName, DatabaseName, SchemaName, TableName,
        IndexName, IndexID, PartitionNumber, FragmentationPercent, PageCount,
        MaintenanceType, Priority
    )
    SELECT
        f.ServerID,
        s.ServerName,
        s.LinkedServerName,
        f.DatabaseName,
        f.SchemaName,
        f.TableName,
        f.IndexName,
        f.IndexID,
        f.PartitionNumber,
        f.FragmentationPercent,
        f.PageCount,
        CASE
            WHEN f.FragmentationPercent >= @RebuildThreshold THEN 'REBUILD'
            WHEN f.FragmentationPercent >= @MinFragmentationPercent THEN 'REORGANIZE'
        END AS MaintenanceType,
        CAST(f.FragmentationPercent AS INT) AS Priority
    FROM dbo.IndexFragmentation f
    INNER JOIN dbo.Servers s ON f.ServerID = s.ServerID
    INNER JOIN (
        -- Get latest collection for each index
        SELECT ServerID, DatabaseName, SchemaName, TableName, IndexName,
               MAX(CollectionTime) AS LastCollection
        FROM dbo.IndexFragmentation
        WHERE CollectionTime > DATEADD(HOUR, -12, GETUTCDATE())
        GROUP BY ServerID, DatabaseName, SchemaName, TableName, IndexName
    ) latest ON f.ServerID = latest.ServerID
            AND f.DatabaseName = latest.DatabaseName
            AND f.SchemaName = latest.SchemaName
            AND f.TableName = latest.TableName
            AND f.IndexName = latest.IndexName
            AND f.CollectionTime = latest.LastCollection
    WHERE f.PageCount >= @MinPageCount
      AND f.FragmentationPercent >= @MinFragmentationPercent
      AND s.IsActive = 1
      AND (@ServerID IS NULL OR f.ServerID = @ServerID)
      AND (@DatabaseName IS NULL OR f.DatabaseName = @DatabaseName)
    ORDER BY Priority DESC, f.PageCount DESC; -- High fragmentation + large indexes first

    SELECT @TotalActions = COUNT(*) FROM @MaintenanceActions;

    PRINT '======================================'
    PRINT 'Index Maintenance Execution Plan'
    PRINT '======================================'
    PRINT 'Total indexes requiring maintenance: ' + CAST(@TotalActions AS VARCHAR);
    PRINT 'Rebuild operations: ' + CAST((SELECT COUNT(*) FROM @MaintenanceActions WHERE MaintenanceType = 'REBUILD') AS VARCHAR);
    PRINT 'Reorganize operations: ' + CAST((SELECT COUNT(*) FROM @MaintenanceActions WHERE MaintenanceType = 'REORGANIZE') AS VARCHAR);
    PRINT 'Dry run: ' + CASE WHEN @DryRun = 1 THEN 'Yes (preview only)' ELSE 'No (executing)' END;
    PRINT 'Max duration: ' + CAST(@MaxDurationMinutes AS VARCHAR) + ' minutes';
    PRINT '';

    IF @TotalActions = 0
    BEGIN
        PRINT 'No indexes require maintenance. Exiting.';
        RETURN 0;
    END;

    -- Execute maintenance actions
    DECLARE @ActionID INT, @CurrentServerID INT, @CurrentServerName NVARCHAR(128),
            @CurrentLinkedServer NVARCHAR(128), @CurrentDB NVARCHAR(128),
            @CurrentSchema NVARCHAR(128), @CurrentTable NVARCHAR(128),
            @CurrentIndex NVARCHAR(128), @CurrentIndexID INT,
            @CurrentPartition INT, @CurrentFragmentation DECIMAL(5,2),
            @CurrentPageCount BIGINT, @CurrentType VARCHAR(20);

    DECLARE @OpStartTime DATETIME2(7), @OpEndTime DATETIME2(7);

    DECLARE maintenance_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT ActionID, ServerID, ServerName, LinkedServerName, DatabaseName, SchemaName,
               TableName, IndexName, IndexID, PartitionNumber, FragmentationPercent,
               PageCount, MaintenanceType
        FROM @MaintenanceActions
        ORDER BY Priority DESC, PageCount DESC;

    OPEN maintenance_cursor;
    FETCH NEXT FROM maintenance_cursor INTO @ActionID, @CurrentServerID, @CurrentServerName,
        @CurrentLinkedServer, @CurrentDB, @CurrentSchema, @CurrentTable, @CurrentIndex,
        @CurrentIndexID, @CurrentPartition, @CurrentFragmentation, @CurrentPageCount, @CurrentType;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Check if we've exceeded max duration
        IF DATEDIFF(MINUTE, @StartTime, GETUTCDATE()) >= @MaxDurationMinutes
        BEGIN
            PRINT 'Max duration (' + CAST(@MaxDurationMinutes AS VARCHAR) + ' minutes) reached. Stopping maintenance.';
            PRINT 'Completed: ' + CAST(@SuccessCount AS VARCHAR) + ' / ' + CAST(@TotalActions AS VARCHAR);
            BREAK;
        END;

        -- Build maintenance command
        IF @CurrentType = 'REBUILD'
        BEGIN
            SET @MaintenanceCommand =
                'USE [' + @CurrentDB + ']; ' +
                'ALTER INDEX [' + @CurrentIndex + '] ON [' + @CurrentSchema + '].[' + @CurrentTable + '] ' +
                'REBUILD WITH (ONLINE = OFF, SORT_IN_TEMPDB = ON);';
        END
        ELSE -- REORGANIZE
        BEGIN
            SET @MaintenanceCommand =
                'USE [' + @CurrentDB + ']; ' +
                'ALTER INDEX [' + @CurrentIndex + '] ON [' + @CurrentSchema + '].[' + @CurrentTable + '] ' +
                'REORGANIZE;';
        END;

        IF @DryRun = 1
        BEGIN
            PRINT '[' + CAST(@ActionID AS VARCHAR) + '/' + CAST(@TotalActions AS VARCHAR) + '] ' +
                  '[DRY RUN] ' + @CurrentType + ' - ' + @CurrentServerName + '.' + @CurrentDB + '.' +
                  @CurrentSchema + '.' + @CurrentTable + '.' + @CurrentIndex +
                  ' (Frag: ' + CAST(@CurrentFragmentation AS VARCHAR) + '%)';
        END
        ELSE
        BEGIN
            PRINT '[' + CAST(@ActionID AS VARCHAR) + '/' + CAST(@TotalActions AS VARCHAR) + '] ' +
                  'Executing ' + @CurrentType + ' on ' + @CurrentServerName + '.' + @CurrentDB + '.' +
                  @CurrentSchema + '.' + @CurrentTable + '.' + @CurrentIndex +
                  ' (Frag: ' + CAST(@CurrentFragmentation AS VARCHAR) + '%)';

            SET @OpStartTime = GETUTCDATE();

            BEGIN TRY
                -- Execute maintenance (local or remote)
                IF @CurrentLinkedServer IS NULL OR @CurrentLinkedServer = '(local)' OR @CurrentLinkedServer = @@SERVERNAME
                BEGIN
                    -- Local execution
                    EXEC sp_executesql @MaintenanceCommand;
                END
                ELSE
                BEGIN
                    -- Remote execution via linked server
                    DECLARE @RemoteExecSQL NVARCHAR(MAX) = N'
                    EXEC (''' + REPLACE(@MaintenanceCommand, '''', '''''') + ''') AT [' + @CurrentLinkedServer + '];
                    ';
                    EXEC sp_executesql @RemoteExecSQL;
                END;

                SET @OpEndTime = GETUTCDATE();
                SET @SuccessCount = @SuccessCount + 1;

                -- Log success
                INSERT INTO dbo.IndexMaintenanceHistory (
                    ServerID, DatabaseName, SchemaName, TableName, IndexName, IndexID,
                    PartitionNumber, MaintenanceType, StartTime, EndTime, DurationSeconds,
                    FragmentationBefore, PageCount, MaintenanceCommand, Status
                )
                VALUES (
                    @CurrentServerID, @CurrentDB, @CurrentSchema, @CurrentTable, @CurrentIndex, @CurrentIndexID,
                    @CurrentPartition, @CurrentType, @OpStartTime, @OpEndTime,
                    DATEDIFF(SECOND, @OpStartTime, @OpEndTime), @CurrentFragmentation,
                    @CurrentPageCount, @MaintenanceCommand, 'Success'
                );

                PRINT '  ✓ Completed in ' + CAST(DATEDIFF(SECOND, @OpStartTime, @OpEndTime) AS VARCHAR) + ' seconds';

            END TRY
            BEGIN CATCH
                SET @OpEndTime = GETUTCDATE();
                SET @ErrorMessage = ERROR_MESSAGE();
                SET @FailCount = @FailCount + 1;

                PRINT '  ✗ FAILED: ' + @ErrorMessage;

                -- Log failure
                INSERT INTO dbo.IndexMaintenanceHistory (
                    ServerID, DatabaseName, SchemaName, TableName, IndexName, IndexID,
                    PartitionNumber, MaintenanceType, StartTime, EndTime, DurationSeconds,
                    FragmentationBefore, PageCount, MaintenanceCommand, Status, ErrorMessage
                )
                VALUES (
                    @CurrentServerID, @CurrentDB, @CurrentSchema, @CurrentTable, @CurrentIndex, @CurrentIndexID,
                    @CurrentPartition, @CurrentType, @OpStartTime, @OpEndTime,
                    DATEDIFF(SECOND, @OpStartTime, @OpEndTime), @CurrentFragmentation,
                    @CurrentPageCount, @MaintenanceCommand, 'Failed', @ErrorMessage
                );
            END CATCH;
        END;

        FETCH NEXT FROM maintenance_cursor INTO @ActionID, @CurrentServerID, @CurrentServerName,
            @CurrentLinkedServer, @CurrentDB, @CurrentSchema, @CurrentTable, @CurrentIndex,
            @CurrentIndexID, @CurrentPartition, @CurrentFragmentation, @CurrentPageCount, @CurrentType;
    END;

    CLOSE maintenance_cursor;
    DEALLOCATE maintenance_cursor;

    -- Final summary
    DECLARE @TotalDurationMinutes INT = DATEDIFF(MINUTE, @StartTime, GETUTCDATE());

    PRINT '';
    PRINT '======================================'
    PRINT 'Index Maintenance Complete'
    PRINT '======================================'
    PRINT 'Total duration: ' + CAST(@TotalDurationMinutes AS VARCHAR) + ' minutes';
    IF @DryRun = 0
    BEGIN
        PRINT 'Successful operations: ' + CAST(@SuccessCount AS VARCHAR);
        PRINT 'Failed operations: ' + CAST(@FailCount AS VARCHAR);
        PRINT 'Success rate: ' + CAST(CAST(@SuccessCount * 100.0 / NULLIF(@TotalActions, 0) AS DECIMAL(5,2)) AS VARCHAR) + '%';
    END;
    PRINT '';

    RETURN @SuccessCount;
END;
GO

PRINT 'Created procedure: dbo.usp_PerformIndexMaintenance';
PRINT ''

-- =====================================================
-- Procedure 4: usp_UpdateStatistics
-- Purpose: Update outdated statistics
-- =====================================================

IF OBJECT_ID('dbo.usp_UpdateStatistics', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_UpdateStatistics;
GO

CREATE PROCEDURE dbo.usp_UpdateStatistics
    @ServerID INT = NULL,
    @DatabaseName NVARCHAR(128) = NULL,
    @MinDaysSinceUpdate INT = 7,
    @MinModificationPercent DECIMAL(5,2) = 20.0,
    @DryRun BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;

    DECLARE @StartTime DATETIME2(7) = GETUTCDATE();
    DECLARE @UpdateCommand NVARCHAR(MAX);
    DECLARE @ErrorMessage NVARCHAR(MAX);
    DECLARE @TotalActions INT = 0;
    DECLARE @SuccessCount INT = 0;

    -- Build list of statistics requiring updates
    DECLARE @StatisticsActions TABLE (
        ActionID INT IDENTITY(1,1),
        ServerID INT,
        ServerName NVARCHAR(128),
        LinkedServerName NVARCHAR(128),
        DatabaseName NVARCHAR(128),
        SchemaName NVARCHAR(128),
        TableName NVARCHAR(128),
        StatisticsName NVARCHAR(128),
        IsClustered BIT,
        IsUnique BIT,
        LastUpdated DATETIME2(7),
        ModificationPercent DECIMAL(5,2),
        SampleMethod VARCHAR(20) -- FULLSCAN or SAMPLE
    );

    -- Identify outdated statistics
    INSERT INTO @StatisticsActions (
        ServerID, ServerName, LinkedServerName, DatabaseName, SchemaName, TableName,
        StatisticsName, IsClustered, IsUnique, LastUpdated, ModificationPercent, SampleMethod
    )
    SELECT
        si.ServerID,
        s.ServerName,
        s.LinkedServerName,
        si.DatabaseName,
        si.SchemaName,
        si.TableName,
        si.StatisticsName,
        si.IsClustered,
        si.IsUnique,
        si.LastUpdated,
        CAST(si.ModificationCounter * 100.0 / NULLIF(si.RowCount, 0) AS DECIMAL(5,2)) AS ModificationPercent,
        CASE
            WHEN si.IsClustered = 1 OR si.IsUnique = 1 THEN 'FULLSCAN' -- Critical statistics
            ELSE 'SAMPLE' -- Non-critical statistics (50% sample)
        END AS SampleMethod
    FROM dbo.StatisticsInfo si
    INNER JOIN dbo.Servers s ON si.ServerID = s.ServerID
    INNER JOIN (
        -- Get latest collection for each statistic
        SELECT ServerID, DatabaseName, SchemaName, TableName, StatisticsName,
               MAX(CollectionTime) AS LastCollection
        FROM dbo.StatisticsInfo
        WHERE CollectionTime > DATEADD(HOUR, -12, GETUTCDATE())
        GROUP BY ServerID, DatabaseName, SchemaName, TableName, StatisticsName
    ) latest ON si.ServerID = latest.ServerID
            AND si.DatabaseName = latest.DatabaseName
            AND si.SchemaName = latest.SchemaName
            AND si.TableName = latest.TableName
            AND si.StatisticsName = latest.StatisticsName
            AND si.CollectionTime = latest.LastCollection
    WHERE s.IsActive = 1
      AND si.RowCount > 0
      AND (
          DATEDIFF(DAY, si.LastUpdated, GETUTCDATE()) >= @MinDaysSinceUpdate
          OR (si.ModificationCounter * 100.0 / NULLIF(si.RowCount, 0)) >= @MinModificationPercent
      )
      AND (@ServerID IS NULL OR si.ServerID = @ServerID)
      AND (@DatabaseName IS NULL OR si.DatabaseName = @DatabaseName)
    ORDER BY ModificationPercent DESC;

    SELECT @TotalActions = COUNT(*) FROM @StatisticsActions;

    PRINT '======================================'
    PRINT 'Statistics Update Execution Plan'
    PRINT '======================================'
    PRINT 'Total statistics requiring updates: ' + CAST(@TotalActions AS VARCHAR);
    PRINT 'FULLSCAN updates: ' + CAST((SELECT COUNT(*) FROM @StatisticsActions WHERE SampleMethod = 'FULLSCAN') AS VARCHAR);
    PRINT 'SAMPLE updates: ' + CAST((SELECT COUNT(*) FROM @StatisticsActions WHERE SampleMethod = 'SAMPLE') AS VARCHAR);
    PRINT 'Dry run: ' + CASE WHEN @DryRun = 1 THEN 'Yes (preview only)' ELSE 'No (executing)' END;
    PRINT '';

    IF @TotalActions = 0
    BEGIN
        PRINT 'No statistics require updates. Exiting.';
        RETURN 0;
    END;

    -- Execute statistics updates
    DECLARE @ActionID INT, @CurrentServerID INT, @CurrentServerName NVARCHAR(128),
            @CurrentLinkedServer NVARCHAR(128), @CurrentDB NVARCHAR(128),
            @CurrentSchema NVARCHAR(128), @CurrentTable NVARCHAR(128),
            @CurrentStatName NVARCHAR(128), @CurrentSampleMethod VARCHAR(20);

    DECLARE stats_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT ActionID, ServerID, ServerName, LinkedServerName, DatabaseName, SchemaName,
               TableName, StatisticsName, SampleMethod
        FROM @StatisticsActions
        ORDER BY ModificationPercent DESC;

    OPEN stats_cursor;
    FETCH NEXT FROM stats_cursor INTO @ActionID, @CurrentServerID, @CurrentServerName,
        @CurrentLinkedServer, @CurrentDB, @CurrentSchema, @CurrentTable, @CurrentStatName, @CurrentSampleMethod;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Build update command
        IF @CurrentSampleMethod = 'FULLSCAN'
        BEGIN
            SET @UpdateCommand =
                'USE [' + @CurrentDB + ']; ' +
                'UPDATE STATISTICS [' + @CurrentSchema + '].[' + @CurrentTable + '] [' + @CurrentStatName + '] WITH FULLSCAN;';
        END
        ELSE
        BEGIN
            SET @UpdateCommand =
                'USE [' + @CurrentDB + ']; ' +
                'UPDATE STATISTICS [' + @CurrentSchema + '].[' + @CurrentTable + '] [' + @CurrentStatName + '] WITH SAMPLE 50 PERCENT;';
        END;

        IF @DryRun = 1
        BEGIN
            PRINT '[' + CAST(@ActionID AS VARCHAR) + '/' + CAST(@TotalActions AS VARCHAR) + '] ' +
                  '[DRY RUN] UPDATE STATISTICS - ' + @CurrentServerName + '.' + @CurrentDB + '.' +
                  @CurrentSchema + '.' + @CurrentTable + '.' + @CurrentStatName +
                  ' (' + @CurrentSampleMethod + ')';
        END
        ELSE
        BEGIN
            PRINT '[' + CAST(@ActionID AS VARCHAR) + '/' + CAST(@TotalActions AS VARCHAR) + '] ' +
                  'Updating statistics: ' + @CurrentServerName + '.' + @CurrentDB + '.' +
                  @CurrentSchema + '.' + @CurrentTable + '.' + @CurrentStatName +
                  ' (' + @CurrentSampleMethod + ')';

            BEGIN TRY
                -- Execute update (local or remote)
                IF @CurrentLinkedServer IS NULL OR @CurrentLinkedServer = '(local)' OR @CurrentLinkedServer = @@SERVERNAME
                BEGIN
                    EXEC sp_executesql @UpdateCommand;
                END
                ELSE
                BEGIN
                    DECLARE @RemoteExecSQL NVARCHAR(MAX) = N'
                    EXEC (''' + REPLACE(@UpdateCommand, '''', '''''') + ''') AT [' + @CurrentLinkedServer + '];
                    ';
                    EXEC sp_executesql @RemoteExecSQL;
                END;

                SET @SuccessCount = @SuccessCount + 1;
                PRINT '  ✓ Complete';

            END TRY
            BEGIN CATCH
                SET @ErrorMessage = ERROR_MESSAGE();
                PRINT '  ✗ FAILED: ' + @ErrorMessage;
            END CATCH;
        END;

        FETCH NEXT FROM stats_cursor INTO @ActionID, @CurrentServerID, @CurrentServerName,
            @CurrentLinkedServer, @CurrentDB, @CurrentSchema, @CurrentTable, @CurrentStatName, @CurrentSampleMethod;
    END;

    CLOSE stats_cursor;
    DEALLOCATE stats_cursor;

    -- Final summary
    DECLARE @TotalDurationMinutes INT = DATEDIFF(MINUTE, @StartTime, GETUTCDATE());

    PRINT '';
    PRINT '======================================'
    PRINT 'Statistics Update Complete'
    PRINT '======================================'
    PRINT 'Total duration: ' + CAST(@TotalDurationMinutes AS VARCHAR) + ' minutes';
    IF @DryRun = 0
    BEGIN
        PRINT 'Successful updates: ' + CAST(@SuccessCount AS VARCHAR) + ' / ' + CAST(@TotalActions AS VARCHAR);
    END;
    PRINT '';

    RETURN @SuccessCount;
END;
GO

PRINT 'Created procedure: dbo.usp_UpdateStatistics';
PRINT ''

-- =====================================================
-- Procedure 5: usp_GetMaintenanceSummary
-- Purpose: Summary report for dashboards
-- =====================================================

IF OBJECT_ID('dbo.usp_GetMaintenanceSummary', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetMaintenanceSummary;
GO

CREATE PROCEDURE dbo.usp_GetMaintenanceSummary
    @ServerID INT = NULL,
    @DaysBack INT = 30
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        s.ServerName,
        COUNT(DISTINCT h.MaintenanceID) AS TotalMaintenanceOperations,
        SUM(CASE WHEN h.MaintenanceType = 'REBUILD' THEN 1 ELSE 0 END) AS TotalRebuilds,
        SUM(CASE WHEN h.MaintenanceType = 'REORGANIZE' THEN 1 ELSE 0 END) AS TotalReorganizes,
        SUM(CASE WHEN h.Status = 'Success' THEN 1 ELSE 0 END) AS SuccessfulOperations,
        SUM(CASE WHEN h.Status = 'Failed' THEN 1 ELSE 0 END) AS FailedOperations,
        CAST(SUM(h.DurationSeconds) / 60.0 AS DECIMAL(10,2)) AS TotalMaintenanceMinutes,
        CAST(AVG(h.FragmentationBefore) AS DECIMAL(5,2)) AS AvgFragmentationBefore,
        CAST(AVG(h.FragmentationAfter) AS DECIMAL(5,2)) AS AvgFragmentationAfter,
        CAST(AVG(h.DurationSeconds) AS DECIMAL(10,2)) AS AvgDurationSeconds
    FROM dbo.IndexMaintenanceHistory h
    INNER JOIN dbo.Servers s ON h.ServerID = s.ServerID
    WHERE h.StartTime >= DATEADD(DAY, -@DaysBack, GETUTCDATE())
      AND (@ServerID IS NULL OR h.ServerID = @ServerID)
    GROUP BY s.ServerName
    ORDER BY s.ServerName;
END;
GO

PRINT 'Created procedure: dbo.usp_GetMaintenanceSummary';
PRINT ''

-- =====================================================
-- Summary and Verification
-- =====================================================

PRINT '======================================'
PRINT 'Index Maintenance Procedures Summary'
PRINT '======================================'
PRINT ''

PRINT 'Stored Procedures Created:'
SELECT
    ROUTINE_NAME AS ProcedureName,
    CREATED AS CreatedDate
FROM INFORMATION_SCHEMA.ROUTINES
WHERE ROUTINE_TYPE = 'PROCEDURE'
  AND ROUTINE_NAME IN (
      'usp_CollectIndexFragmentation',
      'usp_CollectStatisticsInfo',
      'usp_PerformIndexMaintenance',
      'usp_UpdateStatistics',
      'usp_GetMaintenanceSummary'
  )
ORDER BY ROUTINE_NAME;

PRINT ''
PRINT 'Test Commands:'
PRINT '  -- Collect fragmentation data'
PRINT '  EXEC dbo.usp_CollectIndexFragmentation;'
PRINT ''
PRINT '  -- Collect statistics info'
PRINT '  EXEC dbo.usp_CollectStatisticsInfo;'
PRINT ''
PRINT '  -- Perform index maintenance (dry run)'
PRINT '  EXEC dbo.usp_PerformIndexMaintenance @DryRun = 1;'
PRINT ''
PRINT '  -- Update outdated statistics (dry run)'
PRINT '  EXEC dbo.usp_UpdateStatistics @DryRun = 1;'
PRINT ''
PRINT '  -- Get maintenance summary'
PRINT '  EXEC dbo.usp_GetMaintenanceSummary @DaysBack = 30;'
PRINT ''

PRINT '======================================'
PRINT 'Index Maintenance Procedures Created Successfully'
PRINT '======================================'
PRINT ''

GO
