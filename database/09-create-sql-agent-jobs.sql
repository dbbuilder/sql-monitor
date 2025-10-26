-- =====================================================
-- Script: 09-create-sql-agent-jobs.sql
-- Description: Create SQL Agent jobs for automated metric collection
-- Author: SQL Server Monitor Project
-- Date: 2025-10-25
-- Purpose: Schedule automated collection every 5 minutes
-- =====================================================

USE [msdb];
GO

PRINT '';
PRINT '========================================================';
PRINT 'SQL Server Monitor - SQL Agent Jobs Setup';
PRINT '========================================================';
PRINT '';

-- =====================================================
-- Job 1: Complete Metrics Collection (Server + Drill-Down)
-- Runs every 5 minutes
-- =====================================================

PRINT 'Creating Job: SQL Monitor - Complete Collection...';

-- Drop existing job if exists
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'SQL Monitor - Complete Collection')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = N'SQL Monitor - Complete Collection';
    PRINT '  [INFO] Deleted existing job';
END;

-- Create job
EXEC msdb.dbo.sp_add_job
    @job_name = N'SQL Monitor - Complete Collection',
    @enabled = 1,
    @description = N'Collects all SQL Server monitoring metrics (server-level + drill-down) every 5 minutes',
    @category_name = N'Database Maintenance';

PRINT '  [OK] Job created';

-- Add job step
EXEC msdb.dbo.sp_add_jobstep
    @job_name = N'SQL Monitor - Complete Collection',
    @step_name = N'Collect All Metrics',
    @subsystem = N'TSQL',
    @database_name = N'MonitoringDB',
    @command = N'EXEC dbo.usp_CollectAllMetrics @ServerID = 1, @VerboseOutput = 0;',
    @on_success_action = 1,  -- Quit with success
    @on_fail_action = 2,     -- Quit with failure
    @retry_attempts = 2,
    @retry_interval = 1;     -- 1 minute between retries

PRINT '  [OK] Job step added';

-- Create schedule (every 5 minutes)
EXEC msdb.dbo.sp_add_schedule
    @schedule_name = N'Every 5 Minutes',
    @freq_type = 4,              -- Daily
    @freq_interval = 1,          -- Every day
    @freq_subday_type = 4,       -- Minutes
    @freq_subday_interval = 5,   -- Every 5 minutes
    @active_start_time = 000000, -- Midnight
    @active_end_time = 235959;   -- 11:59:59 PM

PRINT '  [OK] Schedule created (every 5 minutes)';

-- Attach schedule to job
EXEC msdb.dbo.sp_attach_schedule
    @job_name = N'SQL Monitor - Complete Collection',
    @schedule_name = N'Every 5 Minutes';

PRINT '  [OK] Schedule attached to job';

-- Add job to local server
EXEC msdb.dbo.sp_add_jobserver
    @job_name = N'SQL Monitor - Complete Collection',
    @server_name = N'(LOCAL)';

PRINT '  [OK] Job added to local server';
PRINT '';

-- =====================================================
-- Job 2: Data Cleanup (Optional - runs daily at 2 AM)
-- Removes metrics older than 90 days
-- =====================================================

PRINT 'Creating Job: SQL Monitor - Data Cleanup...';

-- Drop existing job if exists
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'SQL Monitor - Data Cleanup')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = N'SQL Monitor - Data Cleanup';
    PRINT '  [INFO] Deleted existing job';
END;

-- Create cleanup job
EXEC msdb.dbo.sp_add_job
    @job_name = N'SQL Monitor - Data Cleanup',
    @enabled = 1,
    @description = N'Removes monitoring metrics older than 90 days to manage database size',
    @category_name = N'Database Maintenance';

PRINT '  [OK] Job created';

-- Add cleanup step
EXEC msdb.dbo.sp_add_jobstep
    @job_name = N'SQL Monitor - Data Cleanup',
    @step_name = N'Delete Old Metrics',
    @subsystem = N'TSQL',
    @database_name = N'MonitoringDB',
    @command = N'
-- Delete metrics older than 90 days
DECLARE @CutoffDate DATETIME2 = DATEADD(DAY, -90, GETUTCDATE());
DECLARE @RowsDeleted INT;

-- Delete from PerformanceMetrics
DELETE FROM dbo.PerformanceMetrics
WHERE CollectionTime < @CutoffDate;
SET @RowsDeleted = @@ROWCOUNT;
PRINT ''PerformanceMetrics: Deleted '' + CAST(@RowsDeleted AS VARCHAR(10)) + '' old records'';

-- Delete from DatabaseMetrics
DELETE FROM dbo.DatabaseMetrics
WHERE CollectionTime < @CutoffDate;
SET @RowsDeleted = @@ROWCOUNT;
PRINT ''DatabaseMetrics: Deleted '' + CAST(@RowsDeleted AS VARCHAR(10)) + '' old records'';

-- Delete from ProcedureMetrics
DELETE FROM dbo.ProcedureMetrics
WHERE CollectionTime < @CutoffDate;
SET @RowsDeleted = @@ROWCOUNT;
PRINT ''ProcedureMetrics: Deleted '' + CAST(@RowsDeleted AS VARCHAR(10)) + '' old records'';

