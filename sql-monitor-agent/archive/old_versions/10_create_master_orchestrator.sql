USE [DBATools]
GO

-- =============================================
-- Master Orchestrator - Enhanced Performance Snapshot Collection
-- Calls all modular collectors in priority order
-- =============================================

CREATE OR ALTER PROCEDURE dbo.DBA_CollectPerformanceSnapshot
      @Debug BIT = 0,
      @IncludeP0 BIT = 1,  -- Query stats, I/O, Memory, Backups
      @IncludeP1 BIT = 1,  -- Indexes, Wait stats, TempDB, Query plans
      @IncludeP2 BIT = 1,  -- Config, VLF, Deadlocks, Schedulers, Counters, Autogrowth
      @IncludeP3 BIT = 0   -- Latch stats, Job history, Spinlocks (disabled by default)
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @ProcName SYSNAME = 'DBA_CollectPerformanceSnapshot'
    DECLARE @Section  VARCHAR(200) = 'START'
    DECLARE @NowUTC   DATETIME2(3) = SYSUTCDATETIME()
    DECLARE @ServerName SYSNAME = CAST(SERVERPROPERTY('ServerName') AS SYSNAME)
    DECLARE @SqlVersion NVARCHAR(200) = CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(200))
    DECLARE @NewRunID BIGINT
    DECLARE @ReturnCode INT
    DECLARE @StartTime DATETIME2(3) = SYSUTCDATETIME()
    DECLARE @EndTime DATETIME2(3)
    DECLARE @DurationMs INT

    BEGIN TRY
        -- =============================================
        -- BASELINE COLLECTION (from original procedure)
        -- =============================================

        SET @Section = 'WAITS'

        ;WITH Waits AS
        (
            SELECT
                wait_type,
                wait_time_ms,
                signal_wait_time_ms = signal_wait_time_ms,
                waiting_tasks_count
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
                    'WAIT_XTP_HOST_WAIT','HADR_FABRIC_CALLBACK'
                )
        ),
        Totals AS
        (
            SELECT
                SUM(wait_time_ms)        AS total_wait_ms,
                SUM(signal_wait_time_ms) AS total_signal_wait_ms
            FROM Waits
        ),
        Ranked AS
        (
            SELECT TOP 1
                W.wait_type,
                W.wait_time_ms,
                (W.wait_time_ms / NULLIF(DATEDIFF(SECOND, sqlserver_start_time, SYSDATETIME()),0)*1.0) AS ms_per_sec
            FROM Waits W
            CROSS JOIN sys.dm_os_sys_info SI
            ORDER BY W.wait_time_ms DESC
        )
        SELECT
            @Section = 'WAITS_FINAL'
        ;

        DECLARE @TotalWaitMs BIGINT
        DECLARE @TotalSignalWaitMs BIGINT
        DECLARE @TopWaitType NVARCHAR(120)
        DECLARE @TopWaitMsPerSec DECIMAL(18,4)

        SELECT
            @TotalWaitMs        = T.total_wait_ms,
            @TotalSignalWaitMs  = T.total_signal_wait_ms
        FROM Totals T

        SELECT
            @TopWaitType        = R.wait_type,
            @TopWaitMsPerSec    = R.ms_per_sec
        FROM Ranked R

        DECLARE @CpuSignalWaitPct DECIMAL(9,4)
        SET @CpuSignalWaitPct =
            CASE
                WHEN @TotalWaitMs IS NULL OR @TotalWaitMs = 0 THEN NULL
                ELSE (CAST(@TotalSignalWaitMs AS DECIMAL(18,4)) / @TotalWaitMs) * 100.0
            END

        SET @Section = 'SESSION_REQUEST_COUNTS'

        DECLARE @SessionsCount INT
        DECLARE @RequestsCount INT
        DECLARE @BlockingSessionCount INT

        ;WITH Sess AS
        (
            SELECT session_id, is_user_process
            FROM sys.dm_exec_sessions
            WHERE session_id <> @@SPID
        ),
        Req AS
        (
            SELECT session_id, blocking_session_id
            FROM sys.dm_exec_requests
            WHERE session_id <> @@SPID
        )
        SELECT
            @SessionsCount = (SELECT COUNT(*) FROM Sess),
            @RequestsCount = (SELECT COUNT(*) FROM Req),
            @BlockingSessionCount = (
                SELECT COUNT(DISTINCT r.session_id)
                FROM Req r
                WHERE r.blocking_session_id IS NOT NULL
            )

        SET @Section = 'HEALTH_COUNTS'

        DECLARE @DeadlockCountRecent INT = NULL
        DECLARE @MemoryGrantWarningCount INT = NULL

        ;WITH XEventData AS
        (
            SELECT
                xed.event_data.value('(event/@name)[1]', 'nvarchar(128)') AS event_name,
                xed.event_data.value('(event/@timestamp)[1]','datetime2(3)') AS [utc_time]
            FROM
            (
                SELECT CAST(target_data AS XML) AS TargetData
                FROM sys.dm_xe_session_targets st
                INNER JOIN sys.dm_xe_sessions s
                    ON s.address = st.event_session_address
                WHERE s.name = 'system_health'
                  AND st.target_name = 'ring_buffer'
            ) AS tab
            CROSS APPLY tab.TargetData.nodes('RingBufferTarget/event') AS xed(event_data)
        )
        SELECT
            @DeadlockCountRecent = SUM(CASE WHEN event_name IN ('xml_deadlock_report','deadlock_report')
                                            AND utc_time >= DATEADD(MINUTE,-10,@NowUTC) THEN 1 ELSE 0 END),
            @MemoryGrantWarningCount = SUM(CASE WHEN event_name = 'exchange_spill'
                                                AND utc_time >= DATEADD(MINUTE,-10,@NowUTC) THEN 1 ELSE 0 END)
        FROM XEventData

        SET @Section = 'INSERT_RUN'

        INSERT dbo.PerfSnapshotRun
        (
            SnapshotUTC,
            ServerName,
            SqlVersion,
            CpuSignalWaitPct,
            TopWaitType,
            TopWaitMsPerSec,
            SessionsCount,
            RequestsCount,
            BlockingSessionCount,
            DeadlockCountRecent,
            MemoryGrantWarningCount
        )
        VALUES
        (
            @NowUTC,
            @ServerName,
            @SqlVersion,
            @CpuSignalWaitPct,
            @TopWaitType,
            @TopWaitMsPerSec,
            @SessionsCount,
            @RequestsCount,
            @BlockingSessionCount,
            @DeadlockCountRecent,
            @MemoryGrantWarningCount
        )

        SET @NewRunID = SCOPE_IDENTITY()

        IF @Debug = 1
        BEGIN
            EXEC dbo.DBA_LogEntry_Insert
                  @ProcedureName    = @ProcName
                , @ProcedureSection = 'INSERT_RUN'
                , @IsError          = 0
                , @ErrDescription   = 'Inserted PerfSnapshotRun'
                , @AdditionalInfo   = 'PerfSnapshotRunID=' + CAST(@NewRunID AS VARCHAR(50))
        END

        -- =============================================
        -- P0 CRITICAL COLLECTORS
        -- =============================================

        IF @IncludeP0 = 1
        BEGIN
            SET @Section = 'P0_QUERY_STATS'
            EXEC @ReturnCode = dbo.DBA_Collect_P0_QueryStats @NewRunID, @Debug
            IF @ReturnCode <> 0 AND @Debug = 1
                PRINT 'Warning: P0_QueryStats returned ' + CAST(@ReturnCode AS VARCHAR(10))

            SET @Section = 'P0_IO_STATS'
            EXEC @ReturnCode = dbo.DBA_Collect_P0_IOStats @NewRunID, @Debug
            IF @ReturnCode <> 0 AND @Debug = 1
                PRINT 'Warning: P0_IOStats returned ' + CAST(@ReturnCode AS VARCHAR(10))

            SET @Section = 'P0_MEMORY'
            EXEC @ReturnCode = dbo.DBA_Collect_P0_Memory @NewRunID, @Debug
            IF @ReturnCode <> 0 AND @Debug = 1
                PRINT 'Warning: P0_Memory returned ' + CAST(@ReturnCode AS VARCHAR(10))

            SET @Section = 'P0_BACKUP_HISTORY'
            EXEC @ReturnCode = dbo.DBA_Collect_P0_BackupHistory @NewRunID, @Debug
            IF @ReturnCode <> 0 AND @Debug = 1
                PRINT 'Warning: P0_BackupHistory returned ' + CAST(@ReturnCode AS VARCHAR(10))
        END

        -- =============================================
        -- ORIGINAL DB_STATS (Enhanced)
        -- =============================================

        SET @Section = 'DB_STATS'

        ;WITH dbfiles AS
        (
            SELECT
                db.database_id,
                db.name AS DatabaseName,
                mf.type_desc,
                TotalMB = SUM((mf.size/128.0)),
                FileCount = COUNT(*)
            FROM sys.databases db
            JOIN sys.master_files mf
                ON db.database_id = mf.database_id
            GROUP BY
                db.database_id,
                db.name,
                mf.type_desc
        ),
        dbagg AS
        (
            SELECT
                d.database_id,
                d.DatabaseName,
                SUM(CASE WHEN df.type_desc = 'ROWS' THEN df.TotalMB ELSE 0 END) AS DataMB,
                SUM(CASE WHEN df.type_desc = 'LOG'  THEN df.TotalMB ELSE 0 END) AS LogMB,
                SUM(df.FileCount) AS FileCount
            FROM (SELECT DISTINCT database_id, DatabaseName FROM dbfiles) d
            JOIN dbfiles df
                ON d.database_id = df.database_id
            GROUP BY d.database_id, d.DatabaseName
        )
        INSERT dbo.PerfSnapshotDB
        (
            PerfSnapshotRunID,
            DatabaseID,
            DatabaseName,
            StateDesc,
            RecoveryModelDesc,
            IsReadOnly,
            TotalDataMB,
            TotalLogMB,
            LogReuseWaitDesc,
            FileCount,
            CompatLevel,
            IsAutoClose,
            IsAutoShrink,
            IsAutoCreateStats,
            IsAutoUpdateStats,
            PageVerifyOption,
            SnapshotIsolationState,
            IsRCAllowed
        )
        SELECT
              @NewRunID
            , d.database_id
            , d.name
            , d.state_desc
            , d.recovery_model_desc
            , d.is_read_only
            , A.DataMB
            , A.LogMB
            , d.log_reuse_wait_desc
            , A.FileCount
            , d.compatibility_level
            , d.is_auto_close_on
            , d.is_auto_shrink_on
            , d.is_auto_create_stats_on
            , d.is_auto_update_stats_on
            , d.page_verify_option_desc
            , d.snapshot_isolation_state_desc
            , d.is_read_committed_snapshot_on
        FROM sys.databases d
        LEFT JOIN dbagg A
            ON d.database_id = A.database_id

        IF @Debug = 1
        BEGIN
            EXEC dbo.DBA_LogEntry_Insert
                  @ProcedureName    = @ProcName
                , @ProcedureSection = 'DB_STATS'
                , @IsError          = 0
                , @ErrDescription   = 'Inserted PerfSnapshotDB rows'
                , @AdditionalInfo   = 'PerfSnapshotRunID=' + CAST(@NewRunID AS VARCHAR(50))
        END

        -- =============================================
        -- ORIGINAL WORKLOAD COLLECTION
        -- =============================================

        SET @Section = 'WORKLOAD'

        ;WITH Req AS
        (
            SELECT
                r.session_id,
                r.blocking_session_id,
                r.cpu_time AS CpuTimeMs,
                r.total_elapsed_time AS TotalElapsedMs,
                r.logical_reads,
                r.writes,
                r.wait_type,
                r.wait_time AS WaitTimeMs,
                r.database_id,
                r.status,
                r.command,
                r.sql_handle,
                r.statement_start_offset,
                r.statement_end_offset
            FROM sys.dm_exec_requests r
            WHERE r.session_id <> @@SPID
        ),
        Sess AS
        (
            SELECT
                s.session_id,
                s.login_name,
                s.host_name
            FROM sys.dm_exec_sessions s
            WHERE s.session_id <> @@SPID
        ),
        Texts AS
        (
            SELECT
                R.session_id,
                R.blocking_session_id,
                R.CpuTimeMs,
                R.TotalElapsedMs,
                R.logical_reads,
                R.writes,
                R.wait_type,
                R.WaitTimeMs,
                R.database_id,
                R.status,
                R.command,
                R.statement_start_offset,
                R.statement_end_offset,
                SUBSTRING(
                    st.text,
                    (R.statement_start_offset/2)+1,
                    (
                        CASE
                            WHEN R.statement_end_offset = -1
                            THEN (DATALENGTH(st.text)/2) - (R.statement_start_offset/2) + 1
                            ELSE (R.statement_end_offset/2) - (R.statement_start_offset/2) + 1
                        END
                    )
                ) AS StatementText,
                st.objectid AS ObjectID_IfModule
            FROM Req R
            CROSS APPLY sys.dm_exec_sql_text(R.sql_handle) st
        )
        INSERT dbo.PerfSnapshotWorkload
        (
            PerfSnapshotRunID,
            SessionID,
            LoginName,
            HostName,
            DatabaseName,
            Status,
            Command,
            WaitType,
            WaitTimeMs,
            BlockingSessionID,
            CpuTimeMs,
            TotalElapsedMs,
            LogicalReads,
            Writes,
            StatementText,
            OBJECT_NAME_Resolved
        )
        SELECT
              @NewRunID
            , T.session_id
            , S.login_name
            , S.host_name
            , DB_NAME(T.database_id)
            , T.status
            , T.command
            , T.wait_type
            , T.WaitTimeMs
            , T.blocking_session_id
            , T.CpuTimeMs
            , T.TotalElapsedMs
            , T.logical_reads
            , T.writes
            , T.StatementText
            , OBJECT_SCHEMA_NAME(T.ObjectID_IfModule, T.database_id)
              + '.' +
              OBJECT_NAME(T.ObjectID_IfModule, T.database_id)
        FROM Texts T
        LEFT JOIN Sess S
            ON T.session_id = S.session_id

        IF @Debug = 1
        BEGIN
            EXEC dbo.DBA_LogEntry_Insert
                  @ProcedureName    = @ProcName
                , @ProcedureSection = 'WORKLOAD'
                , @IsError          = 0
                , @ErrDescription   = 'Inserted PerfSnapshotWorkload rows'
                , @AdditionalInfo   = 'PerfSnapshotRunID=' + CAST(@NewRunID AS VARCHAR(50))
        END

        -- =============================================
        -- ORIGINAL ERRORLOG COLLECTION
        -- =============================================

        SET @Section = 'ERRORLOG'

        CREATE TABLE #ErrLogDump
        (
            LogDate        DATETIME,
            ProcessInfo    NVARCHAR(50),
            LogText        NVARCHAR(4000)
        )

        INSERT #ErrLogDump
        EXEC master.sys.xp_readerrorlog 0, 1

        ;WITH RecentErrs AS
        (
            SELECT TOP 20
                LogDateUTC   = CAST(SWITCHOFFSET(CONVERT(DATETIMEOFFSET(3), LogDate), '+00:00') AS DATETIME2(3)),
                ProcessInfo,
                LogText
            FROM #ErrLogDump
            ORDER BY LogDate DESC
        )
        INSERT dbo.PerfSnapshotErrorLog
        (
            PerfSnapshotRunID,
            LogDateUTC,
            ProcessInfo,
            LogText
        )
        SELECT
              @NewRunID
            , R.LogDateUTC
            , R.ProcessInfo
            , R.LogText
        FROM RecentErrs R

        DROP TABLE #ErrLogDump

        IF @Debug = 1
        BEGIN
            EXEC dbo.DBA_LogEntry_Insert
                  @ProcedureName    = @ProcName
                , @ProcedureSection = 'ERRORLOG'
                , @IsError          = 0
                , @ErrDescription   = 'Inserted PerfSnapshotErrorLog rows'
                , @AdditionalInfo   = 'PerfSnapshotRunID=' + CAST(@NewRunID AS VARCHAR(50))
        END

        -- =============================================
        -- P1 HIGH PRIORITY COLLECTORS
        -- =============================================

        IF @IncludeP1 = 1
        BEGIN
            SET @Section = 'P1_INDEX_USAGE'
            EXEC @ReturnCode = dbo.DBA_Collect_P1_IndexUsage @NewRunID, @Debug

            SET @Section = 'P1_MISSING_INDEXES'
            EXEC @ReturnCode = dbo.DBA_Collect_P1_MissingIndexes @NewRunID, @Debug

            SET @Section = 'P1_WAIT_STATS'
            EXEC @ReturnCode = dbo.DBA_Collect_P1_WaitStats @NewRunID, @Debug

            SET @Section = 'P1_TEMPDB_CONTENTION'
            EXEC @ReturnCode = dbo.DBA_Collect_P1_TempDBContention @NewRunID, @Debug

            SET @Section = 'P1_QUERY_PLANS'
            EXEC @ReturnCode = dbo.DBA_Collect_P1_QueryPlans @NewRunID, @Debug
        END

        -- =============================================
        -- P2 MEDIUM PRIORITY COLLECTORS
        -- =============================================

        IF @IncludeP2 = 1
        BEGIN
            SET @Section = 'P2_SERVER_CONFIG'
            EXEC @ReturnCode = dbo.DBA_Collect_P2_ServerConfig @NewRunID, @Debug

            SET @Section = 'P2_VLF_COUNTS'
            EXEC @ReturnCode = dbo.DBA_Collect_P2_VLFCounts @NewRunID, @Debug

            SET @Section = 'P2_DEADLOCK_DETAILS'
            EXEC @ReturnCode = dbo.DBA_Collect_P2_DeadlockDetails @NewRunID, @Debug

            SET @Section = 'P2_SCHEDULER_HEALTH'
            EXEC @ReturnCode = dbo.DBA_Collect_P2_SchedulerHealth @NewRunID, @Debug

            SET @Section = 'P2_PERF_COUNTERS'
            EXEC @ReturnCode = dbo.DBA_Collect_P2_PerfCounters @NewRunID, @Debug

            SET @Section = 'P2_AUTOGROWTH_EVENTS'
            EXEC @ReturnCode = dbo.DBA_Collect_P2_AutogrowthEvents @NewRunID, @Debug
        END

        -- =============================================
        -- P3 LOW PRIORITY COLLECTORS
        -- =============================================

        IF @IncludeP3 = 1
        BEGIN
            SET @Section = 'P3_LATCH_STATS'
            EXEC @ReturnCode = dbo.DBA_Collect_P3_LatchStats @NewRunID, @Debug

            SET @Section = 'P3_JOB_HISTORY'
            EXEC @ReturnCode = dbo.DBA_Collect_P3_JobHistory @NewRunID, @Debug

            SET @Section = 'P3_SPINLOCK_STATS'
            EXEC @ReturnCode = dbo.DBA_Collect_P3_SpinlockStats @NewRunID, @Debug
        END

        -- =============================================
        -- COMPLETION
        -- =============================================

        SET @Section = 'DONE'
        SET @EndTime = SYSUTCDATETIME()
        SET @DurationMs = DATEDIFF(MILLISECOND, @StartTime, @EndTime)

        IF @Debug = 1
        BEGIN
            EXEC dbo.DBA_LogEntry_Insert
                  @ProcedureName    = @ProcName
                , @ProcedureSection = 'DONE'
                , @IsError          = 0
                , @ErrDescription   = 'Completed snapshot run'
                , @AdditionalInfo   = 'PerfSnapshotRunID=' + CAST(@NewRunID AS VARCHAR(50)) +
                                      ', Duration=' + CAST(@DurationMs AS VARCHAR(10)) + 'ms'
        END

        RETURN 0

    END TRY
    BEGIN CATCH
        DECLARE @ErrNumber BIGINT        = ERROR_NUMBER()
        DECLARE @ErrSeverity INT         = ERROR_SEVERITY()
        DECLARE @ErrState INT            = ERROR_STATE()
        DECLARE @ErrLine INT             = ERROR_LINE()
        DECLARE @ErrProcedure SYSNAME    = ERROR_PROCEDURE()
        DECLARE @ErrDescription VARCHAR(2000) = ERROR_MESSAGE()

        EXEC dbo.DBA_LogEntry_Insert
              @ProcedureName    = @ProcName
            , @ProcedureSection = @Section
            , @IsError          = 1
            , @ErrDescription   = @ErrDescription
            , @ErrNumber        = @ErrNumber
            , @ErrSeverity      = @ErrSeverity
            , @ErrState         = @ErrState
            , @ErrLine          = @ErrLine
            , @ErrProcedure     = @ErrProcedure
            , @AdditionalInfo   = 'Snapshot failed at section ' + @Section

        DECLARE @ReThrowMessage NVARCHAR(4000) =
            'Error in ' + @ProcName + ' section ' + ISNULL(@Section,'UNKNOWN') + ': ' + @ErrDescription

        RAISERROR (@ReThrowMessage, 16, 1)

        RETURN -1
    END CATCH
END
GO

PRINT 'Master orchestrator procedure created successfully: DBA_CollectPerformanceSnapshot'
PRINT 'Call with: EXEC DBATools.dbo.DBA_CollectPerformanceSnapshot @Debug = 1'
GO
