-- =============================================
-- Phase 1.25: Auto-Distribute DDL Trigger to All User Databases
-- Part 4: Master-level procedure to deploy triggers across all databases
-- Created: 2025-10-26
--
-- DEPLOYMENT INSTRUCTIONS:
-- 1. Execute this script on the MONITORED SERVER (not MonitoringDB server)
-- 2. Creates procedure in master database (accessible from any DB context)
-- 3. Run: EXEC master.dbo.usp_DeploySchemaChangeTriggersToAllDatabases;
-- =============================================

USE [master];
GO

SET QUOTED_IDENTIFIER ON;
GO

PRINT 'Creating auto-distribute procedure in master database...';
PRINT '';
GO

-- =============================================
-- Drop existing procedure if it exists
-- =============================================

IF OBJECT_ID('dbo.usp_DeploySchemaChangeTriggersToAllDatabases', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_DeploySchemaChangeTriggersToAllDatabases;
GO

-- =============================================
-- Create Auto-Distribute Procedure
-- =============================================

CREATE PROCEDURE dbo.usp_DeploySchemaChangeTriggersToAllDatabases
    @MonitoringServer NVARCHAR(128) = NULL, -- NULL = same server, or specify remote server name
    @MonitoringDatabase NVARCHAR(128) = 'MonitoringDB', -- Default: MonitoringDB
    @IncludeSystemDatabases BIT = 0, -- 1 = include master, msdb, model (not recommended)
    @ExcludeDatabases NVARCHAR(MAX) = NULL, -- Comma-separated list of databases to exclude
    @TestOnly BIT = 0 -- 1 = show what would be deployed without actually deploying
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ServerName NVARCHAR(128) = @@SERVERNAME;
    DECLARE @CurrentDB NVARCHAR(128);
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @TriggerSQL NVARCHAR(MAX);
    DECLARE @DeployedCount INT = 0;
    DECLARE @SkippedCount INT = 0;
    DECLARE @ErrorCount INT = 0;

    -- Determine MonitoringDB location
    DECLARE @MonitoringDBReference NVARCHAR(256);
    IF @MonitoringServer IS NULL OR @MonitoringServer = @ServerName
        SET @MonitoringDBReference = QUOTENAME(@MonitoringDatabase) + '.[dbo].[SchemaChangeLog]';
    ELSE
        SET @MonitoringDBReference = QUOTENAME(@MonitoringServer) + '.' + QUOTENAME(@MonitoringDatabase) + '.[dbo].[SchemaChangeLog]';

    PRINT '========================================';
    PRINT 'Schema Change Trigger Auto-Deployment';
    PRINT '========================================';
    PRINT CONCAT('Server: ', @ServerName);
    PRINT CONCAT('MonitoringDB: ', @MonitoringDBReference);
    PRINT CONCAT('Mode: ', CASE WHEN @TestOnly = 1 THEN 'TEST ONLY (no deployment)' ELSE 'DEPLOY' END);
    PRINT '';

    -- Build DDL trigger SQL (same for all databases)
    -- Note: CREATE TRIGGER must be first statement in batch, so we use EXEC to wrap it
    SET @TriggerSQL = N'
    -- Drop existing trigger if it exists
    IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = ''trg_DDL_SchemaChangeDetection'' AND parent_class_desc = ''DATABASE'')
    BEGIN
        DROP TRIGGER trg_DDL_SchemaChangeDetection ON DATABASE;
    END;
    ';

    -- Append the CREATE TRIGGER statement (must be in separate EXEC to be first in batch)
    SET @TriggerSQL = @TriggerSQL + N'
    EXEC(''''
    CREATE TRIGGER trg_DDL_SchemaChangeDetection
    ON DATABASE
    FOR CREATE_TABLE, ALTER_TABLE, DROP_TABLE,
        CREATE_PROCEDURE, ALTER_PROCEDURE, DROP_PROCEDURE,
        CREATE_VIEW, ALTER_VIEW, DROP_VIEW,
        CREATE_FUNCTION, ALTER_FUNCTION, DROP_FUNCTION,
        CREATE_INDEX, ALTER_INDEX, DROP_INDEX,
        CREATE_TRIGGER, ALTER_TRIGGER, DROP_TRIGGER
    AS
    BEGIN
        SET NOCOUNT ON;

        DECLARE @EventData XML;
        DECLARE @EventType VARCHAR(50);
        DECLARE @ObjectName NVARCHAR(128);
        DECLARE @SchemaName NVARCHAR(128);

        SET @EventData = EVENTDATA();
        SET @EventType = @EventData.value(''''''''(/EVENT_INSTANCE/EventType)[1]'''''''', ''''''''VARCHAR(50)'''''''');
        SET @ObjectName = @EventData.value(''''''''(/EVENT_INSTANCE/ObjectName)[1]'''''''', ''''''''NVARCHAR(128)'''''''');
        SET @SchemaName = @EventData.value(''''''''(/EVENT_INSTANCE/SchemaName)[1]'''''''', ''''''''NVARCHAR(128)'''''''');

        BEGIN TRY
            INSERT INTO ' + @MonitoringDBReference + ' (
                ServerName, DatabaseName, SchemaName, ObjectName, EventType, EventTime
            )
            VALUES (
                @@SERVERNAME,
                DB_NAME(),
                @SchemaName,
                @ObjectName,
                @EventType,
                GETUTCDATE()
            );
        END TRY
        BEGIN CATCH
            -- Silent failure to avoid blocking DDL operations
            -- Do NOT re-throw error
        END CATCH;
    END;
    '''')';  -- Close the EXEC statement
    ';

    -- Create temp table to store databases to process
    CREATE TABLE #DatabasesToProcess (
        DatabaseName NVARCHAR(128),
        ProcessOrder INT
    );

    -- Populate list of databases to process
    INSERT INTO #DatabasesToProcess (DatabaseName, ProcessOrder)
    SELECT
        name,
        ROW_NUMBER() OVER (ORDER BY name)
    FROM sys.databases
    WHERE state = 0 -- ONLINE only
      AND is_read_only = 0 -- Not read-only
      AND database_id > 4 -- Exclude system databases (master, tempdb, model, msdb) unless requested
      AND (@IncludeSystemDatabases = 1 OR name NOT IN ('master', 'tempdb', 'model', 'msdb'))
      AND (
          @ExcludeDatabases IS NULL
          OR name NOT IN (
              SELECT LTRIM(RTRIM(value))
              FROM STRING_SPLIT(@ExcludeDatabases, ',')
          )
      );

    DECLARE @TotalDatabases INT;
    SELECT @TotalDatabases = COUNT(*) FROM #DatabasesToProcess;

    PRINT CONCAT('Databases to process: ', @TotalDatabases);
    PRINT '';

    IF @TestOnly = 1
    BEGIN
        PRINT 'TEST MODE: Showing databases that would be processed:';
        PRINT '';
        SELECT DatabaseName FROM #DatabasesToProcess ORDER BY ProcessOrder;
        PRINT '';
        PRINT 'No triggers deployed (test mode).';
    END
    ELSE
    BEGIN
        -- Deploy trigger to each database
        DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT DatabaseName FROM #DatabasesToProcess ORDER BY ProcessOrder;

        OPEN db_cursor;
        FETCH NEXT FROM db_cursor INTO @CurrentDB;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            BEGIN TRY
                PRINT CONCAT('Deploying trigger to: ', @CurrentDB);

                -- Build USE statement + trigger SQL
                SET @SQL = N'USE ' + QUOTENAME(@CurrentDB) + '; ' + @TriggerSQL;

                -- Execute deployment
                EXEC sp_executesql @SQL;

                PRINT CONCAT('  ✓ SUCCESS: Trigger deployed to ', @CurrentDB);
                SET @DeployedCount = @DeployedCount + 1;
            END TRY
            BEGIN CATCH
                PRINT CONCAT('  ✗ ERROR: Failed to deploy trigger to ', @CurrentDB);
                PRINT CONCAT('    Error: ', ERROR_MESSAGE());
                SET @ErrorCount = @ErrorCount + 1;
            END CATCH;

            FETCH NEXT FROM db_cursor INTO @CurrentDB;
        END;

        CLOSE db_cursor;
        DEALLOCATE db_cursor;
    END;

    -- Cleanup
    DROP TABLE #DatabasesToProcess;

    -- Summary
    PRINT '';
    PRINT '========================================';
    PRINT 'Deployment Summary';
    PRINT '========================================';
    IF @TestOnly = 1
    BEGIN
        PRINT CONCAT('Databases identified: ', @TotalDatabases);
        PRINT 'Mode: TEST ONLY (no deployment)';
        PRINT '';
        PRINT 'Run without @TestOnly = 1 to deploy triggers.';
    END
    ELSE
    BEGIN
        PRINT CONCAT('Databases processed: ', @TotalDatabases);
        PRINT CONCAT('Successfully deployed: ', @DeployedCount);
        PRINT CONCAT('Errors: ', @ErrorCount);
        PRINT CONCAT('Skipped: ', @SkippedCount);
        PRINT '';

        IF @DeployedCount > 0
        BEGIN
            PRINT 'Trigger deployed: trg_DDL_SchemaChangeDetection';
            PRINT CONCAT('Logging to: ', @MonitoringDBReference);
        END;

        IF @ErrorCount > 0
            PRINT 'WARNING: Some databases failed. Check error messages above.';
    END;
    PRINT '========================================';

    -- Return result set
    SELECT
        @ServerName AS ServerName,
        @TotalDatabases AS TotalDatabases,
        @DeployedCount AS DeployedCount,
        @ErrorCount AS ErrorCount,
        @SkippedCount AS SkippedCount,
        @MonitoringDBReference AS LoggingDestination;
