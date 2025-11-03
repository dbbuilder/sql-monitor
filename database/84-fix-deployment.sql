-- =====================================================
-- Fix Feature #6 Deployment Issues
-- =====================================================
USE MonitoringDB;
GO

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
GO

PRINT 'Fixing Feature #6 deployment issues...'
PRINT ''

-- Drop and recreate StatisticsInfo with proper column name
IF OBJECT_ID('dbo.StatisticsInfo', 'U') IS NOT NULL
    DROP TABLE dbo.StatisticsInfo;
GO

CREATE TABLE dbo.StatisticsInfo (
    StatID BIGINT IDENTITY(1,1) NOT NULL,
    ServerID INT NOT NULL,
    DatabaseName NVARCHAR(128) NOT NULL,
    SchemaName NVARCHAR(128) NOT NULL,
    TableName NVARCHAR(128) NOT NULL,
    StatisticsName NVARCHAR(128) NOT NULL,
    StatisticsID INT NOT NULL,
    IsClustered BIT NOT NULL DEFAULT 0,
    IsUnique BIT NOT NULL DEFAULT 0,
    LastUpdated DATETIME2(7) NULL,
    RowCount_Value BIGINT NOT NULL,
    ModificationCounter BIGINT NOT NULL,
    SamplePercent DECIMAL(5,2) NULL,
    CollectionTime DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT PK_StatisticsInfo PRIMARY KEY CLUSTERED (StatID),
    CONSTRAINT FK_StatisticsInfo_Server FOREIGN KEY (ServerID)
        REFERENCES dbo.Servers(ServerID)
);
GO

CREATE NONCLUSTERED INDEX IX_StatisticsInfo_Server_Time
    ON dbo.StatisticsInfo(ServerID, CollectionTime)
    INCLUDE (DatabaseName, SchemaName, TableName, StatisticsName, LastUpdated, ModificationCounter);
GO

CREATE NONCLUSTERED INDEX IX_StatisticsInfo_Outdated
    ON dbo.StatisticsInfo(LastUpdated, ModificationCounter)
    INCLUDE (ServerID, DatabaseName, SchemaName, TableName, StatisticsName, RowCount_Value)
    WHERE ModificationCounter > 1000;
GO

PRINT 'StatisticsInfo table recreated successfully'
PRINT ''

-- Fix usp_CollectStatisticsInfo
IF OBJECT_ID('dbo.usp_CollectStatisticsInfo', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectStatisticsInfo;
GO

CREATE PROCEDURE dbo.usp_CollectStatisticsInfo
    @ServerID INT = NULL
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
        RowCount_Value BIGINT,
        ModificationCounter BIGINT,
        SamplePercent DECIMAL(5,2)
    );

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
            DECLARE @SQL NVARCHAR(MAX) = N'
            SELECT
                ' + CAST(@CurrentServerID AS NVARCHAR(10)) + ' AS ServerID,
                DB_NAME() AS DatabaseName,
                SCHEMA_NAME(t.schema_id) AS SchemaName,
                t.name AS TableName,
                s.name AS StatisticsName,
                s.stats_id AS StatisticsID,
                CASE WHEN i.type = 1 THEN 1 ELSE 0 END AS IsClustered,
                CASE WHEN i.is_unique = 1 THEN 1 ELSE 0 END AS IsUnique,
                sp.last_updated AS LastUpdated,
                sp.rows AS RowCount_Value,
                sp.modification_counter AS ModificationCounter,
                CAST(sp.rows_sampled * 100.0 / NULLIF(sp.rows, 0) AS DECIMAL(5,2)) AS SamplePercent
            FROM sys.stats s
            INNER JOIN sys.tables t ON s.object_id = t.object_id
            LEFT JOIN sys.indexes i ON s.object_id = i.object_id AND s.name = i.name
            CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
            WHERE t.is_ms_shipped = 0
              AND sp.rows > 0
            ORDER BY t.name, s.name;
            ';

            IF @LinkedServerName IS NULL OR @LinkedServerName = '(local)' OR @LinkedServerName = @@SERVERNAME
            BEGIN
                INSERT INTO #StatisticsData
                EXEC sp_executesql @SQL;
            END
            ELSE
            BEGIN
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

    INSERT INTO dbo.StatisticsInfo (
        ServerID, DatabaseName, SchemaName, TableName, StatisticsName, StatisticsID,
        IsClustered, IsUnique, LastUpdated, RowCount_Value, ModificationCounter,
        SamplePercent, CollectionTime
    )
    SELECT
        ServerID, DatabaseName, SchemaName, TableName, StatisticsName, StatisticsID,
        IsClustered, IsUnique, LastUpdated, RowCount_Value, ModificationCounter,
        SamplePercent, GETUTCDATE()
    FROM #StatisticsData;

    SET @RowsInserted = @@ROWCOUNT;

    DROP TABLE #StatisticsData;

    DECLARE @DurationSeconds INT = DATEDIFF(SECOND, @StartTime, GETUTCDATE());
    PRINT '';
    PRINT 'Statistics collection complete:';
    PRINT '  Total statistics collected: ' + CAST(@RowsInserted AS VARCHAR);
    PRINT '  Duration: ' + CAST(@DurationSeconds AS VARCHAR) + ' seconds';
    PRINT '';

    RETURN @RowsInserted;
