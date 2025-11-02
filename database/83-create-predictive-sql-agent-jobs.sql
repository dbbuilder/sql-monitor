-- =====================================================
-- Phase 3 - Feature #5: Predictive Analytics
-- SQL Agent Jobs for Automated Trend Analysis and Forecasting
-- =====================================================
-- File: 83-create-predictive-sql-agent-jobs.sql
-- Purpose: Create SQL Agent jobs for predictive analytics automation
-- Dependencies: 80-create-predictive-analytics-tables.sql
--               81-create-trend-procedures.sql
--               82-create-forecasting-procedures.sql
-- =====================================================

USE msdb;
GO

SET NOCOUNT ON;
GO

PRINT '======================================'
PRINT 'Creating Predictive Analytics SQL Agent Jobs'
PRINT '======================================'
PRINT ''

-- =====================================================
-- Job 1: Daily Trend Calculation
-- Runs at 2:00 AM daily
-- =====================================================

DECLARE @jobName1 NVARCHAR(128) = N'MonitoringDB - Calculate Trends (Daily)';
DECLARE @jobId1 BINARY(16);

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @jobName1)
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @jobName1;
    PRINT 'Deleted existing job: ' + @jobName1;
END;

EXEC msdb.dbo.sp_add_job
    @job_name = @jobName1,
    @enabled = 1,
    @description = N'Calculate linear regression trends for all servers and metrics (7/14/30/90-day periods)',
    @category_name = N'Database Maintenance',
    @job_id = @jobId1 OUTPUT;

-- Add job step
EXEC msdb.dbo.sp_add_jobstep
    @job_name = @jobName1,
    @step_name = N'Calculate All Trends',
    @subsystem = N'TSQL',
    @command = N'
EXEC MonitoringDB.dbo.usp_UpdateAllTrends @TrendPeriod = ''7day'';
EXEC MonitoringDB.dbo.usp_UpdateAllTrends @TrendPeriod = ''14day'';
EXEC MonitoringDB.dbo.usp_UpdateAllTrends @TrendPeriod = ''30day'';
EXEC MonitoringDB.dbo.usp_UpdateAllTrends @TrendPeriod = ''90day'';
',
    @database_name = N'MonitoringDB',
    @on_success_action = 1, -- Quit with success
    @on_fail_action = 2,    -- Quit with failure
    @retry_attempts = 2,
    @retry_interval = 5;

-- Add schedule: Daily at 2:00 AM
EXEC msdb.dbo.sp_add_jobschedule
    @job_name = @jobName1,
    @name = N'Daily at 2:00 AM',
    @enabled = 1,
    @freq_type = 4,              -- Daily
    @freq_interval = 1,          -- Every 1 day
    @freq_subday_type = 1,       -- At specified time
    @freq_recurrence_factor = 1,
    @active_start_time = 020000; -- 02:00:00 AM

-- Add job to local server
EXEC msdb.dbo.sp_add_jobserver
    @job_name = @jobName1,
    @server_name = N'(local)';

PRINT 'Created job: ' + @jobName1;
PRINT '  Schedule: Daily at 2:00 AM';
PRINT '';
GO

-- =====================================================
-- Job 2: Hourly Capacity Forecast Generation
-- Runs every hour
-- =====================================================

DECLARE @jobName2 NVARCHAR(128) = N'MonitoringDB - Generate Capacity Forecasts (Hourly)';
DECLARE @jobId2 BINARY(16);

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @jobName2)
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @jobName2;
    PRINT 'Deleted existing job: ' + @jobName2;
END;

EXEC msdb.dbo.sp_add_job
    @job_name = @jobName2,
    @enabled = 1,
    @description = N'Generate capacity forecasts based on trends (predicts when resources will reach capacity)',
    @category_name = N'Database Maintenance',
    @job_id = @jobId2 OUTPUT;

-- Add job step
EXEC msdb.dbo.sp_add_jobstep
    @job_name = @jobName2,
    @step_name = N'Generate Forecasts',
    @subsystem = N'TSQL',
    @command = N'
EXEC MonitoringDB.dbo.usp_GenerateCapacityForecasts @MinConfidence = 0.7;
',
    @database_name = N'MonitoringDB',
    @on_success_action = 1, -- Quit with success
    @on_fail_action = 2,    -- Quit with failure
    @retry_attempts = 2,
    @retry_interval = 5;

-- Add schedule: Every hour
EXEC msdb.dbo.sp_add_jobschedule
    @job_name = @jobName2,
    @name = N'Every Hour',
    @enabled = 1,
    @freq_type = 4,              -- Daily
    @freq_interval = 1,          -- Every 1 day
    @freq_subday_type = 8,       -- Hours
    @freq_subday_interval = 1,   -- Every 1 hour
    @freq_recurrence_factor = 1,
    @active_start_time = 000000; -- 00:00:00 AM

-- Add job to local server
EXEC msdb.dbo.sp_add_jobserver
    @job_name = @jobName2,
    @server_name = N'(local)';

