# Grafana Dashboard Data Setup Guide

## 🎯 Purpose

This guide addresses two common issues:
1. **No data showing in dashboards** (multiple databases)
2. **Setting landing page as Grafana home**

---

## Issue 1: No Data for Multiple Databases

### Problem

When you first deploy the system, Grafana dashboards may show:
- ❌ Table Browser: Empty or only showing 1 database
- ❌ Code Browser: No stored procedures listed
- ❌ SQL Server Overview: Missing database metrics

### Root Cause

The metadata collection system requires **initialization**:
- Databases must be registered in `DatabaseMetadataCache` table
- Metadata collection must be triggered (tables, procedures, dependencies)
- This is a **one-time setup** per database

### Solution: Run Initialization Script

**Step 1: Execute initialization script**

```bash
# From WSL or Windows with sqlcmd
sqlcmd -S 172.31.208.1,14333 -U sv -P Gv51076! -C -d MonitoringDB \
  -i database/29-initialize-metadata-collection.sql

# Or from SSMS / Azure Data Studio
# Open: database/29-initialize-metadata-collection.sql
# Execute against MonitoringDB database
```

**What this script does**:
1. ✅ Registers local server (@@SERVERNAME) in `Servers` table
2. ✅ Auto-discovers all user databases (excludes system databases)
3. ✅ Registers databases in `DatabaseMetadataCache` table
4. ✅ Collects metadata for all databases:
   - Table metadata (names, sizes, row counts, indexes)
   - Column metadata (data types, nullable, defaults)
   - Code object metadata (procedures, functions, views)
   - Dependency metadata (what calls what)
5. ✅ Displays verification summary

**Expected Duration**: 1-5 minutes per database (depends on database size)

**Step 2: Verify data collected**

```sql
-- Check databases registered
SELECT * FROM dbo.DatabaseMetadataCache;
-- Should show all your user databases with IsCurrent = 1

-- Check table metadata
SELECT DatabaseName, COUNT(*) AS TableCount
FROM dbo.TableMetadata
GROUP BY DatabaseName;
-- Should show table counts for each database

-- Check code objects
SELECT DatabaseName, ObjectType, COUNT(*) AS ObjectCount
FROM dbo.CodeObjectMetadata
GROUP BY DatabaseName, ObjectType;
-- Should show procedures, functions, views per database
```

**Step 3: Refresh Grafana dashboards**

1. Open Grafana: http://localhost:9002
2. Navigate to Table Browser dashboard
3. Check Database dropdown → Should show all user databases
4. Select a database → Should show tables
5. Navigate to Code Browser → Should show procedures/functions

### Troubleshooting

#### Issue: "No databases registered"

**Check**:
```sql
SELECT * FROM dbo.Servers;
```

**Fix**:
```sql
-- Manually register server
INSERT INTO dbo.Servers (ServerName, InstanceName, ServerType, IsActive, MonitoringEnabled)
VALUES (@@SERVERNAME, 'DEFAULT', 'Production', 1, 1);
```

#### Issue: "Collection failed for some databases"

**Check errors**:
```sql
-- Look for error messages in output
-- Common issues:
-- 1. Database offline: ALTER DATABASE [DBName] SET ONLINE;
-- 2. Permission denied: Grant db_datareader to monitoring user
-- 3. Database locked: Wait for exclusive locks to clear
```

**Fix permissions**:
```sql
-- Grant read access to monitoring user
USE [YourDatabase];
CREATE USER [sv] FOR LOGIN [sv];
ALTER ROLE db_datareader ADD MEMBER [sv];
GRANT VIEW DATABASE STATE TO [sv];
```

#### Issue: "Stored procedure usp_RefreshMetadataCache not found"

**Check**:
```sql
SELECT * FROM INFORMATION_SCHEMA.ROUTINES
WHERE ROUTINE_NAME = 'usp_RefreshMetadataCache';
```

**Fix**: Deploy Phase 1.25 scripts
```bash
# Deploy metadata collection procedures
sqlcmd -S 172.31.208.1,14333 -U sv -P Gv51076! -C -d MonitoringDB \
  -i database/19-create-metadata-collectors.sql

sqlcmd -S 172.31.208.1,14333 -U sv -P Gv51076! -C -d MonitoringDB \
  -i database/20-create-remaining-metadata-collectors.sql

sqlcmd -S 172.31.208.1,14333 -U sv -P Gv51076! -C -d MonitoringDB \
  -i database/21-create-advanced-metadata-collectors.sql
```

### Ongoing Maintenance

