-- =====================================================================================
-- SQL Monitor - Timeout History Rescue Kit
-- Purpose: Diagnose the root cause of client timeouts after they've occurred
-- =====================================================================================
--
-- This script provides a comprehensive set of queries to investigate timeout issues
-- by examining multiple evidence sources:
--   1. Extended Events (system_health) - Attention/timeout events
--   2. Blocking history - What was blocking at the time?
--   3. Query Store - Plan regressions, forced plans
--   4. Wait statistics - Resource bottlenecks
--   5. Error logs - Application timeout errors
--   6. Long-running queries - Queries that exceeded thresholds
--
-- Usage:
--   1. Set @StartTime and @EndTime to the timeframe of the timeout incident
--   2. Run all sections to build a complete picture
--   3. Cross-reference findings across different evidence sources
--
-- Author: SQL Monitor Team
-- Date: 2025-10-29
-- =====================================================================================

USE DBATools  -- Or run on the database where timeouts occurred
GO

SET NOCOUNT ON
GO

PRINT ''
PRINT '=============================================================================='
PRINT 'TIMEOUT RESCUE KIT - Root Cause Analysis'
PRINT '=============================================================================='
PRINT ''

-- =====================================================================================
-- Configuration: Set your investigation timeframe
-- =====================================================================================

DECLARE @StartTime DATETIME = DATEADD(HOUR, -4, GETDATE())  -- Last 4 hours
DECLARE @EndTime DATETIME = GETDATE()
DECLARE @TimeoutThresholdSeconds INT = 30  -- Your application timeout setting

PRINT 'Investigation Timeframe:'
PRINT '  Start: ' + CONVERT(VARCHAR(30), @StartTime, 120)
PRINT '  End:   ' + CONVERT(VARCHAR(30), @EndTime, 120)
PRINT '  Timeout Threshold: ' + CAST(@TimeoutThresholdSeconds AS VARCHAR) + ' seconds'
PRINT ''

-- =====================================================================================
-- SECTION 1: Attention Events (Client-Side Timeouts)
-- =====================================================================================
-- Attention events occur when a client cancels a query (timeout or user cancellation)
-- Source: system_health Extended Event session
-- =====================================================================================

PRINT '=============================================================================='
PRINT 'SECTION 1: ATTENTION EVENTS (Client-Side Query Cancellations)'
PRINT '=============================================================================='
PRINT ''

;WITH AttentionEvents AS
(
    SELECT
        event_data.value('(@timestamp)[1]', 'DATETIME') AS EventTime,
        event_data.value('(data[@name="duration"]/value)[1]', 'BIGINT') / 1000000 AS DurationSeconds,
        event_data.value('(action[@name="session_id"]/value)[1]', 'INT') AS SessionID,
        event_data.value('(action[@name="database_name"]/value)[1]', 'VARCHAR(128)') AS DatabaseName,
        event_data.value('(action[@name="username"]/value)[1]', 'VARCHAR(128)') AS Username,
        event_data.value('(action[@name="client_app_name"]/value)[1]', 'VARCHAR(256)') AS ClientApp,
        event_data.value('(action[@name="sql_text"]/value)[1]', 'VARCHAR(MAX)') AS SqlText
    FROM
    (
        SELECT CAST(target_data AS XML) AS TargetData
        FROM sys.dm_xe_session_targets st
        JOIN sys.dm_xe_sessions s ON s.address = st.event_session_address
        WHERE s.name = 'system_health'
          AND st.target_name = 'ring_buffer'
    ) AS Data
    CROSS APPLY TargetData.nodes('RingBufferTarget/event[@name="attention"]') AS XEventData(event_data)
    WHERE event_data.value('(@timestamp)[1]', 'DATETIME') BETWEEN @StartTime AND @EndTime
)
SELECT
    EventTime,
    SessionID,
    DatabaseName,
    Username,
    ClientApp,
    DurationSeconds,
    CASE
        WHEN DurationSeconds >= @TimeoutThresholdSeconds THEN 'LIKELY TIMEOUT'
        WHEN DurationSeconds >= (@TimeoutThresholdSeconds * 0.75) THEN 'Warning (75% of threshold)'
        ELSE 'User Cancellation'
    END AS AttentionReason,
    LEFT(SqlText, 200) AS SqlTextPreview
