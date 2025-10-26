-- =============================================
-- Phase 1.25 Day 5: SQL Agent Jobs
-- Part 1: Schema Change Detection + Metadata Refresh automation
-- Created: 2025-10-26
-- =============================================

USE [msdb];
GO

PRINT 'Creating Phase 1.25 SQL Agent jobs...';
PRINT '';
GO

-- =============================================
-- Job 1: Schema Change Detection (Every 5 Minutes)
-- =============================================

PRINT 'Creating Job 1: SQL Monitor - Schema Change Detection';
GO

-- Delete existing job if it exists
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'SQL Monitor - Schema Change Detection')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = 'SQL Monitor - Schema Change Detection';
    PRINT '  Deleted existing job';
END;
GO

-- Create job
DECLARE @jobId BINARY(16);

EXEC msdb.dbo.sp_add_job
    @job_name = N'SQL Monitor - Schema Change Detection',
    @enabled = 1,
    @description = N'Detects schema changes from DDL triggers and marks databases as stale for metadata refresh. Runs every 5 minutes.',
    @category_name = N'Database Maintenance',
    @owner_login_name = N'sv',
    @job_id = @jobId OUTPUT;

-- Create job step
EXEC msdb.dbo.sp_add_jobstep
    @job_id = @jobId,
    @step_name = N'Detect Schema Changes',
    @step_id = 1,
    @cmdexec_success_code = 0,
    @on_success_action = 1, -- Quit with success
    @on_fail_action = 2,    -- Quit with failure
    @retry_attempts = 0,
    @retry_interval = 0,
    @subsystem = N'TSQL',
    @command = N'
-- Execute schema change detection
EXEC [MonitoringDB].[dbo].[usp_DetectSchemaChanges];

-- Log execution
DECLARE @DatabasesMarkedStale INT;
SELECT @DatabasesMarkedStale = COUNT(*)
FROM [MonitoringDB].[dbo].[DatabaseMetadataCache]
WHERE IsCurrent = 0;

PRINT CONCAT(''Schema change detection completed. Databases marked stale: '', @DatabasesMarkedStale);
',
    @database_name = N'MonitoringDB';

-- Create schedule (every 5 minutes)
EXEC msdb.dbo.sp_add_jobschedule
    @job_id = @jobId,
    @name = N'Every 5 Minutes',
    @enabled = 1,
    @freq_type = 4,          -- Daily
    @freq_interval = 1,      -- Every day
    @freq_subday_type = 4,   -- Minutes
    @freq_subday_interval = 5, -- Every 5 minutes
    @active_start_time = 0,  -- Midnight
    @active_end_time = 235959; -- 11:59:59 PM

-- Add job to local server
EXEC msdb.dbo.sp_add_jobserver
    @job_id = @jobId,
    @server_name = N'(local)';

PRINT '  ✓ Created job: SQL Monitor - Schema Change Detection';
PRINT '    Schedule: Every 5 minutes';
PRINT '';
GO

-- =============================================
-- Job 2: Metadata Refresh (Daily at 2 AM)
-- =============================================

PRINT 'Creating Job 2: SQL Monitor - Metadata Refresh';
GO

-- Delete existing job if it exists
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'SQL Monitor - Metadata Refresh')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = 'SQL Monitor - Metadata Refresh';
    PRINT '  Deleted existing job';
END;
GO

-- Create job
DECLARE @jobId BINARY(16);

EXEC msdb.dbo.sp_add_job
    @job_name = N'SQL Monitor - Metadata Refresh',
    @enabled = 1,
    @description = N'Refreshes cached metadata for all databases marked as stale. Runs daily at 2 AM (off-hours). Full refresh on Sundays.',
    @category_name = N'Database Maintenance',
    @owner_login_name = N'sv',
    @job_id = @jobId OUTPUT;

-- Create job step
EXEC msdb.dbo.sp_add_jobstep
    @job_id = @jobId,
    @step_name = N'Refresh Metadata Cache',
    @step_id = 1,
    @cmdexec_success_code = 0,
    @on_success_action = 1, -- Quit with success
    @on_fail_action = 2,    -- Quit with failure
    @retry_attempts = 1,
    @retry_interval = 5,    -- 5 minutes
    @subsystem = N'TSQL',
    @command = N'
-- Determine if this is Sunday (full refresh day)
DECLARE @IsSunday BIT = CASE WHEN DATEPART(WEEKDAY, GETDATE()) = 1 THEN 1 ELSE 0 END;
DECLARE @ForceRefresh BIT = @IsSunday;

PRINT CONCAT(''Starting metadata refresh at '', CONVERT(VARCHAR, GETUTCDATE(), 120));
PRINT CONCAT(''Mode: '', CASE WHEN @ForceRefresh = 1 THEN ''FULL REFRESH (Sunday)'' ELSE ''INCREMENTAL'' END);
PRINT '''';

-- Execute metadata refresh
EXEC [MonitoringDB].[dbo].[usp_RefreshMetadataCache]
    @ServerID = NULL,        -- All servers
    @DatabaseName = NULL,    -- All databases needing refresh
    @ForceRefresh = @ForceRefresh;

-- Summary
DECLARE @TotalDatabases INT;
DECLARE @CurrentDatabases INT;
DECLARE @StaleDatabases INT;

SELECT @TotalDatabases = COUNT(*) FROM [MonitoringDB].[dbo].[DatabaseMetadataCache];
SELECT @CurrentDatabases = COUNT(*) FROM [MonitoringDB].[dbo].[DatabaseMetadataCache] WHERE IsCurrent = 1;
SELECT @StaleDatabases = COUNT(*) FROM [MonitoringDB].[dbo].[DatabaseMetadataCache] WHERE IsCurrent = 0;

PRINT '''';
PRINT CONCAT(''Metadata refresh completed at '', CONVERT(VARCHAR, GETUTCDATE(), 120));
PRINT CONCAT(''Total databases tracked: '', @TotalDatabases);
PRINT CONCAT(''Databases current: '', @CurrentDatabases);
PRINT CONCAT(''Databases still stale: '', @StaleDatabases);

