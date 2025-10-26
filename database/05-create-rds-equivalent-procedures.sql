-- =====================================================
-- Script: 05-create-rds-equivalent-procedures.sql
-- Description: RDS Performance Insights equivalent stored procedures
-- Author: SQL Server Monitor Project
-- Date: 2025-10-25
-- Purpose: Collect comprehensive metrics matching AWS RDS capabilities
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

    -- Get CPU utilization from ring buffer
    SELECT TOP 1
        @SQLProcessUtilization = SQLProcessUtilization,
        @SystemIdleUtilization = SystemIdle,
        @OtherProcessUtilization = 100 - SystemIdle - SQLProcessUtilization
    FROM (
        SELECT TOP 10
            record_id,
            DATEADD(ms, -1 * ((SELECT ms_ticks FROM sys.dm_os_sys_info) - [timestamp]), GETDATE()) AS EventTime,
            100 - record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS SystemBusy,
            record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS SystemIdle,
            record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS SQLProcessUtilization
        FROM (
            SELECT timestamp, CONVERT(xml, record) AS record, record_id
            FROM sys.dm_os_ring_buffers
            WHERE ring_buffer_type = 'RING_BUFFER_SCHEDULER_MONITOR'
              AND record LIKE '%<SystemHealth>%'
        ) AS rb
    ) AS cpu
    ORDER BY record_id DESC;

    -- Insert SQL Server CPU utilization
    EXEC dbo.usp_InsertMetrics
        @ServerID = @ServerID,
        @CollectionTime = @CollectionTime,
        @MetricCategory = 'CPU',
        @MetricName = 'SQLServerUtilization',
        @MetricValue = @SQLProcessUtilization;

    -- Insert System Idle
    EXEC dbo.usp_InsertMetrics
        @ServerID = @ServerID,
        @CollectionTime = @CollectionTime,
        @MetricCategory = 'CPU',
        @MetricName = 'SystemIdle',
        @MetricValue = @SystemIdleUtilization;

    -- Insert Other Process Utilization
    EXEC dbo.usp_InsertMetrics
        @ServerID = @ServerID,
        @CollectionTime = @CollectionTime,
        @MetricCategory = 'CPU',
        @MetricName = 'OtherProcessUtilization',
        @MetricValue = @OtherProcessUtilization;
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

    -- Get memory clerks
    SELECT
        @TotalServerMemoryMB = (SELECT CAST(value_in_use AS DECIMAL(18,2)) / 1024
                                FROM sys.configurations WHERE name = 'max server memory (MB)'),
        @TargetServerMemoryMB = (SELECT SUM(pages_kb) / 1024.0
                                 FROM sys.dm_os_memory_clerks);

    -- Buffer cache hit ratio
    SELECT @BufferCacheHitRatio =
        (SELECT CAST(cntr_value AS DECIMAL(10,2))
         FROM sys.dm_os_performance_counters
         WHERE counter_name = 'Buffer cache hit ratio' AND object_name LIKE '%Buffer Manager%')
        /
        (SELECT CAST(cntr_value AS DECIMAL(10,2))
         FROM sys.dm_os_performance_counters
         WHERE counter_name = 'Buffer cache hit ratio base' AND object_name LIKE '%Buffer Manager%')
        * 100;

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

    -- Memory utilization percentage
    DECLARE @MemoryUtilizationPercent DECIMAL(10,2);
    SET @MemoryUtilizationPercent = (@TargetServerMemoryMB / NULLIF(@TotalServerMemoryMB, 0)) * 100;
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

    -- Disk I/O stats
    SELECT
        DB_NAME(mf.database_id) AS DatabaseName,
        mf.name AS LogicalFileName,
        mf.type_desc AS FileType,
        vfs.num_of_reads AS ReadOps,
        vfs.num_of_writes AS WriteOps,
        vfs.num_of_bytes_read / 1024.0 / 1024.0 AS ReadMB,
        vfs.num_of_bytes_written / 1024.0 / 1024.0 AS WriteMB,
        vfs.io_stall_read_ms AS ReadLatencyMs,
        vfs.io_stall_write_ms AS WriteLatencyMs
    INTO #DiskIO
    FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
    INNER JOIN sys.master_files AS mf ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id;

    -- Aggregate metrics
    DECLARE @TotalReadMB DECIMAL(18,2), @TotalWriteMB DECIMAL(18,2);
    DECLARE @TotalReadOps BIGINT, @TotalWriteOps BIGINT;
    DECLARE @AvgReadLatency DECIMAL(10,2), @AvgWriteLatency DECIMAL(10,2);

    SELECT
        @TotalReadMB = SUM(ReadMB),
        @TotalWriteMB = SUM(WriteMB),
        @TotalReadOps = SUM(ReadOps),
        @TotalWriteOps = SUM(WriteOps),
        @AvgReadLatency = AVG(CASE WHEN ReadOps > 0 THEN ReadLatencyMs / ReadOps ELSE 0 END),
        @AvgWriteLatency = AVG(CASE WHEN WriteOps > 0 THEN WriteLatencyMs / WriteOps ELSE 0 END)
    FROM #DiskIO;

    -- Insert metrics
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'Disk', 'ReadMB', @TotalReadMB;
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'Disk', 'WriteMB', @TotalWriteMB;
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'Disk', 'ReadIOPS', @TotalReadOps;
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'Disk', 'WriteIOPS', @TotalWriteOps;
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'Disk', 'AvgReadLatencyMs', @AvgReadLatency;
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'Disk', 'AvgWriteLatencyMs', @AvgWriteLatency;

    DROP TABLE #DiskIO;
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

    -- Connection counts
    SELECT
        @TotalConnections = COUNT(*),
        @ActiveConnections = SUM(CASE WHEN status = 'running' THEN 1 ELSE 0 END),
        @SleepingConnections = SUM(CASE WHEN status = 'sleeping' THEN 1 ELSE 0 END),
        @UserConnections = SUM(CASE WHEN is_user_process = 1 THEN 1 ELSE 0 END),
        @SystemConnections = SUM(CASE WHEN is_user_process = 0 THEN 1 ELSE 0 END)
    FROM sys.dm_exec_sessions
    WHERE session_id > 50; -- Exclude system sessions

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

    -- Top 10 wait types by total wait time
    SELECT TOP 10
        wait_type,
        waiting_tasks_count,
        wait_time_ms,
        max_wait_time_ms,
        signal_wait_time_ms
    INTO #WaitStats
    FROM sys.dm_os_wait_stats
    WHERE wait_type NOT IN (
        -- Exclude benign waits
        'CLR_SEMAPHORE', 'LAZYWRITER_SLEEP', 'RESOURCE_QUEUE', 'SLEEP_TASK',
        'SLEEP_SYSTEMTASK', 'SQLTRACE_BUFFER_FLUSH', 'WAITFOR', 'LOGMGR_QUEUE',
        'CHECKPOINT_QUEUE', 'REQUEST_FOR_DEADLOCK_SEARCH', 'XE_TIMER_EVENT',
        'BROKER_TO_FLUSH', 'BROKER_TASK_STOP', 'CLR_MANUAL_EVENT', 'CLR_AUTO_EVENT',
        'DISPATCHER_QUEUE_SEMAPHORE', 'FT_IFTS_SCHEDULER_IDLE_WAIT', 'XE_DISPATCHER_WAIT',
        'XE_DISPATCHER_JOIN', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP'
    )
    AND wait_time_ms > 0
    ORDER BY wait_time_ms DESC;

    -- Insert top wait types
    DECLARE @WaitType NVARCHAR(60), @WaitTimeMs BIGINT;

    DECLARE wait_cursor CURSOR FOR
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

    -- Top 10 queries by CPU
    SELECT TOP 10
        qs.sql_handle,
        qs.execution_count,
        qs.total_worker_time / 1000 AS total_cpu_ms,
        qs.total_elapsed_time / 1000 AS total_duration_ms,
        qs.total_logical_reads,
        qs.total_physical_reads,
        SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
            ((CASE qs.statement_end_offset
                WHEN -1 THEN DATALENGTH(st.text)
                ELSE qs.statement_end_offset
            END - qs.statement_start_offset)/2) + 1) AS query_text
    INTO #TopQueries
    FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
    ORDER BY qs.total_worker_time DESC;

    -- Aggregate metrics
    DECLARE @AvgCPUMs DECIMAL(18,2), @AvgDurationMs DECIMAL(18,2);
    DECLARE @TotalLogicalReads BIGINT, @TotalPhysicalReads BIGINT;

    SELECT
        @AvgCPUMs = AVG(total_cpu_ms),
        @AvgDurationMs = AVG(total_duration_ms),
        @TotalLogicalReads = SUM(total_logical_reads),
        @TotalPhysicalReads = SUM(total_physical_reads)
    FROM #TopQueries;

    -- Insert metrics
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'QueryPerformance', 'AvgCPUMs', @AvgCPUMs;
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'QueryPerformance', 'AvgDurationMs', @AvgDurationMs;
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'QueryPerformance', 'TotalLogicalReads', @TotalLogicalReads;
    EXEC dbo.usp_InsertMetrics @ServerID, @CollectionTime, 'QueryPerformance', 'TotalPhysicalReads', @TotalPhysicalReads;

    DROP TABLE #TopQueries;
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

    BEGIN TRY
        -- Collect all metric categories
        EXEC dbo.usp_CollectCPUMetrics @ServerID;
        EXEC dbo.usp_CollectMemoryMetrics @ServerID;
        EXEC dbo.usp_CollectDiskIOMetrics @ServerID;
        EXEC dbo.usp_CollectConnectionMetrics @ServerID;
        EXEC dbo.usp_CollectWaitStats @ServerID;
        EXEC dbo.usp_CollectQueryPerformance @ServerID;

        PRINT 'All RDS-equivalent metrics collected successfully for ServerID: ' + CAST(@ServerID AS VARCHAR(10));
    END TRY
    BEGIN CATCH
        PRINT 'Error collecting metrics: ' + ERROR_MESSAGE();
        THROW;
    END CATCH;
END;
GO

PRINT '';
PRINT '========================================================';
PRINT 'RDS-Equivalent Stored Procedures Created Successfully';
PRINT '========================================================';
PRINT 'Procedures created:';
PRINT '  1. usp_CollectCPUMetrics - CPU utilization';
PRINT '  2. usp_CollectMemoryMetrics - Memory utilization';
PRINT '  3. usp_CollectDiskIOMetrics - Disk I/O';
PRINT '  4. usp_CollectConnectionMetrics - Connections';
PRINT '  5. usp_CollectWaitStats - Wait statistics';
PRINT '  6. usp_CollectQueryPerformance - Query performance';
PRINT '  7. usp_CollectAllRDSMetrics - Master collection procedure';
PRINT '';
PRINT 'Usage: EXEC dbo.usp_CollectAllRDSMetrics @ServerID = 1';
PRINT '========================================================';
GO
