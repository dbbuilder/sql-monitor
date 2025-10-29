# First Collection Run - Expected Timing

**Question:** How long should the first automated collection take?

---

## Quick Answer

**Expected Duration:** 500ms - 3 seconds (most servers)

**Typical ranges:**
- Small server (< 10 databases): **500ms - 1 second**
- Medium server (10-50 databases): **1-3 seconds**
- Large server (50-100+ databases): **3-10 seconds**

---

## Why First Run Might Be Slower

### Cold Cache Effects

**First run after deployment:**
- Query plan cache may be cold
- DMV statistics not yet populated
- sys.databases metadata may need to be read from disk
- Temp table creation overhead

**Subsequent runs (after 5 minutes):**
- Cached execution plans
- Warm DMV data
- Faster temp table operations

**Difference:** First run can be 2-3x slower than steady-state

---

## Collection Phases - Timing Breakdown

### P0 (Critical) - 100-500ms

| Component | Time | Notes |
|-----------|------|-------|
| **Query Stats** | 50-200ms | TOP 100 from plan cache |
| **I/O Stats** | 20-100ms | All databases, all files |
| **Memory Stats** | 5-20ms | Performance counters |
| **Backup History** | 20-100ms | msdb.dbo.backupset scan |
| **P0 Total** | 95-420ms | |

**First run:** May take 200-500ms
**Steady state:** 100-300ms

---

### P1 (High) - 100-400ms

| Component | Time | Notes |
|-----------|------|-------|
| **Index Usage** | 30-100ms | All databases |
| **Missing Indexes** | 20-80ms | TOP 100 |
| **Wait Stats** | 30-100ms | TOP 100 wait types |
| **TempDB Contention** | 10-50ms | Allocation stats |
| **Query Plans** | 30-150ms | TOP 30 plans (XML) |
| **P1 Total** | 120-480ms | |

**First run:** May take 200-400ms
**Steady state:** 100-300ms

---

### P2 (Medium) - 100-2000ms

| Component | Time | Notes |
|-----------|------|-------|
| **Server Config** | 5-10ms | 8 settings only |
| **VLF Counts** | **50-500ms** | sys.dm_db_log_info() per DB |
| **Deadlock Details** | 20-100ms | system_health XEvent |
| **Scheduler Health** | 10-30ms | Runnable tasks |
| **Perf Counters** | 10-50ms | Subset of counters |
| **Autogrowth Events** | 20-100ms | system_health XEvent |
| **P2 Total** | 115-790ms | |

**VLF collection is the slowest P2 component.**

**First run:** May take 500ms-2 seconds (if many databases)
**Steady state:** 100-800ms

---

### P3 (Low) - DISABLED by Default

**If enabled:** 50-150ms

---

## Total Expected Timing

### First Run (Cold Cache)

| Server Size | P0 | P1 | P2 | Total |
|-------------|----|----|-----|-------|
| **Small (< 10 DBs)** | 300ms | 250ms | 200ms | **750ms** |
| **Medium (10-50 DBs)** | 400ms | 350ms | 800ms | **1.5s** |
| **Large (50-100 DBs)** | 500ms | 450ms | 2000ms | **3s** |
| **Very Large (100+ DBs)** | 600ms | 500ms | 5000ms | **6-10s** |

---

### Steady State (Warm Cache)

| Server Size | P0 | P1 | P2 | Total |
|-------------|----|----|-----|-------|
| **Small (< 10 DBs)** | 150ms | 150ms | 100ms | **400ms** |
| **Medium (10-50 DBs)** | 250ms | 250ms | 400ms | **900ms** |
| **Large (50-100 DBs)** | 350ms | 350ms | 1000ms | **1.7s** |
| **Very Large (100+ DBs)** | 450ms | 450ms | 3000ms | **4-5s** |

**Improvement:** 1.5-2x faster after first run

---

## Factors That Affect Timing

### Server Characteristics

1. **Number of Databases**
   - VLF collection: ~5-20ms per database
   - Backup history: ~2-5ms per database
   - I/O stats: ~2-10ms per database

   **Impact:** Linear scaling with database count

2. **Plan Cache Size**
   - Small cache (< 100 MB): Fast (50-100ms)
   - Large cache (1+ GB): Slower (200-500ms)
   - Query stats collection scans TOP 100 queries

   **Impact:** Larger cache = more time to scan

3. **Disk I/O Speed**
   - SSD/NVMe: Fast DMV reads
   - HDD: Slower metadata reads

   **Impact:** 2-3x difference between SSD and HDD

4. **CPU Cores**
   - More cores = better DMV query parallelism
   - Single core: Slower

   **Impact:** Minimal (DMV queries are lightweight)

5. **Active Workload**
   - Idle server: Fast
   - Heavy OLTP: Slightly slower (more data to collect)

   **Impact:** 10-20% slower under load

---

## What If First Run Takes > 10 Seconds?

