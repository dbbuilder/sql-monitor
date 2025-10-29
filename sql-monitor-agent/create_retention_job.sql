USE msdb
GO

-- =============================================
-- SQL Agent Job: DBA Purge Old Snapshots
-- Runs daily at 2:00 AM to purge data older than 14 days
-- =============================================

-- Drop existing job if present
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = 'DBA Purge Old Snapshots')
BEGIN
    PRINT 'Dropping existing retention job...'
    EXEC dbo.sp_delete_job @job_name = 'DBA Purge Old Snapshots'
END
GO

-- Create job
-- Use SUSER_SNAME() for job owner (works on all servers)
DECLARE @OwnerLogin NVARCHAR(128) = SUSER_SNAME()

EXEC dbo.sp_add_job
    @job_name = N'DBA Purge Old Snapshots',
    @enabled = 1,
    @description = N'Purges snapshot data older than 14 days. Runs daily at 2:00 AM to maintain database size.',
    @category_name = N'Database Maintenance',
    @owner_login_name = @OwnerLogin
GO

-- Add job step
EXEC dbo.sp_add_jobstep
    @job_name = N'DBA Purge Old Snapshots',
    @step_name = N'Execute Purge',
    @subsystem = N'TSQL',
    @command = N'EXEC DBATools.dbo.DBA_PurgeOldSnapshots @RetentionDays = 14, @Debug = 1',
    @database_name = N'DBATools',
    @on_success_action = 1,     -- Quit with success
    @on_fail_action = 2,         -- Quit with failure
    @retry_attempts = 2,
    @retry_interval = 5          -- 5 minutes between retries
GO

-- Schedule: Daily at 2:00 AM
EXEC dbo.sp_add_schedule
    @schedule_name = N'Daily 2 AM',
    @enabled = 1,
    @freq_type = 4,              -- Daily
    @freq_interval = 1,          -- Every day
    @freq_subday_type = 1,       -- Once
    @active_start_date = 20250101,  -- Start date (YYYYMMDD)
    @active_start_time = 20000   -- 2:00 AM (HHMMSS)
GO

-- Attach schedule to job
EXEC dbo.sp_attach_schedule
    @job_name = N'DBA Purge Old Snapshots',
    @schedule_name = N'Daily 2 AM'
GO

-- Add job to local server
EXEC dbo.sp_add_jobserver
    @job_name = N'DBA Purge Old Snapshots',
    @server_name = N'(LOCAL)'
GO

PRINT ''
PRINT '=========================================='
PRINT 'Retention Job Created Successfully'
PRINT '=========================================='
PRINT 'Job Name: DBA Purge Old Snapshots'
PRINT 'Schedule: Daily at 2:00 AM'
PRINT 'Retention: 14 days (older data purged)'
PRINT 'Debug Mode: Enabled (verbose logging)'
PRINT 'Retry: 2 attempts with 5-minute interval'
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
    STUFF(STUFF(RIGHT('000000' + CAST(s.active_start_time AS VARCHAR(6)), 6), 5, 0, ':'), 3, 0, ':') AS StartTime,
    CASE s.enabled
        WHEN 1 THEN 'Enabled'
        ELSE 'Disabled'
    END AS ScheduleStatus
FROM dbo.sysjobs j
INNER JOIN dbo.sysjobschedules js ON j.job_id = js.job_id
INNER JOIN dbo.sysschedules s ON js.schedule_id = s.schedule_id
WHERE j.name = 'DBA Purge Old Snapshots'
GO

PRINT ''
PRINT 'To change retention period:'
PRINT '  -- Edit job step command to use different @RetentionDays value'
PRINT '  EXEC msdb.dbo.sp_update_jobstep'
PRINT '    @job_name = ''DBA Purge Old Snapshots'','
PRINT '    @step_id = 1,'
PRINT '    @command = ''EXEC DBATools.dbo.DBA_PurgeOldSnapshots @RetentionDays = 30, @Debug = 1'''
PRINT ''
PRINT 'To run purge manually:'
PRINT '  EXEC msdb.dbo.sp_start_job @job_name = ''DBA Purge Old Snapshots'''
PRINT ''
PRINT 'To disable automatic purge:'
PRINT '  EXEC msdb.dbo.sp_update_job @job_name = ''DBA Purge Old Snapshots'', @enabled = 0'
PRINT ''
PRINT 'To view purge history:'
PRINT '  SELECT TOP 20 * FROM DBATools.dbo.LogEntry'
PRINT '  WHERE ProcedureName = ''DBA_PurgeOldSnapshots'''
PRINT '  ORDER BY LogEntryID DESC'
GO
