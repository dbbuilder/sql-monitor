# Deploy AWS RDS Performance Insights Dashboard to Azure

**Status:** Ready for deployment
**Date:** 2025-10-30
**Dashboard:** 08-aws-rds-performance-insights.json

---

## What Changed

✅ Created new AWS RDS Performance Insights dashboard (14th dashboard)
✅ Updated Grafana entrypoint to download new dashboard from GitHub
✅ Pushed changes to GitHub repository
✅ Dashboard now available at: https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/public/dashboards/08-aws-rds-performance-insights.json

---

## Deployment Steps

### Option 1: Restart Existing Container (Fastest)

The entrypoint script downloads dashboards from GitHub on startup. Simply restart the container:

```powershell
# From PowerShell (Windows)
az container restart --resource-group rg-sqlmonitor-prod `
    --name ca-sqlmonitor-grafana-prod

# Wait 30 seconds for restart
Start-Sleep -Seconds 30

# Verify dashboard loaded
az container logs --resource-group rg-sqlmonitor-prod `
    --name ca-sqlmonitor-grafana-prod `
    --tail 50
```

**Look for:**
```
Downloading 08-aws-rds-performance-insights.json...
  ✓ Success
Downloaded: 14 dashboards
```

### Option 2: Rebuild and Redeploy (If restart doesn't work)

If the container doesn't download the new dashboard, rebuild and push the image:

```powershell
# Navigate to project directory
cd D:\Dev2\sql-monitor

# Login to Azure Container Registry
az acr login --name sqlmonitoracr

# Build new Grafana image
docker build -f Dockerfile.grafana -t sqlmonitoracr.azurecr.io/sql-monitor-grafana:latest .

# Push to ACR
docker push sqlmonitoracr.azurecr.io/sql-monitor-grafana:latest

# Restart container to pull new image
az container restart --resource-group rg-sqlmonitor-prod `
    --name ca-sqlmonitor-grafana-prod
```

---

## Verification

### 1. Check Container Logs

```powershell
az container logs --resource-group rg-sqlmonitor-prod `
    --name ca-sqlmonitor-grafana-prod `
    --tail 100
```

**Expected output:**
```
Step 4: Downloading dashboard JSON files...
  Downloading 00-dashboard-browser.json...
    ✓ Success
  ...
  Downloading 08-aws-rds-performance-insights.json...
    ✓ Success
  ...
  Downloaded: 14 dashboards
  Failed: 0 dashboards
```

### 2. Access Dashboard

**Direct URL:**
```
http://schoolvision-sqlmonitor.eastus.azurecontainer.io:3000/d/aws-rds-performance-insights
```

**Login:**
- Username: `admin`
- Password: `NewSecurePassword123`

**Expected:**
- Dashboard loads successfully
- 16 panels visible (3 sections)
- Server dropdown appears in top-left
- No "Dashboard not found" error

### 3. Test Queries

The dashboard requires collected metrics. If panels show "No data":

```sql
-- Connect to MonitoringDB on sqltest.schoolvision.net,14333
USE MonitoringDB;

-- Collect RDS metrics for Server ID 1
EXEC dbo.usp_CollectAllRDSMetrics @ServerID = 1;

-- Verify data collected
SELECT
    MetricCategory,
    MetricName,
    COUNT(*) AS DataPoints,
    MAX(CollectionTime) AS LastCollection
FROM dbo.PerformanceMetrics
WHERE ServerID = 1
GROUP BY MetricCategory, MetricName
ORDER BY MetricCategory, MetricName;
```

**Expected categories:**
- CPU (3-5 metrics)
- Memory (3-5 metrics)
- DiskIO (6-8 metrics)
- Connections (3 metrics)
- WaitStats (10+ metrics)
- QueryPerformance (varies)

---

## Troubleshooting

### Issue: Dashboard Still Not Found After Restart

**Cause:** Container didn't re-download dashboards (cached).

