-- =============================================
-- Phase 1.25: DDL Trigger Template for Schema Change Detection
-- Part 3: Database-level DDL trigger to log schema changes
-- Created: 2025-10-26
--
-- DEPLOYMENT INSTRUCTIONS:
-- This trigger should be deployed to EACH monitored database (not MonitoringDB)
-- Replace {{MONITORING_SERVER}} and {{MONITORING_DATABASE}} with actual values
--
-- Example for local deployment:
--   USE [YourDatabase];
--   -- Then execute this script
-- =============================================

-- NOTE: Execute this script while connected to the MONITORED database (not MonitoringDB)
-- Example: USE [MonitoringDB]; GO  -- (this is the database being monitored)

SET QUOTED_IDENTIFIER ON;
GO

PRINT 'Creating DDL trigger for schema change detection...';
PRINT 'Current database: ' + DB_NAME();
PRINT '';
GO

-- =============================================
-- Drop existing trigger if it exists
-- =============================================

IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'trg_DDL_SchemaChangeDetection' AND parent_class_desc = 'DATABASE')
BEGIN
    DROP TRIGGER trg_DDL_SchemaChangeDetection ON DATABASE;
    PRINT 'Dropped existing trigger: trg_DDL_SchemaChangeDetection';
END;
GO

-- =============================================
-- Create DDL Trigger for Schema Change Detection
-- =============================================

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
    DECLARE @ServerName NVARCHAR(128);
    DECLARE @DatabaseName NVARCHAR(128);

    -- Capture event data
    SET @EventData = EVENTDATA();
    SET @EventType = @EventData.value('(/EVENT_INSTANCE/EventType)[1]', 'VARCHAR(50)');
    SET @ObjectName = @EventData.value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(128)');
    SET @SchemaName = @EventData.value('(/EVENT_INSTANCE/SchemaName)[1]', 'NVARCHAR(128)');
    SET @ServerName = @@SERVERNAME;
    SET @DatabaseName = DB_NAME();

    -- Log change to MonitoringDB
    -- IMPORTANT: Update server/database name to match your MonitoringDB location
    BEGIN TRY
        -- Option 1: If MonitoringDB is on same server (recommended)
        INSERT INTO [MonitoringDB].[dbo].[SchemaChangeLog] (
            ServerName, DatabaseName, SchemaName, ObjectName, EventType, EventTime
        )
        VALUES (
            @ServerName,
            @DatabaseName,
            @SchemaName,
            @ObjectName,
            @EventType,
            GETUTCDATE()
        );

        /* Option 2: If MonitoringDB is on a different server (via linked server)
        -- First create linked server, then use 4-part naming:
        INSERT INTO [LINKED_SERVER_NAME].[MonitoringDB].[dbo].[SchemaChangeLog] (
            ServerName, DatabaseName, SchemaName, ObjectName, EventType, EventTime
        )
        VALUES (
            @ServerName,
            @DatabaseName,
            @SchemaName,
            @ObjectName,
            @EventType,
            GETUTCDATE()
        );
        */

        /* Option 3: If MonitoringDB is on a different server (via OPENROWSET)
        -- Requires Ad Hoc Distributed Queries enabled
        INSERT OPENROWSET(
            'SQLNCLI',
            'Server=MONITORING_SERVER;Database=MonitoringDB;Trusted_Connection=yes;',
            'SELECT ServerName, DatabaseName, SchemaName, ObjectName, EventType, EventTime FROM dbo.SchemaChangeLog'
        )
        VALUES (
            @ServerName,
            @DatabaseName,
            @SchemaName,
            @ObjectName,
            @EventType,
            GETUTCDATE()
        );
        */
    END TRY
    BEGIN CATCH
        -- Silent failure to avoid breaking DDL operations
        -- In production, consider logging to local error table
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();

        -- Optional: Log to local error table (create if needed)
        /*
        IF OBJECT_ID('dbo.DDL_Trigger_Errors', 'U') IS NOT NULL
        BEGIN
            INSERT INTO dbo.DDL_Trigger_Errors (ErrorTime, ErrorMessage, EventType, ObjectName)
            VALUES (GETUTCDATE(), @ErrorMessage, @EventType, @ObjectName);
        END;
        */

        -- Do NOT re-throw error to avoid blocking DDL operations
        -- RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
    END CATCH;
END;
GO

PRINT 'Created DDL trigger: trg_DDL_SchemaChangeDetection';
GO

-- =============================================
-- Test the trigger
-- =============================================

PRINT '';
PRINT '========================================';
PRINT 'Testing DDL Trigger';
PRINT '========================================';
PRINT '';

-- Count schema change log entries before test
DECLARE @CountBefore INT;
SELECT @CountBefore = COUNT(*)
FROM [MonitoringDB].[dbo].[SchemaChangeLog]
WHERE DatabaseName = DB_NAME();

PRINT CONCAT('SchemaChangeLog entries before test: ', @CountBefore);

-- Create a test table (this should trigger the DDL trigger)
IF OBJECT_ID('dbo.DDL_Trigger_Test_Table', 'U') IS NOT NULL
    DROP TABLE dbo.DDL_Trigger_Test_Table;

CREATE TABLE dbo.DDL_Trigger_Test_Table (
    TestID INT PRIMARY KEY,
    TestValue NVARCHAR(50)
);

PRINT 'Created test table: dbo.DDL_Trigger_Test_Table';

-- Wait briefly for trigger to complete
WAITFOR DELAY '00:00:01';

-- Check if trigger logged the event
DECLARE @CountAfter INT;
SELECT @CountAfter = COUNT(*)
FROM [MonitoringDB].[dbo].[SchemaChangeLog]
WHERE DatabaseName = DB_NAME();

PRINT CONCAT('SchemaChangeLog entries after test: ', @CountAfter);
PRINT '';

IF @CountAfter > @CountBefore
    PRINT '✓ SUCCESS: DDL trigger is working correctly!';
ELSE
    PRINT '✗ FAILURE: DDL trigger did not log the CREATE TABLE event. Check trigger definition and MonitoringDB connectivity.';

-- View recent log entries
PRINT '';
PRINT 'Recent schema change log entries for this database:';
SELECT TOP 5
    EventType,
    SchemaName,
    ObjectName,
    EventTime,
    ProcessedAt
FROM [MonitoringDB].[dbo].[SchemaChangeLog]
WHERE DatabaseName = DB_NAME()
ORDER BY EventTime DESC;

-- Cleanup test table
DROP TABLE dbo.DDL_Trigger_Test_Table;
PRINT '';
PRINT 'Test table dropped.';

PRINT '';
PRINT '========================================';
PRINT 'DDL Trigger Deployment Summary';
PRINT '========================================';
PRINT CONCAT('Database: ', DB_NAME());
PRINT 'Trigger: trg_DDL_SchemaChangeDetection';
PRINT 'Status: Active';
PRINT '';
PRINT 'Monitored Events:';
PRINT '  - CREATE/ALTER/DROP TABLE';
PRINT '  - CREATE/ALTER/DROP PROCEDURE';
PRINT '  - CREATE/ALTER/DROP VIEW';
PRINT '  - CREATE/ALTER/DROP FUNCTION';
PRINT '  - CREATE/ALTER/DROP INDEX';
PRINT '  - CREATE/ALTER/DROP TRIGGER';
PRINT '';
PRINT 'Change Log Destination: [MonitoringDB].[dbo].[SchemaChangeLog]';
PRINT '';
PRINT 'IMPORTANT: Deploy this trigger to ALL monitored databases!';
PRINT '========================================';
GO
