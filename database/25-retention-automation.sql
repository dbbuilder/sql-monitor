-- =============================================
-- Phase 2.0 Week 2 Day 10: Retention Automation
-- Description: SQL Agent jobs for automated data retention and cleanup
-- SOC 2 Controls: CC6.5, CC7.2 (Data Retention, Archival)
-- =============================================

USE MonitoringDB;
GO

PRINT 'Starting Retention Automation deployment...';
GO

-- =============================================
-- PART 1: Data Retention Procedures
-- =============================================
PRINT '';
PRINT '=============================================='
PRINT 'PART 1: Data Retention Procedures'
PRINT '=============================================='
PRINT '';

-- Procedure: Clean up old performance metrics (keep 90 days)
CREATE OR ALTER PROCEDURE dbo.usp_CleanupOldMetrics
    @RetentionDays INT = 90,
    @BatchSize INT = 10000
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CutoffDate DATETIME2 = DATEADD(DAY, -@RetentionDays, SYSUTCDATETIME());
    DECLARE @RowsDeleted INT = 0;
    DECLARE @TotalRowsDeleted INT = 0;
    DECLARE @StartTime DATETIME2 = SYSUTCDATETIME();

    PRINT 'Starting cleanup of PerformanceMetrics older than ' + CAST(@RetentionDays AS NVARCHAR(10)) + ' days...';
    PRINT 'Cutoff date: ' + CAST(@CutoffDate AS NVARCHAR(50));

    -- Delete in batches to avoid locking
    WHILE 1 = 1
    BEGIN
        DELETE TOP (@BatchSize)
        FROM dbo.PerformanceMetrics
        WHERE CollectionTime < @CutoffDate;

        SET @RowsDeleted = @@ROWCOUNT;
        SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted;

        IF @RowsDeleted = 0
            BREAK;

        -- Log progress
        IF @TotalRowsDeleted % 100000 = 0
            PRINT 'Deleted ' + CAST(@TotalRowsDeleted AS NVARCHAR(20)) + ' rows...';

        -- Small delay between batches
        WAITFOR DELAY '00:00:00.100';
    END

    DECLARE @DurationSeconds INT = DATEDIFF(SECOND, @StartTime, SYSUTCDATETIME());

    PRINT 'Cleanup complete. Total rows deleted: ' + CAST(@TotalRowsDeleted AS NVARCHAR(20));
    PRINT 'Duration: ' + CAST(@DurationSeconds AS NVARCHAR(10)) + ' seconds';

    -- Log retention event
    EXEC dbo.usp_LogAuditEvent
        @EventType = 'DataRetentionCleanup',
        @UserName = 'SQL Agent',
        @ObjectName = 'PerformanceMetrics',
        @ObjectType = 'Table',
        @ActionType = 'DELETE',
        @AffectedRows = @TotalRowsDeleted,
        @Severity = 'Information',
        @ComplianceFlag = 'SOC2',
        @RetentionDays = 2555;

    RETURN @TotalRowsDeleted;
END;
GO

PRINT 'Procedure usp_CleanupOldMetrics created.';
GO

