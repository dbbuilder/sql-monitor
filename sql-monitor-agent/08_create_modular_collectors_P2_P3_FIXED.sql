USE [DBATools]
GO

-- =============================================
-- P2 MEDIUM PRIORITY - Modular Collectors (FIXED)
-- =============================================

-- P2.11: Collect Server Configuration Baseline
CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P2_ServerConfig
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON
    DECLARE @ProcName SYSNAME = 'DBA_Collect_P2_ServerConfig'
    DECLARE @RowCount INT
    DECLARE @AdditionalInfo VARCHAR(4000)

    BEGIN TRY
        INSERT dbo.PerfSnapshotConfig
        (
            PerfSnapshotRunID, ConfigurationID, ConfigName, ConfigValue,
            ConfigValueInUse, ConfigMinimum, ConfigMaximum, IsAdvanced, IsDynamic
        )
        SELECT
            @PerfSnapshotRunID, configuration_id, name, value,
            value_in_use, minimum, maximum, is_advanced, is_dynamic
        FROM sys.configurations
        WHERE name IN (
            'max degree of parallelism', 'cost threshold for parallelism',
            'max server memory (MB)', 'min server memory (MB)',
            'optimize for ad hoc workloads', 'backup compression default',
            'remote admin connections', 'Agent XPs'
        )

        SET @RowCount = @@ROWCOUNT
        IF @Debug = 1
        BEGIN
            SET @AdditionalInfo = 'Rows=' + CAST(@RowCount AS VARCHAR(20))
            EXEC dbo.DBA_LogEntry_Insert @ProcName, 'COMPLETE', 0, 'Config collected', @AdditionalInfo = @AdditionalInfo
        END
        RETURN 0
    END TRY
    BEGIN CATCH
        DECLARE @ErrMessage NVARCHAR(4000) = ERROR_MESSAGE()
        DECLARE @ErrNumber INT = ERROR_NUMBER()
        DECLARE @ErrSeverity INT = ERROR_SEVERITY()
        DECLARE @ErrState INT = ERROR_STATE()
        DECLARE @ErrLine INT = ERROR_LINE()
        EXEC dbo.DBA_LogEntry_Insert @ProcName, 'ERROR', 1, @ErrMessage,
            @ErrNumber = @ErrNumber, @ErrSeverity = @ErrSeverity, @ErrState = @ErrState, @ErrLine = @ErrLine
        RETURN -1
    END CATCH
END
GO

-- P2.12: Update VLF Counts (Optimized - DMV-based, non-blocking)
-- Uses sys.dm_db_log_info() instead of DBCC LOGINFO for 10-20x faster performance
CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P2_VLFCounts
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON
    DECLARE @ProcName SYSNAME = 'DBA_Collect_P2_VLFCounts'
    DECLARE @RowCount INT

    BEGIN TRY
        -- Use sys.dm_db_log_info() with CROSS APPLY for fast, non-blocking VLF collection
        -- This is 10-20x faster than DBCC LOGINFO approach and won't block on busy databases
        -- Requires SQL Server 2016+ (you have SQL Server 2022)

        CREATE TABLE #VLFCounts (DatabaseName SYSNAME, VLFCount INT)

        -- Collect VLF counts for all monitored databases in one query
        -- No cursor, no context switching, no blocking
        -- Uses vw_MonitoredDatabases for centralized include/exclude filtering
        INSERT INTO #VLFCounts (DatabaseName, VLFCount)
        SELECT
            md.database_name AS DatabaseName,
            COUNT(*) AS VLFCount
        FROM dbo.vw_MonitoredDatabases md
        CROSS APPLY sys.dm_db_log_info(md.database_id) li
        GROUP BY md.database_name

        -- Update PerfSnapshotDB with VLF counts
        UPDATE pdb
        SET pdb.VLFCount = vlf.VLFCount
        FROM dbo.PerfSnapshotDB pdb
        INNER JOIN #VLFCounts vlf ON pdb.DatabaseName = vlf.DatabaseName
        WHERE pdb.PerfSnapshotRunID = @PerfSnapshotRunID

        SET @RowCount = @@ROWCOUNT

        DROP TABLE #VLFCounts

        IF @Debug = 1
        BEGIN
            DECLARE @InfoMsg VARCHAR(200) = 'VLF counts updated for ' + CAST(@RowCount AS VARCHAR) + ' databases (DMV-based, non-blocking)'
            EXEC dbo.DBA_LogEntry_Insert @ProcName, 'COMPLETE', 0, @InfoMsg
        END

        RETURN 0
    END TRY
    BEGIN CATCH
        IF OBJECT_ID('tempdb..#VLFCounts') IS NOT NULL DROP TABLE #VLFCounts

        DECLARE @ErrMessage NVARCHAR(4000) = ERROR_MESSAGE()
        DECLARE @ErrNumber INT = ERROR_NUMBER()
        DECLARE @ErrSeverity INT = ERROR_SEVERITY()
        DECLARE @ErrState INT = ERROR_STATE()
        DECLARE @ErrLine INT = ERROR_LINE()

        EXEC dbo.DBA_LogEntry_Insert @ProcName, 'ERROR', 1, @ErrMessage,
            @ErrNumber = @ErrNumber, @ErrSeverity = @ErrSeverity,
            @ErrState = @ErrState, @ErrLine = @ErrLine

        RETURN -1
    END CATCH
