-- =====================================================
-- Phase 3 - Feature #6: Automated Index Maintenance
-- SQL Agent Jobs for Automated Index Maintenance
-- =====================================================
-- File: 86-create-index-maintenance-sql-agent-jobs.sql
-- Purpose: Create SQL Agent jobs for fragmentation collection and maintenance execution
-- Dependencies: 84-create-index-maintenance-tables.sql
--               85-create-index-maintenance-procedures.sql
-- =====================================================

USE msdb;
GO

SET NOCOUNT ON;
GO

PRINT '======================================'
PRINT 'Creating Index Maintenance SQL Agent Jobs'
PRINT '======================================'
PRINT ''

-- =====================================================
-- Job 1: Collect Index Fragmentation (Every 6 Hours)
-- Runs at: 00:00, 06:00, 12:00, 18:00
-- =====================================================

DECLARE @jobName1 NVARCHAR(128) = N'MonitoringDB - Collect Index Fragmentation (6 Hours)';
DECLARE @jobId1 BINARY(16);

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @jobName1)
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @jobName1;
    PRINT 'Deleted existing job: ' + @jobName1;
END;

EXEC msdb.dbo.sp_add_job
    @job_name = @jobName1,
    @enabled = 1,
    @description = N'Collect index fragmentation data from all monitored SQL Server instances',
    @category_name = N'Database Maintenance',
    @job_id = @jobId1 OUTPUT;

-- Add job step
EXEC msdb.dbo.sp_add_jobstep
    @job_name = @jobName1,
    @step_name = N'Collect Fragmentation Data',
    @subsystem = N'TSQL',
    @command = N'
EXEC MonitoringDB.dbo.usp_CollectIndexFragmentation;
',
    @database_name = N'MonitoringDB',
    @on_success_action = 1, -- Quit with success
    @on_fail_action = 2,    -- Quit with failure
    @retry_attempts = 3,
    @retry_interval = 5;

-- Add schedule: Every 6 hours
EXEC msdb.dbo.sp_add_jobschedule
    @job_name = @jobName1,
    @name = N'Every 6 Hours',
    @enabled = 1,
    @freq_type = 4,              -- Daily
    @freq_interval = 1,          -- Every 1 day
    @freq_subday_type = 8,       -- Hours
    @freq_subday_interval = 6,   -- Every 6 hours
    @freq_recurrence_factor = 1,
    @active_start_time = 000000; -- 00:00:00 AM

-- Add job to local server
EXEC msdb.dbo.sp_add_jobserver
    @job_name = @jobName1,
    @server_name = N'(local)';

PRINT 'Created job: ' + @jobName1;
PRINT '  Schedule: Every 6 hours (00:00, 06:00, 12:00, 18:00)';
PRINT ''
GO

-- =====================================================
-- Job 2: Collect Statistics Info (Every 6 Hours)
-- Runs at: 00:30, 06:30, 12:30, 18:30 (offset from fragmentation)
-- =====================================================

DECLARE @jobName2 NVARCHAR(128) = N'MonitoringDB - Collect Statistics Info (6 Hours)';
DECLARE @jobId2 BINARY(16);

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @jobName2)
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @jobName2;
    PRINT 'Deleted existing job: ' + @jobName2;
END;

EXEC msdb.dbo.sp_add_job
    @job_name = @jobName2,
    @enabled = 1,
    @description = N'Collect statistics freshness information from all monitored SQL Server instances',
    @category_name = N'Database Maintenance',
    @job_id = @jobId2 OUTPUT;

-- Add job step
EXEC msdb.dbo.sp_add_jobstep
    @job_name = @jobName2,
    @step_name = N'Collect Statistics Info',
    @subsystem = N'TSQL',
    @command = N'
EXEC MonitoringDB.dbo.usp_CollectStatisticsInfo;
',
    @database_name = N'MonitoringDB',
    @on_success_action = 1, -- Quit with success
    @on_fail_action = 2,    -- Quit with failure
    @retry_attempts = 3,
    @retry_interval = 5;