**Option 1: Manual refresh** (recommended for development)
```sql
-- Run when schema changes occur
EXEC dbo.usp_RefreshMetadataCache
    @ServerID = 1,
    @ForceRefresh = 1;  -- 1 = refresh all, 0 = only stale databases
```

**Option 2: SQL Agent Job** (recommended for production)
```sql
-- Create daily refresh job
EXEC msdb.dbo.sp_add_job
    @job_name = N'SQL Monitor - Refresh Metadata',
    @description = N'Refresh database metadata cache for Grafana dashboards';

EXEC msdb.dbo.sp_add_jobstep
    @job_name = N'SQL Monitor - Refresh Metadata',
    @step_name = N'Refresh Cache',
    @subsystem = N'TSQL',
    @database_name = N'MonitoringDB',
    @command = N'EXEC dbo.usp_RefreshMetadataCache @ForceRefresh = 1;';

EXEC msdb.dbo.sp_add_schedule
    @schedule_name = N'Daily 2 AM',
    @freq_type = 4,  -- Daily
    @freq_interval = 1,
    @active_start_time = 020000;  -- 2:00 AM

EXEC msdb.dbo.sp_attach_schedule
    @job_name = N'SQL Monitor - Refresh Metadata',
    @schedule_name = N'Daily 2 AM';

EXEC msdb.dbo.sp_add_jobserver
    @job_name = N'SQL Monitor - Refresh Metadata';
```

**Option 3: On-Demand via DDL Trigger** (advanced)
```sql
-- Automatically refresh when schema changes
CREATE TRIGGER trg_SchemaChange_RefreshMetadata
ON ALL SERVER
FOR DDL_DATABASE_LEVEL_EVENTS
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @EventData XML = EVENTDATA();
    DECLARE @DatabaseName NVARCHAR(128) = @EventData.value('(/EVENT_INSTANCE/DatabaseName)[1]', 'NVARCHAR(128)');

    -- Mark database as needing refresh
    UPDATE MonitoringDB.dbo.DatabaseMetadataCache
    SET IsCurrent = 0
    WHERE DatabaseName = @DatabaseName;
END;
GO
```

---

## Issue 2: Setting Landing Page as Grafana Home

### Problem

When you open Grafana, it shows the default Grafana home page instead of the arcTrade branded landing page (00-landing-page.json).

### Solution 1: Set via Grafana UI (Easiest)

**Step 1: Login to Grafana**
- URL: http://localhost:9002
- Username: `admin`
- Password: `Admin123!`

**Step 2: Set Home Dashboard**
1. Click gear icon (⚙️) in left sidebar
2. Click "Preferences"
3. Under "Home Dashboard", select **"SQL Monitor - Home"** from dropdown
4. Click "Save"
5. Click Grafana logo (top left) → Should now show landing page

**Step 3: Make it organization default** (all users)
1. Click gear icon (⚙️) → "Preferences"
2. Select "Organization" tab
3. Under "Home Dashboard", select **"SQL Monitor - Home"**
4. Click "Save organization preferences"

### Solution 2: Set via Environment Variable (Already Done)

**Status**: ✅ Already configured in `docker-compose.yml`

```yaml
environment:
  - GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/var/lib/grafana/dashboards/00-landing-page.json
```

**To apply**:
```bash
# Restart Grafana container
docker compose restart grafana

# Or recreate (if environment variable wasn't there before)
docker compose down
docker compose up -d
```

**Note**: This may not work in all Grafana versions. If it doesn't work, use Solution 1 (UI method).

### Solution 3: Set via API (Programmatic)

```bash
# Get dashboard UID
DASHBOARD_UID="sql-monitor-home"

# Set as home dashboard via API
curl -X PUT "http://localhost:9002/api/user/preferences" \
  -H "Content-Type: application/json" \
  -H "Authorization: Basic $(echo -n 'admin:Admin123!' | base64)" \
  -d "{
    \"homeDashboardUID\": \"$DASHBOARD_UID\"
  }"
```

### Solution 4: Direct URL (Bookmark)

If setting home page doesn't work, create a bookmark:
```
http://localhost:9002/d/sql-monitor-home/sql-monitor-home
```

This always opens the landing page directly.

### Verification

After setting home page:
1. Close all Grafana tabs
2. Open http://localhost:9002
3. Login
4. Should see arcTrade branded landing page with navigation tiles
5. If not, click Grafana logo (top left) → Should show landing page

---

## Quick Setup Checklist

### Initial Setup (One-Time)