END;
GO

PRINT 'Created procedure: master.dbo.usp_DeploySchemaChangeTriggersToAllDatabases';
GO

-- =============================================
-- Usage Examples
-- =============================================

PRINT '';
PRINT '========================================';
PRINT 'Usage Examples';
PRINT '========================================';
PRINT '';
PRINT '-- Test mode (see what would be deployed):';
PRINT 'EXEC master.dbo.usp_DeploySchemaChangeTriggersToAllDatabases @TestOnly = 1;';
PRINT '';
PRINT '-- Deploy to all user databases:';
PRINT 'EXEC master.dbo.usp_DeploySchemaChangeTriggersToAllDatabases;';
PRINT '';
PRINT '-- Deploy to all databases EXCEPT specific ones:';
PRINT 'EXEC master.dbo.usp_DeploySchemaChangeTriggersToAllDatabases @ExcludeDatabases = ''TempDB,TestDB'';';
PRINT '';
PRINT '-- Deploy when MonitoringDB is on a different server (via linked server):';
PRINT 'EXEC master.dbo.usp_DeploySchemaChangeTriggersToAllDatabases';
PRINT '    @MonitoringServer = ''MONITORING_SERVER_NAME'',';
PRINT '    @MonitoringDatabase = ''MonitoringDB'';';
PRINT '';
PRINT '-- Include system databases (NOT recommended):';
PRINT 'EXEC master.dbo.usp_DeploySchemaChangeTriggersToAllDatabases @IncludeSystemDatabases = 1;';
PRINT '';
PRINT '========================================';
GO

