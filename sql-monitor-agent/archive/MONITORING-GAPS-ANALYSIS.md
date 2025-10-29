# SQL Server Monitoring System - Gap Analysis & Enhancement Roadmap

**Date:** October 27, 2025
**Project:** SQL Server Linux 2022 Standard Edition Performance Monitoring
**Current Version:** Baseline v1.0

---

## Executive Summary

This document analyzes the current monitoring system against production requirements and provides a prioritized roadmap for enhancements. The current system captures basic health metrics but lacks critical depth needed for:
- Day-one baseline establishment
- Root cause analysis when problems occur
- Query performance forensics
- Proactive alerting

**Key Finding:** 21 critical gaps identified across 6 major categories.

---

## Current System Capabilities

### ✅ What We Have
- Wait statistics (top wait type, CPU signal wait percentage)
- Active session/request counts
- Blocking session detection
- Database file sizes and recovery models
- Error log entries (top 20)
- Deadlock counts (last 10 minutes)
- Memory grant warning counts
- 5-minute automated collection via SQL Agent

### ❌ What We're Missing
- Historical query performance data
- Execution plan capture
- I/O latency metrics
- Memory pressure detection (Page Life Expectancy)
- Backup validation
- Index usage/missing index tracking
- Proactive alerting mechanism
- Configuration drift detection

---

## Priority Classification System

- **CRITICAL (P0)** - Must have for production; data loss risk or blind spots
- **HIGH (P1)** - Essential for troubleshooting; needed within first week
- **MEDIUM (P2)** - Important for optimization; needed within first month
- **LOW (P3)** - Nice to have; advanced scenarios

---

## Enhancement Checklist

### 🔴 CRITICAL PRIORITY (P0) - Deploy Immediately

#### [ ] 1. Query Performance Baseline Capture
**DMV:** `sys.dm_exec_query_stats`
**Why Critical:** Without this, cannot answer "Is this query slower than usual?" or identify expensive queries
**Storage Impact:** ~150 KB per snapshot (top 50 queries)
**Tables Required:** `PerfSnapshotQueryStats`
**Key Metrics:**
- Execution count, total/avg CPU time
- Total/avg logical reads, physical reads
- Total/avg duration
- Last execution time
- Query hash/plan hash for pattern identification

---

#### [ ] 2. I/O Performance Baseline
**DMV:** `sys.dm_io_virtual_file_stats`
**Why Critical:** Storage I/O is #1 cause of performance issues; need baseline to identify degradation
**Storage Impact:** ~10-50 KB per snapshot
**Tables Required:** `PerfSnapshotIOStats`
**Key Metrics:**
- Average read latency per file (threshold: > 15ms = problem)
- Average write latency per file (threshold: > 15ms = problem)
- Total reads/writes, bytes transferred
- I/O stall time (cumulative wait time)

**Industry Thresholds:**
- < 5ms = Excellent
- 5-15ms = Good
- 15-25ms = Needs investigation
- \> 25ms = Critical problem

---

#### [ ] 3. Memory Pressure Detection
**DMVs:** `sys.dm_os_performance_counters`, `sys.dm_os_memory_clerks`
**Why Critical:** Memory pressure causes severe performance degradation; need early warning
**Storage Impact:** ~5 KB per snapshot
**Tables Required:** `PerfSnapshotMemory`, `PerfSnapshotMemoryClerks`
**Key Metrics:**
- **Page Life Expectancy (PLE)** - Threshold: < 300 seconds indicates pressure
- Buffer cache hit ratio - Threshold: < 90% indicates pressure
- Total/target server memory (should converge)
- Memory grants pending/outstanding
- Memory clerk breakdown (buffer pool, plan cache, etc.)

**Industry Thresholds:**
- PLE: > 300 seconds per 4GB buffer pool = healthy
- Buffer cache hit ratio: > 95% = excellent, < 90% = problem

---

#### [ ] 4. Backup Validation
**DMV:** `msdb.dbo.backupset`
**Why Critical:** No backups = catastrophic data loss risk; must validate backup recency
**Storage Impact:** ~5 KB per snapshot
**Tables Required:** `PerfSnapshotBackupHistory`
**Key Metrics:**
- Last full backup date per database
- Last differential backup date
- Last transaction log backup date (FULL recovery model only)
- Hours since last full backup
- Minutes since last log backup