END;
GO

PRINT 'Fixed procedure: dbo.usp_CollectStatisticsInfo'
PRINT ''

-- Fix usp_UpdateStatistics
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
        SampleMethod VARCHAR(20)
    );

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
        CAST(si.ModificationCounter * 100.0 / NULLIF(si.RowCount_Value, 0) AS DECIMAL(5,2)) AS ModificationPercent,
        CASE
            WHEN si.IsClustered = 1 OR si.IsUnique = 1 THEN 'FULLSCAN'
            ELSE 'SAMPLE'
        END AS SampleMethod
    FROM dbo.StatisticsInfo si
    INNER JOIN dbo.Servers s ON si.ServerID = s.ServerID
    INNER JOIN (
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
      AND si.RowCount_Value > 0
      AND (
          DATEDIFF(DAY, si.LastUpdated, GETUTCDATE()) >= @MinDaysSinceUpdate
          OR (si.ModificationCounter * 100.0 / NULLIF(si.RowCount_Value, 0)) >= @MinModificationPercent
      )
      AND (@ServerID IS NULL OR si.ServerID = @ServerID)
      AND (@DatabaseName IS NULL OR si.DatabaseName = @DatabaseName)
    ORDER BY ModificationPercent DESC;

    SELECT @TotalActions = COUNT(*) FROM @StatisticsActions;

    PRINT '======================================';
    PRINT 'Statistics Update Execution Plan';
    PRINT '======================================';
    PRINT 'Total statistics requiring updates: ' + CAST(@TotalActions AS VARCHAR);
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

    DECLARE @TotalDurationMinutes INT = DATEDIFF(MINUTE, @StartTime, GETUTCDATE());

    PRINT '';
    PRINT '======================================';
    PRINT 'Statistics Update Complete';
    PRINT '======================================';
    PRINT 'Total duration: ' + CAST(@TotalDurationMinutes AS VARCHAR) + ' minutes';
    IF @DryRun = 0
    BEGIN
        PRINT 'Successful updates: ' + CAST(@SuccessCount AS VARCHAR) + ' / ' + CAST(@TotalActions AS VARCHAR);
    END;
    PRINT '';

    RETURN @SuccessCount;
END;
GO

PRINT 'Fixed procedure: dbo.usp_UpdateStatistics'
PRINT ''

PRINT '======================================'
PRINT 'Feature #6 deployment fixes complete!'
PRINT '======================================'
PRINT ''

GO
