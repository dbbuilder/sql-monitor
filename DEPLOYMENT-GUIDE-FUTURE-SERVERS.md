# SQL Monitor Deployment Guide for Future Servers

## Overview

This guide ensures future deployments avoid the specific issues encountered on suncity and svweb during initial deployment. All fixes have been captured in updated deployment scripts.

## Critical Issues Fixed (2025-10-31)

### Issue 1: QUOTED_IDENTIFIER Error
**Problem**: `sys.dm_os_ring_buffers` requires `QUOTED_IDENTIFIER ON` for XML methods (.value())
**Impact**: SQL Agent jobs fail with Error 1934
**Fix**: Set `QUOTED_IDENTIFIER ON` both at procedure creation AND execution time

### Issue 2: Linked Server DMV Collection
**Problem**: Remote procedures called via linked server execute ON the remote server, reading wrong server's DMVs
**Impact**: All servers showed identical CPU values, disk I/O not collected for remote servers
**Fix**: Use local-collect-then-forward pattern with inline T-SQL in SQL Agent jobs

### Issue 3: INSERT...EXEC Column Mismatch
**Problem**: Cannot add ServerID column when inserting directly from EXEC results
**Impact**: Column count mismatch error (Error 213)
**Fix**: Use table variable pattern to capture EXEC results, then SELECT with ServerID

### Issue 4: Job Step Flow
**Problem**: `on_success_action = 1` (Quit with success) prevented multi-step jobs from completing
**Impact**: Only Step 1 executed, Step 2 never ran
**Fix**: Set `on_success_action = 3` (Go to next step) for all but last step

## Updated Deployment Files

### Core Files (Tested and Working)

1. **database/05-create-cpu-collection-procedures-FIXED.sql**
   - Creates `usp_GetLocalCPUMetrics` and `usp_CollectAndInsertCPUMetrics`
   - Includes QUOTED_IDENTIFIER ON at creation and execution
   - Uses table variable pattern for ServerID injection
   - Deploy to: ALL servers (sqltest, svweb, suncity, any future servers)

2. **database/09-create-sql-agent-jobs-FIXED.sql**
   - Auto-detects server and sets ServerID (1, 4, 5, etc.)
   - Creates 2-step jobs: CPU (Step 1) + Disk/Memory/Connections (Step 2)
   - Uses inline T-SQL (no procedure dependencies on remote servers)
   - Includes QUOTED_IDENTIFIER ON for CPU collection
   - Step 1 on_success_action = 3 (Go to next step)
   - Deploy to: ALL servers (each server gets its own job)

### Legacy Files (DO NOT USE - Kept for Reference)

- `database/09-create-sql-agent-jobs.sql` - ❌ OLD, has bugs
- `database/05-create-rds-equivalent-procedures.sql` - ❌ OLD, has linked server bug
- `fix-quoted-identifier-cpu-procedures.sql` - ✅ Used for hotfix, superseded by 05-FIXED
- `fix-svweb-disk-collection.sql` - ✅ Used for hotfix, superseded by 09-FIXED
- `fix-suncity-disk-collection.sql` - ✅ Used for hotfix, superseded by 09-FIXED

## Deployment Steps for New Server

### Prerequisites

1. **Central MonitoringDB** must exist on sqltest
2. **Linked server** from new server to sqltest configured (if remote)
3. **SQL Agent** service running
4. **Permissions**:
   - sysadmin on local server (for DMV access)
   - db_datawriter on [sqltest].MonitoringDB (for INSERT)

### Step 1: Add Server to Servers Table

Connect to sqltest and register the new server:

```sql
-- On sqltest.schoolvision.net,14333
USE MonitoringDB;
GO

INSERT INTO dbo.Servers (ServerName, Environment, IsActive)
VALUES
    ('newserver.schoolvision.net,14333', 'Production', 1);

-- Get the ServerID
SELECT ServerID, ServerName FROM dbo.Servers WHERE ServerName LIKE '%newserver%';
-- Result: ServerID = 6 (example)
```

### Step 2: Update Job Creation Script (if new server)

Edit `database/09-create-sql-agent-jobs-FIXED.sql` to add new server detection:

```sql
-- Around line 30, add:
ELSE IF @ServerName LIKE 'newserver%'
BEGIN
    SET @ServerID = 6;  -- Use ServerID from Step 1
    SET @JobName = N'SQL Monitor - Collect Metrics (newserver)';
    SET @ScheduleName = N'Every 5 Minutes - newserver';
    PRINT 'Detected: newserver (ServerID = 6)';
END
```

### Step 3: Deploy Procedures (if local MonitoringDB needed)

**ONLY if the new server will have a local MonitoringDB database** (like sqltest does):

```bash
# Connect to new server
sqlcmd -S newserver.schoolvision.net,14333 -U sv -P YourPassword -C

# Create MonitoringDB (if needed)
:r database/01-create-database.sql
:r database/02-create-tables.sql

# Create CPU collection procedures
:r database/05-create-cpu-collection-procedures-FIXED.sql
```

**If the new server is remote** (like svweb, suncity), skip this step - it doesn't need local procedures.