**Industry Thresholds:**
- Full backup: < 24 hours old
- Differential backup: < 24 hours old (if used)
- Log backup: < 60 minutes old (FULL recovery model)
- **Missing backups = CRITICAL alert**

---

#### [ ] 5. Proactive Alerting Infrastructure
**Why Critical:** Data collection without alerting = blind monitoring; need automated notifications
**Storage Impact:** ~10 KB per snapshot
**Tables Required:** `PerfAlertThresholds`, `PerfAlertHistory`
**Key Features:**
- Configurable thresholds per metric
- Warning vs. critical severity levels
- Alert suppression (consecutive occurrences required)
- Email notification integration
- Alert history audit trail

**Initial Alert Thresholds:**
```
PageLifeExpectancy < 300 seconds = CRITICAL
BlockingSessionCount > 5 = WARNING
BlockingSessionCount > 10 = CRITICAL
DeadlockCountRecent > 0 = WARNING
AvgReadLatencyMs > 15 = WARNING
AvgReadLatencyMs > 25 = CRITICAL
AvgWriteLatencyMs > 15 = WARNING
AvgWriteLatencyMs > 25 = CRITICAL
BufferCacheHitRatio < 90 = WARNING
HoursSinceFullBackup > 24 = CRITICAL
LogSpaceUsedPercent > 80 = WARNING
LogSpaceUsedPercent > 90 = CRITICAL
```

---

### 🟠 HIGH PRIORITY (P1) - Deploy Within First Week

#### [ ] 6. Index Usage Statistics
**DMV:** `sys.dm_db_index_usage_stats`
**Why Important:** Identifies unused indexes (wasted maintenance overhead) and confirms index effectiveness
**Storage Impact:** ~200-500 KB per snapshot
**Tables Required:** `PerfSnapshotIndexUsage`
**Key Metrics:**
- User seeks, scans, lookups, updates per index
- Last seek/scan/lookup/update timestamp
- Index name, table name, database name

**Analysis Patterns:**
- High updates, zero seeks/scans = unused index (candidate for removal)
- High lookups = missing covering index opportunity
- Resets on SQL Server restart = historical tracking essential

---

#### [ ] 7. Missing Index Recommendations
**DMVs:** `sys.dm_db_missing_index_details`, `sys.dm_db_missing_index_groups`, `sys.dm_db_missing_index_group_stats`
**Why Important:** SQL Server automatically identifies index opportunities; prioritizes performance wins
**Storage Impact:** ~50 KB per snapshot (top 100 recommendations)
**Tables Required:** `PerfSnapshotMissingIndexes`
**Key Metrics:**
- Equality columns, inequality columns, included columns
- User seeks/scans (demand for index)
- Average total user cost, average user impact
- **Impact score** = User seeks × Avg total cost (prioritization metric)

**Analysis Patterns:**
- Impact score > 1,000,000 = high-priority index creation
- Recurring recommendations across snapshots = systemic issue

---

#### [ ] 8. Detailed Wait Statistics (Full Breakdown)
**DMV:** `sys.dm_os_wait_stats`
**Why Important:** Current system captures top wait only; need full breakdown for root cause analysis
**Storage Impact:** ~20 KB per snapshot (50-100 significant wait types)
**Tables Required:** `PerfSnapshotWaitStats` (enhanced)
**Key Metrics:**
- All significant wait types (not just top 1)
- Delta calculation (wait time per snapshot interval)
- Resource wait time (total - signal) = non-CPU wait
- Wait time per second (normalized metric)

**Wait Type Meanings:**
- `PAGEIOLATCH_*` = Storage I/O bottleneck
- `CXPACKET/CXCONSUMER` = Parallelism issues (tune MAXDOP, cost threshold)
- `LCK_*` = Locking/blocking contention
- `ASYNC_NETWORK_IO` = Client not consuming results fast enough
- `WRITELOG` = Transaction log I/O bottleneck
- `SOS_SCHEDULER_YIELD` = CPU pressure

---

