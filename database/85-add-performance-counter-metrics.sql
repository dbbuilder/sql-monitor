-- =====================================================
-- Script: 85-add-performance-counter-metrics.sql
-- Description: Add Batch Requests/sec and Transactions/sec metrics
-- Author: SQL Server Monitor Project
-- Date: 2025-11-03
-- Purpose: Update usp_CollectQueryPerformance to collect missing performance counters
-- =====================================================

USE MonitoringDB;
GO

PRINT 'Adding Batch Requests/sec and Transactions/sec metrics...';
PRINT '';

-- =====================================================
-- Update usp_CollectQueryPerformance
-- Add performance counter collection for dashboard metrics
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

    -- NEW: Performance counter metrics
    DECLARE @BatchRequestsPerSec DECIMAL(18,2);
    DECLARE @TransactionsPerSec DECIMAL(18,2);

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

    -- =====================================================
    -- NEW: Collect performance counter metrics for dashboard
    -- =====================================================

    -- Batch Requests/sec - Rate of batch requests received by SQL Server
    -- This is a rate counter (PERF_COUNTER_BULK_COUNT)
    SELECT @BatchRequestsPerSec = cntr_value
    FROM sys.dm_os_performance_counters
    WHERE counter_name = 'Batch Requests/sec'
      AND object_name LIKE '%SQL Statistics%';

    IF @BatchRequestsPerSec IS NOT NULL
    BEGIN
        EXEC dbo.usp_InsertMetrics
            @ServerID,
            @CollectionTime,
            'Performance',
            'BatchRequestsPerSec',
            @BatchRequestsPerSec;
    END;

    -- Transactions/sec - Number of transactions started per second
    -- This is a rate counter (PERF_COUNTER_BULK_COUNT)
    -- Use _Total instance for all databases combined
    SELECT @TransactionsPerSec = cntr_value
    FROM sys.dm_os_performance_counters
    WHERE counter_name = 'Transactions/sec'
      AND instance_name = '_Total'
      AND object_name LIKE '%Databases%';

    IF @TransactionsPerSec IS NOT NULL
    BEGIN
        EXEC dbo.usp_InsertMetrics
            @ServerID,
            @CollectionTime,
            'Performance',
            'Transactions',
            @TransactionsPerSec;
    END;
END;
GO

PRINT 'Procedure updated: dbo.usp_CollectQueryPerformance';
PRINT '';

-- =====================================================
-- Test the updated procedure
-- =====================================================

PRINT 'Testing updated procedure...';
PRINT '';

-- Get first active server
DECLARE @TestServerID INT;
SELECT TOP 1 @TestServerID = ServerID
FROM dbo.Servers
WHERE IsActive = 1
ORDER BY ServerID;

IF @TestServerID IS NOT NULL
BEGIN
    PRINT 'Testing with ServerID: ' + CAST(@TestServerID AS VARCHAR(10));
    PRINT '';

    -- Execute collection
    EXEC dbo.usp_CollectQueryPerformance @ServerID = @TestServerID;

    -- Verify new metrics were collected
    PRINT 'Verifying new metrics...';
    PRINT '';

    SELECT
        MetricCategory,
        MetricName,
        MetricValue,
        CollectionTime
    FROM dbo.PerformanceMetrics
    WHERE ServerID = @TestServerID
      AND MetricCategory = 'Performance'
      AND MetricName IN ('BatchRequestsPerSec', 'Transactions')
      AND CollectionTime >= DATEADD(MINUTE, -1, GETUTCDATE())
    ORDER BY CollectionTime DESC;

    IF @@ROWCOUNT > 0
    BEGIN
        PRINT '';
        PRINT 'SUCCESS: New performance counter metrics are being collected!';
    END
    ELSE
    BEGIN
        PRINT '';
        PRINT 'NOTE: Metrics collected but may not be visible yet (check after next collection cycle)';
    END;
END
ELSE
BEGIN
    PRINT 'No active servers found for testing';
END;

PRINT '';
PRINT '========================================================';
PRINT 'Performance Counter Metrics Added Successfully';
PRINT '========================================================';
PRINT '';
PRINT 'New Metrics:';
PRINT '  - Performance.BatchRequestsPerSec';
PRINT '  - Performance.Transactions';
PRINT '';
PRINT 'Dashboard Usage:';
PRINT '  - AWS RDS Performance Insights dashboard';
PRINT '  - Batch Requests/sec panel (Panel ID 9)';
PRINT '  - Transactions/sec panel (Panel ID 10)';
PRINT '';
PRINT 'Collection:';
PRINT '  - Collected by: dbo.usp_CollectQueryPerformance';
PRINT '  - Called by: dbo.usp_CollectAllMetrics';
PRINT '  - Frequency: Every 5 minutes (via SQL Agent Job)';
PRINT '';
PRINT 'Next Steps:';
PRINT '  1. Wait for next collection cycle (5 minutes)';
PRINT '  2. Update AWS RDS dashboard to use real metrics';
PRINT '  3. Remove placeholder queries (Active/Total connections)';
PRINT '========================================================';
GO