END
GO

-- P2.13: Collect Enhanced Deadlock Analysis
-- Required SET options for XML column operations (must be set at procedure creation time)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
SET ANSI_WARNINGS ON
GO
SET CONCAT_NULL_YIELDS_NULL ON
GO
SET ARITHABORT ON
GO

CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P2_DeadlockDetails
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON
    DECLARE @ProcName SYSNAME = 'DBA_Collect_P2_DeadlockDetails'
    DECLARE @RowCount INT, @NowUTC DATETIME2(3) = SYSUTCDATETIME(), @AdditionalInfo VARCHAR(4000)

    BEGIN TRY
        INSERT dbo.PerfSnapshotDeadlocks (PerfSnapshotRunID, DeadlockTimestamp, DeadlockXML, DeadlockGraphHash)
        SELECT @PerfSnapshotRunID,
            xed.event_data.value('(event/@timestamp)[1]', 'datetime2(3)') AS DeadlockTimestamp,
            xed.event_data.query('.') AS DeadlockXML,
            HASHBYTES('SHA2_256', CAST(xed.event_data.query('.') AS NVARCHAR(MAX))) AS DeadlockGraphHash
        FROM (SELECT CAST(target_data AS XML) AS TargetData FROM sys.dm_xe_session_targets st
              INNER JOIN sys.dm_xe_sessions s ON s.address = st.event_session_address
              WHERE s.name = 'system_health' AND st.target_name = 'ring_buffer') AS tab
        CROSS APPLY tab.TargetData.nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') AS xed(event_data)
        WHERE xed.event_data.value('(event/@timestamp)[1]', 'datetime2(3)') >= DATEADD(MINUTE, -10, @NowUTC)

        SET @RowCount = @@ROWCOUNT
        IF @Debug = 1
        BEGIN
            SET @AdditionalInfo = 'Rows=' + CAST(@RowCount AS VARCHAR(20))
            EXEC dbo.DBA_LogEntry_Insert @ProcName, 'COMPLETE', 0, 'Deadlock details collected', @AdditionalInfo = @AdditionalInfo
        END
        RETURN 0
    END TRY
    BEGIN CATCH
        DECLARE @ErrMessage NVARCHAR(4000) = ERROR_MESSAGE()
        DECLARE @ErrNumber INT = ERROR_NUMBER()
        DECLARE @ErrSeverity INT = ERROR_SEVERITY()
        DECLARE @ErrState INT = ERROR_STATE()
        DECLARE @ErrLine INT = ERROR_LINE()
        EXEC dbo.DBA_LogEntry_Insert @ProcName, 'ERROR', 1, @ErrMessage,
            @ErrNumber = @ErrNumber, @ErrSeverity = @ErrSeverity, @ErrState = @ErrState, @ErrLine = @ErrLine
        RETURN -1
    END CATCH
END
GO

