-- =============================================
-- SQL Agent Jobs for All Servers
-- =============================================
-- Purpose: Create SQL Agent jobs on each server to collect metrics
-- Run this script on EACH server (sqltest, svweb, suncity)
-- =============================================

-- =============================================
-- INSTRUCTIONS:
-- 1. Connect to the server you want to monitor
-- 2. Uncomment ONLY the section for that server
-- 3. Run the script
-- 4. Repeat for each server
-- =============================================

USE [msdb];
GO

-- =============================================
-- OPTION 1: sqltest.schoolvision.net,14333
-- =============================================
-- UNCOMMENT THIS SECTION FOR SQLTEST:
/*
PRINT 'Creating SQL Agent job for: sqltest.schoolvision.net,14333';

DECLARE @ServerID INT = 1; -- sqltest ServerID
DECLARE @JobName NVARCHAR(255) = N'SQL Monitor - Collect Metrics (sqltest)';

-- Delete existing job if it exists
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @JobName;
    PRINT '  Old job deleted';
END

-- Create job
EXEC msdb.dbo.sp_add_job
    @job_name = @JobName,
    @enabled = 1,
    @description = N'Collects performance metrics every 5 minutes for sqltest server';

-- Add job step
EXEC msdb.dbo.sp_add_jobstep
    @job_name = @JobName,
    @step_name = N'Collect All RDS Metrics',
    @subsystem = N'TSQL',
    @database_name = N'MonitoringDB',
    @command = N'EXEC dbo.usp_CollectAllRDSMetrics @ServerID = 1;',
    @retry_attempts = 3,
    @retry_interval = 1,
    @on_success_action = 1, -- Quit with success
    @on_fail_action = 2;    -- Quit with failure

-- Create schedule
EXEC msdb.dbo.sp_add_schedule
    @schedule_name = N'Every 5 Minutes',
    @freq_type = 4,        -- Daily
    @freq_interval = 1,    -- Every day
    @freq_subday_type = 4, -- Minutes
    @freq_subday_interval = 5, -- Every 5 minutes
    @active_start_time = 000000;

-- Attach schedule to job
EXEC msdb.dbo.sp_attach_schedule
    @job_name = @JobName,
    @schedule_name = N'Every 5 Minutes';

-- Add job to local server
EXEC msdb.dbo.sp_add_jobserver
    @job_name = @JobName,
    @server_name = N'(local)';

PRINT '  ✓ Job created successfully: ' + @JobName;
PRINT '  ✓ Schedule: Every 5 minutes';
PRINT '  ✓ ServerID: 1 (sqltest)';
GO
*/

-- =============================================
-- OPTION 2: svweb,14333 (SVWEB\CLUBTRACK)
-- =============================================
-- UNCOMMENT THIS SECTION FOR SVWEB:
/*
PRINT 'Creating SQL Agent job for: svweb,14333';

DECLARE @ServerID INT = 2; -- svweb ServerID
DECLARE @JobName NVARCHAR(255) = N'SQL Monitor - Collect Metrics (svweb)';

-- Delete existing job if it exists
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @JobName;
    PRINT '  Old job deleted';
END

-- Create job
EXEC msdb.dbo.sp_add_job
    @job_name = @JobName,
    @enabled = 1,
    @description = N'Collects performance metrics every 5 minutes for svweb server';

-- Add job step
EXEC msdb.dbo.sp_add_jobstep
    @job_name = @JobName,
    @step_name = N'Collect All RDS Metrics',
    @subsystem = N'TSQL',
    @database_name = N'MonitoringDB',
    @command = N'EXEC dbo.usp_CollectAllRDSMetrics @ServerID = 2;',
    @retry_attempts = 3,
    @retry_interval = 1,
    @on_success_action = 1,
    @on_fail_action = 2;

-- Create schedule
EXEC msdb.dbo.sp_add_schedule
    @schedule_name = N'Every 5 Minutes - svweb',
    @freq_type = 4,
    @freq_interval = 1,
    @freq_subday_type = 4,
    @freq_subday_interval = 5,
    @active_start_time = 000000;

-- Attach schedule
EXEC msdb.dbo.sp_attach_schedule
    @job_name = @JobName,
    @schedule_name = N'Every 5 Minutes - svweb';

-- Add job server
EXEC msdb.dbo.sp_add_jobserver
    @job_name = @JobName,
    @server_name = N'(local)';

PRINT '  ✓ Job created successfully: ' + @JobName;
PRINT '  ✓ Schedule: Every 5 minutes';
PRINT '  ✓ ServerID: 2 (svweb)';
GO
*/

