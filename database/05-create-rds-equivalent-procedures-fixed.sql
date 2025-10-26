-- =====================================================
-- Script: 05-create-rds-equivalent-procedures-fixed.sql
-- Description: RDS Performance Insights equivalent stored procedures (FIXED)
-- Author: SQL Server Monitor Project
-- Date: 2025-10-25
-- Purpose: Collect comprehensive metrics matching AWS RDS capabilities
-- Fixed: Removed invalid column references, simplified queries
-- =====================================================

USE MonitoringDB;
GO

-- =====================================================
-- 1. usp_CollectCPUMetrics
-- Collects CPU utilization metrics
-- Equivalent to: RDS CPU Utilization
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectCPUMetrics', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectCPUMetrics;
GO

CREATE PROCEDURE dbo.usp_CollectCPUMetrics
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CollectionTime DATETIME2 = GETUTCDATE();
    DECLARE @SQLProcessUtilization DECIMAL(10,2);
    DECLARE @SystemIdleUtilization DECIMAL(10,2);
    DECLARE @OtherProcessUtilization DECIMAL(10,2);

    -- Get CPU utilization from ring buffer (simplified - no record_id)
    ;WITH CPUData AS (
        SELECT TOP 1
            100 - record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS SystemBusy,
            record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS SystemIdle,
            record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS SQLProcessUtilization,
            record.value('(./Record/@time)[1]', 'bigint') AS RecordTime
        FROM (
            SELECT CONVERT(xml, record) AS record
            FROM sys.dm_os_ring_buffers
            WHERE ring_buffer_type = 'RING_BUFFER_SCHEDULER_MONITOR'
              AND record LIKE '%<SystemHealth>%'
        ) AS rb
        ORDER BY rb.record.value('(./Record/@time)[1]', 'bigint') DESC
    )
    SELECT
        @SQLProcessUtilization = SQLProcessUtilization,
        @SystemIdleUtilization = SystemIdle,
        @OtherProcessUtilization = 100 - SystemIdle - SQLProcessUtilization
    FROM CPUData;

    -- Fallback to performance counters if ring buffer unavailable
    IF @SQLProcessUtilization IS NULL
    BEGIN
        SELECT @SQLProcessUtilization = cntr_value
        FROM sys.dm_os_performance_counters
        WHERE counter_name = 'CPU usage %'
          AND instance_name = 'default';

        IF @SQLProcessUtilization IS NULL
            SET @SQLProcessUtilization = 0;

        SET @SystemIdleUtilization = 100 - @SQLProcessUtilization;
        SET @OtherProcessUtilization = 0;
    END;

    -- Insert SQL Server CPU utilization
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'CPU', 'SQLServerUtilization', @SQLProcessUtilization;
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'CPU', 'SystemIdle', @SystemIdleUtilization;
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'CPU', 'OtherProcessUtilization', @OtherProcessUtilization;

    -- Total CPU (100 - idle) - using variable per user constraint
    DECLARE @TotalCPU DECIMAL(10,2);
    SET @TotalCPU = (100 - @SystemIdleUtilization);
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'CPU', 'Percent', @TotalCPU;
END;
GO

-- =====================================================
-- 2. usp_CollectMemoryMetrics
-- Collects memory utilization metrics
-- Equivalent to: RDS Memory Utilization
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectMemoryMetrics', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectMemoryMetrics;
GO