### Step 4: Deploy SQL Agent Job

```bash
# Connect to new server
sqlcmd -S newserver.schoolvision.net,14333 -U sv -P YourPassword -C

# Deploy job (auto-detects server and creates 2-step job)
:r database/09-create-sql-agent-jobs-FIXED.sql
```

**Expected output**:
```
========================================
SQL Server Monitor - SQL Agent Jobs Setup (FIXED)
========================================

Detected: newserver (ServerID = 6)

  [INFO] Deleted existing job: SQL Monitor - Collect Metrics (newserver)
  [OK] Job created: SQL Monitor - Collect Metrics (newserver)
  [OK] Step 1 added: Collect LOCAL CPU Metrics
  [OK] Step 2 added: Collect LOCAL Non-CPU Metrics
  [OK] Schedule created: Every 5 Minutes - newserver
  [OK] Schedule attached to job
  [OK] Job added to local server

========================================
SQL Agent Job Created Successfully!
========================================

Job Name: SQL Monitor - Collect Metrics (newserver)
ServerID: 6
Schedule: Every 5 minutes

Job Steps:
  1. Collect LOCAL CPU Metrics (with QUOTED_IDENTIFIER ON)
  2. Collect LOCAL Disk, Memory, Connection Metrics

Metrics collected per cycle: 20 (3 CPU + 6 Disk + 6 Memory + 5 Connections)
```

### Step 5: Test Job Manually

```sql
-- On new server
USE msdb;
GO

-- Start job manually
EXEC msdb.dbo.sp_start_job @job_name = 'SQL Monitor - Collect Metrics (newserver)';

-- Wait 10 seconds, then check job history
SELECT TOP 5
    j.name AS JobName,
    h.step_id,
    h.step_name,
    CASE h.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
    END AS StatusText,
    h.message
FROM sysjobs j
INNER JOIN sysjobhistory h ON j.job_id = h.job_id
WHERE j.name = 'SQL Monitor - Collect Metrics (newserver)'
ORDER BY h.instance_id DESC;
```

**Expected result**:
```
JobName                                          step_id  step_name                         StatusText  message
SQL Monitor - Collect Metrics (newserver)       0        (Job outcome)                     Succeeded   The job succeeded. The last step to run was step 2...
SQL Monitor - Collect Metrics (newserver)       2        Collect LOCAL Non-CPU Metrics     Succeeded   Executed as user: ... Local non-CPU metrics collected...
SQL Monitor - Collect Metrics (newserver)       1        Collect LOCAL CPU Metrics         Succeeded   Executed as user: ... CPU metrics collected...
```

### Step 6: Verify Metrics in Central Database

```sql
-- On sqltest.schoolvision.net,14333
USE MonitoringDB;
GO

-- Check metrics collected in last 10 minutes
SELECT
    s.ServerName,
    pm.ServerID,
    pm.MetricCategory,
    COUNT(*) AS MetricCount,
    MAX(pm.CollectionTime) AS LatestCollection
FROM dbo.PerformanceMetrics pm
INNER JOIN dbo.Servers s ON pm.ServerID = s.ServerID
WHERE pm.ServerID = 6  -- New server's ServerID
  AND pm.CollectionTime >= DATEADD(MINUTE, -10, GETUTCDATE())
GROUP BY s.ServerName, pm.ServerID, pm.MetricCategory
ORDER BY pm.MetricCategory;
```

**Expected result**:
```
ServerName                              ServerID  MetricCategory  MetricCount  LatestCollection
newserver.schoolvision.net,14333        6         Connections     5            2025-10-31 08:50:00
newserver.schoolvision.net,14333        6         CPU             3            2025-10-31 08:50:00
newserver.schoolvision.net,14333        6         Disk            6            2025-10-31 08:50:00
newserver.schoolvision.net,14333        6         Memory          6            2025-10-31 08:50:00
```

### Step 7: Wait for Scheduled Runs

- Jobs run every 5 minutes (at :00, :05, :10, :15, :20, :25, :30, :35, :40, :45, :50, :55)
- After 15 minutes, verify 3 collection cycles completed
- Check Grafana dashboard shows new server

## Common Issues and Solutions

### Issue: "Keyword not supported: 'ConnectTimeout'"

**Problem**: Microsoft.Data.SqlClient 5.2+ requires exact keyword syntax

**Solution**: Use `Connection Timeout` (with space), not `ConnectTimeout`

```
Server=server.domain.com,14333;Database=MonitoringDB;User Id=sv;Password=pass;
TrustServerCertificate=True;Encrypt=Optional;Connection Timeout=30
```

### Issue: "Database 'MonitoringDB' does not exist" (on remote server)

**Problem**: Job step tries to use MonitoringDB database context on remote server

**Solution**: Job script uses `master` database context, this is expected and harmless

### Issue: Job succeeds but only Step 1 runs

**Problem**: Step 1 `on_success_action` is 1 (Quit with success) instead of 3 (Go to next step)

**Solution**: Check Step 1 configuration:

```sql
SELECT step_id, step_name, on_success_action
FROM sysjobsteps
WHERE job_id = (SELECT job_id FROM sysjobs WHERE name = 'SQL Monitor - Collect Metrics (newserver)')
ORDER BY step_id;
```

