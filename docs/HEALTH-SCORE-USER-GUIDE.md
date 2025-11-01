# SQL Server Health Score - User Guide

**Version**: 1.0
**Last Updated**: 2025-11-01
**Feature Status**: Production Ready

---

## Overview

The SQL Server Health Score provides a **single, easy-to-understand number (0-100)** that represents the overall health of your SQL Server instance. It combines 7 key performance indicators into a weighted score, similar to commercial solutions like Redgate SQL Monitor and SolarWinds DPA.

### Key Benefits

- **At-a-Glance Health**: See server health in seconds without analyzing dozens of metrics
- **Proactive Monitoring**: Catch problems before they become critical
- **Actionable Insights**: Each issue includes specific recommendations
- **Historical Trending**: Track health over time to identify degradation
- **Multi-Server View**: Compare health across all monitored servers

---

## Understanding the Health Score

### Score Ranges

| Score | Status | Color | Meaning |
|-------|--------|-------|---------|
| **80-100** | Healthy | Green | Server is performing well |
| **60-79** | Warning | Yellow | Some issues detected, investigate soon |
| **0-59** | Critical | Red | Serious problems, immediate attention required |

### Component Scores (7 Weighted)

The overall health score is calculated from 7 component scores:

| Component | Weight | What It Measures | Good | Warning | Critical |
|-----------|--------|------------------|------|---------|----------|
| **CPU** | 20% | Average CPU usage (last hour) | <60% | 60-90% | >90% |
| **Memory** | 20% | Page Life Expectancy (PLE) | >300s | 100-300s | <100s |
| **Disk I/O** | 15% | Read/write latency | <10ms | 10-50ms | >50ms |
| **Wait Stats** | 15% | % of "bad" waits (I/O, locking, parallelism) | <10% | 10-50% | >50% |
| **Blocking** | 10% | Blocking events per hour | <5 | 5-20 | >20 |
| **Index Health** | 10% | Average index fragmentation (>1000 pages) | <10% | 10-50% | >50% |
| **Query Performance** | 10% | Average query duration (Query Store) | <100ms | 100-1000ms | >1000ms |

**Formula**:
```
Overall Score = (CPU × 0.20) + (Memory × 0.20) + (Disk I/O × 0.15) +
                (Wait Stats × 0.15) + (Blocking × 0.10) + (Index × 0.10) +
                (Query × 0.10)
```

---

## Using the Grafana Dashboard

### Accessing the Dashboard

1. Open Grafana: `http://localhost:9001` (or your Grafana URL)
2. Navigate to **Dashboards** → **SQL Server Health Score**
3. Select a server from the **Server** dropdown at the top

### Dashboard Panels

#### 1. Overall Health Score Gauge

**Location**: Top-left
**Purpose**: Shows current health score with color-coded status

**Interpretation**:
- **Green (80-100)**: Server is healthy
- **Yellow (60-79)**: Some warnings, check component scores
- **Red (0-59)**: Critical issues, immediate action required

**Example**:
```
Score: 84.00 (Green)
Status: Healthy with minor warnings
```

#### 2. Health Score Trend Graph

**Location**: Top-right
**Purpose**: Historical health scores over time

**What to Look For**:
- **Stable line**: Consistent health
- **Gradual decline**: Potential growing problem
- **Sudden drop**: Recent change or incident
- **Spikes**: Intermittent issues

**Time Ranges**: Toggle between 24h, 7d, 30d views

#### 3. Component Scores Bar Gauge

**Location**: Middle section
**Purpose**: Breakdown of health by component

**How to Use**:
1. Identify which component(s) are low (red/yellow)
2. Focus troubleshooting on that area
3. Check the "Current Issues" table for details

**Example**:
```
CPU: 100 (green)
Memory: 50 (yellow) ← Focus here
Disk I/O: 100 (green)
Wait Stats: 100 (green)
Blocking: 100 (green)
Index: 40 (yellow) ← And here
Query: 100 (green)
```

#### 4. Current Issues Table

**Location**: Bottom-left
**Purpose**: Detailed list of current issues with recommendations

**Columns**:
- **Category**: Which component (CPU, Memory, etc.)
- **Severity**: Info, Warning, or Critical
- **Description**: What the problem is
- **Impact on Score**: How much this reduces the overall score
- **Recommended Action**: What to do about it

