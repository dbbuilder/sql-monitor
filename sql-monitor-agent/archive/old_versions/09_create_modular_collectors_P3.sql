USE [DBATools]
GO

-- =============================================
-- P3 LOW PRIORITY - Modular Collectors
-- =============================================

-- =============================================
-- P3.18: Collect Latch Statistics
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P3_LatchStats
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @ProcName SYSNAME = 'DBA_Collect_P3_LatchStats'
    DECLARE @RowCount INT

    BEGIN TRY
        INSERT dbo.PerfSnapshotLatchStats
        (
            PerfSnapshotRunID, LatchClass, WaitingRequestsCount,
            WaitTimeMs, MaxWaitTimeMs, AvgWaitTimeMs
        )
        SELECT TOP 50
            @PerfSnapshotRunID,
            latch_class,
            waiting_requests_count,
            wait_time_ms,
            max_wait_time_ms,
            CASE WHEN waiting_requests_count = 0 THEN 0
                 ELSE wait_time_ms / NULLIF(waiting_requests_count, 0)
            END AS AvgWaitTimeMs
        FROM sys.dm_os_latch_stats
        WHERE wait_time_ms > 0
        ORDER BY wait_time_ms DESC

        SET @RowCount = @@ROWCOUNT

        IF @Debug = 1
        BEGIN
            EXEC dbo.DBA_LogEntry_Insert
                @ProcedureName = @ProcName,
                @ProcedureSection = 'COMPLETE',
                @IsError = 0,
                @ErrDescription = 'Latch statistics collected',
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
-- P3.19: Collect SQL Agent Job History
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P3_JobHistory
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @ProcName SYSNAME = 'DBA_Collect_P3_JobHistory'
    DECLARE @RowCount INT
    DECLARE @NowUTC DATETIME2(3) = SYSUTCDATETIME()

    BEGIN TRY
        INSERT dbo.PerfSnapshotJobHistory
        (
            PerfSnapshotRunID, JobID, JobName, IsEnabled,
            LastRunDate, LastRunOutcome, LastRunDurationSeconds,
            FailureCountLast24Hours
        )
        SELECT
            @PerfSnapshotRunID,
            j.job_id,
            j.name AS JobName,
            j.enabled AS IsEnabled,
            CASE WHEN h.LastRunDate = 0 THEN NULL
                 ELSE CAST(CAST(h.LastRunDate AS VARCHAR(8)) + ' ' +
                      STUFF(STUFF(RIGHT('000000' + CAST(h.LastRunTime AS VARCHAR(6)), 6), 5, 0, ':'), 3, 0, ':') AS DATETIME2(3))
            END AS LastRunDate,
            h.LastRunOutcome,
            h.LastRunDuration AS LastRunDurationSeconds,
            (
                SELECT COUNT(*)
                FROM msdb.dbo.sysjobhistory jh
                WHERE jh.job_id = j.job_id
                  AND jh.run_status = 0  -- Failed
                  AND jh.run_date >= CAST(CONVERT(VARCHAR(8), DATEADD(DAY, -1, GETDATE()), 112) AS INT)
            ) AS FailureCountLast24Hours
        FROM msdb.dbo.sysjobs j
        OUTER APPLY (
            SELECT TOP 1
                run_date AS LastRunDate,
                run_time AS LastRunTime,
                run_status AS LastRunOutcome,
                run_duration AS LastRunDuration
            FROM msdb.dbo.sysjobhistory
            WHERE job_id = j.job_id
              AND step_id = 0  -- Job outcome row
            ORDER BY run_date DESC, run_time DESC
        ) h

        SET @RowCount = @@ROWCOUNT

        IF @Debug = 1
        BEGIN
            EXEC dbo.DBA_LogEntry_Insert
                @ProcedureName = @ProcName,
                @ProcedureSection = 'COMPLETE',
                @IsError = 0,
                @ErrDescription = 'Job history collected',
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
-- P3.21: Collect Spinlock Statistics
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_Collect_P3_SpinlockStats
    @PerfSnapshotRunID BIGINT,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @ProcName SYSNAME = 'DBA_Collect_P3_SpinlockStats'
    DECLARE @RowCount INT

    BEGIN TRY
        INSERT dbo.PerfSnapshotSpinlockStats
        (
            PerfSnapshotRunID, SpinlockName, Collisions, Spins,
            SpinsPerCollision, SleepTime, Backoffs
        )
        SELECT TOP 50
            @PerfSnapshotRunID,
            name AS SpinlockName,
            collisions,
            spins,
            spins_per_collision AS SpinsPerCollision,
            sleep_time AS SleepTime,
            backoffs
        FROM sys.dm_os_spinlock_stats
        WHERE collisions > 0
        ORDER BY collisions DESC

        SET @RowCount = @@ROWCOUNT

        IF @Debug = 1
        BEGIN
            EXEC dbo.DBA_LogEntry_Insert
                @ProcedureName = @ProcName,
                @ProcedureSection = 'COMPLETE',
                @IsError = 0,
                @ErrDescription = 'Spinlock statistics collected',
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

PRINT 'P3 (Low) modular collection procedures created successfully'
PRINT '  - DBA_Collect_P3_LatchStats'
PRINT '  - DBA_Collect_P3_JobHistory'
PRINT '  - DBA_Collect_P3_SpinlockStats'
GO
