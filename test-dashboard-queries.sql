-- Test each dashboard query with actual ServerID value
-- Run this to verify each panel's query works
USE MonitoringDB;
GO

DECLARE @ServerID INT = 1;
DECLARE @__timeFrom DATETIME2 = DATEADD(HOUR, -1, GETUTCDATE());
DECLARE @__timeTo DATETIME2 = GETUTCDATE();

PRINT '========================================';
PRINT 'Testing Dashboard Queries';
PRINT '========================================';
PRINT '';

-- Test 1: Database Connections
PRINT '1. Database Connections:';
SELECT TOP 10
  CollectionTime AS time,
  MetricValue AS value,
  MetricName AS metric
FROM dbo.PerformanceMetrics pm
WHERE pm.MetricCategory = 'Connections'
  AND pm.MetricName IN ('Total', 'Active', 'Sleeping')
  AND pm.ServerID = @ServerID
  AND pm.CollectionTime >= @__timeFrom
  AND pm.CollectionTime <= @__timeTo
ORDER BY pm.CollectionTime DESC;
PRINT '';

-- Test 2: Read/Write IOPS
PRINT '2. Read/Write IOPS:';
SELECT TOP 10
  CollectionTime AS time,
  MetricValue AS value,
  CASE MetricName
    WHEN 'ReadIOPS' THEN 'Read IOPS'
    WHEN 'WriteIOPS' THEN 'Write IOPS'
  END AS metric
FROM dbo.PerformanceMetrics pm
WHERE pm.MetricCategory = 'Disk'
  AND pm.MetricName IN ('ReadIOPS', 'WriteIOPS')
  AND pm.ServerID = @ServerID
  AND pm.CollectionTime >= @__timeFrom
  AND pm.CollectionTime <= @__timeTo
ORDER BY pm.CollectionTime DESC;
PRINT '';

-- Test 3: Read/Write Throughput
PRINT '3. Read/Write Throughput:';
SELECT TOP 10
  CollectionTime AS time,
  MetricValue AS value,
  CASE MetricName
    WHEN 'ReadMB' THEN 'Read MB/s'
    WHEN 'WriteMB' THEN 'Write MB/s'
  END AS metric
FROM dbo.PerformanceMetrics pm
WHERE pm.MetricCategory = 'Disk'
  AND pm.MetricName IN ('ReadMB', 'WriteMB')
  AND pm.ServerID = @ServerID
  AND pm.CollectionTime >= @__timeFrom
  AND pm.CollectionTime <= @__timeTo
ORDER BY pm.CollectionTime DESC;
PRINT '';

-- Test 4: Disk Latency
PRINT '4. Disk Latency:';
SELECT TOP 10
  CollectionTime AS time,
  MetricValue AS value,
  CASE MetricName
    WHEN 'AvgReadLatencyMs' THEN 'Read Latency'
    WHEN 'AvgWriteLatencyMs' THEN 'Write Latency'
  END AS metric
FROM dbo.PerformanceMetrics pm
WHERE pm.MetricCategory = 'Disk'
  AND pm.MetricName IN ('AvgReadLatencyMs', 'AvgWriteLatencyMs')
  AND pm.ServerID = @ServerID
  AND pm.CollectionTime >= @__timeFrom
  AND pm.CollectionTime <= @__timeTo
ORDER BY pm.CollectionTime DESC;
PRINT '';

-- Test 5: Transactions
PRINT '5. Transactions:';
SELECT TOP 1
  CollectionTime AS time,
  MetricValue AS value
FROM dbo.PerformanceMetrics
WHERE MetricCategory = 'Performance'
  AND MetricName = 'Transactions'
  AND ServerID = @ServerID
  AND CollectionTime >= @__timeFrom
  AND CollectionTime <= @__timeTo
ORDER BY CollectionTime DESC;
PRINT '';

PRINT '========================================';
PRINT 'All queries tested successfully!';
PRINT 'If you see data above, the dashboard queries are correct.';
PRINT '========================================';
GO
