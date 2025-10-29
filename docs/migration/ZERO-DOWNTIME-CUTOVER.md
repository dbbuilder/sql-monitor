# Zero-Downtime Cutover Procedure

**Phase**: 1.9 - sql-monitor-agent Integration
**Document**: Day 3 Deliverable
**Author**: SQL Server Monitor Project
**Date**: 2025-10-28

---

## Overview

This document provides a **production-ready, zero-downtime cutover procedure** for migrating from the legacy sql-monitor architecture (generic TALL schema) to the Phase 1.9 integrated architecture (type-safe WIDE schema with view abstraction).

**Key Design Principle**: The API never sees downtime because views provide a unified abstraction layer over both old and new data sources.

---

## Migration Scenarios

### Scenario A: Fresh Installation (No Existing Data)
**Complexity**: Low
**Downtime**: None (new deployment)
**Duration**: 30 minutes

**Steps**:
1. Deploy Phase 1.9 schema (Day 1 scripts)
2. Deploy mapping views (Day 2 scripts)
3. Deploy API (no changes required)
4. Deploy Grafana dashboards
5. Start data collection

**No cutover needed** - this is a greenfield deployment.

---

### Scenario B: Existing sql-monitor (Legacy PerformanceMetrics Table)
**Complexity**: Medium
**Downtime**: **Zero** (views handle transition)
**Duration**: 2-4 hours

