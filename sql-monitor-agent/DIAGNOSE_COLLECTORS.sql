USE DBATools
GO

-- =============================================
-- Diagnostic Script: Test Each Collector Individually
-- Identifies which collectors are slow/hanging
-- =============================================

PRINT '=========================================='
PRINT 'Collector Performance Diagnostic'
PRINT 'Testing each collector with a fake RunID'
PRINT '=========================================='
PRINT ''

-- Create a fake snapshot run for testing
DECLARE @TestRunID BIGINT
INSERT INTO dbo.PerfSnapshotRun (SnapshotUTC, ServerName)
VALUES (SYSUTCDATETIME(), @@SERVERNAME)
SET @TestRunID = SCOPE_IDENTITY()

PRINT 'Created test PerfSnapshotRunID: ' + CAST(@TestRunID AS VARCHAR(20))
PRINT ''
PRINT 'Testing collectors...'
PRINT '----------------------------------------'

-- P0.1: Query Stats
DECLARE @StartTime DATETIME2(3), @EndTime DATETIME2(3), @Duration INT

SET @StartTime = SYSUTCDATETIME()
BEGIN TRY
    EXEC DBA_Collect_P0_QueryStats @TestRunID, 0
    SET @EndTime = SYSUTCDATETIME()
    SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime)
    PRINT '[OK] P0_QueryStats: ' + CAST(@Duration AS VARCHAR(10)) + ' ms'
END TRY
BEGIN CATCH
    SET @EndTime = SYSUTCDATETIME()
    SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime)
    PRINT '[ERROR] P0_QueryStats: ' + ERROR_MESSAGE() + ' (' + CAST(@Duration AS VARCHAR(10)) + ' ms)'
END CATCH

-- P0.2: I/O Stats
SET @StartTime = SYSUTCDATETIME()
BEGIN TRY
    EXEC DBA_Collect_P0_IOStats @TestRunID, 0
    SET @EndTime = SYSUTCDATETIME()
    SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime)
    PRINT '[OK] P0_IOStats: ' + CAST(@Duration AS VARCHAR(10)) + ' ms'
END TRY
BEGIN CATCH
    SET @EndTime = SYSUTCDATETIME()
    SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime)
    PRINT '[ERROR] P0_IOStats: ' + ERROR_MESSAGE() + ' (' + CAST(@Duration AS VARCHAR(10)) + ' ms)'
END CATCH

-- P0.3: Memory
SET @StartTime = SYSUTCDATETIME()
BEGIN TRY
    EXEC DBA_Collect_P0_Memory @TestRunID, 0
    SET @EndTime = SYSUTCDATETIME()
    SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime)
    PRINT '[OK] P0_Memory: ' + CAST(@Duration AS VARCHAR(10)) + ' ms'
END TRY
BEGIN CATCH
    SET @EndTime = SYSUTCDATETIME()
    SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime)
    PRINT '[ERROR] P0_Memory: ' + ERROR_MESSAGE() + ' (' + CAST(@Duration AS VARCHAR(10)) + ' ms)'
END CATCH

-- P0.4: Backup History
SET @StartTime = SYSUTCDATETIME()
BEGIN TRY
    EXEC DBA_Collect_P0_BackupHistory @TestRunID, 0
    SET @EndTime = SYSUTCDATETIME()
    SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime)
    PRINT '[OK] P0_BackupHistory: ' + CAST(@Duration AS VARCHAR(10)) + ' ms'
END TRY
BEGIN CATCH
    SET @EndTime = SYSUTCDATETIME()
    SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime)
    PRINT '[ERROR] P0_BackupHistory: ' + ERROR_MESSAGE() + ' (' + CAST(@Duration AS VARCHAR(10)) + ' ms)'
END CATCH

-- P1.6: Index Usage
SET @StartTime = SYSUTCDATETIME()
BEGIN TRY
    EXEC DBA_Collect_P1_IndexUsage @TestRunID, 0
    SET @EndTime = SYSUTCDATETIME()
    SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime)
    PRINT '[OK] P1_IndexUsage: ' + CAST(@Duration AS VARCHAR(10)) + ' ms'
END TRY
BEGIN CATCH
    SET @EndTime = SYSUTCDATETIME()
    SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime)
    PRINT '[ERROR] P1_IndexUsage: ' + ERROR_MESSAGE() + ' (' + CAST(@Duration AS VARCHAR(10)) + ' ms)'
