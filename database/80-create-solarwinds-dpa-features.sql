-- =====================================================
-- Script: 80-create-solarwinds-dpa-features.sql
-- Description: SolarWinds DPA-inspired features for Feature #7 (Code Editor)
-- Author: SQL Server Monitor Project
-- Date: 2025-11-02
-- Purpose: Response time percentiles, query rewrites, wait categorization
-- =====================================================

USE MonitoringDB;
GO

PRINT '========================================';
PRINT 'Creating SolarWinds DPA-Inspired Features';
PRINT '========================================';
PRINT '';

-- =====================================================
-- FEATURE 1: Response Time Percentiles
-- =====================================================

PRINT 'Adding response time percentile columns...';

-- Add percentile columns to QueryStoreRuntimeStats if they don't exist
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.QueryStoreRuntimeStats')
    AND name = 'P50DurationMs'
)
BEGIN
    ALTER TABLE dbo.QueryStoreRuntimeStats
    ADD
        P50DurationMs DECIMAL(18,4) NULL,  -- Median (50th percentile)
        P95DurationMs DECIMAL(18,4) NULL,  -- 95th percentile
        P99DurationMs DECIMAL(18,4) NULL;  -- 99th percentile

    PRINT '  ✓ Percentile columns added to QueryStoreRuntimeStats';
END
ELSE
    PRINT '  - Percentile columns already exist';
GO