FROM AttentionEvents
ORDER BY EventTime DESC

IF @@ROWCOUNT = 0
    PRINT '  ℹ  No attention events found in system_health for this timeframe'
ELSE
    PRINT '  ✓ Attention events listed above'

PRINT ''

-- =====================================================================================
-- SECTION 2: Long-Running Queries (From DBATools Snapshots)
-- =====================================================================================
-- Queries captured in DBATools that exceeded the timeout threshold
-- Source: PerfSnapshotWorkload table
-- =====================================================================================

PRINT '=============================================================================='
PRINT 'SECTION 2: LONG-RUNNING QUERIES (From Performance Snapshots)'
PRINT '=============================================================================='
PRINT ''

SELECT
    r.SnapshotUTC AS CaptureTime,
    w.SessionID,
    w.LoginName,
    w.HostName,
    w.DatabaseName,
    w.Status,
    w.Command,
    w.WaitType,
    w.WaitTimeMs,
    w.BlockingSessionID,
    w.CpuTimeMs,
    w.TotalElapsedMs,
    w.LogicalReads,
    CAST(w.TotalElapsedMs / 1000.0 AS DECIMAL(18,2)) AS ElapsedSeconds,
    CASE
        WHEN w.TotalElapsedMs >= (@TimeoutThresholdSeconds * 1000) THEN 'EXCEEDED TIMEOUT'
        WHEN w.TotalElapsedMs >= (@TimeoutThresholdSeconds * 750) THEN 'Near Timeout (75%+)'
        ELSE 'Below Threshold'
    END AS TimeoutRisk,
    LEFT(w.StatementText, 200) AS StatementPreview,
    w.OBJECT_NAME_Resolved
FROM DBATools.dbo.PerfSnapshotWorkload w
INNER JOIN DBATools.dbo.PerfSnapshotRun r ON w.PerfSnapshotRunID = r.PerfSnapshotRunID
WHERE r.SnapshotUTC BETWEEN @StartTime AND @EndTime
  AND w.TotalElapsedMs >= (@TimeoutThresholdSeconds * 500)  -- 50%+ of timeout threshold
ORDER BY w.TotalElapsedMs DESC, r.SnapshotUTC DESC

IF @@ROWCOUNT = 0
    PRINT '  ℹ  No long-running queries found in DBATools snapshots for this timeframe'
ELSE
    PRINT '  ✓ Long-running queries listed above'

PRINT ''

-- =====================================================================================
-- SECTION 3: Blocking Chains (What Was Blocking the Timed-Out Queries?)
-- =====================================================================================
-- Identify blocking sessions that may have caused timeouts
-- Source: PerfSnapshotWorkload (blocking data)
-- =====================================================================================

PRINT '=============================================================================='
PRINT 'SECTION 3: BLOCKING CHAINS (Root Cause of Waits)'
PRINT '=============================================================================='
PRINT ''