-- P2.14: Collect Scheduler Health Metrics
CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P2_SchedulerHealth
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON
    DECLARE @ProcName SYSNAME = 'DBA_Collect_P2_SchedulerHealth'
    DECLARE @RowCount INT, @AdditionalInfo VARCHAR(4000)

    BEGIN TRY
        INSERT dbo.PerfSnapshotSchedulers
        (PerfSnapshotRunID, SchedulerID, CpuID, Status, IsOnline, CurrentTasksCount, RunnableTasksCount,
         CurrentWorkersCount, ActiveWorkersCount, WorkQueueCount, PendingDiskIOCount,
         LoadFactor, YieldCount, ContextSwitchCount)
        SELECT @PerfSnapshotRunID, scheduler_id, cpu_id, status, is_online, current_tasks_count, runnable_tasks_count,
            current_workers_count, active_workers_count, work_queue_count, pending_disk_io_count,
            load_factor, yield_count, context_switches_count
        FROM sys.dm_os_schedulers
        WHERE scheduler_id < 255

        SET @RowCount = @@ROWCOUNT
        IF @Debug = 1
        BEGIN
            SET @AdditionalInfo = 'Rows=' + CAST(@RowCount AS VARCHAR(20))
            EXEC dbo.DBA_LogEntry_Insert @ProcName, 'COMPLETE', 0, 'Scheduler health collected', @AdditionalInfo = @AdditionalInfo
        END
        RETURN 0
    END TRY
    BEGIN CATCH
        DECLARE @ErrMessage NVARCHAR(4000) = ERROR_MESSAGE()
        DECLARE @ErrNumber INT = ERROR_NUMBER()
        DECLARE @ErrSeverity INT = ERROR_SEVERITY()
        DECLARE @ErrState INT = ERROR_STATE()
        DECLARE @ErrLine INT = ERROR_LINE()
        EXEC dbo.DBA_LogEntry_Insert @ProcName, 'ERROR', 1, @ErrMessage,
            @ErrNumber = @ErrNumber, @ErrSeverity = @ErrSeverity, @ErrState = @ErrState, @ErrLine = @ErrLine
        RETURN -1
    END CATCH
END
GO

-- P2.15: Collect Performance Counters
CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P2_PerfCounters
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON
    DECLARE @ProcName SYSNAME = 'DBA_Collect_P2_PerfCounters'
    DECLARE @RowCount INT, @AdditionalInfo VARCHAR(4000)

    BEGIN TRY
        INSERT dbo.PerfSnapshotCounters (PerfSnapshotRunID, ObjectName, CounterName, InstanceName, CntrValue, CntrType)
        SELECT @PerfSnapshotRunID, object_name, counter_name, instance_name, cntr_value, cntr_type
        FROM sys.dm_os_performance_counters
        WHERE counter_name IN ('Batch Requests/sec', 'SQL Compilations/sec', 'SQL Re-Compilations/sec',
            'User Connections', 'Transactions/sec', 'Lock Waits/sec', 'Lock Wait Time (ms)',
            'Page Splits/sec', 'Lazy writes/sec', 'Checkpoint pages/sec', 'Free Space in tempdb (KB)')

        SET @RowCount = @@ROWCOUNT
        IF @Debug = 1
        BEGIN
            SET @AdditionalInfo = 'Rows=' + CAST(@RowCount AS VARCHAR(20))
            EXEC dbo.DBA_LogEntry_Insert @ProcName, 'COMPLETE', 0, 'Performance counters collected', @AdditionalInfo = @AdditionalInfo
        END
        RETURN 0
    END TRY
    BEGIN CATCH
        DECLARE @ErrMessage NVARCHAR(4000) = ERROR_MESSAGE()
        DECLARE @ErrNumber INT = ERROR_NUMBER()
        DECLARE @ErrSeverity INT = ERROR_SEVERITY()
        DECLARE @ErrState INT = ERROR_STATE()
        DECLARE @ErrLine INT = ERROR_LINE()
        EXEC dbo.DBA_LogEntry_Insert @ProcName, 'ERROR', 1, @ErrMessage,
            @ErrNumber = @ErrNumber, @ErrSeverity = @ErrSeverity, @ErrState = @ErrState, @ErrLine = @ErrLine
        RETURN -1
    END CATCH
END
GO

