# Quick Deployment Guide - SQL Monitoring System

## TL;DR - One Command Deployment

```powershell
cd /mnt/e/Downloads/sql_monitor

./Deploy-MonitoringSystem.ps1 `
    -ServerName "172.31.208.1" `
    -Port 14333 `
    -Username "sv" `
    -Password "Gv51076!" `
    -TrustServerCertificate `
    -SkipValidation
```

**Duration**: 2-5 minutes
**Expected result**: Monitoring system deployed and collecting every 5 minutes

---

## What Gets Deployed

1. **DBATools database** - Monitoring data storage
2. **Configuration system** - 28 configurable settings
3. **Database filter view** - Include/exclude databases from monitoring
4. **Enhanced monitoring tables** - P0/P1/P2 data storage
5. **P0 (Critical) collectors** - Query stats, I/O, memory, backups
6. **P1 (High) collectors** - Index usage, missing indexes, wait stats, query plans
7. **P2 (Medium) collectors** - VLF counts, deadlocks, server config
8. **Master orchestrator** - Coordinates all collection
9. **SQL Agent job** - Runs every 5 minutes automatically
10. **Reporting views/procedures** - View collected data

---

## Prerequisites

### Required

1. **PowerShell 5.1+** (Windows/Linux/WSL)
2. **sqlcmd utility** ([Download](https://learn.microsoft.com/en-us/sql/tools/sqlcmd-utility))
3. **SQL Server credentials** (sysadmin or db_owner on master)
4. **SQL Server Agent running** (for automated collection)

### Check sqlcmd

```bash
sqlcmd -?
```

If not found:
```bash
# Ubuntu/Debian/WSL
curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
sudo add-apt-repository "$(wget -qO- https://packages.microsoft.com/config/ubuntu/20.04/prod.list)"
sudo apt-get update
sudo apt-get install -y mssql-tools unixodbc-dev
echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc
source ~/.bashrc
```

---

## Deployment Options

### Option 1: Full Automated (Recommended)

```powershell
./Deploy-MonitoringSystem.ps1 `
    -ServerName "server.domain.com" `
    -Username "sa" `
    -Password "YourPassword" `
    -TrustServerCertificate
```

**Default behavior**:
- Skips slow validation (use `-SkipValidation:$false` to enable)
- Creates SQL Agent job (use `-SkipAgentJob` if Agent not running)

---

### Option 2: Custom Port

```powershell
./Deploy-MonitoringSystem.ps1 `
    -ServerName "192.168.1.100" `
    -Port 14333 `
    -Username "sa" `
    -Password "YourPassword" `
    -TrustServerCertificate
```

---

### Option 3: Without SQL Agent Job

```powershell
./Deploy-MonitoringSystem.ps1 `
    -ServerName "localhost" `
    -Username "sa" `
    -Password "YourPassword" `
    -SkipAgentJob
```

**Use when**: SQL Server Agent not running (requires manual collection)

---

### Option 4: With Full Validation

```powershell
./Deploy-MonitoringSystem.ps1 `
    -ServerName "localhost" `
    -Username "sa" `
    -Password "YourPassword" `
    -SkipValidation:$false
```

**Warning**: Takes 30-60 seconds with no visible progress

---

## Manual Deployment (Alternative)

If PowerShell not available, run scripts manually in this order:

```sql
-- 1. Database and tables
:r 01_create_DBATools_and_tables.sql

-- 2. Logging
:r 02_create_DBA_LogEntry_Insert.sql

-- 3. Configuration
:r 13_create_config_table_and_functions.sql

-- 4. Database filter view (NEW)
:r 13b_create_database_filter_view.sql

-- 5. Enhanced tables
:r 05_create_enhanced_tables.sql

-- 6-8. Collectors
:r 06_create_modular_collectors_P0_FIXED.sql
:r 07_create_modular_collectors_P1_FIXED.sql
:r 08_create_modular_collectors_P2_P3_FIXED.sql

-- 9. Reporting
:r 09_create_reporting_views.sql

-- 10. Orchestrator
:r 10_create_master_orchestrator_FIXED.sql

-- 11. Purge
:r 11_create_purge_procedure_FIXED.sql

-- 12. Agent job (optional)
USE msdb
GO
:r 04_create_agent_job_FIXED.sql

-- 13. Reporting procedures (optional)
:r 14_create_reporting_procedures.sql
```

---

## Verification

### Step 1: Test Manual Collection

```sql
USE DBATools
GO

-- Run one collection cycle
EXEC dbo.DBA_CollectPerformanceSnapshot @Debug = 1
```

**Expected**: Completes in < 3 seconds

---

### Step 2: Check Results

```sql
-- View snapshot runs
SELECT TOP 5 * FROM dbo.PerfSnapshotRun ORDER BY PerfSnapshotRunID DESC

-- View database stats
SELECT TOP 10 * FROM dbo.PerfSnapshotDB ORDER BY PerfSnapshotRunID DESC

-- Check for errors
SELECT TOP 10 * FROM dbo.LogEntry WHERE IsError = 1 ORDER BY LogEntryID DESC
```

---

### Step 3: Verify Database Filters

```sql
-- Show current filter configuration
EXEC dbo.DBA_TestDatabaseFilters
```

**Default**: Monitors all user databases except DBATools

---

### Step 4: Check SQL Agent Job

```sql
-- Verify job exists and is enabled
SELECT
    j.name,
    j.enabled,
    js.last_run_date,
    js.last_run_time,
    js.last_run_outcome
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobservers js ON j.job_id = js.job_id
WHERE j.name = 'DBA Collect Perf Snapshot'
```

**Expected**: enabled = 1, runs every 5 minutes

---

## Configuration

### View All Settings

```sql
EXEC DBATools.dbo.DBA_ViewConfig
```

### Common Adjustments

```sql
-- Change collection interval
EXEC DBA_UpdateConfig 'CollectionIntervalMinutes', '15'  -- Every 15 minutes instead of 5

-- Change retention
EXEC DBA_UpdateConfig 'RetentionDays', '60'  -- Keep 60 days instead of 30

-- Disable P2 collection (VLF, deadlocks, etc.)
EXEC DBA_UpdateConfig 'EnableP2Collection', '0'

-- Change timezone for reporting
EXEC DBA_UpdateConfig 'ReportingTimeZone', 'Pacific Standard Time'

-- Reduce TOP N limits (faster collection)
EXEC DBA_UpdateConfig 'QueryStatsTopN', '50'    -- Capture top 50 queries (default 100)
EXEC DBA_UpdateConfig 'QueryPlansTopN', '15'   -- Capture top 15 plans (default 30)
```

---

## Database Filtering

### Exclude Specific Databases

```sql
-- Exclude test and dev databases
EXEC DBA_UpdateConfig 'DatabaseIncludeFilter', '*'
EXEC DBA_UpdateConfig 'DatabaseExcludeFilter', 'Test*;Dev*;Staging*;DBATools'

-- Test filters
EXEC DBA_TestDatabaseFilters
```

---

### Monitor Only Production

```sql
-- Include only production databases
EXEC DBA_UpdateConfig 'DatabaseIncludeFilter', 'Prod*;Production*'
EXEC DBA_UpdateConfig 'DatabaseExcludeFilter', 'DBATools'

-- Test filters
EXEC DBA_TestDatabaseFilters
```

---

## Reporting

### Quick Health Check

```sql
EXEC DBATools.dbo.DBA_CheckSystemHealth
```

**Shows**: Current CPU, memory, I/O, blocking sessions

---

### Top Resource Consumers

```sql
-- Top queries by CPU
EXEC DBATools.dbo.DBA_Monitor_TopQueriesByCPU @TopN = 20

-- Top queries by reads
EXEC DBATools.dbo.DBA_Monitor_TopQueriesByReads @TopN = 20

-- Top missing indexes
EXEC DBATools.dbo.DBA_Monitor_MissingIndexes @TopN = 20
```

---

### Backup Status

```sql
-- Databases with backup issues
EXEC DBATools.dbo.DBA_Monitor_BackupStatus
```

---

### Run All Reports

```sql
EXEC DBATools.dbo.DBA_Monitor_RunAll
```

---

## Troubleshooting

### Issue 1: Deployment Fails

**Check connection**:
```bash
sqlcmd -S server,port -U username -P password -C -Q "SELECT @@VERSION"
```

**Common causes**:
- Firewall blocking port
- Incorrect credentials
- SQL Server not running
- Trust certificate needed (use `-TrustServerCertificate`)

---

### Issue 2: Collection Hangs

**Check for offline databases**:
```sql
SELECT name, state_desc FROM sys.databases WHERE state_desc <> 'ONLINE'
```

**Solution**: Latest version filters offline databases automatically. Re-deploy if using old version.

---

### Issue 3: SQL Agent Job Not Running

**Check Agent status**:
```bash
# Linux
sudo systemctl status mssql-server-agent

# Start if stopped
sudo systemctl start mssql-server-agent
sudo systemctl enable mssql-server-agent
```

**Windows**: Services → SQL Server Agent → Start

---

### Issue 4: Too Much Data

**Reduce collection frequency**:
```sql
EXEC DBA_UpdateConfig 'CollectionIntervalMinutes', '15'  -- Every 15 min
```

**Reduce TOP N limits**:
```sql
EXEC DBA_UpdateConfig 'QueryStatsTopN', '50'
EXEC DBA_UpdateConfig 'QueryPlansTopN', '15'
EXEC DBA_UpdateConfig 'MissingIndexTopN', '50'
```

**Disable P2/P3**:
```sql
EXEC DBA_UpdateConfig 'EnableP2Collection', '0'
EXEC DBA_UpdateConfig 'EnableP3Collection', '0'
```

---

## Data Retention

### Manual Purge

```sql
-- Delete data older than 7 days
EXEC DBATools.dbo.DBA_PurgeHistoricalData @RetentionDays = 7
```

### View Data Volume

```sql
-- Check table sizes
SELECT
    t.name AS TableName,
    SUM(p.rows) AS RowCount,
    SUM(a.total_pages) * 8 / 1024 AS TotalSizeMB
FROM DBATools.sys.tables t
JOIN DBATools.sys.partitions p ON t.object_id = p.object_id
JOIN DBATools.sys.allocation_units a ON p.partition_id = a.container_id
WHERE t.schema_id = SCHEMA_ID('dbo')
  AND t.name LIKE 'Perf%'
GROUP BY t.name
ORDER BY TotalSizeMB DESC
```

---

## Uninstall

```sql
-- Drop database (removes all monitoring data)
USE master
GO
DROP DATABASE DBATools
GO

-- Remove SQL Agent job
USE msdb
GO
EXEC sp_delete_job @job_name = 'DBA Collect Perf Snapshot'
GO
```

---

## Next Steps

### After Deployment

1. **Monitor for 30 minutes** - Ensure collection runs every 5 minutes
2. **Check data growth** - View table sizes after 24 hours
3. **Review configuration** - Adjust TOP N limits, retention, filters as needed
4. **Set up alerts** (optional) - Create SQL Agent alerts for critical thresholds
5. **Create dashboards** (optional) - Use Power BI, Grafana, or SSRS

### Weekly Maintenance

1. **Check for errors**: `SELECT * FROM LogEntry WHERE IsError = 1 ORDER BY LogEntryID DESC`
2. **Review disk usage**: Check PerfSnapshot* table sizes
3. **Purge old data** (if retention > 30 days): `EXEC DBA_PurgeHistoricalData @RetentionDays = 30`

---

## Summary

**Deployment time**: 2-5 minutes
**Collection frequency**: Every 5 minutes (configurable)
**Data retention**: 30 days (configurable)
**Performance impact**: < 0.5% CPU overhead
**Disk growth**: 75-90 MB/day, 2-3 GB/month

**Features**:
- Automated performance monitoring
- Query performance tracking
- Index usage and missing index recommendations
- Wait statistics and blocking detection
- Backup validation
- VLF monitoring
- Deadlock tracking
- Configurable database filtering
- Eastern timezone reporting (configurable)

**Documentation**:
- `CRITICAL-FIXES-SUMMARY.md` - All fixes applied
- `DATABASE-FILTER-SYSTEM.md` - Database filtering guide
- `FIRST-RUN-TIMING.md` - Performance expectations
- `PERFORMANCE-IMPACT-ANALYSIS.md` - Overhead analysis
