# Grafana Dashboard Auto-Refresh - Quick Start

**Created:** 2025-10-30
**Status:** ✅ Ready for deployment

---

## What This Does

**Adds a "Refresh Dashboards" button to Grafana** that pulls the latest dashboards from GitHub without restarting the container!

---

## Deploy in 3 Steps

### Step 1: Rebuild Container (from PowerShell)

```powershell
cd D:\Dev2\sql-monitor

# Login to Azure
az acr login --name sqlmonitoracr

# Build new image
docker build -f Dockerfile.grafana `
  -t sqlmonitoracr.azurecr.io/sql-monitor-grafana:latest .

# Push to Azure
docker push sqlmonitoracr.azurecr.io/sql-monitor-grafana:latest
```

### Step 2: Restart Your Grafana Container

```powershell
az container restart --resource-group YOUR_RG --name YOUR_CONTAINER_NAME
```

### Step 3: Use the Refresh Button

1. **Login to Grafana**
2. **Go to:** http://your-grafana-url:3000/d/admin-dashboard-refresh
3. **Click:** "🔄 Refresh Dashboards from GitHub"
4. **Wait:** 15 seconds (page auto-reloads)
5. **Done!** New dashboards appear in sidebar

---

## What's New

### New Dashboards (2)
1. **AWS RDS Performance Insights** - RDS-style monitoring dashboard
2. **Admin - Dashboard Refresh** - Dashboard refresh control panel

### New Features
- ✅ Webhook server on port 8888
- ✅ Auto-refresh script
- ✅ One-click dashboard updates
- ✅ No container restart needed!

### Dashboard Count
**Before:** 13 dashboards
**After:** 15 dashboards

---

## How Auto-Refresh Works

```
User clicks button → HTTP POST to localhost:8888 → Webhook triggers refresh script
                                                    ↓
                                    Downloads latest dashboards from GitHub
                                                    ↓
                                    Compares with existing files (smart diff)
                                                    ↓
                                    Updates only changed/new dashboards
                                                    ↓
                                    Grafana auto-reloads (15 seconds)
```

---

## Future Dashboard Updates (No Rebuild Needed!)

1. **Create** new dashboard JSON locally
2. **Copy** to `public/dashboards/`
3. **Update** dashboard list in `public/grafana-entrypoint.sh`
4. **Commit** and **push** to GitHub
5. **Click** refresh button in Grafana

**That's it! No container rebuild or restart required!**

---

## Troubleshooting

**Button doesn't work?**
```bash
# Check webhook server running
az container exec --resource-group RG --name NAME \
  --exec-command "ps aux | grep webhook"
```

**New dashboard not appearing?**
```bash
# Hard refresh browser
Ctrl + Shift + R (Windows)
Cmd + Shift + R (Mac)
```

**Want to see what happened?**
```bash
# Check refresh logs
az container exec --resource-group RG --name NAME \
  --exec-command "cat /var/log/dashboard-refresh.log"
```

---

## Documentation

**Complete Guide:** [docs/deployment/DASHBOARD-AUTO-REFRESH-SETUP.md](docs/deployment/DASHBOARD-AUTO-REFRESH-SETUP.md)

**AWS RDS Dashboard:** [docs/guides/AWS-RDS-PERFORMANCE-INSIGHTS-DASHBOARD.md](docs/guides/AWS-RDS-PERFORMANCE-INSIGHTS-DASHBOARD.md)

**Summary:** [AWS-RDS-DASHBOARD-SUMMARY.md](AWS-RDS-DASHBOARD-SUMMARY.md)

---

## Benefits

✅ **Zero Downtime** - No container restart for dashboard updates
✅ **Self-Service** - Refresh from Grafana UI, no command line
✅ **Smart Updates** - Only downloads changed files
✅ **Fast** - 5-10 seconds to refresh all dashboards
✅ **Safe** - Read-only, localhost-only webhook
✅ **Auditable** - Complete logs in /var/log/

---

**Ready to deploy!** 🚀