END CATCH

-- P1.7: Missing Indexes
SET @StartTime = SYSUTCDATETIME()
BEGIN TRY
    EXEC DBA_Collect_P1_MissingIndexes @TestRunID, 0
    SET @EndTime = SYSUTCDATETIME()
    SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime)
    PRINT '[OK] P1_MissingIndexes: ' + CAST(@Duration AS VARCHAR(10)) + ' ms'
END TRY
BEGIN CATCH
    SET @EndTime = SYSUTCDATETIME()
    SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime)
    PRINT '[ERROR] P1_MissingIndexes: ' + ERROR_MESSAGE() + ' (' + CAST(@Duration AS VARCHAR(10)) + ' ms)'
END CATCH

-- P1.8: Wait Stats
SET @StartTime = SYSUTCDATETIME()
BEGIN TRY
    EXEC DBA_Collect_P1_WaitStats @TestRunID, 0
    SET @EndTime = SYSUTCDATETIME()
    SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime)
    PRINT '[OK] P1_WaitStats: ' + CAST(@Duration AS VARCHAR(10)) + ' ms'
END TRY
BEGIN CATCH
    SET @EndTime = SYSUTCDATETIME()
    SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime)
    PRINT '[ERROR] P1_WaitStats: ' + ERROR_MESSAGE() + ' (' + CAST(@Duration AS VARCHAR(10)) + ' ms)'
END CATCH

-- P1.9: TempDB Contention
SET @StartTime = SYSUTCDATETIME()
BEGIN TRY
    EXEC DBA_Collect_P1_TempDBContention @TestRunID, 0
    SET @EndTime = SYSUTCDATETIME()
    SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime)
    PRINT '[OK] P1_TempDBContention: ' + CAST(@Duration AS VARCHAR(10)) + ' ms'
END TRY
BEGIN CATCH
    SET @EndTime = SYSUTCDATETIME()
    SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime)
    PRINT '[ERROR] P1_TempDBContention: ' + ERROR_MESSAGE() + ' (' + CAST(@Duration AS VARCHAR(10)) + ' ms)'
END CATCH

-- P1.10: Query Plans
SET @StartTime = SYSUTCDATETIME()
BEGIN TRY
    EXEC DBA_Collect_P1_QueryPlans @TestRunID, 0
    SET @EndTime = SYSUTCDATETIME()
    SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime)
    PRINT '[OK] P1_QueryPlans: ' + CAST(@Duration AS VARCHAR(10)) + ' ms'
END TRY
BEGIN CATCH
    SET @EndTime = SYSUTCDATETIME()
    SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime)
    PRINT '[ERROR] P1_QueryPlans: ' + ERROR_MESSAGE() + ' (' + CAST(@Duration AS VARCHAR(10)) + ' ms)'
END CATCH

PRINT ''
PRINT '----------------------------------------'
PRINT 'Diagnostic complete!'
PRINT ''
PRINT 'Cleaning up test data...'

-- Clean up test data
DELETE FROM dbo.PerfSnapshotQueryStats WHERE PerfSnapshotRunID = @TestRunID
DELETE FROM dbo.PerfSnapshotIOStats WHERE PerfSnapshotRunID = @TestRunID
DELETE FROM dbo.PerfSnapshotMemory WHERE PerfSnapshotRunID = @TestRunID
DELETE FROM dbo.PerfSnapshotBackupHistory WHERE PerfSnapshotRunID = @TestRunID
DELETE FROM dbo.PerfSnapshotIndexUsage WHERE PerfSnapshotRunID = @TestRunID
DELETE FROM dbo.PerfSnapshotMissingIndexes WHERE PerfSnapshotRunID = @TestRunID
DELETE FROM dbo.PerfSnapshotWaitStats WHERE PerfSnapshotRunID = @TestRunID
DELETE FROM dbo.PerfSnapshotTempDBContention WHERE PerfSnapshotRunID = @TestRunID
DELETE FROM dbo.PerfSnapshotQueryPlans WHERE PerfSnapshotRunID = @TestRunID
DELETE FROM dbo.PerfSnapshotRun WHERE PerfSnapshotRunID = @TestRunID

PRINT 'Test data cleaned up.'
PRINT '=========================================='
GO