;WITH BlockingChains AS
(
    SELECT
        r.SnapshotUTC AS CaptureTime,
        w.SessionID AS BlockedSession,
        w.BlockingSessionID AS BlockingSession,
        w.WaitType,
        w.WaitTimeMs,
        w.DatabaseName,
        w.Status,
        w.TotalElapsedMs AS BlockedElapsedMs,
        LEFT(w.StatementText, 200) AS BlockedStatement
    FROM DBATools.dbo.PerfSnapshotWorkload w
    INNER JOIN DBATools.dbo.PerfSnapshotRun r ON w.PerfSnapshotRunID = r.PerfSnapshotRunID
    WHERE r.SnapshotUTC BETWEEN @StartTime AND @EndTime
      AND w.BlockingSessionID > 0  -- Only blocked sessions
      AND w.WaitTimeMs > 1000  -- Waited more than 1 second
),
BlockerDetails AS
(
    SELECT
        w2.SessionID AS BlockerSessionID,
        r2.SnapshotUTC,
        w2.LoginName AS BlockerLogin,
        w2.HostName AS BlockerHost,
        w2.Command AS BlockerCommand,
        LEFT(w2.StatementText, 200) AS BlockerStatement
    FROM DBATools.dbo.PerfSnapshotWorkload w2
    INNER JOIN DBATools.dbo.PerfSnapshotRun r2 ON w2.PerfSnapshotRunID = r2.PerfSnapshotRunID
    WHERE r2.SnapshotUTC BETWEEN @StartTime AND @EndTime
)
SELECT
    bc.CaptureTime,
    bc.BlockedSession,
    bc.BlockingSession,
    bd.BlockerLogin,
    bd.BlockerHost,
    bc.WaitType,
    CAST(bc.WaitTimeMs / 1000.0 AS DECIMAL(18,2)) AS WaitSeconds,
    CAST(bc.BlockedElapsedMs / 1000.0 AS DECIMAL(18,2)) AS BlockedElapsedSeconds,
    bc.DatabaseName,
    bc.BlockedStatement AS WhatWasBlocked,
    bd.BlockerStatement AS WhatWasBlocking
FROM BlockingChains bc
LEFT JOIN BlockerDetails bd
    ON bc.BlockingSession = bd.BlockerSessionID
    AND ABS(DATEDIFF(SECOND, bc.CaptureTime, bd.SnapshotUTC)) < 30  -- Within 30 seconds
ORDER BY bc.WaitTimeMs DESC, bc.CaptureTime DESC

IF @@ROWCOUNT = 0
    PRINT '  ℹ  No significant blocking found in this timeframe'
ELSE
    PRINT '  ✓ Blocking chains listed above - investigate the blocker sessions'

PRINT ''

-- =====================================================================================
-- SECTION 4: Wait Statistics (Resource Bottlenecks)
-- =====================================================================================
-- Identify which resources were under pressure during the timeout window
-- Source: PerfSnapshotWaitStats (aggregated wait stats)
-- =====================================================================================

PRINT '=============================================================================='
PRINT 'SECTION 4: WAIT STATISTICS (Resource Bottlenecks)'
PRINT '=============================================================================='
PRINT ''

SELECT TOP 20
    r.SnapshotUTC AS SnapshotTime,
    ws.WaitType,
    ws.WaitingTasksCount,
    CAST(ws.WaitTimeMs / 1000.0 AS DECIMAL(18,2)) AS WaitSeconds,
    CAST(ws.AvgWaitTimeMs AS DECIMAL(18,2)) AS AvgWaitMs,
    CASE ws.WaitType
        WHEN 'LCK_M_X' THEN 'Exclusive Lock - Check blocking'
        WHEN 'LCK_M_S' THEN 'Shared Lock - Check blocking'
        WHEN 'LCK_M_U' THEN 'Update Lock - Check blocking'
        WHEN 'PAGEIOLATCH_SH' THEN 'Disk I/O - Check storage performance'
        WHEN 'PAGEIOLATCH_EX' THEN 'Disk I/O - Check storage performance'
        WHEN 'WRITELOG' THEN 'Transaction Log I/O - Check log disk'
        WHEN 'ASYNC_NETWORK_IO' THEN 'Client slow to receive data'
        WHEN 'CXPACKET' THEN 'Parallelism - Check query plans'
        WHEN 'RESOURCE_SEMAPHORE' THEN 'Memory Grant Wait - Memory pressure'
        WHEN 'SOS_SCHEDULER_YIELD' THEN 'CPU Pressure - Check CPU usage'
        ELSE 'See wait stats documentation'
    END AS WaitTypeDescription
