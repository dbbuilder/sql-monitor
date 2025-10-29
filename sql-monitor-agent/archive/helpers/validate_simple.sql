-- Simple Validation Queries

PRINT '=========================================='
PRINT 'Deployment Validation'
PRINT '=========================================='

-- Count procedures
PRINT 'Procedures deployed:'
SELECT COUNT(*) AS ProcedureCount
FROM sys.objects
WHERE name LIKE 'DBA_%' AND type = 'P'

PRINT ''
PRINT 'Collection procedures:'
SELECT name
FROM sys.objects
WHERE name LIKE 'DBA_Collect_%' AND type = 'P'
ORDER BY name

-- Count functions
PRINT ''
PRINT 'Functions deployed:'
SELECT COUNT(*) AS FunctionCount
FROM sys.objects
WHERE name LIKE 'fn_%' AND type IN ('FN', 'IF', 'TF')

-- Config records
PRINT ''
PRINT 'Config records:'
SELECT COUNT(*) AS ConfigCount
FROM dbo.MonitoringConfig

-- Test collection
PRINT ''
PRINT 'Running test snapshot collection...'
EXEC dbo.DBA_CollectPerformanceSnapshot @Debug = 1

-- Count snapshots
PRINT ''
PRINT 'Total snapshots collected:'
SELECT COUNT(*) AS SnapshotCount
FROM dbo.PerfSnapshotRun

-- Latest snapshot
PRINT ''
PRINT 'Latest snapshot:'
SELECT TOP 1 *
FROM dbo.PerfSnapshotRun
ORDER BY PerfSnapshotRunID DESC

-- Check errors
PRINT ''
PRINT 'Recent errors:'
SELECT TOP 10
    DateTime_Occurred,
    ProcedureName,
    ErrDescription
FROM dbo.LogEntry
WHERE IsError = 1
ORDER BY LogEntryID DESC

PRINT ''
PRINT '=========================================='
PRINT 'Validation Complete'
PRINT '=========================================='
