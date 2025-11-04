# T-SQL Code Editor Plugin - Deployment Guide

**Date**: November 3, 2025
**Target**: Azure Grafana Container (schoolvision-sqlmonitor)
**Status**: Ready for deployment

---

## 📋 Pre-Deployment Checklist

### 1. Verify Plugin Build

```bash
# Navigate to plugin directory
cd /mnt/d/Dev2/sql-monitor/grafana-plugins/sqlmonitor-codeeditor-app

# Check if dist/ exists
ls -lh dist/

# Verify key files exist:
# - module.js (~6.3 MB)
# - plugin.json
# - 86 chunk files
```

**Expected Output**:
```
-rw-r--r-- 1 user user 6.3M Nov  3 00:28 module.js
-rw-r--r-- 1 user user 1.9K Nov  4 01:33 plugin.json
... (86 additional chunk files)
```

### 2. Verify Azure CLI Access

```powershell
# Check Azure subscription
az account show

# Expected subscription: Test Environment (7b2beff3-b38a-4516-a75f-3216725cc4e9)
```

### 3. Verify API Backend is Running

The plugin requires the ASP.NET Core API to be running:
- **Required Endpoints**:
  - `GET /api/code/servers` - List monitored servers
  - `GET /api/code/databases/{serverId}` - List databases
  - `POST /api/code/execute` - Execute T-SQL queries
  - `GET /api/code/objects` - Schema object browser

**Test API** (if not already deployed):
```bash
cd /mnt/d/Dev2/sql-monitor/api
dotnet run
# Should start on http://localhost:9000
```

---

## 🚀 Deployment Steps

### Step 1: Build Plugin (if not already built)

```bash
cd /mnt/d/Dev2/sql-monitor/grafana-plugins/sqlmonitor-codeeditor-app
npm run build
```

**Build Time**: ~74 seconds
**Output**: `dist/` directory with module.js and chunks

### Step 2: Deploy to Azure

```powershell
# Navigate to project root
cd D:\Dev2\sql-monitor

# Run deployment script
.\Deploy-Grafana-Update-ACR.ps1
```

**Deployment Process**:
1. ✅ Verifies Azure subscription
2. ✅ Verifies plugin build exists (dist/module.js, dist/plugin.json)
3. ✅ Builds Docker image in Azure Container Registry (3-5 minutes)
   - Includes plugin from `grafana-plugins/sqlmonitor-codeeditor-app/dist/`
   - Sets `GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=sqlmonitor-codeeditor-app`
4. ✅ Restarts Azure Container Instance
5. ✅ Verifies deployment (logs, plugin loading, dashboards)

**Estimated Total Time**: 5-7 minutes

---

## 🔍 Verification Steps

### Step 1: Check Deployment Script Output

Look for these success indicators:

```
Step 1.5: Verifying plugin build...
  Plugin build verified!
  Location: D:\Dev2\sql-monitor\grafana-plugins\sqlmonitor-codeeditor-app\dist
  module.js: 6.3 MB

Step 2: Building Docker image...
  Build successful!
  - Dashboards provisioned from GitHub
  - T-SQL Code Editor plugin included

Step 5: Checking container logs...
  Dashboard download: SUCCESS!
  T-SQL Code Editor plugin: LOADED!
```

### Step 2: Access Grafana UI

**URL**: http://schoolvision-sqlmonitor.eastus.azurecontainer.io:3000

**Login**:
- Username: `admin`
- Password: `NewSecurePassword123`

### Step 3: Verify Plugin Appears in Apps

1. Click **"Apps"** in left sidebar (or **"⚙️ Configuration" → "Plugins"**)
2. Look for **"SQL Monitor Code Editor"**
3. Click to open plugin page
4. Click **"Enable"** if not already enabled

**Expected Plugin Info**:
- **Name**: SQL Monitor Code Editor
- **Type**: App Plugin
- **Version**: 1.0.0
- **Author**: SQL Monitor Team

### Step 4: Open Plugin

**Direct URL**: http://schoolvision-sqlmonitor.eastus.azurecontainer.io:3000/a/sqlmonitor-codeeditor-app

**Or navigate**: Apps → SQL Monitor Code Editor → Code Editor

