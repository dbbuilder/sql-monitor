# Timeout Investigation Cheat Sheet

**Quick Reference Guide for Investigating SQL Server Timeout Issues**

---

## 🚨 When a Timeout Occurs - First 5 Minutes

### Step 1: Run the Rescue Kit (2 minutes)

```sql
-- Set timeframe to when timeout occurred
-- Edit the script to adjust @StartTime and @EndTime
:r TIMEOUT_RESCUE_KIT.sql
```

**What to look for:**
- Section 1: Attention events → Confirms clients actually timed out
- Section 2-6: Long-running queries → Identifies the slow query
- Section 3: Blocking chains → Shows what was blocking the query

### Step 2: Quick Triage (3 minutes)

**Answer these questions:**

1. **What timed out?**
   - Check Section 2 (Long-Running Queries) or Section 6 (DMV Cache)
   - Note the procedure name, database, and duration

2. **Was it blocked?**
   - Check Section 3 (Blocking Chains)
   - If yes → Focus on the blocking session (what was it doing?)

3. **Was there resource pressure?**
   - Check Section 9 (Server Resource Pressure)
   - CPU > 50% → CPU bottleneck
   - Blocking > 5 sessions → Blocking issue
   - Check Section 10 (Memory Pressure) if PLE < 1000

---

## 📊 Root Cause Decision Tree

```
Timeout occurred
    ├─ Check Section 3: Blocking?
    │   ├─ YES → Root cause: BLOCKING
    │   │   └─ Action: Optimize blocker query, reduce transaction time
    │   │
    │   └─ NO → Check Section 4: Top wait type?
    │       ├─ LCK_M_* waits → LOCKING (check for deadlocks in Section 8)
    │       ├─ PAGEIOLATCH → DISK I/O (check storage performance)
    │       ├─ WRITELOG → TRANSACTION LOG I/O (check log disk)
    │       ├─ CXPACKET → PARALLELISM (check query plan, consider MAXDOP)
    │       ├─ RESOURCE_SEMAPHORE → MEMORY PRESSURE (check Section 10)
    │       ├─ SOS_SCHEDULER_YIELD → CPU PRESSURE (check Section 9)
    │       └─ ASYNC_NETWORK_IO → CLIENT SLOW (network or client issue)
```

---

## 🔍 Common Timeout Patterns

### Pattern 1: Blocking-Induced Timeout

**Symptoms:**
- Section 3 shows blocking chain
- Section 4 shows LCK_M_* waits
- Long wait times (multiple seconds)

**Root Cause:** Query was waiting for locks held by another session

**Solution:**
1. Identify the blocker query (Section 3: BlockingSession column)
2. Optimize the blocker to complete faster
3. Reduce transaction duration (commit more frequently)
4. Consider READ_COMMITTED_SNAPSHOT isolation level

**Example:**
```sql
-- From Section 3 output
BlockedSession: 87
BlockingSession: 52
WaitType: LCK_M_X
WaitSeconds: 35.2
BlockedStatement: UPDATE Orders SET Status = 'Shipped' WHERE OrderID = 12345
BlockerStatement: BEGIN TRAN; SELECT * FROM Orders WITH (UPDLOCK); -- Long transaction
```

**Action:** Optimize session 52's query to avoid long-running transactions with locks

---

### Pattern 2: Disk I/O Timeout

**Symptoms:**
- Section 4 shows PAGEIOLATCH_SH or PAGEIOLATCH_EX waits
- Section 2/6 shows high logical reads
- Storage latency > 20ms (check separately)

**Root Cause:** Query reading massive amounts of data from slow disk

**Solution:**
1. Add missing indexes (check Section 4 in daily reports)
2. Optimize query to reduce logical reads
3. Improve storage performance (faster disks, more IOPS)
4. Consider columnstore index for large table scans

**Example:**
```sql
-- From Section 6 output
QueryText: SELECT * FROM LargeTable WHERE NonIndexedColumn = 'Value'
AvgLogicalReads: 2,450,000  -- 2.4M reads!
MaxElapsedMs: 45,200  -- 45 seconds
```

**Action:** Create index on NonIndexedColumn or rewrite query

---

### Pattern 3: Plan Regression Timeout

**Symptoms:**
- Section 5 shows plan change
- Query was fast historically, suddenly slow
- Different execution plan being used

**Root Cause:** Query optimizer chose a bad plan (outdated statistics, parameter sniffing)

**Solution:**
1. Update statistics on affected tables
2. Force the good plan using Query Store
3. Consider query hints (OPTIMIZE FOR, RECOMPILE)
4. Rebuild indexes if fragmented

**Example:**
```sql
-- From Section 5 output
ObjectName: GetCustomerOrders
AvgDurationMs: 42,000  -- Was 200ms historically
PlanStatus: Not Forced
```

**Action:**
```sql
-- Force the good plan
EXEC sp_query_store_force_plan @query_id = 12345, @plan_id = 67890
```