-- Add schedule: Every 6 hours, starting at 00:30
EXEC msdb.dbo.sp_add_jobschedule
    @job_name = @jobName2,
    @name = N'Every 6 Hours (offset 30 min)',
    @enabled = 1,
    @freq_type = 4,              -- Daily
    @freq_interval = 1,          -- Every 1 day
    @freq_subday_type = 8,       -- Hours
    @freq_subday_interval = 6,   -- Every 6 hours
    @freq_recurrence_factor = 1,
    @active_start_time = 003000; -- 00:30:00 AM

-- Add job to local server
EXEC msdb.dbo.sp_add_jobserver
    @job_name = @jobName2,
    @server_name = N'(local)';

PRINT 'Created job: ' + @jobName2;
PRINT '  Schedule: Every 6 hours (00:30, 06:30, 12:30, 18:30)';
PRINT ''
GO

-- =====================================================
-- Job 3: Weekly Index Maintenance (Saturday 2:00 AM)
-- Runs index maintenance and statistics updates
-- =====================================================

DECLARE @jobName3 NVARCHAR(128) = N'MonitoringDB - Perform Index Maintenance (Weekly)';
DECLARE @jobId3 BINARY(16);

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @jobName3)
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @jobName3;
    PRINT 'Deleted existing job: ' + @jobName3;
END;

EXEC msdb.dbo.sp_add_job
    @job_name = @jobName3,
    @enabled = 1,
    @description = N'Weekly index maintenance: rebuild/reorganize fragmented indexes and update outdated statistics',
    @category_name = N'Database Maintenance',
    @job_id = @jobId3 OUTPUT;

-- Step 1: Perform index maintenance
EXEC msdb.dbo.sp_add_jobstep
    @job_name = @jobName3,
    @step_name = N'Step 1: Index Maintenance',
    @subsystem = N'TSQL',
    @command = N'
PRINT ''Starting index maintenance...'';

EXEC MonitoringDB.dbo.usp_PerformIndexMaintenance
    @MinFragmentationPercent = 5.0,
    @RebuildThreshold = 30.0,
    @MinPageCount = 1000,
    @DryRun = 0,
    @MaxDurationMinutes = 240; -- 4 hours max

PRINT ''Index maintenance complete.'';
',
    @database_name = N'MonitoringDB',
    @on_success_action = 3, -- Go to next step
    @on_fail_action = 3,    -- Go to next step (continue with stats update even if maintenance fails)
    @retry_attempts = 2,
    @retry_interval = 10;

-- Step 2: Update statistics
EXEC msdb.dbo.sp_add_jobstep
    @job_name = @jobName3,
    @step_name = N'Step 2: Update Statistics',
    @subsystem = N'TSQL',
    @command = N'
PRINT ''Starting statistics update...'';

EXEC MonitoringDB.dbo.usp_UpdateStatistics
    @MinDaysSinceUpdate = 7,
    @MinModificationPercent = 20.0,
    @DryRun = 0;

PRINT ''Statistics update complete.'';
',
    @database_name = N'MonitoringDB',
    @on_success_action = 1, -- Quit with success
    @on_fail_action = 2,    -- Quit with failure
    @retry_attempts = 2,
    @retry_interval = 10;

-- Add schedule: Weekly on Saturday at 2:00 AM
EXEC msdb.dbo.sp_add_jobschedule
    @job_name = @jobName3,
    @name = N'Weekly Saturday 2:00 AM',
    @enabled = 1,
    @freq_type = 8,              -- Weekly
    @freq_interval = 64,         -- Saturday (2^6 = 64)
    @freq_subday_type = 1,       -- At specified time
    @freq_recurrence_factor = 1, -- Every week
    @active_start_time = 020000; -- 02:00:00 AM

-- Add job to local server
EXEC msdb.dbo.sp_add_jobserver
    @job_name = @jobName3,
    @server_name = N'(local)';

