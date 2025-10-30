# SQL Server Monitor - Drill-Down Analysis Guide

## Overview

This guide explains how to drill down from server-level metrics to database, stored procedure, and individual query performance - matching AWS RDS Performance Insights drill-down capabilities.

---

## 📊 Drill-Down Hierarchy

```
Server (data.schoolvision.net)
  ↓
Database (e.g., DEV_SVDB_POS, MonitoringDB)
  ↓
Stored Procedure (e.g., dbo.usp_GetCustomers)
  ↓
Individual Query (by query_hash)
  ↓
Specific Metrics (CPU, Duration, Reads, Waits)
```

---

## 🗄️ New Tables for Drill-Down

### 1. DatabaseMetrics
**Purpose**: Track performance metrics at the database level

**Columns**:
- ServerID, DatabaseName
- MetricCategory (CPU, Memory, IO, Waits, Connections)
- MetricName, MetricValue
- CollectionTime

**Example Query**:
```sql
-- Top 5 databases by CPU usage
SELECT TOP 5
    DatabaseName,
    SUM(MetricValue) AS TotalCPUMs
FROM dbo.DatabaseMetrics
WHERE MetricCategory = 'CPU'
  AND MetricName = 'TotalCPUMs'
  AND CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE())
GROUP BY DatabaseName
ORDER BY TotalCPUMs DESC;
```

### 2. ProcedureMetrics
**Purpose**: Track stored procedure performance

**Columns**:
- ServerID, DatabaseName, SchemaName, ProcedureName
- ExecutionCount, TotalCPUMs, AvgCPUMs
- TotalDurationMs, AvgDurationMs
- TotalLogicalReads, AvgLogicalReads
- LastExecutionTime

**Example Query**:
```sql
-- Top 10 procedures by average CPU
SELECT TOP 10
    DatabaseName,
    SchemaName + '.' + ProcedureName AS Procedure,
    ExecutionCount,
    AvgCPUMs,
    AvgDurationMs
FROM dbo.ProcedureMetrics
WHERE CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE())
ORDER BY AvgCPUMs DESC;
```

### 3. QueryMetrics
**Purpose**: Track individual query performance

**Columns**:
- ServerID, DatabaseName
- QueryHash (unique identifier)
- QueryText (first 4000 chars)
- ExecutionCount, AvgCPUMs, MaxCPUMs
- AvgDurationMs, MaxDurationMs
- AvgLogicalReads, TotalPhysicalReads

**Example Query**:
```sql
-- Find the query with highest average CPU
SELECT TOP 10
    DatabaseName,
    ExecutionCount,
    AvgCPUMs,
    MaxCPUMs,
    CAST(QueryText AS NVARCHAR(200)) AS QueryPreview
FROM dbo.QueryMetrics
WHERE CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE())
ORDER BY AvgCPUMs DESC;
```

### 4. WaitEventsByDatabase
**Purpose**: Track wait statistics per database

**Columns**:
- ServerID, DatabaseName, WaitType
- WaitingTasksCount, WaitTimeMs
- MaxWaitTimeMs, ResourceWaitTimeMs

**Example Query**:
```sql
-- Top wait types per database
SELECT
    DatabaseName,
    WaitType,
    SUM(WaitTimeMs) AS TotalWaitMs,
    SUM(WaitingTasksCount) AS TotalWaits
FROM dbo.WaitEventsByDatabase
WHERE CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE())
GROUP BY DatabaseName, WaitType
ORDER BY TotalWaitMs DESC;
```

### 5. ConnectionsByDatabase
**Purpose**: Track connection counts per database

**Columns**:
- ServerID, DatabaseName
- TotalConnections, ActiveConnections
- SleepingConnections, BlockedConnections

**Example Query**:
```sql
-- Current connections by database
SELECT
    DatabaseName,
    TotalConnections,
    ActiveConnections,
    BlockedConnections
FROM dbo.ConnectionsByDatabase
WHERE CollectionTime = (SELECT MAX(CollectionTime) FROM dbo.ConnectionsByDatabase);
```

---

## 🔄 Collection Procedures

### Collect All Drill-Down Metrics
```sql
EXEC dbo.usp_CollectAllDrillDownMetrics @ServerID = 1;
```

This master procedure calls:
1. **usp_CollectDatabaseMetrics** - CPU, I/O, connections per database
2. **usp_CollectProcedureMetrics** - Top 100 procedures by CPU
3. **usp_CollectQueryMetrics** - Top 100 queries by CPU
4. **usp_CollectWaitEventsByDatabase** - Wait events per database

### Collect Individual Categories
```sql
-- Database-level metrics only
EXEC dbo.usp_CollectDatabaseMetrics @ServerID = 1;

-- Procedure metrics only
EXEC dbo.usp_CollectProcedureMetrics @ServerID = 1;

-- Query metrics only
EXEC dbo.usp_CollectQueryMetrics @ServerID = 1;

-- Wait events by database
EXEC dbo.usp_CollectWaitEventsByDatabase @ServerID = 1;
```

---

## 📈 Grafana Drill-Down Dashboards

