-- =====================================================
-- Script: 07-create-drilldown-procedures.sql
-- Description: Collection procedures for drill-down analysis
-- Author: SQL Server Monitor Project
-- Date: 2025-10-25
-- Purpose: Collect metrics at Database → Procedure → Query levels
-- =====================================================

USE MonitoringDB;
GO

-- =====================================================
-- 1. usp_CollectDatabaseMetrics
-- Collects performance metrics per database
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectDatabaseMetrics', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectDatabaseMetrics;
GO

CREATE PROCEDURE dbo.usp_CollectDatabaseMetrics
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CollectionTime DATETIME2 = GETUTCDATE();

    -- CPU usage by database
    INSERT INTO dbo.DatabaseMetrics (ServerID, DatabaseName, CollectionTime, MetricCategory, MetricName, MetricValue)
    SELECT
        @ServerID,
        DB_NAME(CAST(pa.value AS INT)) AS DatabaseName,
        @CollectionTime,
        'CPU',
        'TotalCPUMs',
        SUM(qs.total_worker_time) / 1000.0
    FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) pa
    WHERE pa.attribute = 'dbid'
      AND CAST(pa.value AS INT) > 0
      AND DB_NAME(CAST(pa.value AS INT)) IS NOT NULL
    GROUP BY CAST(pa.value AS INT);

    -- I/O by database
    INSERT INTO dbo.DatabaseMetrics (ServerID, DatabaseName, CollectionTime, MetricCategory, MetricName, MetricValue)
    SELECT
        @ServerID,
        DB_NAME(database_id) AS DatabaseName,
        @CollectionTime,
        'IO',
        'TotalReadsMB',
        SUM(num_of_bytes_read) / 1024.0 / 1024.0
    FROM sys.dm_io_virtual_file_stats(NULL, NULL)
    GROUP BY database_id;

    INSERT INTO dbo.DatabaseMetrics (ServerID, DatabaseName, CollectionTime, MetricCategory, MetricName, MetricValue)
    SELECT
        @ServerID,
        DB_NAME(database_id) AS DatabaseName,
        @CollectionTime,
        'IO',
        'TotalWritesMB',
        SUM(num_of_bytes_written) / 1024.0 / 1024.0
    FROM sys.dm_io_virtual_file_stats(NULL, NULL)
    GROUP BY database_id;

    -- Connections by database
    INSERT INTO dbo.ConnectionsByDatabase (ServerID, DatabaseName, CollectionTime, TotalConnections, ActiveConnections, SleepingConnections, BlockedConnections)
    SELECT
        @ServerID,
        ISNULL(DB_NAME(s.database_id), 'N/A') AS DatabaseName,
        @CollectionTime,
        COUNT(*) AS TotalConnections,
        SUM(CASE WHEN s.status = 'running' THEN 1 ELSE 0 END) AS ActiveConnections,
        SUM(CASE WHEN s.status = 'sleeping' THEN 1 ELSE 0 END) AS SleepingConnections,
        SUM(CASE WHEN r.blocking_session_id > 0 THEN 1 ELSE 0 END) AS BlockedConnections
    FROM sys.dm_exec_sessions s
    LEFT JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
    WHERE s.session_id > 50
    GROUP BY s.database_id;

    PRINT 'Database-level metrics collected for ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' databases';
END;
GO

-- =====================================================
-- 2. usp_CollectProcedureMetrics
-- Collects performance metrics per stored procedure
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectProcedureMetrics', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectProcedureMetrics;
GO

CREATE PROCEDURE dbo.usp_CollectProcedureMetrics
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CollectionTime DATETIME2 = GETUTCDATE();

    -- Top procedures by performance
    INSERT INTO dbo.ProcedureMetrics (
        ServerID, DatabaseName, SchemaName, ProcedureName, CollectionTime,
        ExecutionCount, TotalCPUMs, AvgCPUMs, TotalDurationMs, AvgDurationMs,
        TotalLogicalReads, AvgLogicalReads, TotalPhysicalReads, LastExecutionTime
    )
    SELECT TOP 100
        @ServerID,
        DB_NAME(ps.database_id) AS DatabaseName,
        OBJECT_SCHEMA_NAME(ps.object_id, ps.database_id) AS SchemaName,
        OBJECT_NAME(ps.object_id, ps.database_id) AS ProcedureName,
        @CollectionTime,
        ps.execution_count,
        ps.total_worker_time / 1000 AS TotalCPUMs,
        (ps.total_worker_time / 1000.0) / NULLIF(ps.execution_count, 0) AS AvgCPUMs,
        ps.total_elapsed_time / 1000 AS TotalDurationMs,
        (ps.total_elapsed_time / 1000.0) / NULLIF(ps.execution_count, 0) AS AvgDurationMs,
        ps.total_logical_reads,
        CAST(ps.total_logical_reads AS DECIMAL(18,4)) / NULLIF(ps.execution_count, 0) AS AvgLogicalReads,
        ps.total_physical_reads,
        ps.last_execution_time
    FROM sys.dm_exec_procedure_stats ps
    WHERE ps.database_id > 4 -- Exclude system databases
      AND DB_NAME(ps.database_id) IS NOT NULL
      AND OBJECT_NAME(ps.object_id, ps.database_id) IS NOT NULL
    ORDER BY ps.total_worker_time DESC;

    PRINT 'Procedure metrics collected for ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' procedures';
