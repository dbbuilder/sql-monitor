-- =====================================================
-- Script: 91-verify-rds-collection-deployment.sql
-- Description: Verify AWS RDS collection procedures and data
-- Date: 2025-11-06
-- =====================================================

USE MonitoringDB;
GO

PRINT '';
PRINT '========================================================';
PRINT 'AWS RDS Collection Deployment Verification';
PRINT '========================================================';
PRINT '';

-- 1. Check if collection procedures exist
PRINT '1. Checking Collection Procedures:';
PRINT '   --------------------------------';

IF OBJECT_ID('dbo.usp_CollectDiskIOMetrics', 'P') IS NOT NULL
    PRINT '   [OK] usp_CollectDiskIOMetrics exists'
ELSE
    PRINT '   [MISSING] usp_CollectDiskIOMetrics - RUN: 05-create-rds-equivalent-procedures.sql';

IF OBJECT_ID('dbo.usp_CollectCPUMetrics', 'P') IS NOT NULL
    PRINT '   [OK] usp_CollectCPUMetrics exists'
ELSE
    PRINT '   [MISSING] usp_CollectCPUMetrics - RUN: 05-create-rds-equivalent-procedures.sql';

IF OBJECT_ID('dbo.usp_CollectMemoryMetrics', 'P') IS NOT NULL
    PRINT '   [OK] usp_CollectMemoryMetrics exists'
ELSE
    PRINT '   [MISSING] usp_CollectMemoryMetrics - RUN: 05-create-rds-equivalent-procedures.sql';

IF OBJECT_ID('dbo.usp_CollectAllMetrics', 'P') IS NOT NULL
    PRINT '   [OK] usp_CollectAllMetrics exists'
ELSE
    PRINT '   [MISSING] usp_CollectAllMetrics - RUN: 08-create-master-collection-procedure.sql';

PRINT '';

-- 2. Check SQL Agent Job
PRINT '2. Checking SQL Agent Job:';
PRINT '   -----------------------';

DECLARE @JobExists BIT = 0;
DECLARE @JobEnabled BIT = 0;
DECLARE @LastRunStatus INT = 0;
DECLARE @LastRunDate DATETIME = NULL;

SELECT TOP 1
    @JobExists = 1,
    @JobEnabled = j.enabled,
    @LastRunStatus = ISNULL(jh.run_status, 0),
    @LastRunDate = CASE
        WHEN jh.run_date IS NOT NULL
        THEN msdb.dbo.agent_datetime(jh.run_date, jh.run_time)
        ELSE NULL
    END
FROM msdb.dbo.sysjobs j
LEFT JOIN (
    SELECT job_id, run_status, run_date, run_time,
           ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY run_date DESC, run_time DESC) AS rn
    FROM msdb.dbo.sysjobhistory
    WHERE step_id = 0  -- Job outcome
) jh ON j.job_id = jh.job_id AND jh.rn = 1
WHERE j.name = 'SQL Monitor - Complete Collection';

IF @JobExists = 1
BEGIN
    PRINT '   [OK] SQL Agent job exists';
    IF @JobEnabled = 1
        PRINT '   [OK] Job is enabled';
    ELSE
        PRINT '   [WARNING] Job is DISABLED - Enable it to start collection';

    IF @LastRunDate IS NOT NULL
    BEGIN
        PRINT '   [INFO] Last run: ' + CONVERT(VARCHAR(30), @LastRunDate, 120);
        IF @LastRunStatus = 1
            PRINT '   [OK] Last run succeeded';
        ELSE
            PRINT '   [WARNING] Last run FAILED - Check SQL Agent job history';
    END
    ELSE
        PRINT '   [WARNING] Job has never run';
END
ELSE
    PRINT '   [MISSING] SQL Agent job - RUN: 09-create-sql-agent-jobs.sql';

PRINT '';

-- 3. Check for collected data
PRINT '3. Checking Collected Data:';
PRINT '   ------------------------';

DECLARE @TotalMetrics INT = 0;
DECLARE @DiskMetrics INT = 0;
DECLARE @ReadIOPS INT = 0;
DECLARE @WriteIOPS INT = 0;
DECLARE @LatencyMetrics INT = 0;
DECLARE @OldestMetric DATETIME2 = NULL;
DECLARE @NewestMetric DATETIME2 = NULL;

SELECT
    @TotalMetrics = COUNT(*),
    @OldestMetric = MIN(CollectionTime),
    @NewestMetric = MAX(CollectionTime)
FROM dbo.PerformanceMetrics;

SELECT @DiskMetrics = COUNT(*)
FROM dbo.PerformanceMetrics
WHERE MetricCategory = 'Disk';

SELECT @ReadIOPS = COUNT(*)
FROM dbo.PerformanceMetrics
WHERE MetricCategory = 'Disk' AND MetricName = 'ReadIOPS';