**Expected UI Elements**:
- Toolbar with Run, Save, Format buttons
- Server selection dropdown
- Database selection dropdown
- Monaco editor panel
- Results grid panel
- Tab bar for multiple scripts

### Step 5: Test Query Execution

1. **Select Server**: Choose a monitored server from dropdown
2. **Select Database**: Choose a database
3. **Write Query**:
   ```sql
   SELECT TOP 10 * FROM sys.tables
   ```
4. **Click Run** (or press Ctrl+Enter)
5. **Verify Results**:
   - Results appear in ag-Grid
   - Execution time shown
   - Row count shown
   - No errors displayed

### Step 6: Test Analysis Engine

1. Write a query with issues:
   ```sql
   SELECT * FROM Users
   WHERE UserID = 123
   ```
2. Analysis should automatically run
3. Check for analysis results (if analysis panel is visible):
   - Warning: "Avoid SELECT * - specify column names explicitly" (P001)

### Step 7: Test Export Functionality

1. After running a query with results
2. Click **"Export"** buttons in toolbar
3. Test:
   - ✅ **CSV** - Downloads CSV file
   - ✅ **JSON** - Downloads JSON file
   - ✅ **Copy** - Copies to clipboard

---

## 🐛 Troubleshooting

### Issue 1: Plugin Not Visible in Apps

**Symptoms**: Plugin doesn't appear in Apps menu

**Causes**:
1. Plugin not copied to container
2. Plugin build incomplete
3. Grafana hasn't loaded unsigned plugins

**Solutions**:

```powershell
# Check container logs for plugin errors
az container logs --resource-group rg-sqlmonitor-schoolvision --name grafana-schoolvision --tail 200 | Select-String "sqlmonitor"

# Look for:
# - "Registered plugin: sqlmonitor-codeeditor-app"
# - "Plugin loaded: sqlmonitor-codeeditor-app"
# - Or errors like "Failed to load plugin"
```

**If plugin not found**:
1. Verify Dockerfile.grafana has COPY command:
   ```dockerfile
   COPY grafana-plugins/sqlmonitor-codeeditor-app/dist /var/lib/grafana/plugins/sqlmonitor-codeeditor-app
   ```
2. Rebuild and redeploy:
   ```powershell
   .\Deploy-Grafana-Update-ACR.ps1
   ```

### Issue 2: "Failed to Load Plugin" Error

**Symptoms**: Error message in Grafana UI about unsigned plugin

**Cause**: `GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS` not set

**Solution**: Verify Dockerfile.grafana has:
```dockerfile
ENV GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=sqlmonitor-codeeditor-app
```

### Issue 3: Query Execution Fails

**Symptoms**: "Failed to execute query" error

**Causes**:
1. API backend not running
2. API CORS not allowing Grafana origin
3. Server/database not found

**Solutions**:

```bash
# Test API directly
curl http://localhost:9000/api/code/servers

# Should return list of servers
```

**Check API is running**:
```powershell
# If API container exists
az container show --resource-group rg-sqlmonitor-schoolvision --name sql-monitor-api

# If not, API needs to be deployed separately
```

