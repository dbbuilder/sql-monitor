# Automated Data Refresh Guide

## Overview

The SQL Server Monitor has **two-tier automatic data refresh**:

1. **Background Collection** (SQL Agent Job) - Every 5 minutes
2. **On-Demand Refresh** (Grafana Dashboard) - Every 30 seconds when viewing dashboards

---

## Tier 1: Background Collection (Every 5 Minutes)

### SQL Agent Job

**Job Name**: `SQL Monitor - Complete Collection`
**Schedule**: Every 5 minutes, 24/7
**What it does**: Collects server-level + drill-down metrics (fast, ~270ms)

**Verification**:
```sql
-- Check if job exists and is enabled
SELECT name, enabled
FROM msdb.dbo.sysjobs
WHERE name = 'SQL Monitor - Complete Collection';

-- View recent job executions
SELECT TOP 10
    j.name AS JobName,
    jh.run_date,
    jh.run_time,
    CASE jh.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Canceled'
        WHEN 4 THEN 'In Progress'
    END AS Status,
    jh.run_duration
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobhistory jh ON j.job_id = jh.job_id
WHERE j.name = 'SQL Monitor - Complete Collection'
ORDER BY jh.instance_id DESC;
```

**Manual Trigger**:
```sql
-- Start job now (doesn't wait for next scheduled time)
EXEC msdb.dbo.sp_start_job @job_name = N'SQL Monitor - Complete Collection';
```

---

## Tier 2: On-Demand Refresh (Grafana Dashboard)

### Grafana Auto-Refresh Configuration

**Current Setting**: Dashboard refreshes every 30 seconds when being viewed
**Location**: Top-right corner of dashboard → Time picker → Refresh dropdown

**How It Works**:
1. Dashboard panel queries run every 30 seconds
2. Grafana fetches latest data from MonitoringDB
3. If SQL Agent job ran in last 30 seconds, new data appears
4. Otherwise, shows most recent collection (up to 5 minutes old)

**To Change Refresh Rate**:
1. Open dashboard: http://localhost:3000/d/performance-analysis
2. Click time picker (top-right corner)
3. Find "Refresh" dropdown
4. Select new interval:
   - Off (manual refresh only)
   - 5s, 10s, **30s** (current), 1m, 5m, 15m, 30m, 1h

---

## Tier 2.5: Optional - Manual Trigger via API

### On-Demand Collection API Endpoint

If you want fresher data than the 5-minute SQL Agent schedule, trigger collection via API.

**Endpoint**: `POST /api/metrics/collect`

**Usage**:
```bash
# Fast collection (server + drill-down, ~4 seconds)
curl -X POST "http://localhost:5000/api/metrics/collect?serverId=1&includeAdvanced=false"

# Full collection (includes index analysis, ~225 seconds)
curl -X POST "http://localhost:5000/api/metrics/collect?serverId=1&includeAdvanced=true"
```

**Response**:
```json
{
  "success": true,
  "serverId": 1,
  "includeAdvanced": false,
  "durationMs": 4307.77,
  "collectedAt": "2025-10-26T06:42:11Z",
  "message": "Fast metrics collection (server + drill-down) completed successfully"
}
```

---

## Integration: Grafana + API On-Demand Collection

### Option A: Manual Button in Dashboard

**Not yet implemented** - Would require custom Grafana plugin or JavaScript

**Future Enhancement**:
- Add a "Refresh Now" button to dashboard
- Button calls `POST /api/metrics/collect`
- Dashboard automatically refreshes after collection completes

---

### Option B: Curl Command (Current Workaround)

**Workflow**:
1. Open dashboard in browser
2. Open terminal
3. Run: `curl -X POST "http://localhost:5000/api/metrics/collect?serverId=1"`
4. Wait ~4 seconds
5. Dashboard automatically shows new data on next 30-second refresh

---

## Data Freshness Summary

| Scenario | Data Freshness | How It Works |
|----------|----------------|--------------|
| **Passive Viewing** | 0-5 minutes old | SQL Agent job runs every 5 minutes, Grafana refreshes every 30s |
| **Active Monitoring** | 0-30 seconds old | SQL Agent job + Grafana auto-refresh |
| **On-Demand Trigger** | 0-4 seconds old | Call API `/metrics/collect`, then Grafana refreshes in 30s |

---

## Troubleshooting

### Issue: Dashboard shows "No data" or old data

**Check 1**: Verify SQL Agent job is running
```sql
SELECT name, enabled
FROM msdb.dbo.sysjobs
WHERE name = 'SQL Monitor - Complete Collection';
```

**Check 2**: Verify recent collections occurred
```sql
SELECT MAX(CollectionTime) AS LastCollection
FROM dbo.PerformanceMetrics
WHERE ServerID = 1;
```

