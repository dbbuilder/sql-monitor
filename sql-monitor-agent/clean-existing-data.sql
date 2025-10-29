-- =============================================
-- Clean NULL Characters from Existing Data
-- Purpose: Remove CHAR(0) from already-collected data
-- =============================================

USE DBATools
GO

PRINT 'Cleaning NULL characters from existing data...'
PRINT ''

DECLARE @RowsAffected INT = 0

-- Clean PerfSnapshotRun
PRINT 'Cleaning PerfSnapshotRun.TopWaitType...'
UPDATE PerfSnapshotRun
SET TopWaitType = REPLACE(TopWaitType, CHAR(0), '')
WHERE TopWaitType LIKE '%' + CHAR(0) + '%'
SET @RowsAffected = @@ROWCOUNT
PRINT '  Rows updated: ' + CAST(@RowsAffected AS VARCHAR(10))

-- Clean PerfSnapshotQueryStats
PRINT 'Cleaning PerfSnapshotQueryStats.DatabaseName...'
UPDATE PerfSnapshotQueryStats
SET DatabaseName = REPLACE(DatabaseName, CHAR(0), '')
WHERE DatabaseName LIKE '%' + CHAR(0) + '%'
SET @RowsAffected = @@ROWCOUNT
PRINT '  Rows updated: ' + CAST(@RowsAffected AS VARCHAR(10))

PRINT 'Cleaning PerfSnapshotQueryStats.SqlText...'
UPDATE PerfSnapshotQueryStats
SET SqlText = REPLACE(SqlText, CHAR(0), '')
WHERE SqlText LIKE '%' + CHAR(0) + '%'
SET @RowsAffected = @@ROWCOUNT
PRINT '  Rows updated: ' + CAST(@RowsAffected AS VARCHAR(10))

-- Clean PerfSnapshotMissingIndexes
PRINT 'Cleaning PerfSnapshotMissingIndexes.DatabaseName...'
UPDATE PerfSnapshotMissingIndexes
SET DatabaseName = REPLACE(DatabaseName, CHAR(0), '')
WHERE DatabaseName LIKE '%' + CHAR(0) + '%'
SET @RowsAffected = @@ROWCOUNT
PRINT '  Rows updated: ' + CAST(@RowsAffected AS VARCHAR(10))

PRINT 'Cleaning PerfSnapshotMissingIndexes.ObjectName...'
UPDATE PerfSnapshotMissingIndexes
SET ObjectName = REPLACE(ObjectName, CHAR(0), '')
WHERE ObjectName LIKE '%' + CHAR(0) + '%'
SET @RowsAffected = @@ROWCOUNT
PRINT '  Rows updated: ' + CAST(@RowsAffected AS VARCHAR(10))

PRINT 'Cleaning PerfSnapshotMissingIndexes.EqualityColumns...'
UPDATE PerfSnapshotMissingIndexes
SET EqualityColumns = REPLACE(EqualityColumns, CHAR(0), '')
WHERE EqualityColumns LIKE '%' + CHAR(0) + '%'
SET @RowsAffected = @@ROWCOUNT
PRINT '  Rows updated: ' + CAST(@RowsAffected AS VARCHAR(10))

PRINT 'Cleaning PerfSnapshotMissingIndexes.InequalityColumns...'
UPDATE PerfSnapshotMissingIndexes
SET InequalityColumns = REPLACE(InequalityColumns, CHAR(0), '')
WHERE InequalityColumns LIKE '%' + CHAR(0) + '%'
SET @RowsAffected = @@ROWCOUNT
PRINT '  Rows updated: ' + CAST(@RowsAffected AS VARCHAR(10))

PRINT 'Cleaning PerfSnapshotMissingIndexes.IncludedColumns...'
UPDATE PerfSnapshotMissingIndexes
SET IncludedColumns = REPLACE(IncludedColumns, CHAR(0), '')
WHERE IncludedColumns LIKE '%' + CHAR(0) + '%'
SET @RowsAffected = @@ROWCOUNT
PRINT '  Rows updated: ' + CAST(@RowsAffected AS VARCHAR(10))

-- Clean PerfSnapshotDB
PRINT 'Cleaning PerfSnapshotDB.DatabaseName...'
UPDATE PerfSnapshotDB
SET DatabaseName = REPLACE(DatabaseName, CHAR(0), '')
WHERE DatabaseName LIKE '%' + CHAR(0) + '%'
SET @RowsAffected = @@ROWCOUNT
PRINT '  Rows updated: ' + CAST(@RowsAffected AS VARCHAR(10))

PRINT 'Cleaning PerfSnapshotDB.StateDesc...'
UPDATE PerfSnapshotDB
SET StateDesc = REPLACE(StateDesc, CHAR(0), '')
WHERE StateDesc LIKE '%' + CHAR(0) + '%'
SET @RowsAffected = @@ROWCOUNT
PRINT '  Rows updated: ' + CAST(@RowsAffected AS VARCHAR(10))

PRINT 'Cleaning PerfSnapshotDB.RecoveryModelDesc...'
UPDATE PerfSnapshotDB
SET RecoveryModelDesc = REPLACE(RecoveryModelDesc, CHAR(0), '')
WHERE RecoveryModelDesc LIKE '%' + CHAR(0) + '%'
SET @RowsAffected = @@ROWCOUNT
PRINT '  Rows updated: ' + CAST(@RowsAffected AS VARCHAR(10))

PRINT 'Cleaning PerfSnapshotDB.LogReuseWaitDesc...'
UPDATE PerfSnapshotDB
SET LogReuseWaitDesc = REPLACE(LogReuseWaitDesc, CHAR(0), '')
WHERE LogReuseWaitDesc LIKE '%' + CHAR(0) + '%'
SET @RowsAffected = @@ROWCOUNT
PRINT '  Rows updated: ' + CAST(@RowsAffected AS VARCHAR(10))

-- Clean PerfSnapshotErrorLog
PRINT 'Cleaning PerfSnapshotErrorLog.ProcessInfo...'
UPDATE PerfSnapshotErrorLog
SET ProcessInfo = REPLACE(ProcessInfo, CHAR(0), '')
WHERE ProcessInfo LIKE '%' + CHAR(0) + '%'
SET @RowsAffected = @@ROWCOUNT
PRINT '  Rows updated: ' + CAST(@RowsAffected AS VARCHAR(10))

PRINT 'Cleaning PerfSnapshotErrorLog.LogText...'
UPDATE PerfSnapshotErrorLog
SET LogText = REPLACE(LogText, CHAR(0), '')
WHERE LogText LIKE '%' + CHAR(0) + '%'
SET @RowsAffected = @@ROWCOUNT
PRINT '  Rows updated: ' + CAST(@RowsAffected AS VARCHAR(10))

PRINT ''
PRINT 'Data cleaning complete!'
PRINT 'Now try generating the HTML report again.'
GO