END;
GO

-- =====================================================
-- 3. usp_CollectQueryMetrics
-- Collects performance metrics per query
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectQueryMetrics', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectQueryMetrics;
GO

CREATE PROCEDURE dbo.usp_CollectQueryMetrics
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CollectionTime DATETIME2 = GETUTCDATE();

    -- Top queries by CPU
    INSERT INTO dbo.QueryMetrics (
        ServerID, DatabaseName, QueryHash, QueryPlanHash, CollectionTime,
        QueryText, ExecutionCount, TotalCPUMs, AvgCPUMs, MaxCPUMs,
        TotalDurationMs, AvgDurationMs, MaxDurationMs,
        TotalLogicalReads, AvgLogicalReads, TotalPhysicalReads,
        TotalWrites, LastExecutionTime
    )
    SELECT TOP 100
        @ServerID,
        DB_NAME(CAST(pa.value AS INT)) AS DatabaseName,
        qs.query_hash,
        qs.query_plan_hash,
        @CollectionTime,
        SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
            ((CASE qs.statement_end_offset
                WHEN -1 THEN DATALENGTH(st.text)
                ELSE qs.statement_end_offset
            END - qs.statement_start_offset)/2) + 1) AS QueryText,
        qs.execution_count,
        qs.total_worker_time / 1000 AS TotalCPUMs,
        (qs.total_worker_time / 1000.0) / NULLIF(qs.execution_count, 0) AS AvgCPUMs,
        qs.max_worker_time / 1000 AS MaxCPUMs,
        qs.total_elapsed_time / 1000 AS TotalDurationMs,
        (qs.total_elapsed_time / 1000.0) / NULLIF(qs.execution_count, 0) AS AvgDurationMs,
        qs.max_elapsed_time / 1000 AS MaxDurationMs,
        qs.total_logical_reads,
        CAST(qs.total_logical_reads AS DECIMAL(18,4)) / NULLIF(qs.execution_count, 0) AS AvgLogicalReads,
        qs.total_physical_reads,
        qs.total_logical_writes AS TotalWrites,
        qs.last_execution_time
    FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
    CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) pa
    WHERE pa.attribute = 'dbid'
      AND CAST(pa.value AS INT) > 4 -- Exclude system databases
    ORDER BY qs.total_worker_time DESC;

    PRINT 'Query metrics collected for ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' queries';
END;
GO

-- =====================================================
-- 4. usp_CollectWaitEventsByDatabase
-- Collects wait statistics per database
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectWaitEventsByDatabase', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectWaitEventsByDatabase;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE PROCEDURE dbo.usp_CollectWaitEventsByDatabase
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CollectionTime DATETIME2 = GETUTCDATE();

    -- Wait stats by database (from blocking/waiting sessions)
    INSERT INTO dbo.WaitEventsByDatabase (
        ServerID, DatabaseName, WaitType, CollectionTime,
        WaitingTasksCount, WaitTimeMs, MaxWaitTimeMs, SignalWaitTimeMs
    )
    SELECT
        @ServerID,
        ISNULL(DB_NAME(s.database_id), 'N/A') AS DatabaseName,
        w.wait_type,
        @CollectionTime,
        COUNT(*) AS WaitingTasksCount,
        SUM(w.wait_duration_ms) AS WaitTimeMs,
        MAX(w.wait_duration_ms) AS MaxWaitTimeMs,
        0 AS SignalWaitTimeMs -- Not available from dm_os_waiting_tasks
    FROM sys.dm_os_waiting_tasks w
    INNER JOIN sys.dm_exec_sessions s ON w.session_id = s.session_id
    WHERE w.wait_type NOT IN (
        'SLEEP_TASK', 'BROKER_EVENTHANDLER', 'SQLTRACE_BUFFER_FLUSH',
        'LAZYWRITER_SLEEP', 'XE_TIMER_EVENT', 'FT_IFTS_SCHEDULER_IDLE_WAIT',
        'LOGMGR_QUEUE', 'CHECKPOINT_QUEUE', 'REQUEST_FOR_DEADLOCK_SEARCH'
    )
    AND s.session_id > 50
    GROUP BY s.database_id, w.wait_type;

    PRINT 'Wait events by database collected for ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' wait types';
END;
GO

-- =====================================================
-- 5. usp_CollectAllDrillDownMetrics
-- Master procedure to collect all drill-down metrics
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectAllDrillDownMetrics', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectAllDrillDownMetrics;
GO

