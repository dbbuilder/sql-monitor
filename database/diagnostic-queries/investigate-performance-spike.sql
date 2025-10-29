-- ============================================
-- Performance Spike Investigation Query
-- ============================================
-- Issue: API calls took >1 minute at 15:43 UTC, then <5 seconds at 15:45 UTC
-- API Calls: GetQuoteDealSummaryReport(), GetQuoteBaseVolumeCsv()
-- Instance: 001
-- Time Frame: 15:40 - 15:50 UTC
-- ============================================

-- PARAMETERS
DECLARE @IncidentStartTime DATETIME2 = '2025-10-28 15:43:00'; -- Adjust to actual date
DECLARE @IncidentEndTime DATETIME2 = '2025-10-28 15:45:00';
DECLARE @WindowStart DATETIME2 = DATEADD(MINUTE, -5, @IncidentStartTime);
DECLARE @WindowEnd DATETIME2 = DATEADD(MINUTE, 5, @IncidentEndTime);
DECLARE @InstanceName NVARCHAR(128) = '001';

PRINT '========================================'
PRINT 'Performance Spike Investigation Report'
PRINT 'Incident Window: ' + CONVERT(VARCHAR(25), @IncidentStartTime, 121) + ' to ' + CONVERT(VARCHAR(25), @IncidentEndTime, 121)
PRINT 'Analysis Window: ' + CONVERT(VARCHAR(25), @WindowStart, 121) + ' to ' + CONVERT(VARCHAR(25), @WindowEnd, 121)
PRINT 'Instance: ' + @InstanceName
PRINT '========================================'
PRINT ''

-- ============================================
-- 1. DISK I/O THROUGHPUT DURING INCIDENT
-- ============================================
PRINT '1. DISK I/O THROUGHPUT (MB/sec)'
PRINT '----------------------------------------'

SELECT
    CollectionTime,
    CASE
        WHEN CollectionTime BETWEEN @IncidentStartTime AND @IncidentEndTime THEN '>>> INCIDENT <<<'
        ELSE ''
    END AS [Incident_Flag],
    DatabaseName,
    CAST(ReadMBPerSec AS DECIMAL(10,2)) AS ReadMB_Sec,
    CAST(WriteMBPerSec AS DECIMAL(10,2)) AS WriteMB_Sec,
    CAST((ReadMBPerSec + WriteMBPerSec) AS DECIMAL(10,2)) AS TotalIO_MB_Sec,
    CAST(AvgReadLatencyMs AS DECIMAL(10,2)) AS AvgRead_ms,
    CAST(AvgWriteLatencyMs AS DECIMAL(10,2)) AS AvgWrite_ms
FROM DBATools.dbo.DatabaseStats
WHERE ServerName LIKE '%' + @InstanceName + '%'
    AND CollectionTime BETWEEN @WindowStart AND @WindowEnd
ORDER BY CollectionTime DESC, TotalIO_MB_Sec DESC;

PRINT ''
PRINT ''

-- ============================================
-- 2. CPU AND MEMORY PRESSURE
-- ============================================
PRINT '2. CPU AND MEMORY PRESSURE'
PRINT '----------------------------------------'

SELECT
    CollectionTime,
    CASE
        WHEN CollectionTime BETWEEN @IncidentStartTime AND @IncidentEndTime THEN '>>> INCIDENT <<<'
        ELSE ''
    END AS [Incident_Flag],
    CAST(CPUPercent AS DECIMAL(5,2)) AS CPU_Percent,
    CAST(MemoryUsagePercent AS DECIMAL(5,2)) AS Memory_Percent,
    CAST(FreeDiskSpaceGB AS DECIMAL(10,2)) AS FreeDisk_GB,
    ActiveConnections
FROM DBATools.dbo.ServerHealth
WHERE ServerName LIKE '%' + @InstanceName + '%'
    AND CollectionTime BETWEEN @WindowStart AND @WindowEnd
ORDER BY CollectionTime DESC;

PRINT ''
PRINT ''

-- ============================================
-- 3. WAIT STATISTICS (What SQL Server Was Waiting On)
-- ============================================
PRINT '3. TOP WAIT STATISTICS (What was SQL Server waiting for?)'
PRINT '----------------------------------------'

-- Note: If wait stats are captured as snapshots, we'd need delta calculations
-- This assumes DBATools captures wait stat deltas per collection interval