### Dashboard Structure

**Level 1: Server Overview**
- Total CPU, Memory, Disk I/O across all databases
- Click on a metric → Drill down to database level

**Level 2: Database Details**
- Metrics for selected database
- Top procedures in that database
- Top queries in that database
- Click on a procedure/query → Drill down to details

**Level 3: Procedure/Query Details**
- Execution count over time
- Average CPU trend
- Average duration trend
- Wait events breakdown

### Grafana Variables for Drill-Down

Add these variables to your dashboards:

```
Variable: database
Type: Query
Query: SELECT DISTINCT DatabaseName FROM dbo.DatabaseMetrics WHERE ServerID = 1 ORDER BY DatabaseName

Variable: procedure
Type: Query
Query: SELECT DISTINCT SchemaName + '.' + ProcedureName FROM dbo.ProcedureMetrics WHERE DatabaseName = '$database' ORDER BY SchemaName, ProcedureName
```

### Example Panel Queries

**Panel: Top Databases by CPU**
```sql
SELECT
    DatabaseName AS metric,
    CollectionTime AS time,
    MetricValue AS value
FROM dbo.DatabaseMetrics
WHERE ServerID = 1
  AND MetricCategory = 'CPU'
  AND MetricName = 'TotalCPUMs'
  AND $__timeFilter(CollectionTime)
ORDER BY time ASC
```

**Panel: Top Procedures (for selected database)**
```sql
SELECT
    SchemaName + '.' + ProcedureName AS metric,
    CollectionTime AS time,
    AvgCPUMs AS value
FROM dbo.ProcedureMetrics
WHERE ServerID = 1
  AND DatabaseName = '$database'
  AND $__timeFilter(CollectionTime)
ORDER BY time ASC
```

**Panel: Query Details (for selected query_hash)**
```sql
SELECT
    MetricName AS metric,
    CollectionTime AS time,
    CASE MetricName
        WHEN 'AvgCPU' THEN AvgCPUMs
        WHEN 'AvgDuration' THEN AvgDurationMs
        WHEN 'ExecutionCount' THEN ExecutionCount
    END AS value
FROM (
    SELECT
        'AvgCPU' AS MetricName,
        CollectionTime,
        AvgCPUMs,
        NULL AS AvgDurationMs,
        NULL AS ExecutionCount
    FROM dbo.QueryMetrics
    WHERE QueryHash = CONVERT(BINARY(8), '$query_hash', 2)
    UNION ALL
    SELECT
        'AvgDuration',
        CollectionTime,
        NULL,
        AvgDurationMs,
        NULL
    FROM dbo.QueryMetrics
    WHERE QueryHash = CONVERT(BINARY(8), '$query_hash', 2)
    UNION ALL
    SELECT
        'ExecutionCount',
        CollectionTime,
        NULL,
        NULL,
        ExecutionCount
    FROM dbo.QueryMetrics
    WHERE QueryHash = CONVERT(BINARY(8), '$query_hash', 2)
) AS metrics
WHERE $__timeFilter(CollectionTime)
ORDER BY time ASC
```

---

## 🎯 Use Cases

### Use Case 1: Find Which Database is Consuming CPU

**Step 1**: Run server-level collection
```sql
EXEC dbo.usp_CollectAllRDSMetrics @ServerID = 1;
```

**Step 2**: Run database-level collection
```sql
EXEC dbo.usp_CollectDatabaseMetrics @ServerID = 1;
```

**Step 3**: Query top databases
```sql
SELECT TOP 5
    DatabaseName,
    SUM(MetricValue) / 1000.0 AS TotalCPUSeconds
FROM dbo.DatabaseMetrics
WHERE MetricCategory = 'CPU'
  AND CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE())
GROUP BY DatabaseName
ORDER BY TotalCPUSeconds DESC;
```

### Use Case 2: Find Slowest Procedures in a Database

```sql
-- Find slowest procedures in DEV_SVDB_POS
SELECT TOP 10
    SchemaName + '.' + ProcedureName AS Procedure,
    ExecutionCount,
    AvgDurationMs,
    AvgCPUMs,
    LastExecutionTime
FROM dbo.ProcedureMetrics
WHERE DatabaseName = 'DEV_SVDB_POS'
  AND CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE())
ORDER BY AvgDurationMs DESC;
```

### Use Case 3: Find Queries with High Logical Reads (potential indexing issues)

```sql
SELECT TOP 10
    DatabaseName,
    AvgLogicalReads,
    ExecutionCount,
    AvgCPUMs,
    CAST(QueryText AS NVARCHAR(500)) AS QueryPreview
FROM dbo.QueryMetrics
WHERE CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE())
  AND AvgLogicalReads > 10000 -- Threshold
ORDER BY AvgLogicalReads DESC;
```

### Use Case 4: Identify Wait Events by Database

```sql
SELECT
    DatabaseName,
    WaitType,
    SUM(WaitTimeMs) AS TotalWaitMs,
    SUM(WaitingTasksCount) AS TotalWaits,
    AVG(MaxWaitTimeMs) AS AvgMaxWaitMs
FROM dbo.WaitEventsByDatabase
WHERE CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE())
GROUP BY DatabaseName, WaitType
ORDER BY TotalWaitMs DESC;
```

