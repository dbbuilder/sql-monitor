-- =============================================
-- Automated Index Maintenance for SQL Server Monitor
-- Created: 2025-10-26
-- Description: Weekly defragmentation, statistics updates, maintenance reporting
-- =============================================

USE [MonitoringDB];
GO

PRINT 'Creating Automated Index Maintenance System...';
GO

-- =============================================
-- Table 1: Index Maintenance History
-- =============================================

IF OBJECT_ID('dbo.IndexMaintenanceHistory', 'U') IS NOT NULL
    DROP TABLE dbo.IndexMaintenanceHistory;
GO

CREATE TABLE dbo.IndexMaintenanceHistory (
    MaintenanceID BIGINT IDENTITY(1,1) NOT NULL,
    ServerID INT NOT NULL,
    DatabaseName NVARCHAR(128) NOT NULL,
    SchemaName NVARCHAR(128) NOT NULL,
    TableName NVARCHAR(128) NOT NULL,
    IndexName NVARCHAR(128) NOT NULL,
    MaintenanceType VARCHAR(20) NOT NULL, -- REBUILD, REORGANIZE, STATISTICS, NONE
    FragmentationBefore FLOAT NOT NULL,
    FragmentationAfter FLOAT NULL,
    PageCountBefore BIGINT NOT NULL,
    DurationSeconds INT NOT NULL,
    StartTime DATETIME2(7) NOT NULL,
    EndTime DATETIME2(7) NOT NULL,

    CONSTRAINT PK_IndexMaintenanceHistory PRIMARY KEY CLUSTERED (MaintenanceID),
    CONSTRAINT FK_IndexMaintenanceHistory_Servers FOREIGN KEY (ServerID) REFERENCES dbo.Servers(ServerID)
);
GO

CREATE NONCLUSTERED INDEX IX_IndexMaintenanceHistory_Server_Date ON dbo.IndexMaintenanceHistory (ServerID, StartTime DESC);
GO

PRINT 'Table created: dbo.IndexMaintenanceHistory';
GO

-- =============================================
-- Stored Procedure 1: Perform Index Maintenance
-- =============================================

