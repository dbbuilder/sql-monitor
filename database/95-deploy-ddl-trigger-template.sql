-- =====================================================
-- DDL Trigger Template for Monitored SQL Servers
-- Deploy this on EACH monitored SQL Server instance
-- =====================================================
-- This script creates a server-level DDL trigger that captures
-- all DDL events and sends them to the central MonitoringDB
-- =====================================================

-- =====================================================
-- CONFIGURATION: Update these variables before deployment
-- =====================================================
DECLARE @MonitoringDBServer NVARCHAR(128) = 'sqltest.schoolvision.net,14333';  -- MonitoringDB server
DECLARE @MonitoringDBName NVARCHAR(128) = 'MonitoringDB';                       -- MonitoringDB database name
DECLARE @LinkedServerName NVARCHAR(128) = 'MONITORING_DB';                      -- Linked server name to create

-- =====================================================
-- SECTION 1: Create Linked Server to MonitoringDB
-- =====================================================
-- This allows the DDL trigger to send events to the central MonitoringDB

IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = @LinkedServerName)
BEGIN
    EXEC sp_addlinkedserver
        @server = @LinkedServerName,
        @srvproduct = N'',
        @provider = N'SQLNCLI',
        @datasrc = @MonitoringDBServer;

    -- Configure linked server options
    EXEC sp_serveroption @LinkedServerName, 'rpc', 'true';
    EXEC sp_serveroption @LinkedServerName, 'rpc out', 'true';

    PRINT 'Created linked server: ' + @LinkedServerName;
END
ELSE
BEGIN
    PRINT 'Linked server already exists: ' + @LinkedServerName;
END
GO

-- =====================================================
-- SECTION 2: Create DDL Audit Staging Table (Local)
-- =====================================================
-- Stores DDL events locally in case MonitoringDB is unavailable
-- Events are forwarded to MonitoringDB by a job

USE master;
GO

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'DBATools')
BEGIN
    CREATE DATABASE DBATools;
    PRINT 'Created database: DBATools';
END
GO

USE DBATools;
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'DDLAuditStaging' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    CREATE TABLE dbo.DDLAuditStaging (
        StagingID           BIGINT IDENTITY(1,1) PRIMARY KEY,
        EventTime           DATETIME2(7) NOT NULL DEFAULT SYSUTCDATETIME(),
        EventType           VARCHAR(50) NOT NULL,
        DatabaseName        NVARCHAR(128) NOT NULL,
        SchemaName          NVARCHAR(128) NULL,
        ObjectName          NVARCHAR(128) NULL,
        ObjectType          VARCHAR(50) NULL,
        LoginName           NVARCHAR(128) NOT NULL,
        UserName            NVARCHAR(128) NULL,
        HostName            NVARCHAR(128) NULL,
        ApplicationName     NVARCHAR(256) NULL,
        IPAddress           VARCHAR(45) NULL,
        SQLCommand          NVARCHAR(MAX) NOT NULL,
        SPID                INT NULL,
        TransactionID       BIGINT NULL,
        NestLevel           INT NULL,
        IsForwarded         BIT NOT NULL DEFAULT 0,
        ForwardedAt         DATETIME2(7) NULL,
        ForwardError        NVARCHAR(MAX) NULL
    );

    CREATE NONCLUSTERED INDEX IX_DDLAuditStaging_IsForwarded
    ON dbo.DDLAuditStaging (IsForwarded, EventTime)
    WHERE IsForwarded = 0;

    PRINT 'Created table: DBATools.dbo.DDLAuditStaging';
END
GO

-- =====================================================
-- SECTION 3: Create Server-Level DDL Trigger
-- =====================================================

USE master;
GO

-- Drop existing trigger if exists
IF EXISTS (SELECT 1 FROM sys.server_triggers WHERE name = 'trg_DDL_Audit_AllEvents')
BEGIN
    DROP TRIGGER trg_DDL_Audit_AllEvents ON ALL SERVER;
    PRINT 'Dropped existing trigger: trg_DDL_Audit_AllEvents';
END
GO

