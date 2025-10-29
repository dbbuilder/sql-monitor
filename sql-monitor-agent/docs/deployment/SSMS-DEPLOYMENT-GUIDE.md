# SSMS Deployment Guide - SQL Server Monitoring System

**Target:** Remote Linux SQL Server 2019/2022 Standard Edition
**Method:** SQL Server Management Studio (SSMS)
**Time Required:** 5-10 minutes

---

## Prerequisites

- [x] SSMS installed on your Windows machine
- [x] Network access to remote Linux SQL Server
- [x] SQL login credentials (or Windows auth if available)
- [x] Permissions: CREATE DATABASE, CREATE PROCEDURE, SQL Agent access

---

## Files You Need (In Order)

Only run these files - all old versions are in `archive/old_versions/`:

### Step 1: Foundation (Required)
1. **01_create_DBATools_and_tables.sql** - Creates database and 24 tables
2. **02_create_DBA_LogEntry_Insert.sql** - Creates logging procedure

### Step 2: Configuration System (Required)
3. **13_create_config_table_and_functions.sql** - Config table, functions

### Step 3: Enhanced Monitoring Tables (Required)
4. **05_create_enhanced_tables.sql** - 20+ monitoring tables for P0/P1/P2/P3

### Step 4: Collection Procedures (Required)
5. **06_create_modular_collectors_P0_FIXED.sql** - P0 (Critical) procedures
6. **07_create_modular_collectors_P1_FIXED.sql** - P1 (High) procedures
7. **08_create_modular_collectors_P2_P3_FIXED.sql** - P2 + P3 procedures

### Step 5: Reporting Views (Required)
8. **09_create_reporting_views.sql** - Timezone-enabled reporting views

### Step 6: Orchestration (Required)
9. **10_create_master_orchestrator_FIXED.sql** - Main collection coordinator
10. **11_create_purge_procedure_FIXED.sql** - Data retention management

### Step 7: Automation (Required for scheduled collection)
11. **04_create_agent_job_FIXED.sql** - SQL Agent job (every 5 minutes)

### Step 8: Reporting Procedures (Optional but recommended)
12. **14_create_reporting_procedures.sql** - 10 reporting procedures

### Step 9: Testing (Optional but recommended)
13. **99_TEST_AND_VALIDATE.sql** - Comprehensive validation

---

## Detailed Deployment Steps

### 1. Connect to Remote Server in SSMS

1. Open SQL Server Management Studio
2. Click **Connect** > **Database Engine**
3. Enter your remote server details:
   - **Server name:** `your-server.domain.com` or `IP_ADDRESS,PORT`
   - **Authentication:** SQL Server Authentication (recommended for Linux)
   - **Login:** `sa` or your admin username
   - **Password:** Your password
4. Click **Connect**

---

### 2. Run Foundation Scripts

**File: 01_create_DBATools_and_tables.sql**

1. Open the file in SSMS: **File** > **Open** > **File**
2. Browse to `/mnt/e/Downloads/sql_monitor/01_create_DBATools_and_tables.sql`
3. Click **Execute** (F5) or press the Execute button
4. **Expected output:** "Database created successfully" + 24 table creation messages
5. **Verify:** Check Object Explorer, expand **Databases**, confirm **DBATools** exists

**File: 02_create_DBA_LogEntry_Insert.sql**

1. Open the file
2. Execute (F5)
3. **Expected output:** "Commands completed successfully"
4. **Verify:** Expand DBATools > Programmability > Stored Procedures, confirm `dbo.DBA_LogEntry_Insert` exists

---

### 3. Deploy Configuration System

**File: 13_create_config_table_and_functions.sql**

1. Open the file
2. Execute (F5)
3. **Expected output:**
   - "Configuration table and timezone support created successfully"
   - Table showing 28 config settings
4. **Verify:**
   - Expand DBATools > Tables, confirm `dbo.MonitoringConfig` exists
   - Expand Programmability > Functions > Scalar-valued Functions
   - Confirm: `fn_GetConfigValue`, `fn_GetConfigInt`, `fn_GetConfigBit`, `fn_ConvertToReportingTime`, `fn_ConvertToUTC`

---

### 3a. Deploy Enhanced Monitoring Tables

**File: 05_create_enhanced_tables.sql**

1. Open the file
2. Execute (F5)
3. **Expected output:** "Enhanced monitoring tables created successfully" + list of ~20 tables
4. **Verify:** Expand DBATools > Tables, confirm new tables exist:
   - `PerfSnapshotQueryStats`
   - `PerfSnapshotIOStats`
   - `PerfSnapshotMemory`
   - `PerfSnapshotBackupHistory`
   - And 16+ others

---

### 4. Deploy Collection Procedures

**File: 06_create_modular_collectors_P0_FIXED.sql**

1. Open the file
2. Execute (F5)
3. **Expected output:** "P0 (Critical) modular collection procedures created successfully"
4. **Verify:** 4 new procedures with names starting `DBA_Collect_P0_`

**File: 07_create_modular_collectors_P1_FIXED.sql**

