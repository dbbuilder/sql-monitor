-- =====================================================
-- Script: 11-create-extended-events-procedures.sql
-- Description: Collection procedures for Extended Events, Query Store, Index Analysis
-- Author: SQL Server Monitor Project
-- Date: 2025-10-25
-- =====================================================

USE MonitoringDB;
GO

-- =====================================================
-- 1. usp_CollectBlockingEvents
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectBlockingEvents', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectBlockingEvents;
GO

CREATE PROCEDURE dbo.usp_CollectBlockingEvents
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CollectionTime DATETIME2 = GETUTCDATE();

    -- Capture current blocking chains
    INSERT INTO dbo.BlockingEvents (
        ServerID, EventTime, DatabaseName,
        BlockedSessionID, BlockingSessionID,
        WaitType, WaitDurationMs,
        BlockedQuery, BlockingQuery,
        BlockedObjectName, BlockingObjectName
    )
    SELECT
        @ServerID,
        @CollectionTime,
        DB_NAME(blocked.database_id),
        blocked.session_id AS BlockedSessionID,
        blocking.session_id AS BlockingSessionID,
        wait.wait_type,
        wait.wait_duration_ms,
        blocked_sql.text AS BlockedQuery,
        blocking_sql.text AS BlockingQuery,
        OBJECT_SCHEMA_NAME(blocked_req.statement_end_offset, blocked.database_id) + '.' +
        OBJECT_NAME(blocked_req.statement_end_offset, blocked.database_id) AS BlockedObjectName,
        OBJECT_SCHEMA_NAME(blocking_req.statement_end_offset, blocking.database_id) + '.' +
        OBJECT_NAME(blocking_req.statement_end_offset, blocking.database_id) AS BlockingObjectName
    FROM sys.dm_exec_sessions blocked
    INNER JOIN sys.dm_exec_requests blocked_req ON blocked.session_id = blocked_req.session_id
    INNER JOIN sys.dm_os_waiting_tasks wait ON blocked_req.session_id = wait.session_id
    INNER JOIN sys.dm_exec_sessions blocking ON wait.blocking_session_id = blocking.session_id
    LEFT JOIN sys.dm_exec_requests blocking_req ON blocking.session_id = blocking_req.session_id
    CROSS APPLY sys.dm_exec_sql_text(blocked_req.sql_handle) blocked_sql
    OUTER APPLY sys.dm_exec_sql_text(blocking_req.sql_handle) blocking_sql
    WHERE wait.wait_duration_ms > 5000 -- Only capture waits > 5 seconds
      AND blocked.session_id > 50;

    PRINT 'Blocking events captured: ' + CAST(@@ROWCOUNT AS VARCHAR(10));
END;
GO

-- =====================================================
-- 2. usp_CollectLongRunningQueries
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectLongRunningQueries', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectLongRunningQueries;
GO

CREATE PROCEDURE dbo.usp_CollectLongRunningQueries
    @ServerID INT,
    @ThresholdSeconds INT = 30
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CollectionTime DATETIME2 = GETUTCDATE();
    DECLARE @ThresholdMs INT;
    SET @ThresholdMs = @ThresholdSeconds * 1000;

    -- Capture queries running longer than threshold
    INSERT INTO dbo.LongRunningQueries (
        ServerID, EventTime, DatabaseName, SessionID,
        QueryText, DurationMs, CPUMs, LogicalReads, PhysicalReads, WaitType
    )
    SELECT
        @ServerID,
        @CollectionTime,
        DB_NAME(req.database_id),
        req.session_id,
        SUBSTRING(sql.text, (req.statement_start_offset/2)+1,
            ((CASE req.statement_end_offset
                WHEN -1 THEN DATALENGTH(sql.text)
                ELSE req.statement_end_offset
            END - req.statement_start_offset)/2) + 1) AS QueryText,
        DATEDIFF(MILLISECOND, req.start_time, GETUTCDATE()) AS DurationMs,
        req.cpu_time AS CPUMs,
        req.logical_reads AS LogicalReads,
        req.reads AS PhysicalReads,
        req.wait_type
    FROM sys.dm_exec_requests req
    CROSS APPLY sys.dm_exec_sql_text(req.sql_handle) sql
    WHERE DATEDIFF(MILLISECOND, req.start_time, GETUTCDATE()) > @ThresholdMs
      AND req.session_id > 50
      AND req.session_id <> @@SPID;

    PRINT 'Long-running queries captured: ' + CAST(@@ROWCOUNT AS VARCHAR(10));
END;
GO

-- =====================================================
-- 3. usp_CollectQueryStoreData
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectQueryStoreData', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectQueryStoreData;
GO

