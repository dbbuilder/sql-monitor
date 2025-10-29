-- =============================================
-- Diagnose NULL Character Issues
-- Purpose: Find which fields contain CHAR(0)
-- =============================================

USE DBATools
GO

PRINT 'Checking for NULL characters (CHAR(0)) in data...'
PRINT ''

DECLARE @RunID INT = (SELECT MAX(PerfSnapshotRunID) FROM PerfSnapshotRun)

PRINT 'Using PerfSnapshotRunID: ' + CAST(@RunID AS VARCHAR(10))
PRINT ''

-- Check PerfSnapshotRun
PRINT '=== PerfSnapshotRun ==='
SELECT
    'TopWaitType' AS FieldName,
    COUNT(*) AS RecordsWithNullChar
FROM PerfSnapshotRun
WHERE PerfSnapshotRunID = @RunID
  AND TopWaitType LIKE '%' + CHAR(0) + '%'

-- Check PerfSnapshotQueryStats
PRINT '=== PerfSnapshotQueryStats ==='
SELECT 'DatabaseName' AS FieldName, COUNT(*) AS RecordsWithNullChar
FROM PerfSnapshotQueryStats WHERE PerfSnapshotRunID = @RunID AND DatabaseName LIKE '%' + CHAR(0) + '%'
UNION ALL
SELECT 'SqlText', COUNT(*) FROM PerfSnapshotQueryStats WHERE PerfSnapshotRunID = @RunID AND SqlText LIKE '%' + CHAR(0) + '%'

-- Check PerfSnapshotMissingIndexes
PRINT '=== PerfSnapshotMissingIndexes ==='
SELECT 'DatabaseName' AS FieldName, COUNT(*) AS RecordsWithNullChar
FROM PerfSnapshotMissingIndexes WHERE PerfSnapshotRunID = @RunID AND DatabaseName LIKE '%' + CHAR(0) + '%'
UNION ALL
SELECT 'ObjectName', COUNT(*) FROM PerfSnapshotMissingIndexes WHERE PerfSnapshotRunID = @RunID AND ObjectName LIKE '%' + CHAR(0) + '%'
UNION ALL
SELECT 'EqualityColumns', COUNT(*) FROM PerfSnapshotMissingIndexes WHERE PerfSnapshotRunID = @RunID AND EqualityColumns LIKE '%' + CHAR(0) + '%'
UNION ALL
SELECT 'InequalityColumns', COUNT(*) FROM PerfSnapshotMissingIndexes WHERE PerfSnapshotRunID = @RunID AND InequalityColumns LIKE '%' + CHAR(0) + '%'
UNION ALL
SELECT 'IncludedColumns', COUNT(*) FROM PerfSnapshotMissingIndexes WHERE PerfSnapshotRunID = @RunID AND IncludedColumns LIKE '%' + CHAR(0) + '%'

-- Check PerfSnapshotDB
PRINT '=== PerfSnapshotDB ==='
SELECT 'DatabaseName' AS FieldName, COUNT(*) AS RecordsWithNullChar
FROM PerfSnapshotDB WHERE PerfSnapshotRunID = @RunID AND DatabaseName LIKE '%' + CHAR(0) + '%'
UNION ALL
SELECT 'StateDesc', COUNT(*) FROM PerfSnapshotDB WHERE PerfSnapshotRunID = @RunID AND StateDesc LIKE '%' + CHAR(0) + '%'
UNION ALL
SELECT 'RecoveryModelDesc', COUNT(*) FROM PerfSnapshotDB WHERE PerfSnapshotRunID = @RunID AND RecoveryModelDesc LIKE '%' + CHAR(0) + '%'
UNION ALL
SELECT 'LogReuseWaitDesc', COUNT(*) FROM PerfSnapshotDB WHERE PerfSnapshotRunID = @RunID AND LogReuseWaitDesc LIKE '%' + CHAR(0) + '%'

-- Check PerfSnapshotErrorLog
PRINT '=== PerfSnapshotErrorLog ==='
SELECT 'ProcessInfo' AS FieldName, COUNT(*) AS RecordsWithNullChar
FROM PerfSnapshotErrorLog WHERE PerfSnapshotRunID = @RunID AND ProcessInfo LIKE '%' + CHAR(0) + '%'
UNION ALL
SELECT 'LogText', COUNT(*) FROM PerfSnapshotErrorLog WHERE PerfSnapshotRunID = @RunID AND LogText LIKE '%' + CHAR(0) + '%'

PRINT ''
PRINT 'Diagnosis complete. Any non-zero counts indicate fields that need cleaning.'
GO
