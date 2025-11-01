-- =====================================================
-- Phase 3 - Feature #1: SQL Server Health Score
-- SQL Agent Job for Automated Health Score Calculation
-- =====================================================
-- File: 42-create-health-score-job.sql
-- Purpose: Create SQL Agent job to calculate health scores every 15 minutes
-- Dependencies: 41-create-health-score-procedures.sql
-- =====================================================

USE msdb;
GO

PRINT '======================================';
PRINT 'Creating Health Score SQL Agent Job';
PRINT '======================================';
PRINT '';

-- =====================================================
-- Delete existing job if it exists
-- =====================================================

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'Calculate Server Health Scores')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = 'Calculate Server Health Scores';
    PRINT 'Deleted existing job: Calculate Server Health Scores';
END;
PRINT '';

-- =====================================================
-- Create the job
-- =====================================================

DECLARE @jobId BINARY(16);

EXEC msdb.dbo.sp_add_job
    @job_name = 'Calculate Server Health Scores',
    @enabled = 1,
    @description = 'Calculates health scores for all monitored servers every 15 minutes using 7-component weighted algorithm',
    @category_name = 'Database Maintenance',
    @owner_login_name = 'sv',
    @job_id = @jobId OUTPUT;

PRINT '✅ Created job: Calculate Server Health Scores';
PRINT '';

-- =====================================================
-- Job Step: Calculate health scores for all servers
-- =====================================================

EXEC msdb.dbo.sp_add_jobstep
    @job_id = @jobId,
    @step_name = 'Calculate Health Scores for All Servers',
    @subsystem = 'TSQL',
    @database_name = 'MonitoringDB',
    @command = N'
SET NOCOUNT ON;

-- Calculate health score for each active server
DECLARE @ServerID INT;
DECLARE @ServerName NVARCHAR(255);
DECLARE @ErrorCount INT = 0;
DECLARE @SuccessCount INT = 0;

DECLARE server_cursor CURSOR FOR
    SELECT ServerID, ServerName
    FROM MonitoringDB.dbo.Servers
    WHERE IsActive = 1
    ORDER BY ServerID;

OPEN server_cursor;
FETCH NEXT FROM server_cursor INTO @ServerID, @ServerName;

WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        -- Calculate health score for this server
        EXEC MonitoringDB.dbo.usp_CalculateHealthScore @ServerID = @ServerID;

        SET @SuccessCount = @SuccessCount + 1;

        PRINT ''Calculated health score for '' + @ServerName + '' (ServerID='' + CAST(@ServerID AS VARCHAR) + '')'';
    END TRY
    BEGIN CATCH
        SET @ErrorCount = @ErrorCount + 1;

        PRINT ''ERROR calculating health score for '' + @ServerName + '' (ServerID='' + CAST(@ServerID AS VARCHAR) + ''): '' + ERROR_MESSAGE();

        -- Continue to next server even if one fails
    END CATCH;

    FETCH NEXT FROM server_cursor INTO @ServerID, @ServerName;
END;

CLOSE server_cursor;
DEALLOCATE server_cursor;

-- Print summary
PRINT '''';
PRINT ''======================================='';
PRINT ''Health Score Calculation Summary'';
PRINT ''======================================='';
PRINT ''Servers processed successfully: '' + CAST(@SuccessCount AS VARCHAR);
PRINT ''Servers with errors: '' + CAST(@ErrorCount AS VARCHAR);
PRINT ''======================================='';

-- Fail the job if all servers failed
IF @SuccessCount = 0 AND @ErrorCount > 0
BEGIN
    RAISERROR(''Health score calculation failed for all servers'', 16, 1);
END;
',
    @on_success_action = 1,  -- Quit with success
    @on_fail_action = 2,     -- Quit with failure
    @retry_attempts = 0;

PRINT '✅ Created job step: Calculate Health Scores for All Servers';
PRINT '';

-- =====================================================
-- Schedule: Every 15 minutes
-- =====================================================

DECLARE @scheduleId INT;

EXEC msdb.dbo.sp_add_jobschedule
    @job_id = @jobId,
    @name = 'Every 15 Minutes',
    @enabled = 1,
    @freq_type = 4,           -- Daily
    @freq_interval = 1,       -- Every 1 day
    @freq_subday_type = 4,    -- Minutes
    @freq_subday_interval = 15, -- Every 15 minutes
    @active_start_time = 0,   -- Start at midnight
    @active_end_time = 235959, -- End at 11:59:59 PM
    @schedule_id = @scheduleId OUTPUT;

PRINT '✅ Created schedule: Every 15 Minutes';
PRINT '';

-- =====================================================
-- Add job to local server
-- =====================================================

EXEC msdb.dbo.sp_add_jobserver
    @job_id = @jobId,
    @server_name = N'(local)';

PRINT '✅ Added job to local server';
PRINT '';

-- =====================================================
-- Verification
-- =====================================================

PRINT '======================================';
PRINT 'Verification';
PRINT '======================================';
PRINT '';

SELECT
    j.name AS JobName,
    j.enabled AS Enabled,
    s.name AS ScheduleName,
    CASE s.freq_subday_type
        WHEN 4 THEN 'Every ' + CAST(s.freq_subday_interval AS VARCHAR) + ' minutes'
        WHEN 8 THEN 'Every ' + CAST(s.freq_subday_interval AS VARCHAR) + ' hours'
        ELSE 'Other'
    END AS Frequency,
    j.description AS Description
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobschedules js ON j.job_id = js.job_id
INNER JOIN msdb.dbo.sysschedules s ON js.schedule_id = s.schedule_id
WHERE j.name = 'Calculate Server Health Scores';

PRINT '';
PRINT '======================================';
PRINT 'SQL Agent Job Created Successfully';
PRINT '======================================';
PRINT '';
PRINT 'Job Details:';
PRINT '  Name: Calculate Server Health Scores';
PRINT '  Schedule: Every 15 minutes (24/7)';
PRINT '  Action: Calculate health scores for all active servers';
PRINT '  Failure Handling: Continue to next server on error';
PRINT '';
PRINT 'Manual Execution:';
PRINT '  EXEC msdb.dbo.sp_start_job @job_name = ''Calculate Server Health Scores'';';
PRINT '';
PRINT 'View Job History:';
PRINT '  EXEC msdb.dbo.sp_help_jobhistory @job_name = ''Calculate Server Health Scores'';';
PRINT '';
PRINT 'Expected Data Growth:';
PRINT '  - 3 servers × 96 calculations/day = 288 rows/day';
PRINT '  - ~200 KB/day, ~6 MB/month, ~72 MB/year';
PRINT '';

GO