SELECT TOP 20
    CollectionTime,
    CASE
        WHEN CollectionTime BETWEEN @IncidentStartTime AND @IncidentEndTime THEN '>>> INCIDENT <<<'
        ELSE ''
    END AS [Incident_Flag],
    WaitType,
    CAST(WaitTimeMs / 1000.0 AS DECIMAL(10,2)) AS Wait_Seconds,
    WaitCount,
    CAST(WaitTimeMs / NULLIF(WaitCount, 0) AS DECIMAL(10,2)) AS Avg_Wait_ms,
    -- Common wait type explanations
    CASE WaitType
        WHEN 'PAGEIOLATCH_SH' THEN 'Disk I/O bottleneck (reads)'
        WHEN 'PAGEIOLATCH_EX' THEN 'Disk I/O bottleneck (writes)'
        WHEN 'WRITELOG' THEN 'Transaction log writes slow'
        WHEN 'LCK_M_X' THEN 'Exclusive lock waits (blocking)'
        WHEN 'LCK_M_S' THEN 'Shared lock waits (blocking)'
        WHEN 'SOS_SCHEDULER_YIELD' THEN 'CPU pressure'
        WHEN 'ASYNC_NETWORK_IO' THEN 'Client not consuming results fast enough'
        WHEN 'CXPACKET' THEN 'Parallel query coordination'
        ELSE 'See SQL Server docs'
    END AS Explanation
FROM DBATools.dbo.WaitStats -- Adjust table name if different
WHERE ServerName LIKE '%' + @InstanceName + '%'
    AND CollectionTime BETWEEN @WindowStart AND @WindowEnd
ORDER BY CollectionTime DESC, Wait_Seconds DESC;

PRINT ''
PRINT ''

-- ============================================
-- 4. ACTIVE WORKLOAD DURING INCIDENT
-- ============================================
PRINT '4. ACTIVE QUERIES CAPTURED DURING INCIDENT'
PRINT '----------------------------------------'

-- Note: This requires sql-monitor-agent to capture active queries
-- If not available, skip this section

IF OBJECT_ID('DBATools.dbo.ActiveWorkload', 'U') IS NOT NULL
BEGIN
    SELECT
        CollectionTime,
        SessionID,
        DatabaseName,
        Status,
        Command,
        CAST(CPUTimeMs / 1000.0 AS DECIMAL(10,2)) AS CPU_Seconds,
        CAST(ElapsedTimeMs / 1000.0 AS DECIMAL(10,2)) AS Elapsed_Seconds,
        WaitType,
        BlockingSessionID,
        LEFT(QueryText, 500) AS QueryText_Preview
    FROM DBATools.dbo.ActiveWorkload
    WHERE ServerName LIKE '%' + @InstanceName + '%'
        AND CollectionTime BETWEEN @WindowStart AND @WindowEnd
        AND ElapsedTimeMs > 5000 -- Queries running longer than 5 seconds
    ORDER BY CollectionTime DESC, Elapsed_Seconds DESC;
END
ELSE
BEGIN
    PRINT 'Active workload data not available (ActiveWorkload table does not exist)'
END

PRINT ''
PRINT ''

-- ============================================
-- 5. BLOCKING CHAINS (If Present)
-- ============================================
PRINT '5. BLOCKING CHAINS'
PRINT '----------------------------------------'

IF OBJECT_ID('DBATools.dbo.ActiveWorkload', 'U') IS NOT NULL
BEGIN
    SELECT
        CollectionTime,
        SessionID AS Blocked_SessionID,
        BlockingSessionID,
        DatabaseName,
        WaitType,
        CAST(ElapsedTimeMs / 1000.0 AS DECIMAL(10,2)) AS Blocked_Seconds,
        Status,
        LEFT(QueryText, 300) AS BlockedQuery_Preview
    FROM DBATools.dbo.ActiveWorkload
    WHERE ServerName LIKE '%' + @InstanceName + '%'
        AND CollectionTime BETWEEN @WindowStart AND @WindowEnd
        AND BlockingSessionID IS NOT NULL
        AND BlockingSessionID > 0
    ORDER BY CollectionTime DESC, Blocked_Seconds DESC;

    IF @@ROWCOUNT = 0
        PRINT 'No blocking detected during incident window'
END

PRINT ''
PRINT ''

-- ============================================
-- 6. DATABASE GROWTH EVENTS (File Auto-Growth)
-- ============================================
PRINT '6. DATABASE FILE AUTO-GROWTH EVENTS'
PRINT '----------------------------------------'

IF OBJECT_ID('DBATools.dbo.DatabaseStats', 'U') IS NOT NULL
BEGIN
    -- Look for sudden size increases (>100MB) between collections
    WITH SizeChanges AS (
        SELECT
            CollectionTime,
            DatabaseName,
            SizeMB,
            LAG(SizeMB) OVER (PARTITION BY DatabaseName ORDER BY CollectionTime) AS PreviousSizeMB,
            SizeMB - LAG(SizeMB) OVER (PARTITION BY DatabaseName ORDER BY CollectionTime) AS SizeGrowthMB
        FROM DBATools.dbo.DatabaseStats
        WHERE ServerName LIKE '%' + @InstanceName + '%'
            AND CollectionTime BETWEEN @WindowStart AND @WindowEnd
    )
    SELECT
        CollectionTime,
        CASE
            WHEN CollectionTime BETWEEN @IncidentStartTime AND @IncidentEndTime THEN '>>> INCIDENT <<<'
            ELSE ''
        END AS [Incident_Flag],
        DatabaseName,
        CAST(PreviousSizeMB AS DECIMAL(10,2)) AS PreviousSize_MB,
        CAST(SizeMB AS DECIMAL(10,2)) AS CurrentSize_MB,
        CAST(SizeGrowthMB AS DECIMAL(10,2)) AS Growth_MB
    FROM SizeChanges
    WHERE SizeGrowthMB > 100 -- File grew by more than 100MB
    ORDER BY CollectionTime DESC;

    IF @@ROWCOUNT = 0
        PRINT 'No significant database growth events detected'
