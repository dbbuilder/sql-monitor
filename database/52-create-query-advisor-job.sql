-- =====================================================
-- Phase 3 - Feature #2: Query Performance Advisor
-- SQL Agent Job for Automated Query Analysis
-- =====================================================
-- File: 52-create-query-advisor-job.sql
-- Purpose: Create SQL Agent job to analyze query performance daily
-- Dependencies: 51-create-query-advisor-procedures.sql
-- =====================================================

USE msdb;
GO

PRINT '======================================';
PRINT 'Creating Query Performance Advisor SQL Agent Job';
PRINT '======================================';
PRINT '';

-- =====================================================
-- Delete existing job if it exists
-- =====================================================

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'Analyze Query Performance - All Servers')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = 'Analyze Query Performance - All Servers';
    PRINT 'Deleted existing job: Analyze Query Performance - All Servers';
END;
PRINT '';

-- =====================================================
-- Create the job
-- =====================================================

DECLARE @jobId BINARY(16);

EXEC msdb.dbo.sp_add_job
    @job_name = 'Analyze Query Performance - All Servers',
    @enabled = 1,
    @description = 'Analyzes query performance and generates optimization recommendations for all monitored servers',
    @category_name = 'Database Maintenance',
    @owner_login_name = 'sv',
    @job_id = @jobId OUTPUT;

PRINT '✅ Created job: Analyze Query Performance - All Servers';
PRINT '';

-- =====================================================
-- Job Step 1: Analyze Query Performance
-- =====================================================

EXEC msdb.dbo.sp_add_jobstep
    @job_id = @jobId,
    @step_name = 'Analyze Query Performance for All Servers',
    @subsystem = 'TSQL',
    @database_name = 'MonitoringDB',
    @command = N'
SET NOCOUNT ON;

DECLARE @ServerID INT;
DECLARE @ServerName NVARCHAR(255);
DECLARE @ErrorCount INT = 0;
DECLARE @SuccessCount INT = 0;
DECLARE @TotalRecommendations INT = 0;

PRINT ''======================================='';
PRINT ''Query Performance Analysis - Starting'';
PRINT ''======================================='';
PRINT '''';

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
        DECLARE @Recommendations INT;

        -- Analyze query performance
        EXEC MonitoringDB.dbo.usp_AnalyzeQueryPerformance @ServerID = @ServerID;

        -- Get recommendation count
        SELECT @Recommendations = COUNT(*)
        FROM MonitoringDB.dbo.QueryPerformanceRecommendations
        WHERE ServerID = @ServerID
          AND DetectionTime >= DATEADD(MINUTE, -5, GETUTCDATE());

        SET @SuccessCount = @SuccessCount + 1;
        SET @TotalRecommendations = @TotalRecommendations + @Recommendations;

        PRINT ''✅ '' + @ServerName + '' (ServerID='' + CAST(@ServerID AS VARCHAR) + ''): '' +
              CAST(@Recommendations AS VARCHAR) + '' new recommendations'';
    END TRY
    BEGIN CATCH
        SET @ErrorCount = @ErrorCount + 1;
        PRINT ''❌ '' + @ServerName + '' (ServerID='' + CAST(@ServerID AS VARCHAR) + ''): '' + ERROR_MESSAGE();
    END CATCH;

    FETCH NEXT FROM server_cursor INTO @ServerID, @ServerName;
END;

CLOSE server_cursor;
DEALLOCATE server_cursor;

PRINT '''';
PRINT ''======================================='';
PRINT ''Query Performance Analysis Summary'';
PRINT ''======================================='';
PRINT ''Servers analyzed successfully: '' + CAST(@SuccessCount AS VARCHAR);
PRINT ''Servers with errors: '' + CAST(@ErrorCount AS VARCHAR);
PRINT ''Total new recommendations: '' + CAST(@TotalRecommendations AS VARCHAR);
PRINT ''======================================='';

-- Fail the job if all servers failed
IF @SuccessCount = 0 AND @ErrorCount > 0
BEGIN
    RAISERROR(''Query performance analysis failed for all servers'', 16, 1);
END;
',
    @on_success_action = 3,  -- Go to next step
    @on_fail_action = 2,     -- Quit with failure
    @retry_attempts = 0;

PRINT '✅ Created job step 1: Analyze Query Performance';
PRINT '';

-- =====================================================
-- Job Step 2: Detect Plan Regressions
-- =====================================================

EXEC msdb.dbo.sp_add_jobstep
    @job_id = @jobId,
    @step_name = 'Detect Plan Regressions for All Servers',
    @subsystem = 'TSQL',
    @database_name = 'MonitoringDB',
    @command = N'
SET NOCOUNT ON;

DECLARE @ServerID INT;
DECLARE @ServerName NVARCHAR(255);
DECLARE @ErrorCount INT = 0;
DECLARE @SuccessCount INT = 0;
DECLARE @TotalRegressions INT = 0;

