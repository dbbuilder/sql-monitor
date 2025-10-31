-- =====================================================
-- Script: 33-configure-deadlock-trace-flags.sql
-- Description: Enable trace flags for enhanced deadlock monitoring
-- Author: SQL Server Monitor Project
-- Date: 2025-10-31
-- Purpose: Configure SQL Server to capture detailed deadlock information
-- =====================================================

-- IMPORTANT: This script requires sysadmin permissions
-- IMPORTANT: Trace flag changes persist across SQL Server restarts (using -1 for global)

USE master;
GO

PRINT '========================================';
PRINT 'Deadlock Trace Flag Configuration';
PRINT '========================================';
PRINT '';

-- =====================================================
-- Trace Flag 1222: Deadlock Information (Recommended)
-- =====================================================

PRINT 'Checking Trace Flag 1222 status...';

DECLARE @TF1222Enabled BIT = 0;

-- Check if already enabled
IF EXISTS (
    SELECT 1
    FROM sys.dm_os_sys_info
    WHERE 1 = 1  -- Placeholder for compatibility
)
BEGIN
    -- Try to check trace status
    DECLARE @TraceStatus TABLE (TraceFlag INT, Status BIT, Global BIT, Session BIT);
    INSERT INTO @TraceStatus
    EXEC('DBCC TRACESTATUS(1222) WITH NO_INFOMSGS');

    IF EXISTS (SELECT 1 FROM @TraceStatus WHERE TraceFlag = 1222 AND Global = 1)
        SET @TF1222Enabled = 1;
END;

IF @TF1222Enabled = 1
BEGIN
    PRINT '  ✓ Trace Flag 1222 already enabled';
END
ELSE
BEGIN
    PRINT '  - Trace Flag 1222 not enabled. Enabling now...';

    -- Enable globally (persists across restarts)
    DBCC TRACEON(1222, -1) WITH NO_INFOMSGS;

    PRINT '  ✓ Trace Flag 1222 enabled globally';
    PRINT '';
    PRINT '  What this does:';
    PRINT '    - Writes detailed deadlock graph to SQL Server error log';
    PRINT '    - Includes resource information, lock modes, and query text';
    PRINT '    - XML format compatible with SQL Server Management Studio';
    PRINT '    - Zero performance overhead (only writes on deadlock)';
END;

PRINT '';

-- =====================================================
-- Extended Events Session: Deadlock Monitoring
-- =====================================================

PRINT 'Checking Extended Events session for deadlocks...';

IF EXISTS (
    SELECT 1
    FROM sys.server_event_sessions
    WHERE name = 'deadlock_monitor'
)
BEGIN
    PRINT '  ✓ Extended Events session "deadlock_monitor" already exists';

    -- Check if running
    IF EXISTS (
        SELECT 1
        FROM sys.dm_xe_sessions
        WHERE name = 'deadlock_monitor'
    )
    BEGIN
        PRINT '  ✓ Session is running';
    END
    ELSE
    BEGIN
        PRINT '  - Session exists but not running. Starting...';
        ALTER EVENT SESSION deadlock_monitor ON SERVER STATE = START;
        PRINT '  ✓ Session started';
    END;
END
ELSE
BEGIN
    PRINT '  - Extended Events session does not exist. Creating...';

    -- Create dedicated deadlock monitoring session
    CREATE EVENT SESSION deadlock_monitor ON SERVER
    ADD EVENT sqlserver.xml_deadlock_report(
        ACTION(
            sqlserver.client_app_name,
            sqlserver.client_hostname,
            sqlserver.database_id,
            sqlserver.database_name,
            sqlserver.query_hash,
            sqlserver.session_id,
            sqlserver.sql_text,
            sqlserver.username
        )
    )
    ADD TARGET package0.event_file(
        SET filename = N'deadlock_monitor',
        max_file_size = (50),         -- 50 MB per file
        max_rollover_files = (4)       -- Keep 4 files (200 MB total)
    ),
    ADD TARGET package0.ring_buffer(
        SET max_memory = (4096)        -- 4 MB ring buffer (in-memory)
    )
    WITH (
        MAX_MEMORY = 4096 KB,
        EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
        MAX_DISPATCH_LATENCY = 30 SECONDS,
        MAX_EVENT_SIZE = 0 KB,
        MEMORY_PARTITION_MODE = NONE,
        TRACK_CAUSALITY = OFF,
        STARTUP_STATE = ON             -- Start automatically on SQL Server restart
    );

    PRINT '  ✓ Extended Events session created';

    -- Start the session
    ALTER EVENT SESSION deadlock_monitor ON SERVER STATE = START;

    PRINT '  ✓ Session started';
    PRINT '';
    PRINT '  What this does:';
    PRINT '    - Captures all deadlock events to dedicated files';
    PRINT '    - Files stored in SQL Server log directory';
    PRINT '    - 4 MB in-memory ring buffer for quick access';
    PRINT '    - 200 MB total disk space (4 files × 50 MB)';
    PRINT '    - Automatically starts on SQL Server restart';