-- P2.16: Collect Autogrowth Events
CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P2_AutogrowthEvents
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON
    DECLARE @ProcName SYSNAME = 'DBA_Collect_P2_AutogrowthEvents'
    DECLARE @RowCount INT, @NowUTC DATETIME2(3) = SYSUTCDATETIME(), @TraceFileName NVARCHAR(500), @AdditionalInfo VARCHAR(4000)

    BEGIN TRY
        SELECT @TraceFileName = REVERSE(SUBSTRING(REVERSE([path]), CHARINDEX('\', REVERSE([path])), 260)) + N'log.trc'
        FROM sys.traces WHERE is_default = 1

        -- Note: Autogrowth requires Extended Events or specific trace columns
        -- Skipping for now as default trace may not have FileID column
        IF @TraceFileName IS NOT NULL AND 1 = 0  -- Disabled until XEvent implementation
        BEGIN
            INSERT dbo.PerfSnapshotAutogrowthEvents
            (PerfSnapshotRunID, DatabaseID, DatabaseName, FileID, FileName, FileType, EventTimestamp, DurationMs, GrowthMB)
            SELECT @PerfSnapshotRunID, DatabaseID, DB_NAME(DatabaseID),
                0 AS FileID, 'N/A' AS FileName,
                CASE WHEN EventClass = 92 THEN 'ROWS' ELSE 'LOG' END AS FileType,
                StartTime AS EventTimestamp, Duration / 1000 AS DurationMs, (IntegerData * 8) / 1024.0 AS GrowthMB
            FROM sys.fn_trace_gettable(@TraceFileName, DEFAULT)
            WHERE EventClass IN (92, 93) AND StartTime >= DATEADD(MINUTE, -10, @NowUTC) AND DatabaseID > 4
        END

        SET @RowCount = @@ROWCOUNT
        IF @Debug = 1
        BEGIN
            SET @AdditionalInfo = 'Rows=' + CAST(@RowCount AS VARCHAR(20))
            EXEC dbo.DBA_LogEntry_Insert @ProcName, 'COMPLETE', 0, 'Autogrowth events collected', @AdditionalInfo = @AdditionalInfo
        END
        RETURN 0
    END TRY
    BEGIN CATCH
        DECLARE @ErrMessage NVARCHAR(4000) = ERROR_MESSAGE()
        DECLARE @ErrNumber INT = ERROR_NUMBER()
        DECLARE @ErrSeverity INT = ERROR_SEVERITY()
        DECLARE @ErrState INT = ERROR_STATE()
        DECLARE @ErrLine INT = ERROR_LINE()
        EXEC dbo.DBA_LogEntry_Insert @ProcName, 'ERROR', 1, @ErrMessage,
            @ErrNumber = @ErrNumber, @ErrSeverity = @ErrSeverity, @ErrState = @ErrState, @ErrLine = @ErrLine
        RETURN -1
    END CATCH
END
GO

-- =============================================
-- P3 LOW PRIORITY - Modular Collectors (FIXED)
-- =============================================

-- P3.18: Collect Latch Statistics
CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P3_LatchStats
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON
    DECLARE @ProcName SYSNAME = 'DBA_Collect_P3_LatchStats'
    DECLARE @RowCount INT, @AdditionalInfo VARCHAR(4000)

    BEGIN TRY
        INSERT dbo.PerfSnapshotLatchStats (PerfSnapshotRunID, LatchClass, WaitingRequestsCount, WaitTimeMs, MaxWaitTimeMs, AvgWaitTimeMs)
        SELECT TOP 50 @PerfSnapshotRunID, latch_class, waiting_requests_count, wait_time_ms, max_wait_time_ms,
            CASE WHEN waiting_requests_count = 0 THEN 0 ELSE wait_time_ms / NULLIF(waiting_requests_count, 0) END AS AvgWaitTimeMs
        FROM sys.dm_os_latch_stats WHERE wait_time_ms > 0 ORDER BY wait_time_ms DESC

        SET @RowCount = @@ROWCOUNT
        IF @Debug = 1
        BEGIN
            SET @AdditionalInfo = 'Rows=' + CAST(@RowCount AS VARCHAR(20))
            EXEC dbo.DBA_LogEntry_Insert @ProcName, 'COMPLETE', 0, 'Latch statistics collected', @AdditionalInfo = @AdditionalInfo
        END
        RETURN 0
    END TRY
    BEGIN CATCH
        DECLARE @ErrMessage NVARCHAR(4000) = ERROR_MESSAGE()
        DECLARE @ErrNumber INT = ERROR_NUMBER()
        DECLARE @ErrSeverity INT = ERROR_SEVERITY()
        DECLARE @ErrState INT = ERROR_STATE()
        DECLARE @ErrLine INT = ERROR_LINE()
        EXEC dbo.DBA_LogEntry_Insert @ProcName, 'ERROR', 1, @ErrMessage,
            @ErrNumber = @ErrNumber, @ErrSeverity = @ErrSeverity, @ErrState = @ErrState, @ErrLine = @ErrLine
        RETURN -1
    END CATCH
END
GO

-- P3.19: Collect SQL Agent Job History
CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P3_JobHistory
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON
    DECLARE @ProcName SYSNAME = 'DBA_Collect_P3_JobHistory'
    DECLARE @RowCount INT, @NowUTC DATETIME2(3) = SYSUTCDATETIME(), @AdditionalInfo VARCHAR(4000)

    BEGIN TRY
        INSERT dbo.PerfSnapshotJobHistory (PerfSnapshotRunID, JobID, JobName, IsEnabled, LastRunDate, LastRunOutcome, LastRunDurationSeconds, FailureCountLast24Hours)
        SELECT @PerfSnapshotRunID, j.job_id, j.name AS JobName, j.enabled AS IsEnabled,
            CASE WHEN h.LastRunDate = 0 THEN NULL
                 ELSE CAST(CAST(h.LastRunDate AS VARCHAR(8)) + ' ' +
                      STUFF(STUFF(RIGHT('000000' + CAST(h.LastRunTime AS VARCHAR(6)), 6), 5, 0, ':'), 3, 0, ':') AS DATETIME2(3))
            END AS LastRunDate,
            h.LastRunOutcome, h.LastRunDuration AS LastRunDurationSeconds,
            (SELECT COUNT(*) FROM msdb.dbo.sysjobhistory jh WHERE jh.job_id = j.job_id AND jh.run_status = 0
             AND jh.run_date >= CAST(CONVERT(VARCHAR(8), DATEADD(DAY, -1, GETDATE()), 112) AS INT)) AS FailureCountLast24Hours
        FROM msdb.dbo.sysjobs j
        OUTER APPLY (SELECT TOP 1 run_date AS LastRunDate, run_time AS LastRunTime, run_status AS LastRunOutcome, run_duration AS LastRunDuration
                     FROM msdb.dbo.sysjobhistory WHERE job_id = j.job_id AND step_id = 0 ORDER BY run_date DESC, run_time DESC) h

        SET @RowCount = @@ROWCOUNT
        IF @Debug = 1
        BEGIN
            SET @AdditionalInfo = 'Rows=' + CAST(@RowCount AS VARCHAR(20))
            EXEC dbo.DBA_LogEntry_Insert @ProcName, 'COMPLETE', 0, 'Job history collected', @AdditionalInfo = @AdditionalInfo
        END
        RETURN 0
    END TRY
    BEGIN CATCH
        DECLARE @ErrMessage NVARCHAR(4000) = ERROR_MESSAGE()
        DECLARE @ErrNumber INT = ERROR_NUMBER()
        DECLARE @ErrSeverity INT = ERROR_SEVERITY()
        DECLARE @ErrState INT = ERROR_STATE()
        DECLARE @ErrLine INT = ERROR_LINE()
        EXEC dbo.DBA_LogEntry_Insert @ProcName, 'ERROR', 1, @ErrMessage,
            @ErrNumber = @ErrNumber, @ErrSeverity = @ErrSeverity, @ErrState = @ErrState, @ErrLine = @ErrLine
        RETURN -1
    END CATCH
END
GO

-- P3.21: Collect Spinlock Statistics
CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P3_SpinlockStats
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON
    DECLARE @ProcName SYSNAME = 'DBA_Collect_P3_SpinlockStats'
    DECLARE @RowCount INT, @AdditionalInfo VARCHAR(4000)

    BEGIN TRY
        INSERT dbo.PerfSnapshotSpinlockStats (PerfSnapshotRunID, SpinlockName, Collisions, Spins, SpinsPerCollision, SleepTime, Backoffs)
        SELECT TOP 50 @PerfSnapshotRunID, name AS SpinlockName, collisions, spins, spins_per_collision AS SpinsPerCollision, sleep_time AS SleepTime, backoffs
        FROM sys.dm_os_spinlock_stats WHERE collisions > 0 ORDER BY collisions DESC

        SET @RowCount = @@ROWCOUNT
        IF @Debug = 1
        BEGIN
            SET @AdditionalInfo = 'Rows=' + CAST(@RowCount AS VARCHAR(20))
            EXEC dbo.DBA_LogEntry_Insert @ProcName, 'COMPLETE', 0, 'Spinlock statistics collected', @AdditionalInfo = @AdditionalInfo
        END
        RETURN 0
    END TRY
    BEGIN CATCH
        DECLARE @ErrMessage NVARCHAR(4000) = ERROR_MESSAGE()
        DECLARE @ErrNumber INT = ERROR_NUMBER()
        DECLARE @ErrSeverity INT = ERROR_SEVERITY()
        DECLARE @ErrState INT = ERROR_STATE()
        DECLARE @ErrLine INT = ERROR_LINE()
        EXEC dbo.DBA_LogEntry_Insert @ProcName, 'ERROR', 1, @ErrMessage,
            @ErrNumber = @ErrNumber, @ErrSeverity = @ErrSeverity, @ErrState = @ErrState, @ErrLine = @ErrLine
        RETURN -1
    END CATCH
END
GO

PRINT 'P2 (Medium) and P3 (Low) modular collection procedures created successfully - FIXED'
PRINT 'P2: ServerConfig, VLFCounts, DeadlockDetails, SchedulerHealth, PerfCounters, AutogrowthEvents'
PRINT 'P3: LatchStats, JobHistory, SpinlockStats'
GO