- [ ] **Deploy database scripts** (if not already done)
  ```bash
  # Phase 1.25 metadata collection
  sqlcmd -S server -U user -P pass -d MonitoringDB -i database/19-create-metadata-collectors.sql
  sqlcmd -S server -U user -P pass -d MonitoringDB -i database/20-create-remaining-metadata-collectors.sql
  sqlcmd -S server -U user -P pass -d MonitoringDB -i database/21-create-advanced-metadata-collectors.sql
  ```

- [ ] **Initialize metadata collection**
  ```bash
  sqlcmd -S server -U user -P pass -d MonitoringDB -i database/29-initialize-metadata-collection.sql
  ```

- [ ] **Verify data collected**
  ```sql
  SELECT * FROM dbo.DatabaseMetadataCache;  -- Should show all databases
  SELECT COUNT(*) FROM dbo.TableMetadata;   -- Should show >0 tables
  SELECT COUNT(*) FROM dbo.CodeObjectMetadata;  -- Should show >0 procedures
  ```

- [ ] **Set Grafana home page**
  - Open Grafana → Preferences → Home Dashboard → "SQL Monitor - Home"
  - Or use docker-compose.yml environment variable (already added)

- [ ] **Restart Grafana**
  ```bash
  docker compose restart grafana
  ```

- [ ] **Verify dashboards**
  - Open http://localhost:9002
  - Should land on arcTrade branded page
  - Navigate to Table Browser → Should show multiple databases
  - Navigate to Code Browser → Should show procedures/functions

### Ongoing Maintenance

- [ ] **Refresh metadata** when schema changes
  ```sql
  EXEC dbo.usp_RefreshMetadataCache @ForceRefresh = 1;
  ```

- [ ] **Set up SQL Agent job** for automatic daily refresh (optional)

- [ ] **Monitor metadata cache status**
  ```sql
  -- Check for stale databases
  SELECT * FROM dbo.DatabaseMetadataCache WHERE IsCurrent = 0;
  ```

---

## Performance Tips

### Large Databases (>1000 tables)

If metadata collection is slow:

1. **Run during off-hours**: Schedule SQL Agent job for 2 AM
2. **Incremental refresh**: Only refresh changed databases
   ```sql
   EXEC dbo.usp_RefreshMetadataCache @ForceRefresh = 0;  -- Only stale databases
   ```
3. **Filter databases**: Exclude dev/test databases if not needed
   ```sql
   DELETE FROM dbo.DatabaseMetadataCache WHERE DatabaseName LIKE '%_DEV';
   ```

### Many Databases (>50)

1. **Prioritize**: Collect production databases first
2. **Batch processing**: Use cursor in script to process 10 at a time
3. **Monitor progress**: Check LastRefreshTime to track completion

---

## Troubleshooting Common Issues

### "Table Browser shows 'No data'"

**Causes**:
- Metadata not collected (run initialization script)
- Database dropdown filter applied (select different database)
- Grafana query error (check browser console F12)

**Fix**:
```sql
-- Check if metadata exists
SELECT COUNT(*) FROM dbo.TableMetadata;  -- Should be >0

-- If 0, run initialization
:r database/29-initialize-metadata-collection.sql
```

### "Code Browser empty"

**Causes**:
- Database has no procedures/functions (check in SSMS)
- Metadata not collected
- System stored procedures filtered out (correct behavior)

**Fix**:
```sql
-- Check if code objects exist
SELECT DatabaseName, ObjectType, COUNT(*)
FROM dbo.CodeObjectMetadata
GROUP BY DatabaseName, ObjectType;

-- If empty, run initialization
```

### "Grafana still shows default home page"

**Causes**:
- User preference not set
- Organization default not set
- Browser cache

**Fix**:
1. Clear browser cache (Ctrl+Shift+Delete)
2. Set preference via UI (Solution 1 above)
3. Use direct URL bookmark

---

## Summary

**To get data in dashboards**:
1. Run `database/29-initialize-metadata-collection.sql`
2. Wait 1-5 minutes per database
3. Refresh Grafana dashboards

**To set landing page as home**:
1. Grafana UI → Preferences → Home Dashboard → "SQL Monitor - Home"
2. Or restart Grafana (docker-compose.yml already configured)

**Questions?**
- Check logs: `docker logs sql-monitor-grafana`
- Check database: Query `DatabaseMetadataCache` table
- Check permissions: User needs `db_datareader` on all databases

---

**Created**: 2025-10-28
**Status**: Ready for use
**Next**: Execute initialization script and set home page

🤖 Generated with Claude Code (https://claude.com/claude-code)