CREATE PROCEDURE dbo.usp_CollectMemoryMetrics
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CollectionTime DATETIME2 = GETUTCDATE();
    DECLARE @TotalServerMemoryMB DECIMAL(18,2);
    DECLARE @TargetServerMemoryMB DECIMAL(18,2);
    DECLARE @BufferCacheHitRatio DECIMAL(10,2);
    DECLARE @PageLifeExpectancy INT;
    DECLARE @MemoryGrantsPending INT;

    -- Total Server Memory (from performance counters)
    SELECT @TotalServerMemoryMB = cntr_value / 1024.0
    FROM sys.dm_os_performance_counters
    WHERE counter_name = 'Total Server Memory (KB)'
      AND object_name LIKE '%Memory Manager%';

    -- Target Server Memory
    SELECT @TargetServerMemoryMB = cntr_value / 1024.0
    FROM sys.dm_os_performance_counters
    WHERE counter_name = 'Target Server Memory (KB)'
      AND object_name LIKE '%Memory Manager%';

    -- Buffer cache hit ratio
    SELECT @BufferCacheHitRatio =
        (CAST(a.cntr_value AS DECIMAL(10,2)) / NULLIF(CAST(b.cntr_value AS DECIMAL(10,2)), 0)) * 100
    FROM sys.dm_os_performance_counters a
    CROSS JOIN sys.dm_os_performance_counters b
    WHERE a.counter_name = 'Buffer cache hit ratio'
      AND b.counter_name = 'Buffer cache hit ratio base'
      AND a.object_name LIKE '%Buffer Manager%'
      AND b.object_name LIKE '%Buffer Manager%';

    -- Page Life Expectancy
    SELECT @PageLifeExpectancy = cntr_value
    FROM sys.dm_os_performance_counters
    WHERE counter_name = 'Page life expectancy'
      AND object_name LIKE '%Buffer Manager%';

    -- Memory Grants Pending
    SELECT @MemoryGrantsPending = cntr_value
    FROM sys.dm_os_performance_counters
    WHERE counter_name = 'Memory Grants Pending'
      AND object_name LIKE '%Memory Manager%';

    -- Insert metrics
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'Memory', 'TotalServerMemoryMB', @TotalServerMemoryMB;
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'Memory', 'TargetServerMemoryMB', @TargetServerMemoryMB;
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'Memory', 'BufferCacheHitRatio', @BufferCacheHitRatio;
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'Memory', 'PageLifeExpectancy', @PageLifeExpectancy;
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'Memory', 'MemoryGrantsPending', @MemoryGrantsPending;

    -- Memory utilization percentage (Target / Total * 100)
    DECLARE @MemoryUtilizationPercent DECIMAL(10,2);
    SET @MemoryUtilizationPercent = (@TotalServerMemoryMB / NULLIF(@TargetServerMemoryMB, 0)) * 100;
    IF @MemoryUtilizationPercent > 100 SET @MemoryUtilizationPercent = 100;
    IF @MemoryUtilizationPercent IS NULL SET @MemoryUtilizationPercent = 0;

    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'Memory', 'Percent', @MemoryUtilizationPercent;
END;
GO

-- =====================================================
-- 3. usp_CollectDiskIOMetrics
-- Collects disk I/O metrics
-- Equivalent to: RDS Read/Write IOPS and Throughput
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectDiskIOMetrics', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectDiskIOMetrics;
GO

CREATE PROCEDURE dbo.usp_CollectDiskIOMetrics
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CollectionTime DATETIME2 = GETUTCDATE();
    DECLARE @TotalReadMB DECIMAL(18,2);
    DECLARE @TotalWriteMB DECIMAL(18,2);
    DECLARE @TotalReadOps BIGINT;
    DECLARE @TotalWriteOps BIGINT;
    DECLARE @AvgReadLatencyMs DECIMAL(10,2);
    DECLARE @AvgWriteLatencyMs DECIMAL(10,2);

    -- Aggregate disk I/O stats across all databases
    SELECT
        @TotalReadMB = SUM(vfs.num_of_bytes_read / 1024.0 / 1024.0),
        @TotalWriteMB = SUM(vfs.num_of_bytes_written / 1024.0 / 1024.0),
        @TotalReadOps = SUM(vfs.num_of_reads),
        @TotalWriteOps = SUM(vfs.num_of_writes),
        @AvgReadLatencyMs = AVG(CASE WHEN vfs.num_of_reads > 0
                                     THEN vfs.io_stall_read_ms * 1.0 / vfs.num_of_reads
                                     ELSE 0 END),
        @AvgWriteLatencyMs = AVG(CASE WHEN vfs.num_of_writes > 0
                                      THEN vfs.io_stall_write_ms * 1.0 / vfs.num_of_writes
                                      ELSE 0 END)
    FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs;

    -- Insert metrics (cumulative totals)
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'Disk', 'TotalReadMB', @TotalReadMB;
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'Disk', 'TotalWriteMB', @TotalWriteMB;
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'Disk', 'TotalReadIOPS', @TotalReadOps;
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'Disk', 'TotalWriteIOPS', @TotalWriteOps;
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'Disk', 'AvgReadLatencyMs', @AvgReadLatencyMs;
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'Disk', 'AvgWriteLatencyMs', @AvgWriteLatencyMs;
END;
GO

-- =====================================================
-- 4. usp_CollectConnectionMetrics
-- Collects connection and session metrics
-- Equivalent to: RDS DatabaseConnections
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectConnectionMetrics', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectConnectionMetrics;
GO

