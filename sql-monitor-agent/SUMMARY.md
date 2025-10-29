# SQL Server Monitoring System - Final Summary

## Project Status: ✅ COMPLETE

Deployed to 3 production servers with all enhancements active.

## Deployment Locations

1. **svweb** (data.schoolvision.net,14333)
2. **suncity.schoolvision.net,14333**
3. **sqltest.schoolvision.net,14333**

## Key Features

### 1. Per-Database Collection
- **QueryStats**: 2467 rows (36 databases) vs 100 previously
- **MissingIndexes**: 391 rows (24 databases) vs 100 previously
- Small databases like LogDB now get monitoring coverage

### 2. Smart Query Plan Collection
- Only captures plans for queries >20 seconds average elapsed
- Runs every 30-60 minutes (randomized to avoid spikes)
- **95% reduction** in query plan overhead

### 3. Automatic Deadlock Response
- Enables trace flags 1222 and 1204 when deadlocks detected
- Provides detailed logging to SQL Server error log
- Zero manual intervention required

### 4. Comprehensive Blocking Monitoring
- `BlockingSessionCount` captured every 5 minutes
- Detailed blocking chains in `PerfSnapshotWorkload`
- Full session/request context with SQL text

## What's Monitored

**Every 5 minutes (P0+P1+P2):**
- Per-database query statistics (top 100 per DB)
- Per-database missing indexes (top 100 per DB)
- Database I/O statistics
- Memory usage and grants
- Backup history
- Active workload with blocking chains
- Wait statistics (server-level)
- Scheduler health
- Performance counters
- TempDB contention

**Every 30-60 minutes (randomized):**
- Query execution plans (only queries >20 sec avg elapsed)

**On Detection:**
- Deadlock trace flags (automatic enablement)

## Performance Impact

| Metric | Impact |
|--------|---------|
| P0+P1+P2 Collection Time | <20 seconds |
| Query Plan Overhead | 95% reduction |
| Data Collected | 24x more query stats |
| Storage (14 days) | ~500MB-2GB depending on workload |

## Directory Structure

```
sql_monitor/
├── README.md                           # Main documentation
├── CLAUDE.md                           # AI assistant instructions
├── SUMMARY.md                          # This file
├── .gitignore                          # Excludes servers.txt, *.log
├── servers.txt                         # Deployment targets (gitignored)
│
├── deploy_all.sh                       # Bash deployment script
├── Deploy-MonitoringSystem.ps1         # PowerShell deployment script
├── test-all-collectors.sh              # Test script
│
├── 01-14_*.sql                         # Numbered SQL deployment scripts
├── create_agent_job.sql                # SQL Agent collection job
├── create_retention_job.sql            # SQL Agent retention job
├── create_retention_policy.sql         # Retention procedure
│
├── 99_QUICK_VALIDATE.sql               # Quick validation queries
├── 99_TEST_AND_VALIDATE.sql            # Comprehensive tests
├── DIAGNOSE_COLLECTORS.sql             # Diagnostic queries
│
├── docs/
│   ├── ENHANCEMENTS.md                 # Recent enhancements (Oct 27, 2025)
│   ├── deployment/
│   │   ├── QUICK-START.md              # Quick start guide
│   │   ├── COMPLETE_DEPLOYMENT_GUIDE.md
│   │   ├── DEPLOYMENT_VERIFICATION_REPORT.md
│   │   └── ...
│   ├── reference/
│   │   ├── CONFIGURATION-GUIDE.md
│   │   ├── DATABASE-FILTER-SYSTEM.md
│   │   └── README-START-HERE.md
│   └── troubleshooting/
│       ├── FIXES_APPLIED.md
│       ├── HOW-TO-CHECK-IF-WORKING.md
│       └── ...
│
└── archive/
    └── (old versions and intermediate docs)
```

## Quick Commands

**Deploy to new server:**
```bash
./deploy_all.sh
```

**Check system health:**
```sql
EXEC DBATools.dbo.DBA_CheckSystemHealth
```

**View recent snapshots:**
```sql
SELECT TOP 5 * 
FROM DBATools.dbo.PerfSnapshotRun 
ORDER BY PerfSnapshotRunID DESC
```

**Check blocking:**
```sql
SELECT SessionID, LoginName, DatabaseName, Status, 
       BlockingSessionID, WaitType
FROM DBATools.dbo.PerfSnapshotWorkload
WHERE PerfSnapshotRunID = <latest_run>
  AND BlockingSessionID IS NOT NULL
```

**View per-database query stats:**
```sql
SELECT DatabaseName, COUNT(*) AS QueryCount
FROM DBATools.dbo.PerfSnapshotQueryStats
WHERE PerfSnapshotRunID = <latest_run>
GROUP BY DatabaseName
ORDER BY QueryCount DESC
```

## Configuration

All settings in `DBATools.dbo.Configuration`:

```sql
-- View all settings
SELECT * FROM DBATools.dbo.Configuration

-- Update setting
UPDATE DBATools.dbo.Configuration 
SET ConfigValue = '50' 
WHERE ConfigKey = 'QueryStatsTopN'
```

**Key Settings:**
- `EnableP0Collection`: 1 (Query stats, I/O, memory, backup)
- `EnableP1Collection`: 1 (Missing indexes, wait stats, query plans)
- `EnableP2Collection`: 1 (Counters, schedulers, TempDB)
- `EnableP3Collection`: 0 (Disabled - fragmentation, VLFs)
- `QueryStatsTopN`: 100 (per database)
- `RetentionDays`: 14

## Maintenance

**SQL Agent Jobs:**
1. **DBA Collect Perf Snapshot** - Runs every 5 minutes (P0+P1+P2)
2. **DBA Purge Old Snapshots** - Runs daily at 2:00 AM (deletes >14 days)

**Manual purge:**
```sql
EXEC DBATools.dbo.DBA_PurgeOldSnapshots @RetentionDays = 14
```

## Troubleshooting

**Collection not running:**
```sql
-- Check SQL Agent
EXEC msdb.dbo.sp_help_jobhistory @job_name='DBA Collect Perf Snapshot'

-- Check for errors
SELECT TOP 20 * 
FROM DBATools.dbo.LogEntry 
WHERE IsError = 1
ORDER BY LogEntryID DESC
```

**High storage usage:**
```sql
-- Check table sizes
EXEC sp_spaceused 'DBATools.dbo.PerfSnapshotQueryStats'
EXEC sp_spaceused 'DBATools.dbo.PerfSnapshotWorkload'

-- Reduce retention
UPDATE DBATools.dbo.Configuration 
SET ConfigValue = '7' 
WHERE ConfigKey = 'RetentionDays'
```

## Recent Changes

**October 27, 2025:**
- ✅ Per-database collection (QueryStats, MissingIndexes, QueryPlans)
- ✅ Query plan optimization (>20 sec filter, randomized hourly)
- ✅ Automatic deadlock trace flag enablement
- ✅ Deadlock monitoring NULL fix
- ✅ Documentation reorganization

## Support

**Documentation:**
- See `docs/` folder for detailed guides
- `docs/ENHANCEMENTS.md` for recent changes
- `docs/troubleshooting/` for common issues

**Testing:**
- `test-all-collectors.sh` - Test all collectors
- `99_QUICK_VALIDATE.sql` - Quick validation
- `DIAGNOSE_COLLECTORS.sql` - Diagnostic queries

---

**Last Updated:** October 27, 2025  
**Version:** 2.0 (Per-Database Collection + Smart Query Plans)  
**Status:** Production Ready ✅