CREATE PROCEDURE dbo.usp_CollectQueryStoreData
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CollectionTime DATETIME2 = GETUTCDATE();
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @DatabaseName NVARCHAR(128);

    -- Cursor through databases with Query Store enabled
    DECLARE db_cursor CURSOR FOR
    SELECT name
    FROM sys.databases
    WHERE is_query_store_on = 1
      AND database_id > 4
      AND state = 0; -- Online only

    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @DatabaseName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @SQL = N'
        USE [' + @DatabaseName + N'];

        INSERT INTO MonitoringDB.dbo.QueryStoreData (
            ServerID, CollectionTime, DatabaseName, QueryID, QueryHash,
            QueryText, ObjectName, ExecutionCount,
            AvgDurationMs, LastDurationMs, MinDurationMs, MaxDurationMs,
            AvgCPUMs, AvgLogicalReads, PlanRegression
        )
        SELECT TOP 100
            @ServerID,
            @CollectionTime,
            @DatabaseName,
            q.query_id,
            q.query_hash,
            qt.query_sql_text,
            OBJECT_SCHEMA_NAME(q.object_id) + ''.'' + OBJECT_NAME(q.object_id) AS ObjectName,
            SUM(rs.count_executions) AS ExecutionCount,
            AVG(rs.avg_duration) / 1000.0 AS AvgDurationMs,
            MAX(rs.last_duration) / 1000.0 AS LastDurationMs,
            MIN(rs.min_duration) / 1000.0 AS MinDurationMs,
            MAX(rs.max_duration) / 1000.0 AS MaxDurationMs,
            AVG(rs.avg_cpu_time) / 1000.0 AS AvgCPUMs,
            AVG(rs.avg_logical_io_reads) AS AvgLogicalReads,
            CASE
                WHEN MAX(rs.last_duration) > AVG(rs.avg_duration) * 2 THEN 1
                ELSE 0
            END AS PlanRegression
        FROM sys.query_store_query q
        INNER JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
        INNER JOIN sys.query_store_plan p ON q.query_id = p.query_id
        INNER JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
        WHERE rs.last_execution_time >= DATEADD(HOUR, -1, GETUTCDATE())
        GROUP BY q.query_id, q.query_hash, qt.query_sql_text, q.object_id
        ORDER BY AVG(rs.avg_duration) DESC;
        ';

        EXEC sp_executesql @SQL,
            N'@ServerID INT, @CollectionTime DATETIME2, @DatabaseName NVARCHAR(128)',
            @ServerID, @CollectionTime, @DatabaseName;

        FETCH NEXT FROM db_cursor INTO @DatabaseName;
    END;

    CLOSE db_cursor;
    DEALLOCATE db_cursor;

    PRINT 'Query Store data collected';
END;
GO

-- =====================================================
-- 4. usp_CollectIndexAnalysis
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectIndexAnalysis', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectIndexAnalysis;
GO