-- Alert if any databases still stale
IF @StaleDatabases > 0
BEGIN
    PRINT '''';
    PRINT ''WARNING: Some databases failed to refresh.'';
    RAISERROR(''Metadata refresh incomplete - %d databases still stale'', 16, 1, @StaleDatabases);
END;
',
    @database_name = N'MonitoringDB';

-- Create schedule (daily at 2 AM)
EXEC msdb.dbo.sp_add_jobschedule
    @job_id = @jobId,
    @name = N'Daily at 2 AM',
    @enabled = 1,
    @freq_type = 4,          -- Daily
    @freq_interval = 1,      -- Every day
    @freq_subday_type = 1,   -- At the specified time
    @freq_recurrence_factor = 1,
    @active_start_time = 20000; -- 2:00:00 AM

-- Add job to local server
EXEC msdb.dbo.sp_add_jobserver
    @job_id = @jobId,
    @server_name = N'(local)';

PRINT '  ✓ Created job: SQL Monitor - Metadata Refresh';
PRINT '    Schedule: Daily at 2:00 AM';
PRINT '    Full refresh: Sundays';
PRINT '';
GO

-- =============================================
-- Verification: Show created jobs
-- =============================================

PRINT '';
PRINT '========================================';
PRINT 'SQL Agent Jobs Created';
PRINT '========================================';
PRINT '';

SELECT
    j.name AS JobName,
    j.enabled AS Enabled,
    j.description AS Description,
    CASE
        WHEN s.freq_type = 4 AND s.freq_subday_type = 4
        THEN CONCAT('Every ', s.freq_subday_interval, ' minutes')
        WHEN s.freq_type = 4 AND s.freq_subday_type = 1
        THEN CONCAT('Daily at ', FORMAT(CAST(STUFF(STUFF(RIGHT('000000' + CAST(s.active_start_time AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':') AS TIME), 'hh\:mm tt'))
        ELSE 'Other'
    END AS Schedule,
    CASE j.enabled WHEN 1 THEN 'Yes' ELSE 'No' END AS IsEnabled
FROM msdb.dbo.sysjobs j
LEFT JOIN msdb.dbo.sysjobschedules js ON j.job_id = js.job_id
LEFT JOIN msdb.dbo.sysschedules s ON js.schedule_id = s.schedule_id
WHERE j.name LIKE 'SQL Monitor%'
ORDER BY j.name;

PRINT '';
PRINT '========================================';
PRINT 'Next Steps';
PRINT '========================================';
PRINT '1. Verify jobs are enabled';
PRINT '2. Test Schema Change Detection:';
PRINT '   - Make a schema change (CREATE TABLE, ALTER PROCEDURE, etc.)';
PRINT '   - Wait 5 minutes for detection job';
PRINT '   - Check DatabaseMetadataCache.IsCurrent = 0';
PRINT '';
PRINT '3. Test Metadata Refresh:';
PRINT '   - Manually run: EXEC msdb.dbo.sp_start_job @job_name = ''SQL Monitor - Metadata Refresh'';';
PRINT '   - Verify DatabaseMetadataCache.IsCurrent = 1';
PRINT '';
PRINT '4. Create Grafana dashboards for schema browsing';
PRINT '========================================';
GO

-- =============================================
-- Manual Test: Run Schema Change Detection Now
-- =============================================

PRINT '';
PRINT 'Manual Test: Running Schema Change Detection...';
PRINT '';
GO

USE [MonitoringDB];
GO

EXEC dbo.usp_DetectSchemaChanges;
GO

-- Show results
SELECT
    DatabaseName,
    IsCurrent,
    LastRefreshTime,
    LastSchemaChangeTime,
    TableCount,
    ViewCount,
    ProcedureCount,
    FunctionCount
FROM dbo.DatabaseMetadataCache
ORDER BY LastSchemaChangeTime DESC;
GO

PRINT '';
PRINT '========================================';
PRINT 'SQL Agent Jobs Setup Complete';
PRINT '========================================';
PRINT 'Jobs created:';
PRINT '  1. SQL Monitor - Schema Change Detection (every 5 min)';
PRINT '  2. SQL Monitor - Metadata Refresh (daily at 2 AM)';
PRINT '';
PRINT 'To start jobs immediately:';
PRINT '  EXEC msdb.dbo.sp_start_job @job_name = ''SQL Monitor - Schema Change Detection'';';
PRINT '  EXEC msdb.dbo.sp_start_job @job_name = ''SQL Monitor - Metadata Refresh'';';
PRINT '========================================';
GO
