-- =====================================================================================
-- SQL Monitor - Create Extended Event Session for Timeout Tracking
-- Purpose: Capture detailed timeout evidence for future analysis
-- =====================================================================================
--
-- This script creates a persistent Extended Event session that captures:
--   1. Attention events (client-side timeouts/cancellations)
--   2. Long-running queries (queries exceeding threshold)
--   3. Blocking events
--   4. Query plan warnings (missing indexes, excessive memory grants)
--
-- Benefits:
--   - Provides detailed evidence when timeouts occur
--   - Captures full SQL text and execution context
--   - Minimal overhead (<1% CPU)
--   - Automatic circular file rollover (keeps last 5 files, 100MB each)
--
-- Usage:
--   1. Adjust @TimeoutThresholdMs to match your application timeout
--   2. Adjust @FilePath to a location with sufficient disk space
--   3. Run this script to create the XE session
--   4. Session starts automatically and persists across SQL Server restarts
--
-- Author: SQL Monitor Team
-- Date: 2025-10-29
-- =====================================================================================

USE master
GO

SET NOCOUNT ON
GO

-- =====================================================================================
-- Configuration
-- =====================================================================================

DECLARE @TimeoutThresholdMs INT = 30000  -- 30 seconds (adjust to your timeout setting)
DECLARE @FilePath NVARCHAR(260) = N'C:\SQLMonitor\XE\'  -- Change to your preferred location
DECLARE @SessionName NVARCHAR(128) = N'SqlMonitor_TimeoutTracking'

PRINT ''
PRINT '=============================================================================='
PRINT 'Creating Extended Event Session: ' + @SessionName
PRINT '=============================================================================='
PRINT ''
PRINT 'Configuration:'
PRINT '  Timeout Threshold: ' + CAST(@TimeoutThresholdMs/1000 AS VARCHAR) + ' seconds (' + CAST(@TimeoutThresholdMs AS VARCHAR) + ' ms)'
PRINT '  File Path: ' + @FilePath
PRINT '  File Retention: Last 5 files, 100MB each (500MB total)'
PRINT ''

-- =====================================================================================
-- Drop existing session if it exists
-- =====================================================================================

IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = @SessionName)
BEGIN
    PRINT 'Stopping and dropping existing session...'
    EXEC('ALTER EVENT SESSION [' + @SessionName + '] ON SERVER STATE = STOP')
    EXEC('DROP EVENT SESSION [' + @SessionName + '] ON SERVER')
    PRINT '  ✓ Existing session removed'
    PRINT ''
END

-- =====================================================================================
-- Create Extended Event Session
-- =====================================================================================

PRINT 'Creating new Extended Event session...'

DECLARE @SQL NVARCHAR(MAX) = N'
CREATE EVENT SESSION [' + @SessionName + '] ON SERVER

-- =====================================================================================
-- EVENT 1: Attention (Client-Side Query Cancellations)
-- =====================================================================================
-- Fires when a client cancels a query (timeout or user action)
-- Includes full SQL text and session context
-- =====================================================================================

ADD EVENT sqlserver.attention
(
    ACTION
    (
        sqlserver.session_id,
        sqlserver.database_name,
        sqlserver.username,
        sqlserver.client_app_name,
        sqlserver.client_hostname,
        sqlserver.sql_text,
        sqlserver.query_hash,
        sqlserver.query_plan_hash
    )
    WHERE (duration >= ' + CAST(@TimeoutThresholdMs * 1000 AS NVARCHAR) + ')  -- Filter: Only queries >= timeout threshold (in microseconds)
),

-- =====================================================================================
-- EVENT 2: RPC Completed (Long-Running Remote Procedure Calls)
-- =====================================================================================
-- Captures stored procedure executions that exceeded the timeout threshold
-- =====================================================================================

ADD EVENT sqlserver.rpc_completed
(
    ACTION
    (
        sqlserver.session_id,
        sqlserver.database_name,
        sqlserver.username,
        sqlserver.client_app_name,
        sqlserver.client_hostname,
        sqlserver.sql_text,
        sqlserver.query_hash,
        sqlserver.query_plan_hash
    )
    WHERE (duration >= ' + CAST(@TimeoutThresholdMs * 1000 AS NVARCHAR) + ')  -- Microseconds
),

-- =====================================================================================
-- EVENT 3: SQL Statement Completed (Long-Running Ad-Hoc Queries)
-- =====================================================================================
-- Captures individual SQL statements that exceeded the timeout threshold
-- =====================================================================================