**Steps**: See [Cutover Procedure B](#cutover-procedure-b-legacy-performancemetrics) below

---

### Scenario C: Consolidating Multiple DBATools Instances → MonitoringDB
**Complexity**: High
**Downtime**: **Zero** (phased migration)
**Duration**: 1-3 days (depending on data volume)

**Steps**: See [Cutover Procedure C](#cutover-procedure-c-multi-server-consolidation) below

---

## Cutover Procedure B: Legacy PerformanceMetrics

### Phase: Existing sql-monitor with PerformanceMetrics table

**Objective**: Migrate from generic TALL schema (key-value pairs) to WIDE schema (typed columns) without API downtime.

### Prerequisites

✅ Backup database (full backup + transaction log backup)
✅ Phase 1.9 Day 1 schema deployed (24 tables created)
✅ Phase 1.9 Day 2 views deployed (10 views created)
✅ API and Grafana are currently operational
✅ Maintenance window scheduled (optional - migration can run during business hours)

### Timeline: 2-4 Hours

| Step | Duration | Can Fail? | Rollback Time |
|------|----------|-----------|---------------|
| 1. Validation | 15 min | No | N/A |
| 2. Schema Deployment | 30 min | Yes | 5 min |
| 3. Legacy Table Rename | 5 min | Yes | 2 min |
| 4. View Update | 5 min | Yes | 2 min |
| 5. Data Collection Start | 10 min | No | N/A |
| 6. Parallel Operation | 1-2 hours | No | N/A |
| 7. Validation | 30 min | No | N/A |
| 8. Legacy Marking | 15 min | No | N/A |

**Total**: 2-4 hours (most of which is parallel operation monitoring)

---

### Step 1: Pre-Migration Validation (15 minutes)

**Status**: API remains ONLINE ✅

**Actions**:

```sql
-- Connect to target database
USE [DBATools];  -- or MonitoringDB
GO

-- 1.1: Verify existing PerformanceMetrics table
SELECT
    COUNT(*) AS TotalRows,
    MIN(CollectionTime) AS EarliestData,
    MAX(CollectionTime) AS LatestData,
    DATEDIFF(DAY, MIN(CollectionTime), MAX(CollectionTime)) AS DaysOfData
FROM dbo.PerformanceMetrics;

-- 1.2: Verify API is working
-- Test endpoint: GET /api/metrics?startDate=YYYY-MM-DD&endDate=YYYY-MM-DD
-- Expected: 200 OK with JSON data

-- 1.3: Verify database backup
SELECT TOP 1
    database_name,
    backup_finish_date,
    type,
    DATEDIFF(HOUR, backup_finish_date, GETDATE()) AS HoursAgo
FROM msdb.dbo.backupset
WHERE database_name = DB_NAME()
ORDER BY backup_finish_date DESC;

-- Ensure backup is recent (< 24 hours)
```

**Expected Output**:
```
TotalRows    EarliestData            LatestData              DaysOfData
-----------  ----------------------  ----------------------  ----------
5000000      2024-01-01 00:00:00     2025-10-28 10:00:00     666
```

**Validation Checklist**:
- ✅ PerformanceMetrics table exists
- ✅ Data volume confirmed
- ✅ API responding (HTTP 200)
- ✅ Recent backup exists
- ✅ Team notified of migration

**If any validation fails**: STOP and investigate before proceeding.

---

### Step 2: Deploy Phase 1.9 Schema (30 minutes)

**Status**: API remains ONLINE ✅ (no schema changes to existing tables)

**Actions**:

```bash
# Navigate to sql-monitor directory
cd /mnt/d/dev2/sql-monitor

# Set environment variables
export SQL_SERVER="your-server,port"
export SQL_USER="sa"
export SQL_PASSWORD="YourPassword"

# Deploy core tables (creates new tables, doesn't touch PerformanceMetrics)
sqlcmd -S $SQL_SERVER -U $SQL_USER -P $SQL_PASSWORD -C \
  -d DBATools \
  -i database/20-create-dbatools-tables.sql

# Deploy enhanced tables
sqlcmd -S $SQL_SERVER -U $SQL_USER -P $SQL_PASSWORD -C \
  -d DBATools \
  -i database/21-create-enhanced-tables.sql

# Deploy mapping views (without legacy UNION yet)
sqlcmd -S $SQL_SERVER -U $SQL_USER -P $SQL_PASSWORD -C \
  -d DBATools \
  -i database/22-create-mapping-views.sql
```

**Expected Output**:
```
✓ Core tables deployment complete (5 tables + 1 Servers table)
✓ Enhanced tables deployment complete (19 tables)
✓ Mapping views deployment complete (10 views)
```

**Validation**:
```sql
-- Verify new tables exist
SELECT name FROM sys.tables
WHERE name LIKE 'PerfSnapshot%'
ORDER BY name;

-- Verify views exist
SELECT name FROM sys.views
WHERE name LIKE 'vw_Performance%'
ORDER BY name;
```

**Expected**: 24 tables + 10 views created, API still working against old PerformanceMetrics table.

---

### Step 3: Rename Legacy Table (5 minutes)

**Status**: API remains ONLINE ✅ (but queries will start failing soon)

**⚠ CRITICAL MOMENT**: This is where the cutover begins. From this point forward, rollback procedures must be ready.

**Actions**:

```sql
USE [DBATools];
GO

-- Begin transaction (for safety)
BEGIN TRANSACTION;

-- 3.1: Verify API is not currently querying (optional - check for active queries)
SELECT
    session_id,
    status,
    command,
    DB_NAME(database_id) AS database_name,
    wait_type
FROM sys.dm_exec_requests
WHERE database_id = DB_ID()
  AND session_id <> @@SPID;

-- 3.2: Drop existing vw_PerformanceMetrics view
IF OBJECT_ID('dbo.vw_PerformanceMetrics', 'V') IS NOT NULL
    DROP VIEW dbo.vw_PerformanceMetrics;

-- 3.3: Rename PerformanceMetrics → PerformanceMetrics_Legacy
EXEC sp_rename 'dbo.PerformanceMetrics', 'PerformanceMetrics_Legacy';

-- 3.4: Verify rename
IF OBJECT_ID('dbo.PerformanceMetrics_Legacy', 'U') IS NOT NULL
    PRINT '✓ Rename successful: PerformanceMetrics → PerformanceMetrics_Legacy';

-- Commit transaction
COMMIT TRANSACTION;
```

**Expected Downtime**: **30-60 seconds** (time between DROP VIEW and CREATE VIEW in next step)

**During this window**: API queries will return error 404 (view not found)

---

### Step 4: Create Unified View with Legacy UNION (5 minutes)

**Status**: API comes back ONLINE ✅

**Actions**:

```sql
USE [DBATools];
GO

-- Run the legacy migration script
-- This script creates vw_PerformanceMetrics with UNION of legacy + new data
:r database/23-migrate-legacy-data.sql
```

**Expected Output**:
```
✓ Legacy table renamed: PerformanceMetrics → PerformanceMetrics_Legacy
✓ vw_PerformanceMetrics updated to UNION legacy + new data
✓ Legacy data preserved (zero data loss)
✓ Stored procedures created:
  - dbo.usp_MarkLegacyDataAsMigrated
  - dbo.usp_CleanupLegacyData
```

**Validation**:

```sql
-- Verify view returns data
SELECT COUNT(*) AS TotalMetrics
FROM dbo.vw_PerformanceMetrics;

-- Should match or exceed original PerformanceMetrics count

-- Test API endpoint
-- GET /api/metrics?startDate=2025-10-27&endDate=2025-10-28
-- Expected: 200 OK with JSON data (including legacy data)
```

**Result**: **API is back online** with access to both legacy and new data sources.

---

### Step 5: Start New Data Collection (10 minutes)

**Status**: API ONLINE ✅ (serving legacy data), new collection starting

**Actions**:

```sql
-- Option A: Manual test collection
USE [DBATools];
GO

-- Insert a test server (if not exists)
IF NOT EXISTS (SELECT 1 FROM dbo.Servers WHERE ServerName = @@SERVERNAME)
BEGIN
    INSERT INTO dbo.Servers (ServerName, Environment, IsActive)
    VALUES (@@SERVERNAME, 'Production', 1);
END

-- Manually run collection procedure (from sql-monitor-agent)
-- EXEC dbo.DBA_CollectPerformanceSnapshot;
-- (Assumes you've deployed sql-monitor-agent's collection procedures)

-- Verify new data appears
SELECT TOP 10
    PerfSnapshotRunID,
    SnapshotUTC,
    ServerID,
    ServerName,
    CpuSignalWaitPct,
    SessionsCount
FROM dbo.PerfSnapshotRun
ORDER BY SnapshotUTC DESC;
```

**Option B**: Configure SQL Agent job for automated collection (recommended)

```sql
-- Create SQL Agent job (run every 5 minutes)
-- Job step: EXEC dbo.DBA_CollectPerformanceSnapshot;
```

**Validation**:
- ✅ New PerfSnapshotRun rows appearing (every 5 minutes)
- ✅ ServerID properly populated (not NULL)
- ✅ Enhanced tables being populated (QueryStats, IOStats, Memory, etc.)

---

### Step 6: Parallel Operation (1-2 hours)

**Status**: DUAL MODE ✅
- Legacy data: Served from PerformanceMetrics_Legacy (IsMigrated = 0)
- New data: Served from PerfSnapshotRun → vw_PerformanceMetrics_Core
- API: Unaware of difference (views handle UNION)

**Actions**:

```sql
-- Monitor data collection every 15 minutes
SELECT
    'Legacy' AS DataSource,
    COUNT(*) AS RowCount,
    MAX(CollectionTime) AS LatestCollection
FROM dbo.PerformanceMetrics_Legacy
WHERE IsMigrated = 0

UNION ALL

SELECT
    'New' AS DataSource,
    COUNT(*) AS RowCount,
    MAX(SnapshotUTC) AS LatestCollection
FROM dbo.PerfSnapshotRun;
```

**Expected Output** (after 1 hour):

| DataSource | RowCount | LatestCollection      |
|------------|----------|-----------------------|
| Legacy     | 5000000  | 2025-10-28 10:00:00   |
| New        | 12       | 2025-10-28 11:00:00   |

**Validation Queries**:

```sql
-- 1. Verify API compatibility (view returns expected structure)
SELECT TOP 10
    MetricID,
    ServerID,
    CollectionTime,
    MetricCategory,
    MetricName,
    MetricValue
FROM dbo.vw_PerformanceMetrics
ORDER BY CollectionTime DESC;

-- 2. Verify no data loss (row count comparison)
DECLARE @LegacyCount BIGINT, @ViewCount BIGINT;

SELECT @LegacyCount = COUNT(*) FROM dbo.PerformanceMetrics_Legacy WHERE IsMigrated = 0;
SELECT @ViewCount = COUNT(*) FROM dbo.vw_PerformanceMetrics;

IF @ViewCount < @LegacyCount
BEGIN
    PRINT '⚠ WARNING: View row count less than legacy table!';
    PRINT '  Legacy: ' + CAST(@LegacyCount AS VARCHAR);
    PRINT '  View: ' + CAST(@ViewCount AS VARCHAR);
END
ELSE
BEGIN
    PRINT '✓ Data integrity verified';
    PRINT '  View includes all legacy data plus new data';
END

-- 3. Test Grafana dashboards
-- Browse to: http://localhost:3000/d/instance-health
-- Verify: Charts display data, no errors
```

**Monitoring Checklist**:
- ✅ New data collecting every 5 minutes
- ✅ API responding normally
- ✅ Grafana dashboards working
- ✅ No errors in SQL Server error log
- ✅ Performance acceptable (query times < 500ms)

---

### Step 7: Post-Cutover Validation (30 minutes)

**Status**: DUAL MODE ✅ (everything working, time to validate)

**Validation Tests**:

```sql
-- Run comprehensive validation test suite
sqlcmd -S $SQL_SERVER -U $SQL_USER -P $SQL_PASSWORD -C \
  -d DBATools \
  -i database/tests/test-phase-1.9-schema.sql

sqlcmd -S $SQL_SERVER -U $SQL_USER -P $SQL_PASSWORD -C \
  -d DBATools \
  -i database/tests/test-phase-1.9-views.sql
```

**Expected**: 27 schema tests + 27 view tests = **54/54 tests passing** ✅

**Performance Benchmarks**:

```sql
-- Run performance benchmarks
sqlcmd -S $SQL_SERVER -U $SQL_USER -P $SQL_PASSWORD -C \
  -d DBATools \
  -i database/tests/benchmark-phase-1.9-views.sql
```

**Expected**: All 8 benchmarks meet targets (especially Benchmark 4: 90-day query < 500ms)

---

### Step 8: Mark Legacy Data as Migrated (15 minutes)

**Status**: TRANSITIONING to new-only mode

**When to Run**: After 24-48 hours of parallel operation with no issues detected.

**Actions**:

```sql
USE [DBATools];
GO

-- Mark all legacy data as migrated (hides from view)
EXEC dbo.usp_MarkLegacyDataAsMigrated;

-- Verify legacy data is now hidden
SELECT COUNT(*) AS UnmigratedRows
FROM dbo.PerformanceMetrics_Legacy
WHERE IsMigrated = 0;

-- Expected: 0 (all rows marked as migrated)

-- Verify view still returns data (now only from new tables)
SELECT COUNT(*) AS TotalMetrics
FROM dbo.vw_PerformanceMetrics;

-- Should return row count from new PerfSnapshot* tables only
```

**Result**: API now queries ONLY new data (legacy data preserved but hidden).

---

### Step 9: Cleanup (Optional - After 90 Days)

**Status**: NEW MODE ONLY ✅

**When to Run**: After 90 days of successful operation with new schema.

**Actions**:

```sql
-- Preview cleanup (dry run)
EXEC dbo.usp_CleanupLegacyData
    @OlderThanDays = 90,
    @DryRun = 1;

-- Actual cleanup (CAUTION: deletes data)
EXEC dbo.usp_CleanupLegacyData
    @OlderThanDays = 90,
    @DryRun = 0;

-- After cleanup completes, optionally drop legacy table
-- DROP TABLE dbo.PerformanceMetrics_Legacy;  -- CAUTION: permanent deletion
```

---

## Cutover Procedure C: Multi-Server Consolidation

### Phase: Multiple DBATools instances → Single MonitoringDB

**Objective**: Consolidate monitoring data from N single-server DBATools databases into one multi-server MonitoringDB.

### Prerequisites

✅ MonitoringDB database created and Phase 1.9 schema deployed
✅ All source servers registered in MonitoringDB.dbo.Servers
✅ Network connectivity between SQL Servers (for linked servers)
✅ Sufficient disk space on MonitoringDB server
✅ API configured to connect to MonitoringDB

### Timeline: 1-3 Days (depending on number of servers and data volume)

**Strategy**: Phased migration (one server at a time)

---

### Phase 1: Setup MonitoringDB (1 hour)

```sql
-- 1.1: Create MonitoringDB database
CREATE DATABASE MonitoringDB;
GO

-- 1.2: Deploy Phase 1.9 schema
USE MonitoringDB;
GO

-- Run deployment scripts
:r database/20-create-dbatools-tables.sql
:r database/21-create-enhanced-tables.sql
:r database/22-create-mapping-views.sql

-- 1.3: Register all source servers
INSERT INTO dbo.Servers (ServerName, Environment, IsActive)
VALUES
    ('SQL-PROD-01', 'Production', 1),
    ('SQL-PROD-02', 'Production', 1),
    ('SQL-DEV-01', 'Development', 1),
    ('SQL-TEST-01', 'Test', 1);

-- Verify registration
SELECT * FROM dbo.Servers;
```

---

### Phase 2: Migrate Server 1 (2-4 hours per server)

**Repeat for each server**

```bash
# Customize migration script for Server 1
# Edit scripts/migrate-dbatools-to-monitoringdb.sql:
#   @SourceDatabase = 'DBATools'  # On SQL-PROD-01
#   @TargetDatabase = 'MonitoringDB'  # On MonitoringDB server
#   @SourceServerName = 'SQL-PROD-01'
#   @DryRun = 1  # Preview first

# Run dry run
sqlcmd -S MonitoringDB-Server -U sa -P Password -C \
  -i scripts/migrate-dbatools-to-monitoringdb.sql

# Review output, then run actual migration
# (Set @DryRun = 0 in script)
sqlcmd -S MonitoringDB-Server -U sa -P Password -C \
  -i scripts/migrate-dbatools-to-monitoringdb.sql
```

**Validation** (after each server):

```sql
-- Verify data migrated
SELECT
    s.ServerName,
    COUNT(psr.PerfSnapshotRunID) AS SnapshotCount,
    MIN(psr.SnapshotUTC) AS EarliestData,
    MAX(psr.SnapshotUTC) AS LatestData
FROM MonitoringDB.dbo.Servers s
LEFT JOIN MonitoringDB.dbo.PerfSnapshotRun psr ON s.ServerID = psr.ServerID
GROUP BY s.ServerID, s.ServerName
ORDER BY s.ServerName;
```

---

### Phase 3: API Cutover (1 hour)

**After all servers migrated**:

```csharp
// Update API connection string (appsettings.json)
{
  "ConnectionStrings": {
    "MonitoringDB": "Server=MonitoringDB-Server;Database=MonitoringDB;User Id=monitor_api;Password=...;Encrypt=True;TrustServerCertificate=True;Connection Timeout=30"
  }
}
```

**Restart API**, verify:
- GET /api/servers (should return all registered servers)
- GET /api/metrics/{serverId} (should return metrics for specific server)
- GET /health (should show "Healthy" status)

---

### Phase 4: Grafana Dashboard Updates (30 minutes)

**Update Grafana datasource** to point to MonitoringDB:

```yaml
# dashboards/grafana/provisioning/datasources/monitoringdb.yaml
datasources:
  - name: MonitoringDB
    type: mssql
    url: MonitoringDB-Server:1433
    database: MonitoringDB
    user: grafana_readonly
    jsonData:
      encrypt: true
      serverName: MonitoringDB-Server
    secureJsonData:
      password: 'GrafanaPassword'
```

**Restart Grafana**, verify dashboards display multi-server data.

---

## Rollback Procedures

See [ROLLBACK.md](./ROLLBACK.md) for detailed rollback procedures.

**Quick Rollback** (if cutover fails):

```sql
-- Emergency rollback: Restore view to point directly at legacy table
USE [DBATools];
GO

DROP VIEW IF EXISTS dbo.vw_PerformanceMetrics;
GO

CREATE VIEW dbo.vw_PerformanceMetrics AS
SELECT
    MetricID,
    ServerID,
    CollectionTime,
    MetricCategory,
    MetricName,
    MetricValue
FROM dbo.PerformanceMetrics_Legacy;
GO

-- Rename table back to original name
EXEC sp_rename 'dbo.PerformanceMetrics_Legacy', 'PerformanceMetrics';
```

**Result**: API back to original state (< 2 minutes)

---

## Success Criteria

**Cutover is considered successful when**:

✅ **Zero Data Loss**: All legacy metrics accessible through views
✅ **API Compatibility**: 100% backward compatible (no code changes)
✅ **Performance**: All queries meet SLA (< 500ms for 90-day queries)
✅ **Reliability**: 48 hours of stable operation with no errors
✅ **Monitoring**: New data collection working every 5 minutes
✅ **Dashboards**: Grafana displays all historical + new data correctly
✅ **Multi-Server**: (If applicable) All servers reporting to MonitoringDB

---

## Support and Troubleshooting

**Common Issues**:

| Issue | Cause | Solution |
|-------|-------|----------|
| API returns 404 after rename | View not created yet | Run Step 4 immediately |
| View row count < legacy table | UNION missing legacy data | Check IsMigrated filter |
| Performance degraded | Missing indexes | Run benchmark-phase-1.9-views.sql |
| New data not collecting | SQL Agent job not started | Check job schedule |
| ServerID all NULL | Server not registered | Insert into dbo.Servers |

**Escalation Path**:
1. Check SQL Server error log: `EXEC xp_readerrorlog`
2. Review validation test results
3. Examine query execution plans
4. Consult rollback procedures if needed

---

**Document Status**: ✅ COMPLETE
**Last Updated**: 2025-10-28
**Version**: 1.0
