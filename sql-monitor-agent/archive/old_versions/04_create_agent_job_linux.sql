USE [msdb]
GO

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

EXEC msdb.dbo.sp_add_job
    @job_name = N'DBA Collect Perf Snapshot',
    @enabled = 1,
    @description = N'Collects health/perf baseline snapshots into DBATools every 5 minutes (Linux/StdEd compatible)',
    @start_step_id = 1,
    @notify_level_eventlog = 0,
    @notify_level_email = 0,
    @notify_level_netsend = 0,
    @notify_level_page = 0,
    @delete_level = 0,
    @job_id = @job_id OUTPUT

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

EXEC msdb.dbo.sp_add_schedule 
    @schedule_name = N'Every5Min',
    @enabled = 1,
    @freq_type = 4,
    @freq_interval = 1,
    @freq_subday_type = 4,
    @freq_subday_interval = 5,
    @active_start_time = 0,
    @active_start_date = CONVERT(INT, CONVERT(CHAR(8), GETDATE(), 112))

EXEC msdb.dbo.sp_attach_schedule
    @job_name = N'DBA Collect Perf Snapshot',
    @schedule_name = N'Every5Min'

DECLARE @ThisServer SYSNAME = @@SERVERNAME

EXEC msdb.dbo.sp_add_jobserver
    @job_name = N'DBA Collect Perf Snapshot',
    @server_name = @ThisServer
GO