---

### Pattern 4: CPU Pressure Timeout

**Symptoms:**
- Section 9 shows CpuSignalWaitPct > 50%
- Section 4 shows SOS_SCHEDULER_YIELD waits
- Many concurrent requests

**Root Cause:** CPU overloaded, queries competing for CPU time

**Solution:**
1. Identify CPU-intensive queries (Section 6: AvgCpuMs)
2. Optimize queries to reduce CPU (fewer table scans, better indexes)
3. Reduce query parallelism (MAXDOP)
4. Scale up (more/faster CPUs) or scale out (read replicas)

**Example:**
```sql
-- From Section 9 output
CPUPressurePct: 72  -- High CPU pressure!
SessionsCount: 45
RequestsCount: 38
TopWaitType: SOS_SCHEDULER_YIELD
```

**Action:** Find and optimize the top CPU-consuming queries

---

### Pattern 5: Memory Pressure Timeout

**Symptoms:**
- Section 10 shows PLE < 300 (severe) or < 1000 (moderate)
- Section 4 shows RESOURCE_SEMAPHORE waits
- MemoryGrantsPending > 0

**Root Cause:** Queries waiting for memory grants, pages being flushed from cache prematurely

**Solution:**
1. Add more RAM to SQL Server
2. Optimize memory-heavy queries (reduce sorts, reduce row counts)
3. Review max server memory setting
4. Identify memory-hogging queries

**Example:**
```sql
-- From Section 10 output
PageLifeExpectancy: 180  -- SEVERE! (should be > 1000)
MemoryGrantsPending: 12  -- Queries waiting for memory
TotalServerMemoryMB: 8192
TargetServerMemoryMB: 8192  -- At maximum configured memory
```

**Action:** Increase SQL Server max memory or add more RAM

---

## 🛠️ Quick Actions by Root Cause

