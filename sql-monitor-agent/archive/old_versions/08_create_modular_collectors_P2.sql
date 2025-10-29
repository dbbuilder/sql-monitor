USE [DBATools]
GO

-- =============================================
-- P2 MEDIUM PRIORITY - Modular Collectors
-- =============================================

-- =============================================
-- P2.11: Collect Server Configuration Baseline
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P2_ServerConfig
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @ProcName SYSNAME = 'DBA_Collect_P2_ServerConfig'
    DECLARE @RowCount INT

    BEGIN TRY
        INSERT dbo.PerfSnapshotConfig
        (
            PerfSnapshotRunID, ConfigurationID, ConfigName, ConfigValue,
            ConfigValueInUse, ConfigMinimum, ConfigMaximum, IsAdvanced, IsDynamic
        )
        SELECT
            @PerfSnapshotRunID,
            configuration_id,
            name,
            value,
            value_in_use,
            minimum,
            maximum,
            is_advanced,
            is_dynamic
        FROM sys.configurations
        WHERE name IN (
            'max degree of parallelism',
            'cost threshold for parallelism',
            'max server memory (MB)',
            'min server memory (MB)',
            'optimize for ad hoc workloads',
            'backup compression default',
            'remote admin connections',
            'Agent XPs'
        )

        SET @RowCount = @@ROWCOUNT

        IF @Debug = 1
        BEGIN
            EXEC dbo.DBA_LogEntry_Insert
                @ProcedureName = @ProcName,
                @ProcedureSection = 'COMPLETE',
                @IsError = 0,
                @ErrDescription = 'Server configuration collected',
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
-- P2.12: Update VLF Counts (updates existing PerfSnapshotDB)
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P2_VLFCounts
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @ProcName SYSNAME = 'DBA_Collect_P2_VLFCounts'
    DECLARE @DatabaseName SYSNAME
    DECLARE @VLFCount INT
    DECLARE @SQL NVARCHAR(MAX)

    BEGIN TRY
        DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT DatabaseName
            FROM dbo.PerfSnapshotDB
            WHERE PerfSnapshotRunID = @PerfSnapshotRunID
              AND StateDesc = 'ONLINE'

        OPEN db_cursor
        FETCH NEXT FROM db_cursor INTO @DatabaseName

        WHILE @@FETCH_STATUS = 0
        BEGIN
            BEGIN TRY
                -- Use DBCC LOGINFO to count VLFs
                CREATE TABLE #VLFInfo (
                    RecoveryUnitId INT NULL,
                    FileId INT,
                    FileSize BIGINT,
                    StartOffset BIGINT,
                    FSeqNo BIGINT,
                    Status INT,
                    Parity INT,
                    CreateLSN NUMERIC(38)
                )

                SET @SQL = N'USE [' + @DatabaseName + N']; INSERT #VLFInfo EXEC(''DBCC LOGINFO WITH NO_INFOMSGS'');'
                EXEC sp_executesql @SQL

                SELECT @VLFCount = COUNT(*) FROM #VLFInfo

                UPDATE dbo.PerfSnapshotDB
                SET VLFCount = @VLFCount
                WHERE PerfSnapshotRunID = @PerfSnapshotRunID
                  AND DatabaseName = @DatabaseName

                DROP TABLE #VLFInfo
            END TRY
            BEGIN CATCH
                -- Skip databases with errors (e.g., offline, restoring)
                IF OBJECT_ID('tempdb..#VLFInfo') IS NOT NULL
                    DROP TABLE #VLFInfo
            END CATCH

            FETCH NEXT FROM db_cursor INTO @DatabaseName
        END

        CLOSE db_cursor
        DEALLOCATE db_cursor

        IF @Debug = 1
        BEGIN
            EXEC dbo.DBA_LogEntry_Insert
                @ProcedureName = @ProcName,
                @ProcedureSection = 'COMPLETE',
                @IsError = 0,
                @ErrDescription = 'VLF counts updated'
        END

        RETURN 0
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'db_cursor') >= 0
        BEGIN
            CLOSE db_cursor
            DEALLOCATE db_cursor
        END

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
-- P2.13: Collect Enhanced Deadlock Analysis
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P2_DeadlockDetails
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @ProcName SYSNAME = 'DBA_Collect_P2_DeadlockDetails'
    DECLARE @RowCount INT
    DECLARE @NowUTC DATETIME2(3) = SYSUTCDATETIME()

    BEGIN TRY
        INSERT dbo.PerfSnapshotDeadlocks
        (
            PerfSnapshotRunID, DeadlockTimestamp, DeadlockXML,
            DeadlockGraphHash
        )
        SELECT
            @PerfSnapshotRunID,
            xed.event_data.value('(event/@timestamp)[1]', 'datetime2(3)') AS DeadlockTimestamp,
            xed.event_data.query('.') AS DeadlockXML,
            HASHBYTES('SHA2_256', CAST(xed.event_data.query('.') AS NVARCHAR(MAX))) AS DeadlockGraphHash
        FROM
        (
            SELECT CAST(target_data AS XML) AS TargetData
            FROM sys.dm_xe_session_targets st
            INNER JOIN sys.dm_xe_sessions s
                ON s.address = st.event_session_address
            WHERE s.name = 'system_health'
              AND st.target_name = 'ring_buffer'
        ) AS tab
        CROSS APPLY tab.TargetData.nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') AS xed(event_data)
        WHERE xed.event_data.value('(event/@timestamp)[1]', 'datetime2(3)') >= DATEADD(MINUTE, -10, @NowUTC)

        SET @RowCount = @@ROWCOUNT

        IF @Debug = 1
        BEGIN
            EXEC dbo.DBA_LogEntry_Insert
                @ProcedureName = @ProcName,
                @ProcedureSection = 'COMPLETE',
                @IsError = 0,
                @ErrDescription = 'Deadlock details collected',
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
-- P2.14: Collect Scheduler Health Metrics
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P2_SchedulerHealth
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @ProcName SYSNAME = 'DBA_Collect_P2_SchedulerHealth'
    DECLARE @RowCount INT

    BEGIN TRY
        INSERT dbo.PerfSnapshotSchedulers
        (
            PerfSnapshotRunID, SchedulerID, CpuID, Status, IsOnline,
            CurrentTasksCount, RunnableTasksCount, CurrentWorkersCount,
            ActiveWorkersCount, WorkQueueCount, PendingDiskIOCount,
            LoadFactor, YieldCount, ContextSwitchCount
        )
        SELECT
            @PerfSnapshotRunID,
            scheduler_id,
            cpu_id,
            status,
            is_online,
            current_tasks_count,
            runnable_tasks_count,
            current_workers_count,
            active_workers_count,
            work_queue_count,
            pending_disk_io_count,
            load_factor,
            yield_count,
            context_switch_count
        FROM sys.dm_os_schedulers
        WHERE scheduler_id < 255  -- Exclude hidden schedulers

        SET @RowCount = @@ROWCOUNT

        IF @Debug = 1
        BEGIN
            EXEC dbo.DBA_LogEntry_Insert
                @ProcedureName = @ProcName,
                @ProcedureSection = 'COMPLETE',
                @IsError = 0,
                @ErrDescription = 'Scheduler health collected',
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
-- P2.15: Collect Performance Counters
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P2_PerfCounters
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @ProcName SYSNAME = 'DBA_Collect_P2_PerfCounters'
    DECLARE @RowCount INT

    BEGIN TRY
        INSERT dbo.PerfSnapshotCounters
        (
            PerfSnapshotRunID, ObjectName, CounterName, InstanceName,
            CntrValue, CntrType
        )
        SELECT
            @PerfSnapshotRunID,
            object_name,
            counter_name,
            instance_name,
            cntr_value,
            cntr_type
        FROM sys.dm_os_performance_counters
        WHERE counter_name IN (
            'Batch Requests/sec',
            'SQL Compilations/sec',
            'SQL Re-Compilations/sec',
            'User Connections',
            'Transactions/sec',
            'Lock Waits/sec',
            'Lock Wait Time (ms)',
            'Page Splits/sec',
            'Lazy writes/sec',
            'Checkpoint pages/sec',
            'Free Space in tempdb (KB)'
        )

        SET @RowCount = @@ROWCOUNT

        IF @Debug = 1
        BEGIN
            EXEC dbo.DBA_LogEntry_Insert
                @ProcedureName = @ProcName,
                @ProcedureSection = 'COMPLETE',
                @IsError = 0,
                @ErrDescription = 'Performance counters collected',
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
-- P2.16: Collect Autogrowth Events
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P2_AutogrowthEvents
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @ProcName SYSNAME = 'DBA_Collect_P2_AutogrowthEvents'
    DECLARE @RowCount INT
    DECLARE @NowUTC DATETIME2(3) = SYSUTCDATETIME()

    BEGIN TRY
        -- Capture autogrowth events from default trace (last 10 minutes)
        DECLARE @TraceFileName NVARCHAR(500)
        SELECT @TraceFileName = REVERSE(SUBSTRING(REVERSE([path]), CHARINDEX('\', REVERSE([path])), 260)) + N'log.trc'
        FROM sys.traces
        WHERE is_default = 1

        IF @TraceFileName IS NOT NULL
        BEGIN
            INSERT dbo.PerfSnapshotAutogrowthEvents
            (
                PerfSnapshotRunID, DatabaseID, DatabaseName, FileID, FileName,
                FileType, EventTimestamp, DurationMs, GrowthMB
            )
            SELECT
                @PerfSnapshotRunID,
                DatabaseID,
                DatabaseName,
                FileID,
                FileName,
                CASE WHEN EventClass = 92 THEN 'ROWS' ELSE 'LOG' END AS FileType,
                StartTime AS EventTimestamp,
                Duration / 1000 AS DurationMs,
                (IntegerData * 8) / 1024.0 AS GrowthMB
            FROM sys.fn_trace_gettable(@TraceFileName, DEFAULT)
            WHERE EventClass IN (92, 93)  -- Data File Auto Grow, Log File Auto Grow
              AND StartTime >= DATEADD(MINUTE, -10, @NowUTC)
              AND DatabaseID > 4  -- Exclude system databases
        END

        SET @RowCount = @@ROWCOUNT

        IF @Debug = 1
        BEGIN
            EXEC dbo.DBA_LogEntry_Insert
                @ProcedureName = @ProcName,
                @ProcedureSection = 'COMPLETE',
                @IsError = 0,
                @ErrDescription = 'Autogrowth events collected',
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

PRINT 'P2 (Medium) modular collection procedures created successfully'
PRINT '  - DBA_Collect_P2_ServerConfig'
PRINT '  - DBA_Collect_P2_VLFCounts'
PRINT '  - DBA_Collect_P2_DeadlockDetails'
PRINT '  - DBA_Collect_P2_SchedulerHealth'
PRINT '  - DBA_Collect_P2_PerfCounters'
PRINT '  - DBA_Collect_P2_AutogrowthEvents'
GO