FROM DBATools.dbo.PerfSnapshotWaitStats ws
INNER JOIN DBATools.dbo.PerfSnapshotRun r ON ws.PerfSnapshotRunID = r.PerfSnapshotRunID
WHERE r.SnapshotUTC BETWEEN @StartTime AND @EndTime
  AND ws.WaitType NOT IN ('BROKER_EVENTHANDLER', 'BROKER_RECEIVE_WAITFOR', 'BROKER_TASK_STOP',
                          'BROKER_TO_FLUSH', 'BROKER_TRANSMITTER', 'CHECKPOINT_QUEUE',
                          'CHKPT', 'CLR_AUTO_EVENT', 'CLR_MANUAL_EVENT', 'CLR_SEMAPHORE',
                          'DBMIRROR_DBM_EVENT', 'DBMIRROR_EVENTS_QUEUE', 'DBMIRROR_WORKER_QUEUE',
                          'DBMIRRORING_CMD', 'DIRTY_PAGE_POLL', 'DISPATCHER_QUEUE_SEMAPHORE',
                          'EXECSYNC', 'FSAGENT', 'FT_IFTS_SCHEDULER_IDLE_WAIT', 'FT_IFTSHC_MUTEX',
                          'HADR_CLUSAPI_CALL', 'HADR_FILESTREAM_IOMGR_IOCOMPLETION', 'HADR_LOGCAPTURE_WAIT',
                          'HADR_NOTIFICATION_DEQUEUE', 'HADR_TIMER_TASK', 'HADR_WORK_QUEUE',
                          'KSOURCE_WAKEUP', 'LAZYWRITER_SLEEP', 'LOGMGR_QUEUE',
                          'MEMORY_ALLOCATION_EXT', 'ONDEMAND_TASK_QUEUE',
                          'PARALLEL_REDO_WORKER_WAIT_WORK', 'PREEMPTIVE_XE_GETTARGETSTATE',
                          'PWAIT_ALL_COMPONENTS_INITIALIZED', 'PWAIT_DIRECTLOGCONSUMER_GETNEXT',
                          'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', 'QDS_ASYNC_QUEUE',
                          'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', 'QDS_SHUTDOWN_QUEUE',
                          'REDO_THREAD_PENDING_WORK', 'REQUEST_FOR_DEADLOCK_SEARCH', 'RESOURCE_QUEUE',
                          'SERVER_IDLE_CHECK', 'SLEEP_BPOOL_FLUSH', 'SLEEP_DBSTARTUP', 'SLEEP_DCOMSTARTUP',
                          'SLEEP_MASTERDBREADY', 'SLEEP_MASTERMDREADY', 'SLEEP_MASTERUPGRADED',
                          'SLEEP_MSDBSTARTUP', 'SLEEP_SYSTEMTASK', 'SLEEP_TASK',
                          'SLEEP_TEMPDBSTARTUP', 'SNI_HTTP_ACCEPT', 'SP_SERVER_DIAGNOSTICS_SLEEP',
                          'SQLTRACE_BUFFER_FLUSH', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
                          'SQLTRACE_WAIT_ENTRIES', 'WAIT_FOR_RESULTS', 'WAITFOR',
                          'WAITFOR_TASKSHUTDOWN', 'WAIT_XTP_RECOVERY',
                          'WAIT_XTP_HOST_WAIT', 'WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
                          'WAIT_XTP_CKPT_CLOSE', 'XE_DISPATCHER_JOIN',
                          'XE_DISPATCHER_WAIT', 'XE_TIMER_EVENT')  -- Filter benign waits
ORDER BY ws.WaitTimeMs DESC

IF @@ROWCOUNT = 0
    PRINT '  ℹ  No significant wait statistics found'
ELSE
    PRINT '  ✓ Wait statistics listed above - focus on top wait types'

