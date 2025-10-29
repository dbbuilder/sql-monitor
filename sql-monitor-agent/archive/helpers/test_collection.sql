-- Test snapshot collection
PRINT 'Testing snapshot collection...'
EXEC dbo.DBA_CollectPerformanceSnapshot @Debug = 1

PRINT ''
PRINT 'Checking results...'

SELECT TOP 1
    PerfSnapshotRunID,
    SnapshotUTC,
    ServerName
FROM dbo.PerfSnapshotRun
ORDER BY PerfSnapshotRunID DESC

PRINT ''
PRINT 'Data counts:'
SELECT 'QueryStats' AS TableName, COUNT(*) AS Records FROM dbo.PerfSnapshotQueryStats
UNION ALL SELECT 'IOStats', COUNT(*) FROM dbo.PerfSnapshotIOStats
UNION ALL SELECT 'Memory', COUNT(*) FROM dbo.PerfSnapshotMemory
UNION ALL SELECT 'BackupHistory', COUNT(*) FROM dbo.PerfSnapshotBackupHistory

PRINT ''
PRINT 'Recent log entries:'
SELECT TOP 5
    DateTime_Occurred,
    ProcedureName,
    ProcedureSection,
    IsError
FROM dbo.LogEntry
ORDER BY LogEntryID DESC