ADD EVENT sqlserver.sql_statement_completed
(
    ACTION
    (
        sqlserver.session_id,
        sqlserver.database_name,
        sqlserver.username,
        sqlserver.client_app_name,
        sqlserver.client_hostname,
        sqlserver.sql_text,
        sqlserver.query_hash,
        sqlserver.query_plan_hash
    )
    WHERE (duration >= ' + CAST(@TimeoutThresholdMs * 1000 AS NVARCHAR) + ')  -- Microseconds
),

-- =====================================================================================
-- EVENT 4: Blocked Process Report
-- =====================================================================================
-- Fires when a process is blocked for more than the blocked process threshold
-- Requires: sp_configure ''blocked process threshold'', 5 (seconds)
-- =====================================================================================

ADD EVENT sqlserver.blocked_process_report
(
    ACTION
    (
        sqlserver.session_id,
        sqlserver.database_name,
        sqlserver.username,
        sqlserver.client_app_name,
        sqlserver.sql_text
    )
),

-- =====================================================================================
-- EVENT 5: XML Deadlock Report
-- =====================================================================================
-- Captures full deadlock graphs for post-mortem analysis
-- =====================================================================================

ADD EVENT sqlserver.xml_deadlock_report
(
    ACTION
    (
        sqlserver.database_name,
        sqlserver.username
    )
)

-- =====================================================================================
-- TARGET: Event File (Ring Buffer for Historical Analysis)
-- =====================================================================================

