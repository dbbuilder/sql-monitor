-- =====================================================
-- Phase 3 - Feature #4: Historical Baseline Comparison
-- SQL Agent Jobs for Baseline Calculation and Anomaly Detection
-- =====================================================
-- File: 72-create-baseline-sql-agent-job.sql
-- Purpose: Automate baseline calculations (daily) and anomaly detection (every 15 min)
-- Dependencies: 71-create-baseline-procedures.sql
-- =====================================================

USE msdb;
GO

SET QUOTED_IDENTIFIER ON;
GO

PRINT '======================================';
PRINT 'Creating Baseline SQL Agent Jobs';
PRINT '======================================';
PRINT '';

-- =====================================================
-- Job 1: Daily Baseline Calculation (3:00 AM)
-- =====================================================

DECLARE @jobName1 NVARCHAR(128) = N'MonitoringDB - Update Baselines (Daily)';
DECLARE @jobId1 BINARY(16);

-- Drop job if exists
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @jobName1)
BEGIN
    PRINT 'Dropping existing job: ' + @jobName1;
    EXEC msdb.dbo.sp_delete_job @job_name = @jobName1;
END;

-- Create job (use current login as owner)
EXEC msdb.dbo.sp_add_job
    @job_name = @jobName1,
    @enabled = 1,
    @description = N'Calculate statistical baselines for all servers and metrics (7/14/30/90-day rolling windows)',
    @category_name = N'Database Maintenance',
    @job_id = @jobId1 OUTPUT;

-- Add job step
EXEC msdb.dbo.sp_add_jobstep
    @job_name = @jobName1,
    @step_name = N'Calculate All Baselines',
    @subsystem = N'TSQL',
    @command = N'EXEC MonitoringDB.dbo.usp_UpdateAllBaselines;',
    @database_name = N'MonitoringDB',
    @on_success_action = 1, -- Quit with success
    @on_fail_action = 2,     -- Quit with failure
    @retry_attempts = 3,
    @retry_interval = 5;     -- 5 minutes

-- Add schedule (daily at 3:00 AM)
EXEC msdb.dbo.sp_add_jobschedule
    @job_name = @jobName1,
    @name = N'Daily at 3:00 AM',
    @enabled = 1,
    @freq_type = 4,              -- Daily
    @freq_interval = 1,          -- Every 1 day
    @freq_subday_type = 1,       -- At specified time
    @freq_recurrence_factor = 1,
    @active_start_time = 030000; -- 3:00:00 AM

-- Add job to local server
EXEC msdb.dbo.sp_add_jobserver
    @job_name = @jobName1,
    @server_name = N'(local)';

PRINT '✅ Created job: ' + @jobName1;
PRINT '   Schedule: Daily at 3:00 AM';
PRINT '';

-- =====================================================
-- Job 2: Anomaly Detection (Every 15 Minutes)
-- =====================================================

DECLARE @jobName2 NVARCHAR(128) = N'MonitoringDB - Detect Anomalies (15 min)';
DECLARE @jobId2 BINARY(16);

-- Drop job if exists
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @jobName2)
BEGIN
    PRINT 'Dropping existing job: ' + @jobName2;
    EXEC msdb.dbo.sp_delete_job @job_name = @jobName2;
END;

-- Create job (use current login as owner)
EXEC msdb.dbo.sp_add_job
    @job_name = @jobName2,
    @enabled = 1,
    @description = N'Detect anomalies by comparing recent metrics to 7-day baselines',
    @category_name = N'Database Maintenance',
    @job_id = @jobId2 OUTPUT;

-- Add job step
EXEC msdb.dbo.sp_add_jobstep
    @job_name = @jobName2,
    @step_name = N'Detect Anomalies (7-day baseline)',
    @subsystem = N'TSQL',
    @command = N'EXEC MonitoringDB.dbo.usp_DetectAnomalies @BaselinePeriod = ''7day'';',
    @database_name = N'MonitoringDB',
    @on_success_action = 1, -- Quit with success
    @on_fail_action = 2,     -- Quit with failure
    @retry_attempts = 2,
    @retry_interval = 1;     -- 1 minute

-- Add schedule (every 15 minutes, 24x7)
EXEC msdb.dbo.sp_add_jobschedule
    @job_name = @jobName2,
    @name = N'Every 15 minutes',
    @enabled = 1,
    @freq_type = 4,              -- Daily
    @freq_interval = 1,          -- Every day
    @freq_subday_type = 4,       -- Minutes
    @freq_subday_interval = 15,  -- Every 15 minutes
    @freq_recurrence_factor = 1,
    @active_start_time = 000000, -- 12:00:00 AM
    @active_end_time = 235959;   -- 11:59:59 PM

-- Add job to local server
EXEC msdb.dbo.sp_add_jobserver
    @job_name = @jobName2,
    @server_name = N'(local)';

PRINT '✅ Created job: ' + @jobName2;
PRINT '   Schedule: Every 15 minutes (24x7)';
PRINT '';

-- =====================================================
-- Verify Jobs Created
-- =====================================================

PRINT '======================================';
PRINT 'Baseline SQL Agent Jobs Created';
PRINT '======================================';
PRINT '';

SELECT
    j.name AS JobName,
    j.enabled AS Enabled,
    s.name AS ScheduleName,
    CASE s.freq_type
        WHEN 4 THEN 'Daily'
        ELSE 'Other'
    END AS Frequency,
    CASE s.freq_subday_type
        WHEN 1 THEN 'At ' + STUFF(STUFF(RIGHT('000000' + CAST(s.active_start_time AS VARCHAR(6)), 6), 5, 0, ':'), 3, 0, ':')
        WHEN 4 THEN 'Every ' + CAST(s.freq_subday_interval AS VARCHAR) + ' minutes'
        ELSE 'Other'
    END AS Schedule,
    CASE j.enabled
        WHEN 1 THEN '✅ Enabled'
        ELSE '❌ Disabled'
    END AS Status
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobschedules js ON j.job_id = js.job_id
INNER JOIN msdb.dbo.sysschedules s ON js.schedule_id = s.schedule_id
WHERE j.name LIKE '%MonitoringDB - %Baseline%'
   OR j.name LIKE '%MonitoringDB - %Anomal%'
ORDER BY j.name;

PRINT '';
PRINT 'Summary:';
PRINT '  ✅ Daily baseline calculation (3:00 AM)';
PRINT '  ✅ Anomaly detection every 15 minutes';
PRINT '';
PRINT 'Next Steps:';
PRINT '1. Run initial baseline calculation manually (or wait until 3:00 AM)';
PRINT '2. Verify anomaly detection triggers every 15 minutes';
PRINT '3. Create Grafana dashboards for baseline visualization';
PRINT '4. Create integration tests';
PRINT '======================================';
PRINT '';

GO