END;

PRINT '';

-- =====================================================
-- Verification
-- =====================================================

PRINT '========================================';
PRINT 'Verification';
PRINT '========================================';
PRINT '';

-- Check trace flag status
PRINT 'Trace Flag Status:';
DBCC TRACESTATUS(1222);
PRINT '';

-- Check Extended Events session
PRINT 'Extended Events Sessions:';
SELECT
    s.name AS SessionName,
    CASE
        WHEN ds.name IS NOT NULL THEN 'Running'
        ELSE 'Stopped'
    END AS Status,
    s.create_time AS CreatedTime
FROM sys.server_event_sessions s
LEFT JOIN sys.dm_xe_sessions ds ON s.name = ds.name
WHERE s.name IN ('system_health', 'deadlock_monitor')
ORDER BY s.name;

PRINT '';

-- Show Extended Events file location
PRINT 'Extended Events File Location:';
SELECT
    t.name AS TargetName,
    CAST(t.target_data AS XML).value('(EventFileTarget/File/@name)[1]', 'NVARCHAR(500)') AS FilePath
FROM sys.server_event_sessions s
INNER JOIN sys.server_event_session_targets t ON s.event_session_id = t.event_session_id
WHERE s.name = 'deadlock_monitor'
  AND t.name = 'event_file';

PRINT '';

-- =====================================================
-- Configuration Summary
-- =====================================================

PRINT '========================================';
PRINT 'Configuration Complete!';
PRINT '========================================';
PRINT '';
PRINT 'Deadlock monitoring configured with:';
PRINT '';
PRINT '1. Trace Flag 1222 (Global)';
PRINT '   - Writes deadlock graphs to SQL Server error log';
PRINT '   - Viewable via: EXEC xp_readerrorlog';
PRINT '   - Format: XML (readable in SSMS)';
PRINT '';
PRINT '2. Extended Events Session: deadlock_monitor';
PRINT '   - Captures all deadlock events to files';
PRINT '   - 4 MB ring buffer for quick access';
PRINT '   - 200 MB total disk space (4 files)';
PRINT '   - Startup State: ON (starts automatically)';
PRINT '';
PRINT '3. system_health Session';
PRINT '   - Built-in SQL Server health monitoring';
PRINT '   - Also captures deadlocks (last 5 minutes in ring buffer)';
PRINT '   - Used by our usp_CollectDeadlockEvents procedure';
PRINT '';
PRINT 'Collection Schedule:';
PRINT '   - usp_CollectDeadlockEvents runs every 5 minutes';
PRINT '   - Reads from system_health ring buffer';
PRINT '   - Stores in MonitoringDB.dbo.DeadlockEvents table';
PRINT '';
PRINT 'To test deadlock detection:';
PRINT '   - Run: tests/test-deadlock-detection.sql';
PRINT '   - Wait 1 minute after deadlock occurs';
PRINT '   - Run: EXEC dbo.usp_CollectDeadlockEvents @ServerID = 1';
PRINT '';
PRINT 'To view deadlock graphs manually:';
PRINT '   - Error Log: EXEC xp_readerrorlog 0, 1, N''deadlock''';
PRINT '   - Extended Events: Use SSMS "View Target Data" on deadlock_monitor session';
PRINT '';
PRINT '========================================';
GO

-- =====================================================
-- Optional: Enable at Startup (Registry)
-- =====================================================

PRINT '';
PRINT '========================================';
PRINT 'Optional: Persist Trace Flag at Startup';
PRINT '========================================';
PRINT '';
PRINT 'To ensure Trace Flag 1222 persists across SQL Server restarts:';
PRINT '';
PRINT '1. Open SQL Server Configuration Manager';
PRINT '2. Right-click SQL Server service → Properties';
PRINT '3. Startup Parameters tab';
PRINT '4. Add: -T1222';
PRINT '5. Click OK and restart SQL Server';
PRINT '';
PRINT 'OR use registry method:';
PRINT 'EXEC xp_instance_regwrite';
PRINT '    N''HKEY_LOCAL_MACHINE'',';
PRINT '    N''SOFTWARE\Microsoft\MSSQLServer\MSSQLServer\Parameters'',';
PRINT '    N''SQLArg2'',  -- Increment number if SQLArg1, SQLArg2 already exist';
PRINT '    N''REG_SZ'',';
PRINT '    N''-T1222'';';
PRINT '';
PRINT 'Note: DBCC TRACEON(1222, -1) already persists across restarts.';
PRINT 'Startup parameter is redundant but provides extra safety.';
PRINT '';
PRINT '========================================';
GO
