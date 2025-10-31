-- =============================================
-- Update SQL Agent Jobs for CPU Fix
-- New architecture: Each server collects CPU locally, then pushes to central DB
-- Execute this script on sqltest to update all 3 SQL Agent jobs
-- =============================================

USE msdb;
GO

PRINT '========================================';
PRINT 'Updating SQL Agent Jobs for CPU Collection Fix';
PRINT '========================================';
PRINT '';

-- =============================================
-- Update SQLTEST Job (ServerID = 1)
-- =============================================
PRINT 'Updating SQL Agent job on SQLTEST...';

EXEC sp_update_jobstep
    @job_name = N'SQL Monitor - Collect Metrics (sqltest)',
    @step_id = 1,
    @step_name = N'Collect All Metrics (Local)',
    @database_name = N'MonitoringDB',
    @command = N'
-- Collect CPU metrics (local ring buffer)
EXEC dbo.usp_CollectAndInsertCPUMetrics @ServerID = 1;

-- Collect other metrics (performance counters, disk, connections)
EXEC dbo.usp_CollectAllMetrics @ServerID = 1, @VerboseOutput = 0;
';

PRINT '  ✓ SQLTEST job updated';
PRINT '';

-- =============================================
-- Update SVWEB Job (ServerID = 5) - via linked server
-- =============================================
PRINT 'Updating SQL Agent job on SVWEB...';

-- Step 1: Update job on svweb to collect LOCAL CPU
EXEC('
USE msdb;
EXEC sp_update_jobstep
    @job_name = N''SQL Monitor - Collect Metrics (svweb)'',
    @step_id = 1,
    @step_name = N''Collect LOCAL CPU Metrics'',
    @database_name = N''master'',
    @command = N''
-- Collect LOCAL CPU from ring buffer and push to central DB
DECLARE @CPUMetrics TABLE (
    CollectionTime DATETIME2,
    MetricCategory VARCHAR(50),
    MetricName VARCHAR(100),
    MetricValue DECIMAL(20,4)
);

-- Read LOCAL ring buffer
DECLARE @SQLProcessUtilization INT, @SystemIdle INT;
SELECT TOP 1
    @SQLProcessUtilization = record.value(''''(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]'''', ''''int''''),
    @SystemIdle = record.value(''''(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]'''', ''''int'''')
FROM (
    SELECT TOP 1 timestamp, CONVERT(xml, record) AS record
    FROM sys.dm_os_ring_buffers WITH (NOLOCK)
    WHERE ring_buffer_type = N''''RING_BUFFER_SCHEDULER_MONITOR''''
      AND record LIKE ''''%<SystemHealth>%''''
    ORDER BY timestamp DESC
) AS rb;

-- Insert CPU metrics to table variable
INSERT INTO @CPUMetrics (CollectionTime, MetricCategory, MetricName, MetricValue)
SELECT GETUTCDATE(), ''''CPU'''', ''''SQLServerCPUPercent'''', CAST(@SQLProcessUtilization AS DECIMAL(10,4))
WHERE @SQLProcessUtilization IS NOT NULL
UNION ALL
SELECT GETUTCDATE(), ''''CPU'''', ''''SystemIdlePercent'''', CAST(@SystemIdle AS DECIMAL(10,4))
WHERE @SQLProcessUtilization IS NOT NULL
UNION ALL
SELECT GETUTCDATE(), ''''CPU'''', ''''OtherProcessCPUPercent'''', CAST(100 - @SQLProcessUtilization - @SystemIdle AS DECIMAL(10,4))
WHERE @SQLProcessUtilization IS NOT NULL;

-- Push to central database
INSERT INTO [sqltest.schoolvision.net].MonitoringDB.dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
SELECT 5, CollectionTime, MetricCategory, MetricName, MetricValue
FROM @CPUMetrics;

PRINT ''''CPU metrics collected and pushed to central DB for ServerID 5'''';
'';
') AT SVWEB;

-- Add step 2 if it doesn't exist, or update if it does
EXEC('
USE msdb;
IF NOT EXISTS (
    SELECT 1 FROM sysjobsteps js
    INNER JOIN sysjobs j ON js.job_id = j.job_id
    WHERE j.name = N''SQL Monitor - Collect Metrics (svweb)'' AND js.step_id = 2
)
BEGIN
    EXEC sp_add_jobstep
        @job_name = N''SQL Monitor - Collect Metrics (svweb)'',
        @step_id = 2,
        @step_name = N''Collect REMOTE Performance Metrics'',
        @database_name = N''master'',
        @command = N''EXEC [sqltest.schoolvision.net].MonitoringDB.dbo.usp_CollectAllMetrics @ServerID = 5, @VerboseOutput = 0;'';
END
ELSE
BEGIN
    EXEC sp_update_jobstep
        @job_name = N''SQL Monitor - Collect Metrics (svweb)'',
        @step_id = 2,
        @step_name = N''Collect REMOTE Performance Metrics'',
        @database_name = N''master'',
        @command = N''EXEC [sqltest.schoolvision.net].MonitoringDB.dbo.usp_CollectAllMetrics @ServerID = 5, @VerboseOutput = 0;'';
END
') AT SVWEB;

PRINT '  ✓ SVWEB job updated';
PRINT '';

-- =============================================
-- SUNCITY Job Update Skipped (No MonitoringDB)
-- =============================================
PRINT 'SUNCITY: Skipping job update (MonitoringDB not present on this server)';
PRINT '  Note: SUNCITY may need separate deployment if metrics collection is required';
PRINT '';

PRINT '========================================';
PRINT 'SQL Agent Jobs Updated!';
PRINT '========================================';
PRINT '';
PRINT 'Jobs will start collecting CPU metrics on next run (every 5 minutes)';
PRINT 'Monitor: SELECT TOP 10 * FROM MonitoringDB.dbo.PerformanceMetrics WHERE MetricCategory = ''''CPU'''' ORDER BY CollectionTime DESC';
GO