CREATE PROCEDURE dbo.usp_CollectConnectionMetrics
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CollectionTime DATETIME2 = GETUTCDATE();
    DECLARE @TotalConnections INT;
    DECLARE @ActiveConnections INT;
    DECLARE @SleepingConnections INT;
    DECLARE @UserConnections INT;
    DECLARE @SystemConnections INT;

    -- Connection counts (exclude system sessions < 50)
    SELECT
        @TotalConnections = COUNT(*),
        @ActiveConnections = SUM(CASE WHEN status = 'running' THEN 1 ELSE 0 END),
        @SleepingConnections = SUM(CASE WHEN status = 'sleeping' THEN 1 ELSE 0 END),
        @UserConnections = SUM(CASE WHEN is_user_process = 1 THEN 1 ELSE 0 END),
        @SystemConnections = SUM(CASE WHEN is_user_process = 0 THEN 1 ELSE 0 END)
    FROM sys.dm_exec_sessions
    WHERE session_id > 50;

    -- Insert metrics
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'Connections', 'Total', @TotalConnections;
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'Connections', 'Active', @ActiveConnections;
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'Connections', 'Sleeping', @SleepingConnections;
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'Connections', 'User', @UserConnections;
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'Connections', 'System', @SystemConnections;
END;
GO

-- =====================================================
-- 5. usp_CollectWaitStats
-- Collects wait statistics
-- Equivalent to: RDS Wait Events
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectWaitStats', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectWaitStats;
GO

CREATE PROCEDURE dbo.usp_CollectWaitStats
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CollectionTime DATETIME2 = GETUTCDATE();
    DECLARE @WaitType NVARCHAR(60);
    DECLARE @WaitTimeMs BIGINT;

    -- Create temp table for top wait types
    CREATE TABLE #WaitStats (
        wait_type NVARCHAR(60),
        wait_time_ms BIGINT
    );

    -- Get top 10 wait types by total wait time (exclude benign waits)
    INSERT INTO #WaitStats
    SELECT TOP 10
        wait_type,
        wait_time_ms
    FROM sys.dm_os_wait_stats
    WHERE wait_type NOT IN (
        'CLR_SEMAPHORE', 'LAZYWRITER_SLEEP', 'RESOURCE_QUEUE', 'SLEEP_TASK',
        'SLEEP_SYSTEMTASK', 'SQLTRACE_BUFFER_FLUSH', 'WAITFOR', 'LOGMGR_QUEUE',
        'CHECKPOINT_QUEUE', 'REQUEST_FOR_DEADLOCK_SEARCH', 'XE_TIMER_EVENT',
        'BROKER_TO_FLUSH', 'BROKER_TASK_STOP', 'CLR_MANUAL_EVENT', 'CLR_AUTO_EVENT',
        'DISPATCHER_QUEUE_SEMAPHORE', 'FT_IFTS_SCHEDULER_IDLE_WAIT', 'XE_DISPATCHER_WAIT',
        'XE_DISPATCHER_JOIN', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', 'DIRTY_PAGE_POLL',
        'HADR_FILESTREAM_IOMGR_IOCOMPLETION', 'SP_SERVER_DIAGNOSTICS_SLEEP'
    )
    AND wait_time_ms > 0
    ORDER BY wait_time_ms DESC;

    -- Insert each wait type as a metric
    DECLARE wait_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT wait_type, wait_time_ms FROM #WaitStats;

    OPEN wait_cursor;
    FETCH NEXT FROM wait_cursor INTO @WaitType, @WaitTimeMs;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'WaitStats', @WaitType, @WaitTimeMs;
        FETCH NEXT FROM wait_cursor INTO @WaitType, @WaitTimeMs;
    END;

    CLOSE wait_cursor;
    DEALLOCATE wait_cursor;
    DROP TABLE #WaitStats;
END;
GO

-- =====================================================
-- 6. usp_CollectQueryPerformance
-- Collects top query performance metrics
-- Equivalent to: RDS Top SQL
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectQueryPerformance', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectQueryPerformance;
GO

