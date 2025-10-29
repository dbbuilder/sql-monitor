USE [msdb]
GO

-- Delete existing job if it exists
IF EXISTS (
    SELECT 1
    FROM msdb.dbo.sysjobs
    WHERE name = N'DBA Collect Perf Snapshot'
)
BEGIN
    EXEC msdb.dbo.sp_delete_job
        @job_name = N'DBA Collect Perf Snapshot'
END
GO

DECLARE @job_id UNIQUEIDENTIFIER
DECLARE @schedule_id INT
DECLARE @ThisServer SYSNAME = @@SERVERNAME
DECLARE @StartDate INT = CAST(CONVERT(VARCHAR(8), GETDATE(), 112) AS INT)

-- Create job
EXEC msdb.dbo.sp_add_job
    @job_name = N'DBA Collect Perf Snapshot',
    @enabled = 1,
    @description = N'Collects health/perf baseline snapshots into DBATools every 5 minutes (config-driven)',
    @start_step_id = 1,
    @notify_level_eventlog = 0,
    @notify_level_email = 0,
    @delete_level = 0,
    @job_id = @job_id OUTPUT

-- Add job step
EXEC msdb.dbo.sp_add_jobstep
    @job_id = @job_id,
    @step_id = 1,
    @step_name = N'Run Snapshot Collector',
    @subsystem = N'TSQL',
    @command = N'EXEC DBATools.dbo.DBA_CollectPerformanceSnapshot @Debug = 0',
    @database_name = N'master',
    @on_success_action = 1,
    @on_fail_action = 2,
    @retry_attempts = 0,
    @retry_interval = 0,
    @flags = 0

-- Create schedule
EXEC msdb.dbo.sp_add_schedule
    @schedule_name = N'Every5Min',
    @enabled = 1,
    @freq_type = 4,              -- Daily
    @freq_interval = 1,          -- Every day
    @freq_subday_type = 4,       -- Minutes
    @freq_subday_interval = 5,   -- Every 5 minutes
    @active_start_time = 0,      -- Start at midnight
    @active_start_date = @StartDate,
    @schedule_id = @schedule_id OUTPUT

-- Attach schedule to job
EXEC msdb.dbo.sp_attach_schedule
    @job_id = @job_id,
    @schedule_id = @schedule_id

-- Add job server
EXEC msdb.dbo.sp_add_jobserver
    @job_id = @job_id,
    @server_name = @ThisServer

PRINT 'SQL Agent job created successfully'
PRINT 'Job Name: DBA Collect Perf Snapshot'
PRINT 'Schedule: Every 5 minutes'
PRINT 'Status: Enabled'
GO