#### [ ] 9. TempDB Contention Detection
**DMV:** `sys.dm_os_waiting_tasks` (filtered for tempdb pages)
**Why Important:** TempDB contention is extremely common in high-concurrency OLTP; specific diagnosis required
**Storage Impact:** ~5 KB per snapshot
**Tables Required:** `PerfSnapshotTempDBContention`
**Key Metrics:**
- `PAGELATCH_UP` waits on pages 2:1:1 (PFS), 2:1:2 (GAM), 2:1:3 (SGAM)
- Waiting task count per page type
- Total wait time per page type

**Resolution:**
- Add more tempdb data files (equal to # CPU cores, up to 8)
- Use trace flags 1117, 1118 (or default in SQL Server 2016+)

---

#### [ ] 10. Query Execution Plan Capture
**DMV:** `sys.dm_exec_query_plan`
**Why Important:** Plans show index usage, join strategies, missing stats, implicit conversions
**Storage Impact:** ~500 KB - 2 MB per snapshot (top 20-50 expensive plans)
**Tables Required:** `PerfSnapshotQueryPlans`
**Key Metrics:**
- Query plan XML (full execution plan)
- Query hash, plan hash
- Capture reason (high CPU, high reads, long duration)
- Associated query statistics

**Capture Criteria:**
- Top 20 by CPU time
- Top 20 by logical reads
- Top 10 by duration
- Any query > 5 seconds execution time

---

### 🟡 MEDIUM PRIORITY (P2) - Deploy Within First Month

#### [ ] 11. Server Configuration Baseline
**DMV:** `sys.configurations`
**Why Important:** Tracks configuration drift; unauthorized changes cause performance issues
**Storage Impact:** ~10 KB per snapshot (only store on changes)
**Tables Required:** `PerfSnapshotConfig`
**Key Settings to Monitor:**
- MAXDOP (recommended: # cores per NUMA node)
- Cost threshold for parallelism (recommended: 25-50, default 5 is too low)
- Max server memory (recommended: leave 4-8 GB for OS)
- Optimize for ad hoc workloads
- Backup compression default

---

#### [ ] 12. VLF Count and Transaction Log Health
**DMV:** `sys.dm_db_log_info` (SQL Server 2017+) or `DBCC LOGINFO`
**Why Important:** High VLF counts cause severe performance degradation during recovery, backups, log truncation
**Storage Impact:** ~2 KB per snapshot (added to existing `PerfSnapshotDB`)
**Tables Required:** Enhance `PerfSnapshotDB`
**Key Metrics:**
- Total VLF count (threshold: > 1,000 = problem, > 10,000 = critical)
- Active VLF count
- Log size used MB, log space used percentage

**Cause:** Frequent small autogrowth events
**Resolution:** Manually grow log file to appropriate size

---

#### [ ] 13. Enhanced Deadlock Analysis (XML Capture)
**DMV:** `system_health` Extended Event session
**Why Important:** Current system counts deadlocks but doesn't capture details for resolution
**Storage Impact:** ~50 KB per snapshot (variable based on deadlock frequency)
**Tables Required:** `PerfSnapshotDeadlocks`
**Key Metrics:**
- Full deadlock XML graph
- Victim session ID, database, object
- Deadlock graph hash (identify recurring patterns)
- Deadlock timestamp

**Analysis:** XML contains victim/winner queries, lock resources, isolation levels

---

#### [ ] 14. Scheduler Health Metrics
**DMV:** `sys.dm_os_schedulers`
**Why Important:** Detects CPU pressure and NUMA node imbalances
**Storage Impact:** ~10 KB per snapshot
**Tables Required:** `PerfSnapshotSchedulers`
**Key Metrics:**
- Runnable tasks count per scheduler (threshold: > 2 = CPU pressure)
- Work queue count
- Context switch count (high = thread contention)
- Current workers vs. active workers
- Load factor (CPU utilization)

---

#### [ ] 15. Performance Counter Metrics
**DMV:** `sys.dm_os_performance_counters`
**Why Important:** Exposes SQL Server perfmon counters for workload characterization
**Storage Impact:** ~20 KB per snapshot (50-100 key counters)
**Tables Required:** `PerfSnapshotCounters`
**Key Counters:**
- Batch Requests/sec (server workload)
- SQL Compilations/sec, Re-Compilations/sec (plan cache efficiency)
- Transactions/sec per database
- User Connections (connection pool health)
- Lock Waits/sec, Lock Wait Time
- Page Splits/sec (index fragmentation indicator)

---

#### [ ] 16. Autogrowth Event Tracking
**Source:** Default Trace or Extended Events
**Why Important:** Frequent autogrowth indicates undersized files; causes performance pauses
**Storage Impact:** ~10 KB per snapshot
**Tables Required:** `PerfSnapshotAutogrowthEvents`
**Key Metrics:**
- Database name, file name, file type
- Growth amount, duration
- Event count since last snapshot

**Threshold:** > 10 autogrowth events per day = manually size file

---

#### [ ] 17. Database Property Change Tracking
**DMV:** `sys.databases` (enhanced monitoring)
**Why Important:** Unexpected changes (e.g., SIMPLE recovery on production) cause data loss risk
**Storage Impact:** 0 (enhance existing `PerfSnapshotDB`)
**Tables Required:** Enhance `PerfSnapshotDB`
**Additional Properties:**
- Is auto-close enabled (performance anti-pattern)
- Is auto-shrink enabled (major red flag, causes fragmentation)
- Auto create/update statistics settings
- Page verify option (CHECKSUM recommended)
- Snapshot isolation state

---

### 🟢 LOW PRIORITY (P3) - Future Enhancements

#### [ ] 18. Latch Statistics
**DMV:** `sys.dm_os_latch_stats`
**Why Optional:** Advanced contention diagnosis; rare issue
**Storage Impact:** ~15 KB per snapshot
**Use Case:** Diagnose non-buffer latch contention

---

#### [ ] 19. SQL Agent Job History
**DMV:** `msdb.dbo.sysjobhistory`
**Why Optional:** Failed jobs indicate maintenance issues
**Storage Impact:** ~10 KB per snapshot
**Key Metrics:**
- Job success rate, last run outcome
- Job duration trends
- Failure count (last 24 hours)

---

#### [ ] 20. Query Store Integration
**Source:** Query Store DMVs (if enabled)
**Why Optional:** Query Store provides better query performance history
**Prerequisite:** Must enable Query Store on databases
**Recommendation:** Enable Query Store on all production databases (SQL Server 2016+)

---

#### [ ] 21. Spinlock Statistics
**DMV:** `sys.dm_os_spinlock_stats`
**Why Optional:** Extremely rare; indicates severe internal contention
**Storage Impact:** ~10 KB per snapshot
**Use Case:** Microsoft support-level troubleshooting

---

## Storage Impact Summary

### Current System (per snapshot)
- 1 PerfSnapshotRun row: ~200 bytes
- 10-50 PerfSnapshotDB rows: ~5-25 KB
- 5-100 PerfSnapshotWorkload rows: ~10-200 KB
- 20 PerfSnapshotErrorLog rows: ~10 KB
- **Total: ~25-235 KB per snapshot**

### With P0 Enhancements (per snapshot)
- Query stats (top 50): ~150 KB
- I/O stats (all files): ~10-50 KB
- Memory metrics: ~5 KB
- Backup history: ~5 KB
- Alert history: ~5 KB
- **Additional: ~175-215 KB**
- **New Total: ~200-450 KB per snapshot**

### With P0 + P1 Enhancements (per snapshot)
- Index usage: ~200-500 KB
- Missing indexes: ~50 KB
- Wait stats (full): ~20 KB
- TempDB contention: ~5 KB
- Query plans (top 20): ~500 KB - 2 MB
- **Additional: ~775 KB - 2.5 MB**
- **New Total: ~1-3 MB per snapshot**

### Annual Storage Projections

**At 5-minute intervals (288 snapshots/day):**

| Retention Period | Current System | With P0 | With P0 + P1 |
|------------------|----------------|---------|--------------|
| 30 days | ~0.7-2 GB | ~1.8-4 GB | ~8.6-26 GB |
| 60 days | ~1.4-4 GB | ~3.5-8 GB | ~17-52 GB |
| 90 days | ~2.1-6 GB | ~5.2-12 GB | ~26-77 GB |

**Recommendation:**
- **30-day retention** for detailed workload/query data
- **90-day retention** for aggregated metrics only
- **Implement data aging:** Purge detailed query plans/workload after 30 days, keep aggregated metrics for 90 days

---

## Implementation Phases

### Phase 1: Critical Foundation (Week 1)
**Goal:** Establish baseline and prevent data loss

1. Deploy P0 table schema (5 new tables)
2. Enhance `DBA_CollectPerformanceSnapshot` procedure
3. Create alerting stored procedure
4. Configure alert thresholds
5. Test manual execution with @Debug = 1
6. Deploy to production SQL Agent job

**Deliverables:**
- Query performance baseline captured
- I/O latency monitoring active
- Memory pressure alerts configured
- Backup validation alerts configured
- Proactive alerting operational

---

### Phase 2: Troubleshooting Depth (Week 2)
**Goal:** Enable root cause analysis

1. Deploy P1 table schema (5 new tables)
2. Add index usage/missing index collection
3. Enhance wait statistics collection
4. Add TempDB contention detection
5. Implement query plan capture logic
6. Create diagnostic views/queries

**Deliverables:**
- Index optimization recommendations available
- Full wait statistics breakdown captured
- TempDB contention visibility
- Slow query plan forensics enabled

---

### Phase 3: Optimization & Drift Detection (Week 3-4)
**Goal:** Long-term stability and configuration management

1. Deploy P2 table schema (enhancements)
2. Add configuration baseline tracking
3. Implement VLF count monitoring
4. Enhance deadlock analysis (XML capture)
5. Add scheduler health monitoring
6. Create autogrowth event tracking

**Deliverables:**
- Configuration drift alerts
- VLF count warnings
- Detailed deadlock root cause data
- CPU pressure detection

---

### Phase 4: Reporting & Dashboards (Ongoing)
**Goal:** Visualize and operationalize data

1. Create reporting views (last 24 hours, last 7 days, trends)
2. Build diagnostic stored procedures
3. Implement PowerBI/Grafana dashboards
4. Document runbooks for common alerts
5. Establish baseline review cadence (weekly)

**Deliverables:**
- Executive health dashboard
- DBA diagnostic toolkit
- Alert runbooks
- Baseline review process

---

## Success Metrics

### Operational Goals
- [ ] Zero backup-related data loss incidents
- [ ] < 15-minute MTTR (Mean Time To Resolution) for performance incidents
- [ ] 100% alert accuracy (no false positives after tuning period)
- [ ] Proactive problem detection (issues identified before user reports)

### Technical Goals
- [ ] Establish day-1 baseline for all critical metrics
- [ ] Capture 95th percentile query performance data
- [ ] Identify top 10 optimization opportunities per database
- [ ] Detect configuration drift within 5 minutes

---

## Risks & Mitigation

### Risk: Excessive Storage Growth
**Mitigation:** Implement 30-day retention with automated purge job; monitor database size weekly

### Risk: Collection Performance Overhead
**Mitigation:** Test on non-production first; monitor PerfSnapshotRun execution duration; increase interval from 5 minutes to 15 minutes if needed

### Risk: Alert Fatigue
**Mitigation:** Conservative initial thresholds; require consecutive occurrences (3x) before alerting; implement suppression windows

### Risk: False Positives During Maintenance
**Mitigation:** Create maintenance window schedule; suppress alerts during known maintenance periods

---

## Quick Reference: Critical Thresholds

| Metric | Warning | Critical | Meaning |
|--------|---------|----------|---------|
| Page Life Expectancy | < 500 sec | < 300 sec | Memory pressure |
| Buffer Cache Hit Ratio | < 95% | < 90% | Excessive disk reads |
| Avg Read Latency | > 15 ms | > 25 ms | Storage I/O bottleneck |
| Avg Write Latency | > 15 ms | > 25 ms | Storage I/O bottleneck |
| Blocking Sessions | > 5 | > 10 | Lock contention |
| VLF Count | > 1,000 | > 10,000 | Log fragmentation |
| Hours Since Full Backup | > 24 | > 48 | Data loss risk |
| Log Space Used % | > 80% | > 90% | Log growth imminent |
| Runnable Tasks/Scheduler | > 2 | > 5 | CPU pressure |
| TempDB PFS Waits | > 100/min | > 500/min | TempDB contention |

---

## Document Maintenance

**Last Updated:** October 27, 2025
**Next Review:** After Phase 1 deployment
**Owner:** DBA Team

**Changelog:**
- 2025-10-27: Initial gap analysis and roadmap creation