CREATE PROCEDURE dbo.usp_CollectQueryPerformance
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CollectionTime DATETIME2 = GETUTCDATE();
    DECLARE @AvgCPUMs DECIMAL(18,2);
    DECLARE @AvgDurationMs DECIMAL(18,2);
    DECLARE @TotalLogicalReads BIGINT;
    DECLARE @TotalPhysicalReads BIGINT;
    DECLARE @TotalExecutions BIGINT;

    -- Aggregate top query stats
    SELECT
        @AvgCPUMs = AVG(qs.total_worker_time / 1000.0 / NULLIF(qs.execution_count, 0)),
        @AvgDurationMs = AVG(qs.total_elapsed_time / 1000.0 / NULLIF(qs.execution_count, 0)),
        @TotalLogicalReads = SUM(qs.total_logical_reads),
        @TotalPhysicalReads = SUM(qs.total_physical_reads),
        @TotalExecutions = SUM(qs.execution_count)
    FROM (
        SELECT TOP 100
            total_worker_time,
            total_elapsed_time,
            total_logical_reads,
            total_physical_reads,
            execution_count
        FROM sys.dm_exec_query_stats
        ORDER BY total_worker_time DESC
    ) AS qs;

    -- Insert aggregate metrics
    IF @AvgCPUMs IS NOT NULL
        EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'QueryPerformance', 'AvgCPUMs', @AvgCPUMs;

    IF @AvgDurationMs IS NOT NULL
        EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'QueryPerformance', 'AvgDurationMs', @AvgDurationMs;

    IF @TotalLogicalReads IS NOT NULL
        EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'QueryPerformance', 'TotalLogicalReads', @TotalLogicalReads;

    IF @TotalPhysicalReads IS NOT NULL
        EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'QueryPerformance', 'TotalPhysicalReads', @TotalPhysicalReads;

    IF @TotalExecutions IS NOT NULL
        EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'QueryPerformance', 'TotalExecutions', @TotalExecutions;
END;
GO

-- =====================================================
-- 7. usp_CollectAllRDSMetrics
-- Master procedure to collect all RDS-equivalent metrics
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectAllRDSMetrics', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectAllRDSMetrics;
GO

CREATE PROCEDURE dbo.usp_CollectAllRDSMetrics
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartTime DATETIME2 = GETUTCDATE();
    DECLARE @ErrorMessage NVARCHAR(4000);

    BEGIN TRY
        -- Collect all metric categories
        EXEC dbo.usp_CollectCPUMetrics @ServerID;
        EXEC dbo.usp_CollectMemoryMetrics @ServerID;
        EXEC dbo.usp_CollectDiskIOMetrics @ServerID;
        EXEC dbo.usp_CollectConnectionMetrics @ServerID;
        EXEC dbo.usp_CollectWaitStats @ServerID;
        EXEC dbo.usp_CollectQueryPerformance @ServerID;

        DECLARE @DurationMs INT = DATEDIFF(MILLISECOND, @StartTime, GETUTCDATE());
        PRINT 'All RDS-equivalent metrics collected successfully for ServerID: ' + CAST(@ServerID AS VARCHAR(10));
        PRINT 'Collection completed in ' + CAST(@DurationMs AS VARCHAR(10)) + ' ms';
    END TRY
    BEGIN CATCH
        SET @ErrorMessage = 'Error collecting metrics: ' + ERROR_MESSAGE() + ' (Line ' + CAST(ERROR_LINE() AS VARCHAR(10)) + ')';
        PRINT @ErrorMessage;
        THROW;
    END CATCH;
END;
GO

PRINT '';
PRINT '========================================================';
PRINT 'RDS-Equivalent Stored Procedures Created Successfully';
PRINT '========================================================';
PRINT 'Procedures created (FIXED VERSION):';
PRINT '  1. usp_CollectCPUMetrics - CPU utilization';
PRINT '  2. usp_CollectMemoryMetrics - Memory utilization';
PRINT '  3. usp_CollectDiskIOMetrics - Disk I/O';
PRINT '  4. usp_CollectConnectionMetrics - Connections';
PRINT '  5. usp_CollectWaitStats - Wait statistics';
PRINT '  6. usp_CollectQueryPerformance - Query performance';
PRINT '  7. usp_CollectAllRDSMetrics - Master collection procedure';
PRINT '';
PRINT 'Test the collection:';
PRINT '  EXEC dbo.usp_CollectAllRDSMetrics @ServerID = 1;';
PRINT '';
PRINT 'View collected metrics:';
PRINT '  SELECT TOP 20 * FROM dbo.PerformanceMetrics';
PRINT '  WHERE ServerID = 1 ORDER BY CollectionTime DESC;';
PRINT '========================================================';
GO