-- Procedure: Archive old audit logs (move to archive table, keep 7 years)
CREATE OR ALTER PROCEDURE dbo.usp_ArchiveOldAuditLogs
    @ArchiveAfterDays INT = 365,  -- Archive logs older than 1 year
    @RetentionDays INT = 2555,    -- Keep archived logs for 7 years
    @BatchSize INT = 10000
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ArchiveCutoff DATETIME2 = DATEADD(DAY, -@ArchiveAfterDays, SYSUTCDATETIME());
    DECLARE @DeleteCutoff DATETIME2 = DATEADD(DAY, -@RetentionDays, SYSUTCDATETIME());
    DECLARE @RowsArchived INT = 0;
    DECLARE @RowsDeleted INT = 0;
    DECLARE @StartTime DATETIME2 = SYSUTCDATETIME();

    PRINT 'Starting archive of AuditLog entries older than ' + CAST(@ArchiveAfterDays AS NVARCHAR(10)) + ' days...';

    -- Create archive table if it doesn't exist
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'AuditLog_Archive')
    BEGIN
        PRINT 'Creating AuditLog_Archive table...';

        SELECT TOP 0 *
        INTO dbo.AuditLog_Archive
        FROM dbo.AuditLog;

        -- Add clustered index on ArchiveDate
        CREATE CLUSTERED INDEX IX_AuditLog_Archive_EventTime
        ON dbo.AuditLog_Archive(EventTime);

        PRINT 'AuditLog_Archive table created.';
    END

    -- Archive old audit logs
    WHILE 1 = 1
    BEGIN
        INSERT INTO dbo.AuditLog_Archive
        SELECT TOP (@BatchSize) *
        FROM dbo.AuditLog
        WHERE EventTime < @ArchiveCutoff
          AND EventTime >= @DeleteCutoff -- Don't archive logs that should be deleted
          AND AuditID NOT IN (SELECT AuditID FROM dbo.AuditLog_Archive);

        SET @RowsArchived = @@ROWCOUNT;

        IF @RowsArchived = 0
            BREAK;

        -- Log progress
        IF @RowsArchived % 100000 = 0
            PRINT 'Archived ' + CAST(@RowsArchived AS NVARCHAR(20)) + ' rows...';

        WAITFOR DELAY '00:00:00.100';
    END

    PRINT 'Archive complete. Total rows archived: ' + CAST(@RowsArchived AS NVARCHAR(20));

    -- Delete archived logs from main table
    DECLARE @TotalDeleted INT = 0;
    WHILE 1 = 1
    BEGIN
        DELETE TOP (@BatchSize)
        FROM dbo.AuditLog
        WHERE EventTime < @ArchiveCutoff
          AND AuditID IN (SELECT AuditID FROM dbo.AuditLog_Archive);

        SET @RowsDeleted = @@ROWCOUNT;
        SET @TotalDeleted = @TotalDeleted + @RowsDeleted;

        IF @RowsDeleted = 0
            BREAK;

        WAITFOR DELAY '00:00:00.100';
    END

    PRINT 'Deleted ' + CAST(@TotalDeleted AS NVARCHAR(20)) + ' archived rows from AuditLog.';

    -- Delete very old archived logs
    DECLARE @VeryOldDeleted INT = 0;
    WHILE 1 = 1
    BEGIN
        DELETE TOP (@BatchSize)
        FROM dbo.AuditLog_Archive
        WHERE EventTime < @DeleteCutoff;

        SET @RowsDeleted = @@ROWCOUNT;
        SET @VeryOldDeleted = @VeryOldDeleted + @RowsDeleted;

        IF @RowsDeleted = 0
            BREAK;

        WAITFOR DELAY '00:00:00.100';
    END

    IF @VeryOldDeleted > 0
        PRINT 'Deleted ' + CAST(@VeryOldDeleted AS NVARCHAR(20)) + ' very old rows from AuditLog_Archive.';

    DECLARE @DurationSeconds INT = DATEDIFF(SECOND, @StartTime, SYSUTCDATETIME());
    PRINT 'Archive/cleanup complete. Duration: ' + CAST(@DurationSeconds AS NVARCHAR(10)) + ' seconds';

    RETURN @RowsArchived + @VeryOldDeleted;
END;
GO

PRINT 'Procedure usp_ArchiveOldAuditLogs created.';
GO

-- Procedure: Clean up old blocking events (keep 180 days)
CREATE OR ALTER PROCEDURE dbo.usp_CleanupOldBlockingEvents
    @RetentionDays INT = 180,
    @BatchSize INT = 5000
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CutoffDate DATETIME2 = DATEADD(DAY, -@RetentionDays, SYSUTCDATETIME());
    DECLARE @RowsDeleted INT = 0;

    PRINT 'Cleaning up BlockingEvents older than ' + CAST(@RetentionDays AS NVARCHAR(10)) + ' days...';

    WHILE 1 = 1
    BEGIN
        DELETE TOP (@BatchSize)
        FROM dbo.BlockingEvents
        WHERE EventTime < @CutoffDate;

        SET @RowsDeleted = @@ROWCOUNT;

        IF @RowsDeleted = 0
            BREAK;

        WAITFOR DELAY '00:00:00.100';
    END

    PRINT 'BlockingEvents cleanup complete.';

    RETURN 0;