-- Delete from QueryMetrics
DELETE FROM dbo.QueryMetrics
WHERE CollectionTime < @CutoffDate;
SET @RowsDeleted = @@ROWCOUNT;
PRINT ''QueryMetrics: Deleted '' + CAST(@RowsDeleted AS VARCHAR(10)) + '' old records'';

-- Delete from WaitEventsByDatabase
DELETE FROM dbo.WaitEventsByDatabase
WHERE CollectionTime < @CutoffDate;
SET @RowsDeleted = @@ROWCOUNT;
PRINT ''WaitEventsByDatabase: Deleted '' + CAST(@RowsDeleted AS VARCHAR(10)) + '' old records'';

-- Delete from ConnectionsByDatabase
DELETE FROM dbo.ConnectionsByDatabase
WHERE CollectionTime < @CutoffDate;
SET @RowsDeleted = @@ROWCOUNT;
PRINT ''ConnectionsByDatabase: Deleted '' + CAST(@RowsDeleted AS VARCHAR(10)) + '' old records'';

PRINT ''Cleanup completed successfully'';
',
    @on_success_action = 1,
    @on_fail_action = 2,
    @retry_attempts = 1,
    @retry_interval = 5;

PRINT '  [OK] Job step added';

-- Create schedule (daily at 2 AM)
EXEC msdb.dbo.sp_add_schedule
    @schedule_name = N'Daily at 2 AM',
    @freq_type = 4,              -- Daily
    @freq_interval = 1,          -- Every day
    @freq_subday_type = 1,       -- At specified time
    @active_start_time = 020000; -- 2:00 AM

PRINT '  [OK] Schedule created (daily at 2 AM)';

-- Attach schedule to job
EXEC msdb.dbo.sp_attach_schedule
    @job_name = N'SQL Monitor - Data Cleanup',
    @schedule_name = N'Daily at 2 AM';

PRINT '  [OK] Schedule attached to job';

-- Add job to local server
EXEC msdb.dbo.sp_add_jobserver
    @job_name = N'SQL Monitor - Data Cleanup',
    @server_name = N'(LOCAL)';

PRINT '  [OK] Job added to local server';
PRINT '';

-- =====================================================
-- Display job status
-- =====================================================

PRINT '========================================================';
PRINT 'SQL Agent Jobs Created Successfully';
PRINT '========================================================';
PRINT '';
PRINT 'Jobs created:';
PRINT '  1. SQL Monitor - Complete Collection';
PRINT '     Schedule: Every 5 minutes';
PRINT '     Purpose: Collect all server + drill-down metrics';
PRINT '';
PRINT '  2. SQL Monitor - Data Cleanup';
PRINT '     Schedule: Daily at 2:00 AM';
PRINT '     Purpose: Remove metrics older than 90 days';
PRINT '';
PRINT 'Job Management Commands:';
PRINT '  -- Start job manually:';
PRINT '  EXEC msdb.dbo.sp_start_job @job_name = N''SQL Monitor - Complete Collection'';';
PRINT '';
PRINT '  -- View job history:';
PRINT '  EXEC msdb.dbo.sp_help_jobhistory @job_name = N''SQL Monitor - Complete Collection'';';
PRINT '';
PRINT '  -- Disable job:';
PRINT '  EXEC msdb.dbo.sp_update_job @job_name = N''SQL Monitor - Complete Collection'', @enabled = 0;';
PRINT '';
PRINT '  -- Enable job:';
PRINT '  EXEC msdb.dbo.sp_update_job @job_name = N''SQL Monitor - Complete Collection'', @enabled = 1;';
PRINT '';
PRINT '  -- Delete job:';
PRINT '  EXEC msdb.dbo.sp_delete_job @job_name = N''SQL Monitor - Complete Collection'';';
PRINT '';
PRINT 'Next collection will occur in 5 minutes or less.';
PRINT '========================================================';
GO

-- Verify jobs were created
SELECT
    j.name AS JobName,
    j.enabled AS Enabled,
    j.description AS Description,
    s.name AS ScheduleName,
    CASE s.freq_type
        WHEN 4 THEN 'Daily'
        WHEN 8 THEN 'Weekly'
        WHEN 16 THEN 'Monthly'
        ELSE 'Other'
    END AS Frequency,
    CASE s.freq_subday_type
        WHEN 1 THEN 'At specified time'
        WHEN 4 THEN 'Every ' + CAST(s.freq_subday_interval AS VARCHAR(10)) + ' minutes'
        WHEN 8 THEN 'Every ' + CAST(s.freq_subday_interval AS VARCHAR(10)) + ' hours'
        ELSE 'Other'
    END AS SubdayFrequency,
    STUFF(STUFF(RIGHT('000000' + CAST(s.active_start_time AS VARCHAR(6)), 6), 5, 0, ':'), 3, 0, ':') AS StartTime
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobschedules js ON j.job_id = js.job_id
INNER JOIN msdb.dbo.sysschedules s ON js.schedule_id = s.schedule_id
WHERE j.name LIKE 'SQL Monitor%'
ORDER BY j.name;
GO