PRINT ''

-- =====================================================================================
-- SECTION 5: Query Store - Plan Regressions
-- =====================================================================================
-- Check if plan changes caused performance degradation
-- Source: Query Store (if enabled)
-- =====================================================================================

PRINT '=============================================================================='
PRINT 'SECTION 5: QUERY STORE - Plan Regressions'
PRINT '=============================================================================='
PRINT ''

IF EXISTS (SELECT 1 FROM sys.databases WHERE name = DB_NAME() AND is_query_store_on = 1)
BEGIN
    -- Top regressed queries (worse performance in recent interval)
    SELECT TOP 20
        qsq.query_id,
        OBJECT_NAME(qsq.object_id) AS ObjectName,
        qsrs.avg_duration / 1000.0 AS AvgDurationMs,
        qsrs.max_duration / 1000.0 AS MaxDurationMs,
        qsrs.count_executions AS ExecutionCount,
        qsrs.last_execution_time,
        qsp.plan_id,
        CASE
            WHEN qsp.is_forced_plan = 1 THEN 'FORCED'
            WHEN qsp.force_failure_count > 0 THEN 'FORCE FAILED'
            ELSE 'Not Forced'
        END AS PlanStatus,
        LEFT(qst.query_sql_text, 200) AS QueryText
    FROM sys.query_store_query qsq
    INNER JOIN sys.query_store_plan qsp ON qsq.query_id = qsp.query_id
    INNER JOIN sys.query_store_runtime_stats qsrs ON qsp.plan_id = qsrs.plan_id
    INNER JOIN sys.query_store_query_text qst ON qsq.query_text_id = qst.query_text_id
    INNER JOIN sys.query_store_runtime_stats_interval qsrsi ON qsrs.runtime_stats_interval_id = qsrsi.runtime_stats_interval_id
    WHERE qsrsi.start_time >= @StartTime
      AND qsrsi.end_time <= @EndTime
      AND qsrs.avg_duration > (@TimeoutThresholdSeconds * 1000000)  -- Query Store uses microseconds
    ORDER BY qsrs.avg_duration DESC

    IF @@ROWCOUNT = 0
        PRINT '  ℹ  No plan regressions found in Query Store'
    ELSE
        PRINT '  ✓ Plan regressions listed above - investigate plan changes'
END
ELSE
BEGIN
    PRINT '  ℹ  Query Store is not enabled on this database'
    PRINT '      To enable: ALTER DATABASE [' + DB_NAME() + '] SET QUERY_STORE = ON'
END

PRINT ''

-- =====================================================================================
-- SECTION 6: Recently Executed Slow Queries (DMV Cache)
-- =====================================================================================
-- Queries still in plan cache that took longer than timeout threshold
-- Source: sys.dm_exec_query_stats
-- =====================================================================================

PRINT '=============================================================================='
PRINT 'SECTION 6: RECENTLY EXECUTED SLOW QUERIES (DMV Cache)'
PRINT '=============================================================================='
PRINT ''

SELECT TOP 30
    DB_NAME(st.dbid) AS DatabaseName,
    OBJECT_NAME(st.objectid, st.dbid) AS ObjectName,
    qs.last_execution_time,
    qs.execution_count,
    CAST((qs.total_elapsed_time / qs.execution_count) / 1000.0 AS DECIMAL(18,2)) AS AvgElapsedMs,
    CAST(qs.max_elapsed_time / 1000.0 AS DECIMAL(18,2)) AS MaxElapsedMs,
    CAST(qs.min_elapsed_time / 1000.0 AS DECIMAL(18,2)) AS MinElapsedMs,
    CAST(qs.total_worker_time / qs.execution_count / 1000.0 AS DECIMAL(18,2)) AS AvgCpuMs,
    CAST(qs.total_logical_reads / qs.execution_count AS DECIMAL(18,2)) AS AvgLogicalReads,
    CASE
        WHEN qs.max_elapsed_time / 1000.0 >= (@TimeoutThresholdSeconds * 1000) THEN 'EXCEEDED TIMEOUT'
        WHEN qs.max_elapsed_time / 1000.0 >= (@TimeoutThresholdSeconds * 750) THEN 'Near Timeout (75%+)'
        ELSE 'Below Threshold'
    END AS TimeoutRisk,
    LEFT(st.text, 200) AS QueryTextPreview
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE qs.last_execution_time >= @StartTime
  AND (qs.max_elapsed_time / 1000.0) >= (@TimeoutThresholdSeconds * 500)  -- 50%+ of threshold