END;
GO

PRINT 'Procedure usp_CleanupOldBlockingEvents created.';
GO

-- Procedure: Clean up old deadlock events (keep 180 days)
CREATE OR ALTER PROCEDURE dbo.usp_CleanupOldDeadlockEvents
    @RetentionDays INT = 180,
    @BatchSize INT = 5000
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CutoffDate DATETIME2 = DATEADD(DAY, -@RetentionDays, SYSUTCDATETIME());
    DECLARE @RowsDeleted INT = 0;

    PRINT 'Cleaning up DeadlockEvents older than ' + CAST(@RetentionDays AS NVARCHAR(10)) + ' days...';

    WHILE 1 = 1
    BEGIN
        DELETE TOP (@BatchSize)
        FROM dbo.DeadlockEvents
        WHERE EventTime < @CutoffDate;

        SET @RowsDeleted = @@ROWCOUNT;

        IF @RowsDeleted = 0
            BREAK;

        WAITFOR DELAY '00:00:00.100';
    END

    PRINT 'DeadlockEvents cleanup complete.';

    RETURN 0;
END;
GO

PRINT 'Procedure usp_CleanupOldDeadlockEvents created.';
GO

-- Master cleanup procedure (calls all cleanup procedures)
CREATE OR ALTER PROCEDURE dbo.usp_MasterCleanup
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartTime DATETIME2 = SYSUTCDATETIME();
    DECLARE @TotalRowsDeleted INT = 0;
    DECLARE @ReturnCode INT;

    PRINT '=============================================='
    PRINT 'Master Cleanup Job Started'
    PRINT 'Start Time: ' + CAST(@StartTime AS NVARCHAR(50));
    PRINT '=============================================='

    -- Cleanup performance metrics (90 days)
    PRINT '';
    PRINT 'Step 1: Cleanup Performance Metrics';
    PRINT '-------------------------------------';
    EXEC @ReturnCode = dbo.usp_CleanupOldMetrics @RetentionDays = 90;
    SET @TotalRowsDeleted = @TotalRowsDeleted + @ReturnCode;

    -- Archive audit logs (1 year archival, 7 years total retention)
    PRINT '';
    PRINT 'Step 2: Archive Audit Logs';
    PRINT '-------------------------------------';
    EXEC @ReturnCode = dbo.usp_ArchiveOldAuditLogs
        @ArchiveAfterDays = 365,
        @RetentionDays = 2555;
    SET @TotalRowsDeleted = @TotalRowsDeleted + @ReturnCode;

    -- Cleanup blocking events (180 days)
    PRINT '';
    PRINT 'Step 3: Cleanup Blocking Events';
    PRINT '-------------------------------------';
    EXEC dbo.usp_CleanupOldBlockingEvents @RetentionDays = 180;

    -- Cleanup deadlock events (180 days)
    PRINT '';
    PRINT 'Step 4: Cleanup Deadlock Events';
    PRINT '-------------------------------------';
    EXEC dbo.usp_CleanupOldDeadlockEvents @RetentionDays = 180;

    DECLARE @EndTime DATETIME2 = SYSUTCDATETIME();
    DECLARE @DurationMinutes INT = DATEDIFF(MINUTE, @StartTime, @EndTime);

    PRINT '';
    PRINT '=============================================='
    PRINT 'Master Cleanup Job Complete'
    PRINT 'End Time: ' + CAST(@EndTime AS NVARCHAR(50));
    PRINT 'Duration: ' + CAST(@DurationMinutes AS NVARCHAR(10)) + ' minutes';
    PRINT 'Total Rows Processed: ' + CAST(@TotalRowsDeleted AS NVARCHAR(20));
    PRINT '=============================================='

    -- Log master cleanup event
    EXEC dbo.usp_LogAuditEvent
        @EventType = 'MasterCleanupJobCompleted',
        @UserName = 'SQL Agent',
        @ObjectName = 'Multiple Tables',
        @ObjectType = 'Database',
        @ActionType = 'DELETE',
        @AffectedRows = @TotalRowsDeleted,
        @Severity = 'Information',
        @ComplianceFlag = 'SOC2',
        @RetentionDays = 2555;
