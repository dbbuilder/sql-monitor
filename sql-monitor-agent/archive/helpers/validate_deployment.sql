-- Validation Queries for SQL Server Monitoring System

PRINT '=========================================='
PRINT 'SQL Server Monitoring System - Validation'
PRINT '=========================================='
PRINT ''

-- 1. Count all procedures
PRINT '1. Counting deployed procedures...'
SELECT COUNT(*) AS TotalProcedures
FROM sys.objects
WHERE name LIKE 'DBA_%' AND type = 'P'

-- 2. List all collection procedures
PRINT ''
PRINT '2. Collection procedures:'
SELECT name AS ProcedureName
FROM sys.objects
WHERE name LIKE 'DBA_Collect_%' AND type = 'P'
ORDER BY name

-- 3. Count functions
PRINT ''
PRINT '3. Counting config functions...'
SELECT COUNT(*) AS TotalFunctions
FROM sys.objects
WHERE name LIKE 'fn_%' AND type IN ('FN', 'IF', 'TF')

-- 4. Check config table
PRINT ''
PRINT '4. Config table record count:'
SELECT COUNT(*) AS ConfigRecords
FROM dbo.MonitoringConfig

-- 5. Test a simple collection
PRINT ''
PRINT '5. Testing snapshot collection...'
EXEC dbo.DBA_CollectPerformanceSnapshot @Debug = 1

-- 6. Check latest snapshot
PRINT ''
PRINT '6. Latest snapshot details:'
SELECT TOP 1
    PerfSnapshotRunID,
    SnapshotUTC,
    ServerName,
    ActiveSessions,
    ActiveRequests,
    BlockingSessions
FROM dbo.PerfSnapshotRun
ORDER BY PerfSnapshotRunID DESC

-- 7. Check for errors
PRINT ''
PRINT '7. Recent errors (if any):'
SELECT TOP 5
    DateTime_Occurred,
    ProcedureName,
    ProcedureSection,
    ErrDescription
FROM dbo.LogEntry
WHERE IsError = 1
ORDER BY LogEntryID DESC

-- 8. Count collected data
PRINT ''
PRINT '8. Data collection counts:'
SELECT 'QueryStats' AS TableName, COUNT(*) AS RecordCount FROM dbo.PerfSnapshotQueryStats
UNION ALL
SELECT 'IOStats', COUNT(*) FROM dbo.PerfSnapshotIOStats
UNION ALL
SELECT 'Memory', COUNT(*) FROM dbo.PerfSnapshotMemory
UNION ALL
SELECT 'BackupHistory', COUNT(*) FROM dbo.PerfSnapshotBackupHistory
UNION ALL
SELECT 'IndexUsage', COUNT(*) FROM dbo.PerfSnapshotIndexUsage
UNION ALL
SELECT 'MissingIndexes', COUNT(*) FROM dbo.PerfSnapshotMissingIndexes
UNION ALL
SELECT 'WaitStats', COUNT(*) FROM dbo.PerfSnapshotWaitStats

PRINT ''
PRINT '=========================================='
PRINT 'Validation Complete!'
PRINT '=========================================='
