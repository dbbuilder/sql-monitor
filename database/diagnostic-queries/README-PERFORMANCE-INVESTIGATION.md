# Performance Spike Investigation Guide

## Quick Start

### 1. Update the Query Parameters

Edit the query file and set the actual incident date/time:

```sql
DECLARE @IncidentStartTime DATETIME2 = '2025-10-28 15:43:00'; -- YOUR ACTUAL DATE
DECLARE @IncidentEndTime DATETIME2 = '2025-10-28 15:45:00';   -- YOUR ACTUAL DATE
DECLARE @InstanceName NVARCHAR(128) = '001';                   -- YOUR INSTANCE NAME
```

### 2. Run the Query

```bash
# From WSL (adjust connection details)
sqlcmd -S 172.31.208.1,14333 -U sv -P Gv51076! -C -d DBATools \
  -i database/diagnostic-queries/investigate-performance-spike.sql \
  -o /tmp/performance-investigation-results.txt

# View results
cat /tmp/performance-investigation-results.txt
```

Or run directly in SSMS/Azure Data Studio connected to the DBATools database.

## What the Query Investigates

### 1. Disk I/O Throughput
- **Looks for**: Sudden spikes in MB/sec or high latency
- **Common cause**: Storage subsystem saturation, SAN latency
- **Good values**: Read/Write < 100ms latency
- **Red flag**: >500ms latency or >200 MB/sec sustained

### 2. CPU and Memory Pressure
- **Looks for**: CPU >80%, Memory >90%
- **Common cause**: Query parallelism, plan cache bloat
- **Good values**: CPU <70%, Memory <85%

### 3. Wait Statistics
This is the **most important** section. Wait types tell you what SQL Server was waiting for:

| Wait Type | Meaning | Likely Cause |
|-----------|---------|--------------|
| `PAGEIOLATCH_SH` | Reading data from disk | Disk I/O bottleneck, missing indexes |
| `PAGEIOLATCH_EX` | Writing data to disk | Checkpoint activity, disk slow |
| `WRITELOG` | Writing to transaction log | Log file on slow disk, log flush |
| `LCK_M_X` | Exclusive lock wait | Blocking, long transactions |
| `LCK_M_S` | Shared lock wait | Blocking from updates |
| `SOS_SCHEDULER_YIELD` | CPU yielding | CPU pressure, runnable queue |
| `ASYNC_NETWORK_IO` | Waiting for client | Client not reading results fast enough |
| `CXPACKET` | Parallel query wait | Poorly balanced parallel plan |

### 4. Active Workload
- Shows long-running queries during the incident
- Queries >5 seconds are flagged
- Look for queries running during the 15:43 spike

### 5. Blocking Chains
- **Critical**: Shows if queries were blocked by other sessions
- If present, identifies the blocker and victim sessions
- Common cause of sudden 1-minute delays

### 6. Database Auto-Growth Events
- **Very common culprit** for sudden delays
- If database file grows during query execution, entire instance pauses
- Growth >100MB flagged
- **Solution**: Pre-size files, enable instant file initialization

### 7. Stored Procedure Stats
- Looks for `GetQuoteDealSummaryReport` and `GetQuoteBaseVolumeCsv` specifically
- Compares average duration during incident vs normal
- Shows CPU and I/O consumption

## Common Patterns and Solutions

### Pattern 1: Disk I/O Spike + PAGEIOLATCH Waits
**Diagnosis**: Storage bottleneck
**Solutions**:
- Check SAN/storage team for underlying issue
- Add missing indexes (check execution plans)
- Reduce table scans with better queries
- Consider columnstore for large scans

### Pattern 2: WRITELOG Waits
**Diagnosis**: Transaction log writes slow
**Solutions**:
- Move log file to faster storage (SSD)
- Reduce transaction size (batch updates)
- Check log file auto-growth settings
- Ensure instant file initialization enabled

### Pattern 3: Blocking (LCK_M_* waits)
**Diagnosis**: Lock contention
**Solutions**:
- Identify blocking query (session ID)
- Optimize long-running transactions
- Consider READ COMMITTED SNAPSHOT isolation
- Add indexes to reduce lock duration

### Pattern 4: Auto-Growth Event
**Diagnosis**: Database file grew during query execution
**Solutions**:
- Pre-size database files to expected size
- Enable instant file initialization (Windows privilege)
- Set reasonable auto-growth increments (avoid %)
- Monitor file sizes proactively

### Pattern 5: CPU Pressure (SOS_SCHEDULER_YIELD)
**Diagnosis**: Not enough CPU capacity
**Solutions**:
- Optimize queries (reduce scans, add indexes)
- Reduce parallelism (MAXDOP setting)
- Scale up SQL Server instance
- Offload reporting workload

## If No Data is Returned

Check data availability at the bottom of the report:

```sql
-- Run this separately to verify monitoring is working
SELECT
    ServerName,
    CollectionTime,
    CPUPercent,
    MemoryUsagePercent
FROM DBATools.dbo.ServerHealth
WHERE ServerName LIKE '%001%'
ORDER BY CollectionTime DESC;
```

If no rows:
1. Check that sql-monitor-agent is collecting data
2. Verify SQL Agent jobs are enabled and running
3. Check ServerName value (might not be '001')

## Real-World Example

```
Time: 15:43:00 UTC
Wait Type: PAGEIOLATCH_SH
Wait Seconds: 58.2
Disk Read MB/sec: 245
Read Latency: 850ms

Diagnosis: Disk read bottleneck causing 58-second page latch wait
Root Cause: Query scanning 50GB table without index
Solution: Added index on WHERE clause columns, scan reduced to 200MB
```

## Next Steps After Running Query

1. **Share results with team**: Export the text output
2. **Check execution plans**: For identified slow queries
3. **Review waits**: Focus on top 3 wait types
4. **Look for patterns**: Does this happen daily at same time?
5. **Correlate with app logs**: Match SQL delays to API timeouts

## Advanced: Real-Time Monitoring

If issue is recurring, capture real-time DMV data:

```sql
-- Run this in a separate window during incident
SELECT
    r.session_id,
    r.status,
    r.wait_type,
    r.wait_time,
    r.blocking_session_id,
    r.cpu_time,
    r.total_elapsed_time / 1000 AS elapsed_seconds,
    DB_NAME(r.database_id) AS database_name,
    t.text AS query_text
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id > 50
    AND r.total_elapsed_time > 5000 -- Running >5 seconds
ORDER BY r.total_elapsed_time DESC;
```

## Questions to Ask

When reviewing results with the development team:

1. **Were these API calls hitting the same data?** (Cache miss vs cache hit)
2. **Did anything deploy around 15:43 UTC?** (Code, database, infrastructure)
3. **Is this a regular occurrence?** (Daily at same time = batch job contention)
4. **What changed 2 minutes later?** (Query finished? Lock released? Cache warmed?)
5. **What does the application do during 1-minute wait?** (Timeout and retry? Wait silently?)

## Contact

If you need help interpreting results:
- Share the full query output
- Include any relevant application error logs
- Note if issue is recurring or one-time

---

**Created**: 2025-10-28
**Purpose**: Investigate 15:43 UTC performance spike for GetQuoteDealSummaryReport() and GetQuoteBaseVolumeCsv() API calls
**Instance**: 001
**Symptom**: API calls took >1 minute at 15:43, then <5 seconds at 15:45