PRINT 'Created job: ' + @jobName3;
PRINT '  Schedule: Weekly on Saturday at 2:00 AM';
PRINT '  Step 1: Index Maintenance (up to 4 hours)';
PRINT '  Step 2: Update Statistics';
PRINT ''
GO

-- =====================================================
-- Summary and Verification
-- =====================================================

PRINT '======================================'
PRINT 'Index Maintenance SQL Agent Jobs Created'
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
                WHEN 8 THEN 'Every ' + CAST(s.freq_subday_interval AS VARCHAR) + ' hours starting at ' +
                            RIGHT('0' + CAST(s.active_start_time / 10000 AS VARCHAR), 2) + ':' +
                            RIGHT('0' + CAST((s.active_start_time % 10000) / 100 AS VARCHAR), 2)
                ELSE 'Daily'
            END
        WHEN 8 THEN 'Weekly on ' +
            CASE
                WHEN s.freq_interval & 1 = 1 THEN 'Sunday '
                ELSE ''
            END +
            CASE
                WHEN s.freq_interval & 64 = 64 THEN 'Saturday '
                ELSE ''
            END +
            'at ' + RIGHT('0' + CAST(s.active_start_time / 10000 AS VARCHAR), 2) + ':' +
                    RIGHT('0' + CAST((s.active_start_time % 10000) / 100 AS VARCHAR), 2)
        ELSE 'Other'
    END AS Schedule,
    (SELECT COUNT(*) FROM msdb.dbo.sysjobsteps js WHERE js.job_id = j.job_id) AS StepCount
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobschedules js ON j.job_id = js.job_id
INNER JOIN msdb.dbo.sysschedules s ON js.schedule_id = s.schedule_id
WHERE j.name LIKE 'MonitoringDB%Index%'
   OR j.name LIKE 'MonitoringDB%Statistics%'
   OR j.name LIKE 'MonitoringDB%Maintenance%'
ORDER BY j.name;

PRINT ''
PRINT 'Manual Test Commands:'
PRINT '  -- Start fragmentation collection manually'
PRINT '  EXEC msdb.dbo.sp_start_job @job_name = ''MonitoringDB - Collect Index Fragmentation (6 Hours)'';'
PRINT ''
PRINT '  -- Start statistics collection manually'
PRINT '  EXEC msdb.dbo.sp_start_job @job_name = ''MonitoringDB - Collect Statistics Info (6 Hours)'';'
PRINT ''
PRINT '  -- Preview maintenance actions (dry run)'
PRINT '  EXEC MonitoringDB.dbo.usp_PerformIndexMaintenance @DryRun = 1;'
PRINT ''
PRINT '  -- Run maintenance manually (NOT recommended during business hours)'
PRINT '  EXEC msdb.dbo.sp_start_job @job_name = ''MonitoringDB - Perform Index Maintenance (Weekly)'';'
PRINT ''
PRINT '  -- Check job history'
PRINT '  EXEC msdb.dbo.sp_help_jobhistory'
PRINT '      @job_name = ''MonitoringDB - Collect Index Fragmentation (6 Hours)'','
PRINT '      @mode = ''SUMMARY'';'
PRINT ''

PRINT 'Next Steps:'
PRINT '  1. Allow 6 hours for first fragmentation/statistics collection'
PRINT '  2. Review fragmentation data:'
PRINT '     SELECT TOP 20 * FROM MonitoringDB.dbo.IndexFragmentation'
PRINT '     WHERE FragmentationPercent > 30 ORDER BY PageCount DESC;'
PRINT ''
PRINT '  3. Test maintenance with dry run:'
PRINT '     EXEC MonitoringDB.dbo.usp_PerformIndexMaintenance @DryRun = 1;'
PRINT ''
PRINT '  4. Wait for Saturday 2:00 AM for first automated maintenance'
PRINT '  5. Review maintenance history:'
PRINT '     EXEC MonitoringDB.dbo.usp_GetMaintenanceSummary @DaysBack = 7;'
PRINT ''

PRINT '======================================'
PRINT ''

GO