PRINT ''======================================='';
PRINT ''Plan Regression Detection - Starting'';
PRINT ''======================================='';
PRINT '''';

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
        DECLARE @Regressions INT;

        -- Detect plan regressions
        EXEC MonitoringDB.dbo.usp_DetectPlanRegressions
            @ServerID = @ServerID,
            @RegressionThresholdPercent = 50.0;

        -- Get regression count
        SELECT @Regressions = COUNT(*)
        FROM MonitoringDB.dbo.QueryPlanRegressions
        WHERE ServerID = @ServerID
          AND DetectionTime >= DATEADD(MINUTE, -5, GETUTCDATE())
          AND IsResolved = 0;

        SET @SuccessCount = @SuccessCount + 1;
        SET @TotalRegressions = @TotalRegressions + @Regressions;

        PRINT ''✅ '' + @ServerName + '' (ServerID='' + CAST(@ServerID AS VARCHAR) + ''): '' +
              CAST(@Regressions AS VARCHAR) + '' new regressions'';
    END TRY
    BEGIN CATCH
        SET @ErrorCount = @ErrorCount + 1;
        PRINT ''❌ '' + @ServerName + '' (ServerID='' + CAST(@ServerID AS VARCHAR) + ''): '' + ERROR_MESSAGE();
    END CATCH;

    FETCH NEXT FROM server_cursor INTO @ServerID, @ServerName;
END;

CLOSE server_cursor;
DEALLOCATE server_cursor;

PRINT '''';
PRINT ''======================================='';
PRINT ''Plan Regression Detection Summary'';
PRINT ''======================================='';
PRINT ''Servers analyzed successfully: '' + CAST(@SuccessCount AS VARCHAR);
PRINT ''Servers with errors: '' + CAST(@ErrorCount AS VARCHAR);
PRINT ''Total new regressions: '' + CAST(@TotalRegressions AS VARCHAR);
PRINT ''======================================='';

-- Continue even if all servers failed (non-critical)
',
    @on_success_action = 1,  -- Quit with success
    @on_fail_action = 1,     -- Quit with success (non-critical step)
    @retry_attempts = 0;

PRINT '✅ Created job step 2: Detect Plan Regressions';
PRINT '';

-- =====================================================
-- Schedule: Daily at 2:00 AM
-- =====================================================

DECLARE @scheduleId INT;

EXEC msdb.dbo.sp_add_jobschedule
    @job_id = @jobId,
    @name = 'Daily at 2:00 AM',
    @enabled = 1,
    @freq_type = 4,           -- Daily
    @freq_interval = 1,       -- Every 1 day
    @freq_subday_type = 1,    -- At specified time
    @freq_subday_interval = 0,
    @active_start_time = 20000, -- 2:00:00 AM
    @schedule_id = @scheduleId OUTPUT;

PRINT '✅ Created schedule: Daily at 2:00 AM';
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
    js.step_name AS StepName,
    s.name AS ScheduleName,
    CASE
        WHEN s.freq_type = 4 THEN 'Daily'
        WHEN s.freq_type = 8 THEN 'Weekly'
        ELSE 'Other'
    END + ' at ' +
    STUFF(STUFF(RIGHT('000000' + CAST(s.active_start_time AS VARCHAR), 6), 5, 0, ':'), 3, 0, ':') AS Schedule,
    j.description AS Description
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobschedules jsc ON j.job_id = jsc.job_id
INNER JOIN msdb.dbo.sysschedules s ON jsc.schedule_id = s.schedule_id
LEFT JOIN msdb.dbo.sysjobsteps js ON j.job_id = js.job_id
WHERE j.name = 'Analyze Query Performance - All Servers'
ORDER BY js.step_id;

PRINT '';
PRINT '======================================';
PRINT 'SQL Agent Job Created Successfully';
PRINT '======================================';
PRINT '';
PRINT 'Job Details:';
PRINT '  Name: Analyze Query Performance - All Servers';
PRINT '  Schedule: Daily at 2:00 AM';
PRINT '  Steps:';
PRINT '    1. Analyze query performance for all servers';
PRINT '    2. Detect execution plan regressions';
PRINT '';
PRINT 'Manual Execution:';
PRINT '  EXEC msdb.dbo.sp_start_job @job_name = ''Analyze Query Performance - All Servers'';';
PRINT '';
PRINT 'View Job History:';
PRINT '  EXEC msdb.dbo.sp_help_jobhistory @job_name = ''Analyze Query Performance - All Servers'';';
PRINT '';
PRINT 'Expected Data Growth:';
PRINT '  - ~50-100 recommendations/day across 3 servers';
PRINT '  - ~5-10 plan regressions/week';
PRINT '  - ~50 KB/day, ~1.5 MB/month, ~18 MB/year';
PRINT '';

GO
