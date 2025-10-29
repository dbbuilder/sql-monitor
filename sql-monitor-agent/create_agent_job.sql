USE msdb
GO

-- =============================================
-- SQL Agent Job: DBA Collect Perf Snapshot
-- Runs every 5 minutes to collect P0+P1+P2 metrics
-- =============================================

-- Drop existing job if present
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = 'DBA Collect Perf Snapshot')
BEGIN
    PRINT 'Dropping existing job...'
    EXEC dbo.sp_delete_job @job_name = 'DBA Collect Perf Snapshot'
END
GO

-- Create job (use SUSER_SNAME for job owner - works on all servers)
DECLARE @OwnerLogin NVARCHAR(128) = SUSER_SNAME()

EXEC dbo.sp_add_job
    @job_name = N'DBA Collect Perf Snapshot',
    @enabled = 1,
    @description = N'Collects performance snapshot every 5 minutes (P0+P1+P2). Expected execution time: <20 seconds.',
    @category_name = N'Database Maintenance',
    @owner_login_name = @OwnerLogin
GO

-- Add job step with proper SET options for XML parsing
EXEC dbo.sp_add_jobstep
    @job_name = N'DBA Collect Perf Snapshot',
    @step_name = N'Execute Collection',
    @subsystem = N'TSQL',
    @command = N'SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON; EXEC DBATools.dbo.DBA_CollectPerformanceSnapshot @IncludeP0=1, @IncludeP1=1, @IncludeP2=1, @IncludeP3=0, @Debug=0',
    @database_name = N'DBATools',
    @on_success_action = 1,     -- Quit with success
    @on_fail_action = 2,         -- Quit with failure
    @retry_attempts = 3,
    @retry_interval = 1          -- 1 minute between retries
GO

-- Schedule: Every 5 minutes
-- Use unique schedule name to avoid conflicts
DECLARE @ScheduleName NVARCHAR(128) = N'DBA Perf Snapshot - Every 5 Minutes'

-- Drop existing schedule with same name if present
IF EXISTS (SELECT 1 FROM dbo.sysschedules WHERE name = @ScheduleName)
BEGIN
    PRINT 'Dropping existing schedule...'
    EXEC dbo.sp_delete_schedule @schedule_name = @ScheduleName, @force_delete = 1
END

-- Create new schedule
EXEC dbo.sp_add_schedule
    @schedule_name = @ScheduleName,
    @enabled = 1,
    @freq_type = 4,              -- Daily
    @freq_interval = 1,          -- Every day
    @freq_subday_type = 4,       -- Minutes
    @freq_subday_interval = 5,   -- Every 5 minutes
    @active_start_date = 20250101,  -- Start date (YYYYMMDD)
    @active_start_time = 0       -- Start at midnight (HHMMSS)

-- Attach schedule to job
EXEC dbo.sp_attach_schedule
    @job_name = N'DBA Collect Perf Snapshot',
    @schedule_name = @ScheduleName
GO

-- Add job to local server
EXEC dbo.sp_add_jobserver
    @job_name = N'DBA Collect Perf Snapshot',
    @server_name = N'(LOCAL)'
GO

PRINT ''
PRINT '=========================================='
PRINT 'SQL Agent Job Created Successfully'
PRINT '=========================================='
PRINT 'Job Name: DBA Collect Perf Snapshot'
PRINT 'Schedule: Every 5 minutes'
PRINT 'Priority: P0 + P1 + P2 (MaxPriority = 2)'
PRINT 'Debug Mode: Disabled (set @Debug=1 for verbose logging)'
PRINT 'Retry: 3 attempts with 1-minute interval'
PRINT '=========================================='
PRINT ''
GO

-- Verify job configuration
SELECT
    j.name AS JobName,
    j.enabled AS JobEnabled,
    j.description,
    s.name AS ScheduleName,
    CASE s.freq_type
        WHEN 4 THEN 'Daily'
        WHEN 8 THEN 'Weekly'
        WHEN 16 THEN 'Monthly'
    END AS Frequency,
    'Every ' + CAST(s.freq_subday_interval AS VARCHAR(10)) + ' minutes' AS Interval,
    CASE s.enabled
        WHEN 1 THEN 'Enabled'
        ELSE 'Disabled'
    END AS ScheduleStatus
FROM dbo.sysjobs j
INNER JOIN dbo.sysjobschedules js ON j.job_id = js.job_id
INNER JOIN dbo.sysschedules s ON js.schedule_id = s.schedule_id
WHERE j.name = 'DBA Collect Perf Snapshot'
GO

-- Show job history (if any)
IF EXISTS (
    SELECT 1
    FROM msdb.dbo.sysjobhistory h
    INNER JOIN msdb.dbo.sysjobs j ON h.job_id = j.job_id
    WHERE j.name = 'DBA Collect Perf Snapshot'
)
BEGIN
    PRINT 'Recent Job Execution History:'
    PRINT '----------------------------------------'

    SELECT TOP 10
        CONVERT(DATETIME,
            CAST(h.run_date AS VARCHAR(8)) + ' ' +
            STUFF(STUFF(RIGHT('000000' + CAST(h.run_time AS VARCHAR(6)), 6), 5, 0, ':'), 3, 0, ':')
        ) AS ExecutionTime,
        CASE h.run_status
            WHEN 0 THEN 'Failed'
            WHEN 1 THEN 'Succeeded'
            WHEN 2 THEN 'Retry'
            WHEN 3 THEN 'Canceled'
            WHEN 4 THEN 'In Progress'
        END AS Status,
        h.run_duration AS DurationSeconds,
        h.message
    FROM msdb.dbo.sysjobs j
    INNER JOIN msdb.dbo.sysjobhistory h ON j.job_id = h.job_id
    WHERE j.name = 'DBA Collect Perf Snapshot'
        AND h.step_id = 0  -- Job outcome only
    ORDER BY h.instance_id DESC
END
ELSE
BEGIN
    PRINT 'No execution history yet (job just created)'
END
GO

PRINT ''
PRINT 'To monitor job execution:'
PRINT '  EXEC msdb.dbo.sp_help_jobhistory @job_name = ''DBA Collect Perf Snapshot'''
PRINT ''
PRINT 'To disable the job:'
PRINT '  EXEC msdb.dbo.sp_update_job @job_name = ''DBA Collect Perf Snapshot'', @enabled = 0'
PRINT ''
PRINT 'To enable the job:'
PRINT '  EXEC msdb.dbo.sp_update_job @job_name = ''DBA Collect Perf Snapshot'', @enabled = 1'
PRINT ''
PRINT 'To run the job manually:'
PRINT '  EXEC msdb.dbo.sp_start_job @job_name = ''DBA Collect Perf Snapshot'''
GO