END;
GO

PRINT 'Procedure usp_MasterCleanup created.';
GO

-- =============================================
-- PART 2: SQL Agent Job Creation
-- =============================================
PRINT '';
PRINT '=============================================='
PRINT 'PART 2: SQL Agent Job Creation'
PRINT '=============================================='
PRINT '';

USE msdb;
GO

-- Check if SQL Agent is running
IF (SELECT COUNT(*) FROM sys.dm_server_services WHERE servicename LIKE '%SQL Server Agent%' AND status = 4) = 0
BEGIN
    PRINT 'WARNING: SQL Server Agent is not running!';
    PRINT 'Please start SQL Server Agent to enable scheduled jobs.';
    PRINT '';
END

-- Job 1: Daily Master Cleanup Job
IF EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = 'MonitoringDB - Master Cleanup')
BEGIN
    PRINT 'Deleting existing job: MonitoringDB - Master Cleanup';
    EXEC msdb.dbo.sp_delete_job @job_name = 'MonitoringDB - Master Cleanup';
END

PRINT 'Creating job: MonitoringDB - Master Cleanup';

DECLARE @jobId BINARY(16);

EXEC msdb.dbo.sp_add_job
    @job_name = 'MonitoringDB - Master Cleanup',
    @enabled = 1,
    @description = 'Daily data retention cleanup job for MonitoringDB (SOC 2 compliance)',
    @category_name = 'Database Maintenance',
    @owner_login_name = 'sa',
    @job_id = @jobId OUTPUT;

-- Add job step
EXEC msdb.dbo.sp_add_jobstep
    @job_id = @jobId,
    @step_name = 'Run Master Cleanup',
    @subsystem = 'TSQL',
    @database_name = 'MonitoringDB',
    @command = 'EXEC dbo.usp_MasterCleanup;',
    @on_success_action = 1,  -- Quit with success
    @on_fail_action = 2,     -- Quit with failure
    @retry_attempts = 3,
    @retry_interval = 5;

-- Schedule: Daily at 2:00 AM
EXEC msdb.dbo.sp_add_jobschedule
    @job_id = @jobId,
    @name = 'Daily at 2 AM',
    @enabled = 1,
    @freq_type = 4,          -- Daily
    @freq_interval = 1,      -- Every day
    @active_start_time = 020000;  -- 2:00 AM

-- Add job to local server
EXEC msdb.dbo.sp_add_jobserver
    @job_id = @jobId,
    @server_name = N'(local)';

PRINT 'Job created: MonitoringDB - Master Cleanup (scheduled daily at 2:00 AM)';
GO

-- Job 2: Weekly Database Maintenance (Index Rebuild, Statistics Update)
IF EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = 'MonitoringDB - Weekly Maintenance')
BEGIN
    PRINT 'Deleting existing job: MonitoringDB - Weekly Maintenance';
    EXEC msdb.dbo.sp_delete_job @job_name = 'MonitoringDB - Weekly Maintenance';
END

PRINT 'Creating job: MonitoringDB - Weekly Maintenance';

DECLARE @jobId2 BINARY(16);

EXEC msdb.dbo.sp_add_job
    @job_name = 'MonitoringDB - Weekly Maintenance',
    @enabled = 1,
    @description = 'Weekly database maintenance (index rebuild, statistics update)',
    @category_name = 'Database Maintenance',
    @owner_login_name = 'sa',
    @job_id = @jobId2 OUTPUT;

-- Add job step
EXEC msdb.dbo.sp_add_jobstep
    @job_id = @jobId2,
    @step_name = 'Rebuild Indexes and Update Statistics',
    @subsystem = 'TSQL',
    @database_name = 'MonitoringDB',
    @command = '
-- Rebuild fragmented indexes
DECLARE @TableName NVARCHAR(255);
DECLARE @IndexName NVARCHAR(255);
DECLARE @SQL NVARCHAR(MAX);

