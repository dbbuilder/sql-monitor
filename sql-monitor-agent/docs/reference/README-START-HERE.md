# SQL Server Monitoring System

**Version:** 1.0 - Production Ready
**Target:** SQL Server 2019/2022 Standard Edition (Linux)
**Deployment Method:** SQL Server Management Studio (SSMS)

---

## 🚀 Quick Start - Two Options

### Option 1: PowerShell Automated (Fastest - 2-3 minutes)
```powershell
.\Deploy-MonitoringSystem.ps1 `
    -ServerName "your-server.com" `
    -Username "sa" `
    -Password "YourPassword" `
    -TrustServerCertificate
```
See `POWERSHELL-DEPLOYMENT.md` for full details.

### Option 2: SSMS Manual (5-10 minutes)
1. **Read:** `SSMS-DEPLOYMENT-GUIDE.md` (full instructions)
2. **Follow:** `DEPLOYMENT-CHECKLIST.txt` (simple checklist)
3. **Run files 1-9** in SSMS in numbered order
4. **Done!** System collects data every 5 minutes automatically

---

## 📁 Files to Run (In Order)

These are the ONLY files you need to run:

| # | File | Purpose |
|---|------|---------|
| 1 | `01_create_DBATools_and_tables.sql` | Database + 24 tables |
| 2 | `02_create_DBA_LogEntry_Insert.sql` | Logging |
| 3 | `13_create_config_table_and_functions.sql` | Config system |
| 4 | `06_create_modular_collectors_P0_FIXED.sql` | Critical collectors |
| 5 | `07_create_modular_collectors_P1_FIXED.sql` | High-priority collectors |
| 6 | `08_create_modular_collectors_P2_P3_FIXED.sql` | Medium/Low collectors |
| 7 | `10_create_master_orchestrator_FIXED.sql` | Main coordinator |
| 8 | `11_create_purge_procedure_FIXED.sql` | Data retention |
| 9 | `04_create_agent_job_FIXED.sql` | Automated job (every 5 min) |
| 10 | `99_TEST_AND_VALIDATE.sql` | Testing (optional) |

**Time:** 5-10 minutes total

---

## 📋 What Gets Deployed

- **24 procedures** - All monitoring collectors
- **5 functions** - Config helpers & timezone conversion
- **1 SQL Agent job** - Runs every 5 minutes
- **28 config settings** - Fully customizable
- **24 tables** - Stores all performance data
- **Enhanced views** - Eastern Time reporting

---

## 🗂️ Directory Structure

```
sql_monitor/
├── SSMS-DEPLOYMENT-GUIDE.md      ⭐ START HERE - Full instructions
├── DEPLOYMENT-CHECKLIST.txt       ⭐ Quick checklist
├── README-START-HERE.md           ⭐ This file
│
├── 01_create_DBATools_and_tables.sql       [RUN #1]
├── 02_create_DBA_LogEntry_Insert.sql       [RUN #2]
├── 13_create_config_table_and_functions.sql [RUN #3]
├── 06_create_modular_collectors_P0_FIXED.sql [RUN #4]
├── 07_create_modular_collectors_P1_FIXED.sql [RUN #5]
├── 08_create_modular_collectors_P2_P3_FIXED.sql [RUN #6]
├── 10_create_master_orchestrator_FIXED.sql  [RUN #7]
├── 11_create_purge_procedure_FIXED.sql      [RUN #8]
├── 04_create_agent_job_FIXED.sql           [RUN #9]
├── 99_TEST_AND_VALIDATE.sql                [RUN #10 - Optional]
│
├── CLAUDE.md                      Project overview
├── CONFIGURATION-GUIDE.md         Config system reference
├── FINAL-DEPLOYMENT-SUMMARY.md    Complete system docs
├── MONITORING-GAPS-ANALYSIS.md    Component justification
├── ENHANCEMENT-CHECKLIST.md       Priority matrix
│
└── archive/
    ├── old_versions/              ⚠️ Don't run these!
    └── helpers/                   PowerShell/Linux scripts
```

---

## ⚠️ DO NOT RUN These Files

Archived in `archive/old_versions/` - old versions with errors:
- Anything without `_FIXED` in the name
- `00_DEPLOY_ALL.sql`
- `03_create_DBA_CollectPerformanceSnapshot.sql`
- `12_create_diagnostic_views.sql`

---

## ✅ System Features