CREATE TRIGGER trg_DDL_Audit_AllEvents
ON ALL SERVER
FOR DDL_DATABASE_LEVEL_EVENTS
AS
BEGIN
    SET NOCOUNT ON;

    -- Skip if this is a system operation or specific excluded operations
    IF SYSTEM_USER IN ('NT AUTHORITY\SYSTEM', 'NT SERVICE\MSSQLSERVER')
        RETURN;

    -- Parse event data
    DECLARE @EventData XML = EVENTDATA();
    DECLARE @EventType VARCHAR(50);
    DECLARE @DatabaseName NVARCHAR(128);
    DECLARE @SchemaName NVARCHAR(128);
    DECLARE @ObjectName NVARCHAR(128);
    DECLARE @ObjectType VARCHAR(50);
    DECLARE @LoginName NVARCHAR(128);
    DECLARE @UserName NVARCHAR(128);
    DECLARE @HostName NVARCHAR(128);
    DECLARE @ApplicationName NVARCHAR(256);
    DECLARE @SQLCommand NVARCHAR(MAX);
    DECLARE @SPID INT;
    DECLARE @IPAddress VARCHAR(45);

    -- Extract event details
    SET @EventType = @EventData.value('(/EVENT_INSTANCE/EventType)[1]', 'VARCHAR(50)');
    SET @DatabaseName = @EventData.value('(/EVENT_INSTANCE/DatabaseName)[1]', 'NVARCHAR(128)');
    SET @SchemaName = @EventData.value('(/EVENT_INSTANCE/SchemaName)[1]', 'NVARCHAR(128)');
    SET @ObjectName = @EventData.value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(128)');
    SET @ObjectType = @EventData.value('(/EVENT_INSTANCE/ObjectType)[1]', 'VARCHAR(50)');
    SET @LoginName = @EventData.value('(/EVENT_INSTANCE/LoginName)[1]', 'NVARCHAR(128)');
    SET @UserName = @EventData.value('(/EVENT_INSTANCE/UserName)[1]', 'NVARCHAR(128)');
    SET @SQLCommand = @EventData.value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'NVARCHAR(MAX)');
    SET @SPID = @EventData.value('(/EVENT_INSTANCE/SPID)[1]', 'INT');

    -- Get additional context
    SET @HostName = HOST_NAME();
    SET @ApplicationName = APP_NAME();

    -- Get client IP address
    SELECT @IPAddress = client_net_address
    FROM sys.dm_exec_connections
    WHERE session_id = @@SPID;

    -- Skip certain operations (statistics updates, temp objects, etc.)
    IF @EventType IN ('UPDATE_STATISTICS', 'CREATE_STATISTICS')
        AND @ObjectName LIKE '#%'  -- Temp objects
        RETURN;

    -- Skip system databases for certain operations
    IF @DatabaseName IN ('tempdb') AND @EventType NOT IN ('CREATE_TABLE', 'DROP_TABLE')
        RETURN;

    BEGIN TRY
        -- Insert into local staging table
        INSERT INTO DBATools.dbo.DDLAuditStaging (
            EventTime,
            EventType,
            DatabaseName,
            SchemaName,
            ObjectName,
            ObjectType,
            LoginName,
            UserName,
            HostName,
            ApplicationName,
            IPAddress,
            SQLCommand,
            SPID,
            TransactionID,
            NestLevel
        )
        VALUES (
            SYSUTCDATETIME(),
            @EventType,
            @DatabaseName,
            @SchemaName,
            @ObjectName,
            @ObjectType,
            @LoginName,
            @UserName,
            @HostName,
            @ApplicationName,
            @IPAddress,
            @SQLCommand,
            @SPID,
            CURRENT_TRANSACTION_ID(),
            TRIGGER_NESTLEVEL()
        );
    END TRY
    BEGIN CATCH
        -- Silently fail - don't block DDL operations
        -- Errors will be logged in SQL Server error log
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('DDL Audit trigger error: %s', 10, 1, @ErrorMessage) WITH LOG;
    END CATCH
END
GO

PRINT 'Created server trigger: trg_DDL_Audit_AllEvents';
GO

-- =====================================================
-- SECTION 4: Create Procedure to Forward DDL Events
-- =====================================================

