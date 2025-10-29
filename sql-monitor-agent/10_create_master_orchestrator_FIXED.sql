USE [DBATools]
GO

SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Master Orchestrator - Enhanced Performance Snapshot Collection (FIXED)
-- Integrated with config system
-- =============================================

CREATE OR ALTER PROCEDURE dbo.DBA_CollectPerformanceSnapshot
      @Debug BIT = 0,
      @IncludeP0 BIT = NULL,  -- NULL = use config
      @IncludeP1 BIT = NULL,
      @IncludeP2 BIT = NULL,
      @IncludeP3 BIT = NULL
AS
BEGIN
    SET NOCOUNT ON
    SET QUOTED_IDENTIFIER ON

    DECLARE @ProcName SYSNAME = 'DBA_CollectPerformanceSnapshot'
    DECLARE @Section VARCHAR(200) = 'START'
    DECLARE @NowUTC DATETIME2(3) = SYSUTCDATETIME()
    DECLARE @ServerName SYSNAME = CAST(SERVERPROPERTY('ServerName') AS SYSNAME)
    DECLARE @SqlVersion NVARCHAR(200) = CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(200))
    DECLARE @NewRunID BIGINT
    DECLARE @ReturnCode INT
    DECLARE @StartTime DATETIME2(3) = SYSUTCDATETIME()
    DECLARE @EndTime DATETIME2(3)
    DECLARE @DurationMs INT
    DECLARE @AdditionalInfo VARCHAR(4000)

    -- Get config if not specified
    IF @IncludeP0 IS NULL SET @IncludeP0 = dbo.fn_GetConfigBit('EnableP0Collection')
    IF @IncludeP1 IS NULL SET @IncludeP1 = dbo.fn_GetConfigBit('EnableP1Collection')
    IF @IncludeP2 IS NULL SET @IncludeP2 = dbo.fn_GetConfigBit('EnableP2Collection')
    IF @IncludeP3 IS NULL SET @IncludeP3 = dbo.fn_GetConfigBit('EnableP3Collection')

    BEGIN TRY
        -- =============================================
        -- BASELINE METRICS COLLECTION
        -- =============================================
        SET @Section = 'WAITS'

        DECLARE @TotalWaitMs BIGINT
        DECLARE @TotalSignalWaitMs BIGINT
        DECLARE @TopWaitType NVARCHAR(120)
        DECLARE @TopWaitMsPerSec DECIMAL(18,4)
        DECLARE @CpuSignalWaitPct DECIMAL(9,4)

        ;WITH Waits AS (
            SELECT wait_type, wait_time_ms, signal_wait_time_ms, waiting_tasks_count
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
                    'WAIT_XTP_HOST_WAIT','HADR_FABRIC_CALLBACK')
        )
        SELECT
            @TotalWaitMs = SUM(wait_time_ms),
            @TotalSignalWaitMs = SUM(signal_wait_time_ms)
        FROM Waits

        ;WITH Ranked AS (
            SELECT TOP 1 W.wait_type,
                (W.wait_time_ms / NULLIF(DATEDIFF(SECOND, sqlserver_start_time, SYSDATETIME()),0)*1.0) AS ms_per_sec
            FROM sys.dm_os_wait_stats W
            CROSS JOIN sys.dm_os_sys_info SI
            WHERE wait_type NOT LIKE 'SLEEP%%'
            ORDER BY W.wait_time_ms DESC
        )
        SELECT @TopWaitType = wait_type, @TopWaitMsPerSec = ms_per_sec FROM Ranked

        SET @CpuSignalWaitPct = CASE WHEN @TotalWaitMs = 0 THEN NULL
            ELSE (CAST(@TotalSignalWaitMs AS DECIMAL(18,4)) / @TotalWaitMs) * 100.0 END

        SET @Section = 'SESSION_COUNTS'

        DECLARE @SessionsCount INT, @RequestsCount INT, @BlockingSessionCount INT

        SELECT
            @SessionsCount = (SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE session_id <> @@SPID),
            @RequestsCount = (SELECT COUNT(*) FROM sys.dm_exec_requests WHERE session_id <> @@SPID),
            @BlockingSessionCount = (SELECT COUNT(DISTINCT session_id)
                FROM sys.dm_exec_requests WHERE blocking_session_id IS NOT NULL AND session_id <> @@SPID)

        SET @Section = 'HEALTH_COUNTS'

        -- Initialize to 0 (not NULL) so we always have a value even if XEvent parsing fails
        DECLARE @DeadlockCountRecent INT = 0, @MemoryGrantWarningCount INT = 0

        -- Optimized XEvent collection using XML variable (best practice for performance)
        -- Load XML into variable first to avoid expensive repeated DMV access
        BEGIN TRY
            DECLARE @TargetXML XML
            DECLARE @RecentThreshold DATETIME2(3) = DATEADD(MINUTE, -10, @NowUTC)

            -- Load XML into variable once
            SELECT @TargetXML = CAST(target_data AS XML)
            FROM sys.dm_xe_session_targets st
            INNER JOIN sys.dm_xe_sessions s ON s.address = st.event_session_address
            WHERE s.name = 'system_health' AND st.target_name = 'ring_buffer'

            -- Shred XML from variable (much faster) - direct query without CTE
            -- Use ISNULL to convert NULL to 0 when no events found
            SELECT
                @DeadlockCountRecent = ISNULL(SUM(CASE WHEN xed.event_data.value('(event/@name)[1]', 'nvarchar(128)') IN ('xml_deadlock_report','deadlock_report') THEN 1 ELSE 0 END), 0),
                @MemoryGrantWarningCount = ISNULL(SUM(CASE WHEN xed.event_data.value('(event/@name)[1]', 'nvarchar(128)') = 'exchange_spill' THEN 1 ELSE 0 END), 0)
            FROM @TargetXML.nodes('RingBufferTarget/event') AS xed(event_data)
            WHERE xed.event_data.value('(event/@timestamp)[1]','datetime2(3)') >= @RecentThreshold
        END TRY
        BEGIN CATCH
            -- If XEvent parsing fails, keep values at 0 (initialized above) and log error
            IF @Debug = 1
            BEGIN
                DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE()
                EXEC dbo.DBA_LogEntry_Insert @ProcName, 'HEALTH_COUNTS_ERROR', 0,
                    'XEvent parsing failed, values set to 0', @AdditionalInfo = @ErrMsg
            END
        END CATCH

        -- Enable deadlock trace flags if deadlocks detected
        -- Trace flag 1222: Detailed deadlock information in SQL Server error log (preferred)
        -- Trace flag 1204: Lock ownership information (older format, provides additional context)
        IF @DeadlockCountRecent > 0
        BEGIN
            BEGIN TRY
                -- Enable both trace flags globally (-1)
                -- These are idempotent - safe to call even if already enabled
                DBCC TRACEON(1222, -1) WITH NO_INFOMSGS
                DBCC TRACEON(1204, -1) WITH NO_INFOMSGS

                IF @Debug = 1
                BEGIN
                    SET @AdditionalInfo = 'DeadlockCount=' + CAST(@DeadlockCountRecent AS VARCHAR(10)) +
                                          ' (trace flags 1222, 1204 enabled)'
                    EXEC dbo.DBA_LogEntry_Insert @ProcName, 'DEADLOCK_TRACE', 0,
                        'Enabled deadlock trace flags for detailed logging',
                        @AdditionalInfo = @AdditionalInfo
                END
            END TRY
            BEGIN CATCH
                -- Log error but don't fail collection
                IF @Debug = 1
                BEGIN
                    SET @AdditionalInfo = 'Error enabling trace flags: ' + ERROR_MESSAGE()
                    EXEC dbo.DBA_LogEntry_Insert @ProcName, 'DEADLOCK_TRACE_ERROR', 1,
                        'Failed to enable deadlock trace flags',
                        @AdditionalInfo = @AdditionalInfo
                END
            END CATCH
        END

        SET @Section = 'INSERT_RUN'

        INSERT dbo.PerfSnapshotRun (
            SnapshotUTC, ServerName, SqlVersion, CpuSignalWaitPct, TopWaitType, TopWaitMsPerSec,
            SessionsCount, RequestsCount, BlockingSessionCount, DeadlockCountRecent, MemoryGrantWarningCount
        )
        VALUES (
            @NowUTC, @ServerName, @SqlVersion, @CpuSignalWaitPct, @TopWaitType, @TopWaitMsPerSec,
            @SessionsCount, @RequestsCount, @BlockingSessionCount, @DeadlockCountRecent, @MemoryGrantWarningCount
        )

        SET @NewRunID = SCOPE_IDENTITY()

        IF @Debug = 1
        BEGIN
            SET @AdditionalInfo = 'PerfSnapshotRunID=' + CAST(@NewRunID AS VARCHAR(50))
            EXEC dbo.DBA_LogEntry_Insert @ProcName, 'INSERT_RUN', 0, 'Inserted PerfSnapshotRun', @AdditionalInfo = @AdditionalInfo
        END

        -- =============================================
        -- P0 CRITICAL COLLECTORS
        -- =============================================
        IF @IncludeP0 = 1
        BEGIN
            SET @Section = 'P0_QUERY_STATS'
            EXEC @ReturnCode = dbo.DBA_Collect_P0_QueryStats @NewRunID, @Debug

            SET @Section = 'P0_IO_STATS'
            EXEC @ReturnCode = dbo.DBA_Collect_P0_IOStats @NewRunID, @Debug

            SET @Section = 'P0_MEMORY'
            EXEC @ReturnCode = dbo.DBA_Collect_P0_Memory @NewRunID, @Debug

            SET @Section = 'P0_BACKUP_HISTORY'
            EXEC @ReturnCode = dbo.DBA_Collect_P0_BackupHistory @NewRunID, @Debug
        END

        -- =============================================
        -- DATABASE STATS (Optimized) - Using sys.dm_io_virtual_file_stats for file sizes
        -- =============================================
        SET @Section = 'DB_STATS'

        -- Create temp table to hold database stats
        CREATE TABLE #DBStats (
            DatabaseID INT,
            DatabaseName SYSNAME,
            StateDesc NVARCHAR(60),
            RecoveryModelDesc NVARCHAR(60),
            IsReadOnly BIT,
            TotalDataMB DECIMAL(18,2),
            TotalLogMB DECIMAL(18,2),
            LogReuseWaitDesc NVARCHAR(60),
            FileCount INT,
            CompatLevel TINYINT,
            IsAutoClose BIT,
            IsAutoShrink BIT,
            IsAutoCreateStats BIT,
            IsAutoUpdateStats BIT,
            PageVerifyOption NVARCHAR(60),
            SnapshotIsolationState NVARCHAR(60),
            IsRCAllowed BIT
        )

        -- Optimized: Use sys.dm_io_virtual_file_stats for file sizes (avoids offline DB issues)
        ;WITH FileSizes AS (
            SELECT
                vfs.database_id,
                SUM(CASE WHEN mf.type = 0 THEN vfs.size_on_disk_bytes / 1024.0 / 1024.0 ELSE 0 END) AS TotalDataMB,
                SUM(CASE WHEN mf.type = 1 THEN vfs.size_on_disk_bytes / 1024.0 / 1024.0 ELSE 0 END) AS TotalLogMB,
                COUNT(*) AS FileCount
            FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
            INNER JOIN sys.master_files mf WITH (NOLOCK)
                ON vfs.database_id = mf.database_id
                AND vfs.file_id = mf.file_id
            WHERE vfs.database_id IN (SELECT database_id FROM dbo.vw_MonitoredDatabases)
            GROUP BY vfs.database_id
        )
        INSERT INTO #DBStats (
            DatabaseID, DatabaseName, StateDesc, RecoveryModelDesc, IsReadOnly,
            TotalDataMB, TotalLogMB, LogReuseWaitDesc, FileCount, CompatLevel,
            IsAutoClose, IsAutoShrink, IsAutoCreateStats, IsAutoUpdateStats,
            PageVerifyOption, SnapshotIsolationState, IsRCAllowed
        )
        SELECT
            md.database_id,
            md.database_name,
            md.state_desc,
            md.recovery_model_desc,
            md.is_read_only,
            ISNULL(fs.TotalDataMB, 0) AS TotalDataMB,
            ISNULL(fs.TotalLogMB, 0) AS TotalLogMB,
            d.log_reuse_wait_desc,
            ISNULL(fs.FileCount, 0) AS FileCount,
            md.compatibility_level,
            d.is_auto_close_on,
            d.is_auto_shrink_on,
            d.is_auto_create_stats_on,
            d.is_auto_update_stats_on,
            d.page_verify_option_desc,
            d.snapshot_isolation_state_desc,
            d.is_read_committed_snapshot_on
        FROM dbo.vw_MonitoredDatabases md
        INNER JOIN sys.databases d WITH (NOLOCK)
            ON md.database_id = d.database_id
        LEFT JOIN FileSizes fs
            ON md.database_id = fs.database_id

        -- Insert from temp table into PerfSnapshotDB
        INSERT dbo.PerfSnapshotDB (
            PerfSnapshotRunID, DatabaseID, DatabaseName, StateDesc, RecoveryModelDesc, IsReadOnly,
            TotalDataMB, TotalLogMB, LogReuseWaitDesc, FileCount, CompatLevel,
            IsAutoClose, IsAutoShrink, IsAutoCreateStats, IsAutoUpdateStats,
            PageVerifyOption, SnapshotIsolationState, IsRCAllowed
        )
        SELECT
            @NewRunID, DatabaseID, DatabaseName, StateDesc, RecoveryModelDesc, IsReadOnly,
            TotalDataMB, TotalLogMB, LogReuseWaitDesc, FileCount, CompatLevel,
            IsAutoClose, IsAutoShrink, IsAutoCreateStats, IsAutoUpdateStats,
            PageVerifyOption, SnapshotIsolationState, IsRCAllowed
        FROM #DBStats

        DROP TABLE #DBStats

        IF @Debug = 1
        BEGIN
            SET @AdditionalInfo = 'PerfSnapshotRunID=' + CAST(@NewRunID AS VARCHAR(50))
            EXEC dbo.DBA_LogEntry_Insert @ProcName, 'DB_STATS', 0, 'Inserted PerfSnapshotDB rows', @AdditionalInfo = @AdditionalInfo
        END

        -- =============================================
        -- WORKLOAD COLLECTION
        -- =============================================
        SET @Section = 'WORKLOAD'

        ;WITH Req AS (
            SELECT r.session_id, r.blocking_session_id, r.cpu_time AS CpuTimeMs,
                r.total_elapsed_time AS TotalElapsedMs, r.logical_reads, r.writes,
                r.wait_type, r.wait_time AS WaitTimeMs, r.database_id, r.status, r.command,
                r.sql_handle, r.statement_start_offset, r.statement_end_offset
            FROM sys.dm_exec_requests r WHERE r.session_id <> @@SPID
        ),
        Sess AS (
            SELECT s.session_id, s.login_name, s.host_name
            FROM sys.dm_exec_sessions s WHERE s.session_id <> @@SPID
        ),
        Texts AS (
            SELECT R.session_id, R.blocking_session_id, R.CpuTimeMs, R.TotalElapsedMs,
                R.logical_reads, R.writes, R.wait_type, R.WaitTimeMs, R.database_id, R.status, R.command,
                SUBSTRING(st.text, (R.statement_start_offset/2)+1,
                    CASE WHEN R.statement_end_offset = -1 THEN (DATALENGTH(st.text)/2) - (R.statement_start_offset/2) + 1
                         ELSE (R.statement_end_offset/2) - (R.statement_start_offset/2) + 1 END) AS StatementText,
                st.objectid AS ObjectID_IfModule
            FROM Req R CROSS APPLY sys.dm_exec_sql_text(R.sql_handle) st
        )
        INSERT dbo.PerfSnapshotWorkload (
            PerfSnapshotRunID, SessionID, LoginName, HostName, DatabaseName, Status, Command,
            WaitType, WaitTimeMs, BlockingSessionID, CpuTimeMs, TotalElapsedMs,
            LogicalReads, Writes, StatementText, OBJECT_NAME_Resolved
        )
        SELECT
            @NewRunID, T.session_id, S.login_name, S.host_name, DB_NAME(T.database_id),
            T.status, T.command, T.wait_type, T.WaitTimeMs, T.blocking_session_id,
            T.CpuTimeMs, T.TotalElapsedMs, T.logical_reads, T.writes, T.StatementText,
            CASE
                WHEN T.ObjectID_IfModule IS NOT NULL AND md.database_id IS NOT NULL
                THEN OBJECT_SCHEMA_NAME(T.ObjectID_IfModule, T.database_id) + '.' +
                     OBJECT_NAME(T.ObjectID_IfModule, T.database_id)
                ELSE NULL
            END
        FROM Texts T
        LEFT JOIN Sess S ON T.session_id = S.session_id
        LEFT JOIN dbo.vw_MonitoredDatabases md ON T.database_id = md.database_id

        IF @Debug = 1
        BEGIN
            SET @AdditionalInfo = 'PerfSnapshotRunID=' + CAST(@NewRunID AS VARCHAR(50))
            EXEC dbo.DBA_LogEntry_Insert @ProcName, 'WORKLOAD', 0, 'Inserted PerfSnapshotWorkload rows', @AdditionalInfo = @AdditionalInfo
        END

        -- =============================================
        -- ERRORLOG COLLECTION
        -- =============================================
        SET @Section = 'ERRORLOG'

        CREATE TABLE #ErrLogDump (LogDate DATETIME, ProcessInfo NVARCHAR(50), LogText NVARCHAR(4000))
        INSERT #ErrLogDump EXEC master.sys.xp_readerrorlog 0, 1

        INSERT dbo.PerfSnapshotErrorLog (PerfSnapshotRunID, LogDateUTC, ProcessInfo, LogText)
        SELECT TOP 20
            @NewRunID,
            CAST(SWITCHOFFSET(CONVERT(DATETIMEOFFSET(3), LogDate), '+00:00') AS DATETIME2(3)) AS LogDateUTC,
            ProcessInfo, LogText
        FROM #ErrLogDump ORDER BY LogDate DESC

        DROP TABLE #ErrLogDump

        IF @Debug = 1
        BEGIN
            SET @AdditionalInfo = 'PerfSnapshotRunID=' + CAST(@NewRunID AS VARCHAR(50))
            EXEC dbo.DBA_LogEntry_Insert @ProcName, 'ERRORLOG', 0, 'Inserted PerfSnapshotErrorLog rows', @AdditionalInfo = @AdditionalInfo
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
            SET @AdditionalInfo = 'PerfSnapshotRunID=' + CAST(@NewRunID AS VARCHAR(50)) + ', Duration=' + CAST(@DurationMs AS VARCHAR(10)) + 'ms'
            EXEC dbo.DBA_LogEntry_Insert @ProcName, 'DONE', 0, 'Completed snapshot run', @AdditionalInfo = @AdditionalInfo
        END

        RETURN 0

    END TRY
    BEGIN CATCH
        DECLARE @ErrNumber BIGINT = ERROR_NUMBER()
        DECLARE @ErrSeverity INT = ERROR_SEVERITY()
        DECLARE @ErrState INT = ERROR_STATE()
        DECLARE @ErrLine INT = ERROR_LINE()
        DECLARE @ErrProcedure SYSNAME = ERROR_PROCEDURE()
        DECLARE @ErrDescription VARCHAR(2000) = ERROR_MESSAGE()

        SET @AdditionalInfo = 'Snapshot failed at section ' + @Section

        EXEC dbo.DBA_LogEntry_Insert @ProcName, @Section, 1, @ErrDescription,
            @ErrNumber = @ErrNumber, @ErrSeverity = @ErrSeverity,
            @ErrState = @ErrState, @ErrLine = @ErrLine,
            @ErrProcedure = @ErrProcedure, @AdditionalInfo = @AdditionalInfo

        RETURN -1
    END CATCH
END
GO

PRINT 'Master orchestrator procedure created successfully - FIXED'
PRINT 'Config Integration:'
PRINT '  - Reads EnableP0Collection, EnableP1Collection, EnableP2Collection, EnableP3Collection'
PRINT '  - Pass NULL to use config, or 0/1 to override'
PRINT ''
PRINT 'Usage:'
PRINT '  EXEC DBA_CollectPerformanceSnapshot @Debug = 1  -- Use config settings'
PRINT '  EXEC DBA_CollectPerformanceSnapshot @IncludeP0=1, @IncludeP1=1, @IncludeP2=0, @IncludeP3=0'
GO
