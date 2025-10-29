# SQL Server Health Metrics - Interpretation Guide

**Purpose:** Help you understand what the numbers mean and when to take action
**Audience:** DBAs, developers, system administrators
**Last Updated:** 2025-10-27

---

## Table of Contents

1. [Server Health Metrics](#server-health-metrics)
2. [Database Metrics](#database-metrics)
3. [Query Performance Metrics](#query-performance-metrics)
4. [Missing Indexes Metrics](#missing-indexes-metrics)
5. [Summary Statistics](#summary-statistics)
6. [Error Log Interpretation](#error-log-interpretation)
7. [When to Take Action](#when-to-take-action)
8. [Common Scenarios](#common-scenarios)

---

## Server Health Metrics

### 1. CPU Signal Wait %

**What it measures:** Percentage of time SQL Server is waiting for CPU (signal waits)

**Formula:** `(Signal Wait Time / Total Wait Time) × 100`

#### Interpretation

| Value | Status | Meaning | Action |
|-------|--------|---------|--------|
| **0-5%** | ✅ INFO | CPU is not a bottleneck | No action needed |
| **5-10%** | ✅ INFO | Normal CPU usage | Monitor trends |
| **10-20%** | ⚠️ ATTENTION | Moderate CPU pressure | Review top CPU queries |
| **20-40%** | ⚠️ WARNING | Elevated CPU usage | Investigate and optimize queries |
| **40%+** | 🔴 CRITICAL | High CPU pressure | Immediate action required |

#### What causes high CPU?

1. **Inefficient queries** - Missing indexes, table scans, complex calculations
2. **High concurrency** - Too many simultaneous queries
3. **Application issues** - Excessive query frequency
4. **Missing statistics** - Poor execution plans
5. **Hardware limits** - Not enough CPU cores

#### Recommended Actions

**10-20% (Attention):**
- Review top CPU-consuming queries
- Check for missing indexes
- Update statistics

**20-40% (Warning):**
- Identify and optimize expensive queries
- Consider query result caching
- Review application query patterns
- Check for index fragmentation

**40%+ (Critical):**
- Kill long-running expensive queries
- Implement query throttling
- Add CPU cores if hardware-limited
- Consider read replicas for reporting

#### Example
```
CPU Signal Wait Pct: 35%
Analysis: Elevated CPU usage - investigate expensive queries
Recommendation: Review top CPU consumers and optimize
```
**Action:** Check "Top 10 Slow Queries per Database" section for high CPU queries

---

### 2. Blocking Sessions

**What it measures:** Number of sessions currently blocked by other sessions

**Technical:** Count of sessions in `sys.dm_exec_requests` where `blocking_session_id > 0`

#### Interpretation

| Count | Status | Meaning | Action |
|-------|--------|---------|--------|
| **0-5** | ✅ INFO | Normal lock contention | No action needed |
| **6-15** | ⚠️ ATTENTION | Moderate blocking | Monitor blocking chains |
| **16-30** | ⚠️ WARNING | High blocking | Investigate lock holders |
| **30+** | 🔴 CRITICAL | Severe blocking | Kill blocking sessions |

#### What causes blocking?

1. **Long-running transactions** - Large updates/deletes without batching
2. **Missing indexes** - Queries take locks for too long
3. **Lock escalation** - Row locks escalate to table locks
4. **Deadlock resolution** - One transaction chosen as victim
5. **Application design** - Transactions held open unnecessarily

#### Recommended Actions

**6-15 (Attention):**
```sql
-- Find blocking chains
SELECT
    blocking_session_id,
    session_id,
    wait_type,
    wait_time,
    status,
    command
FROM sys.dm_exec_requests
WHERE blocking_session_id > 0
ORDER BY blocking_session_id
```

**16-30 (Warning):**
```sql
-- Identify head blocker
SELECT TOP 10
    session_id,
    status,
    command,
    cpu_time,
    total_elapsed_time,
    blocking_session_id
FROM sys.dm_exec_requests
WHERE session_id IN (
    SELECT DISTINCT blocking_session_id
    FROM sys.dm_exec_requests
    WHERE blocking_session_id > 0
)
```

**30+ (Critical):**
```sql
-- Kill head blocker (use with caution!)
KILL <session_id>
```

#### Prevention Strategies

1. **Batch large operations** - Break updates into smaller chunks
2. **Use NOLOCK** - For read-only queries (accepts dirty reads)
3. **Optimize indexes** - Reduce query duration
4. **Reduce transaction scope** - Keep transactions short
5. **Use snapshot isolation** - Reduces blocking (requires tempdb space)

---

### 3. Recent Deadlocks

**What it measures:** Number of deadlocks in the last 10 minutes (from system_health XEvent)

**Technical:** Count from `sys.fn_xe_file_target_read_file` where event = 'xml_deadlock_report'

#### Interpretation

| Count | Status | Meaning | Action |
|-------|--------|---------|--------|
| **0** | ✅ INFO | No deadlocks detected | No action needed |
| **1-4** | ⚠️ WARNING | Some deadlocks occurring | Review deadlock graphs |
| **5+** | 🔴 CRITICAL | Frequent deadlocks | Immediate investigation |

#### What causes deadlocks?

1. **Lock order inversion** - Two transactions acquire locks in opposite order
2. **Missing indexes** - Queries scan large tables, increasing lock duration
3. **High concurrency** - Many transactions competing for same resources
4. **Application design** - Poor transaction design

#### How to investigate

**View deadlock graph:**
```sql
-- Get recent deadlock details
SELECT
    CAST(target_data AS XML) AS DeadlockGraph
FROM sys.dm_xe_session_targets t
JOIN sys.dm_xe_sessions s ON s.address = t.event_session_address
WHERE s.name = 'system_health'
  AND t.target_name = 'ring_buffer'
```

**Look for in deadlock graph:**
- Tables/objects involved
- Queries causing deadlock
- Lock types (RID, KEY, PAGE, TABLE)
- Victim selection (which transaction was rolled back)

#### Recommended Actions

**1-4 deadlocks:**
- Capture deadlock graph for analysis
- Identify resource contention points
- Review transaction isolation levels

**5+ deadlocks:**
- Implement retry logic in application
- Reorder operations to access tables consistently
- Reduce transaction scope
- Add indexes to reduce scan time
- Consider partitioning for large tables

#### Prevention Strategies

1. **Consistent access order** - Always access tables in same order
2. **Keep transactions short** - Minimize lock hold time
3. **Use lower isolation levels** - READ COMMITTED SNAPSHOT
4. **Add indexes** - Reduce lock escalation
5. **Batch operations** - Smaller batches = shorter locks

---

### 4. Memory Grant Warnings

**What it measures:** Number of queries that spilled to tempdb due to insufficient memory (last 10 minutes)

**Technical:** Count from system_health XEvent where `sort_warning` or `hash_warning` occurred

#### Interpretation

| Count | Status | Meaning | Action |
|-------|--------|---------|--------|
| **0** | ✅ INFO | No memory spills | No action needed |
| **1-9** | ⚠️ WARNING | Some memory pressure | Review query memory grants |
| **10+** | 🔴 CRITICAL | Frequent spills | Optimize queries or add RAM |

#### What causes memory spills?

1. **Insufficient memory grants** - Query estimated fewer rows than actual
2. **Outdated statistics** - Poor cardinality estimates
3. **Complex queries** - Large sorts, hash joins
4. **Concurrent queries** - Many queries competing for memory
5. **Server memory limits** - Not enough total RAM

#### Performance Impact

**Memory spill to tempdb:**
- **10-100× slower** than in-memory operations
- Increases tempdb I/O
- Can cause tempdb contention
- Degrades overall server performance

#### Recommended Actions

**1-9 warnings:**
```sql
-- Find queries with memory grants
SELECT TOP 10
    text,
    granted_memory_kb,
    used_memory_kb,
    ideal_memory_kb,
    execution_count
FROM sys.dm_exec_query_memory_grants
ORDER BY granted_memory_kb DESC
```

**10+ warnings:**
```sql
-- Update statistics to improve estimates
EXEC sp_updatestats

-- Rebuild indexes (updates stats automatically)
ALTER INDEX ALL ON TableName REBUILD

-- Increase memory for specific queries
OPTION (QUERYTRACEON 2388) -- Better cardinality estimates
```

#### Prevention Strategies

1. **Update statistics** - Keep them current with AUTO_UPDATE_STATISTICS
2. **Optimize queries** - Reduce row counts in intermediate steps
3. **Add indexes** - Reduce rows scanned
4. **Increase server memory** - If hardware allows
5. **Use query hints** - OPTION (RECOMPILE) for better estimates

---

### 5. Top Wait Type

**What it measures:** The wait type consuming the most time on the server

**Common wait types:**

#### I/O-Related Waits
| Wait Type | Meaning | Action |
|-----------|---------|--------|
| **PAGEIOLATCH_SH** | Reading data pages from disk | Add RAM, optimize queries |
| **PAGEIOLATCH_EX** | Writing data pages to disk | Faster disks, reduce writes |
| **WRITELOG** | Waiting for log writes | Faster log disk, batch commits |
| **IO_COMPLETION** | Waiting for I/O to complete | Check disk performance |

#### CPU-Related Waits
| Wait Type | Meaning | Action |
|-----------|---------|--------|
| **SOS_SCHEDULER_YIELD** | CPU pressure, queries yielding | Optimize queries, add CPUs |
| **CXPACKET** | Parallel query coordination | Tune MAXDOP, review parallelism |

#### Lock-Related Waits
| Wait Type | Meaning | Action |
|-----------|---------|--------|
| **LCK_M_X** | Exclusive lock wait | Reduce transaction time |
| **LCK_M_S** | Shared lock wait | Add indexes, use NOLOCK |

#### Memory-Related Waits
| Wait Type | Meaning | Action |
|-----------|---------|--------|
| **RESOURCE_SEMAPHORE** | Waiting for query memory | Add RAM, optimize queries |
| **PAGEIOLATCH_** | Page latch waits | Add RAM for buffer cache |

---

## Database Metrics

### 1. Database Size

**What it measures:** Total space used by data files and log files

#### Data File Size

| Size | Typical Use | Consideration |
|------|-------------|---------------|
| **< 1 GB** | Small app database | Normal |
| **1-10 GB** | Medium app database | Monitor growth |
| **10-100 GB** | Large app database | Plan for growth |
| **100 GB - 1 TB** | Very large database | Partitioning recommended |
| **1 TB+** | Enterprise database | Advanced strategies needed |

#### Log File Size

**Normal:** Log size should be 10-25% of data size

**Concerning scenarios:**

| Condition | Meaning | Action |
|-----------|---------|--------|
| **Log > Data** | Log not truncating | Check log reuse wait |
| **Log > 50% data** | Excessive logging | Review recovery model |
| **Rapid growth** | Large transactions | Batch operations |

#### Example Interpretation

```
Database: DB_Production
Data Size: 450 GB
Log Size: 120 GB (27% of data)
Status: ⚠️ Log size acceptable but monitor
```

**Action:** Check "Log Reuse Wait" column

---

### 2. Recovery Model

**What it measures:** How SQL Server handles transaction logging and recovery

#### Recovery Models

| Model | Purpose | Log Behavior | Backups Required |
|-------|---------|--------------|------------------|
| **SIMPLE** | Dev/test, data warehouses | Auto-truncated on checkpoint | Full + Differential |
| **FULL** | Production databases | Never auto-truncated | Full + Differential + Log |
| **BULK_LOGGED** | Large bulk imports | Minimally logged for bulk ops | Full + Differential + Log |

#### Recommendations by Database Type

**Production (OLTP):**
```
✅ Use: FULL recovery model
Why: Point-in-time recovery needed
Requirement: Regular log backups (hourly)
```

**Data Warehouse:**
```
✅ Use: SIMPLE or BULK_LOGGED
Why: Can reload data from source
Benefit: Minimal log space
```

**Development/Test:**
```
✅ Use: SIMPLE
Why: Recovery not critical
Benefit: No log backup needed
```

---

### 3. Log Reuse Wait

**What it measures:** What is preventing log truncation

#### Common Values

| Wait Description | Meaning | Action |
|------------------|---------|--------|
| **NOTHING** | ✅ Log truncating normally | No action needed |
| **ACTIVE_TRANSACTION** | 🔴 Long-running transaction | Find and commit/rollback |
| **LOG_BACKUP** | ⚠️ No log backup taken | Take log backup immediately |
| **REPLICATION** | ⚠️ Replication lagging | Check replication status |
| **DATABASE_MIRRORING** | ⚠️ Mirroring lagging | Check mirror status |
| **AVAILABILITY_REPLICA** | ⚠️ AG replica lagging | Check AG synchronization |

#### Critical Issues

**LOG_BACKUP (FULL recovery):**
```sql
-- Log backup overdue
-- Log will grow until backup taken

-- Action: Immediate log backup
BACKUP LOG DatabaseName TO DISK = 'path\to\backup.trn'
```

**ACTIVE_TRANSACTION:**
```sql
-- Find long-running transaction
SELECT
    session_id,
    transaction_id,
    DATEDIFF(MINUTE, transaction_begin_time, GETDATE()) AS MinutesOpen,
    [text]
FROM sys.dm_tran_active_transactions t
JOIN sys.dm_exec_sessions s ON t.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(s.most_recent_sql_handle)
WHERE DATEDIFF(MINUTE, transaction_begin_time, GETDATE()) > 60
ORDER BY transaction_begin_time
```

---

## Query Performance Metrics

### 1. Total CPU (ms)

**What it measures:** Total CPU time consumed by query across all executions

**Formula:** `Avg CPU per execution × Execution count`

#### Interpretation

| Value | Priority | Action |
|-------|----------|--------|
| **> 1,000,000** | 🔴 Critical | Optimize immediately |
| **500,000 - 1,000,000** | ⚠️ High | Review execution plan |
| **100,000 - 500,000** | ⚠️ Medium | Monitor and optimize |
| **< 100,000** | ✅ Low | No immediate action |

#### What makes total CPU high?

1. **High per-execution cost + many executions** (Common)
   ```
   Example: 100ms per execution × 10,000 executions = 1,000,000ms total
   ```

2. **Very expensive query + few executions** (Less common)
   ```
   Example: 10,000ms per execution × 100 executions = 1,000,000ms total
   ```

#### Analysis Pattern

```
Query: SELECT * FROM Orders WHERE OrderDate > ...
Total CPU: 2,345,678 ms
Avg Duration: 234.56 ms
Execution Count: 10,000

Analysis:
✅ Not too slow per execution (234ms)
🔴 But executes 10,000 times!
💡 Total impact: 2.3 million ms = 39 minutes of CPU time

Recommendation:
- Add index on OrderDate
- Cache results in application
- Reduce query frequency
```

---

### 2. Avg Duration (ms)

**What it measures:** Average elapsed time per query execution

**Includes:** CPU time + wait time (I/O, locks, etc.)

#### Interpretation

| Value | User Impact | Action |
|-------|-------------|--------|
| **< 100ms** | ✅ Fast | No action needed |
| **100-500ms** | ⚠️ Acceptable | Monitor trends |
| **500-2000ms** | ⚠️ Slow | Optimize query |
| **2000-5000ms** | 🔴 Very slow | Urgent optimization |
| **> 5000ms** | 🔴 Extremely slow | Immediate action |

#### Breaking Down Duration

```sql
-- Duration breakdown
Duration = CPU Time + Wait Time

Where Wait Time includes:
- Disk I/O waits (reading data)
- Lock waits (blocking)
- Memory waits (tempdb spills)
- Network waits (result set transfer)
```

#### Example Analysis

**Query A:**
```
Avg Duration: 1,500 ms
Avg CPU: 100 ms
Avg Reads: 500,000 pages

Analysis:
Duration (1500ms) >> CPU (100ms)
Wait time = 1400ms (93% of duration)
High reads = I/O bound query

Action: Add index to reduce reads
```

**Query B:**
```
Avg Duration: 1,200 ms
Avg CPU: 1,150 ms
Avg Reads: 1,000 pages

Analysis:
Duration (1200ms) ≈ CPU (1150ms)
Wait time = 50ms (4% of duration)
Low reads = CPU bound query

Action: Optimize query logic, reduce calculations
```

---

### 3. Execution Count

**What it measures:** Number of times query has executed since cache

**Context:** Since last server restart or plan eviction

#### Interpretation

| Count | Pattern | Consideration |
|-------|---------|---------------|
| **1-100** | Rare query | Low total impact |
| **100-1,000** | Occasional | Monitor if expensive |
| **1,000-10,000** | Frequent | Optimize if slow |
| **10,000-100,000** | Very frequent | Must be fast |
| **100,000+** | Extremely frequent | Cache or redesign |

#### High Execution Count Analysis

**Good scenario:**
```
Query: SELECT UserID, Name FROM Users WHERE UserID = @ID
Execution Count: 50,000
Avg Duration: 2 ms
Total CPU: 100,000 ms

Analysis:
✅ Fast query (2ms)
✅ High reuse (50k executions)
✅ Low total impact (100 seconds)
Status: Efficient, no action needed
```

**Bad scenario:**
```
Query: SELECT * FROM Orders WHERE OrderDate > @Date
Execution Count: 10,000
Avg Duration: 500 ms
Total CPU: 5,000,000 ms

Analysis:
🔴 Slow query (500ms)
🔴 Frequent execution (10k times)
🔴 Huge total impact (83 minutes)
Status: Critical - optimize immediately
```

#### When High Count is a Problem

1. **In loops** - Application calling query repeatedly
   ```
   Bad: for (int i = 0; i < 10000; i++) { SELECT * FROM ... }
   Good: SELECT * FROM ... (get all at once)
   ```

2. **Polling** - Constant checking for changes
   ```
   Bad: Every second: SELECT COUNT(*) FROM NewOrders
   Good: Use triggers, Service Broker, or SignalR
   ```

3. **No caching** - Application not reusing results
   ```
   Bad: Query database for every page view
   Good: Cache in Redis/Memcached for 5 minutes
   ```

---

### 4. Avg Logical Reads

**What it measures:** Average number of 8KB pages read from memory or disk per execution

**Technical:** `logical_reads / execution_count`

#### Interpretation

| Reads | Impact | Action |
|-------|--------|--------|
| **< 100** | ✅ Excellent | No action |
| **100-1,000** | ✅ Good | Monitor |
| **1,000-10,000** | ⚠️ Moderate | Review indexes |
| **10,000-100,000** | ⚠️ High | Optimize query |
| **100,000+** | 🔴 Very high | Urgent optimization |

#### What Causes High Reads?

1. **Table scans** - Reading entire table
2. **Missing indexes** - Can't seek to specific rows
3. **SELECT *** - Retrieving unnecessary columns
4. **Large result sets** - Returning many rows

#### Page Read Examples

```sql
-- Example table: 1 million rows, 80 bytes per row
-- Page size: 8KB = 8,192 bytes
-- Rows per page: ~100 rows

-- Scenario 1: Index seek (specific row)
SELECT * FROM Users WHERE UserID = 123
Logical Reads: 3 pages (root + intermediate + leaf)
Status: ✅ Excellent

-- Scenario 2: Index scan (all users in city)
SELECT * FROM Users WHERE City = 'Seattle'
Rows returned: 10,000
Logical Reads: 100 pages (10,000 rows / 100 per page)
Status: ⚠️ Moderate - consider filtered index

-- Scenario 3: Table scan (no index)
SELECT * FROM Users WHERE LastLogin > GETDATE()-7
Logical Reads: 10,000 pages (entire table)
Status: 🔴 Critical - add index on LastLogin
```

#### Optimization Strategy

**Step 1: Identify high-read queries**
```sql
SELECT TOP 10
    text,
    total_logical_reads / execution_count AS avg_reads,
    execution_count
FROM sys.dm_exec_query_stats
CROSS APPLY sys.dm_exec_sql_text(sql_handle)
ORDER BY total_logical_reads DESC
```

**Step 2: Check for missing indexes**
```sql
-- See "Missing Indexes" section in report
```

**Step 3: Review execution plan**
```
Look for:
- Table Scans (🔴 bad)
- Index Scans (⚠️ moderate)
- Index Seeks (✅ good)
```

**Step 4: Add covering indexes**
```sql
-- Include all columns in SELECT to avoid lookups
CREATE INDEX IX_Covering ON Users (City)
INCLUDE (UserID, Name, Email)
```

---

## Missing Indexes Metrics

### 1. Avg User Impact

**What it measures:** Estimated percentage improvement in query cost if index were added

**Range:** 0-100%

#### Interpretation

| Impact % | Priority | Action |
|----------|----------|--------|
| **90-100%** | 🔴 Critical | Create immediately |
| **75-90%** | ⚠️ High | Create soon |
| **50-75%** | ⚠️ Medium | Schedule creation |
| **25-50%** | ⚠️ Low | Consider if space allows |
| **< 25%** | ℹ️ Minimal | Probably not worth it |

#### What Does Impact Mean?

```
Avg User Impact: 85%

Interpretation:
If you create this index, queries using it will be
approximately 85% faster (or use 85% less resources).

Example:
Current query time: 1000ms
With index: ~150ms (85% improvement)
```

#### Caveat: Impact is Estimated

**SQL Server's estimate based on:**
- Query compilation history
- Cardinality estimates
- Cost-based optimizer calculations

**May not be exact because:**
- Statistics may be outdated
- Actual usage patterns may differ
- Other indexes may also help

**Best practice:** Create high-impact indexes and measure actual improvement

---

### 2. User Seeks

**What it measures:** Number of times queries would have used this index if it existed

**Context:** Since last restart

#### Interpretation

| Seeks | Frequency | Priority |
|-------|-----------|----------|
| **> 10,000** | Very high | Create immediately |
| **1,000-10,000** | High | Create soon |
| **100-1,000** | Moderate | Consider |
| **10-100** | Low | Evaluate cost/benefit |
| **< 10** | Very low | Probably skip |

#### Combined Analysis: Impact + Seeks

**High impact + high seeks = MUST CREATE:**
```
Avg User Impact: 92%
User Seeks: 25,000

Analysis:
🔴 92% improvement potential
🔴 Used 25,000 times
💡 Impact Score: 25,000 × 92% = 2,300,000

Action: Create this index immediately!
```

**High impact + low seeks = MAYBE CREATE:**
```
Avg User Impact: 88%
User Seeks: 15

Analysis:
✅ 88% improvement potential
⚠️ Only used 15 times
💡 Impact Score: 15 × 88% = 1,320

Action: Low priority - only if space available
```

**Low impact + high seeks = PROBABLY CREATE:**
```
Avg User Impact: 35%
User Seeks: 50,000

Analysis:
⚠️ 35% improvement (moderate)
🔴 Used 50,000 times!
💡 Impact Score: 50,000 × 35% = 1,750,000

Action: Create - frequent use justifies moderate improvement
```

---

### 3. Impact Score

**What it measures:** `User Seeks × Avg User Impact`

**Purpose:** Prioritization - which index gives best overall improvement

#### Interpretation

| Score | Priority | Action |
|-------|----------|--------|
| **> 1,000,000** | 🔴 Critical | Create first |
| **500,000-1,000,000** | ⚠️ High | Create in batch 1 |
| **100,000-500,000** | ⚠️ Medium | Create in batch 2 |
| **10,000-100,000** | ℹ️ Low | Create if space allows |
| **< 10,000** | ℹ️ Very low | Skip |

#### Example Prioritization

```
Index 1: Score = 2,500,000 (Impact: 90%, Seeks: 27,778)
Index 2: Score = 1,800,000 (Impact: 60%, Seeks: 30,000)
Index 3: Score = 950,000 (Impact: 95%, Seeks: 10,000)
Index 4: Score = 450,000 (Impact: 30%, Seeks: 15,000)

Priority Order:
1st: Index 1 - Highest overall impact
2nd: Index 2 - High frequency with good impact
3rd: Index 3 - Excellent impact but less frequent
4th: Index 4 - Lowest combined benefit
```

---

### 4. Equality vs Inequality Columns

**What it measures:** Columns used in WHERE clause predicates

#### Column Types

**Equality Columns:**
```sql
-- Exact match predicates
WHERE CustomerID = 123
WHERE Status = 'Active'
WHERE OrderDate = '2024-01-01'
```

**Inequality Columns:**
```sql
-- Range predicates
WHERE OrderDate > '2024-01-01'
WHERE Amount BETWEEN 100 AND 500
WHERE Price < 50
```

**Included Columns:**
```sql
-- Columns in SELECT but not in WHERE
-- Adding these prevents key lookups
SELECT CustomerName, Email  -- These become INCLUDE columns
FROM Customers
WHERE CustomerID = 123  -- This is equality column
```

#### Index Structure

**Best practice order:**
```sql
CREATE INDEX IX_Example ON TableName
(
    -- 1. Equality columns first (most selective)
    EqualityColumn1,
    EqualityColumn2,

    -- 2. Inequality columns last
    InequalityColumn
)
INCLUDE
(
    -- 3. Included columns (for covering)
    SelectColumn1,
    SelectColumn2
)
```

#### Why Order Matters

**Good example:**
```sql
-- Query
SELECT Name, Email
FROM Users
WHERE City = 'Seattle'  -- Equality
  AND LastLogin > '2024-01-01'  -- Inequality

-- Optimal index
CREATE INDEX IX_Users_City_LastLogin ON Users
(
    City,        -- Equality first
    LastLogin    -- Inequality last
)
INCLUDE (Name, Email)  -- Covering
```

**Bad example:**
```sql
-- Wrong order - inequality before equality
CREATE INDEX IX_Users_Bad ON Users
(
    LastLogin,   -- ❌ Inequality first (less selective)
    City         -- ❌ Equality last
)
```

---

## Summary Statistics

### 1. Total Snapshots

**What it measures:** Number of 5-minute snapshots collected in the lookback period

**Expected values:**
- 48 hours = 576 snapshots (48 × 12 per hour)
- 24 hours = 288 snapshots
- 12 hours = 144 snapshots

#### Interpretation

| Count vs Expected | Status | Action |
|-------------------|--------|--------|
| **100%** | ✅ Normal | Collection working |
| **90-99%** | ⚠️ Minor gaps | Check job history |
| **< 90%** | 🔴 Collection issues | Investigate job failures |

#### Example
```
Total Snapshots: 145
Lookback Period: 48 hours
Expected: 576
Coverage: 25%

Analysis: 🔴 Major data gaps - collection not running consistently
Action: Check SQL Agent job "DBA Collect Perf Snapshot"
```

---

### 2. Avg/Max CPU Signal Wait %

**What it measures:**
- **Avg:** Average CPU pressure over time period
- **Max:** Highest CPU pressure spike

#### Interpretation

**Avg CPU Signal Wait:**
```
< 10%: ✅ Healthy CPU usage
10-20%: ⚠️ Moderate pressure - monitor
20-30%: ⚠️ Elevated pressure - investigate
> 30%: 🔴 Chronic CPU issues - urgent optimization
```

**Max CPU Signal Wait:**
```
< 20%: ✅ No severe spikes
20-40%: ⚠️ Occasional spikes - acceptable
40-60%: ⚠️ Frequent spikes - investigate
> 60%: 🔴 Severe spikes - immediate action
```

#### Example Analysis

**Scenario 1: Healthy**
```
Avg CPU: 8%
Max CPU: 15%

Analysis: ✅ Healthy
- Normal average usage
- Small spikes (not concerning)
- System has capacity headroom
```

**Scenario 2: Spike Pattern**
```
Avg CPU: 12%
Max CPU: 65%

Analysis: ⚠️ Investigate spikes
- Average is acceptable
- But severe spikes occurring
- Likely batch jobs or scheduled reports

Action: Find what causes spikes (check top CPU queries during spike times)
```

**Scenario 3: Chronic High**
```
Avg CPU: 45%
Max CPU: 78%

Analysis: 🔴 Critical
- Chronic high CPU pressure
- Severe spikes on top of high baseline
- System capacity exceeded

Action: Urgent optimization or add CPU cores
```

---

### 3. Snapshots with Blocking

**What it measures:** How many snapshots showed blocking (out of total)

**Formula:** `COUNT(snapshots where blocking > 0) / Total snapshots × 100`

#### Interpretation

| % of Snapshots | Status | Action |
|----------------|--------|--------|
| **0-10%** | ✅ Normal | Acceptable blocking |
| **10-25%** | ⚠️ Moderate | Review blocking patterns |
| **25-50%** | ⚠️ High | Investigate lock contention |
| **> 50%** | 🔴 Severe | Critical blocking issues |

#### Example

```
Snapshots with Blocking: 145 out of 576
Percentage: 25%

Analysis: ⚠️ Blocking in 1 of 4 snapshots
Pattern: Likely specific times of day (batch processes?)

Action:
1. Check what time blocking occurs (review snapshot times)
2. Identify blocking queries during those times
3. Optimize or reschedule blocking operations
```

---

## Error Log Interpretation

### Common Error Patterns

#### 1. Informational Messages
```
Pattern: "SQL Server started", "Backup completed"
Status: ✅ Normal
Action: None
```

#### 2. I/O Warnings
```
Pattern: "SQL Server has encountered X occurrence(s) of I/O requests taking longer than 15 seconds"
Status: ⚠️ Disk performance issue
Action: Check disk latency, review storage
```

#### 3. Deadlock Messages
```
Pattern: "Transaction was deadlocked"
Status: ⚠️ Application design issue
Action: Review deadlock graph, optimize queries
```

#### 4. Memory Pressure
```
Pattern: "A significant part of sql server process memory has been paged out"
Status: 🔴 Memory issue
Action: Add RAM or reduce max server memory
```

#### 5. Login Failures
```
Pattern: "Login failed for user 'X'"
Status: ⚠️ Security or connection issue
Action: Check credentials, connection strings
```

---

## When to Take Action

### Immediate Action Required (🔴 Critical)

| Metric | Threshold | Impact | Action |
|--------|-----------|--------|--------|
| CPU Signal Wait % | > 40% | Performance degradation | Optimize top CPU queries |
| Blocking Sessions | > 30 | Application hangs | Kill blocking sessions |
| Deadlocks (10 min) | > 5 | Transaction failures | Review deadlock graphs |
| Memory Spills | > 10 | Severe slowdown | Optimize queries, add RAM |

### Plan Optimization (⚠️ Warning)

| Metric | Threshold | Impact | Action |
|--------|-----------|--------|--------|
| CPU Signal Wait % | 20-40% | Slow queries | Schedule optimization |
| Blocking Sessions | 16-30 | Intermittent delays | Investigate patterns |
| Avg Duration | > 2000ms | Poor UX | Optimize queries |
| Logical Reads | > 100,000 | High I/O | Add indexes |

### Monitor Trends (⚠️ Attention)

| Metric | Threshold | Impact | Action |
|--------|-----------|--------|--------|
| CPU Signal Wait % | 10-20% | Capacity concern | Monitor trends |
| Log Size Growth | Rapid | Disk space | Check log backups |
| Query Executions | > 10,000 | App design | Consider caching |

---

## Common Scenarios

### Scenario 1: Slow Application Response

**Symptoms in report:**
- ⚠️ CPU Signal Wait: 35%
- ⚠️ Avg Duration: 3,500ms in top queries
- 🔴 Logical Reads: 500,000+ per query

**Root cause:** Missing indexes causing table scans

**Action plan:**
1. Check "Top 10 Slow Queries per Database"
2. Review "Top Missing Indexes"
3. Create top 3-5 indexes by impact score
4. Monitor improvement in next report

---

### Scenario 2: Intermittent Hangs

**Symptoms in report:**
- ⚠️ Blocking Sessions: 25
- ⚠️ Snapshots with Blocking: 45%
- ℹ️ Deadlocks: 2-3

**Root cause:** Long-running transactions holding locks

**Action plan:**
1. Find head blockers during peak times
2. Review transaction scope in application
3. Add indexes to reduce lock duration
4. Implement batching for large operations

---

### Scenario 3: High CPU Usage

**Symptoms in report:**
- 🔴 CPU Signal Wait: 55%
- 🔴 Total CPU in queries: 10+ million ms
- ⚠️ Execution Count: Very high

**Root cause:** Inefficient queries executing frequently

**Action plan:**
1. Identify top CPU consumers
2. Optimize query logic
3. Add indexes
4. Implement application-level caching
5. Review query frequency (reduce if possible)

---

### Scenario 4: Growing Log File

**Symptoms in report:**
- ⚠️ Log Size: 200 GB (larger than data)
- 🔴 Log Reuse Wait: ACTIVE_TRANSACTION
- ℹ️ Recovery Model: FULL

**Root cause:** Long-running transaction preventing log truncation

**Action plan:**
```sql
-- 1. Find long transaction
SELECT * FROM sys.dm_tran_active_transactions
WHERE DATEDIFF(HOUR, transaction_begin_time, GETDATE()) > 1

-- 2. Kill transaction if stuck
KILL <session_id>

-- 3. Take log backup
BACKUP LOG DatabaseName TO DISK = 'path\to\log.trn'

-- 4. Prevent recurrence
-- Review application transaction handling
```

---

### Scenario 5: Tempdb Spills

**Symptoms in report:**
- 🔴 Memory Grant Warnings: 25
- ⚠️ Avg Duration: High for sort/aggregate queries
- ℹ️ System reports tempdb I/O

**Root cause:** Insufficient memory grants for queries

**Action plan:**
```sql
-- 1. Update statistics
EXEC sp_updatestats

-- 2. Rebuild indexes (updates stats)
ALTER INDEX ALL ON TableName REBUILD

-- 3. Add RAM if budget allows
-- 4. Optimize queries to reduce row counts
```

---

## Additional Resources

### SQL Server DMVs for Investigation

```sql
-- Current blocking
SELECT * FROM sys.dm_exec_requests WHERE blocking_session_id > 0

-- Memory grants
SELECT * FROM sys.dm_exec_query_memory_grants

-- Active transactions
SELECT * FROM sys.dm_tran_active_transactions

-- Wait statistics
SELECT * FROM sys.dm_os_wait_stats

-- Index usage
SELECT * FROM sys.dm_db_index_usage_stats

-- Missing indexes
SELECT * FROM sys.dm_db_missing_index_details
```

### Further Reading

- **Microsoft Docs:** [sys.dm_exec_requests](https://docs.microsoft.com/sql/relational-databases/system-dynamic-management-views/sys-dm-exec-requests-transact-sql)
- **Brent Ozar:** [sp_BlitzFirst](https://www.brentozar.com/blitz/) - Real-time performance analysis
- **SQL Skills:** [Wait Statistics](https://www.sqlskills.com/help/waits/)

---

## Summary

**Key Takeaways:**

1. **CPU Signal Wait** - Main indicator of CPU pressure
2. **Blocking Sessions** - Shows lock contention
3. **Avg Duration** - User-perceived query performance
4. **Logical Reads** - I/O efficiency indicator
5. **Missing Indexes** - Optimization opportunities

**Action Priority:**

1. 🔴 **Critical** - Fix immediately (downtime risk)
2. ⚠️ **Warning** - Schedule optimization (performance impact)
3. ⚠️ **Attention** - Monitor trends (capacity planning)
4. ✅ **Normal** - No action needed

**Remember:** Context matters! A metric that's concerning in one environment may be normal in another. Use this guide as a starting point and adjust thresholds based on your specific workload.
