-- =====================================================
-- Script: 09-create-sql-agent-jobs-FIXED.sql
-- Description: Create SQL Agent jobs for LOCAL metric collection
-- Author: SQL Server Monitor Project
-- Date: 2025-10-31 (UPDATED AFTER FIX)
-- Purpose: Schedule automated LOCAL collection every 5 minutes
--
-- CRITICAL FIXES INCORPORATED:
-- 1. SET QUOTED_IDENTIFIER ON for CPU collection (sys.dm_os_ring_buffers requires it)
-- 2. Two-step jobs: Step 1 (CPU), Step 2 (Disk/Memory/Connections)
-- 3. LOCAL DMV collection with push to central database (no linked server execution)
-- 4. Step 1 on_success_action = 3 (Go to next step)
-- 5. Uses master database context (MonitoringDB may not exist on remote servers)
--
-- DEPLOYMENT INSTRUCTIONS:
-- - sqltest: Run this script on sqltest to create its local collection job
-- - svweb: Run this script on svweb to create its local collection job
-- - suncity: Run this script on suncity to create its local collection job
--
-- Each server collects LOCAL DMVs and pushes to central MonitoringDB on sqltest
-- =====================================================

USE [msdb];
GO

PRINT '';
PRINT '========================================================';
PRINT 'SQL Server Monitor - SQL Agent Jobs Setup (FIXED)';
PRINT '========================================================';
PRINT '';

-- =====================================================
-- Detect server and set ServerID
-- =====================================================

DECLARE @ServerName NVARCHAR(128) = CAST(SERVERPROPERTY('ServerName') AS NVARCHAR(128));
DECLARE @ServerID INT;
DECLARE @JobName NVARCHAR(128);
DECLARE @ScheduleName NVARCHAR(128);

-- Determine ServerID based on server name
IF @ServerName LIKE 'sqltest%' OR @ServerName LIKE '%\SQLTEST%'
BEGIN
    SET @ServerID = 1;
    SET @JobName = N'SQL Monitor - Collect Metrics (sqltest)';
    SET @ScheduleName = N'Every 5 Minutes - sqltest';
    PRINT 'Detected: sqltest (ServerID = 1)';
END
ELSE IF @ServerName LIKE '%SUNCITYSERVER%' OR @ServerName LIKE 'suncity%'
BEGIN
    SET @ServerID = 4;
    SET @JobName = N'SQL Monitor - Collect Metrics (suncity)';
    SET @ScheduleName = N'Every 5 Minutes - suncity';
    PRINT 'Detected: suncity (ServerID = 4)';
END
ELSE IF @ServerName LIKE 'svweb%'
BEGIN
    SET @ServerID = 5;
    SET @JobName = N'SQL Monitor - Collect Metrics (svweb)';
    SET @ScheduleName = N'Every 5 Minutes - svweb';
    PRINT 'Detected: svweb (ServerID = 5)';
END
ELSE
BEGIN
    RAISERROR('Unknown server. Please add server mapping to script.', 16, 1);
    RETURN;
END

PRINT '';

-- =====================================================
-- Drop existing job if exists
-- =====================================================

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @JobName;
    PRINT '  [INFO] Deleted existing job: ' + @JobName;
END;

-- =====================================================
-- Create job
-- =====================================================

EXEC msdb.dbo.sp_add_job
    @job_name = @JobName,
    @enabled = 1,
    @description = N'Collects LOCAL performance metrics (CPU, Disk, Memory, Connections) and pushes to central MonitoringDB',
    @category_name = N'Database Maintenance';

PRINT '  [OK] Job created: ' + @JobName;

-- =====================================================
-- Step 1: Collect LOCAL CPU Metrics
-- CRITICAL: SET QUOTED_IDENTIFIER ON required for sys.dm_os_ring_buffers
-- =====================================================

DECLARE @Step1Command NVARCHAR(MAX) = N'
SET QUOTED_IDENTIFIER ON;

