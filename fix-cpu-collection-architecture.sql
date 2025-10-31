-- =============================================
-- Fix CPU Collection Architecture
-- Problem: Remote servers are reading sqltest's ring buffer instead of their own
-- Solution: Split CPU collection into local + remote insert pattern
-- =============================================

USE MonitoringDB;
GO

-- Step 1: Create a procedure that collects LOCAL CPU metrics and returns as table
IF OBJECT_ID('dbo.usp_GetLocalCPUMetrics', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetLocalCPUMetrics;
GO

CREATE PROCEDURE dbo.usp_GetLocalCPUMetrics
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SQLProcessUtilization INT;
    DECLARE @SystemIdle INT;

    -- Read LOCAL ring buffer
    SELECT TOP 1
        @SQLProcessUtilization = record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int'),
        @SystemIdle = record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int')
    FROM (
        SELECT TOP 1 timestamp, CONVERT(xml, record) AS record
        FROM sys.dm_os_ring_buffers WITH (NOLOCK)
        WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
          AND record LIKE '%<SystemHealth>%'
        ORDER BY timestamp DESC
    ) AS rb;

    -- Return CPU metrics as result set
    SELECT
        GETUTCDATE() AS CollectionTime,
        'CPU' AS MetricCategory,
        'SQLServerCPUPercent' AS MetricName,
        CAST(@SQLProcessUtilization AS DECIMAL(10,4)) AS MetricValue
    UNION ALL
    SELECT
        GETUTCDATE(),
        'CPU',
        'SystemIdlePercent',
        CAST(@SystemIdle AS DECIMAL(10,4))
    UNION ALL
    SELECT
        GETUTCDATE(),
        'CPU',
        'OtherProcessCPUPercent',
        CAST(100 - @SQLProcessUtilization - @SystemIdle AS DECIMAL(10,4))
    WHERE @SQLProcessUtilization IS NOT NULL;
END;
GO

-- Step 2: Update usp_CollectPerformanceCounters to NOT collect CPU (only counters)
IF OBJECT_ID('dbo.usp_CollectPerformanceCountersNoCPU', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectPerformanceCountersNoCPU;
GO

CREATE PROCEDURE dbo.usp_CollectPerformanceCountersNoCPU
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;

    DECLARE @CollectionTime DATETIME2 = GETUTCDATE();

    -- Collect performance counters from sys.dm_os_performance_counters (NO CPU)
    INSERT INTO dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
    SELECT
        @ServerID,
        @CollectionTime,
        CASE
            WHEN counter_name LIKE '%Batch Requests%' THEN 'Performance'
            WHEN counter_name LIKE '%Transactions%' THEN 'Performance'
            WHEN counter_name LIKE '%IOPS%' OR counter_name LIKE '%Disk%' THEN 'DiskIO'
            ELSE 'Performance'
        END AS MetricCategory,
        CASE counter_name
            WHEN 'Batch Requests/sec' THEN 'BatchRequestsPerSec'
            WHEN 'Transactions/sec' THEN 'Transactions'
            WHEN 'SQL Compilations/sec' THEN 'SQLCompilationsPerSec'
            WHEN 'SQL Re-Compilations/sec' THEN 'SQLReCompilationsPerSec'
            ELSE REPLACE(REPLACE(counter_name, '/', 'Per'), ' ', '')
        END AS MetricName,
        cntr_value AS MetricValue
    FROM sys.dm_os_performance_counters
    WHERE (
        counter_name IN (
            'Batch Requests/sec',
            'Transactions/sec',
            'SQL Compilations/sec',
            'SQL Re-Compilations/sec',
            'User Connections',
            'Processes blocked',
            'Lock Waits/sec',
            'Page life expectancy',
            'Buffer cache hit ratio',
            'Lazy writes/sec',
            'Page reads/sec',
            'Page writes/sec'
        )
        OR (object_name LIKE '%:SQL Statistics%' AND counter_name = 'Batch Requests/sec')
        OR (object_name LIKE '%:General Statistics%' AND counter_name IN ('Transactions', 'User Connections'))
        OR (object_name LIKE '%:Buffer Manager%' AND counter_name IN ('Buffer cache hit ratio', 'Page life expectancy'))
    )
    AND instance_name = '';

    PRINT 'Performance counters collected (NO CPU)';
END;
GO

-- Step 3: Create wrapper that calls local CPU + inserts to central DB
IF OBJECT_ID('dbo.usp_CollectAndInsertCPUMetrics', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectAndInsertCPUMetrics;
GO

CREATE PROCEDURE dbo.usp_CollectAndInsertCPUMetrics
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Get LOCAL CPU metrics
    INSERT INTO dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
    EXEC dbo.usp_GetLocalCPUMetrics;

    PRINT 'CPU metrics collected and inserted for ServerID ' + CAST(@ServerID AS VARCHAR(10));
END;
GO

PRINT '========================================';
PRINT 'CPU Collection Architecture Fixed!';
PRINT '========================================';
PRINT '';
PRINT 'Next Steps:';
PRINT '1. Deploy this to ALL servers (sqltest, svweb, suncity)';
PRINT '2. Update SQL Agent jobs to call TWO procedures:';
PRINT '   a) usp_CollectAndInsertCPUMetrics @ServerID=X  -- LOCAL execution';
PRINT '   b) [central].MonitoringDB.dbo.usp_CollectPerformanceCountersNoCPU @ServerID=X  -- REMOTE execution';
PRINT '========================================';
GO