1. Open the file
2. Execute (F5)
3. **Expected output:** "P1 (High) modular collection procedures created successfully"
4. **Verify:** 5 new procedures with names starting `DBA_Collect_P1_`

**File: 08_create_modular_collectors_P2_P3_FIXED.sql**

1. Open the file
2. Execute (F5)
3. **Expected output:** "P2 (Medium) and P3 (Low) modular collection procedures created successfully"
4. **Verify:** 9 new procedures with names starting `DBA_Collect_P2_` or `DBA_Collect_P3_`

---

### 4a. Deploy Reporting Views

**File: 09_create_reporting_views.sql**

1. Open the file
2. Execute (F5)
3. **Expected output:** "Reporting views with timezone conversion created successfully"
4. **Verify:** 3 new views:
   - `vw_LatestSnapshotSummary_ET`
   - `vw_BackupRiskAssessment_ET`
   - `vw_IOLatencyHotspots_ET`

---

### 5. Deploy Orchestration

**File: 10_create_master_orchestrator_FIXED.sql**

1. Open the file
2. Execute (F5)
3. **Expected output:** "Master orchestrator procedure created successfully - FIXED"
4. **Verify:** Procedure `dbo.DBA_CollectPerformanceSnapshot` exists

**File: 11_create_purge_procedure_FIXED.sql**

1. Open the file
2. Execute (F5)
3. **Expected output:** "Purge procedure created successfully - FIXED"
4. **Verify:** Procedure `dbo.DBA_PurgeOldSnapshots` exists

---

### 6. Create SQL Agent Job

**IMPORTANT:** Ensure SQL Server Agent is running on your Linux server:

```bash
# On the Linux server, run:
sudo systemctl status mssql-server-agent
sudo systemctl enable mssql-server-agent
sudo systemctl start mssql-server-agent
```

**File: 04_create_agent_job_FIXED.sql**

1. Open the file
2. Execute (F5)
3. **Expected output:**
   - "SQL Agent job created successfully"
   - "Job Name: DBA Collect Perf Snapshot"
   - "Schedule: Every 5 minutes"
   - "Status: Enabled"
4. **Verify in SSMS:**
   - Expand **SQL Server Agent** (may need to right-click > Refresh)
   - Expand **Jobs**
   - Confirm `DBA Collect Perf Snapshot` exists and shows green arrow (enabled)

---

### 7. Test the System

**Option A: Run Full Validation Script**

**File: 99_TEST_AND_VALIDATE.sql**

1. Open the file
2. Execute (F5)
3. Review output for any errors

**Option B: Manual Test (Quick)**

Run this query in a new query window:

```sql
-- Test collection
EXEC DBATools.dbo.DBA_CollectPerformanceSnapshot @Debug = 1

-- Check if snapshot was created
SELECT TOP 1 *
FROM DBATools.dbo.PerfSnapshotRun
ORDER BY PerfSnapshotRunID DESC

-- Check for errors
SELECT TOP 10 *
FROM DBATools.dbo.LogEntry
WHERE IsError = 1
ORDER BY LogEntryID DESC

-- View config
EXEC DBATools.dbo.DBA_ViewConfig
```

**Expected Results:**
- Snapshot collection completes without errors
- PerfSnapshotRun has at least 1 row
- No recent errors in LogEntry (or only harmless warnings)
- Config shows 28 settings

---

## Verification Checklist

After deployment, verify:

- [ ] **DBATools database exists** (Object Explorer > Databases)
- [ ] **24 tables created** (DBATools > Tables - count them)
- [ ] **24 procedures created** (DBATools > Programmability > Stored Procedures)
- [ ] **5 functions created** (DBATools > Programmability > Functions)
- [ ] **Config table has 28 rows** (`SELECT COUNT(*) FROM DBATools.dbo.MonitoringConfig`)
- [ ] **SQL Agent job exists and is enabled** (SQL Server Agent > Jobs)
- [ ] **Test collection runs successfully** (`EXEC DBATools.dbo.DBA_CollectPerformanceSnapshot @Debug = 1`)
- [ ] **Data is being collected** (`SELECT COUNT(*) FROM DBATools.dbo.PerfSnapshotRun`)

---

## What Happens After Deployment?

### Automatic Collection
- SQL Agent job runs **every 5 minutes**
- Collects P0, P1, and P2 data (P3 disabled by default)
- Data stored in DBATools database
- **Retention:** 30 days (configurable)

### Monitor Collection
```sql
-- View recent snapshots
SELECT TOP 20
    PerfSnapshotRunID,
    SnapshotUTC,
    ServerName
FROM DBATools.dbo.PerfSnapshotRun
ORDER BY PerfSnapshotRunID DESC

-- Check job history
SELECT TOP 20
    run_date,
    run_time,
    run_duration,
    message
FROM msdb.dbo.sysjobhistory jh
INNER JOIN msdb.dbo.sysjobs j ON jh.job_id = j.job_id
WHERE j.name = 'DBA Collect Perf Snapshot'
ORDER BY run_date DESC, run_time DESC
```

---

## Troubleshooting

