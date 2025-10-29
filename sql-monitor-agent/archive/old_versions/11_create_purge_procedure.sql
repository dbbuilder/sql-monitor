USE [DBATools]
GO

-- =============================================
-- Data Retention / Purge Procedure
-- Removes old snapshot data based on retention policy
-- =============================================

CREATE OR ALTER PROCEDURE dbo.DBA_PurgeOldSnapshots
    @RetentionDays INT = 30,
    @Debug BIT = 0,
    @DeleteBatchSize INT = 5000
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @ProcName SYSNAME = 'DBA_PurgeOldSnapshots'
    DECLARE @CutoffDate DATETIME2(3) = DATEADD(DAY, -@RetentionDays, SYSUTCDATETIME())
    DECLARE @RowsDeleted INT = 0
    DECLARE @TotalRowsDeleted INT = 0
    DECLARE @RunIDsToPurge TABLE (PerfSnapshotRunID BIGINT)

    BEGIN TRY
        -- Identify runs to purge
        INSERT INTO @RunIDsToPurge (PerfSnapshotRunID)
        SELECT PerfSnapshotRunID
        FROM dbo.PerfSnapshotRun
        WHERE SnapshotUTC < @CutoffDate

        DECLARE @RunCount INT = (SELECT COUNT(*) FROM @RunIDsToPurge)

        IF @Debug = 1
        BEGIN
            PRINT 'Purging snapshots older than: ' + CONVERT(VARCHAR(30), @CutoffDate, 121)
            PRINT 'Snapshot runs to purge: ' + CAST(@RunCount AS VARCHAR(20))
        END

        IF @RunCount = 0
        BEGIN
            IF @Debug = 1
                PRINT 'No snapshots to purge'
            RETURN 0
        END

        -- Purge child tables in batches (to avoid long transactions)

        -- P3 Tables
        WHILE 1 = 1
        BEGIN
            DELETE TOP (@DeleteBatchSize) psls
            FROM dbo.PerfSnapshotLatchStats psls
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)

            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1
        BEGIN
            DELETE TOP (@DeleteBatchSize) psjh
            FROM dbo.PerfSnapshotJobHistory psjh
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)

            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1
        BEGIN
            DELETE TOP (@DeleteBatchSize) psss
            FROM dbo.PerfSnapshotSpinlockStats psss
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)

            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        -- P2 Tables
        WHILE 1 = 1
        BEGIN
            DELETE TOP (@DeleteBatchSize) psc
            FROM dbo.PerfSnapshotConfig psc
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)

            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1
        BEGIN
            DELETE TOP (@DeleteBatchSize) psd
            FROM dbo.PerfSnapshotDeadlocks psd
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)

            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1
        BEGIN
            DELETE TOP (@DeleteBatchSize) pss
            FROM dbo.PerfSnapshotSchedulers pss
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)

            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1
        BEGIN
            DELETE TOP (@DeleteBatchSize) psc
            FROM dbo.PerfSnapshotCounters psc
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)

            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1
        BEGIN
            DELETE TOP (@DeleteBatchSize) psae
            FROM dbo.PerfSnapshotAutogrowthEvents psae
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)

            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        -- P1 Tables (typically largest)
        WHILE 1 = 1
        BEGIN
            DELETE TOP (@DeleteBatchSize) psiu
            FROM dbo.PerfSnapshotIndexUsage psiu
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)

            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1
        BEGIN
            DELETE TOP (@DeleteBatchSize) psmi
            FROM dbo.PerfSnapshotMissingIndexes psmi
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)

            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1
        BEGIN
            DELETE TOP (@DeleteBatchSize) psws
            FROM dbo.PerfSnapshotWaitStats psws
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)

            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1
        BEGIN
            DELETE TOP (@DeleteBatchSize) pstd
            FROM dbo.PerfSnapshotTempDBContention pstd
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)

            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1
        BEGIN
            DELETE TOP (@DeleteBatchSize) psqp
            FROM dbo.PerfSnapshotQueryPlans psqp
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)

            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        -- P0 Tables
        WHILE 1 = 1
        BEGIN
            DELETE TOP (@DeleteBatchSize) psqs
            FROM dbo.PerfSnapshotQueryStats psqs
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)

            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1
        BEGIN
            DELETE TOP (@DeleteBatchSize) psio
            FROM dbo.PerfSnapshotIOStats psio
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)

            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1
        BEGIN
            DELETE TOP (@DeleteBatchSize) psm
            FROM dbo.PerfSnapshotMemory psm
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)

            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1
        BEGIN
            DELETE TOP (@DeleteBatchSize) psmc
            FROM dbo.PerfSnapshotMemoryClerks psmc
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)

            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1
        BEGIN
            DELETE TOP (@DeleteBatchSize) psbh
            FROM dbo.PerfSnapshotBackupHistory psbh
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)

            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        -- Original Tables
        WHILE 1 = 1
        BEGIN
            DELETE TOP (@DeleteBatchSize) psdb
            FROM dbo.PerfSnapshotDB psdb
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)

            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1
        BEGIN
            DELETE TOP (@DeleteBatchSize) psw
            FROM dbo.PerfSnapshotWorkload psw
            WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunIDsToPurge)

            SET @RowsDeleted = @@ROWCOUNT
            SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted
            IF @RowsDeleted = 0 BREAK
        END

        WHILE 1 = 1
        BEGIN
            DELETE TOP (@DeleteBatchSize) psel
            FROM dbo.PerfSnapshotErrorLog psel
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
        EXEC dbo.DBA_LogEntry_Insert
            @ProcedureName = @ProcName,
            @ProcedureSection = 'PURGE',
            @IsError = 0,
            @ErrDescription = 'Purged old snapshots',
            @AdditionalInfo = 'Runs=' + CAST(@RunCount AS VARCHAR(20)) +
                              ', TotalRows=' + CAST(@TotalRowsDeleted AS VARCHAR(20)) +
                              ', RetentionDays=' + CAST(@RetentionDays AS VARCHAR(10))

        RETURN 0

    END TRY
    BEGIN CATCH
        DECLARE @ErrNumber BIGINT = ERROR_NUMBER()
        DECLARE @ErrSeverity INT = ERROR_SEVERITY()
        DECLARE @ErrState INT = ERROR_STATE()
        DECLARE @ErrLine INT = ERROR_LINE()
        DECLARE @ErrProcedure SYSNAME = ERROR_PROCEDURE()
        DECLARE @ErrDescription VARCHAR(2000) = ERROR_MESSAGE()

        EXEC dbo.DBA_LogEntry_Insert
            @ProcedureName = @ProcName,
            @ProcedureSection = 'ERROR',
            @IsError = 1,
            @ErrDescription = @ErrDescription,
            @ErrNumber = @ErrNumber,
            @ErrSeverity = @ErrSeverity,
            @ErrState = @ErrState,
            @ErrLine = @ErrLine,
            @ErrProcedure = @ErrProcedure

        DECLARE @ReThrowMessage NVARCHAR(4000) =
            'Error in ' + @ProcName + ': ' + @ErrDescription

        RAISERROR (@ReThrowMessage, 16, 1)

        RETURN -1
    END CATCH
END
GO

PRINT 'Purge procedure created successfully: DBA_PurgeOldSnapshots'
PRINT 'Default retention: 30 days'
PRINT 'Call with: EXEC DBATools.dbo.DBA_PurgeOldSnapshots @RetentionDays = 30, @Debug = 1'
GO
