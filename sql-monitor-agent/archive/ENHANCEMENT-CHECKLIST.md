# SQL Server Monitoring Enhancement Checklist

**Quick Reference Guide - Sorted by Priority**

Last Updated: October 27, 2025

---

## 🔴 CRITICAL (P0) - Deploy Immediately

Must-have for production operations. Data loss risk or critical blind spots.

- [ ] **Query Performance Baseline** - `sys.dm_exec_query_stats`
  - Identify expensive queries and establish "normal" performance
  - Table: `PerfSnapshotQueryStats`
  - Impact: ~150 KB/snapshot

- [ ] **I/O Performance Baseline** - `sys.dm_io_virtual_file_stats`
  - Detect storage bottlenecks (threshold: > 15ms = problem)
  - Table: `PerfSnapshotIOStats`
  - Impact: ~10-50 KB/snapshot

- [ ] **Memory Pressure Detection** - `sys.dm_os_performance_counters`
  - Track Page Life Expectancy, Buffer Cache Hit Ratio
  - Tables: `PerfSnapshotMemory`, `PerfSnapshotMemoryClerks`
  - Impact: ~5 KB/snapshot

- [ ] **Backup Validation** - `msdb.dbo.backupset`
  - Prevent data loss from missing/failed backups
  - Table: `PerfSnapshotBackupHistory`
  - Impact: ~5 KB/snapshot

- [ ] **Proactive Alerting** - Custom infrastructure
  - Automated notifications for threshold violations
  - Tables: `PerfAlertThresholds`, `PerfAlertHistory`
  - Impact: ~10 KB/snapshot

**Total P0 Storage Impact:** ~200-450 KB per snapshot (~1.8-4 GB for 30 days)

---

## 🟠 HIGH (P1) - Deploy Within First Week

Essential for troubleshooting and root cause analysis.

- [ ] **Index Usage Statistics** - `sys.dm_db_index_usage_stats`
  - Identify unused indexes and optimization opportunities
  - Table: `PerfSnapshotIndexUsage`
  - Impact: ~200-500 KB/snapshot

- [ ] **Missing Index Recommendations** - `sys.dm_db_missing_index_*`
  - SQL Server's automatic index suggestions with impact scoring
  - Table: `PerfSnapshotMissingIndexes`
  - Impact: ~50 KB/snapshot

- [ ] **Detailed Wait Statistics** - `sys.dm_os_wait_stats` (full breakdown)
  - Enhance current system to capture all significant waits
  - Table: `PerfSnapshotWaitStats` (enhanced)
  - Impact: ~20 KB/snapshot

- [ ] **TempDB Contention Detection** - `sys.dm_os_waiting_tasks`
  - Diagnose PFS/GAM/SGAM page contention
  - Table: `PerfSnapshotTempDBContention`
  - Impact: ~5 KB/snapshot

- [ ] **Query Execution Plan Capture** - `sys.dm_exec_query_plan`
  - Capture plans for expensive queries (forensic analysis)
  - Table: `PerfSnapshotQueryPlans`
  - Impact: ~500 KB - 2 MB/snapshot

**Total P1 Storage Impact:** ~775 KB - 2.5 MB per snapshot (~8.6-26 GB for 30 days)

---

## 🟡 MEDIUM (P2) - Deploy Within First Month

Important for optimization and configuration management.

- [ ] **Server Configuration Baseline** - `sys.configurations`
  - Track MAXDOP, cost threshold, max memory drift
  - Table: `PerfSnapshotConfig`
  - Impact: ~10 KB/snapshot (on changes only)

- [ ] **VLF Count Tracking** - `sys.dm_db_log_info`
  - Detect transaction log fragmentation (threshold: > 1,000)
  - Enhancement to: `PerfSnapshotDB`
  - Impact: ~2 KB/snapshot

- [ ] **Enhanced Deadlock Analysis** - `system_health` XEvent
  - Capture full deadlock XML for root cause analysis
  - Table: `PerfSnapshotDeadlocks`
  - Impact: ~50 KB/snapshot

- [ ] **Scheduler Health Metrics** - `sys.dm_os_schedulers`
  - Detect CPU pressure and NUMA imbalances
  - Table: `PerfSnapshotSchedulers`
  - Impact: ~10 KB/snapshot

- [ ] **Performance Counters** - `sys.dm_os_performance_counters`
  - Batch Requests/sec, Compilations/sec, Transactions/sec
  - Table: `PerfSnapshotCounters`
  - Impact: ~20 KB/snapshot

- [ ] **Autogrowth Event Tracking** - Default Trace or XEvents
  - Identify undersized files causing frequent growth
  - Table: `PerfSnapshotAutogrowthEvents`
  - Impact: ~10 KB/snapshot