**Fix:** Force rebuild without cache:
```powershell
docker build --no-cache -f Dockerfile.grafana `
    -t sqlmonitoracr.azurecr.io/sql-monitor-grafana:latest .
docker push sqlmonitoracr.azurecr.io/sql-monitor-grafana:latest
az container restart --resource-group rg-sqlmonitor-prod `
    --name ca-sqlmonitor-grafana-prod
```

### Issue: Download Failed for 08-aws-rds-performance-insights.json

**Cause:** File not yet available on GitHub (CDN delay).

**Fix:** Verify file accessible:
```powershell
curl https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/public/dashboards/08-aws-rds-performance-insights.json
```

If 404, wait 2-5 minutes for GitHub CDN to update.

### Issue: Panels Show "No data"

**Cause:** Metrics not collected yet.

**Fix:** Run collection manually:
```sql
USE MonitoringDB;
EXEC dbo.usp_CollectAllRDSMetrics @ServerID = 1;
```

Then create SQL Agent job for automated collection every 5 minutes (see AWS-RDS-PERFORMANCE-INSIGHTS-DASHBOARD.md).

### Issue: "Query timeout" errors in panels

**Cause:** PerformanceMetrics table too large or missing indexes.

**Fix:** Verify indexes exist:
```sql
SELECT
    i.name AS IndexName,
    OBJECT_NAME(i.object_id) AS TableName,
    i.type_desc
FROM sys.indexes i
WHERE OBJECT_NAME(i.object_id) = 'PerformanceMetrics'
ORDER BY i.index_id;
```

Expected indexes:
- Clustered columnstore (for compression)
- Nonclustered on (ServerID, MetricCategory, CollectionTime)

---

## Post-Deployment Checklist

- [ ] Container restarted successfully
- [ ] Container logs show "Downloaded: 14 dashboards"
- [ ] Dashboard accessible at /d/aws-rds-performance-insights
- [ ] All 16 panels render (no errors)
- [ ] Server dropdown shows active servers
- [ ] Time range picker functional
- [ ] Auto-refresh working (30s interval)
- [ ] Data visible in Counter Metrics section
- [ ] Database Load chart shows wait types
- [ ] Top Dimensions tables populated

---

## Rollback Plan

If deployment fails, revert to previous image:

```powershell
# Find previous image digest
az acr repository show-tags --name sqlmonitoracr `
    --repository sql-monitor-grafana `
    --orderby time_desc `
    --output table

# Tag previous version as latest
az acr import --name sqlmonitoracr `
    --source sqlmonitoracr.azurecr.io/sql-monitor-grafana:PREVIOUS_TAG `
    --image sql-monitor-grafana:latest

# Restart container
az container restart --resource-group rg-sqlmonitor-prod `
    --name ca-sqlmonitor-grafana-prod
```

---

## Success Criteria

✅ Dashboard count increased from 13 to 14
✅ AWS RDS Performance Insights dashboard accessible
✅ All 16 panels render correctly
✅ No errors in container logs
✅ Data collection working
✅ Auto-refresh functional

---

## Next Steps (Optional)

1. **Set as Default Dashboard** for new users:
```bash
az container exec --resource-group rg-sqlmonitor-prod \
    --name ca-sqlmonitor-grafana-prod \
    --exec-command "grafana-cli admin update-default-dashboard aws-rds-performance-insights"
```

2. **Create Dashboard Folder** for organization:
- Login to Grafana UI
- Create folder: "Performance Insights"
- Move dashboard to folder

3. **Setup Alerts** on critical metrics:
- CPU > 90%
- Memory > 95%
- Disk Latency > 25ms
- Buffer Cache Hit Ratio < 90%

---

**Deployment Time:** ~5 minutes (restart) or ~15 minutes (rebuild)
**Downtime:** ~30 seconds (container restart)
**Risk:** Low (read-only dashboard, no schema changes)