**Expected API Configuration**:
- Port: 9000
- CORS: Allow Grafana origin (http://schoolvision-sqlmonitor.eastus.azurecontainer.io:3000)

### Issue 4: Server Dropdown Empty

**Symptoms**: No servers appear in dropdown

**Cause**: No servers registered in MonitoringDB

**Solution**: Register servers via SQL:
```sql
USE MonitoringDB;
GO

EXEC dbo.usp_AddServer
    @ServerName = 'sqltest.schoolvision.net',
    @Environment = 'Test',
    @IsActive = 1;
```

### Issue 5: Results Not Displaying

**Symptoms**: Query executes but no results shown

**Causes**:
1. ag-Grid not loading
2. JavaScript error in browser console
3. Query returned no rows

**Solutions**:

1. **Open Browser DevTools** (F12)
2. **Check Console** for errors:
   - Look for ag-Grid errors
   - Look for Monaco Editor errors
   - Look for API fetch errors

3. **Check Network Tab**:
   - Verify POST to /api/code/execute returns 200
   - Check response body for results

4. **Verify Query Returns Data**:
   ```sql
   -- Test query that always returns data
   SELECT 1 AS TestColumn
   ```

---

## 📊 Post-Deployment Validation

### Checklist

- [ ] Plugin appears in Grafana Apps menu
- [ ] Plugin can be opened at `/a/sqlmonitor-codeeditor-app`
- [ ] Server dropdown loads monitored servers
- [ ] Database dropdown loads databases for selected server
- [ ] Monaco editor displays and accepts input
- [ ] Queries execute successfully
- [ ] Results display in ag-Grid
- [ ] Export to CSV works
- [ ] Export to JSON works
- [ ] Copy to clipboard works
- [ ] Analysis engine runs automatically
- [ ] Analysis results display (if panel visible)
- [ ] Tab management works (open/close/switch)
- [ ] Auto-save works (localStorage)
- [ ] Keyboard shortcuts work (Ctrl+Enter to run)

### Performance Checks

- [ ] Plugin loads in <3 seconds
- [ ] Analysis completes in <2 seconds for typical queries
- [ ] Query execution completes in <5 seconds (for simple queries)
- [ ] Results grid renders smoothly with 100+ rows
- [ ] No console errors or warnings

---

## 🔄 Rollback Plan

If deployment fails or plugin causes issues:

### Option 1: Disable Plugin Only

1. Login to Grafana as admin
2. Go to **Configuration → Plugins**
3. Find **SQL Monitor Code Editor**
4. Click **"Disable"**
5. Plugin will be inactive but container still running

### Option 2: Redeploy Without Plugin

1. Revert Dockerfile.grafana changes:
   ```bash
   git revert 3b8d449  # Revert plugin deployment commit
   ```

2. Redeploy:
   ```powershell
   .\Deploy-Grafana-Update-ACR.ps1
   ```

3. Container will restart without plugin

### Option 3: Full Rollback

```powershell
# Use previous image tag
az container update `
    --resource-group rg-sqlmonitor-schoolvision `
    --name grafana-schoolvision `
    --image sqlmonitoracr.azurecr.io/sql-monitor-grafana:previous

# Or restart with last known good image
```

---

## 📝 Monitoring

### Container Logs

```powershell
# View last 200 lines
az container logs --resource-group rg-sqlmonitor-schoolvision --name grafana-schoolvision --tail 200

# Follow logs in real-time
az container logs --resource-group rg-sqlmonitor-schoolvision --name grafana-schoolvision --follow
```

### Key Log Indicators

**Success**:
```
Registered plugin: sqlmonitor-codeeditor-app
Plugin loaded: sqlmonitor-codeeditor-app
```

**Errors**:
```
Failed to load plugin: sqlmonitor-codeeditor-app
Error loading unsigned plugin (not in allow list)
```

### Grafana UI Logs

1. Open browser DevTools (F12)
2. Go to **Console** tab
3. Look for:
   - `[AnalysisEngine] Registered 41 rules`
   - `[CodeEditor] Loaded servers: N`
   - Errors starting with `[CodeEditor]` or `[SqlMonitorApiClient]`

---

## 🎯 Success Criteria

Deployment is successful when:

1. ✅ Plugin appears in Grafana Apps
2. ✅ Plugin can be accessed at `/a/sqlmonitor-codeeditor-app`
3. ✅ Query execution works end-to-end
4. ✅ Results display correctly
5. ✅ Export functionality works
6. ✅ No errors in container logs
7. ✅ No errors in browser console
8. ✅ Performance is acceptable (<3s load, <2s analysis)

---

## 📚 Additional Resources

- **Plugin Source**: `/mnt/d/Dev2/sql-monitor/grafana-plugins/sqlmonitor-codeeditor-app/`
- **API Source**: `/mnt/d/Dev2/sql-monitor/api/`
- **Feature Status**: `/mnt/d/Dev2/sql-monitor/FEATURE-7-ACTUAL-STATUS.md`
- **Session Summary**: `/mnt/d/Dev2/sql-monitor/SESSION-SUMMARY-2025-11-03.md`

---

**Last Updated**: November 3, 2025 17:00 UTC
**Status**: Ready for deployment
**Estimated Deployment Time**: 5-7 minutes
**Risk Level**: LOW (plugin is read-only, no database changes)