### "SQL Server Agent is not running"
**Linux Server:**
```bash
sudo systemctl start mssql-server-agent
sudo systemctl enable mssql-server-agent
```

### "Cannot connect to server"
- Check firewall rules (default SQL port: 1433)
- Verify SQL Server is running: `sudo systemctl status mssql-server`
- Test with: `sqlcmd -S localhost -U sa -P YourPassword`

### "Login failed for user"
- Verify username and password
- Check if SQL authentication is enabled
- For `sa`, ensure it's not disabled

### "Insufficient permissions"
- User needs `sysadmin` role or:
  - `CREATE DATABASE` permission
  - `ALTER ANY DATABASE` permission
  - SQL Agent permissions (`SQLAgentUserRole`)

### Collection Errors
```sql
-- Check recent errors
SELECT TOP 20
    DateTime_Occurred,
    ProcedureName,
    ProcedureSection,
    ErrDescription
FROM DBATools.dbo.LogEntry
WHERE IsError = 1
ORDER BY LogEntryID DESC
```

Common issues:
- **QUOTED_IDENTIFIER errors:** Already fixed in FIXED files
- **Permission errors:** Grant VIEW SERVER STATE to login
- **Timeout errors:** Normal on busy servers, collection will retry

---

## Configuration Changes

After deployment, you can adjust settings:

```sql
-- View all settings
EXEC DBATools.dbo.DBA_ViewConfig

-- Change retention to 60 days
EXEC DBATools.dbo.DBA_UpdateConfig 'RetentionDays', '60'

-- Increase queries captured
EXEC DBATools.dbo.DBA_UpdateConfig 'QueryStatsTopN', '100'

-- Disable P2 collection (reduce storage)
EXEC DBATools.dbo.DBA_UpdateConfig 'EnableP2Collection', '0'

-- Enable P3 collection (deep troubleshooting)
EXEC DBATools.dbo.DBA_UpdateConfig 'EnableP3Collection', '1'
```

---

## Storage Management

### Check Storage Usage
```sql
-- Database size
SELECT
    name,
    size * 8 / 1024 AS SizeMB,
    (size * 8.0 / 1024) / 1024 AS SizeGB
FROM sys.master_files
WHERE database_id = DB_ID('DBATools')

-- Row counts
SELECT
    OBJECT_NAME(object_id) AS TableName,
    SUM(row_count) AS RowCount
FROM sys.dm_db_partition_stats
WHERE OBJECT_NAME(object_id) LIKE 'PerfSnapshot%'
  AND index_id IN (0,1)
GROUP BY OBJECT_NAME(object_id)
ORDER BY SUM(row_count) DESC
```

### Manual Purge
```sql
-- Purge data older than 30 days (uses config default)
EXEC DBATools.dbo.DBA_PurgeOldSnapshots @Debug = 1

-- Purge data older than 7 days (override)
EXEC DBATools.dbo.DBA_PurgeOldSnapshots @RetentionDays = 7, @Debug = 1
```

---

## Files You DON'T Need to Run

These are in `archive/old_versions/` - **DO NOT RUN THESE:**

- `00_DEPLOY_ALL.sql` - Old combined script
- `03_create_DBA_CollectPerformanceSnapshot.sql` - Old baseline (has errors)
- Files without `_FIXED` suffix - Old versions with syntax errors
- `12_create_diagnostic_views.sql` - Views included in config file now

These are in `archive/helpers/` - **PowerShell/Linux tools (not needed for SSMS):**
- All `.ps1` files - PowerShell deployment scripts
- `validate_*.sql` - Used for automated testing
- `test_collection.sql` - Validation queries (use 99_TEST_AND_VALIDATE.sql instead)

---

## Next Steps

1. **Monitor for 24 hours** - Watch job execution and data growth
2. **Adjust config** - Tune TopN values and priorities based on your needs
3. **Review storage** - Ensure database has room for 30 days of data
4. **Schedule purge** - Optional: Create weekly job to run `DBA_PurgeOldSnapshots`
5. **Backup DBATools** - Include in your backup strategy

---

## Quick Reference - Files in Correct Order

1. `01_create_DBATools_and_tables.sql`
2. `02_create_DBA_LogEntry_Insert.sql`
3. `13_create_config_table_and_functions.sql`
4. `06_create_modular_collectors_P0_FIXED.sql`
5. `07_create_modular_collectors_P1_FIXED.sql`
6. `08_create_modular_collectors_P2_P3_FIXED.sql`
7. `10_create_master_orchestrator_FIXED.sql`
8. `11_create_purge_procedure_FIXED.sql`
9. `04_create_agent_job_FIXED.sql`
10. `99_TEST_AND_VALIDATE.sql` (optional test)

**Total Time:** 5-10 minutes in SSMS

---

## Support

- **Documentation:** See `CLAUDE.md`, `FINAL-DEPLOYMENT-SUMMARY.md`
- **Configuration:** See `CONFIGURATION-GUIDE.md`
- **Analysis:** See `MONITORING-GAPS-ANALYSIS.md`

**Ready to deploy! Open SSMS and start with file #1.**