IF OBJECT_ID('dbo.usp_PerformIndexMaintenance', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_PerformIndexMaintenance;
GO

CREATE PROCEDURE dbo.usp_PerformIndexMaintenance
    @ServerID INT,
    @DatabaseName NVARCHAR(128) = NULL, -- NULL = all databases
    @MinFragmentation FLOAT = 10.0,
    @MinPageCount INT = 1000,
    @OnlineRebuild BIT = 1,
    @MaxDegreeOfParallelism INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

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

    PRINT CONCAT('Starting index maintenance for server: ', @LinkedServerName);

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

    -- Build query to get index fragmentation stats from remote server
    SET @SQL = N'
    SELECT
        DB_NAME(ips.database_id) AS DatabaseName,
        OBJECT_SCHEMA_NAME(ips.object_id, ips.database_id) AS SchemaName,
        OBJECT_NAME(ips.object_id, ips.database_id) AS TableName,
        i.name AS IndexName,
        ips.avg_fragmentation_in_percent AS FragmentationPercent,
        ips.page_count AS PageCount,
        CASE
            WHEN ips.avg_fragmentation_in_percent >= 30 THEN ''REBUILD''
            WHEN ips.avg_fragmentation_in_percent >= 10 THEN ''REORGANIZE''
            ELSE ''NONE''
        END AS MaintenanceAction
    FROM sys.dm_db_index_physical_stats(NULL, NULL, NULL, NULL, ''LIMITED'') ips
    INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
    WHERE ips.avg_fragmentation_in_percent >= ' + CAST(@MinFragmentation AS NVARCHAR(10)) + '
      AND ips.page_count >= ' + CAST(@MinPageCount AS NVARCHAR(10)) + '
      AND i.name IS NOT NULL
      AND ips.index_type_desc IN (''CLUSTERED INDEX'', ''NONCLUSTERED INDEX'')
      ' + CASE WHEN @DatabaseName IS NOT NULL THEN 'AND DB_NAME(ips.database_id) = ''' + @DatabaseName + '''' ELSE '' END + '
    ORDER BY ips.avg_fragmentation_in_percent DESC;
    ';

    -- Execute query via OPENQUERY (linked server)
    -- Note: In production, this would use OPENQUERY or execute remote stored procedure
    -- For MonitoringDB (local), we can query directly

    INSERT INTO @IndexesToMaintain
    EXEC sp_executesql @SQL;

    DECLARE @TotalIndexes INT;
    DECLARE @ProcessedIndexes INT;

    SELECT @TotalIndexes = COUNT(*)
    FROM @IndexesToMaintain
    WHERE MaintenanceAction IN ('REBUILD', 'REORGANIZE');

    SET @ProcessedIndexes = 0;

    PRINT CONCAT('Found ', @TotalIndexes, ' indexes requiring maintenance');

    -- Process each index
    DECLARE @DbName NVARCHAR(128), @SchemaName NVARCHAR(128), @TableName NVARCHAR(128), @IndexName NVARCHAR(128);
    DECLARE @Fragmentation FLOAT, @PageCount BIGINT, @Action VARCHAR(20);

    DECLARE index_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT DatabaseName, SchemaName, TableName, IndexName, FragmentationPercent, PageCount, MaintenanceAction
        FROM @IndexesToMaintain
        WHERE MaintenanceAction IN ('REBUILD', 'REORGANIZE')
        ORDER BY PageCount DESC; -- Process largest indexes first

    OPEN index_cursor;
    FETCH NEXT FROM index_cursor INTO @DbName, @SchemaName, @TableName, @IndexName, @Fragmentation, @PageCount, @Action;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @StartTime = GETUTCDATE();

        BEGIN TRY
            -- Build maintenance command
            SET @SQL = N'USE [' + @DbName + ']; ';

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

            PRINT CONCAT('[', @ProcessedIndexes + 1, '/', @TotalIndexes, '] ', @Action, ': ', @DbName, '.', @SchemaName, '.', @TableName, '.', @IndexName, ' (', CAST(@Fragmentation AS VARCHAR(10)), '% fragmented, ', @PageCount, ' pages)');

            -- Execute maintenance command
            EXEC sp_executesql @SQL;

            SET @EndTime = GETUTCDATE();
            SET @DurationSeconds = DATEDIFF(SECOND, @StartTime, @EndTime);

            -- Log maintenance action
            INSERT INTO dbo.IndexMaintenanceHistory (
                ServerID, DatabaseName, SchemaName, TableName, IndexName,
                MaintenanceType, FragmentationBefore, PageCountBefore,
                DurationSeconds, StartTime, EndTime
            )
            VALUES (
                @ServerID, @DbName, @SchemaName, @TableName, @IndexName,
                @Action, @Fragmentation, @PageCount,
                @DurationSeconds, @StartTime, @EndTime
            );

            SET @ProcessedIndexes = @ProcessedIndexes + 1;

            PRINT CONCAT('  Completed in ', @DurationSeconds, ' seconds');
        END TRY
        BEGIN CATCH
            PRINT CONCAT('  ERROR: ', ERROR_MESSAGE());

            -- Log failed maintenance attempt
            INSERT INTO dbo.IndexMaintenanceHistory (
                ServerID, DatabaseName, SchemaName, TableName, IndexName,
                MaintenanceType, FragmentationBefore, PageCountBefore,
                DurationSeconds, StartTime, EndTime
            )
            VALUES (
                @ServerID, @DbName, @SchemaName, @TableName, @IndexName,
                'FAILED', @Fragmentation, @PageCount,
                0, @StartTime, GETUTCDATE()
            );
        END CATCH;

        FETCH NEXT FROM index_cursor INTO @DbName, @SchemaName, @TableName, @IndexName, @Fragmentation, @PageCount, @Action;
    END;

    CLOSE index_cursor;
    DEALLOCATE index_cursor;

    PRINT CONCAT('Index maintenance completed. Processed: ', @ProcessedIndexes, '/', @TotalIndexes);
END;
GO

PRINT 'Stored procedure created: dbo.usp_PerformIndexMaintenance';
GO

-- =============================================
-- Stored Procedure 2: Update Statistics
-- =============================================

IF OBJECT_ID('dbo.usp_UpdateStatistics', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_UpdateStatistics;
GO

CREATE PROCEDURE dbo.usp_UpdateStatistics
    @ServerID INT,
    @DatabaseName NVARCHAR(128) = NULL, -- NULL = all databases
    @SamplePercent INT = 100, -- FULLSCAN = 100, or specific percentage
    @OnlyIfModified BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @LinkedServerName NVARCHAR(128);

    -- Get server info
    SELECT @LinkedServerName = ServerName
    FROM dbo.Servers
    WHERE ServerID = @ServerID;

    IF @LinkedServerName IS NULL
    BEGIN
        RAISERROR('Server not found: %d', 16, 1, @ServerID);
        RETURN;
    END;

    PRINT CONCAT('Starting statistics update for server: ', @LinkedServerName);

    -- Build query to update statistics
    -- For each database
    DECLARE @DbCursor CURSOR;
    DECLARE @CurrentDb NVARCHAR(128);

    IF @DatabaseName IS NOT NULL
    BEGIN
        -- Single database
        SET @CurrentDb = @DatabaseName;

        SET @SQL = N'USE [' + @CurrentDb + ']; ';

        IF @SamplePercent = 100
            SET @SQL = @SQL + N'EXEC sp_updatestats;'; -- Fast, uses sampling
        ELSE
            SET @SQL = @SQL + N'UPDATE STATISTICS ALL WITH SAMPLE ' + CAST(@SamplePercent AS NVARCHAR(10)) + N' PERCENT;';

        PRINT CONCAT('Updating statistics in database: ', @CurrentDb);
        EXEC sp_executesql @SQL;
        PRINT '  Completed';
    END
    ELSE
    BEGIN
        -- All databases
        DECLARE @Databases TABLE (DatabaseName NVARCHAR(128));

        INSERT INTO @Databases
        SELECT name
        FROM sys.databases
        WHERE state_desc = 'ONLINE'
          AND name NOT IN ('master', 'model', 'msdb', 'tempdb', 'rdsadmin');

        DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT DatabaseName FROM @Databases;

        OPEN db_cursor;
        FETCH NEXT FROM db_cursor INTO @CurrentDb;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            BEGIN TRY
                SET @SQL = N'USE [' + @CurrentDb + ']; ';

                IF @SamplePercent = 100
                    SET @SQL = @SQL + N'EXEC sp_updatestats;';
                ELSE
                    SET @SQL = @SQL + N'UPDATE STATISTICS ALL WITH SAMPLE ' + CAST(@SamplePercent AS NVARCHAR(10)) + N' PERCENT;';

                PRINT CONCAT('Updating statistics in database: ', @CurrentDb);
                EXEC sp_executesql @SQL;
                PRINT '  Completed';
            END TRY
            BEGIN CATCH
                PRINT CONCAT('  ERROR: ', ERROR_MESSAGE());
            END CATCH;

            FETCH NEXT FROM db_cursor INTO @CurrentDb;
        END;

        CLOSE db_cursor;
        DEALLOCATE db_cursor;
    END;

    PRINT 'Statistics update completed';
END;
GO

PRINT 'Stored procedure created: dbo.usp_UpdateStatistics';
GO

-- =============================================
-- Stored Procedure 3: Get Index Maintenance Report
-- =============================================

IF OBJECT_ID('dbo.usp_GetIndexMaintenanceReport', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetIndexMaintenanceReport;
GO

CREATE PROCEDURE dbo.usp_GetIndexMaintenanceReport
    @ServerID INT = NULL,
    @StartDate DATETIME2(7) = NULL,
    @EndDate DATETIME2(7) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @StartDate IS NULL
        SET @StartDate = DATEADD(DAY, -30, GETUTCDATE());

    IF @EndDate IS NULL
        SET @EndDate = GETUTCDATE();

    -- Summary report
    SELECT
        s.ServerName,
        imh.DatabaseName,
        imh.MaintenanceType,
        COUNT(*) AS MaintenanceCount,
        AVG(imh.FragmentationBefore) AS AvgFragmentationBefore,
        AVG(imh.DurationSeconds) AS AvgDurationSeconds,
        SUM(imh.DurationSeconds) AS TotalDurationSeconds,
        MIN(imh.StartTime) AS FirstMaintenanceDate,
        MAX(imh.StartTime) AS LastMaintenanceDate
    FROM dbo.IndexMaintenanceHistory imh
    INNER JOIN dbo.Servers s ON imh.ServerID = s.ServerID
    WHERE (@ServerID IS NULL OR imh.ServerID = @ServerID)
      AND imh.StartTime BETWEEN @StartDate AND @EndDate
      AND imh.MaintenanceType IN ('REBUILD', 'REORGANIZE')
    GROUP BY s.ServerName, imh.DatabaseName, imh.MaintenanceType
    ORDER BY s.ServerName, imh.DatabaseName, imh.MaintenanceType;

    -- Top 10 slowest index maintenance operations
    SELECT TOP 10
        s.ServerName,
        imh.DatabaseName,
        imh.SchemaName,
        imh.TableName,
        imh.IndexName,
        imh.MaintenanceType,
        imh.FragmentationBefore,
        imh.PageCountBefore,
        imh.DurationSeconds,
        imh.StartTime
    FROM dbo.IndexMaintenanceHistory imh
    INNER JOIN dbo.Servers s ON imh.ServerID = s.ServerID
    WHERE (@ServerID IS NULL OR imh.ServerID = @ServerID)
      AND imh.StartTime BETWEEN @StartDate AND @EndDate
      AND imh.MaintenanceType IN ('REBUILD', 'REORGANIZE')
    ORDER BY imh.DurationSeconds DESC;
END;
GO

PRINT 'Stored procedure created: dbo.usp_GetIndexMaintenanceReport';
GO

-- =============================================
-- Create SQL Agent Job for Weekly Index Maintenance
-- =============================================

PRINT 'Creating SQL Agent job for weekly index maintenance...';
GO

-- Check if SQL Agent is available
IF OBJECT_ID('msdb.dbo.sp_add_job') IS NULL
BEGIN
    PRINT 'SQL Server Agent is not available. Skipping job creation.';
    PRINT 'You can manually run: EXEC dbo.usp_PerformIndexMaintenance @ServerID = 1;';
END
ELSE
BEGIN
    DECLARE @jobId UNIQUEIDENTIFIER;
    DECLARE @jobName NVARCHAR(128);

    SET @jobName = N'SQL Monitor - Weekly Index Maintenance';

    -- Delete existing job if it exists
    IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @jobName)
    BEGIN
        EXEC msdb.dbo.sp_delete_job @job_name = @jobName;
        PRINT CONCAT('Existing job deleted: ', @jobName);
    END;

    -- Create job
    EXEC msdb.dbo.sp_add_job
        @job_name = @jobName,
        @enabled = 1,
        @description = N'Automated weekly index maintenance (rebuild/reorganize fragmented indexes)',
        @owner_login_name = N'sa',
        @job_id = @jobId OUTPUT;

    -- Add job step: Index Maintenance
    EXEC msdb.dbo.sp_add_jobstep
        @job_id = @jobId,
        @step_name = N'Perform Index Maintenance',
        @subsystem = N'TSQL',
        @command = N'EXEC dbo.usp_PerformIndexMaintenance @ServerID = 1, @MinFragmentation = 10.0, @MinPageCount = 1000, @OnlineRebuild = 1;',
        @database_name = N'MonitoringDB',
        @on_success_action = 3, -- Go to next step
        @on_fail_action = 3;    -- Go to next step

    -- Add job step: Update Statistics
    EXEC msdb.dbo.sp_add_jobstep
        @job_id = @jobId,
        @step_name = N'Update Statistics',
        @subsystem = N'TSQL',
        @command = N'EXEC dbo.usp_UpdateStatistics @ServerID = 1, @SamplePercent = 100;',
        @database_name = N'MonitoringDB',
        @on_success_action = 1, -- Quit with success
        @on_fail_action = 2;    -- Quit with failure

    -- Create schedule: Weekly on Sunday at 2 AM
    DECLARE @scheduleId INT;

    EXEC msdb.dbo.sp_add_schedule
        @schedule_name = N'Weekly Sunday 2 AM',
        @enabled = 1,
        @freq_type = 8,              -- Weekly
        @freq_interval = 1,          -- Sunday
        @freq_subday_type = 1,       -- At specified time
        @freq_recurrence_factor = 1, -- Every week
        @active_start_time = 20000,  -- 02:00:00 AM
        @schedule_id = @scheduleId OUTPUT;

    -- Attach schedule to job
    EXEC msdb.dbo.sp_attach_schedule
        @job_id = @jobId,
        @schedule_id = @scheduleId;

    -- Add job to local server
    EXEC msdb.dbo.sp_add_jobserver
        @job_id = @jobId,
        @server_name = N'(local)';

    PRINT CONCAT('Job created: ', @jobName);
    PRINT '  Schedule: Weekly on Sunday at 2:00 AM';
END;
GO

PRINT '';
PRINT 'Automated Index Maintenance System created successfully!';
PRINT '';
PRINT 'Summary:';
PRINT '- Table: IndexMaintenanceHistory';
PRINT '- Stored Procedures: usp_PerformIndexMaintenance, usp_UpdateStatistics, usp_GetIndexMaintenanceReport';
PRINT '- SQL Agent Job: SQL Monitor - Weekly Index Maintenance (Sundays at 2 AM)';
PRINT '';
PRINT 'Manual Execution:';
PRINT '  EXEC dbo.usp_PerformIndexMaintenance @ServerID = 1;';
PRINT '  EXEC dbo.usp_UpdateStatistics @ServerID = 1;';
PRINT '  EXEC dbo.usp_GetIndexMaintenanceReport @ServerID = 1;';
GO