DECLARE IndexCursor CURSOR FOR
SELECT
    t.name AS TableName,
    i.name AS IndexName
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, ''LIMITED'') AS ips
INNER JOIN sys.tables AS t ON ips.object_id = t.object_id
INNER JOIN sys.indexes AS i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.avg_fragmentation_in_percent > 30
  AND ips.page_count > 1000;

OPEN IndexCursor;
FETCH NEXT FROM IndexCursor INTO @TableName, @IndexName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @SQL = ''ALTER INDEX '' + QUOTENAME(@IndexName) + '' ON dbo.'' + QUOTENAME(@TableName) + '' REBUILD WITH (ONLINE = OFF);'';
    PRINT ''Rebuilding index: '' + @IndexName + '' on table: '' + @TableName;
    EXEC sp_executesql @SQL;

    FETCH NEXT FROM IndexCursor INTO @TableName, @IndexName;
END

CLOSE IndexCursor;
DEALLOCATE IndexCursor;

-- Update statistics
PRINT ''Updating statistics for all tables...'';
EXEC sp_updatestats;
PRINT ''Maintenance complete.'';
',
    @on_success_action = 1,
    @on_fail_action = 2,
    @retry_attempts = 2,
    @retry_interval = 10;

-- Schedule: Weekly on Sunday at 3:00 AM
EXEC msdb.dbo.sp_add_jobschedule
    @job_id = @jobId2,
    @name = 'Weekly Sunday at 3 AM',
    @enabled = 1,
    @freq_type = 8,          -- Weekly
    @freq_interval = 1,      -- Sunday
    @freq_recurrence_factor = 1,
    @active_start_time = 030000;  -- 3:00 AM

-- Add job to local server
EXEC msdb.dbo.sp_add_jobserver
    @job_id = @jobId2,
    @server_name = N'(local)';

PRINT 'Job created: MonitoringDB - Weekly Maintenance (scheduled Sunday at 3:00 AM)';
GO

-- =============================================
-- PART 3: Verification and Testing
-- =============================================
PRINT '';
PRINT '=============================================='
PRINT 'PART 3: Job Verification'
PRINT '=============================================='
PRINT '';

-- List created jobs
SELECT
    j.name AS JobName,
    j.enabled AS Enabled,
    j.description,
    s.name AS ScheduleName,
    CASE s.freq_type
        WHEN 4 THEN 'Daily'
        WHEN 8 THEN 'Weekly'
        ELSE 'Other'
    END AS Frequency,
    s.active_start_time AS StartTime
FROM msdb.dbo.sysjobs j
LEFT JOIN msdb.dbo.sysjobschedules js ON j.job_id = js.job_id
LEFT JOIN msdb.dbo.sysschedules s ON js.schedule_id = s.schedule_id
WHERE j.name LIKE 'MonitoringDB%'
ORDER BY j.name;

PRINT '';
PRINT '=============================================='
PRINT 'Retention Automation deployment complete!'
PRINT '=============================================='
PRINT '';
PRINT 'Summary:';
PRINT '- 5 retention cleanup procedures created';
PRINT '- 1 master cleanup procedure (orchestrates all cleanups)';
PRINT '- 2 SQL Agent jobs created:';
PRINT '  1. MonitoringDB - Master Cleanup (Daily at 2:00 AM)';
PRINT '  2. MonitoringDB - Weekly Maintenance (Sunday at 3:00 AM)';
PRINT '';
PRINT 'Retention Policies:';
PRINT '- PerformanceMetrics: 90 days';
PRINT '- AuditLog: 7 years (with archival after 1 year)';
PRINT '- BlockingEvents: 180 days';
PRINT '- DeadlockEvents: 180 days';
PRINT '';
PRINT 'SOC 2 Controls: CC6.5 (Data Retention), CC7.2 (Archival)';
PRINT '';
PRINT 'Next Steps:';
PRINT '1. Verify SQL Server Agent is running';
PRINT '2. Test jobs manually: EXEC msdb.dbo.sp_start_job @job_name = ''MonitoringDB - Master Cleanup'';';
PRINT '3. Monitor job history in SQL Server Agent';
GO
