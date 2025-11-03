-- =====================================================
-- Script: 81-fix-solarwinds-dpa-features.sql
-- Description: Fix errors in SolarWinds DPA features
-- Author: SQL Server Monitor Project
-- Date: 2025-11-02
-- Purpose: Fix ambiguous column names and invalid column references
-- =====================================================

USE MonitoringDB;
GO

PRINT 'Fixing SolarWinds DPA features...';
PRINT '';

-- =====================================================
-- FIX 1: usp_CalculateQueryPercentiles - Ambiguous column name
-- =====================================================

IF OBJECT_ID('dbo.usp_CalculateQueryPercentiles', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CalculateQueryPercentiles;
GO

CREATE PROCEDURE dbo.usp_CalculateQueryPercentiles
    @ServerID INT = NULL,
    @TimeWindowMinutes INT = 60  -- Calculate percentiles for last N minutes
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartTime DATETIME2 = DATEADD(MINUTE, -@TimeWindowMinutes, GETUTCDATE());

    PRINT '[usp_CalculateQueryPercentiles] Calculating percentiles...';
    PRINT '  Server ID: ' + ISNULL(CAST(@ServerID AS NVARCHAR), 'ALL');
    PRINT '  Time Window: Last ' + CAST(@TimeWindowMinutes AS NVARCHAR) + ' minutes';

    -- Create temp table with sample durations for each query
    IF OBJECT_ID('tempdb..#QueryDurations') IS NOT NULL
        DROP TABLE #QueryDurations;

    CREATE TABLE #QueryDurations
    (
        QueryStoreQueryID BIGINT,
        PlanID BIGINT,
        Duration DECIMAL(18,4),
        RowNum INT
    );

    -- Insert sample durations (FIXED: fully qualified column names)
    INSERT INTO #QueryDurations (QueryStoreQueryID, PlanID, Duration, RowNum)
    SELECT
        rs.QueryStoreQueryID,  -- FIXED: Added rs. prefix
        rs.PlanID,
        rs.AvgDurationMs,
        ROW_NUMBER() OVER (PARTITION BY rs.QueryStoreQueryID, rs.PlanID ORDER BY rs.CollectionTime)  -- FIXED: Added rs. prefix
    FROM dbo.QueryStoreRuntimeStats rs
    INNER JOIN dbo.QueryStoreQueries q ON rs.QueryStoreQueryID = q.QueryStoreQueryID
    WHERE rs.CollectionTime >= @StartTime
        AND (@ServerID IS NULL OR q.ServerID = @ServerID);

    DECLARE @QueryCount INT = (SELECT COUNT(DISTINCT QueryStoreQueryID) FROM #QueryDurations);
    PRINT '  Processing ' + CAST(@QueryCount AS NVARCHAR) + ' queries...';

    -- Calculate percentiles
    IF OBJECT_ID('tempdb..#Percentiles') IS NOT NULL
        DROP TABLE #Percentiles;

    SELECT
        QueryStoreQueryID,
        PlanID,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY Duration) OVER (PARTITION BY QueryStoreQueryID, PlanID) AS P50,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY Duration) OVER (PARTITION BY QueryStoreQueryID, PlanID) AS P95,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY Duration) OVER (PARTITION BY QueryStoreQueryID, PlanID) AS P99
    INTO #Percentiles
    FROM #QueryDurations;

    -- Update the most recent RuntimeStats record with percentiles
    UPDATE rs
    SET
        P50DurationMs = p.P50,
        P95DurationMs = p.P95,
        P99DurationMs = p.P99
    FROM dbo.QueryStoreRuntimeStats rs
    INNER JOIN (
        SELECT DISTINCT QueryStoreQueryID, PlanID, P50, P95, P99
        FROM #Percentiles
    ) p ON rs.QueryStoreQueryID = p.QueryStoreQueryID AND rs.PlanID = p.PlanID
    WHERE rs.RuntimeStatsID IN (
        -- Only update the most recent record for each query/plan
        SELECT MAX(RuntimeStatsID)
        FROM dbo.QueryStoreRuntimeStats
        WHERE CollectionTime >= @StartTime
            AND QueryStoreQueryID = rs.QueryStoreQueryID
            AND PlanID = rs.PlanID
        GROUP BY QueryStoreQueryID, PlanID
    );

    DECLARE @UpdatedRows INT = @@ROWCOUNT;
    PRINT '  ✓ Updated ' + CAST(@UpdatedRows AS NVARCHAR) + ' records with percentiles';

    -- Cleanup
    DROP TABLE #QueryDurations;
    DROP TABLE #Percentiles;

    RETURN 0;
END;
GO

PRINT '  ✓ usp_CalculateQueryPercentiles fixed';
PRINT '';

-- =====================================================
-- FIX 2: usp_GetWaitStatsByCategory - Invalid column name 'WaitCount'
-- =====================================================