-- =============================================
-- Run Test Mode (show what would be deployed)
-- =============================================

PRINT '';
PRINT 'Running in TEST MODE to show databases...';
PRINT '';
GO

EXEC master.dbo.usp_DeploySchemaChangeTriggersToAllDatabases @TestOnly = 1;
GO

-- =============================================
-- Companion Procedure: Verify Trigger Deployment
-- =============================================

IF OBJECT_ID('master.dbo.usp_VerifySchemaChangeTriggers', 'P') IS NOT NULL
    DROP PROCEDURE master.dbo.usp_VerifySchemaChangeTriggers;
GO

CREATE PROCEDURE master.dbo.usp_VerifySchemaChangeTriggers
AS
BEGIN
    SET NOCOUNT ON;

    PRINT '========================================';
    PRINT 'Schema Change Trigger Verification';
    PRINT '========================================';
    PRINT '';

    -- Check all user databases for trigger
    SELECT
        d.name AS DatabaseName,
        CASE
            WHEN t.name IS NOT NULL THEN 'Deployed'
            ELSE 'Missing'
        END AS TriggerStatus,
        d.state_desc AS DatabaseState,
        d.is_read_only AS IsReadOnly
    FROM sys.databases d
    LEFT JOIN (
        SELECT
            DB_NAME(database_id) AS DatabaseName,
            t.name
        FROM sys.triggers t
        WHERE t.parent_class_desc = 'DATABASE'
          AND t.name = 'trg_DDL_SchemaChangeDetection'
    ) t ON d.name = t.DatabaseName
    WHERE d.database_id > 4 -- Exclude system databases
      AND d.state = 0 -- ONLINE only
    ORDER BY
        CASE WHEN t.name IS NULL THEN 0 ELSE 1 END, -- Missing first
        d.name;

    -- Summary
    DECLARE @TotalDatabases INT, @DeployedCount INT, @MissingCount INT;

    SELECT @TotalDatabases = COUNT(*)
    FROM sys.databases
    WHERE database_id > 4 AND state = 0;

    SELECT @DeployedCount = COUNT(*)
    FROM sys.databases d
    WHERE d.database_id > 4
      AND d.state = 0
      AND EXISTS (
          SELECT 1
          FROM sys.triggers t
          WHERE t.parent_class_desc = 'DATABASE'
            AND t.name = 'trg_DDL_SchemaChangeDetection'
            AND DB_NAME(t.database_id) = d.name
      );

    SET @MissingCount = @TotalDatabases - @DeployedCount;

    PRINT '';
    PRINT CONCAT('Total user databases: ', @TotalDatabases);
    PRINT CONCAT('Triggers deployed: ', @DeployedCount);
    PRINT CONCAT('Triggers missing: ', @MissingCount);

    IF @MissingCount > 0
    BEGIN
        PRINT '';
        PRINT 'Run the following to deploy missing triggers:';
        PRINT 'EXEC master.dbo.usp_DeploySchemaChangeTriggersToAllDatabases;';
    END;
END;
GO

PRINT 'Created procedure: master.dbo.usp_VerifySchemaChangeTriggers';
GO

PRINT '';
PRINT '========================================';
PRINT 'Auto-Distribute Procedures Created';
PRINT '========================================';
PRINT 'Procedures created in master database:';
PRINT '  1. usp_DeploySchemaChangeTriggersToAllDatabases - Deploy triggers';
PRINT '  2. usp_VerifySchemaChangeTriggers - Verify deployment';
PRINT '';
PRINT 'Run verification:';
PRINT '  EXEC master.dbo.usp_VerifySchemaChangeTriggers;';
PRINT '';
PRINT 'Deploy triggers to all user databases:';
PRINT '  EXEC master.dbo.usp_DeploySchemaChangeTriggersToAllDatabases;';
PRINT '========================================';
GO