SELECT @WriteIOPS = COUNT(*)
FROM dbo.PerformanceMetrics
WHERE MetricCategory = 'Disk' AND MetricName = 'WriteIOPS';

SELECT @LatencyMetrics = COUNT(*)
FROM dbo.PerformanceMetrics
WHERE MetricCategory = 'Disk'
  AND MetricName IN ('AvgReadLatencyMs', 'AvgWriteLatencyMs');

PRINT '   Total metrics collected: ' + CAST(@TotalMetrics AS VARCHAR(20));

IF @TotalMetrics > 0
BEGIN
    PRINT '   Oldest metric: ' + CONVERT(VARCHAR(30), @OldestMetric, 120);
    PRINT '   Newest metric: ' + CONVERT(VARCHAR(30), @NewestMetric, 120);
    PRINT '';
    PRINT '   Disk category metrics: ' + CAST(@DiskMetrics AS VARCHAR(20));

    IF @DiskMetrics > 0
    BEGIN
        PRINT '   [OK] Disk metrics are being collected';
        PRINT '   - ReadIOPS metrics: ' + CAST(@ReadIOPS AS VARCHAR(20));
        PRINT '   - WriteIOPS metrics: ' + CAST(@WriteIOPS AS VARCHAR(20));
        PRINT '   - Latency metrics: ' + CAST(@LatencyMetrics AS VARCHAR(20));

        IF @ReadIOPS = 0
            PRINT '   [WARNING] No ReadIOPS metrics - Dashboard will show "No data"';
        IF @WriteIOPS = 0
            PRINT '   [WARNING] No WriteIOPS metrics - Dashboard will show "No data"';
        IF @LatencyMetrics = 0
            PRINT '   [WARNING] No latency metrics - Dashboard will show "No data"';
    END
    ELSE
        PRINT '   [WARNING] No Disk category metrics - AWS RDS dashboard will show "No data"';
END
ELSE
    PRINT '   [WARNING] No metrics collected yet - Wait 5 minutes for first collection';

PRINT '';

-- 4. Sample recent disk metrics
PRINT '4. Recent Disk Metrics Sample:';
PRINT '   ---------------------------';

IF EXISTS (SELECT 1 FROM dbo.PerformanceMetrics WHERE MetricCategory = 'Disk')
BEGIN
    SELECT TOP 10
        CollectionTime,
        s.ServerName,
        MetricName,
        MetricValue
    FROM dbo.PerformanceMetrics pm
    INNER JOIN dbo.Servers s ON pm.ServerID = s.ServerID
    WHERE MetricCategory = 'Disk'
    ORDER BY CollectionTime DESC;
END
ELSE
    PRINT '   No disk metrics found';

PRINT '';

-- 5. Deployment Recommendations
PRINT '5. Deployment Recommendations:';
PRINT '   ----------------------------';

DECLARE @NeedsDeploy BIT = 0;

IF OBJECT_ID('dbo.usp_CollectDiskIOMetrics', 'P') IS NULL
BEGIN
    PRINT '   [ACTION] Deploy RDS collection procedures:';
    PRINT '            sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P YourPassword -C -d MonitoringDB -i database/05-create-rds-equivalent-procedures.sql';
    SET @NeedsDeploy = 1;
END

IF OBJECT_ID('dbo.usp_CollectAllMetrics', 'P') IS NULL
BEGIN
    PRINT '   [ACTION] Deploy master collection procedure:';
    PRINT '            sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P YourPassword -C -d MonitoringDB -i database/08-create-master-collection-procedure.sql';
    SET @NeedsDeploy = 1;
END

IF @JobExists = 0
BEGIN
    PRINT '   [ACTION] Deploy SQL Agent job:';
    PRINT '            sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P YourPassword -C -d msdb -i database/09-create-sql-agent-jobs.sql';
    SET @NeedsDeploy = 1;
END

IF @JobEnabled = 0 AND @JobExists = 1
BEGIN
    PRINT '   [ACTION] Enable SQL Agent job:';
    PRINT '            EXEC msdb.dbo.sp_update_job @job_name=''SQL Monitor - Complete Collection'', @enabled=1';
    SET @NeedsDeploy = 1;
END

IF @DiskMetrics = 0 AND @NeedsDeploy = 0
BEGIN
    PRINT '   [ACTION] Manually run collection to verify:';
    PRINT '            EXEC dbo.usp_CollectAllMetrics @ServerID = 1, @VerboseOutput = 1';
    PRINT '';
    PRINT '   [ACTION] Check for errors in SQL Agent job history';
END

IF @NeedsDeploy = 0 AND @DiskMetrics > 0
    PRINT '   [SUCCESS] Everything is deployed and working! Data should appear in Grafana.';

PRINT '';
PRINT '========================================================';
PRINT 'Verification Complete';
PRINT '========================================================';
GO
