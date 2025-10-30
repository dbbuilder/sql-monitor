# AWS RDS Performance Insights Dashboard - Summary

**Created:** 2025-10-30
**Status:** ✅ Ready for deployment
**Dashboard Count:** 14 (was 13)

---

## Quick Summary

✅ **Created AWS RDS Performance Insights-style dashboard for SQL Server**
✅ **16 panels across 3 sections** (Counter Metrics, Database Load, Top Dimensions)
✅ **Pushed to GitHub** - changes committed and available
✅ **Deployment ready** - restart container to load new dashboard

---

## What You Need to Do

### Step 1: Restart Grafana Container

**From PowerShell on Windows:**

```powershell
az container restart --resource-group rg-sqlmonitor-prod `
    --name ca-sqlmonitor-grafana-prod
```

Wait 30 seconds, then verify:

```powershell
az container logs --resource-group rg-sqlmonitor-prod `
    --name ca-sqlmonitor-grafana-prod `
    --tail 50
```

**Look for:** `Downloaded: 14 dashboards` (was 13)

### Step 2: Access Dashboard

**URL:** http://schoolvision-sqlmonitor.eastus.azurecontainer.io:3000/d/aws-rds-performance-insights

**Login:**
- Username: `admin`
- Password: `NewSecurePassword123`

### Step 3: Collect Metrics (if panels show "No data")

**Connect to SQL Server:**
- Server: `sqltest.schoolvision.net,14333`
- Database: `MonitoringDB`
- User: `sv`
- Password: `Gv51076!`

**Run:**
```sql
EXEC dbo.usp_CollectAllRDSMetrics @ServerID = 1;
```

**Then refresh the dashboard in Grafana.**

---

## Dashboard Features

### 10 Counter Metrics
1. CPU Utilization (%)
2. Memory Utilization (%)
3. Database Connections (stacked)
4. Read/Write IOPS
5. Read/Write Throughput (MB/s)
6. Disk Latency (ms)
7. Buffer Cache Hit Ratio (gauge)
8. Page Life Expectancy (gauge)
9. Batch Requests/sec
10. Transactions/sec

### Database Load Chart
- Active sessions stacked by wait type
- Max vCPU line (capacity indicator)
- 12 key wait types tracked

### Top Dimensions Tables
1. Top SQL (by total duration)
2. Top Waits (by total wait time)
3. Top Hosts (by connection count)
4. Top Users (by connection count)
5. Top Databases (by connection count)

---

## Files Created

| File | Purpose | Location |
|------|---------|----------|
| 08-aws-rds-performance-insights.json | Dashboard definition | dashboards/grafana/dashboards/ |
| AWS-RDS-PERFORMANCE-INSIGHTS-DASHBOARD.md | Complete documentation | docs/guides/ |
| DEPLOY-AWS-RDS-DASHBOARD.md | Deployment guide | Root directory |
| grafana-entrypoint.sh | Updated with new dashboard | public/ |

---

## Git Commits

```
52fb306 - Add deployment guide for AWS RDS Performance Insights dashboard
ec504f5 - Update Grafana entrypoint to include AWS RDS Performance Insights dashboard
80c47f9 - Add AWS RDS Performance Insights dashboard for SQL Server
```

---

## Troubleshooting

**Dashboard not found?**
→ Wait 2-5 minutes for GitHub CDN, then restart container again

**Panels show "No data"?**
→ Run `EXEC dbo.usp_CollectAllRDSMetrics @ServerID = 1`

**Container restart failed?**
→ See DEPLOY-AWS-RDS-DASHBOARD.md for rollback plan

---

## Documentation

- **User Guide:** docs/guides/AWS-RDS-PERFORMANCE-INSIGHTS-DASHBOARD.md
- **Deployment Guide:** DEPLOY-AWS-RDS-DASHBOARD.md
- **RDS Setup Guide:** docs/guides/RDS-EQUIVALENT-SETUP.md

---

**Estimated Deployment Time:** 5 minutes
**Downtime:** 30 seconds (container restart)
**Risk:** Low (read-only dashboard, no schema changes)