### Automatic Monitoring
- **Query Performance** - Top expensive queries
- **I/O Statistics** - Database I/O latency
- **Memory Usage** - Buffer pool, memory clerks
- **Backup Status** - Last backup times
- **Index Usage** - Index statistics
- **Wait Statistics** - Server waits analysis
- **TempDB Contention** - TempDB performance
- **Missing Indexes** - Recommendations
- **Server Configuration** - Config tracking
- **VLF Counts** - Transaction log health
- **Scheduler Health** - CPU scheduler status
- **Performance Counters** - Key SQL metrics

### Data Collection
- **Frequency:** Every 5 minutes (configurable)
- **Retention:** 30 days (configurable)
- **Storage:** ~5-20 MB per snapshot
- **Priority Levels:** P0 (Critical), P1 (High), P2 (Medium), P3 (Low)

### Configuration
- **28 settings** - All customizable via stored procedures
- **Timezone support** - Stores UTC, displays Eastern Time
- **Easy tuning** - Change TopN values, retention, priorities

---

## 🔧 Prerequisites

Before deployment:

- [x] SQL Server 2019+ (Linux or Windows)
- [x] Standard or Enterprise Edition
- [x] SSMS installed on your PC
- [x] SQL authentication credentials
- [x] Permissions: CREATE DATABASE, SQL Agent access
- [x] SQL Server Agent running (Linux: `sudo systemctl start mssql-server-agent`)

---

## 📊 After Deployment

### Monitor Collection
```sql
-- View recent snapshots
SELECT TOP 10 *
FROM DBATools.dbo.PerfSnapshotRun
ORDER BY PerfSnapshotRunID DESC

-- Check for errors
SELECT TOP 20 *
FROM DBATools.dbo.LogEntry
WHERE IsError = 1
ORDER BY LogEntryID DESC
```

### Adjust Configuration
```sql
-- View all settings
EXEC DBATools.dbo.DBA_ViewConfig

-- Change retention
EXEC DBATools.dbo.DBA_UpdateConfig 'RetentionDays', '60'

-- Increase queries captured
EXEC DBATools.dbo.DBA_UpdateConfig 'QueryStatsTopN', '100'
```

### Check Storage
```sql
-- Database size
SELECT
    name,
    size * 8 / 1024 AS SizeMB
FROM sys.master_files
WHERE database_id = DB_ID('DBATools')

-- Row counts
SELECT
    OBJECT_NAME(object_id) AS TableName,
    SUM(row_count) AS Rows
FROM sys.dm_db_partition_stats
WHERE OBJECT_NAME(object_id) LIKE 'PerfSnapshot%'
  AND index_id IN (0,1)
GROUP BY OBJECT_NAME(object_id)
ORDER BY SUM(row_count) DESC
```

---

## 🆘 Troubleshooting

### SQL Agent Not Running
```bash
# On Linux server:
sudo systemctl status mssql-server-agent
sudo systemctl start mssql-server-agent
sudo systemctl enable mssql-server-agent
```

### Collection Errors
```sql
-- Get error details
SELECT TOP 10
    DateTime_Occurred,
    ProcedureName,
    ProcedureSection,
    ErrDescription
FROM DBATools.dbo.LogEntry
WHERE IsError = 1
ORDER BY LogEntryID DESC
```

### No Data Collected
1. Check if job is enabled (SQL Server Agent > Jobs)
2. Run manual collection: `EXEC DBATools.dbo.DBA_CollectPerformanceSnapshot @Debug = 1`
3. Check LogEntry table for errors
4. Verify config enables P0/P1/P2

---

## 📚 Documentation

- **SSMS-DEPLOYMENT-GUIDE.md** - Step-by-step SSMS instructions
- **DEPLOYMENT-CHECKLIST.txt** - Quick reference checklist
- **CONFIGURATION-GUIDE.md** - All config settings explained
- **FINAL-DEPLOYMENT-SUMMARY.md** - Complete system overview
- **CLAUDE.md** - Project architecture and design

---

## 🎯 Ready to Deploy?

1. Open **SSMS**
2. Connect to your Linux SQL Server
3. Follow **SSMS-DEPLOYMENT-GUIDE.md**
4. Run files 1-9 in order
5. **Done!**

System will automatically collect data every 5 minutes.

---

**Questions?** See `SSMS-DEPLOYMENT-GUIDE.md` for detailed troubleshooting.
