USE DBATools
GO

-- =============================================
-- Data Retention Procedure
-- Deletes snapshot data older than specified days
-- Recommended: 14-30 days retention
-- =============================================
CREATE OR ALTER PROCEDURE dbo.DBA_PurgeOldSnapshots
    @RetentionDays INT = 14,
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @ProcName SYSNAME = 'DBA_PurgeOldSnapshots'
    DECLARE @CutoffDate DATETIME2(3) = DATEADD(DAY, -@RetentionDays, SYSUTCDATETIME())
    DECLARE @DeletedRuns INT = 0
    DECLARE @DeletedRows INT = 0
    DECLARE @TotalRows INT = 0
    DECLARE @AdditionalInfo VARCHAR(4000)
    DECLARE @StartTime DATETIME2(3) = SYSUTCDATETIME()
    DECLARE @EndTime DATETIME2(3)

    BEGIN TRY
        IF @Debug = 1
        BEGIN
            PRINT '=========================================='
            PRINT 'DBA_PurgeOldSnapshots - Data Retention'
            PRINT '=========================================='
            PRINT 'Cutoff Date: ' + CAST(@CutoffDate AS VARCHAR(30))
            PRINT 'Retention: ' + CAST(@RetentionDays AS VARCHAR(10)) + ' days'
            PRINT 'Current Time: ' + CAST(@StartTime AS VARCHAR(30))
            PRINT ''
        END

        -- Get list of runs to delete
        DECLARE @RunsToDelete TABLE (PerfSnapshotRunID BIGINT)

        INSERT INTO @RunsToDelete
        SELECT PerfSnapshotRunID
        FROM dbo.PerfSnapshotRun
        WHERE SnapshotUTC < @CutoffDate

        SET @DeletedRuns = @@ROWCOUNT

        IF @DeletedRuns = 0
        BEGIN
            IF @Debug = 1
            BEGIN
                PRINT 'No snapshots older than ' + CAST(@RetentionDays AS VARCHAR(10)) + ' days found.'
                PRINT 'Nothing to purge.'
            END

            RETURN 0
        END

        IF @Debug = 1
        BEGIN
            PRINT 'Found ' + CAST(@DeletedRuns AS VARCHAR(10)) + ' snapshot runs to purge'
            PRINT ''
            PRINT 'Deleting child records...'
        END

        -- Delete child records first (in order from largest to smallest tables)

        -- 1. Workload (typically largest - multiple rows per snapshot)
        DELETE FROM dbo.PerfSnapshotWorkload WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        SET @DeletedRows = @@ROWCOUNT
        SET @TotalRows = @TotalRows + @DeletedRows
        IF @Debug = 1 PRINT '  PerfSnapshotWorkload: ' + CAST(@DeletedRows AS VARCHAR(10)) + ' rows'

        -- 2. Query Stats (TOP N queries per snapshot)
        DELETE FROM dbo.PerfSnapshotQueryStats WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        SET @DeletedRows = @@ROWCOUNT
        SET @TotalRows = @TotalRows + @DeletedRows
        IF @Debug = 1 PRINT '  PerfSnapshotQueryStats: ' + CAST(@DeletedRows AS VARCHAR(10)) + ' rows'

        -- 3. Query Plans
        DELETE FROM dbo.PerfSnapshotQueryPlans WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        SET @DeletedRows = @@ROWCOUNT
        SET @TotalRows = @TotalRows + @DeletedRows
        IF @Debug = 1 PRINT '  PerfSnapshotQueryPlans: ' + CAST(@DeletedRows AS VARCHAR(10)) + ' rows'

        -- 4. Missing Indexes
        DELETE FROM dbo.PerfSnapshotMissingIndexes WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        SET @DeletedRows = @@ROWCOUNT
        SET @TotalRows = @TotalRows + @DeletedRows
        IF @Debug = 1 PRINT '  PerfSnapshotMissingIndexes: ' + CAST(@DeletedRows AS VARCHAR(10)) + ' rows'

        -- 5. Wait Stats
        DELETE FROM dbo.PerfSnapshotWaitStats WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        SET @DeletedRows = @@ROWCOUNT
        SET @TotalRows = @TotalRows + @DeletedRows
        IF @Debug = 1 PRINT '  PerfSnapshotWaitStats: ' + CAST(@DeletedRows AS VARCHAR(10)) + ' rows'

        -- 6. Performance Counters
        DELETE FROM dbo.PerfSnapshotPerfCounters WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        SET @DeletedRows = @@ROWCOUNT
        SET @TotalRows = @TotalRows + @DeletedRows
        IF @Debug = 1 PRINT '  PerfSnapshotPerfCounters: ' + CAST(@DeletedRows AS VARCHAR(10)) + ' rows'

        -- 7. I/O Stats (one row per file)
        DELETE FROM dbo.PerfSnapshotIOStats WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        SET @DeletedRows = @@ROWCOUNT
        SET @TotalRows = @TotalRows + @DeletedRows
        IF @Debug = 1 PRINT '  PerfSnapshotIOStats: ' + CAST(@DeletedRows AS VARCHAR(10)) + ' rows'

        -- 8. Index Usage
        DELETE FROM dbo.PerfSnapshotIndexUsage WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        SET @DeletedRows = @@ROWCOUNT
        SET @TotalRows = @TotalRows + @DeletedRows
        IF @Debug = 1 PRINT '  PerfSnapshotIndexUsage: ' + CAST(@DeletedRows AS VARCHAR(10)) + ' rows'

        -- 9. Database Stats
        DELETE FROM dbo.PerfSnapshotDB WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        SET @DeletedRows = @@ROWCOUNT
        SET @TotalRows = @TotalRows + @DeletedRows
        IF @Debug = 1 PRINT '  PerfSnapshotDB: ' + CAST(@DeletedRows AS VARCHAR(10)) + ' rows'

        -- 10. VLF Counts
        DELETE FROM dbo.PerfSnapshotVLFCounts WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        SET @DeletedRows = @@ROWCOUNT
        SET @TotalRows = @TotalRows + @DeletedRows
        IF @Debug = 1 PRINT '  PerfSnapshotVLFCounts: ' + CAST(@DeletedRows AS VARCHAR(10)) + ' rows'

        -- 11. Backup History
        DELETE FROM dbo.PerfSnapshotBackupHistory WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        SET @DeletedRows = @@ROWCOUNT
        SET @TotalRows = @TotalRows + @DeletedRows
        IF @Debug = 1 PRINT '  PerfSnapshotBackupHistory: ' + CAST(@DeletedRows AS VARCHAR(10)) + ' rows'

        -- 12. Error Log
        DELETE FROM dbo.PerfSnapshotErrorLog WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        SET @DeletedRows = @@ROWCOUNT
        SET @TotalRows = @TotalRows + @DeletedRows
        IF @Debug = 1 PRINT '  PerfSnapshotErrorLog: ' + CAST(@DeletedRows AS VARCHAR(10)) + ' rows'

        -- 13. Memory
        DELETE FROM dbo.PerfSnapshotMemory WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        SET @DeletedRows = @@ROWCOUNT
        SET @TotalRows = @TotalRows + @DeletedRows
        IF @Debug = 1 PRINT '  PerfSnapshotMemory: ' + CAST(@DeletedRows AS VARCHAR(10)) + ' rows'

        -- 14. Memory Clerks
        DELETE FROM dbo.PerfSnapshotMemoryClerks WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        SET @DeletedRows = @@ROWCOUNT
        SET @TotalRows = @TotalRows + @DeletedRows
        IF @Debug = 1 PRINT '  PerfSnapshotMemoryClerks: ' + CAST(@DeletedRows AS VARCHAR(10)) + ' rows'

        -- 15. TempDB Contention
        DELETE FROM dbo.PerfSnapshotTempDBContention WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        SET @DeletedRows = @@ROWCOUNT
        SET @TotalRows = @TotalRows + @DeletedRows
        IF @Debug = 1 PRINT '  PerfSnapshotTempDBContention: ' + CAST(@DeletedRows AS VARCHAR(10)) + ' rows'

        -- 16. Server Config
        DELETE FROM dbo.PerfSnapshotServerConfig WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        SET @DeletedRows = @@ROWCOUNT
        SET @TotalRows = @TotalRows + @DeletedRows
        IF @Debug = 1 PRINT '  PerfSnapshotServerConfig: ' + CAST(@DeletedRows AS VARCHAR(10)) + ' rows'

        -- 17. Deadlock Details
        DELETE FROM dbo.PerfSnapshotDeadlockDetails WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        SET @DeletedRows = @@ROWCOUNT
        SET @TotalRows = @TotalRows + @DeletedRows
        IF @Debug = 1 PRINT '  PerfSnapshotDeadlockDetails: ' + CAST(@DeletedRows AS VARCHAR(10)) + ' rows'

        -- 18. Scheduler Health
        DELETE FROM dbo.PerfSnapshotSchedulerHealth WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        SET @DeletedRows = @@ROWCOUNT
        SET @TotalRows = @TotalRows + @DeletedRows
        IF @Debug = 1 PRINT '  PerfSnapshotSchedulerHealth: ' + CAST(@DeletedRows AS VARCHAR(10)) + ' rows'

        -- 19. Autogrowth Events
        DELETE FROM dbo.PerfSnapshotAutogrowthEvents WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        SET @DeletedRows = @@ROWCOUNT
        SET @TotalRows = @TotalRows + @DeletedRows
        IF @Debug = 1 PRINT '  PerfSnapshotAutogrowthEvents: ' + CAST(@DeletedRows AS VARCHAR(10)) + ' rows'

        -- 20. Latch Stats
        DELETE FROM dbo.PerfSnapshotLatchStats WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        SET @DeletedRows = @@ROWCOUNT
        SET @TotalRows = @TotalRows + @DeletedRows
        IF @Debug = 1 PRINT '  PerfSnapshotLatchStats: ' + CAST(@DeletedRows AS VARCHAR(10)) + ' rows'

        -- 21. Job History
        DELETE FROM dbo.PerfSnapshotJobHistory WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        SET @DeletedRows = @@ROWCOUNT
        SET @TotalRows = @TotalRows + @DeletedRows
        IF @Debug = 1 PRINT '  PerfSnapshotJobHistory: ' + CAST(@DeletedRows AS VARCHAR(10)) + ' rows'

        -- 22. Spinlock Stats
        DELETE FROM dbo.PerfSnapshotSpinlockStats WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        SET @DeletedRows = @@ROWCOUNT
        SET @TotalRows = @TotalRows + @DeletedRows
        IF @Debug = 1 PRINT '  PerfSnapshotSpinlockStats: ' + CAST(@DeletedRows AS VARCHAR(10)) + ' rows'

        IF @Debug = 1
        BEGIN
            PRINT ''
            PRINT 'Deleting parent records...'
        END

        -- Finally, delete parent records
        DELETE FROM dbo.PerfSnapshotRun WHERE PerfSnapshotRunID IN (SELECT PerfSnapshotRunID FROM @RunsToDelete)
        IF @Debug = 1 PRINT '  PerfSnapshotRun: ' + CAST(@DeletedRuns AS VARCHAR(10)) + ' rows'

        SET @EndTime = SYSUTCDATETIME()

        SET @AdditionalInfo = 'Retention=' + CAST(@RetentionDays AS VARCHAR(10)) + ' days, '
                            + 'Runs=' + CAST(@DeletedRuns AS VARCHAR(10)) + ', '
                            + 'TotalRows=' + CAST(@TotalRows AS VARCHAR(10)) + ', '
                            + 'Duration=' + CAST(DATEDIFF(MILLISECOND, @StartTime, @EndTime) AS VARCHAR(10)) + 'ms'

        -- Log success
        EXEC dbo.DBA_LogEntry_Insert
            @ProcedureName = @ProcName,
            @ProcedureSection = 'COMPLETE',
            @IsError = 0,
            @ErrDescription = 'Purge completed successfully',
            @AdditionalInfo = @AdditionalInfo

        IF @Debug = 1
        BEGIN
            PRINT ''
            PRINT '=========================================='
            PRINT 'Purge Summary:'
            PRINT '  Snapshot Runs Deleted: ' + CAST(@DeletedRuns AS VARCHAR(10))
            PRINT '  Total Rows Deleted: ' + CAST(@TotalRows AS VARCHAR(10))
            PRINT '  Duration: ' + CAST(DATEDIFF(MILLISECOND, @StartTime, @EndTime) AS VARCHAR(10)) + ' ms'
            PRINT '=========================================='
        END

        RETURN 0
    END TRY
    BEGIN CATCH
        DECLARE @ErrMessage NVARCHAR(4000) = ERROR_MESSAGE()
        DECLARE @ErrNumber INT = ERROR_NUMBER()
        DECLARE @ErrSeverity INT = ERROR_SEVERITY()
        DECLARE @ErrState INT = ERROR_STATE()
        DECLARE @ErrLine INT = ERROR_LINE()

        EXEC dbo.DBA_LogEntry_Insert
            @ProcedureName = @ProcName,
            @ProcedureSection = 'ERROR',
            @IsError = 1,
            @ErrDescription = @ErrMessage,
            @ErrNumber = @ErrNumber,
            @ErrSeverity = @ErrSeverity,
            @ErrState = @ErrState,
            @ErrLine = @ErrLine

        IF @Debug = 1
        BEGIN
            PRINT ''
            PRINT 'ERROR during purge:'
            PRINT '  Message: ' + @ErrMessage
            PRINT '  Number: ' + CAST(@ErrNumber AS VARCHAR(10))
            PRINT '  Line: ' + CAST(@ErrLine AS VARCHAR(10))
        END

        RETURN -1
    END CATCH
END
GO

PRINT ''
PRINT '=========================================='
PRINT 'Retention Policy Procedure Created'
PRINT '=========================================='
PRINT 'Procedure: dbo.DBA_PurgeOldSnapshots'
PRINT 'Default Retention: 14 days'
PRINT ''
PRINT 'Usage Examples:'
PRINT '  -- Purge with 14-day retention (default)'
PRINT '  EXEC dbo.DBA_PurgeOldSnapshots'
PRINT ''
PRINT '  -- Purge with 30-day retention'
PRINT '  EXEC dbo.DBA_PurgeOldSnapshots @RetentionDays = 30'
PRINT ''
PRINT '  -- Purge with verbose output'
PRINT '  EXEC dbo.DBA_PurgeOldSnapshots @RetentionDays = 14, @Debug = 1'
PRINT '=========================================='
GO
