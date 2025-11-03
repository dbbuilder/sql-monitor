-- =====================================================
-- Script: 84-fix-deployment.sql
-- Description: Diagnose and fix AWS RDS dashboard missing data
-- Author: SQL Server Monitor Project
-- Date: 2025-11-03
-- Purpose: Check what metrics exist and fix dashboard queries
-- =====================================================

USE MonitoringDB;
GO

PRINT 'Diagnosing AWS RDS Dashboard Missing Data...';
PRINT '';

-- =====================================================
-- STEP 1: Check what metrics are actually being collected
-- =====================================================

PRINT '1. Checking available metrics in PerformanceMetrics table...';
PRINT '';

SELECT DISTINCT
    MetricCategory,
    MetricName,
    COUNT(*) AS RecordCount,
    MIN(CollectionTime) AS OldestRecord,
    MAX(CollectionTime) AS NewestRecord
FROM dbo.PerformanceMetrics
WHERE CollectionTime >= DATEADD(HOUR, -24, GETUTCDATE())
GROUP BY MetricCategory, MetricName
ORDER BY MetricCategory, MetricName;

PRINT '';
PRINT '2. Checking for Disk-related metrics...';
PRINT '';

SELECT DISTINCT MetricName
FROM dbo.PerformanceMetrics
WHERE MetricCategory = 'Disk'
  AND CollectionTime >= DATEADD(HOUR, -24, GETUTCDATE())
ORDER BY MetricName;

PRINT '';
PRINT '3. Checking for Performance-related metrics...';
PRINT '';

SELECT DISTINCT MetricName
FROM dbo.PerformanceMetrics
WHERE MetricCategory = 'Performance'
  AND CollectionTime >= DATEADD(HOUR, -24, GETUTCDATE())
ORDER BY MetricName;

PRINT '';
PRINT '4. Sample IOPS data (if exists)...';
PRINT '';

SELECT TOP 10
    CollectionTime,
    MetricName,
    MetricValue
FROM dbo.PerformanceMetrics
WHERE MetricCategory = 'Disk'
  AND (MetricName LIKE '%IOPS%' OR MetricName LIKE '%Ops%')
  AND CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE())
ORDER BY CollectionTime DESC;

PRINT '';
PRINT 'Diagnostic complete!';
PRINT '';
GO
