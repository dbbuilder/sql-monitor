USE [DBATools]
GO

-- =============================================
-- P1 HIGH PRIORITY - Modular Collectors
-- =============================================

-- =============================================
-- P1.6: Collect Index Usage Statistics
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P1_IndexUsage
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @ProcName SYSNAME = 'DBA_Collect_P1_IndexUsage'
    DECLARE @RowCount INT

    BEGIN TRY
        INSERT dbo.PerfSnapshotIndexUsage
        (
            PerfSnapshotRunID, DatabaseID, DatabaseName, ObjectID, ObjectName,
            IndexID, IndexName, UserSeeks, UserScans, UserLookups, UserUpdates,
            LastSeek, LastScan, LastLookup, LastUpdate
        )
        SELECT
            @PerfSnapshotRunID,
            ius.database_id,
            DB_NAME(ius.database_id),
            ius.object_id,
            OBJECT_SCHEMA_NAME(ius.object_id, ius.database_id) + '.' +
                OBJECT_NAME(ius.object_id, ius.database_id) AS ObjectName,
            ius.index_id,
            i.name AS IndexName,
            ius.user_seeks,
            ius.user_scans,
            ius.user_lookups,
            ius.user_updates,
            ius.last_user_seek,
            ius.last_user_scan,
            ius.last_user_lookup,
            ius.last_user_update
        FROM sys.dm_db_index_usage_stats ius
        INNER JOIN sys.indexes i
            ON ius.object_id = i.object_id
            AND ius.index_id = i.index_id
            AND ius.database_id = DB_ID()
        WHERE OBJECTPROPERTY(ius.object_id, 'IsUserTable') = 1

        SET @RowCount = @@ROWCOUNT

        IF @Debug = 1
        BEGIN
            EXEC dbo.DBA_LogEntry_Insert
                @ProcedureName = @ProcName,
                @ProcedureSection = 'COMPLETE',
                @IsError = 0,
                @ErrDescription = 'Index usage stats collected',
                @AdditionalInfo = 'Rows=' + CAST(@RowCount AS VARCHAR(20))
        END

        RETURN 0
    END TRY
    BEGIN CATCH
        EXEC dbo.DBA_LogEntry_Insert
            @ProcedureName = @ProcName,
            @ProcedureSection = 'ERROR',
            @IsError = 1,
            @ErrDescription = ERROR_MESSAGE(),
            @ErrNumber = ERROR_NUMBER(),
            @ErrSeverity = ERROR_SEVERITY(),
            @ErrState = ERROR_STATE(),
            @ErrLine = ERROR_LINE()

        RETURN -1
    END CATCH
END
GO

-- =============================================
-- P1.7: Collect Missing Index Recommendations
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P1_MissingIndexes
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @ProcName SYSNAME = 'DBA_Collect_P1_MissingIndexes'
    DECLARE @RowCount INT

    BEGIN TRY
        INSERT dbo.PerfSnapshotMissingIndexes
        (
            PerfSnapshotRunID, DatabaseID, DatabaseName, ObjectID, ObjectName,
            EqualityColumns, InequalityColumns, IncludedColumns,
            UserSeeks, UserScans, AvgTotalUserCost, AvgUserImpact,
            LastUserSeek, LastUserScan, ImpactScore
        )
        SELECT TOP 100
            @PerfSnapshotRunID,
            mid.database_id,
            DB_NAME(mid.database_id),
            mid.object_id,
            OBJECT_SCHEMA_NAME(mid.object_id, mid.database_id) + '.' +
                OBJECT_NAME(mid.object_id, mid.database_id) AS ObjectName,
            mid.equality_columns,
            mid.inequality_columns,
            mid.included_columns,
            migs.user_seeks,
            migs.user_scans,
            migs.avg_total_user_cost,
            migs.avg_user_impact,
            migs.last_user_seek,
            migs.last_user_scan,
            (migs.user_seeks + migs.user_scans) * migs.avg_total_user_cost * migs.avg_user_impact AS ImpactScore
        FROM sys.dm_db_missing_index_details mid
        INNER JOIN sys.dm_db_missing_index_groups mig
            ON mid.index_handle = mig.index_handle
        INNER JOIN sys.dm_db_missing_index_group_stats migs
            ON mig.index_group_handle = migs.group_handle
        WHERE mid.database_id > 4  -- Exclude system databases
        ORDER BY ImpactScore DESC

        SET @RowCount = @@ROWCOUNT

        IF @Debug = 1
        BEGIN
            EXEC dbo.DBA_LogEntry_Insert
                @ProcedureName = @ProcName,
                @ProcedureSection = 'COMPLETE',
                @IsError = 0,
                @ErrDescription = 'Missing index recommendations collected',
                @AdditionalInfo = 'Rows=' + CAST(@RowCount AS VARCHAR(20))
        END

        RETURN 0
    END TRY
    BEGIN CATCH
        EXEC dbo.DBA_LogEntry_Insert
            @ProcedureName = @ProcName,
            @ProcedureSection = 'ERROR',
            @IsError = 1,
            @ErrDescription = ERROR_MESSAGE(),
            @ErrNumber = ERROR_NUMBER(),
            @ErrSeverity = ERROR_SEVERITY(),
            @ErrState = ERROR_STATE(),
            @ErrLine = ERROR_LINE()

        RETURN -1
    END CATCH