IF OBJECT_ID('dbo.usp_GetWaitStatsByCategory', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetWaitStatsByCategory;
GO

CREATE PROCEDURE dbo.usp_GetWaitStatsByCategory
    @ServerID INT,
    @TimeWindowMinutes INT = 60
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartTime DATETIME2 = DATEADD(MINUTE, -@TimeWindowMinutes, GETUTCDATE());

    -- Return wait statistics grouped by category
    SELECT
        dbo.fn_CategorizeWaitType(ws.WaitType) AS WaitCategory,
        ws.WaitType,
        SUM(ws.WaitTimeMs) AS TotalWaitTimeMs,
        SUM(ws.WaitingTasksCount) AS TotalWaitCount,  -- FIXED: Changed from WaitCount to WaitingTasksCount
        AVG(ws.WaitTimeMs / NULLIF(ws.WaitingTasksCount, 0)) AS AvgWaitTimeMs,  -- FIXED: Changed from WaitCount to WaitingTasksCount
        MAX(ws.MaxWaitTimeMs) AS MaxWaitTimeMs,
        -- Calculate percentage of total waits
        CAST(
            100.0 * SUM(ws.WaitTimeMs) /
            NULLIF(SUM(SUM(ws.WaitTimeMs)) OVER (), 0)
            AS DECIMAL(10,2)
        ) AS PercentageOfTotal
    FROM dbo.WaitStatsSnapshot ws
    WHERE ws.SnapshotTime >= @StartTime
        AND ws.ServerID = @ServerID
        -- Exclude benign waits
        AND ws.WaitType NOT IN (
            'BROKER_EVENTHANDLER', 'BROKER_RECEIVE_WAITFOR', 'BROKER_TASK_STOP',
            'BROKER_TO_FLUSH', 'BROKER_TRANSMITTER', 'CHECKPOINT_QUEUE',
            'CHKPT', 'CLR_AUTO_EVENT', 'CLR_MANUAL_EVENT', 'CLR_SEMAPHORE',
            'DBMIRROR_DBM_EVENT', 'DBMIRROR_DBM_MUTEX', 'DBMIRROR_EVENTS_QUEUE',
            'DBMIRROR_WORKER_QUEUE', 'DBMIRRORING_CMD', 'DIRTY_PAGE_POLL',
            'DISPATCHER_QUEUE_SEMAPHORE', 'EXECSYNC', 'FSAGENT',
            'FT_IFTS_SCHEDULER_IDLE_WAIT', 'FT_IFTSHC_MUTEX', 'HADR_CLUSAPI_CALL',
            'HADR_FILESTREAM_IOMGR_IOCOMPLETION', 'HADR_LOGCAPTURE_WAIT',
            'HADR_NOTIFICATION_DEQUEUE', 'HADR_TIMER_TASK', 'HADR_WORK_QUEUE',
            'KSOURCE_WAKEUP', 'LAZYWRITER_SLEEP', 'LOGMGR_QUEUE',
            'MEMORY_ALLOCATION_EXT', 'ONDEMAND_TASK_QUEUE', 'PARALLEL_REDO_DRAIN_WORKER',
            'PARALLEL_REDO_LOG_CACHE', 'PARALLEL_REDO_TRAN_LIST', 'PARALLEL_REDO_WORKER_SYNC',
            'PARALLEL_REDO_WORKER_WAIT_WORK', 'PREEMPTIVE_OS_LIBRARYOPS',
            'PREEMPTIVE_OS_COMOPS', 'PREEMPTIVE_OS_CRYPTOPS', 'PREEMPTIVE_OS_PIPEOPS',
            'PREEMPTIVE_OS_AUTHENTICATIONOPS', 'PREEMPTIVE_OS_GENERICOPS',
            'PREEMPTIVE_OS_VERIFYTRUST', 'PREEMPTIVE_OS_FILEOPS',
            'PREEMPTIVE_OS_DEVICEOPS', 'PREEMPTIVE_XE_GETTARGETSTATE', 'PWAIT_ALL_COMPONENTS_INITIALIZED',
            'PWAIT_DIRECTLOGCONSUMER_GETNEXT', 'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
            'QDS_ASYNC_QUEUE', 'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
            'QDS_SHUTDOWN_QUEUE', 'REDO_THREAD_PENDING_WORK', 'REQUEST_FOR_DEADLOCK_SEARCH',
            'RESOURCE_QUEUE', 'SERVER_IDLE_CHECK', 'SLEEP_BPOOL_FLUSH', 'SLEEP_DBSTARTUP',
            'SLEEP_DCOMSTARTUP', 'SLEEP_MASTERDBREADY', 'SLEEP_MASTERMDREADY',
            'SLEEP_MASTERUPGRADED', 'SLEEP_MSDBSTARTUP', 'SLEEP_SYSTEMTASK', 'SLEEP_TASK',
            'SLEEP_TEMPDBSTARTUP', 'SNI_HTTP_ACCEPT', 'SP_SERVER_DIAGNOSTICS_SLEEP',
            'SQLTRACE_BUFFER_FLUSH', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', 'SQLTRACE_WAIT_ENTRIES',
            'WAIT_FOR_RESULTS', 'WAITFOR', 'WAITFOR_TASKSHUTDOWN', 'WAIT_XTP_RECOVERY',
            'WAIT_XTP_HOST_WAIT', 'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', 'WAIT_XTP_CKPT_CLOSE',
            'XE_DISPATCHER_JOIN', 'XE_DISPATCHER_WAIT', 'XE_TIMER_EVENT'
        )
    GROUP BY
        dbo.fn_CategorizeWaitType(ws.WaitType),
        ws.WaitType
    HAVING SUM(ws.WaitTimeMs) > 0  -- Only include waits that occurred
    ORDER BY
        TotalWaitTimeMs DESC;

    RETURN 0;
END;
GO

PRINT '  ✓ usp_GetWaitStatsByCategory fixed';
PRINT '';

PRINT '========================================';
PRINT 'SolarWinds DPA Features - FIXES COMPLETE';
PRINT '========================================';
PRINT '';
GO
