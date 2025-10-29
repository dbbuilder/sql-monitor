-- Quick status check
SELECT COUNT(*) AS SnapshotCount FROM DBATools.dbo.PerfSnapshotRun

SELECT TOP 1
    PerfSnapshotRunID,
    SnapshotUTC,
    ServerName
FROM DBATools.dbo.PerfSnapshotRun
ORDER BY PerfSnapshotRunID DESC

SELECT TOP 5
    DateTime_Occurred,
    ProcedureName,
    ProcedureSection,
    IsError,
    ErrDescription
FROM DBATools.dbo.LogEntry
ORDER BY LogEntryID DESC