END

PRINT ''
PRINT ''

-- ============================================
-- 7. STORED PROCEDURE EXECUTION STATS (If Available)
-- ============================================
PRINT '7. STORED PROCEDURE PERFORMANCE (Looking for GetQuoteDealSummaryReport, GetQuoteBaseVolumeCsv)'
PRINT '----------------------------------------'

-- Note: sql-monitor-agent may not capture procedure-level stats
-- If MonitoringDB has procedure stats, query those instead

IF OBJECT_ID('MonitoringDB.dbo.ProcedureStats', 'U') IS NOT NULL
BEGIN
    SELECT
        CollectionTime,
        CASE
            WHEN CollectionTime BETWEEN @IncidentStartTime AND @IncidentEndTime THEN '>>> INCIDENT <<<'
            ELSE ''
        END AS [Incident_Flag],
        DatabaseName,
        ProcedureName,
        ExecutionCount,
        CAST(AvgDurationMs AS DECIMAL(10,2)) AS Avg_Duration_ms,
        CAST(MaxDurationMs AS DECIMAL(10,2)) AS Max_Duration_ms,
        CAST(AvgCPUMs AS DECIMAL(10,2)) AS Avg_CPU_ms,
        CAST(AvgReadsKB / 1024.0 AS DECIMAL(10,2)) AS Avg_Reads_MB
    FROM MonitoringDB.dbo.ProcedureStats
    WHERE ServerID = (SELECT ServerID FROM MonitoringDB.dbo.Servers WHERE ServerName LIKE '%' + @InstanceName + '%')
        AND CollectionTime BETWEEN @WindowStart AND @WindowEnd
        AND (
            ProcedureName LIKE '%GetQuoteDealSummaryReport%'
            OR ProcedureName LIKE '%GetQuoteBaseVolumeCsv%'
            OR ProcedureName LIKE '%Quote%'
        )
    ORDER BY CollectionTime DESC, Avg_Duration_ms DESC;

    IF @@ROWCOUNT = 0
        PRINT 'No procedure stats available for these API calls (check procedure name mapping)'
END
ELSE
BEGIN
    PRINT 'Procedure stats not available in MonitoringDB.dbo.ProcedureStats'
END

PRINT ''
PRINT ''

-- ============================================
-- 8. SUMMARY AND RECOMMENDATIONS
-- ============================================
PRINT '========================================'
PRINT 'INVESTIGATION SUMMARY'
PRINT '========================================'
PRINT ''
PRINT 'Review the results above to identify:'
PRINT '1. Disk I/O spikes during incident window (look for high MB/sec or latency)'
PRINT '2. CPU or Memory pressure (>80% sustained)'
PRINT '3. Wait statistics indicating bottleneck:'
PRINT '   - PAGEIOLATCH_* = Disk I/O bottleneck'
PRINT '   - WRITELOG = Transaction log slow'
PRINT '   - LCK_M_* = Blocking'
PRINT '   - SOS_SCHEDULER_YIELD = CPU pressure'
PRINT '4. Blocking chains (queries waiting on other sessions)'
PRINT '5. Database auto-growth events (causes I/O pause)'
PRINT ''
PRINT 'Common Causes of Sudden 1-Minute Delays:'
PRINT '- Database auto-growth (instant file initialization not enabled)'
PRINT '- Lock escalation and blocking'
PRINT '- Plan cache flush (recompilation storm)'
PRINT '- Statistics update during query execution'
PRINT '- TempDB contention'
PRINT '- Disk subsystem saturation'
PRINT ''
PRINT '========================================'

-- ============================================
-- 9. ADDITIONAL QUERY: CHECK IF MONITORING DATA EXISTS
-- ============================================
PRINT ''
PRINT '9. DATA AVAILABILITY CHECK'
PRINT '----------------------------------------'

SELECT
    'DBATools.dbo.ServerHealth' AS TableName,
    COUNT(*) AS RowCount,
    MIN(CollectionTime) AS EarliestData,
    MAX(CollectionTime) AS LatestData
FROM DBATools.dbo.ServerHealth
WHERE ServerName LIKE '%' + @InstanceName + '%'
UNION ALL
SELECT
    'DBATools.dbo.DatabaseStats',
    COUNT(*),
    MIN(CollectionTime),
    MAX(CollectionTime)
FROM DBATools.dbo.DatabaseStats
WHERE ServerName LIKE '%' + @InstanceName + '%';

PRINT ''
PRINT 'If RowCount = 0, monitoring data is not available for this instance'
PRINT 'Check ServerName in DBATools tables and adjust @InstanceName parameter'
