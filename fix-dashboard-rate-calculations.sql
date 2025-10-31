-- =============================================
-- Fix Dashboard Queries to Calculate Rates
-- Converts cumulative counters to per-second rates
-- =============================================

USE MonitoringDB;
GO

-- Test rate calculation for IOPS (should show ~2K reads/sec instead of 3.4M total)
DECLARE @ServerID INT = 1;
DECLARE @__timeFrom DATETIME2 = DATEADD(HOUR, -1, GETUTCDATE());
DECLARE @__timeTo DATETIME2 = GETUTCDATE();

PRINT '========================================';
PRINT 'Testing Rate Calculations for Dashboard';
PRINT '========================================';
PRINT '';

-- Current approach (WRONG - shows cumulative totals)
PRINT '1. Current Query (Cumulative Totals - WRONG):';
SELECT TOP 5
  CollectionTime AS time,
  MetricValue AS value,
  MetricName AS metric
FROM dbo.PerformanceMetrics pm
WHERE pm.MetricCategory = 'Disk'
  AND pm.MetricName IN ('ReadIOPS', 'WriteIOPS')
  AND pm.ServerID = @ServerID
  AND pm.CollectionTime >= @__timeFrom
  AND pm.CollectionTime <= @__timeTo
ORDER BY pm.CollectionTime DESC, MetricName;
PRINT '';

-- Fixed approach (CORRECT - calculates delta between collections)
PRINT '2. Fixed Query (Delta/Rate Calculation - CORRECT):';
WITH MetricsWithPrevious AS (
    SELECT
        CollectionTime,
        MetricName,
        MetricValue,
        LAG(MetricValue) OVER (PARTITION BY MetricName ORDER BY CollectionTime) AS PrevValue,
        LAG(CollectionTime) OVER (PARTITION BY MetricName ORDER BY CollectionTime) AS PrevTime
    FROM dbo.PerformanceMetrics
    WHERE ServerID = @ServerID
      AND MetricCategory = 'Disk'
      AND MetricName IN ('ReadIOPS', 'WriteIOPS')
      AND CollectionTime >= @__timeFrom
      AND CollectionTime <= @__timeTo
)
SELECT TOP 10
    CollectionTime AS time,
    CASE
        WHEN PrevValue IS NOT NULL AND DATEDIFF(SECOND, PrevTime, CollectionTime) > 0
        THEN (MetricValue - PrevValue) / DATEDIFF(SECOND, PrevTime, CollectionTime)
        ELSE 0
    END AS value,
    CASE MetricName
        WHEN 'ReadIOPS' THEN 'Read IOPS'
        WHEN 'WriteIOPS' THEN 'Write IOPS'
    END AS metric
FROM MetricsWithPrevious
WHERE PrevValue IS NOT NULL  -- Exclude first row (no previous value)
ORDER BY CollectionTime DESC;
PRINT '';

PRINT '========================================';
PRINT 'Rate calculations complete!';
PRINT 'Apply these patterns to IOPS, Throughput panels.';
PRINT '========================================';
GO