- [ ] **Database Property Enhancements** - `sys.databases`
  - Track auto-close, auto-shrink, page verify settings
  - Enhancement to: `PerfSnapshotDB`
  - Impact: 0 KB (existing table)

---

## 🟢 LOW (P3) - Future Enhancements

Nice-to-have for advanced scenarios.

- [ ] **Latch Statistics** - `sys.dm_os_latch_stats`
  - Advanced contention diagnosis
  - Table: `PerfSnapshotLatchStats`
  - Impact: ~15 KB/snapshot

- [ ] **SQL Agent Job History** - `msdb.dbo.sysjobhistory`
  - Monitor maintenance job success rates
  - Table: `PerfSnapshotJobHistory`
  - Impact: ~10 KB/snapshot

- [ ] **Query Store Integration** - Query Store DMVs
  - Leverage native query performance history (if enabled)
  - Requires: Query Store enabled on databases
  - Impact: Variable

- [ ] **Spinlock Statistics** - `sys.dm_os_spinlock_stats`
  - Severe internal contention diagnosis
  - Table: `PerfSnapshotSpinlockStats`
  - Impact: ~10 KB/snapshot

---

## Implementation Timeline

### Week 1: Critical Foundation
- [ ] Deploy all P0 components
- [ ] Test alerting mechanism
- [ ] Establish initial baselines
- [ ] Configure alert thresholds

### Week 2: Troubleshooting Depth
- [ ] Deploy all P1 components
- [ ] Create diagnostic queries
- [ ] Build performance dashboards
- [ ] Document common alert scenarios

### Week 3-4: Optimization & Stability
- [ ] Deploy all P2 components
- [ ] Implement data retention/purge job
- [ ] Fine-tune alert thresholds
- [ ] Create runbooks for alerts

### Ongoing: Reporting & Refinement
- [ ] Build PowerBI/Grafana dashboards
- [ ] Establish weekly baseline review
- [ ] Optimize collection performance
- [ ] Add P3 components as needed

---

## Quick Priority Reference

| Priority | Component Count | Total Storage Impact (30 days) | When to Deploy |
|----------|----------------|-------------------------------|----------------|
| P0 (Critical) | 5 components | ~1.8-4 GB | Immediately |
| P1 (High) | 5 components | +~8.6-26 GB | Week 1 |
| P2 (Medium) | 7 components | +~1-2 GB | Week 2-4 |
| P3 (Low) | 4 components | +~0.5-1 GB | As needed |

---

## Critical Thresholds Quick Reference

**Memory:**
- Page Life Expectancy < 300 seconds = CRITICAL
- Buffer Cache Hit Ratio < 90% = WARNING

**I/O:**
- Read/Write Latency > 15ms = WARNING
- Read/Write Latency > 25ms = CRITICAL

**Backups:**
- Full backup > 24 hours old = CRITICAL
- Log backup > 60 minutes old = CRITICAL (FULL recovery model)

**Blocking:**
- > 5 blocking sessions = WARNING
- > 10 blocking sessions = CRITICAL

**Log Health:**
- VLF count > 1,000 = WARNING
- VLF count > 10,000 = CRITICAL
- Log space used > 80% = WARNING

**TempDB:**
- PFS waits > 100/minute = WARNING
- PFS waits > 500/minute = CRITICAL

---

## Validation Checklist

After deployment of each phase, verify:

- [ ] SQL Agent job runs successfully
- [ ] New tables populated with data
- [ ] No performance degradation (check PerfSnapshotRun duration)
- [ ] Alert procedure executes without errors
- [ ] Test alerts received for known threshold violations
- [ ] Storage growth within expected range
- [ ] Diagnostic queries return expected results

---

## Rollback Plan

If issues occur:

1. **Disable SQL Agent job** (stop data collection)
   ```sql
   EXEC msdb.dbo.sp_update_job
       @job_name='DBA Collect Perf Snapshot',
       @enabled=0
   ```

2. **Restore previous procedure version** (keep backup of each version)
   ```sql
   -- Run backup copy of DBA_CollectPerformanceSnapshot
   ```

3. **Verify core monitoring still functional**
   ```sql
   EXEC DBATools.dbo.DBA_CollectPerformanceSnapshot @Debug = 1
   SELECT TOP 1 * FROM DBATools.dbo.PerfSnapshotRun ORDER BY PerfSnapshotRunID DESC
   ```

4. **Re-enable job after fix**
   ```sql
   EXEC msdb.dbo.sp_update_job
       @job_name='DBA Collect Perf Snapshot',
       @enabled=1
   ```

---

**End of Checklist**
