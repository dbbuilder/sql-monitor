USE [DBATools]
GO

-- =============================================
-- P0 CRITICAL PRIORITY - Modular Collectors
-- =============================================

-- =============================================
-- P0.1: Collect Query Performance Baseline
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P0_QueryStats
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @ProcName SYSNAME = 'DBA_Collect_P0_QueryStats'
    DECLARE @RowCount INT

    BEGIN TRY
        INSERT dbo.PerfSnapshotQueryStats
        (
            PerfSnapshotRunID, QueryHash, QueryPlanHash, DatabaseID, DatabaseName,
            ObjectID, ObjectName, SqlText, ExecutionCount, TotalCpuMs, AvgCpuMs,
            TotalLogicalReads, AvgLogicalReads, TotalPhysicalReads, AvgPhysicalReads,
            TotalElapsedMs, AvgElapsedMs, TotalWorkerTimeMs, AvgWorkerTimeMs,
            CreationTime, LastExecutionTime, PlanHandle
        )
        SELECT TOP 100
            @PerfSnapshotRunID,
            qs.query_hash,
            qs.plan_hash,
            CAST(pa.value AS INT) AS DatabaseID,
            DB_NAME(CAST(pa.value AS INT)) AS DatabaseName,
            st.objectid,
            OBJECT_SCHEMA_NAME(st.objectid, CAST(pa.value AS INT)) + '.' +
                OBJECT_NAME(st.objectid, CAST(pa.value AS INT)) AS ObjectName,
            SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
                CASE WHEN qs.statement_end_offset = -1
                     THEN DATALENGTH(st.text)
                     ELSE qs.statement_end_offset/2 - qs.statement_start_offset/2 + 1
                END) AS SqlText,
            qs.execution_count,
            qs.total_worker_time / 1000 AS TotalCpuMs,
            (qs.total_worker_time / qs.execution_count) / 1000.0 AS AvgCpuMs,
            qs.total_logical_reads,
            qs.total_logical_reads / NULLIF(qs.execution_count, 0) AS AvgLogicalReads,
            qs.total_physical_reads,
            qs.total_physical_reads / NULLIF(qs.execution_count, 0) AS AvgPhysicalReads,
            qs.total_elapsed_time / 1000 AS TotalElapsedMs,
            (qs.total_elapsed_time / qs.execution_count) / 1000.0 AS AvgElapsedMs,
            qs.total_worker_time / 1000 AS TotalWorkerTimeMs,
            (qs.total_worker_time / qs.execution_count) / 1000.0 AS AvgWorkerTimeMs,
            qs.creation_time,
            qs.last_execution_time,
            qs.plan_handle
        FROM sys.dm_exec_query_stats qs
        CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
        CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) pa
        WHERE pa.attribute = 'dbid'
          AND CAST(pa.value AS INT) > 4  -- Exclude system databases
        ORDER BY qs.total_worker_time DESC

        SET @RowCount = @@ROWCOUNT

        IF @Debug = 1
        BEGIN
            EXEC dbo.DBA_LogEntry_Insert
                @ProcedureName = @ProcName,
                @ProcedureSection = 'COMPLETE',
                @IsError = 0,
                @ErrDescription = 'Query stats collected',
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
-- P0.2: Collect I/O Performance Baseline
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P0_IOStats
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @ProcName SYSNAME = 'DBA_Collect_P0_IOStats'
    DECLARE @RowCount INT

    BEGIN TRY
        INSERT dbo.PerfSnapshotIOStats
        (
            PerfSnapshotRunID, DatabaseID, DatabaseName, FileID, FileType,
            PhysicalName, NumReads, BytesRead, IoStallReadMs, NumWrites,
            BytesWritten, IoStallWriteMs, IoStallMs, SizeOnDiskMB,
            AvgReadLatencyMs, AvgWriteLatencyMs
        )
        SELECT
            @PerfSnapshotRunID,
            vfs.database_id,
            DB_NAME(vfs.database_id),
            vfs.file_id,
            mf.type_desc,
            mf.physical_name,
            vfs.num_of_reads,
            vfs.num_of_bytes_read,
            vfs.io_stall_read_ms,
            vfs.num_of_writes,
            vfs.num_of_bytes_written,
            vfs.io_stall_write_ms,
            vfs.io_stall,
            vfs.size_on_disk_bytes / 1024.0 / 1024.0 AS SizeOnDiskMB,
            CASE WHEN vfs.num_of_reads = 0 THEN 0
                 ELSE (vfs.io_stall_read_ms / NULLIF(vfs.num_of_reads, 0))
            END AS AvgReadLatencyMs,
            CASE WHEN vfs.num_of_writes = 0 THEN 0
                 ELSE (vfs.io_stall_write_ms / NULLIF(vfs.num_of_writes, 0))
            END AS AvgWriteLatencyMs
        FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
        INNER JOIN sys.master_files mf
            ON vfs.database_id = mf.database_id
            AND vfs.file_id = mf.file_id

        SET @RowCount = @@ROWCOUNT

        IF @Debug = 1
        BEGIN
            EXEC dbo.DBA_LogEntry_Insert
                @ProcedureName = @ProcName,
                @ProcedureSection = 'COMPLETE',
                @IsError = 0,
                @ErrDescription = 'I/O stats collected',
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
-- P0.3: Collect Memory Utilization Baseline
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P0_Memory
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @ProcName SYSNAME = 'DBA_Collect_P0_Memory'

    BEGIN TRY
        DECLARE @PageLifeExpectancy BIGINT
        DECLARE @BufferCacheHitRatio DECIMAL(9,4)
        DECLARE @TotalServerMemoryMB BIGINT
        DECLARE @TargetServerMemoryMB BIGINT

        -- Get Page Life Expectancy
        SELECT @PageLifeExpectancy = cntr_value
        FROM sys.dm_os_performance_counters
        WHERE counter_name = 'Page life expectancy'
          AND object_name LIKE '%Buffer Node%'

        -- Get Buffer Cache Hit Ratio
        SELECT @BufferCacheHitRatio =
            (a.cntr_value * 1.0 / NULLIF(b.cntr_value, 0)) * 100.0
        FROM sys.dm_os_performance_counters a
        CROSS JOIN sys.dm_os_performance_counters b
        WHERE a.counter_name = 'Buffer cache hit ratio'
          AND b.counter_name = 'Buffer cache hit ratio base'
          AND a.object_name LIKE '%Buffer Manager%'
          AND b.object_name LIKE '%Buffer Manager%'

        -- Get Total/Target Server Memory
        SELECT @TotalServerMemoryMB = cntr_value / 1024
        FROM sys.dm_os_performance_counters
        WHERE counter_name = 'Total Server Memory (KB)'

        SELECT @TargetServerMemoryMB = cntr_value / 1024
        FROM sys.dm_os_performance_counters
        WHERE counter_name = 'Target Server Memory (KB)'

        -- Insert memory metrics
        INSERT dbo.PerfSnapshotMemory
        (
            PerfSnapshotRunID, PageLifeExpectancy, BufferCacheHitRatio,
            TotalServerMemoryMB, TargetServerMemoryMB
        )
        VALUES
        (
            @PerfSnapshotRunID,
            @PageLifeExpectancy,
            @BufferCacheHitRatio,
            @TotalServerMemoryMB,
            @TargetServerMemoryMB
        )

        -- Insert memory clerks (top 20 by size)
        INSERT dbo.PerfSnapshotMemoryClerks
        (
            PerfSnapshotRunID, ClerkType, MemoryNodeId,
            SinglePagesMB, MultiPagesMB, TotalMemoryMB
        )
        SELECT TOP 20
            @PerfSnapshotRunID,
            type AS ClerkType,
            memory_node_id,
            pages_kb / 1024.0 AS SinglePagesMB,
            0 AS MultiPagesMB,
            pages_kb / 1024.0 AS TotalMemoryMB
        FROM sys.dm_os_memory_clerks
        WHERE pages_kb > 0
        ORDER BY pages_kb DESC

        IF @Debug = 1
        BEGIN
            EXEC dbo.DBA_LogEntry_Insert
                @ProcedureName = @ProcName,
                @ProcedureSection = 'COMPLETE',
                @IsError = 0,
                @ErrDescription = 'Memory stats collected',
                @AdditionalInfo = 'PLE=' + CAST(@PageLifeExpectancy AS VARCHAR(20))
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
-- P0.4: Collect Backup Validation
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P0_BackupHistory
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @ProcName SYSNAME = 'DBA_Collect_P0_BackupHistory'
    DECLARE @NowUTC DATETIME2(3) = SYSUTCDATETIME()
    DECLARE @RowCount INT

    BEGIN TRY
        INSERT dbo.PerfSnapshotBackupHistory
        (
            PerfSnapshotRunID, DatabaseID, DatabaseName, RecoveryModel,
            LastFullBackupDate, LastDiffBackupDate, LastLogBackupDate,
            HoursSinceFullBackup, HoursSinceDiffBackup, MinutesSinceLogBackup,
            BackupRiskLevel
        )
        SELECT
            @PerfSnapshotRunID,
            d.database_id,
            d.name,
            d.recovery_model_desc,
            b.LastFullBackup,
            b.LastDiffBackup,
            b.LastLogBackup,
            DATEDIFF(HOUR, b.LastFullBackup, @NowUTC),
            DATEDIFF(HOUR, b.LastDiffBackup, @NowUTC),
            DATEDIFF(MINUTE, b.LastLogBackup, @NowUTC),
            CASE
                WHEN b.LastFullBackup IS NULL THEN 'CRITICAL'
                WHEN DATEDIFF(HOUR, b.LastFullBackup, @NowUTC) > 48 THEN 'CRITICAL'
                WHEN DATEDIFF(HOUR, b.LastFullBackup, @NowUTC) > 24 THEN 'WARNING'
                WHEN d.recovery_model_desc = 'FULL' AND DATEDIFF(MINUTE, b.LastLogBackup, @NowUTC) > 60 THEN 'WARNING'
                ELSE 'OK'
            END AS BackupRiskLevel
        FROM sys.databases d
        OUTER APPLY (
            SELECT
                MAX(CASE WHEN type = 'D' THEN backup_finish_date END) AS LastFullBackup,
                MAX(CASE WHEN type = 'I' THEN backup_finish_date END) AS LastDiffBackup,
                MAX(CASE WHEN type = 'L' THEN backup_finish_date END) AS LastLogBackup
            FROM msdb.dbo.backupset
            WHERE database_name = d.name
        ) b
        WHERE d.database_id > 4  -- Exclude system databases

        SET @RowCount = @@ROWCOUNT

        IF @Debug = 1
        BEGIN
            EXEC dbo.DBA_LogEntry_Insert
                @ProcedureName = @ProcName,
                @ProcedureSection = 'COMPLETE',
                @IsError = 0,
                @ErrDescription = 'Backup history collected',
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

PRINT 'P0 (Critical) modular collection procedures created successfully'
PRINT '  - DBA_Collect_P0_QueryStats'
PRINT '  - DBA_Collect_P0_IOStats'
PRINT '  - DBA_Collect_P0_Memory'
PRINT '  - DBA_Collect_P0_BackupHistory'
GO