USE DBATools;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ForwardDDLEvents
    @BatchSize INT = 100,
    @RetryMinutes INT = 5
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ServerName NVARCHAR(128) = @@SERVERNAME;
    DECLARE @ForwardedCount INT = 0;
    DECLARE @ErrorCount INT = 0;

    -- Get events to forward
    DECLARE @EventsToForward TABLE (
        StagingID BIGINT,
        EventTime DATETIME2(7),
        EventType VARCHAR(50),
        DatabaseName NVARCHAR(128),
        SchemaName NVARCHAR(128),
        ObjectName NVARCHAR(128),
        ObjectType VARCHAR(50),
        LoginName NVARCHAR(128),
        UserName NVARCHAR(128),
        HostName NVARCHAR(128),
        ApplicationName NVARCHAR(256),
        IPAddress VARCHAR(45),
        SQLCommand NVARCHAR(MAX),
        SPID INT,
        TransactionID BIGINT,
        NestLevel INT
    );

    INSERT INTO @EventsToForward
    SELECT TOP (@BatchSize)
        StagingID,
        EventTime,
        EventType,
        DatabaseName,
        SchemaName,
        ObjectName,
        ObjectType,
        LoginName,
        UserName,
        HostName,
        ApplicationName,
        IPAddress,
        SQLCommand,
        SPID,
        TransactionID,
        NestLevel
    FROM dbo.DDLAuditStaging
    WHERE IsForwarded = 0
      AND (ForwardError IS NULL OR EventTime < DATEADD(MINUTE, -@RetryMinutes, SYSUTCDATETIME()))
    ORDER BY EventTime;

    IF NOT EXISTS (SELECT 1 FROM @EventsToForward)
    BEGIN
        PRINT 'No events to forward';
        RETURN 0;
    END

    -- Forward each event
    DECLARE @StagingID BIGINT;
    DECLARE @EventTime DATETIME2(7);
    DECLARE @EventType VARCHAR(50);
    DECLARE @DatabaseName NVARCHAR(128);
    DECLARE @SchemaName NVARCHAR(128);
    DECLARE @ObjectName NVARCHAR(128);
    DECLARE @ObjectType VARCHAR(50);
    DECLARE @LoginName NVARCHAR(128);
    DECLARE @UserName NVARCHAR(128);
    DECLARE @HostName NVARCHAR(128);
    DECLARE @ApplicationName NVARCHAR(256);
    DECLARE @IPAddress VARCHAR(45);
    DECLARE @SQLCommand NVARCHAR(MAX);
    DECLARE @SPID INT;
    DECLARE @TransactionID BIGINT;
    DECLARE @NestLevel INT;

    DECLARE forward_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT * FROM @EventsToForward;

    OPEN forward_cursor;
    FETCH NEXT FROM forward_cursor INTO
        @StagingID, @EventTime, @EventType, @DatabaseName, @SchemaName, @ObjectName,
        @ObjectType, @LoginName, @UserName, @HostName, @ApplicationName, @IPAddress,
        @SQLCommand, @SPID, @TransactionID, @NestLevel;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            -- Forward to MonitoringDB via linked server
            EXEC [MONITORING_DB].[MonitoringDB].[dbo].[usp_LogDDLEvent]
                @ServerName = @ServerName,
                @EventType = @EventType,
                @DatabaseName = @DatabaseName,
                @SchemaName = @SchemaName,
                @ObjectName = @ObjectName,
                @ObjectType = @ObjectType,
                @LoginName = @LoginName,
                @UserName = @UserName,
                @HostName = @HostName,
                @ApplicationName = @ApplicationName,
                @IPAddress = @IPAddress,
                @SQLCommand = @SQLCommand,
                @SPID = @SPID,
                @TransactionID = @TransactionID,
                @NestLevel = @NestLevel,
                @IsAutomated = 0;

            -- Mark as forwarded
            UPDATE dbo.DDLAuditStaging
            SET IsForwarded = 1,
                ForwardedAt = SYSUTCDATETIME(),
                ForwardError = NULL
            WHERE StagingID = @StagingID;

            SET @ForwardedCount = @ForwardedCount + 1;
        END TRY
        BEGIN CATCH
            -- Log error but continue
            UPDATE dbo.DDLAuditStaging
            SET ForwardError = ERROR_MESSAGE()
            WHERE StagingID = @StagingID;

            SET @ErrorCount = @ErrorCount + 1;
        END CATCH

        FETCH NEXT FROM forward_cursor INTO
            @StagingID, @EventTime, @EventType, @DatabaseName, @SchemaName, @ObjectName,
            @ObjectType, @LoginName, @UserName, @HostName, @ApplicationName, @IPAddress,
            @SQLCommand, @SPID, @TransactionID, @NestLevel;
    END

    CLOSE forward_cursor;
    DEALLOCATE forward_cursor;

    PRINT 'Forwarded ' + CAST(@ForwardedCount AS VARCHAR) + ' events, ' +
          CAST(@ErrorCount AS VARCHAR) + ' errors';

    RETURN 0;
END
GO