CREATE PROCEDURE dbo.usp_CollectIndexAnalysis
    @ServerID INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CollectionTime DATETIME2 = GETUTCDATE();
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @DatabaseName NVARCHAR(128);

    -- Cursor through user databases
    DECLARE db_cursor CURSOR FOR
    SELECT name
    FROM sys.databases
    WHERE database_id > 4
      AND state = 0; -- Online only

    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @DatabaseName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Collect missing indexes
        SET @SQL = N'
        USE [' + @DatabaseName + N'];

        INSERT INTO MonitoringDB.dbo.IndexAnalysis (
            ServerID, CollectionTime, DatabaseName, SchemaName, TableName,
            IndexName, AnalysisType, ImprovementMeasure,
            EqualityColumns, InequalityColumns, IncludeColumns, Recommendation
        )
        SELECT TOP 50
            @ServerID,
            @CollectionTime,
            @DatabaseName,
            OBJECT_SCHEMA_NAME(mid.object_id),
            OBJECT_NAME(mid.object_id),
            NULL,
            ''Missing'',
            (migs.avg_total_user_cost * migs.avg_user_impact * (migs.user_seeks + migs.user_scans)) AS ImprovementMeasure,
            mid.equality_columns,
            mid.inequality_columns,
            mid.included_columns,
            ''CREATE NONCLUSTERED INDEX IX_'' + OBJECT_NAME(mid.object_id) + ''_Missing ON '' +
            OBJECT_SCHEMA_NAME(mid.object_id) + ''.'' + OBJECT_NAME(mid.object_id) +
            '' ('' + ISNULL(mid.equality_columns, '''') +
            CASE WHEN mid.inequality_columns IS NOT NULL THEN '', '' + mid.inequality_columns ELSE '''' END + '')'' +
            CASE WHEN mid.included_columns IS NOT NULL THEN '' INCLUDE ('' + mid.included_columns + '')'' ELSE '''' END
        FROM sys.dm_db_missing_index_details mid
        INNER JOIN sys.dm_db_missing_index_groups mig ON mid.index_handle = mig.index_handle
        INNER JOIN sys.dm_db_missing_index_group_stats migs ON mig.index_group_handle = migs.group_handle
        WHERE mid.database_id = DB_ID()
        ORDER BY ImprovementMeasure DESC;

        -- Collect fragmented indexes
        INSERT INTO MonitoringDB.dbo.IndexAnalysis (
            ServerID, CollectionTime, DatabaseName, SchemaName, TableName,
            IndexName, AnalysisType, FragmentationPercent, PageCount,
            AvgFragmentationPercent, Recommendation
        )
        SELECT
            @ServerID,
            @CollectionTime,
            @DatabaseName,
            OBJECT_SCHEMA_NAME(ips.object_id),
            OBJECT_NAME(ips.object_id),
            i.name,
            ''Fragmented'',
            ips.avg_fragmentation_in_percent,
            ips.page_count,
            ips.avg_fragmentation_in_percent,
            CASE
                WHEN ips.avg_fragmentation_in_percent > 30 AND ips.page_count > 1000
                    THEN ''ALTER INDEX ['' + i.name + ''] ON ['' + OBJECT_SCHEMA_NAME(ips.object_id) + ''].['' + OBJECT_NAME(ips.object_id) + ''] REBUILD''
                WHEN ips.avg_fragmentation_in_percent > 10 AND ips.page_count > 1000
                    THEN ''ALTER INDEX ['' + i.name + ''] ON ['' + OBJECT_SCHEMA_NAME(ips.object_id) + ''].['' + OBJECT_NAME(ips.object_id) + ''] REORGANIZE''
                ELSE ''No action needed''
            END
        FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, ''LIMITED'') ips
        INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
        WHERE ips.avg_fragmentation_in_percent > 10
          AND ips.page_count > 1000
          AND i.name IS NOT NULL;
        ';

        EXEC sp_executesql @SQL,
            N'@ServerID INT, @CollectionTime DATETIME2, @DatabaseName NVARCHAR(128)',
            @ServerID, @CollectionTime, @DatabaseName;

        FETCH NEXT FROM db_cursor INTO @DatabaseName;
    END;

    CLOSE db_cursor;
    DEALLOCATE db_cursor;

    PRINT 'Index analysis completed';
END;
GO

-- =====================================================
-- 5. usp_CacheObjectCode
-- =====================================================

IF OBJECT_ID('dbo.usp_CacheObjectCode', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CacheObjectCode;
GO

CREATE PROCEDURE dbo.usp_CacheObjectCode
    @ServerID INT,
    @DatabaseName NVARCHAR(128),
    @SchemaName NVARCHAR(128),
    @ObjectName NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @Definition NVARCHAR(MAX);
    DECLARE @ObjectType VARCHAR(20);

    -- Get object definition
    SET @SQL = N'
    USE [' + @DatabaseName + N'];

    SELECT
        @Definition = OBJECT_DEFINITION(OBJECT_ID(@SchemaName + ''.'' + @ObjectName)),
        @ObjectType = CASE o.type
            WHEN ''P'' THEN ''Procedure''
            WHEN ''FN'' THEN ''Function''
            WHEN ''IF'' THEN ''Function''
            WHEN ''TF'' THEN ''Function''
            WHEN ''V'' THEN ''View''
            WHEN ''TR'' THEN ''Trigger''
            ELSE ''Unknown''
        END
    FROM sys.objects o
    WHERE o.object_id = OBJECT_ID(@SchemaName + ''.'' + @ObjectName);
    ';

    EXEC sp_executesql @SQL,
        N'@SchemaName NVARCHAR(128), @ObjectName NVARCHAR(128), @Definition NVARCHAR(MAX) OUTPUT, @ObjectType VARCHAR(20) OUTPUT',
        @SchemaName, @ObjectName, @Definition OUTPUT, @ObjectType OUTPUT;

    -- Update or insert into cache
    IF EXISTS (
        SELECT 1 FROM dbo.ObjectCode
        WHERE ServerID = @ServerID
          AND DatabaseName = @DatabaseName
          AND SchemaName = @SchemaName
          AND ObjectName = @ObjectName
    )
    BEGIN
        UPDATE dbo.ObjectCode
        SET Definition = @Definition,
            ObjectType = @ObjectType,
            LastUpdated = GETUTCDATE()
        WHERE ServerID = @ServerID
          AND DatabaseName = @DatabaseName
          AND SchemaName = @SchemaName
          AND ObjectName = @ObjectName;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.ObjectCode (ServerID, DatabaseName, SchemaName, ObjectName, ObjectType, Definition, LastUpdated)
        VALUES (@ServerID, @DatabaseName, @SchemaName, @ObjectName, @ObjectType, @Definition, GETUTCDATE());
    END;

    PRINT 'Object code cached: ' + @SchemaName + '.' + @ObjectName;
END;
GO

-- =====================================================
-- 6. usp_GetObjectCode
-- =====================================================

IF OBJECT_ID('dbo.usp_GetObjectCode', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetObjectCode;
GO

CREATE PROCEDURE dbo.usp_GetObjectCode
    @ServerID INT,
    @DatabaseName NVARCHAR(128),
    @SchemaName NVARCHAR(128),
    @ObjectName NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    -- Try to get from cache
    SELECT
        Definition,
        ObjectType,
        LastUpdated
    FROM dbo.ObjectCode
    WHERE ServerID = @ServerID
      AND DatabaseName = @DatabaseName
      AND SchemaName = @SchemaName
      AND ObjectName = @ObjectName;

    -- If not found, cache it and return
    IF @@ROWCOUNT = 0
    BEGIN
        EXEC dbo.usp_CacheObjectCode @ServerID, @DatabaseName, @SchemaName, @ObjectName;

        SELECT
            Definition,
            ObjectType,
            LastUpdated
        FROM dbo.ObjectCode
        WHERE ServerID = @ServerID
          AND DatabaseName = @DatabaseName
          AND SchemaName = @SchemaName
          AND ObjectName = @ObjectName;
    END;
END;
GO

-- =====================================================
-- 7. usp_CollectAllAdvancedMetrics
-- =====================================================

IF OBJECT_ID('dbo.usp_CollectAllAdvancedMetrics', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CollectAllAdvancedMetrics;
GO

CREATE PROCEDURE dbo.usp_CollectAllAdvancedMetrics
    @ServerID INT,
    @VerboseOutput BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartTime DATETIME2 = GETUTCDATE();
    DECLARE @Duration INT;

    IF @VerboseOutput = 1
    BEGIN
        PRINT '';
        PRINT 'Advanced Metrics Collection Starting...';
        PRINT '';
    END;

    -- Blocking events
    BEGIN TRY
        EXEC dbo.usp_CollectBlockingEvents @ServerID;
    END TRY
    BEGIN CATCH
        IF @VerboseOutput = 1 PRINT '  [ERROR] Blocking events: ' + ERROR_MESSAGE();
    END CATCH;

    -- Long-running queries
    BEGIN TRY
        EXEC dbo.usp_CollectLongRunningQueries @ServerID, @ThresholdSeconds = 30;
    END TRY
    BEGIN CATCH
        IF @VerboseOutput = 1 PRINT '  [ERROR] Long queries: ' + ERROR_MESSAGE();
    END CATCH;

    -- Query Store
    BEGIN TRY
        EXEC dbo.usp_CollectQueryStoreData @ServerID;
    END TRY
    BEGIN CATCH
        IF @VerboseOutput = 1 PRINT '  [ERROR] Query Store: ' + ERROR_MESSAGE();
    END CATCH;

    -- Index analysis
    BEGIN TRY
        EXEC dbo.usp_CollectIndexAnalysis @ServerID;
    END TRY
    BEGIN CATCH
        IF @VerboseOutput = 1 PRINT '  [ERROR] Index analysis: ' + ERROR_MESSAGE();
    END CATCH;

    SET @Duration = DATEDIFF(MILLISECOND, @StartTime, GETUTCDATE());

    IF @VerboseOutput = 1
    BEGIN
        PRINT '';
        PRINT 'Advanced metrics collection completed in ' + CAST(@Duration AS VARCHAR(10)) + ' ms';
    END;
END;
GO

PRINT '';
PRINT '========================================================';
PRINT 'Extended Events Procedures Created Successfully';
PRINT '========================================================';
PRINT 'Procedures:';
PRINT '  1. usp_CollectBlockingEvents - Capture blocking chains';
PRINT '  2. usp_CollectLongRunningQueries - Long query capture';
PRINT '  3. usp_CollectQueryStoreData - Query Store analysis';
PRINT '  4. usp_CollectIndexAnalysis - Missing/fragmented indexes';
PRINT '  5. usp_CacheObjectCode - Cache object definitions';
PRINT '  6. usp_GetObjectCode - Retrieve object code';
PRINT '  7. usp_CollectAllAdvancedMetrics - Master collector';
PRINT '========================================================';
GO