### Use Case 5: Find Databases with Blocking

```sql
SELECT
    DatabaseName,
    MAX(BlockedConnections) AS MaxBlocked,
    AVG(CAST(BlockedConnections AS DECIMAL(10,2))) AS AvgBlocked,
    MAX(CollectionTime) AS LastSeen
FROM dbo.ConnectionsByDatabase
WHERE CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE())
  AND BlockedConnections > 0
GROUP BY DatabaseName
ORDER BY MaxBlocked DESC;
```

---

## 🔧 Automated Collection Setup

### SQL Agent Job for Drill-Down Metrics

```sql
USE [msdb];
GO

-- Create job
EXEC dbo.sp_add_job
    @job_name = N'SQL Monitor - Drill-Down Collection',
    @enabled = 1;
GO

-- Add step
EXEC dbo.sp_add_jobstep
    @job_name = N'SQL Monitor - Drill-Down Collection',
    @step_name = N'Collect Drill-Down Metrics',
    @subsystem = N'TSQL',
    @database_name = N'MonitoringDB',
    @command = N'EXEC dbo.usp_CollectAllDrillDownMetrics @ServerID = 1;';
GO

-- Schedule every 5 minutes
EXEC dbo.sp_add_schedule
    @schedule_name = N'Every 5 Minutes - Drill-Down',
    @freq_type = 4,
    @freq_interval = 1,
    @freq_subday_type = 4,
    @freq_subday_interval = 5;
GO

-- Attach schedule
EXEC dbo.sp_attach_schedule
    @job_name = N'SQL Monitor - Drill-Down Collection',
    @schedule_name = N'Every 5 Minutes - Drill-Down';
GO

-- Add to local server
EXEC dbo.sp_add_jobserver
    @job_name = N'SQL Monitor - Drill-Down Collection';
GO
```

---

## 📊 Helper Views

### vw_TopDatabasesByCPU
Shows top databases by CPU usage (last 24 hours)

```sql
SELECT * FROM dbo.vw_TopDatabasesByCPU;
```

### vw_TopProceduresByCPU
Shows top procedures by average CPU (last 24 hours)

```sql
SELECT * FROM dbo.vw_TopProceduresByCPU
WHERE DatabaseName = 'DEV_SVDB_POS';
```

### vw_TopQueriesByCPU
Shows top queries by average CPU (last 24 hours)

```sql
SELECT * FROM dbo.vw_TopQueriesByCPU
WHERE DatabaseName = 'DEV_SVDB_POS';
```

---

## 🎨 Grafana Dashboard Layout

### Dashboard: Database Performance Drill-Down

**Row 1: Database Overview**
- Panel 1: Top 10 Databases by CPU (Bar Chart)
- Panel 2: Top 10 Databases by I/O (Bar Chart)
- Panel 3: Databases by Connection Count (Table)

**Row 2: Selected Database Details** (Variable: $database)
- Panel 4: CPU Trend for $database (Time Series)
- Panel 5: I/O Trend for $database (Time Series)
- Panel 6: Connections for $database (Time Series)

**Row 3: Procedure Analysis** (Variable: $database)
- Panel 7: Top 20 Procedures by CPU (Table with drill-down link)
- Panel 8: Procedure Execution Counts (Time Series)

**Row 4: Query Analysis** (Variable: $database)
- Panel 9: Top 20 Queries by CPU (Table)
- Panel 10: Query Execution Trends (Time Series)

**Row 5: Wait Events** (Variable: $database)
- Panel 11: Wait Types Breakdown (Pie Chart)
- Panel 12: Wait Time Trend (Stacked Area)

---

## ✅ Checklist

- [ ] Deploy drill-down tables (`06-create-drilldown-tables.sql`)
- [ ] Deploy drill-down procedures (`07-create-drilldown-procedures.sql`)
- [ ] Run initial collection: `EXEC dbo.usp_CollectAllDrillDownMetrics @ServerID = 1;`
- [ ] Create SQL Agent job for automated collection
- [ ] Create Grafana dashboard variables ($database, $procedure)
- [ ] Build drill-down dashboards in Grafana
- [ ] Test drill-down from Server → Database → Procedure → Query
- [ ] Set up alerts for top resource consumers

---

## 📝 Summary

**Drill-Down Capabilities**:
- ✅ Server-level aggregates (existing PerformanceMetrics table)
- ✅ Database-level metrics (DatabaseMetrics table)
- ✅ Stored procedure performance (ProcedureMetrics table)
- ✅ Individual query performance (QueryMetrics table)
- ✅ Wait events by database (WaitEventsByDatabase table)
- ✅ Connections by database (ConnectionsByDatabase table)

**Grafana Integration**:
- Dashboard variables for dynamic filtering
- Drill-down links between panels
- Time-series analysis at each level
- Top N rankings (databases, procedures, queries)

**This matches and exceeds AWS RDS Performance Insights drill-down capabilities!**