Expected: Step 1 `on_success_action = 3`, Step 2 `on_success_action = 1`

If wrong:
```sql
EXEC msdb.dbo.sp_update_jobstep
    @job_name = 'SQL Monitor - Collect Metrics (newserver)',
    @step_id = 1,
    @on_success_action = 3;  -- Go to next step
```

### Issue: Metrics not showing different values per server

**Problem**: Jobs are calling remote procedures via linked server (old architecture)

**Solution**: Redeploy job using `database/09-create-sql-agent-jobs-FIXED.sql`

## Architecture Summary

### Current (CORRECT) Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Each Server (sqltest, svweb, suncity, newserver)           │
│                                                               │
│ SQL Agent Job (every 5 minutes):                            │
│   Step 1: Collect LOCAL CPU Metrics                         │
│     - SET QUOTED_IDENTIFIER ON                               │
│     - Read sys.dm_os_ring_buffers (LOCAL)                   │
│     - INSERT to central DB with ServerID                     │
│                                                               │
│   Step 2: Collect LOCAL Disk/Memory/Connections             │
│     - Read sys.dm_io_virtual_file_stats (LOCAL)             │
│     - Read sys.dm_os_memory_clerks (LOCAL)                  │
│     - Read sys.dm_exec_sessions (LOCAL)                     │
│     - INSERT to central DB with ServerID                     │
│                                                               │
│ Push via:                                                    │
│   - sqltest: INSERT to MonitoringDB.dbo.PerformanceMetrics  │
│   - Others: INSERT to [sqltest].MonitoringDB.dbo...         │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Central Database (sqltest.schoolvision.net,14333)          │
│                                                               │
│ MonitoringDB.dbo.PerformanceMetrics                         │
│   ServerID | CollectionTime | MetricCategory | MetricName   │
│   1        | 2025-10-31...  | CPU            | SQLServer... │
│   5        | 2025-10-31...  | Disk           | ReadIOPS     │
│   4        | 2025-10-31...  | Memory         | PageLife...  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Grafana Dashboard (http://20.232.76.38:3000)                │
│                                                               │
│ Queries MonitoringDB via MSSQL datasource                   │
│ Variable: $ServerID (dropdown: sqltest, svweb, suncity)     │
│ Panels: CPU, Disk I/O, Memory, Connections                  │
└─────────────────────────────────────────────────────────────┘
```

### Old (WRONG) Architecture - DO NOT USE

```
┌─────────────────────────────────────────────────────────────┐
│ Remote Server (svweb, suncity)                              │
│                                                               │
│ SQL Agent Job:                                               │
│   EXEC [sqltest].MonitoringDB.dbo.usp_CollectAllMetrics     │
│     ❌ Runs ON sqltest                                       │
│     ❌ Reads sqltest's DMVs                                  │
│     ❌ Tags with remote ServerID (wrong data!)              │
└─────────────────────────────────────────────────────────────┘
```

## Checklist for New Server Deployment

- [ ] Server added to Servers table (get ServerID)
- [ ] Linked server to sqltest configured (if remote)
- [ ] Job creation script updated with new server detection
- [ ] Job deployed and created successfully
- [ ] Manual job test succeeded (both steps)
- [ ] Metrics verified in central database (20 metrics per cycle)
- [ ] Scheduled runs working (check after 15 minutes)
- [ ] Grafana dashboard shows new server
- [ ] CPU values differ from other servers (not identical)
- [ ] Disk I/O metrics collecting (not zeros)

## Files Reference

### Must Use (FIXED)
- `database/05-create-cpu-collection-procedures-FIXED.sql`
- `database/09-create-sql-agent-jobs-FIXED.sql`

### Documentation
- `CPU-COLLECTION-FIX-SUMMARY.md` - QUOTED_IDENTIFIER fix details
- `SVWEB-DISK-COLLECTION-FIX-SUMMARY.md` - Remote collection fix details
- `DASHBOARD-ISSUES-AND-FIXES.md` - Complete issue tracking
- `DEPLOYMENT-GUIDE-FUTURE-SERVERS.md` - This document

### Hotfix Scripts (Reference Only)
- `fix-quoted-identifier-cpu-procedures.sql`
- `fix-svweb-disk-collection.sql`
- `fix-suncity-disk-collection.sql`

## Support

If issues occur during deployment:

1. Check SQL Agent job history for error messages
2. Verify QUOTED_IDENTIFIER setting:
   ```sql
   SELECT uses_quoted_identifier FROM sys.sql_modules
   WHERE object_id = OBJECT_ID('dbo.usp_GetLocalCPUMetrics');
   ```
3. Test procedures manually with SET QUOTED_IDENTIFIER ON
4. Check metrics in central database (verify ServerID and values)
5. Review this guide's "Common Issues and Solutions" section

## Change Log

- 2025-10-31: Initial version capturing all fixes from suncity/svweb deployment
- Added QUOTED_IDENTIFIER fix
- Added local-collect-then-forward pattern
- Added table variable pattern for ServerID injection
- Added job step flow fix (on_success_action)