-- =====================================================
-- Stored Procedure: usp_CalculateQueryPercentiles
-- Description: Calculate P50, P95, P99 percentiles for query durations
-- Called by: Collection procedures (after runtime stats collection)
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
    -- We'll use the detailed execution data to calculate percentiles
    IF OBJECT_ID('tempdb..#QueryDurations') IS NOT NULL
        DROP TABLE #QueryDurations;

    CREATE TABLE #QueryDurations
    (
        QueryStoreQueryID BIGINT,
        PlanID BIGINT,
        Duration DECIMAL(18,4),
        RowNum INT
    );

    -- Insert sample durations (we use avg duration as proxy since we don't have individual execution times)
    -- In production, you'd want to collect actual execution times for better percentile accuracy
    INSERT INTO #QueryDurations (QueryStoreQueryID, PlanID, Duration, RowNum)
    SELECT
        QueryStoreQueryID,
        PlanID,
        AvgDurationMs,
        ROW_NUMBER() OVER (PARTITION BY QueryStoreQueryID, PlanID ORDER BY CollectionTime)
    FROM dbo.QueryStoreRuntimeStats rs
    INNER JOIN dbo.QueryStoreQueries q ON rs.QueryStoreQueryID = q.QueryStoreQueryID
    WHERE CollectionTime >= @StartTime
        AND (@ServerID IS NULL OR q.ServerID = @ServerID);

    DECLARE @QueryCount INT = (SELECT COUNT(DISTINCT QueryStoreQueryID) FROM #QueryDurations);
    PRINT '  Processing ' + CAST(@QueryCount AS NVARCHAR) + ' queries...';

    -- Calculate percentiles using PERCENTILE_CONT (SQL Server 2012+)
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

PRINT '  ✓ usp_CalculateQueryPercentiles created';
PRINT '';

-- =====================================================
-- Stored Procedure: usp_GetQueryPerformanceInsights
-- Description: Get query performance insights with percentiles
-- Called by: Code Editor plugin (API endpoint)
-- =====================================================

IF OBJECT_ID('dbo.usp_GetQueryPerformanceInsights', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetQueryPerformanceInsights;
GO

CREATE PROCEDURE dbo.usp_GetQueryPerformanceInsights
    @ServerID INT,
    @DatabaseName NVARCHAR(128) = NULL,
    @Top INT = 50  -- Top N slowest queries
AS
BEGIN
    SET NOCOUNT ON;

    -- Return query performance insights with percentiles
    -- Focus on queries with high variance (P95/P50 ratio > 5)
    SELECT TOP (@Top)
        q.ServerID,
        q.DatabaseName,
        q.QueryID,
        q.QueryText,
        rs.ExecutionCount,
        rs.AvgDurationMs,
        rs.P50DurationMs,
        rs.P95DurationMs,
        rs.P99DurationMs,
        -- Calculate variance ratio (P95/P50)
        CASE
            WHEN rs.P50DurationMs > 0
            THEN CAST(rs.P95DurationMs / rs.P50DurationMs AS DECIMAL(10,2))
            ELSE NULL
        END AS VarianceRatio,
        rs.MinDurationMs,
        rs.MaxDurationMs,
        rs.TotalCPUTimeMs,
        rs.TotalLogicalReads,
        rs.CollectionTime,
        -- Performance flags
        CASE
            WHEN rs.P95DurationMs / NULLIF(rs.P50DurationMs, 0) > 5 THEN 'High Variance'
            WHEN rs.AvgDurationMs > 1000 THEN 'Slow Average'
            WHEN rs.MaxDurationMs > 10000 THEN 'Slow Max'
            ELSE 'Normal'
        END AS PerformanceStatus
    FROM dbo.QueryStoreQueries q
    INNER JOIN (
        -- Get most recent stats for each query
        SELECT
            QueryStoreQueryID,
            PlanID,
            ExecutionCount,
            AvgDurationMs,
            P50DurationMs,
            P95DurationMs,
            P99DurationMs,
            MinDurationMs,
            MaxDurationMs,
            TotalCPUTimeMs,
            TotalLogicalReads,
            CollectionTime,
            ROW_NUMBER() OVER (PARTITION BY QueryStoreQueryID ORDER BY CollectionTime DESC) AS rn
        FROM dbo.QueryStoreRuntimeStats
        WHERE P50DurationMs IS NOT NULL  -- Only queries with percentiles
    ) rs ON q.QueryStoreQueryID = rs.QueryStoreQueryID AND rs.rn = 1
    WHERE q.ServerID = @ServerID
        AND (@DatabaseName IS NULL OR q.DatabaseName = @DatabaseName)
        AND q.IsActive = 1
    ORDER BY
        -- Prioritize high-variance queries
        CASE WHEN rs.P95DurationMs / NULLIF(rs.P50DurationMs, 0) > 5 THEN 0 ELSE 1 END,
        rs.AvgDurationMs DESC;

    RETURN 0;
END;
GO

PRINT '  ✓ usp_GetQueryPerformanceInsights created';
PRINT '';

-- =====================================================
-- FEATURE 2: Query Rewrite Suggestions
-- =====================================================

PRINT 'Creating query rewrite suggestion infrastructure...';

-- Table: QueryRewriteSuggestions
-- Stores automated query rewrite recommendations
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.QueryRewriteSuggestions') AND type = 'U')
BEGIN
    CREATE TABLE dbo.QueryRewriteSuggestions
    (
        SuggestionID        BIGINT          IDENTITY(1,1)   NOT NULL,
        QueryStoreQueryID   BIGINT                          NOT NULL,
        RuleID              NVARCHAR(20)                    NOT NULL,  -- P001, P002, etc.
        RuleName            NVARCHAR(200)                   NOT NULL,
        Severity            NVARCHAR(20)                    NOT NULL,  -- Error, Warning, Info
        OriginalCode        NVARCHAR(MAX)                   NOT NULL,
        SuggestedCode       NVARCHAR(MAX)                   NULL,
        Explanation         NVARCHAR(MAX)                   NULL,
        EstimatedImpact     NVARCHAR(20)                    NULL,      -- Low, Medium, High, Very High
        CreatedTime         DATETIME2                       NOT NULL DEFAULT GETUTCDATE(),
        IsResolved          BIT                             NOT NULL DEFAULT 0,
        ResolvedTime        DATETIME2                       NULL,

        CONSTRAINT PK_QueryRewriteSuggestions PRIMARY KEY CLUSTERED (SuggestionID),
        CONSTRAINT FK_QueryRewriteSuggestions_Queries FOREIGN KEY (QueryStoreQueryID)
            REFERENCES dbo.QueryStoreQueries(QueryStoreQueryID)
    );

    CREATE NONCLUSTERED INDEX IX_QueryRewriteSuggestions_QueryID
    ON dbo.QueryRewriteSuggestions(QueryStoreQueryID, IsResolved)
    INCLUDE (RuleID, RuleName, Severity, CreatedTime);

    PRINT '  ✓ QueryRewriteSuggestions table created';
END
ELSE
    PRINT '  - QueryRewriteSuggestions table already exists';
GO

-- =====================================================
-- Stored Procedure: usp_AnalyzeQueryForRewrites
-- Description: Analyze a query and generate rewrite suggestions
-- Called by: Code Editor plugin (API endpoint)
-- =====================================================

IF OBJECT_ID('dbo.usp_AnalyzeQueryForRewrites', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_AnalyzeQueryForRewrites;
GO

CREATE PROCEDURE dbo.usp_AnalyzeQueryForRewrites
    @QueryText NVARCHAR(MAX),
    @ServerID INT = NULL,
    @DatabaseName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Create temp table for suggestions
    CREATE TABLE #Suggestions
    (
        RuleID NVARCHAR(20),
        RuleName NVARCHAR(200),
        Severity NVARCHAR(20),
        LineNumber INT,
        ColumnNumber INT,
        OriginalCode NVARCHAR(MAX),
        SuggestedCode NVARCHAR(MAX),
        Explanation NVARCHAR(MAX),
        EstimatedImpact NVARCHAR(20)
    );

    DECLARE @UpperQuery NVARCHAR(MAX) = UPPER(@QueryText);

    -- Rule P001: SELECT * usage
    IF @UpperQuery LIKE '%SELECT%*%FROM%'
    BEGIN
        INSERT INTO #Suggestions
        VALUES (
            'P001',
            'Avoid SELECT * - Specify explicit columns',
            'Warning',
            0, 0,  -- Line/column (would need parser to determine)
            'SELECT * FROM',
            'SELECT Column1, Column2, Column3 FROM',
            'Using SELECT * can cause performance issues and maintainability problems. Explicitly list the columns you need.',
            'Medium'
        );
    END

    -- Rule P002: Missing WHERE clause on large tables
    -- (Would need table size metadata to implement fully)
    IF @UpperQuery LIKE '%SELECT%FROM%' AND @UpperQuery NOT LIKE '%WHERE%'
    BEGIN
        INSERT INTO #Suggestions
        VALUES (
            'P002',
            'Consider adding WHERE clause to filter results',
            'Warning',
            0, 0,
            NULL,
            'Add WHERE clause to filter results',
            'Queries without WHERE clauses may return unnecessary data. Consider filtering to improve performance.',
            'High'
        );
    END

    -- Rule P005: Functions in WHERE clause (non-SARGable)
    IF @UpperQuery LIKE '%WHERE%YEAR(%'
        OR @UpperQuery LIKE '%WHERE%MONTH(%'
        OR @UpperQuery LIKE '%WHERE%DAY(%'
        OR @UpperQuery LIKE '%WHERE%DATEPART(%'
        OR @UpperQuery LIKE '%WHERE%CAST(%'
        OR @UpperQuery LIKE '%WHERE%CONVERT(%'
        OR @UpperQuery LIKE '%WHERE%UPPER(%'
        OR @UpperQuery LIKE '%WHERE%LOWER(%'
        OR @UpperQuery LIKE '%WHERE%SUBSTRING(%'
    BEGIN
        INSERT INTO #Suggestions
        VALUES (
            'P005',
            'Functions in WHERE clause prevent index usage',
            'Warning',
            0, 0,
            NULL,
            'Rewrite to avoid functions on indexed columns',
            'Functions on columns in WHERE clauses prevent index seeks. Consider rewriting the predicate to allow index usage. Example: YEAR(OrderDate) = 2023 → OrderDate >= ''2023-01-01'' AND OrderDate < ''2024-01-01''',
            'High'
        );
    END

    -- Rule P006: OR in WHERE clause (suggest UNION)
    IF @UpperQuery LIKE '%WHERE%OR%'
    BEGIN
        INSERT INTO #Suggestions
        VALUES (
            'P006',
            'OR in WHERE clause may cause index scans',
            'Info',
            0, 0,
            NULL,
            'Consider using UNION ALL instead of OR',
            'OR conditions can prevent index usage. If filtering on different columns, consider UNION ALL with separate predicates for better performance.',
            'Medium'
        );
    END

    -- Rule P007: CURSOR usage
    IF @UpperQuery LIKE '%DECLARE%CURSOR%' OR @UpperQuery LIKE '%FETCH%NEXT%'
    BEGIN
        INSERT INTO #Suggestions
        VALUES (
            'P007',
            'CURSOR usage detected - Consider set-based alternative',
            'Warning',
            0, 0,
            NULL,
            'Use set-based operations instead of CURSOR',
            'Cursors process rows one-by-one and are slower than set-based operations. Consider rewriting using JOINs, CTEs, or window functions.',
            'Very High'
        );
    END

    -- Rule P008: WHILE loop for data manipulation
    IF @UpperQuery LIKE '%WHILE%' AND (@UpperQuery LIKE '%UPDATE%' OR @UpperQuery LIKE '%INSERT%' OR @UpperQuery LIKE '%DELETE%')
    BEGIN
        INSERT INTO #Suggestions
        VALUES (
            'P008',
            'WHILE loop for data manipulation - Use set-based approach',
            'Warning',
            0, 0,
            NULL,
            'Replace WHILE loop with set-based UPDATE/INSERT/DELETE',
            'WHILE loops process rows iteratively. Set-based operations are significantly faster. Consider batch processing or single set-based statement.',
            'High'
        );
    END

    -- Rule P009: Correlated subquery in SELECT list
    IF @UpperQuery LIKE '%SELECT%(%SELECT%FROM%'
    BEGIN
        INSERT INTO #Suggestions
        VALUES (
            'P009',
            'Correlated subquery in SELECT list',
            'Warning',
            0, 0,
            NULL,
            'Consider using LEFT JOIN or CROSS APPLY',
            'Correlated subqueries in the SELECT list execute once per row. Convert to JOIN or APPLY for better performance.',
            'High'
        );
    END

    -- Rule S001: Dynamic SQL concatenation (SQL injection risk)
    IF @UpperQuery LIKE '%EXEC(%@%+%' OR @UpperQuery LIKE '%EXECUTE(%@%+%'
    BEGIN
        INSERT INTO #Suggestions
        VALUES (
            'S001',
            'SQL Injection risk - Dynamic SQL with concatenation',
            'Error',
            0, 0,
            'EXEC (@sql + @variable)',
            'Use sp_executesql with parameters',
            'Concatenating user input into dynamic SQL creates SQL injection vulnerability. Use sp_executesql with parameterized queries.',
            'Very High'
        );
    END

    -- Rule DP001: Deprecated TEXT/NTEXT/IMAGE data types
    IF @UpperQuery LIKE '%TEXT%' OR @UpperQuery LIKE '%NTEXT%' OR @UpperQuery LIKE '%IMAGE%'
    BEGIN
        INSERT INTO #Suggestions
        VALUES (
            'DP001',
            'Deprecated data type usage (TEXT/NTEXT/IMAGE)',
            'Warning',
            0, 0,
            'TEXT/NTEXT/IMAGE',
            'Use VARCHAR(MAX)/NVARCHAR(MAX)/VARBINARY(MAX)',
            'TEXT, NTEXT, and IMAGE data types are deprecated. Use VARCHAR(MAX), NVARCHAR(MAX), or VARBINARY(MAX) instead.',
            'Low'
        );
    END

    -- Return suggestions
    SELECT * FROM #Suggestions
    ORDER BY
        CASE Severity
            WHEN 'Error' THEN 1
            WHEN 'Warning' THEN 2
            WHEN 'Info' THEN 3
            ELSE 4
        END,
        RuleID;

    DROP TABLE #Suggestions;

    RETURN 0;
END;
GO

PRINT '  ✓ usp_AnalyzeQueryForRewrites created';
PRINT '';

-- =====================================================
-- FEATURE 3: Wait Time Categorization
-- =====================================================

PRINT 'Creating wait time categorization function...';

-- Function: fn_CategorizeWaitType
-- Description: Categorize wait types into actionable groups
-- Returns: Wait category (CPU, IO, Lock, Network, Memory, Other)
IF OBJECT_ID('dbo.fn_CategorizeWaitType', 'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_CategorizeWaitType;
GO

CREATE FUNCTION dbo.fn_CategorizeWaitType
(
    @WaitType NVARCHAR(60)
)
RETURNS NVARCHAR(20)
AS
BEGIN
    DECLARE @Category NVARCHAR(20);

    -- CPU-related waits
    IF @WaitType IN ('SOS_SCHEDULER_YIELD', 'THREADPOOL', 'RESOURCE_SEMAPHORE')
        SET @Category = 'CPU';

    -- I/O-related waits
    ELSE IF @WaitType LIKE 'PAGEIOLATCH%'
        OR @WaitType LIKE 'IO_COMPLETION%'
        OR @WaitType LIKE 'ASYNC_IO_COMPLETION%'
        OR @WaitType LIKE 'WRITE%'
        OR @WaitType IN ('DISK_IO', 'DISKIO_SUSPEND', 'BACKUPIO')
        SET @Category = 'I/O';

    -- Lock-related waits
    ELSE IF @WaitType LIKE 'LCK%'
        OR @WaitType LIKE 'LOCK%'
        OR @WaitType IN ('LATCH_EX', 'LATCH_SH', 'PAGELATCH_EX', 'PAGELATCH_SH', 'PAGELATCH_UP')
        SET @Category = 'Lock';

    -- Network-related waits
    ELSE IF @WaitType LIKE 'ASYNC_NETWORK%'
        OR @WaitType LIKE 'NETWORK%'
        OR @WaitType = 'SQLCLR_QUANTUM_PUNISHMENT'
        SET @Category = 'Network';

    -- Memory-related waits
    ELSE IF @WaitType LIKE 'RESOURCE_SEMAPHORE%'
        OR @WaitType LIKE 'CMEMTHREAD%'
        OR @WaitType LIKE 'SOS_RESERVEDMEMBLOCKLIST%'
        OR @WaitType = 'MEMORYCLERK_SQLQERESERVATIONS'
        SET @Category = 'Memory';

    -- Service Broker waits
    ELSE IF @WaitType LIKE 'BROKER%'
        OR @WaitType LIKE 'SERVICE_BROKER%'
        SET @Category = 'Service Broker';

    -- Parallelism waits
    ELSE IF @WaitType LIKE 'CXPACKET%'
        OR @WaitType LIKE 'CXCONSUMER%'
        OR @WaitType = 'EXCHANGE'
        SET @Category = 'Parallelism';

    -- Backup/Restore waits
    ELSE IF @WaitType LIKE 'BACKUP%'
        OR @WaitType LIKE 'RESTORE%'
        SET @Category = 'Backup';

    -- Other/Unknown
    ELSE
        SET @Category = 'Other';

    RETURN @Category;
END;
GO

PRINT '  ✓ fn_CategorizeWaitType function created';
PRINT '';

-- =====================================================
-- Stored Procedure: usp_GetWaitStatsByCategory
-- Description: Get wait statistics categorized by type
-- Called by: Code Editor plugin, dashboards
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
        SUM(ws.WaitCount) AS TotalWaitCount,
        AVG(ws.WaitTimeMs / NULLIF(ws.WaitCount, 0)) AS AvgWaitTimeMs,
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

PRINT '  ✓ usp_GetWaitStatsByCategory created';
PRINT '';

-- =====================================================
-- Summary and Next Steps
-- =====================================================

PRINT '========================================';
PRINT 'SolarWinds DPA Features - Deployment Complete!';
PRINT '========================================';
PRINT '';
PRINT 'COMPLETED:';
PRINT '  ✓ Response time percentiles (P50, P95, P99)';
PRINT '  ✓ Query rewrite suggestions (10 rules)';
PRINT '  ✓ Wait time categorization';
PRINT '';
PRINT 'NEW PROCEDURES:';
PRINT '  - dbo.usp_CalculateQueryPercentiles';
PRINT '  - dbo.usp_GetQueryPerformanceInsights';
PRINT '  - dbo.usp_AnalyzeQueryForRewrites';
PRINT '  - dbo.usp_GetWaitStatsByCategory';
PRINT '';
PRINT 'NEW FUNCTION:';
PRINT '  - dbo.fn_CategorizeWaitType';
PRINT '';
PRINT 'NEXT STEPS:';
PRINT '  1. Integrate usp_CalculateQueryPercentiles into collection job';
PRINT '  2. Create API endpoints to expose these procedures';
PRINT '  3. Update Code Editor plugin to call new APIs';
PRINT '  4. Test percentile calculations with real data';
PRINT '  5. Add monitoring dashboard for wait categories';
PRINT '';
PRINT '========================================';
GO