ORDER BY qs.max_elapsed_time DESC

IF @@ROWCOUNT = 0
    PRINT '  ℹ  No slow queries found in DMV cache for this timeframe'
ELSE
    PRINT '  ✓ Slow queries listed above - investigate these procedures/statements'

PRINT ''

-- =====================================================================================
-- SECTION 7: SQL Server Error Log (Application Timeout Messages)
-- =====================================================================================
-- Check error log for timeout-related entries
-- Source: xp_readerrorlog
-- =====================================================================================

PRINT '=============================================================================='
PRINT 'SECTION 7: SQL SERVER ERROR LOG (Timeout Messages)'
PRINT '=============================================================================='
PRINT ''

BEGIN TRY
    CREATE TABLE #ErrorLog
    (
        LogDate DATETIME,
        ProcessInfo VARCHAR(50),
        LogText VARCHAR(MAX)
    )

    -- Try to read timeout-related entries
    BEGIN TRY
        INSERT INTO #ErrorLog
        EXEC xp_readerrorlog 0, 1, 'timeout', NULL, @StartTime, @EndTime
    END TRY
    BEGIN CATCH
        -- Ignore errors (log might be locked or inaccessible)
        PRINT '  ⚠  Could not read error log for "timeout" keyword'
    END CATCH

    -- Try to read attention-related entries
    BEGIN TRY
        INSERT INTO #ErrorLog
        EXEC xp_readerrorlog 0, 1, 'attention', NULL, @StartTime, @EndTime
    END TRY
    BEGIN CATCH
        -- Ignore errors
        PRINT '  ⚠  Could not read error log for "attention" keyword'
    END CATCH

    -- Display results if any
    IF EXISTS (SELECT 1 FROM #ErrorLog)
    BEGIN
        SELECT
            LogDate,
            ProcessInfo,
            LogText
        FROM #ErrorLog
        ORDER BY LogDate DESC

        PRINT '  ✓ Error log entries listed above'
    END
    ELSE
    BEGIN
        PRINT '  ℹ  No timeout-related entries found in SQL Server error log'
    END

    DROP TABLE #ErrorLog
END TRY
BEGIN CATCH
    PRINT '  ⚠  Error reading SQL Server error log: ' + ERROR_MESSAGE()
    PRINT '  ℹ  This section can be skipped - error log analysis is optional'
    IF OBJECT_ID('tempdb..#ErrorLog') IS NOT NULL
        DROP TABLE #ErrorLog
END CATCH

PRINT ''

-- =====================================================================================
-- SECTION 8: Deadlock Events
-- =====================================================================================
-- Check if deadlocks contributed to timeout perception
-- Source: PerfSnapshotDeadlockDetails (if available)
-- =====================================================================================

PRINT '=============================================================================='
PRINT 'SECTION 8: DEADLOCK EVENTS'
PRINT '=============================================================================='
PRINT ''

IF OBJECT_ID('DBATools.dbo.PerfSnapshotDeadlockDetails') IS NOT NULL
BEGIN
    SELECT
        r.SnapshotUTC AS CaptureTime,
        d.VictimSessionID,
        d.VictimLoginName,
        d.BlockingSessionID,
        d.BlockingLoginName,
        LEFT(d.VictimQuery, 200) AS VictimQueryPreview,
        LEFT(d.BlockingQuery, 200) AS BlockingQueryPreview,
        d.LockMode,
        d.ResourceType
    FROM DBATools.dbo.PerfSnapshotDeadlockDetails d
    INNER JOIN DBATools.dbo.PerfSnapshotRun r ON d.PerfSnapshotRunID = r.PerfSnapshotRunID
    WHERE r.SnapshotUTC BETWEEN @StartTime AND @EndTime
    ORDER BY r.SnapshotUTC DESC

    IF @@ROWCOUNT = 0
        PRINT '  ℹ  No deadlocks found in this timeframe'
    ELSE
        PRINT '  ✓ Deadlocks listed above - may have caused application retries/timeouts'
END
ELSE
BEGIN
    PRINT '  ℹ  Deadlock tracking not available (PerfSnapshotDeadlockDetails table not found)'
END

PRINT ''

-- =====================================================================================
-- SECTION 9: Server Resource Pressure
-- =====================================================================================
-- Check if server-level resource constraints contributed to timeouts
-- Source: PerfSnapshotRun (server health metrics)
-- =====================================================================================

PRINT '=============================================================================='
PRINT 'SECTION 9: SERVER RESOURCE PRESSURE'
PRINT '=============================================================================='
PRINT ''

SELECT
    SnapshotUTC AS SnapshotTime,
    CpuSignalWaitPct AS CPUPressurePct,
    TopWaitType,
    CAST(TopWaitMsPerSec / 1000.0 AS DECIMAL(18,2)) AS TopWaitSecondsPerSec,
    SessionsCount,
    RequestsCount,
    BlockingSessionCount,
    DeadlockCountRecent,
    MemoryGrantWarningCount,
    CASE
        WHEN CpuSignalWaitPct > 50 THEN 'HIGH CPU PRESSURE'
        WHEN CpuSignalWaitPct > 25 THEN 'Moderate CPU Pressure'
        WHEN BlockingSessionCount > 5 THEN 'HIGH BLOCKING'
        WHEN DeadlockCountRecent > 0 THEN 'DEADLOCKS DETECTED'
        ELSE 'Normal'
    END AS ServerStatus
FROM DBATools.dbo.PerfSnapshotRun
WHERE SnapshotUTC BETWEEN @StartTime AND @EndTime
ORDER BY SnapshotUTC DESC

IF @@ROWCOUNT = 0
    PRINT '  ℹ  No server health snapshots found for this timeframe'
ELSE
    PRINT '  ✓ Server health metrics listed above'

PRINT ''

-- =====================================================================================
-- SECTION 10: Memory Pressure
-- =====================================================================================
-- Check if memory grants or Page Life Expectancy indicate memory pressure
-- Source: PerfSnapshotMemory (if available)
-- =====================================================================================

PRINT '=============================================================================='
PRINT 'SECTION 10: MEMORY PRESSURE'
PRINT '=============================================================================='
PRINT ''

IF OBJECT_ID('DBATools.dbo.PerfSnapshotMemory') IS NOT NULL
BEGIN
    SELECT
        r.SnapshotUTC AS SnapshotTime,
        m.PageLifeExpectancy,
        m.BufferCacheHitRatio,
        m.TotalServerMemoryMB,
        m.TargetServerMemoryMB,
        m.FreeMemoryMB,
        m.MemoryGrantsPending,
        m.MemoryGrantsOutstanding,
        CASE
            WHEN m.PageLifeExpectancy < 300 THEN 'SEVERE MEMORY PRESSURE'
            WHEN m.PageLifeExpectancy < 1000 THEN 'Memory Pressure'
            WHEN m.MemoryGrantsPending > 0 THEN 'QUERIES WAITING FOR MEMORY'
            ELSE 'Normal'
        END AS MemoryStatus
    FROM DBATools.dbo.PerfSnapshotMemory m
    INNER JOIN DBATools.dbo.PerfSnapshotRun r ON m.PerfSnapshotRunID = r.PerfSnapshotRunID
    WHERE r.SnapshotUTC BETWEEN @StartTime AND @EndTime
    ORDER BY r.SnapshotUTC DESC

    IF @@ROWCOUNT = 0
        PRINT '  ℹ  No memory metrics found for this timeframe'
    ELSE
        PRINT '  ✓ Memory metrics listed above'
END
ELSE
BEGIN
    PRINT '  ℹ  Memory tracking not available (PerfSnapshotMemory table not found)'
END

PRINT ''

-- =====================================================================================
-- SUMMARY & RECOMMENDATIONS
-- =====================================================================================

PRINT '=============================================================================='
PRINT 'TIMEOUT RESCUE KIT - SUMMARY'
PRINT '=============================================================================='
PRINT ''
PRINT 'Root Cause Analysis Checklist:'
PRINT ''
PRINT '  1. ATTENTION EVENTS: Did clients actually timeout? (Section 1)'
PRINT '     → Look for events matching your timeout threshold'
PRINT ''
PRINT '  2. LONG-RUNNING QUERIES: What queries exceeded the timeout? (Section 2, 6)'
PRINT '     → Identify the specific stored procedures or statements'
PRINT ''
PRINT '  3. BLOCKING: Was blocking the root cause? (Section 3)'
PRINT '     → Find the blocking session and what it was doing'
PRINT ''
PRINT '  4. RESOURCE BOTTLENECK: What resource was constrained? (Section 4, 9, 10)'
PRINT '     → CPU pressure (CpuSignalWaitPct > 25%)'
PRINT '     → Disk I/O (PAGEIOLATCH waits, avg latency > 20ms)'
PRINT '     → Memory pressure (Page Life Expectancy < 1000s)'
PRINT '     → Lock contention (LCK_M_* waits)'
PRINT ''
PRINT '  5. PLAN REGRESSION: Did a plan change cause slowdown? (Section 5)'
PRINT '     → Compare current plan to historical performance'
PRINT '     → Consider forcing good plan if regression found'
PRINT ''
PRINT '  6. DEADLOCKS: Did deadlocks cause retries/delays? (Section 8)'
PRINT '     → Investigate deadlock victims and patterns'
PRINT ''
PRINT 'Typical Root Causes by Symptom:'
PRINT ''
PRINT '  • Timeout + High LCK_M_* waits = BLOCKING (check Section 3)'
PRINT '  • Timeout + High PAGEIOLATCH = SLOW DISK (check storage performance)'
PRINT '  • Timeout + High CXPACKET = PARALLELISM (check query plans, consider MAXDOP)'
PRINT '  • Timeout + Low PLE = MEMORY PRESSURE (add RAM or tune queries)'
PRINT '  • Timeout + CpuSignalWaitPct > 50% = CPU PRESSURE (check for scans)'
PRINT '  • Timeout + Plan regression = BAD PLAN (force good plan or update stats)'
PRINT ''
PRINT 'Next Steps:'
PRINT ''
PRINT '  1. Correlate evidence across sections (time-based matching)'
PRINT '  2. Identify the slowest query at the time of timeout (Section 2, 6)'
PRINT '  3. Determine if blocking, resource pressure, or plan change was the cause'
PRINT '  4. Take corrective action:'
PRINT '     - Blocking: Optimize blocker query, reduce transaction duration'
PRINT '     - I/O: Add indexes, improve storage performance'
PRINT '     - CPU: Optimize queries, reduce scans, consider more CPUs'
PRINT '     - Memory: Add RAM, optimize memory-heavy queries'
PRINT '     - Plan: Force good plan, update statistics, rebuild indexes'
PRINT ''
PRINT '=============================================================================='
PRINT 'RESCUE KIT COMPLETE'
PRINT '=============================================================================='
PRINT ''

GO
