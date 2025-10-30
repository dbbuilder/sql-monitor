# Update Azure Grafana Container

**Container:** grafana-schoolvision
**Resource Group:** rg-sqlmonitor-schoolvision
**Subscription:** Test Environment

---

## Quick Update (One Command)

**Open PowerShell on Windows and run:**

```powershell
cd D:\Dev2\sql-monitor
.\Deploy-Grafana-Update.ps1
```

**This will:**
1. ✅ Set correct Azure subscription
2. ✅ Login to Azure Container Registry
3. ✅ Build new Docker image with auto-refresh system
4. ✅ Push to Azure Container Registry
5. ✅ Restart container
6. ✅ Verify deployment

**Time:** ~5-10 minutes
**Downtime:** ~30 seconds

---

## Access After Update

### Grafana URL
```
http://schoolvision-sqlmonitor.eastus.azurecontainer.io:3000
```

### Login
- **Username:** admin
- **Password:** NewSecurePassword123

### New Dashboards
1. **AWS RDS Performance Insights**
   - http://schoolvision-sqlmonitor.eastus.azurecontainer.io:3000/d/aws-rds-performance-insights

2. **Admin - Dashboard Refresh**
   - http://schoolvision-sqlmonitor.eastus.azurecontainer.io:3000/d/admin-dashboard-refresh

---

## What's New

### Dashboard Count
**Before:** 13 dashboards
**After:** 15 dashboards

### New Features
✅ **Auto-Refresh System** - Click button to update dashboards from GitHub
✅ **AWS RDS Performance Insights** - 16 panels matching AWS RDS monitoring
✅ **Webhook Server** - HTTP endpoint for dashboard refresh (localhost:8888)
✅ **Zero Downtime Updates** - Add dashboards without container restart

---

## Manual Steps (If Script Fails)

### Step 1: Build Image
```powershell
cd D:\Dev2\sql-monitor
az acr login --name sqlmonitoracr
docker build -f Dockerfile.grafana -t sqlmonitoracr.azurecr.io/sql-monitor-grafana:latest .
```

### Step 2: Push to Registry
```powershell
docker push sqlmonitoracr.azurecr.io/sql-monitor-grafana:latest
```

### Step 3: Restart Container
```powershell
az account set --subscription "Test Environment"
az container restart --resource-group rg-sqlmonitor-schoolvision --name grafana-schoolvision
```

### Step 4: Verify Logs
```powershell
az container logs --resource-group rg-sqlmonitor-schoolvision --name grafana-schoolvision --tail 100
```

**Look for:**
- "Downloaded: 15 dashboards"
- "Webhook server started on port 8888"

---

## Verify Deployment

### Check Container Status
```powershell
az container show `
  --resource-group rg-sqlmonitor-schoolvision `
  --name grafana-schoolvision `
  --query "{state: instanceView.state, fqdn: ipAddress.fqdn}" `
  -o json
```

**Expected:**
```json
{
  "fqdn": "schoolvision-sqlmonitor.eastus.azurecontainer.io",
  "state": "Running"
}
```

### Check Logs
```powershell
az container logs `
  --resource-group rg-sqlmonitor-schoolvision `
  --name grafana-schoolvision `
  --tail 50 | Select-String "dashboard"
```

**Expected Output:**
```
Downloading 08-aws-rds-performance-insights.json...
  ✓ Success
Downloading 99-admin-dashboard-refresh.json...
  ✓ Success
Downloaded: 15 dashboards
Failed: 0 dashboards
```

---

## Using the Refresh Button

After deployment, you can add future dashboards without rebuilding:

### Step 1: Access Admin Dashboard
```
http://schoolvision-sqlmonitor.eastus.azurecontainer.io:3000/d/admin-dashboard-refresh
```

### Step 2: Click Refresh Button
Click "🔄 Refresh Dashboards from GitHub"

### Step 3: Wait 15 Seconds
Page will auto-reload

### Step 4: Verify
New dashboards appear in sidebar!

---

## Troubleshooting

### Error: "Docker command not found"
**Solution:** Install Docker Desktop for Windows
- https://docs.docker.com/desktop/install/windows-install/

### Error: "az: command not found"
**Solution:** Install Azure CLI
- https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows

### Error: "Access denied" to ACR
**Solution:** Login again
```powershell
az acr login --name sqlmonitoracr
```

### Error: Container won't restart
**Solution:** Check container events
```powershell
az container show `
  --resource-group rg-sqlmonitor-schoolvision `
  --name grafana-schoolvision `
  --query "containers[0].instanceView.events"
```

### Dashboard still not appearing
**Solution:** Hard refresh browser
- Windows: Ctrl + Shift + R
- Mac: Cmd + Shift + R

Or manually import:
1. Download JSON: https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/dashboards/grafana/dashboards/08-aws-rds-performance-insights.json
2. Grafana → Import → Upload JSON file
3. Select MonitoringDB datasource
4. Click Import

---

## Rollback (If Needed)

If something goes wrong, revert to previous image:

```powershell
# List previous images
az acr repository show-tags `
  --name sqlmonitoracr `
  --repository sql-monitor-grafana `
  --orderby time_desc `
  --output table

# Tag previous version as latest (replace DIGEST)
az acr import `
  --name sqlmonitoracr `
  --source sqlmonitoracr.azurecr.io/sql-monitor-grafana@sha256:PREVIOUS_DIGEST `
  --image sql-monitor-grafana:latest

# Restart container
az container restart `
  --resource-group rg-sqlmonitor-schoolvision `
  --name grafana-schoolvision
```

---

**Ready to deploy!** 🚀

Run: `.\Deploy-Grafana-Update.ps1` from PowerShell