END
GO

-- =============================================
-- P1.8: Collect Detailed Wait Statistics
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P1_WaitStats
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @ProcName SYSNAME = 'DBA_Collect_P1_WaitStats'
    DECLARE @RowCount INT

    BEGIN TRY
        INSERT dbo.PerfSnapshotWaitStats
        (
            PerfSnapshotRunID, WaitType, WaitingTasksCount, WaitTimeMs,
            SignalWaitTimeMs, ResourceWaitTimeMs, MaxWaitTimeMs, AvgWaitTimeMs
        )
        SELECT TOP 100
            @PerfSnapshotRunID,
            wait_type,
            waiting_tasks_count,
            wait_time_ms,
            signal_wait_time_ms,
            wait_time_ms - signal_wait_time_ms AS ResourceWaitTimeMs,
            max_wait_time_ms,
            CASE WHEN waiting_tasks_count = 0 THEN 0
                 ELSE wait_time_ms / NULLIF(waiting_tasks_count, 0)
            END AS AvgWaitTimeMs
        FROM sys.dm_os_wait_stats
        WHERE wait_type NOT LIKE 'SLEEP%%'
          AND wait_type NOT IN (
                'BROKER_EVENTHANDLER','BROKER_RECEIVE_WAITFOR','BROKER_TASK_STOP',
                'BROKER_TO_FLUSH','BROKER_TRANSMITTER','CHECKPOINT_QUEUE','CHKPT',
                'CLR_AUTO_EVENT','CLR_MANUAL_EVENT','CLR_SEMAPHORE','LAZYWRITER_SLEEP',
                'FT_IFTS_SCHEDULER_IDLE_WAIT','XE_TIMER_EVENT','XE_DISPATCHER_WAIT',
                'XE_DISPATCHER_JOIN','DIRTY_PAGE_POLL','HADR_FILESTREAM_IOMGR_IOCOMPLETION',
                'SP_SERVER_DIAGNOSTICS_SLEEP','BROKER_CONNECTION_RECEIVE_TASK',
                'HADR_WORK_QUEUE','HADR_TIMER_TASK','HADR_CLUSAPI_CALL','QDS_SHUTDOWN_QUEUE',
                'WAIT_XTP_HOST_WAIT','HADR_FABRIC_CALLBACK','REQUEST_FOR_DEADLOCK_SEARCH',
                'SQLTRACE_INCREMENTAL_FLUSH_SLEEP','WAITFOR','DBMIRROR_DBM_MUTEX',
                'DBMIRROR_EVENTS_QUEUE','DBMIRRORING_CMD','DISPATCHER_QUEUE_SEMAPHORE',
                'LOGMGR_QUEUE','ONDEMAND_TASK_QUEUE','XE_BUFFERMGR_ALLPROCESSED_EVENT',
                'XE_BUFFERMGR_FREEBUF_EVENT'
            )
          AND wait_time_ms > 0
        ORDER BY wait_time_ms DESC

        SET @RowCount = @@ROWCOUNT

        IF @Debug = 1
        BEGIN
            EXEC dbo.DBA_LogEntry_Insert
                @ProcedureName = @ProcName,
                @ProcedureSection = 'COMPLETE',
                @IsError = 0,
                @ErrDescription = 'Wait statistics collected',
                @AdditionalInfo = 'Rows=' + CAST(@RowCount AS VARCHAR(20))
        END

        RETURN 0
    END TRY
    BEGIN CATCH
        EXEC dbo.DBA_LogEntry_Insert
            @ProcedureName = @ProcName,
            @ProcedureSection = 'ERROR',
            @IsError = 1,
            @ErrDescription = ERROR_MESSAGE(),
            @ErrNumber = ERROR_NUMBER(),
            @ErrSeverity = ERROR_SEVERITY(),
            @ErrState = ERROR_STATE(),
            @ErrLine = ERROR_LINE()

        RETURN -1
    END CATCH