CREATE PROCEDURE dbo.usp_CollectAllDrillDownMetrics
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartTime DATETIME2 = GETUTCDATE();
    DECLARE @ErrorMessage NVARCHAR(4000);

    BEGIN TRY
        PRINT 'Starting drill-down metrics collection...';
        PRINT '';

        -- Collect all drill-down metrics
        EXEC dbo.usp_CollectDatabaseMetrics @ServerID;
        EXEC dbo.usp_CollectProcedureMetrics @ServerID;
        EXEC dbo.usp_CollectQueryMetrics @ServerID;
        EXEC dbo.usp_CollectWaitEventsByDatabase @ServerID;

        DECLARE @DurationMs INT;
        SET @DurationMs = DATEDIFF(MILLISECOND, @StartTime, GETUTCDATE());

        PRINT '';
        PRINT 'All drill-down metrics collected successfully for ServerID: ' + CAST(@ServerID AS VARCHAR(10));
        PRINT 'Collection completed in ' + CAST(@DurationMs AS VARCHAR(10)) + ' ms';
    END TRY
    BEGIN CATCH
        SET @ErrorMessage = 'Error collecting drill-down metrics: ' + ERROR_MESSAGE() + ' (Line ' + CAST(ERROR_LINE() AS VARCHAR(10)) + ')';
        PRINT @ErrorMessage;
        THROW;
    END CATCH;
END;
GO

-- =====================================================
-- 6. Helper Views for Grafana Queries
-- =====================================================

-- View: Top Databases by CPU
IF OBJECT_ID('dbo.vw_TopDatabasesByCPU', 'V') IS NOT NULL
    DROP VIEW dbo.vw_TopDatabasesByCPU;
GO

CREATE VIEW dbo.vw_TopDatabasesByCPU
AS
SELECT TOP 100
    s.ServerName,
    dm.DatabaseName,
    dm.CollectionTime,
    dm.MetricValue AS TotalCPUMs
FROM dbo.DatabaseMetrics dm
INNER JOIN dbo.Servers s ON dm.ServerID = s.ServerID
WHERE dm.MetricCategory = 'CPU'
  AND dm.MetricName = 'TotalCPUMs'
  AND dm.CollectionTime >= DATEADD(HOUR, -24, GETUTCDATE())
ORDER BY dm.MetricValue DESC;
GO

-- View: Top Procedures by CPU
IF OBJECT_ID('dbo.vw_TopProceduresByCPU', 'V') IS NOT NULL
    DROP VIEW dbo.vw_TopProceduresByCPU;
GO

CREATE VIEW dbo.vw_TopProceduresByCPU
AS
SELECT TOP 100
    s.ServerName,
    pm.DatabaseName,
    pm.SchemaName + '.' + pm.ProcedureName AS FullProcedureName,
    pm.CollectionTime,
    pm.ExecutionCount,
    pm.AvgCPUMs,
    pm.AvgDurationMs,
    pm.AvgLogicalReads
FROM dbo.ProcedureMetrics pm
INNER JOIN dbo.Servers s ON pm.ServerID = s.ServerID
WHERE pm.CollectionTime >= DATEADD(HOUR, -24, GETUTCDATE())
ORDER BY pm.AvgCPUMs DESC;
GO

-- View: Top Queries by CPU
IF OBJECT_ID('dbo.vw_TopQueriesByCPU', 'V') IS NOT NULL
    DROP VIEW dbo.vw_TopQueriesByCPU;
GO

CREATE VIEW dbo.vw_TopQueriesByCPU
AS
SELECT TOP 100
    s.ServerName,
    qm.DatabaseName,
    qm.QueryHash,
    qm.CollectionTime,
    qm.ExecutionCount,
    qm.AvgCPUMs,
    qm.MaxCPUMs,
    qm.AvgDurationMs,
    CAST(qm.QueryText AS NVARCHAR(500)) AS QueryTextPreview
FROM dbo.QueryMetrics qm
INNER JOIN dbo.Servers s ON qm.ServerID = s.ServerID
WHERE qm.CollectionTime >= DATEADD(HOUR, -24, GETUTCDATE())
ORDER BY qm.AvgCPUMs DESC;
GO

PRINT '';
PRINT '========================================================';
PRINT 'Drill-Down Collection Procedures Created Successfully';
PRINT '========================================================';
PRINT 'Procedures created:';
PRINT '  1. usp_CollectDatabaseMetrics - Metrics per database';
PRINT '  2. usp_CollectProcedureMetrics - Metrics per procedure';
PRINT '  3. usp_CollectQueryMetrics - Metrics per query';
PRINT '  4. usp_CollectWaitEventsByDatabase - Waits per database';
PRINT '  5. usp_CollectAllDrillDownMetrics - Master collector';
PRINT '';
PRINT 'Helper views created:';
PRINT '  1. vw_TopDatabasesByCPU';
PRINT '  2. vw_TopProceduresByCPU';
PRINT '  3. vw_TopQueriesByCPU';
PRINT '';
PRINT 'Usage: EXEC dbo.usp_CollectAllDrillDownMetrics @ServerID = 1;';
PRINT '========================================================';
GO
