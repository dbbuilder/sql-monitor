-- =====================================================================================
-- SQL Monitor Agent - Procedure Timeout Diagnostic Query
-- Purpose: Identify stored procedures that may be at risk of hitting client timeout
-- =====================================================================================
--
-- FIXED BUG: Original query compared DMV microseconds directly to millisecond threshold
-- This fix properly converts sys.dm_exec_query_stats values (microseconds) to milliseconds
--
-- Usage:
--   1. Adjust @TimeoutMs to match your application's command timeout setting
--   2. Adjust @TodayStart to widen/narrow the time window as needed
--   3. Run on any monitored SQL Server instance
--
-- Author: SQL Monitor Team
-- Date: 2025-10-29
-- =====================================================================================

USE DBATools  -- Or run on any database where DBA procedures exist
GO

SET NOCOUNT ON
GO

-- =====================================================================================
-- Configuration
-- =====================================================================================

DECLARE @TodayStart DATETIME = CONVERT(DATE, GETDATE())  -- Start of today
DECLARE @TimeoutMs INT = 30000  -- 30 seconds threshold in milliseconds

PRINT ''
PRINT '=========================================='
PRINT 'Procedure Timeout Risk Analysis'
PRINT '=========================================='
PRINT '  Threshold: ' + CAST(@TimeoutMs/1000 AS VARCHAR) + ' seconds (' + CAST(@TimeoutMs AS VARCHAR) + ' ms)'
PRINT '  Time Window: Since ' + CONVERT(VARCHAR(30), @TodayStart, 120)
PRINT ''

-- =====================================================================================
-- Query: Procedures Exceeding Timeout Threshold
-- =====================================================================================

;WITH ProcExecs AS
(
    SELECT
        DB_NAME(st.dbid) AS DatabaseName,
        OBJECT_NAME(st.objectid, st.dbid) AS ProcName,
        qs.last_execution_time,

        -- FIXED: Convert microseconds to milliseconds
        -- sys.dm_exec_query_stats returns elapsed times in MICROSECONDS
        -- We divide by 1000.0 to convert to milliseconds before comparison
        (qs.total_elapsed_time / qs.execution_count) / 1000.0 AS AvgElapsedMs,
        qs.max_elapsed_time / 1000.0 AS MaxElapsedMs,  -- Convert μs to ms
        qs.min_elapsed_time / 1000.0 AS MinElapsedMs,  -- Convert μs to ms
        qs.execution_count

    FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
    WHERE st.dbid IS NOT NULL
      AND OBJECTPROPERTY(st.objectid, 'IsProcedure') = 1
)
SELECT
    DatabaseName,
    ProcName,
    last_execution_time AS LastExecutionTime,
    CAST(AvgElapsedMs AS DECIMAL(10,2)) AS AvgElapsedMs,
    CAST(MaxElapsedMs AS DECIMAL(10,2)) AS MaxElapsedMs,
    CAST(MinElapsedMs AS DECIMAL(10,2)) AS MinElapsedMs,
    execution_count AS ExecutionCountRecently,
    CASE
        WHEN MaxElapsedMs >= @TimeoutMs
            THEN 'Likely Timeout Risk (exceeded ' + CAST(@TimeoutMs/1000 AS VARCHAR) + 's threshold)'
        WHEN MaxElapsedMs >= (@TimeoutMs * 0.75)
            THEN 'Warning (75% of threshold)'
        ELSE 'Below Threshold'
    END AS TimeoutRiskFlag
FROM ProcExecs
WHERE last_execution_time >= @TodayStart
  AND MaxElapsedMs >= (@TimeoutMs * 0.5)  -- Show procedures at 50%+ of threshold
ORDER BY MaxElapsedMs DESC, last_execution_time DESC

PRINT ''
PRINT '=========================================='
PRINT 'Summary Statistics'
PRINT '=========================================='

-- =====================================================================================
-- Summary: Aggregate statistics
-- =====================================================================================

SELECT
    'Procedures over ' + CAST(@TimeoutMs/1000 AS VARCHAR) + ' seconds' AS Category,
    COUNT(*) AS ProcedureCount,
    CAST(MAX(MaxElapsedMs/1000.0) AS DECIMAL(10,2)) AS MaxSeconds,
    CAST(AVG(MaxElapsedMs/1000.0) AS DECIMAL(10,2)) AS AvgMaxSeconds
FROM ProcExecs
WHERE MaxElapsedMs >= @TimeoutMs

UNION ALL

SELECT
    'Procedures 50-100% of threshold' AS Category,
    COUNT(*) AS ProcedureCount,
    CAST(MAX(MaxElapsedMs/1000.0) AS DECIMAL(10,2)) AS MaxSeconds,
    CAST(AVG(MaxElapsedMs/1000.0) AS DECIMAL(10,2)) AS AvgMaxSeconds
FROM ProcExecs
WHERE MaxElapsedMs >= (@TimeoutMs * 0.5) AND MaxElapsedMs < @TimeoutMs

UNION ALL

SELECT
    'Total procedures analyzed' AS Category,
    COUNT(*) AS ProcedureCount,
    CAST(MAX(MaxElapsedMs/1000.0) AS DECIMAL(10,2)) AS MaxSeconds,
    CAST(AVG(MaxElapsedMs/1000.0) AS DECIMAL(10,2)) AS AvgMaxSeconds
FROM ProcExecs

PRINT ''
PRINT '=========================================='
PRINT 'Analysis Complete'
PRINT '=========================================='
PRINT ''
PRINT 'NOTE: This query analyzes cached execution plans in sys.dm_exec_query_stats.'
PRINT 'Results represent procedures executed since last SQL Server restart or plan eviction.'
PRINT ''
GO

-- =====================================================================================
-- Additional Diagnostic: Top 10 Slowest Procedures (Regardless of Threshold)
-- =====================================================================================

PRINT ''
PRINT '=========================================='
PRINT 'Top 10 Slowest Procedures (By Max Execution Time)'
PRINT '=========================================='
PRINT ''

SELECT TOP 10
    DB_NAME(st.dbid) AS DatabaseName,
    OBJECT_NAME(st.objectid, st.dbid) AS ProcName,
    CAST((qs.max_elapsed_time / 1000.0) AS DECIMAL(10,2)) AS MaxElapsedMs,
    CAST((qs.total_elapsed_time / qs.execution_count / 1000.0) AS DECIMAL(10,2)) AS AvgElapsedMs,
    qs.execution_count AS ExecutionCount,
    qs.last_execution_time AS LastExecution
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE st.dbid IS NOT NULL
  AND OBJECTPROPERTY(st.objectid, 'IsProcedure') = 1
ORDER BY qs.max_elapsed_time DESC

GO

PRINT ''
PRINT 'Diagnostic query complete.'
PRINT ''