END
GO

-- =============================================
-- P1.9: Collect TempDB Contention Detection
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P1_TempDBContention
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @ProcName SYSNAME = 'DBA_Collect_P1_TempDBContention'
    DECLARE @RowCount INT

    BEGIN TRY
        INSERT dbo.PerfSnapshotTempDBContention
        (
            PerfSnapshotRunID, WaitingTasksCount, PageResource,
            PageType, TotalWaitTimeMs, MaxWaitTimeMs
        )
        SELECT
            @PerfSnapshotRunID,
            COUNT(*) AS WaitingTasksCount,
            wait_resource AS PageResource,
            CASE
                WHEN wait_resource LIKE '2:1:1%' THEN 'PFS'
                WHEN wait_resource LIKE '2:1:2%' THEN 'GAM'
                WHEN wait_resource LIKE '2:1:3%' THEN 'SGAM'
                ELSE 'OTHER'
            END AS PageType,
            SUM(wait_duration_ms) AS TotalWaitTimeMs,
            MAX(wait_duration_ms) AS MaxWaitTimeMs
        FROM sys.dm_os_waiting_tasks
        WHERE wait_type LIKE 'PAGELATCH_%'
          AND wait_resource LIKE '2:1:%'  -- TempDB (database_id = 2), file 1
        GROUP BY wait_resource

        SET @RowCount = @@ROWCOUNT

        IF @Debug = 1
        BEGIN
            EXEC dbo.DBA_LogEntry_Insert
                @ProcedureName = @ProcName,
                @ProcedureSection = 'COMPLETE',
                @IsError = 0,
                @ErrDescription = 'TempDB contention stats collected',
                @AdditionalInfo = 'Rows=' + CAST(@RowCount AS VARCHAR(20))
        END

        RETURN 0
    END TRY
    BEGIN CATCH
        EXEC dbo.DBA_LogEntry_Insert
            @ProcedureName = @ProcName,
            @ProcedureSection = 'ERROR',
            @IsError = 1,
            @ErrDescription = ERROR_MESSAGE(),
            @ErrNumber = ERROR_NUMBER(),
            @ErrSeverity = ERROR_SEVERITY(),
            @ErrState = ERROR_STATE(),
            @ErrLine = ERROR_LINE()

        RETURN -1
    END CATCH
END
GO