### Possible Causes

1. **Many Databases (100+)**
   - VLF collection: 100 DBs × 50ms = 5 seconds
   - **Solution:** Acceptable, or disable P2

2. **Slow Disk I/O**
   - DMV reads waiting on disk
   - **Solution:** Check disk latency

3. **Large Plan Cache (10+ GB)**
   - Query stats scan taking long
   - **Solution:** Reduce QueryStatsTopN config

4. **Blocking/Locking**
   - Collection waiting for locks
   - **Solution:** Check sys.dm_exec_requests for blocking

5. **Network Latency** (Remote Server)
   - If SQL Server is remote, network adds latency
   - **Solution:** Run collection on server itself

---

## How to Measure First Run Time

### Method 1: Manual Test

```sql
USE DBATools
GO

DECLARE @Start DATETIME2(3) = SYSUTCDATETIME()

EXEC dbo.DBA_CollectPerformanceSnapshot @Debug = 1

DECLARE @DurationMs INT = DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME())

PRINT 'First collection run: ' + CAST(@DurationMs AS VARCHAR) + 'ms'

-- Wait 30 seconds, then run again
WAITFOR DELAY '00:00:30'

SET @Start = SYSUTCDATETIME()
EXEC dbo.DBA_CollectPerformanceSnapshot @Debug = 0
SET @DurationMs = DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME())

PRINT 'Second collection run (warm): ' + CAST(@DurationMs AS VARCHAR) + 'ms'
```

---

### Method 2: Check LogEntry Table

```sql
-- View collection timing from debug logs
SELECT TOP 10
    DateTime_Occurred,
    ProcedureName,
    ProcedureSection,
    AdditionalInfo,
    DATEDIFF(MILLISECOND,
        DateTime_Occurred,
        LEAD(DateTime_Occurred) OVER (ORDER BY LogEntryID)
    ) AS DurationMs
FROM DBATools.dbo.LogEntry
WHERE ProcedureName = 'DBA_CollectPerformanceSnapshot'
  AND IsError = 0
ORDER BY LogEntryID DESC
```

---

### Method 3: SQL Agent Job History

```sql
-- Check actual job execution time
SELECT TOP 10
    h.run_date,
    h.run_time,
    h.run_duration,  -- HHMMSS format
    -- Convert to seconds
    (h.run_duration / 10000) * 3600 +  -- Hours
    ((h.run_duration / 100) % 100) * 60 +  -- Minutes
    (h.run_duration % 100) AS run_duration_seconds,
    CASE h.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Canceled'
    END AS status
FROM msdb.dbo.sysjobhistory h
INNER JOIN msdb.dbo.sysjobs j ON h.job_id = j.job_id
WHERE j.name = 'DBA Collect Perf Snapshot'
  AND h.step_id = 0  -- Job outcome (not individual steps)
ORDER BY h.run_date DESC, h.run_time DESC
```

---

## Expected SQL Agent Job Timing

**First automated run (5 minutes after deployment):**
- **Expected:** 1-3 seconds
- **Acceptable:** Up to 10 seconds
- **Concerning:** > 10 seconds

**Subsequent runs (every 5 minutes):**
- **Expected:** 500ms - 2 seconds
- **Acceptable:** Up to 5 seconds
- **Concerning:** > 5 seconds consistently

---

## Optimization If Too Slow

### If First Run > 10 Seconds

**Option 1: Reduce TOP N Limits**
```sql
-- Collect fewer queries/plans
EXEC DBA_UpdateConfig 'QueryStatsTopN', '50'  -- Default: 100
EXEC DBA_UpdateConfig 'QueryPlansTopN', '10'  -- Default: 30
EXEC DBA_UpdateConfig 'WaitStatsTopN', '50'   -- Default: 100
EXEC DBA_UpdateConfig 'MissingIndexTopN', '50' -- Default: 100
```

**Result:** 20-30% faster collection

---

**Option 2: Disable P2 (VLF Collection)**
```sql
-- VLF collection is slowest on servers with many databases
EXEC DBA_UpdateConfig 'EnableP2Collection', '0'
```

**Result:** 50-70% faster on servers with 50+ databases

---

**Option 3: Increase Collection Interval**
```sql
-- Collect less frequently
EXEC DBA_UpdateConfig 'CollectionIntervalMinutes', '15'  -- Default: 5

-- Then update SQL Agent job schedule to match
```

**Result:** Less frequent collections = less overhead

---

## Summary

**Expected first run timing:**
- Small server: **500ms - 1 second**
- Medium server: **1-3 seconds**
- Large server: **3-10 seconds**

**If > 10 seconds:**
- Check number of databases (VLF collection overhead)
- Check plan cache size (query stats overhead)
- Check disk I/O latency
- Consider reducing TOP N limits or disabling P2

**Subsequent runs will be faster** due to warm cache effects.

**Monitor for 30 minutes** after deployment to see steady-state timing.