PRINT 'Created procedure: DBATools.dbo.usp_ForwardDDLEvents';
GO

-- =====================================================
-- SECTION 5: Create SQL Agent Job to Forward Events
-- =====================================================

USE msdb;
GO

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'DDL Audit - Forward to MonitoringDB')
BEGIN
    EXEC msdb.dbo.sp_add_job
        @job_name = N'DDL Audit - Forward to MonitoringDB',
        @enabled = 1,
        @description = N'Forwards local DDL audit events to the central MonitoringDB',
        @category_name = N'Database Maintenance',
        @owner_login_name = N'sa';

    EXEC msdb.dbo.sp_add_jobstep
        @job_name = N'DDL Audit - Forward to MonitoringDB',
        @step_name = N'Forward DDL Events',
        @step_id = 1,
        @subsystem = N'TSQL',
        @command = N'EXEC dbo.usp_ForwardDDLEvents @BatchSize = 500, @RetryMinutes = 5;',
        @database_name = N'DBATools',
        @on_success_action = 1,
        @on_fail_action = 2;

    EXEC msdb.dbo.sp_add_jobschedule
        @job_name = N'DDL Audit - Forward to MonitoringDB',
        @name = N'Every 1 minute',
        @freq_type = 4,
        @freq_interval = 1,
        @freq_subday_type = 4,
        @freq_subday_interval = 1,
        @active_start_time = 0;

    EXEC msdb.dbo.sp_add_jobserver
        @job_name = N'DDL Audit - Forward to MonitoringDB',
        @server_name = N'(local)';

    PRINT 'Created SQL Agent job: DDL Audit - Forward to MonitoringDB';
END
GO

-- =====================================================
-- SECTION 6: Cleanup Old Staged Events
-- =====================================================

USE DBATools;
GO

CREATE OR ALTER PROCEDURE dbo.usp_CleanupDDLAuditStaging
    @RetentionDays INT = 7
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CutoffDate DATETIME2(7) = DATEADD(DAY, -@RetentionDays, SYSUTCDATETIME());
    DECLARE @DeletedCount INT;

    DELETE FROM dbo.DDLAuditStaging
    WHERE IsForwarded = 1
      AND ForwardedAt < @CutoffDate;

    SET @DeletedCount = @@ROWCOUNT;

    PRINT 'Deleted ' + CAST(@DeletedCount AS VARCHAR) + ' old staged DDL events';

    RETURN 0;
END
GO

-- Add cleanup step to the forwarding job
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'DDL Audit - Forward to MonitoringDB')
BEGIN
    -- Check if cleanup step already exists
    IF NOT EXISTS (
        SELECT 1 FROM msdb.dbo.sysjobsteps
        WHERE job_id = (SELECT job_id FROM msdb.dbo.sysjobs WHERE name = 'DDL Audit - Forward to MonitoringDB')
          AND step_name = 'Cleanup Old Staged Events'
    )
    BEGIN
        EXEC msdb.dbo.sp_add_jobstep
            @job_name = N'DDL Audit - Forward to MonitoringDB',
            @step_name = N'Cleanup Old Staged Events',
            @step_id = 2,
            @subsystem = N'TSQL',
            @command = N'EXEC dbo.usp_CleanupDDLAuditStaging @RetentionDays = 7;',
            @database_name = N'DBATools',
            @on_success_action = 1,
            @on_fail_action = 2;

        PRINT 'Added cleanup step to job: DDL Audit - Forward to MonitoringDB';
    END
END
GO

PRINT '';
PRINT '=========================================';
PRINT 'DDL Trigger Deployment Complete!';
PRINT '=========================================';
PRINT '';
PRINT 'The following components have been created:';
PRINT '1. Linked server to MonitoringDB (MONITORING_DB)';
PRINT '2. Local staging table (DBATools.dbo.DDLAuditStaging)';
PRINT '3. Server-level DDL trigger (trg_DDL_Audit_AllEvents)';
PRINT '4. Forwarding procedure (DBATools.dbo.usp_ForwardDDLEvents)';
PRINT '5. SQL Agent job to forward events every minute';
PRINT '6. Cleanup procedure for old staged events';
PRINT '';
PRINT 'IMPORTANT: Update the linked server credentials if needed:';
PRINT '  EXEC sp_addlinkedsrvlogin @rmtsrvname = ''MONITORING_DB'',';
PRINT '       @useself = ''false'', @rmtuser = ''monitor_user'', @rmtpassword = ''password'';';
PRINT '';
GO