**Example**:
| Category | Severity | Description | Impact | Recommended Action |
|----------|----------|-------------|--------|-------------------|
| Memory | Warning | Low page life expectancy: 150 seconds | 10.0 | Consider adding more memory or reducing memory pressure |
| Index | Warning | High index fragmentation: 32.49% | 6.0 | Schedule index maintenance to rebuild fragmented indexes |

#### 5. Critical/Warning Issue Counts

**Location**: Bottom-middle
**Purpose**: Quick count of issues by severity

**Use Case**: Determine urgency without reading details

#### 6. Top Issue Panel

**Location**: Bottom-right
**Purpose**: Highlights the most impactful issue

**Use Case**: "What's the #1 thing I should fix right now?"

---

## Interpreting Scores & Taking Action

### Scenario 1: Low CPU Score (<60)

**Symptoms**:
- Overall score 60-75
- CPU component score 20-40
- High average CPU usage (>85%)

**Investigation Steps**:
1. Check **Top CPU Queries** dashboard
2. Review expensive stored procedures
3. Look for sudden changes in workload

**Recommended Actions**:
- Optimize slow queries (add indexes, rewrite queries)
- Consider scaling up (more CPU cores)
- Implement query result caching
- Review recent application deployments

**SQL Query to Investigate**:
```sql
-- Find top CPU-consuming queries (last hour)
SELECT TOP 10
    DatabaseName,
    QueryText,
    AvgDurationMs,
    TotalCPUTimeMs,
    ExecutionCount
FROM dbo.QueryStoreRuntimeStats rs
INNER JOIN dbo.QueryStoreQueries q ON rs.QueryStoreQueryID = q.QueryStoreQueryID
WHERE rs.CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE())
ORDER BY TotalCPUTimeMs DESC;
```

### Scenario 2: Low Memory Score (<60)

**Symptoms**:
- Overall score 60-75
- Memory component score 20-50
- Low Page Life Expectancy (<200 seconds)

**What PLE Means**:
- **PLE (Page Life Expectancy)**: How long a data page stays in memory
- **Good**: >300 seconds (pages stay in memory, less disk I/O)
- **Bad**: <100 seconds (constant disk I/O, "memory pressure")

**Investigation Steps**:
1. Check buffer pool usage
2. Review memory grants for queries
3. Look for memory leaks in application

**Recommended Actions**:
- Add more RAM (if physical memory is low)
- Optimize queries to reduce memory grants
- Review index strategy (missing indexes cause table scans)
- Consider enabling Query Store for analysis

**SQL Query to Investigate**:
```sql
-- Check current memory usage
SELECT
    (physical_memory_kb / 1024.0) AS PhysicalMemoryMB,
    (total_page_count * 8 / 1024.0) AS BufferPoolMB,
    (available_physical_memory_kb / 1024.0) AS AvailableMemoryMB
FROM sys.dm_os_sys_memory;
```

### Scenario 3: Low Index Health Score (<60)

**Symptoms**:
- Overall score 70-80
- Index component score 20-50
- High average fragmentation (>30%)

**What Fragmentation Means**:
- **<10%**: Good, no action needed
- **10-30%**: Reorganize indexes
- **>30%**: Rebuild indexes