PRINT 'Created job: ' + @jobName2;
PRINT '  Schedule: Every hour';
PRINT '';
GO

-- =====================================================
-- Job 3: Predictive Alert Evaluation (15 minutes)
-- Runs every 15 minutes
-- =====================================================

DECLARE @jobName3 NVARCHAR(128) = N'MonitoringDB - Evaluate Predictive Alerts (15 min)';
DECLARE @jobId3 BINARY(16);

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @jobName3)
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @jobName3;
    PRINT 'Deleted existing job: ' + @jobName3;
END;

EXEC msdb.dbo.sp_add_job
    @job_name = @jobName3,
    @enabled = 1,
    @description = N'Evaluate capacity forecasts and raise alerts when resources approach capacity limits',
    @category_name = N'Database Maintenance',
    @job_id = @jobId3 OUTPUT;

-- Add job step
EXEC msdb.dbo.sp_add_jobstep
    @job_name = @jobName3,
    @step_name = N'Evaluate Predictive Alerts',
    @subsystem = N'TSQL',
    @command = N'
EXEC MonitoringDB.dbo.usp_EvaluatePredictiveAlerts;

-- Send notifications for new alerts (if enabled)
-- EXEC MonitoringDB.dbo.usp_SendAlertNotifications; -- Uncomment when email is configured
',
    @database_name = N'MonitoringDB',
    @on_success_action = 1, -- Quit with success
    @on_fail_action = 2,    -- Quit with failure
    @retry_attempts = 2,
    @retry_interval = 2;

-- Add schedule: Every 15 minutes
EXEC msdb.dbo.sp_add_jobschedule
    @job_name = @jobName3,
    @name = N'Every 15 Minutes',
    @enabled = 1,
    @freq_type = 4,              -- Daily
    @freq_interval = 1,          -- Every 1 day
    @freq_subday_type = 4,       -- Minutes
    @freq_subday_interval = 15,  -- Every 15 minutes
    @freq_recurrence_factor = 1,
    @active_start_time = 000000; -- 00:00:00 AM

-- Add job to local server
EXEC msdb.dbo.sp_add_jobserver
    @job_name = @jobName3,
    @server_name = N'(local)';

PRINT 'Created job: ' + @jobName3;
PRINT '  Schedule: Every 15 minutes';
PRINT '';
GO

-- =====================================================
-- Summary and Verification
-- =====================================================

PRINT '======================================'
PRINT 'Predictive Analytics SQL Agent Jobs Created'
PRINT '======================================'
PRINT ''

PRINT 'Jobs Created:'
SELECT
    j.name AS JobName,
    CASE j.enabled
        WHEN 1 THEN 'Enabled'
        ELSE 'Disabled'
    END AS Status,
    s.name AS ScheduleName,
    CASE s.freq_type
        WHEN 4 THEN
            CASE s.freq_subday_type
                WHEN 1 THEN 'Daily at ' + RIGHT('0' + CAST(s.active_start_time / 10000 AS VARCHAR), 2) + ':' +
                            RIGHT('0' + CAST((s.active_start_time % 10000) / 100 AS VARCHAR), 2)
                WHEN 4 THEN 'Every ' + CAST(s.freq_subday_interval AS VARCHAR) + ' minutes'
                WHEN 8 THEN 'Every ' + CAST(s.freq_subday_interval AS VARCHAR) + ' hours'
                ELSE 'Daily'
            END
        ELSE 'Other'
    END AS Schedule
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobschedules js ON j.job_id = js.job_id
INNER JOIN msdb.dbo.sysschedules s ON js.schedule_id = s.schedule_id
WHERE j.name LIKE 'MonitoringDB%Trend%'
   OR j.name LIKE 'MonitoringDB%Forecast%'
   OR j.name LIKE 'MonitoringDB%Predictive%'
ORDER BY j.name;

PRINT ''
PRINT 'Next Steps:'
PRINT '  1. Run trend calculation manually to populate baseline data:'
PRINT '     EXEC MonitoringDB.dbo.usp_UpdateAllTrends;'
PRINT ''
PRINT '  2. Run forecast generation manually to create initial forecasts:'
PRINT '     EXEC MonitoringDB.dbo.usp_GenerateCapacityForecasts;'
PRINT ''
PRINT '  3. Check job history:'
PRINT '     EXEC msdb.dbo.sp_help_jobhistory @job_name = ''MonitoringDB - Calculate Trends (Daily)'';'
PRINT ''
PRINT '  4. Enable/Disable jobs:'
PRINT '     EXEC msdb.dbo.sp_update_job @job_name = ''MonitoringDB - Calculate Trends (Daily)'', @enabled = 0;'
PRINT ''
PRINT '  5. Configure email notifications (Feature #3 integration):'
PRINT '     UPDATE MonitoringDB.dbo.PredictiveAlerts'
PRINT '     SET SendEmail = 1, EmailRecipients = ''your-email@example.com'''
PRINT '     WHERE AlertName = ''Memory - Increasing Utilization'';'
PRINT '======================================'
PRINT ''

GO