-- Collect LOCAL CPU from ring buffer and push to central DB
DECLARE @CPUMetrics TABLE (
    CollectionTime DATETIME2,
    MetricCategory NVARCHAR(50),
    MetricName NVARCHAR(100),
    MetricValue DECIMAL(20,4)
);

-- Read LOCAL ring buffer
DECLARE @SQLProcessUtilization INT, @SystemIdle INT;
SELECT TOP 1
    @SQLProcessUtilization = record.value(''(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]'', ''int''),
    @SystemIdle = record.value(''(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]'', ''int'')
FROM (
    SELECT TOP 1 timestamp, CONVERT(xml, record) AS record
    FROM sys.dm_os_ring_buffers WITH (NOLOCK)
    WHERE ring_buffer_type = N''RING_BUFFER_SCHEDULER_MONITOR''
      AND record LIKE ''%<SystemHealth>%''
    ORDER BY timestamp DESC
) AS rb;

-- Insert to table variable
INSERT INTO @CPUMetrics (CollectionTime, MetricCategory, MetricName, MetricValue)
SELECT GETUTCDATE(), ''CPU'', ''SQLServerCPUPercent'', CAST(@SQLProcessUtilization AS DECIMAL(10,4))
WHERE @SQLProcessUtilization IS NOT NULL
UNION ALL
SELECT GETUTCDATE(), ''CPU'', ''SystemIdlePercent'', CAST(@SystemIdle AS DECIMAL(10,4))
WHERE @SQLProcessUtilization IS NOT NULL
UNION ALL
SELECT GETUTCDATE(), ''CPU'', ''OtherProcessCPUPercent'',
       CAST(100 - @SQLProcessUtilization - @SystemIdle AS DECIMAL(10,4))
WHERE @SQLProcessUtilization IS NOT NULL;

-- Push to central database with ServerID
';

-- Add server-specific INSERT based on ServerID
IF @ServerID = 1
BEGIN
    -- sqltest: Insert to local MonitoringDB
    SET @Step1Command = @Step1Command + N'