**Recommended Actions**:
- Schedule index maintenance (rebuild/reorganize)
- Automate index maintenance (see Phase 3 Feature #4)
- Review fill factor settings
- Consider page compression for large tables

**SQL Query to Investigate**:
```sql
-- Find most fragmented indexes
SELECT TOP 10
    DatabaseName,
    SchemaName + '.' + TableName AS TableName,
    IndexName,
    FragmentationPercent,
    PageCount
FROM dbo.IndexFragmentation
WHERE ServerID = 1
  AND ScanDate >= DATEADD(DAY, -1, GETUTCDATE())
  AND PageCount > 1000
ORDER BY FragmentationPercent DESC;
```

**Quick Fix**:
```sql
-- Rebuild highly fragmented indexes
ALTER INDEX [IndexName] ON [Schema].[Table] REBUILD;

-- Or reorganize for moderate fragmentation
ALTER INDEX [IndexName] ON [Schema].[Table] REORGANIZE;
```

### Scenario 4: Low Blocking Score (<60)

**Symptoms**:
- Overall score 65-75
- Blocking component score 20-50
- High blocking event count (>20/hour)

**Investigation Steps**:
1. Check **Blocking Events** dashboard
2. Identify blocking chains (head blocker → victims)
3. Review long-running transactions

**Recommended Actions**:
- Optimize queries to reduce lock duration
- Review transaction isolation levels
- Implement NOLOCK hints (read-uncommitted) where appropriate
- Consider READ COMMITTED SNAPSHOT isolation
- Break up large transactions

**SQL Query to Investigate**:
```sql
-- Find recent blocking events
SELECT TOP 10
    EventTime,
    BlockingSessionID,
    BlockedSessionID,
    WaitTimeMs,
    WaitType,
    DatabaseName,
    BlockingQuery,
    BlockedQuery
FROM dbo.BlockingEvents
WHERE ServerID = 1
  AND EventTime >= DATEADD(HOUR, -1, GETUTCDATE())
ORDER BY WaitTimeMs DESC;
```

---

## Customizing Thresholds

Health score thresholds are configurable per environment. For example, a test environment might tolerate higher CPU usage than production.

### Viewing Current Thresholds

```sql
SELECT
    ComponentName,
    MetricName,
    CriticalThreshold,
    WarningThreshold,
    GoodThreshold,
    ComponentWeight
FROM dbo.HealthScoreThresholds
WHERE IsActive = 1
ORDER BY ComponentName;
```

### Adjusting Thresholds

**Example**: Increase CPU warning threshold from 90% to 95% for high-performance servers

```sql
UPDATE dbo.HealthScoreThresholds
SET WarningThreshold = 95.0
WHERE ComponentName = 'CPU' AND MetricName = 'CPUPercent';
```

**Example**: Decrease PLE warning threshold from 200s to 150s for smaller servers

```sql
UPDATE dbo.HealthScoreThresholds
SET WarningThreshold = 150.0
WHERE ComponentName = 'Memory' AND MetricName = 'PageLifeExpectancy';
```

**After changing thresholds**, health scores will be recalculated on the next collection (every 15 minutes).

---

## Querying Health Score Data

### Get Latest Health Score for a Server

```sql
EXEC dbo.usp_GetLatestHealthScores;
```

**Returns**:
- ServerID, ServerName, Environment
- Latest health score and calculation time
- Health status (Healthy/Warning/Critical)
- Critical and warning issue counts
- Top issue description

### Get Health Score History

```sql
-- Last 24 hours
EXEC dbo.usp_GetHealthScoreHistory
    @ServerID = 1,
    @StartTime = DATEADD(HOUR, -24, GETUTCDATE()),
    @EndTime = GETUTCDATE();
```

**Returns**:
- Time-series data for graphing
- All component scores at each calculation
- Issue counts over time

### Get Detailed Issues for Latest Score

```sql
-- Get latest health score ID
DECLARE @HealthScoreID BIGINT;
SELECT TOP 1 @HealthScoreID = HealthScoreID
FROM dbo.ServerHealthScore
WHERE ServerID = 1
ORDER BY CalculationTime DESC;

-- Get detailed issues
EXEC dbo.usp_GetHealthScoreIssues @HealthScoreID = @HealthScoreID;
```

**Returns**:
- Issue category, severity, description
- Impact on overall score
- Recommended action

---

## Troubleshooting

### Health Score Not Updating

**Problem**: Health scores haven't changed in >15 minutes

**Diagnosis**:
```sql
-- Check SQL Agent job status
SELECT
    j.name AS JobName,
    j.enabled AS Enabled,
    CASE WHEN ja.start_execution_date IS NOT NULL THEN 'Running' ELSE 'Idle' END AS Status
FROM msdb.dbo.sysjobs j
LEFT JOIN msdb.dbo.sysjobactivity ja ON j.job_id = ja.job_id
WHERE j.name = 'Calculate Server Health Scores';

-- Check last calculation time
SELECT
    s.ServerName,
    MAX(hs.CalculationTime) AS LastCalculation,
    DATEDIFF(MINUTE, MAX(hs.CalculationTime), GETUTCDATE()) AS MinutesAgo
FROM dbo.ServerHealthScore hs
INNER JOIN dbo.Servers s ON hs.ServerID = s.ServerID
GROUP BY s.ServerName;
```

**Solution**:
1. Verify SQL Agent service is running
2. Check job history for errors: `EXEC msdb.dbo.sp_help_jobhistory @job_name = 'Calculate Server Health Scores';`
3. Manually run job: `EXEC msdb.dbo.sp_start_job @job_name = 'Calculate Server Health Scores';`

### Score is 100 but Server Feels Slow

**Problem**: Health score shows 100 (perfect) but users report slow performance

**Possible Causes**:
1. **Query Store not enabled**: Query Performance component defaults to 100 if no data
2. **Recent change**: Health score is based on last hour; very recent issues may not show yet
3. **Application-level issues**: Problem is in the application, not SQL Server
4. **Network latency**: Between application and SQL Server

**Diagnosis**:
```sql
-- Check if Query Store is enabled
SELECT
    name AS DatabaseName,
    is_query_store_on AS QueryStoreEnabled
FROM sys.databases
WHERE is_query_store_on = 0
  AND state_desc = 'ONLINE'
  AND database_id > 4;

-- Check for very recent spikes (last 5 minutes)
SELECT
    hs.CalculationTime,
    hs.OverallHealthScore,
    hs.TopIssueDescription
FROM dbo.ServerHealthScore hs
WHERE hs.ServerID = 1
  AND hs.CalculationTime >= DATEADD(MINUTE, -5, GETUTCDATE())
ORDER BY hs.CalculationTime DESC;
```

**Solution**:
1. Enable Query Store on key databases
2. Check application logs for errors
3. Review network performance (ping times, packet loss)
4. Look at granular metrics (PerformanceMetrics table) for spikes

### Score Fluctuates Wildly

**Problem**: Health score swings between 70-100 every few minutes

**Cause**: Workload is highly variable (batch jobs, peak hours)

**Solution**: This is normal for some workloads. Focus on:
1. **Average score over time**: Is the trend up or down?
2. **Peak vs. off-peak**: Different thresholds for different times?
3. **Scheduled jobs**: Exclude known batch job times from alerting

**Advanced**: Create separate thresholds for peak/off-peak hours

---

## Best Practices

### 1. Review Health Scores Daily

**When**: Start of day, before critical operations

**What to Check**:
- Overall score for all servers
- Trending (up or down over last week)
- New critical issues

**Time Required**: 2-5 minutes

### 2. Investigate Warnings Promptly

**SLA**:
- **Critical (score <60)**: Investigate immediately
- **Warning (score 60-79)**: Investigate within 24 hours
- **Healthy (score 80+)**: No action needed

**Escalation**:
- If score drops below 60, page on-call DBA
- If score below 40 for >30 minutes, escalate to senior DBA

### 3. Track Score Improvements

**After fixing an issue**, verify health score improves:

1. Note score before fix (e.g., 72)
2. Implement fix (rebuild indexes, optimize query, etc.)
3. Wait 15-30 minutes for next calculation
4. Check score after fix (e.g., 86)
5. Document improvement in ticket

**Example**:
```
Before: 72 (Memory: 50, Index: 40)
Action: Rebuilt fragmented indexes, optimized top 5 queries
After: 86 (Memory: 50, Index: 85)
Result: +14 point improvement, index health resolved
```

### 4. Set Up Alerting (Future Feature)

**Recommended Alerts**:
- Overall score <60 for >15 minutes: Page on-call
- Overall score <80 for >1 hour: Email DBA team
- Critical issue count >2: Email DBA team
- Score dropped >20 points in 15 minutes: Immediate alert

---

## FAQ

### Q: Why is my score 84 instead of 100?

**A**: A score of 84 is **healthy**! It means minor warnings were detected (e.g., low memory PLE, some index fragmentation). These are normal and don't require immediate action, but should be monitored.

### Q: Can I exclude certain servers from health scoring?

**A**: Yes, set `IsActive = 0` in the `Servers` table:

```sql
UPDATE dbo.Servers
SET IsActive = 0
WHERE ServerName = 'dev-server-01';
```

### Q: How far back is historical data kept?

**A**: Currently, all health scores are kept indefinitely. For large environments, you may want to implement retention:

```sql
-- Delete health scores older than 90 days
DELETE FROM dbo.ServerHealthScore
WHERE CalculationTime < DATEADD(DAY, -90, GETUTCDATE());

DELETE FROM dbo.HealthScoreIssues
WHERE HealthScoreID NOT IN (SELECT HealthScoreID FROM dbo.ServerHealthScore);
```

### Q: Can I add custom components to the health score?

**A**: Yes! This requires modifying `usp_CalculateHealthScore`. For example, to add a "Backup Health" component:

1. Add thresholds to `HealthScoreThresholds` table
2. Calculate backup health score in `usp_CalculateHealthScore`
3. Add to weighted average formula
4. Add backup health score column to `ServerHealthScore` table

**Recommendation**: Submit this as a feature request for Phase 3 Feature #3 (Backup Verification).

### Q: What if Query Store is not enabled?

**A**: The Query Performance component will default to 100 (perfect score). To get accurate query performance scoring, enable Query Store on your databases:

```sql
ALTER DATABASE [YourDatabase]
SET QUERY_STORE = ON (
    OPERATION_MODE = READ_WRITE,
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    INTERVAL_LENGTH_MINUTES = 60,
    MAX_STORAGE_SIZE_MB = 1000
);
```

---

## Appendix: Component Calculation Details

### CPU Health Score

**Data Source**: `PerformanceMetrics` table, `MetricName = 'ProcessorTimePercent'`
**Time Window**: Last hour average

**Algorithm**:
```
IF AvgCPU > 95% THEN Score = 10 (Critical)
IF AvgCPU > 90% THEN Score = 20
IF AvgCPU > 85% THEN Score = 30
IF AvgCPU > 80% THEN Score = 40
IF AvgCPU > 70% THEN Score = 60
IF AvgCPU > 60% THEN Score = 80
ELSE Score = 100 - AvgCPU
```

### Memory Health Score

**Data Source**: `PerformanceMetrics` table, `MetricName = 'PageLifeExpectancy'`
**Time Window**: Last hour average

**Algorithm**:
```
IF AvgPLE < 100s THEN Score = 20 (Critical)
IF AvgPLE < 200s THEN Score = 50 (Warning)
IF AvgPLE < 300s THEN Score = 70
ELSE Score = 100 (Good)
```

### Disk I/O Health Score

**Data Source**: `PerformanceMetrics` table, `MetricName = 'AvgDiskSecRead'/'AvgDiskSecWrite'`
**Time Window**: Last hour average
**Unit Conversion**: Seconds → Milliseconds (× 1000)

**Algorithm**:
```
IF AvgLatency > 100ms THEN Score = 10 (Critical)
IF AvgLatency > 50ms THEN Score = 20
IF AvgLatency > 20ms THEN Score = 50 (Warning)
IF AvgLatency > 10ms THEN Score = 80
ELSE Score = 100 (Good, <10ms)
```

### Wait Stats Health Score

**Data Source**: `WaitStatsSnapshot` table
**Time Window**: Last hour
**Categories**: Bad waits = I/O + Locking + Parallelism waits

**Algorithm**:
```
BadWaitPercent = (SUM(IO + Locking + Parallelism waits) / SUM(ALL waits)) × 100

IF BadWaitPercent > 50% THEN Score = 20 (Critical)
IF BadWaitPercent > 30% THEN Score = 40 (Warning)
IF BadWaitPercent > 10% THEN Score = 70
ELSE Score = 100 (Good, <10% bad waits)
```

### Blocking Health Score

**Data Source**: `BlockingEvents` table
**Time Window**: Last hour
**Metric**: Count of blocking events

**Algorithm**:
```
IF BlockingCount > 50 THEN Score = 10 (Critical)
IF BlockingCount > 20 THEN Score = 20
IF BlockingCount > 10 THEN Score = 40 (Warning)
IF BlockingCount > 5 THEN Score = 60
IF BlockingCount > 0 THEN Score = 80
ELSE Score = 100 (No blocking)
```

### Index Health Score

**Data Source**: `IndexFragmentation` table
**Time Window**: Last day
**Filter**: Only indexes with >1000 pages (exclude tiny indexes)

**Algorithm**:
```
AvgFragmentation = AVG(FragmentationPercent) for indexes >1000 pages

IF AvgFragmentation > 50% THEN Score = 20 (Critical)
IF AvgFragmentation > 30% THEN Score = 40 (Warning)
IF AvgFragmentation > 10% THEN Score = 70
ELSE Score = 100 (Good, <10% fragmentation)
```

### Query Performance Health Score

**Data Source**: `QueryStoreRuntimeStats` + `QueryStoreQueries` tables
**Time Window**: Last hour
**Metric**: Average query duration

**Algorithm**:
```
AvgDuration = AVG(AvgDurationMs) for all queries

IF AvgDuration > 1000ms THEN Score = 20 (Critical, >1 second)
IF AvgDuration > 500ms THEN Score = 50 (Warning)
IF AvgDuration > 100ms THEN Score = 80
ELSE Score = 100 (Good, <100ms)
```

**Note**: If Query Store is not enabled, defaults to Score = 100.

---

## Support & Feedback

**Questions?** Check the FAQ above or review stored procedures in `database/41-create-health-score-procedures.sql`

**Found a Bug?** Report in project issues with health score details and expected vs. actual behavior

**Feature Request?** Suggest new components or threshold adjustments in project discussions

---

**Document Version**: 1.0
**Last Updated**: 2025-11-01
**Author**: SQL Monitor Project Team