-- =============================================
-- P1.10: Collect Query Execution Plans (Expensive Queries)
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P1_QueryPlans
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @ProcName SYSNAME = 'DBA_Collect_P1_QueryPlans'
    DECLARE @RowCount INT

    BEGIN TRY
        -- Capture top 20 by CPU
        INSERT dbo.PerfSnapshotQueryPlans
        (
            PerfSnapshotRunID, QueryHash, QueryPlanHash, DatabaseName,
            SqlText, ExecutionCount, AvgCpuMs, AvgLogicalReads, AvgElapsedMs,
            QueryPlanXML, CaptureReason
        )
        SELECT TOP 20
            @PerfSnapshotRunID,
            qs.query_hash,
            qs.plan_hash,
            DB_NAME(CAST(pa.value AS INT)) AS DatabaseName,
            SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
                CASE WHEN qs.statement_end_offset = -1
                     THEN DATALENGTH(st.text)
                     ELSE qs.statement_end_offset/2 - qs.statement_start_offset/2 + 1
                END) AS SqlText,
            qs.execution_count,
            (qs.total_worker_time / qs.execution_count) / 1000.0 AS AvgCpuMs,
            qs.total_logical_reads / NULLIF(qs.execution_count, 0) AS AvgLogicalReads,
            (qs.total_elapsed_time / qs.execution_count) / 1000.0 AS AvgElapsedMs,
            TRY_CAST(qp.query_plan AS XML) AS QueryPlanXML,
            'HighCPU' AS CaptureReason
        FROM sys.dm_exec_query_stats qs
        CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
        CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
        CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) pa
        WHERE pa.attribute = 'dbid'
          AND CAST(pa.value AS INT) > 4  -- Exclude system databases
        ORDER BY qs.total_worker_time DESC

        -- Capture top 10 by Logical Reads
        INSERT dbo.PerfSnapshotQueryPlans
        (
            PerfSnapshotRunID, QueryHash, QueryPlanHash, DatabaseName,
            SqlText, ExecutionCount, AvgCpuMs, AvgLogicalReads, AvgElapsedMs,
            QueryPlanXML, CaptureReason
        )
        SELECT TOP 10
            @PerfSnapshotRunID,
            qs.query_hash,
            qs.plan_hash,
            DB_NAME(CAST(pa.value AS INT)) AS DatabaseName,
            SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
                CASE WHEN qs.statement_end_offset = -1
                     THEN DATALENGTH(st.text)
                     ELSE qs.statement_end_offset/2 - qs.statement_start_offset/2 + 1
                END) AS SqlText,
            qs.execution_count,
            (qs.total_worker_time / qs.execution_count) / 1000.0 AS AvgCpuMs,
            qs.total_logical_reads / NULLIF(qs.execution_count, 0) AS AvgLogicalReads,
            (qs.total_elapsed_time / qs.execution_count) / 1000.0 AS AvgElapsedMs,
            TRY_CAST(qp.query_plan AS XML) AS QueryPlanXML,
            'HighReads' AS CaptureReason
        FROM sys.dm_exec_query_stats qs
        CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
        CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
        CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) pa
        WHERE pa.attribute = 'dbid'
          AND CAST(pa.value AS INT) > 4  -- Exclude system databases
          AND NOT EXISTS (
              SELECT 1 FROM dbo.PerfSnapshotQueryPlans
              WHERE PerfSnapshotRunID = @PerfSnapshotRunID
                AND QueryHash = qs.query_hash
          )
        ORDER BY qs.total_logical_reads DESC

        SET @RowCount = @@ROWCOUNT

        IF @Debug = 1
        BEGIN
            EXEC dbo.DBA_LogEntry_Insert
                @ProcedureName = @ProcName,
                @ProcedureSection = 'COMPLETE',
                @IsError = 0,
                @ErrDescription = 'Query plans collected',
                @AdditionalInfo = 'Rows=' + CAST(@RowCount AS VARCHAR(20))
        END

        RETURN 0
    END TRY
    BEGIN CATCH
        EXEC dbo.DBA_LogEntry_Insert
            @ProcedureName = @ProcName,
            @ProcedureSection = 'ERROR',
            @IsError = 1,
            @ErrDescription = ERROR_MESSAGE(),
            @ErrNumber = ERROR_NUMBER(),
            @ErrSeverity = ERROR_SEVERITY(),
            @ErrState = ERROR_STATE(),
            @ErrLine = ERROR_LINE()

        RETURN -1
    END CATCH
END
GO

PRINT 'P1 (High) modular collection procedures created successfully'
PRINT '  - DBA_Collect_P1_IndexUsage'
PRINT '  - DBA_Collect_P1_MissingIndexes'
PRINT '  - DBA_Collect_P1_WaitStats'
PRINT '  - DBA_Collect_P1_TempDBContention'
PRINT '  - DBA_Collect_P1_QueryPlans'
GO