**Check 3**: Check job history for errors
```sql
EXEC msdb.dbo.sp_help_jobhistory @job_name = N'SQL Monitor - Complete Collection';
```

**Solution**: If job is disabled or failing, re-run setup:
```bash
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -d MonitoringDB -i database/09-create-sql-agent-jobs.sql
```

---

### Issue: Grafana dashboard not auto-refreshing

**Check 1**: Verify auto-refresh is enabled
- Look at top-right corner of dashboard
- Should show "Refreshing in XX seconds"

**Check 2**: Enable auto-refresh
1. Click time picker (top-right)
2. Find "Refresh" dropdown
3. Select "30s"

**Check 3**: Browser performance
- Disable ad blockers
- Close other tabs
- Check browser console for errors (F12 → Console)

---

### Issue: API collection endpoint returns error

**Check 1**: Verify API is running
```bash
curl http://localhost:5000/api/metrics/health
```

**Check 2**: Check API logs
```bash
docker-compose logs api | tail -50
```

**Check 3**: Verify database connection
```bash
docker-compose exec api printenv | grep ConnectionStrings
```

**Solution**: Restart API container
```bash
docker-compose restart api
```

---

## Health Check Endpoints

### API Health Check
```bash
curl http://localhost:5000/api/metrics/health
```

**Healthy Response**:
```json
{
  "status": "Healthy",
  "lastCollectionTime": "2025-10-26T06:42:09Z",
  "secondsSinceCollection": 10.2,
  "nextExpectedCollection": "2025-10-26T06:47:09Z"
}
```

**Unhealthy Response** (no collections yet):
```json
{
  "status": "Unhealthy",
  "reason": "No metrics have been collected yet",
  "recommendation": "Run: POST /api/metrics/collect to start collection"
}
```

**Degraded Response** (stale data):
```json
{
  "status": "Degraded",
  "lastCollectionTime": "2025-10-26T06:00:00Z",
  "minutesSinceCollection": 42.15,
  "reason": "No recent collections (expected every 5 minutes)",
  "recommendation": "Check SQL Agent job status"
}
```

---

### Last Collection Time
```bash
curl http://localhost:5000/api/metrics/last-collection/1
```

**Response**:
```json
{
  "serverId": 1,
  "lastCollectionTime": "2025-10-26T06:42:09Z",
  "secondsSinceCollection": 10.2,
  "isStale": false
}
```

---

## Performance Expectations

| Collection Type | Duration | What It Includes |
|-----------------|----------|------------------|
| **Fast** (`includeAdvanced=false`) | ~4 seconds | Server metrics + drill-down (queries, procedures, databases) |
| **Full** (`includeAdvanced=true`) | ~225 seconds | Server + drill-down + index analysis + Query Store + blocking |

**Recommendation**:
- Use **fast collection** for frequent refreshes (30 seconds)
- Use **full collection** for detailed analysis (once per hour or on-demand)
- SQL Agent job uses **fast collection** (every 5 minutes)

---

## Configuration Files

### SQL Agent Job Schedule

**File**: `database/09-create-sql-agent-jobs.sql`

**Schedule Settings**:
```sql
-- Every 5 minutes schedule
EXEC msdb.dbo.sp_add_schedule
    @schedule_name = N'Every 5 Minutes',
    @enabled = 1,
    @freq_type = 4,              -- Daily
    @freq_interval = 1,          -- Every day
    @freq_subday_type = 4,       -- Minutes
    @freq_subday_interval = 5;   -- Every 5 minutes
```

**To Change Schedule**:
```sql
-- Update to every 10 minutes
EXEC msdb.dbo.sp_update_schedule
    @name = N'Every 5 Minutes',
    @freq_subday_interval = 10;
```

---

### Grafana Dashboard Refresh

**File**: `grafana/dashboards/05-performance-analysis.json`

**Current Setting**:
```json
{
  "refresh": "30s",
  "time": {
    "from": "now-6h",
    "to": "now"
  }
}
```

**To Change** (via Grafana UI):
1. Open dashboard
2. Click gear icon (⚙️) → Settings
3. Find "Auto refresh" setting
4. Change from "30s" to desired interval
5. Save dashboard

---

## Summary

**Automated Refresh is Configured and Working!**

- ✅ **SQL Agent Job**: Runs every 5 minutes automatically
- ✅ **Grafana Auto-Refresh**: Dashboard refreshes every 30 seconds
- ✅ **On-Demand API**: Manual trigger available for immediate refresh
- ✅ **Health Monitoring**: Endpoints available to check collection status

**Typical Data Flow**:
1. SQL Agent job runs every 5 minutes → Collects metrics
2. Grafana refreshes every 30 seconds → Fetches latest data
3. User sees fresh data (0-5 minutes old)
4. Optional: User triggers API collection for immediate refresh (0-4 seconds old)

**No manual intervention required** - the system continuously collects and displays data automatically!
