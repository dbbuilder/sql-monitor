USE [DBATools]
GO

-- =============================================
-- Data Retention / Purge Procedure (FIXED)
-- =============================================

CREATE OR ALTER PROCEDURE dbo.DBA_PurgeOldSnapshots
    @RetentionDays INT = NULL,  -- NULL = use config
    @Debug BIT = 0,
    @DeleteBatchSize INT = 5000
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @ProcName SYSNAME = 'DBA_PurgeOldSnapshots'
    DECLARE @AdditionalInfo VARCHAR(4000)

    -- Get retention from config if not specified
    IF @RetentionDays IS NULL
        SET @RetentionDays = dbo.fn_GetConfigInt('RetentionDays')

    DECLARE @CutoffDate DATETIME2(3) = DATEADD(DAY, -@RetentionDays, SYSUTCDATETIME())
    DECLARE @RowsDeleted INT = 0
    DECLARE @TotalRowsDeleted INT = 0
    DECLARE @RunIDsToPurge TABLE (PerfSnapshotRunID BIGINT)

    BEGIN TRY
        -- Identify runs to purge
        INSERT INTO @RunIDsToPurge (PerfSnapshotRunID)
        SELECT PerfSnapshotRunID FROM dbo.PerfSnapshotRun
        WHERE SnapshotUTC < @CutoffDate

        DECLARE @RunCount INT = (SELECT COUNT(*) FROM @RunIDsToPurge)

        IF @Debug = 1
        BEGIN
            PRINT 'Purging snapshots older than: ' + CONVERT(VARCHAR(30), @CutoffDate, 121)
            SET @AdditionalInfo = 'Runs=' + CAST(@RunCount AS VARCHAR(20))
            PRINT 'Snapshot runs to purge: ' + CAST(@RunCount AS VARCHAR(20))
        END

        IF @RunCount = 0
        BEGIN
            IF @Debug = 1 PRINT 'No snapshots to purge'
            RETURN 0
        END

        -- P3 Tables
        WHILE 1 = 1 BEGIN
            DELETE TOP (@DeleteBatchSize) FROM dbo.PerfSnapshotLatchStats
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)
            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1 BEGIN
            DELETE TOP (@DeleteBatchSize) FROM dbo.PerfSnapshotJobHistory
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)
            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1 BEGIN
            DELETE TOP (@DeleteBatchSize) FROM dbo.PerfSnapshotSpinlockStats
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)
            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        -- P2 Tables
        WHILE 1 = 1 BEGIN
            DELETE TOP (@DeleteBatchSize) FROM dbo.PerfSnapshotConfig
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)
            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1 BEGIN
            DELETE TOP (@DeleteBatchSize) FROM dbo.PerfSnapshotDeadlocks
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)
            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1 BEGIN
            DELETE TOP (@DeleteBatchSize) FROM dbo.PerfSnapshotSchedulers
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)
            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1 BEGIN
            DELETE TOP (@DeleteBatchSize) FROM dbo.PerfSnapshotCounters
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)
            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1 BEGIN
            DELETE TOP (@DeleteBatchSize) FROM dbo.PerfSnapshotAutogrowthEvents
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)
            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        -- P1 Tables (typically largest)
        WHILE 1 = 1 BEGIN
            DELETE TOP (@DeleteBatchSize) FROM dbo.PerfSnapshotIndexUsage
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)
            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1 BEGIN
            DELETE TOP (@DeleteBatchSize) FROM dbo.PerfSnapshotMissingIndexes
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)
            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1 BEGIN
            DELETE TOP (@DeleteBatchSize) FROM dbo.PerfSnapshotWaitStats
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)
            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1 BEGIN
            DELETE TOP (@DeleteBatchSize) FROM dbo.PerfSnapshotTempDBContention
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)
            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1 BEGIN
            DELETE TOP (@DeleteBatchSize) FROM dbo.PerfSnapshotQueryPlans
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)
            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        -- P0 Tables
        WHILE 1 = 1 BEGIN
            DELETE TOP (@DeleteBatchSize) FROM dbo.PerfSnapshotQueryStats
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)
            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1 BEGIN
            DELETE TOP (@DeleteBatchSize) FROM dbo.PerfSnapshotIOStats
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)
            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1 BEGIN
            DELETE TOP (@DeleteBatchSize) FROM dbo.PerfSnapshotMemory
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)
            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1 BEGIN
            DELETE TOP (@DeleteBatchSize) FROM dbo.PerfSnapshotMemoryClerks
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)
            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1 BEGIN
            DELETE TOP (@DeleteBatchSize) FROM dbo.PerfSnapshotBackupHistory
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)
            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        -- Original Tables
        WHILE 1 = 1 BEGIN
            DELETE TOP (@DeleteBatchSize) FROM dbo.PerfSnapshotDB
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)
            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1 BEGIN
            DELETE TOP (@DeleteBatchSize) FROM dbo.PerfSnapshotWorkload
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)
            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1 BEGIN
            DELETE TOP (@DeleteBatchSize) FROM dbo.PerfSnapshotErrorLog
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)
            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        -- Finally, delete parent rows
        DELETE FROM dbo.PerfSnapshotRun
        WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)

        SET @TotalRowsDeleted = @TotalRowsDeleted + @@ROWCOUNT

        IF @Debug = 1
        BEGIN
            PRINT 'Purge completed successfully'
            PRINT 'Total rows deleted: ' + CAST(@TotalRowsDeleted AS VARCHAR(20))
        END

        -- Log the purge operation
        SET @AdditionalInfo = 'Runs=' + CAST(@RunCount AS VARCHAR(20)) + ', TotalRows=' + CAST(@TotalRowsDeleted AS VARCHAR(20)) + ', RetentionDays=' + CAST(@RetentionDays AS VARCHAR(10))
        EXEC dbo.DBA_LogEntry_Insert @ProcName, 'PURGE', 0, 'Purged old snapshots', @AdditionalInfo = @AdditionalInfo

        RETURN 0

    END TRY
    BEGIN CATCH
        DECLARE @ErrMessage NVARCHAR(4000) = ERROR_MESSAGE()
        DECLARE @ErrNumber INT = ERROR_NUMBER()
        DECLARE @ErrSeverity INT = ERROR_SEVERITY()
        DECLARE @ErrState INT = ERROR_STATE()
        DECLARE @ErrLine INT = ERROR_LINE()

        SET @AdditionalInfo = 'Error during purge'
        EXEC dbo.DBA_LogEntry_Insert @ProcName, 'ERROR', 1, @ErrMessage,
            @ErrNumber = @ErrNumber, @ErrSeverity = @ErrSeverity,
            @ErrState = @ErrState, @ErrLine = @ErrLine,
            @AdditionalInfo = @AdditionalInfo

        RETURN -1
    END CATCH
END
GO

PRINT 'Purge procedure created successfully - FIXED'
PRINT 'Config Integration: Reads RetentionDays from config if not specified'
PRINT 'Usage: EXEC DBA_PurgeOldSnapshots @Debug = 1  -- Uses config'
PRINT '       EXEC DBA_PurgeOldSnapshots @RetentionDays = 60, @Debug = 1'
GO