-- =============================================
-- OPTION 3: suncity.schoolvision.net,14333
-- =============================================
-- UNCOMMENT THIS SECTION FOR SUNCITY:
/*
PRINT 'Creating SQL Agent job for: suncity.schoolvision.net,14333';

DECLARE @ServerID INT = 3; -- suncity ServerID
DECLARE @JobName NVARCHAR(255) = N'SQL Monitor - Collect Metrics (suncity)';

-- Delete existing job if it exists
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @JobName;
    PRINT '  Old job deleted';
END

-- Create job
EXEC msdb.dbo.sp_add_job
    @job_name = @JobName,
    @enabled = 1,
    @description = N'Collects performance metrics every 5 minutes for suncity server';

-- Add job step
EXEC msdb.dbo.sp_add_jobstep
    @job_name = @JobName,
    @step_name = N'Collect All RDS Metrics',
    @subsystem = N'TSQL',
    @database_name = N'MonitoringDB',
    @command = N'EXEC dbo.usp_CollectAllRDSMetrics @ServerID = 3;',
    @retry_attempts = 3,
    @retry_interval = 1,
    @on_success_action = 1,
    @on_fail_action = 2;

-- Create schedule
EXEC msdb.dbo.sp_add_schedule
    @schedule_name = N'Every 5 Minutes - suncity',
    @freq_type = 4,
    @freq_interval = 1,
    @freq_subday_type = 4,
    @freq_subday_interval = 5,
    @active_start_time = 000000;

-- Attach schedule
EXEC msdb.dbo.sp_attach_schedule
    @job_name = @JobName,
    @schedule_name = N'Every 5 Minutes - suncity';

-- Add job server
EXEC msdb.dbo.sp_add_jobserver
    @job_name = @JobName,
    @server_name = N'(local)';

PRINT '  ✓ Job created successfully: ' + @JobName;
PRINT '  ✓ Schedule: Every 5 minutes';
PRINT '  ✓ ServerID: 3 (suncity)';
GO
*/

-- =============================================
-- VERIFICATION QUERY
-- =============================================
-- Run this after creating the job to verify:

PRINT '';
PRINT 'Verifying SQL Agent job...';
PRINT '';

SELECT
    j.name AS JobName,
    j.enabled AS IsEnabled,
    j.date_created AS CreatedDate,
    s.name AS ScheduleName,
    CASE s.freq_type
        WHEN 4 THEN 'Daily'
        ELSE 'Other'
    END AS Frequency,
    CASE s.freq_subday_type
        WHEN 4 THEN 'Every ' + CAST(s.freq_subday_interval AS VARCHAR(10)) + ' minutes'
        ELSE 'Other'
    END AS Interval
FROM msdb.dbo.sysjobs j
LEFT JOIN msdb.dbo.sysjobschedules js ON j.job_id = js.job_id
LEFT JOIN msdb.dbo.sysschedules s ON js.schedule_id = s.schedule_id
WHERE j.name LIKE 'SQL Monitor%'
ORDER BY j.name;

PRINT '';
PRINT 'Job verification complete!';
PRINT '';

-- =============================================
-- TEST THE JOB
-- =============================================
PRINT 'To test the job immediately, run:';
PRINT '  EXEC msdb.dbo.sp_start_job @job_name = N''SQL Monitor - Collect Metrics (YOUR_SERVER)'';';
PRINT '';
PRINT 'Check job history:';
PRINT '  EXEC msdb.dbo.sp_help_jobhistory @job_name = N''SQL Monitor - Collect Metrics (YOUR_SERVER)'';';
PRINT '';

GO