| Root Cause | Immediate Action | Long-Term Fix |
|------------|------------------|---------------|
| **Blocking** | KILL blocker (if safe) | Optimize blocker query, reduce transaction time |
| **Disk I/O** | N/A (can't fix instantly) | Add indexes, faster storage, optimize queries |
| **Plan Regression** | Force good plan (Query Store) | Update stats, rebuild indexes, query hints |
| **CPU Pressure** | Reduce parallelism (MAXDOP) | Optimize queries, add CPUs, offload reads |
| **Memory Pressure** | Clear plan cache (risky!) | Add RAM, optimize queries, tune memory grants |
| **Deadlocks** | N/A (already resolved) | Fix deadlock pattern (lock order, indexes) |

---

## 📝 Sample Investigation Workflow

### Example: "Our order processing timed out at 2:15 PM"

**Step 1: Set timeframe and run rescue kit**
```sql
-- Edit TIMEOUT_RESCUE_KIT.sql
DECLARE @StartTime DATETIME = '2025-10-29 14:00:00'  -- 2:00 PM
DECLARE @EndTime DATETIME = '2025-10-29 14:30:00'    -- 2:30 PM

-- Run the kit
:r TIMEOUT_RESCUE_KIT.sql
```

**Step 2: Identify the timed-out query**
```
Section 2 Output:
  CaptureTime: 2025-10-29 14:15:23
  SessionID: 127
  LoginName: app_user
  DatabaseName: OrdersDB
  Command: UPDATE
  ElapsedSeconds: 42.3  -- TIMED OUT (>30s)
  StatementPreview: UPDATE Orders SET Status = 'Processed' WHERE OrderID = 456789
```

**Step 3: Check for blocking**
```
Section 3 Output:
  BlockedSession: 127
  BlockingSession: 98
  WaitType: LCK_M_X
  WaitSeconds: 38.5
  WhatWasBlocked: UPDATE Orders SET Status = 'Processed'...
  WhatWasBlocking: SELECT * FROM Orders WITH (UPDLOCK) WHERE CustomerID = 12345
```

**Step 4: Root cause identified → BLOCKING**
- Session 98 held an exclusive lock on Orders table
- Session 127 waited 38.5 seconds for the lock
- Application timeout is 30 seconds → Query timed out

**Step 5: Solution**
```sql
-- Immediate: Kill the blocker if it's stuck
-- KILL 98

-- Long-term: Fix the blocking query
-- The blocker is using UPDLOCK on a SELECT (holding locks unnecessarily)
-- Change to:
SELECT * FROM Orders WITH (NOLOCK) WHERE CustomerID = 12345
-- Or use READ_COMMITTED_SNAPSHOT isolation level
```

---

## 🎯 Proactive Timeout Prevention

### 1. Set Up Extended Event Tracking
```sql
-- Run once to create persistent timeout tracking
:r CREATE_TIMEOUT_TRACKING_XE.sql
```

**Benefits:**
- Captures timeout evidence automatically
- Full SQL text and execution context
- Minimal overhead (<1%)

### 2. Regular Performance Reviews
```sql
-- Weekly: Review timeout risk procedures
:r DIAGNOSE_PROCEDURE_TIMEOUTS.sql
```

### 3. Monitor Key Metrics Daily
```sql
-- Daily health check
EXEC DBA_CheckSystemHealth

-- Focus on:
-- - CpuSignalWaitPct (should be < 25%)
-- - BlockingSessionCount (should be 0-2)
-- - PageLifeExpectancy (should be > 1000)
```

### 4. Set Up Alerts
```sql
-- Alert on high blocking
IF (SELECT BlockingSessionCount FROM PerfSnapshotRun ORDER BY SnapshotUTC DESC OFFSET 0 ROWS FETCH NEXT 1 ROW ONLY) > 5
BEGIN
    -- Send alert
END
```

---

## 📚 Reference: Wait Type Quick Guide

| Wait Type | Meaning | Action |
|-----------|---------|--------|
| LCK_M_X | Exclusive lock wait | Check blocking (Section 3) |
| LCK_M_S | Shared lock wait | Check blocking (Section 3) |
| PAGEIOLATCH_SH | Reading data from disk | Add indexes, faster storage |
| PAGEIOLATCH_EX | Writing data to disk | Faster storage, reduce writes |
| WRITELOG | Transaction log write | Faster log disk, reduce transaction size |
| ASYNC_NETWORK_IO | Client slow to receive | Network issue or client processing slow |
| CXPACKET | Parallelism wait | Check MAXDOP, optimize query |
| RESOURCE_SEMAPHORE | Memory grant wait | Add RAM, optimize queries |
| SOS_SCHEDULER_YIELD | CPU pressure | Optimize queries, add CPUs |
| OLEDB | Linked server/external call | Check remote server performance |

---

## 🚀 Quick Commands

```sql
-- Run timeout rescue kit for last 4 hours
:r TIMEOUT_RESCUE_KIT.sql

-- Diagnose procedure timeout risk
:r DIAGNOSE_PROCEDURE_TIMEOUTS.sql

-- Create Extended Event session (one-time setup)
:r CREATE_TIMEOUT_TRACKING_XE.sql

-- Query Extended Event data
EXEC DBA_QueryTimeoutEvents @StartTime = '2025-10-29 14:00', @EndTime = '2025-10-29 15:00'

-- Adjust collection schedules (if overhead is high)
:r ADJUST_COLLECTION_SCHEDULE.sql

-- Daily health check
EXEC DBA_CheckSystemHealth

-- Check currently running queries
SELECT
    r.session_id,
    r.status,
    r.command,
    r.wait_type,
    r.wait_time / 1000.0 AS WaitSeconds,
    r.blocking_session_id,
    SUBSTRING(st.text, (r.statement_start_offset/2)+1,
        ((CASE r.statement_end_offset
            WHEN -1 THEN DATALENGTH(st.text)
            ELSE r.statement_end_offset
        END - r.statement_start_offset)/2) + 1) AS CurrentStatement
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) st
WHERE r.session_id > 50
ORDER BY r.total_elapsed_time DESC

-- Check current blocking
SELECT
    blocked.session_id AS BlockedSession,
    blocked.wait_type,
    blocked.wait_time / 1000.0 AS WaitSeconds,
    blocking.session_id AS BlockingSession,
    blocking_sql.text AS BlockingQuery,
    blocked_sql.text AS BlockedQuery
FROM sys.dm_exec_requests blocked
INNER JOIN sys.dm_exec_requests blocking ON blocked.blocking_session_id = blocking.session_id
CROSS APPLY sys.dm_exec_sql_text(blocking.sql_handle) blocking_sql
CROSS APPLY sys.dm_exec_sql_text(blocked.sql_handle) blocked_sql
WHERE blocked.blocking_session_id > 0
```

---

## 📞 Escalation Path

**If timeout cannot be resolved:**

1. **Immediate:** Contact DBA team with rescue kit output
2. **Provide:**
   - Timeframe of timeout
   - Rescue kit sections 1-10 output
   - Application error messages
   - Frequency of timeouts (one-time or recurring?)
3. **Include:**
   - Recent changes (deployments, schema changes, data growth)
   - Affected users/workloads
   - Business impact

---

## 📖 Additional Resources

- **Timeout Rescue Kit:** TIMEOUT_RESCUE_KIT.sql
- **Extended Event Setup:** CREATE_TIMEOUT_TRACKING_XE.sql
- **Procedure Diagnostics:** DIAGNOSE_PROCEDURE_TIMEOUTS.sql
- **Schedule Adjustment:** ADJUST_COLLECTION_SCHEDULE.sql
- **Bug Fix Documentation:** TIMEOUT-DETECTION-FIX-2025-10-29.md

---

**Last Updated:** 2025-10-29
**Author:** SQL Monitor Team