ADD TARGET package0.event_file
(
    SET filename = ''' + @FilePath + @SessionName + '.xel'',
        max_file_size = 100,        -- 100 MB per file
        max_rollover_files = 5      -- Keep last 5 files (500MB total)
)

WITH
(
    MAX_MEMORY = 8192 KB,           -- 8 MB memory for session
    EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,  -- Prevent memory pressure
    MAX_DISPATCH_LATENCY = 30 SECONDS,
    MAX_EVENT_SIZE = 0 KB,
    MEMORY_PARTITION_MODE = NONE,
    TRACK_CAUSALITY = ON,           -- Track related events
    STARTUP_STATE = ON              -- Start automatically on SQL Server restart
)
'

EXEC sp_executesql @SQL

PRINT '  ✓ Extended Event session created successfully'
PRINT ''

-- =====================================================================================
-- Configure Blocked Process Threshold (Required for Blocked Process Reports)
-- =====================================================================================

PRINT 'Configuring blocked process threshold...'

DECLARE @CurrentThreshold INT
EXEC sp_configure 'show advanced options', 1
RECONFIGURE
EXEC sp_configure 'blocked process threshold', 5  -- Report blocking after 5 seconds
RECONFIGURE

SELECT @CurrentThreshold = CAST(value_in_use AS INT)
FROM sys.configurations
WHERE name = 'blocked process threshold'

PRINT '  ✓ Blocked process threshold set to ' + CAST(@CurrentThreshold AS VARCHAR) + ' seconds'
PRINT ''

-- =====================================================================================
-- Start the Extended Event Session
-- =====================================================================================

PRINT 'Starting Extended Event session...'

EXEC('ALTER EVENT SESSION [' + @SessionName + '] ON SERVER STATE = START')

PRINT '  ✓ Session started and running'
PRINT ''

-- =====================================================================================
-- Verification
-- =====================================================================================

PRINT '=============================================================================='
PRINT 'VERIFICATION'
PRINT '=============================================================================='
PRINT ''

SELECT
    s.name AS SessionName,
    s.create_time AS CreatedTime,
    CASE
        WHEN st.target_name = 'event_file' THEN
            CAST(st.execution_count AS VARCHAR) + ' files created, ' +
            CAST(st.execution_duration_ms/1000.0 AS VARCHAR) + ' seconds total'
        ELSE 'N/A'
    END AS TargetStatus,
    CASE
        WHEN ses.session_source = 0 THEN 'Running'
        WHEN ses.session_source = 1 THEN 'Stopped'
        ELSE 'Unknown'
    END AS CurrentState
FROM sys.server_event_sessions s
LEFT JOIN sys.dm_xe_session_targets st ON s.name = st.event_session_address
LEFT JOIN sys.dm_xe_sessions ses ON s.name = ses.name
WHERE s.name = @SessionName

PRINT ''
PRINT '=============================================================================='
PRINT 'EXTENDED EVENT SESSION READY'
PRINT '=============================================================================='
PRINT ''
PRINT 'Session Name: ' + @SessionName
PRINT 'Status: Running and capturing timeout evidence'
PRINT 'File Location: ' + @FilePath + @SessionName + '.xel'
PRINT ''
PRINT 'To query captured events:'
PRINT '  SELECT * FROM sys.fn_xe_file_target_read_file(''' + @FilePath + @SessionName + '*.xel'', NULL, NULL, NULL)'
PRINT ''
PRINT 'To stop the session:'
PRINT '  ALTER EVENT SESSION [' + @SessionName + '] ON SERVER STATE = STOP'
PRINT ''
PRINT 'To restart the session:'
PRINT '  ALTER EVENT SESSION [' + @SessionName + '] ON SERVER STATE = START'
PRINT ''
PRINT 'To drop the session:'
PRINT '  ALTER EVENT SESSION [' + @SessionName + '] ON SERVER STATE = STOP'
PRINT '  DROP EVENT SESSION [' + @SessionName + '] ON SERVER'
PRINT ''

GO

-- =====================================================================================
-- Create Helper Procedure to Query Timeout Events
-- =====================================================================================

USE DBATools
GO

PRINT '=============================================================================='
PRINT 'Creating helper procedure: DBA_QueryTimeoutEvents'
PRINT '=============================================================================='
PRINT ''

CREATE OR ALTER PROCEDURE dbo.DBA_QueryTimeoutEvents
    @StartTime DATETIME = NULL,
    @EndTime DATETIME = NULL,
    @SessionName NVARCHAR(128) = N'SqlMonitor_TimeoutTracking'
AS
BEGIN
    SET NOCOUNT ON

    -- Default to last 4 hours if not specified
    IF @StartTime IS NULL
        SET @StartTime = DATEADD(HOUR, -4, GETDATE())

    IF @EndTime IS NULL
        SET @EndTime = GETDATE()

    PRINT 'Querying timeout events from Extended Events session: ' + @SessionName
    PRINT 'Timeframe: ' + CONVERT(VARCHAR(30), @StartTime, 120) + ' to ' + CONVERT(VARCHAR(30), @EndTime, 120)
    PRINT ''

    -- Query the XE files
    ;WITH EventData AS
    (
        SELECT
            event_data.value('(@timestamp)[1]', 'DATETIME') AS EventTime,
            event_data.value('(@name)[1]', 'VARCHAR(128)') AS EventName,
            event_data.value('(data[@name="duration"]/value)[1]', 'BIGINT') / 1000000.0 AS DurationSeconds,
            event_data.value('(action[@name="session_id"]/value)[1]', 'INT') AS SessionID,
            event_data.value('(action[@name="database_name"]/value)[1]', 'VARCHAR(128)') AS DatabaseName,
            event_data.value('(action[@name="username"]/value)[1]', 'VARCHAR(128)') AS Username,
            event_data.value('(action[@name="client_app_name"]/value)[1]', 'VARCHAR(256)') AS ClientApp,
            event_data.value('(action[@name="client_hostname"]/value)[1]', 'VARCHAR(128)') AS HostName,
            event_data.value('(action[@name="sql_text"]/value)[1]', 'VARCHAR(MAX)') AS SqlText
        FROM
        (
            SELECT CAST(event_data AS XML) AS event_data
            FROM sys.fn_xe_file_target_read_file('C:\SQLMonitor\XE\SqlMonitor_TimeoutTracking*.xel', NULL, NULL, NULL)
        ) AS Data
        WHERE event_data.value('(@timestamp)[1]', 'DATETIME') BETWEEN @StartTime AND @EndTime
    )
    SELECT
        EventTime,
        EventName,
        SessionID,
        DatabaseName,
        Username,
        ClientApp,
        HostName,
        CAST(DurationSeconds AS DECIMAL(10,2)) AS DurationSeconds,
        LEFT(SqlText, 500) AS SqlTextPreview
    FROM EventData
    ORDER BY EventTime DESC
END
GO

PRINT '  ✓ Helper procedure created: EXEC DBA_QueryTimeoutEvents @StartTime = ..., @EndTime = ...'
PRINT ''
PRINT 'Example usage:'
PRINT '  -- Query last 4 hours'
PRINT '  EXEC DBA_QueryTimeoutEvents'
PRINT ''
PRINT '  -- Query specific timeframe'
PRINT '  EXEC DBA_QueryTimeoutEvents @StartTime = ''2025-10-29 12:00'', @EndTime = ''2025-10-29 14:00'''
PRINT ''

GO