INSERT INTO MonitoringDB.dbo.PerformanceMetrics
    (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
SELECT ' + CAST(@ServerID AS NVARCHAR(10)) + N', CollectionTime, MetricCategory, MetricName, MetricValue
FROM @CPUMetrics;

PRINT ''CPU metrics collected and inserted for ServerID ' + CAST(@ServerID AS NVARCHAR(10)) + N''';
';
END
ELSE
BEGIN
    -- Remote servers: Push to sqltest via linked server
    SET @Step1Command = @Step1Command + N'
INSERT INTO [sqltest.schoolvision.net].MonitoringDB.dbo.PerformanceMetrics
    (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
SELECT ' + CAST(@ServerID AS NVARCHAR(10)) + N', CollectionTime, MetricCategory, MetricName, MetricValue
FROM @CPUMetrics;

PRINT ''CPU metrics collected and pushed to central DB for ServerID ' + CAST(@ServerID AS NVARCHAR(10)) + N''';
';
END

EXEC msdb.dbo.sp_add_jobstep
    @job_name = @JobName,
    @step_id = 1,
    @step_name = N'Collect LOCAL CPU Metrics',
    @subsystem = N'TSQL',
    @database_name = N'master',
    @command = @Step1Command,
    @on_success_action = 3,  -- Go to next step
    @on_fail_action = 2,     -- Quit with failure
    @retry_attempts = 2,
    @retry_interval = 1;

PRINT '  [OK] Step 1 added: Collect LOCAL CPU Metrics';

-- =====================================================
-- Step 2: Collect LOCAL Non-CPU Metrics
-- (Disk, Memory, Connections)
-- =====================================================

DECLARE @Step2Command NVARCHAR(MAX) = N'
SET NOCOUNT ON;

DECLARE @ServerID INT = ' + CAST(@ServerID AS NVARCHAR(10)) + N';
DECLARE @CollectionTime DATETIME2 = GETUTCDATE();

-- =============================================
-- 1. Collect LOCAL Disk I/O Metrics
-- =============================================

DECLARE @TotalReadMB DECIMAL(18,2), @TotalWriteMB DECIMAL(18,2);
DECLARE @TotalReadOps BIGINT, @TotalWriteOps BIGINT;
DECLARE @AvgReadLatency DECIMAL(10,2), @AvgWriteLatency DECIMAL(10,2);

-- Read LOCAL disk stats
SELECT
    @TotalReadMB = SUM(vfs.num_of_bytes_read / 1024.0 / 1024.0),
    @TotalWriteMB = SUM(vfs.num_of_bytes_written / 1024.0 / 1024.0),
    @TotalReadOps = SUM(vfs.num_of_reads),
    @TotalWriteOps = SUM(vfs.num_of_writes),
    @AvgReadLatency = AVG(CASE WHEN vfs.num_of_reads > 0 THEN vfs.io_stall_read_ms / vfs.num_of_reads ELSE 0 END),
    @AvgWriteLatency = AVG(CASE WHEN vfs.num_of_writes > 0 THEN vfs.io_stall_write_ms / vfs.num_of_writes ELSE 0 END)
FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs;

';

-- Add server-specific INSERT
IF @ServerID = 1
BEGIN
    SET @Step2Command = @Step2Command + N'
-- Push disk metrics to local database
INSERT INTO MonitoringDB.dbo.PerformanceMetrics
    (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
VALUES
    (@ServerID, @CollectionTime, ''Disk'', ''ReadMB'', @TotalReadMB),
    (@ServerID, @CollectionTime, ''Disk'', ''WriteMB'', @TotalWriteMB),
    (@ServerID, @CollectionTime, ''Disk'', ''ReadIOPS'', @TotalReadOps),
    (@ServerID, @CollectionTime, ''Disk'', ''WriteIOPS'', @TotalWriteOps),
    (@ServerID, @CollectionTime, ''Disk'', ''AvgReadLatencyMs'', @AvgReadLatency),
    (@ServerID, @CollectionTime, ''Disk'', ''AvgWriteLatencyMs'', @AvgWriteLatency);
';
END
ELSE
BEGIN
    SET @Step2Command = @Step2Command + N'
-- Push disk metrics to central database
INSERT INTO [sqltest.schoolvision.net].MonitoringDB.dbo.PerformanceMetrics
    (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
VALUES
    (@ServerID, @CollectionTime, ''Disk'', ''ReadMB'', @TotalReadMB),
    (@ServerID, @CollectionTime, ''Disk'', ''WriteMB'', @TotalWriteMB),
    (@ServerID, @CollectionTime, ''Disk'', ''ReadIOPS'', @TotalReadOps),
    (@ServerID, @CollectionTime, ''Disk'', ''WriteIOPS'', @TotalWriteOps),
    (@ServerID, @CollectionTime, ''Disk'', ''AvgReadLatencyMs'', @AvgReadLatency),
    (@ServerID, @CollectionTime, ''Disk'', ''AvgWriteLatencyMs'', @AvgWriteLatency);
';
END

-- Add memory and connection metrics (same for all servers)
SET @Step2Command = @Step2Command + N'

-- =============================================
-- 2. Collect LOCAL Memory Metrics
-- =============================================

DECLARE @TotalServerMemoryMB DECIMAL(18,2), @TargetServerMemoryMB DECIMAL(18,2);
DECLARE @BufferCacheHitRatio DECIMAL(10,2), @PageLifeExpectancy INT, @MemoryGrantsPending INT, @MemoryUtilizationPercent DECIMAL(10,2);

SELECT
    @TotalServerMemoryMB = (SELECT CAST(value_in_use AS DECIMAL(18,2)) / 1024 FROM sys.configurations WHERE name = ''max server memory (MB)''),
    @TargetServerMemoryMB = (SELECT SUM(pages_kb) / 1024.0 FROM sys.dm_os_memory_clerks);

SELECT @BufferCacheHitRatio =
    (SELECT CAST(cntr_value AS DECIMAL(10,2)) FROM sys.dm_os_performance_counters WHERE counter_name = ''Buffer cache hit ratio'' AND object_name LIKE ''%Buffer Manager%'')
    / NULLIF((SELECT CAST(cntr_value AS DECIMAL(10,2)) FROM sys.dm_os_performance_counters WHERE counter_name = ''Buffer cache hit ratio base'' AND object_name LIKE ''%Buffer Manager%''), 0) * 100;

SELECT @PageLifeExpectancy = cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = ''Page life expectancy'' AND object_name LIKE ''%Buffer Manager%'';
SELECT @MemoryGrantsPending = cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = ''Memory Grants Pending'' AND object_name LIKE ''%Memory Manager%'';

SET @MemoryUtilizationPercent = (@TargetServerMemoryMB / NULLIF(@TotalServerMemoryMB, 0)) * 100;
';

IF @ServerID = 1
BEGIN
    SET @Step2Command = @Step2Command + N'
INSERT INTO MonitoringDB.dbo.PerformanceMetrics
    (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
VALUES
    (@ServerID, @CollectionTime, ''Memory'', ''TotalServerMemoryMB'', @TotalServerMemoryMB),
    (@ServerID, @CollectionTime, ''Memory'', ''TargetServerMemoryMB'', @TargetServerMemoryMB),
    (@ServerID, @CollectionTime, ''Memory'', ''BufferCacheHitRatio'', @BufferCacheHitRatio),
    (@ServerID, @CollectionTime, ''Memory'', ''PageLifeExpectancy'', @PageLifeExpectancy),
    (@ServerID, @CollectionTime, ''Memory'', ''MemoryGrantsPending'', @MemoryGrantsPending),
    (@ServerID, @CollectionTime, ''Memory'', ''Percent'', @MemoryUtilizationPercent);
';
END
ELSE
BEGIN
    SET @Step2Command = @Step2Command + N'
INSERT INTO [sqltest.schoolvision.net].MonitoringDB.dbo.PerformanceMetrics
    (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
VALUES
    (@ServerID, @CollectionTime, ''Memory'', ''TotalServerMemoryMB'', @TotalServerMemoryMB),
    (@ServerID, @CollectionTime, ''Memory'', ''TargetServerMemoryMB'', @TargetServerMemoryMB),
    (@ServerID, @CollectionTime, ''Memory'', ''BufferCacheHitRatio'', @BufferCacheHitRatio),
    (@ServerID, @CollectionTime, ''Memory'', ''PageLifeExpectancy'', @PageLifeExpectancy),
    (@ServerID, @CollectionTime, ''Memory'', ''MemoryGrantsPending'', @MemoryGrantsPending),
    (@ServerID, @CollectionTime, ''Memory'', ''Percent'', @MemoryUtilizationPercent);
';
END

SET @Step2Command = @Step2Command + N'

-- =============================================
-- 3. Collect LOCAL Connection Metrics
-- =============================================

DECLARE @TotalConnections INT, @ActiveConnections INT, @SleepingConnections INT, @UserConnections INT, @SystemConnections INT;

SELECT
    @TotalConnections = COUNT(*),
    @ActiveConnections = SUM(CASE WHEN status = ''running'' THEN 1 ELSE 0 END),
    @SleepingConnections = SUM(CASE WHEN status = ''sleeping'' THEN 1 ELSE 0 END),
    @UserConnections = SUM(CASE WHEN is_user_process = 1 THEN 1 ELSE 0 END),
    @SystemConnections = SUM(CASE WHEN is_user_process = 0 THEN 1 ELSE 0 END)
FROM sys.dm_exec_sessions
WHERE session_id > 50;
';

IF @ServerID = 1
BEGIN
    SET @Step2Command = @Step2Command + N'
INSERT INTO MonitoringDB.dbo.PerformanceMetrics
    (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
VALUES
    (@ServerID, @CollectionTime, ''Connections'', ''Total'', @TotalConnections),
    (@ServerID, @CollectionTime, ''Connections'', ''Active'', @ActiveConnections),
    (@ServerID, @CollectionTime, ''Connections'', ''Sleeping'', @SleepingConnections),
    (@ServerID, @CollectionTime, ''Connections'', ''User'', @UserConnections),
    (@ServerID, @CollectionTime, ''Connections'', ''System'', @SystemConnections);

PRINT ''Local metrics collected and inserted for ServerID ' + CAST(@ServerID AS NVARCHAR(10)) + N''';
';
END
ELSE
BEGIN
    SET @Step2Command = @Step2Command + N'
INSERT INTO [sqltest.schoolvision.net].MonitoringDB.dbo.PerformanceMetrics
    (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
VALUES
    (@ServerID, @CollectionTime, ''Connections'', ''Total'', @TotalConnections),
    (@ServerID, @CollectionTime, ''Connections'', ''Active'', @ActiveConnections),
    (@ServerID, @CollectionTime, ''Connections'', ''Sleeping'', @SleepingConnections),
    (@ServerID, @CollectionTime, ''Connections'', ''User'', @UserConnections),
    (@ServerID, @CollectionTime, ''Connections'', ''System'', @SystemConnections);

PRINT ''Local non-CPU metrics collected and pushed to central DB for ServerID ' + CAST(@ServerID AS NVARCHAR(10)) + N''';
';
END

EXEC msdb.dbo.sp_add_jobstep
    @job_name = @JobName,
    @step_id = 2,
    @step_name = N'Collect LOCAL Non-CPU Metrics',
    @subsystem = N'TSQL',
    @database_name = N'master',
    @command = @Step2Command,
    @on_success_action = 1,  -- Quit with success (last step)
    @on_fail_action = 2,     -- Quit with failure
    @retry_attempts = 2,
    @retry_interval = 1;

PRINT '  [OK] Step 2 added: Collect LOCAL Non-CPU Metrics';

-- =====================================================
-- Create schedule (every 5 minutes)
-- =====================================================

EXEC msdb.dbo.sp_add_schedule
    @schedule_name = @ScheduleName,
    @freq_type = 4,              -- Daily
    @freq_interval = 1,          -- Every day
    @freq_subday_type = 4,       -- Minutes
    @freq_subday_interval = 5,   -- Every 5 minutes
    @active_start_time = 000000, -- Midnight
    @active_end_time = 235959;   -- 11:59:59 PM

PRINT '  [OK] Schedule created: ' + @ScheduleName;

-- =====================================================
-- Attach schedule to job
-- =====================================================

EXEC msdb.dbo.sp_attach_schedule
    @job_name = @JobName,
    @schedule_name = @ScheduleName;

PRINT '  [OK] Schedule attached to job';

-- =====================================================
-- Add job to local server
-- =====================================================

EXEC msdb.dbo.sp_add_jobserver
    @job_name = @JobName,
    @server_name = N'(LOCAL)';

PRINT '  [OK] Job added to local server';
PRINT '';

PRINT '========================================================';
PRINT 'SQL Agent Job Created Successfully!';
PRINT '========================================================';
PRINT '';
PRINT 'Job Name: ' + @JobName;
PRINT 'ServerID: ' + CAST(@ServerID AS NVARCHAR(10));
PRINT 'Schedule: Every 5 minutes';
PRINT '';
PRINT 'Job Steps:';
PRINT '  1. Collect LOCAL CPU Metrics (with QUOTED_IDENTIFIER ON)';
PRINT '  2. Collect LOCAL Disk, Memory, Connection Metrics';
PRINT '';
PRINT 'Metrics collected per cycle: 20 (3 CPU + 6 Disk + 6 Memory + 5 Connections)';
PRINT '';
PRINT 'Next: Wait for scheduled run or manually execute:';
PRINT '  EXEC msdb.dbo.sp_start_job @job_name = ''' + @JobName + ''';';
PRINT '';
GO
