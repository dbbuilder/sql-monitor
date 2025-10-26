# Grafana Automated Setup Guide

## Overview

The SQL Server Monitor uses **Grafana Provisioning** to automatically configure data sources and dashboards on startup. No manual configuration needed!

---

## What Gets Automatically Configured?

### 1. Data Source (MonitoringDB)
- **Name**: MonitoringDB
- **Type**: Microsoft SQL Server
- **Connection**: sqltest.schoolvision.net:14333
- **Database**: MonitoringDB
- **Credentials**: sv / Gv51076!
- **Status**: ✅ Automatically provisioned on startup

### 2. Pre-Built Dashboards

#### Dashboard 1: SQL Server Performance Overview
**URL**: http://localhost:3000/d/sql-server-overview

**Panels**:
- **CPU Usage (%)** - Time series chart (last 24h)
- **Memory Usage (%)** - Time series chart (last 24h)
- **Current CPU** - Gauge (real-time)
- **Current Memory** - Gauge (real-time)
- **Active Servers** - Stat counter
- **Metrics (24h)** - Total metrics collected
- **Disk I/O (MB/s)** - Read/Write throughput
- **Monitored Servers** - Table with all servers

**Refresh**: Auto-refresh every 30 seconds
**Time Range**: Last 24 hours

#### Dashboard 2: Detailed Metrics View
**URL**: http://localhost:3000/d/detailed-metrics

**Panels**:
- **Recent Metrics** - Table showing last 100 metrics
- **All Metrics Time Series** - Combined view of all metrics

**Refresh**: Auto-refresh every 1 minute
**Time Range**: Last 24 hours

---

## Directory Structure

```
grafana/
├── provisioning/
│   ├── datasources/
│   │   └── monitoringdb.yml          # Auto-configures MSSQL datasource
│   └── dashboards/
│       └── default.yml                # Dashboard provisioning config
└── dashboards/
    ├── sql-server-overview.json      # Main performance dashboard
    └── detailed-metrics.json          # Detailed metrics view
```

---

## How It Works

### Step 1: Docker Container Starts
When `docker-compose up -d` runs, Grafana container starts with mounted volumes:

```yaml
volumes:
  - ./grafana/provisioning/datasources:/etc/grafana/provisioning/datasources:ro
  - ./grafana/provisioning/dashboards:/etc/grafana/provisioning/dashboards:ro
  - ./grafana/dashboards:/var/lib/grafana/dashboards:ro
```

### Step 2: Grafana Reads Provisioning Files
On startup, Grafana automatically:
1. Scans `/etc/grafana/provisioning/datasources/` for datasource configs
2. Creates the MonitoringDB datasource connection
3. Scans `/etc/grafana/provisioning/dashboards/` for dashboard configs
4. Loads all JSON dashboards from `/var/lib/grafana/dashboards/`

### Step 3: Dashboards Are Ready
Within 10-15 seconds of startup, dashboards are fully configured and accessible.

---

## Access Grafana

1. **Open Grafana**: http://localhost:3000
2. **Login**:
   - Username: `admin`
   - Password: `Admin123!`
3. **View Dashboards**:
   - Click "Dashboards" in left menu
   - Select "SQL Server Performance Overview" or "Detailed Metrics View"

**Direct Links**:
- Overview: http://localhost:3000/d/sql-server-overview
- Detailed: http://localhost:3000/d/detailed-metrics

---

## Verification

Check that provisioning worked:

### 1. Verify Data Source
```bash
curl -s -u admin:Admin123! http://localhost:3000/api/datasources | jq '.[0].name'
# Expected: "MonitoringDB"
```

### 2. Verify Dashboards
```bash
curl -s -u admin:Admin123! http://localhost:3000/api/search?type=dash-db | jq '.[].title'
# Expected:
# "Detailed Metrics View"
# "SQL Server Performance Overview"
```

### 3. Check Container Logs
```bash
docker logs sql-monitor-grafana 2>&1 | grep -i "provision\|datasource"
# Should show: "inserting datasource from configuration name=MonitoringDB"
```

---

## Customization

### Add New Data Source

Create a new YAML file in `grafana/provisioning/datasources/`:

```yaml
# Example: production-db.yml
apiVersion: 1

datasources:
  - name: ProductionDB
    type: mssql
    access: proxy
    uid: productiondb
    url: prod-sql.example.com:1433
    database: ProductionDB
    user: monitoring_user
    secureJsonData:
      password: 'SecurePassword123!'
    jsonData:
      maxOpenConns: 10
      maxIdleConns: 5
      encrypt: 'false'
      tlsSkipVerify: true
    isDefault: false
    editable: false
```

Restart Grafana:
```bash
docker-compose restart grafana
```

### Add New Dashboard

1. **Option A: Export from Grafana UI**
   - Create dashboard in Grafana
   - Click "Share" → "Export" → "Save to file"
   - Copy JSON to `grafana/dashboards/my-dashboard.json`
   - Restart: `docker-compose restart grafana`

2. **Option B: Create JSON Manually**
   - Use existing dashboard JSON as template
   - Modify queries, panels, titles
   - Save to `grafana/dashboards/`
   - Restart: `docker-compose restart grafana`

### Modify Existing Dashboard

**Important**: Provisioned dashboards are **read-only by default** to prevent accidental changes.

To allow editing:
1. Edit `grafana/provisioning/dashboards/default.yml`
2. Change `allowUiUpdates: false` to `allowUiUpdates: true`
3. Restart Grafana: `docker-compose restart grafana`
4. Edit dashboard in UI
5. Export updated JSON
6. Replace file in `grafana/dashboards/`

---

## Dashboard Queries

### Example: CPU Metrics Time Series
```sql
SELECT
  CollectionTime AS time,
  MetricValue AS value,
  ServerName AS metric
FROM dbo.PerformanceMetrics
WHERE
  MetricCategory = 'CPU'
  AND MetricName = 'Percent'
  AND CollectionTime >= DATEADD(hour, -24, GETUTCDATE())
ORDER BY time ASC
```

### Example: Current CPU Gauge
```sql
SELECT TOP 1
  MetricValue
FROM dbo.PerformanceMetrics
WHERE
  MetricCategory = 'CPU'
  AND MetricName = 'Percent'
ORDER BY CollectionTime DESC
```

### Example: Active Servers Count
```sql
SELECT COUNT(*) AS value
FROM dbo.Servers
WHERE IsActive = 1
```

---

## Pre-Built Alerts (Optional)

To add alerting, create `grafana/provisioning/alerting/alerts.yml`:

```yaml
apiVersion: 1

groups:
  - orgId: 1
    name: SQL Server Alerts
    folder: Alerts
    interval: 1m
    rules:
      - uid: high-cpu-alert
        title: High CPU Usage
        condition: A
        data:
          - refId: A
            datasourceUid: monitoringdb
            model:
              rawSql: |
                SELECT TOP 1 MetricValue
                FROM dbo.PerformanceMetrics
                WHERE MetricCategory = 'CPU' AND MetricName = 'Percent'
                ORDER BY CollectionTime DESC
        for: 5m
        annotations:
          description: CPU usage is above 80%
        labels:
          severity: warning
```

---

## Troubleshooting

### Dashboards Not Appearing

**Check logs**:
```bash
docker logs sql-monitor-grafana 2>&1 | grep -i dashboard
```

**Common issues**:
- JSON syntax errors in dashboard files
- Missing provisioning configuration
- Volume mount paths incorrect

**Fix**:
1. Validate JSON: `cat grafana/dashboards/sql-server-overview.json | jq .`
2. Check mounts: `docker inspect sql-monitor-grafana | grep -A5 Mounts`
3. Restart: `docker-compose restart grafana`

### Data Source Connection Failed

**Test connection**:
```bash
# From container
docker exec -it sql-monitor-grafana /bin/bash
# Inside container (if sqlcmd available):
# sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -Q "SELECT @@VERSION"
```

**Common issues**:
- Firewall blocking port 14333
- SQL Server not allowing remote connections
- Incorrect credentials

**Fix**:
1. Update `grafana/provisioning/datasources/monitoringdb.yml`
2. Restart: `docker-compose restart grafana`

### Dashboards Show "No Data"

**Check if metrics exist**:
```bash
curl -s "http://localhost:5000/api/metrics?serverID=1" | jq length
# Should return > 0
```

**Insert test metrics**:
```bash
curl -X POST http://localhost:5000/api/metrics \
  -H "Content-Type: application/json" \
  -d '{
    "serverID": 1,
    "collectionTime": "'$(date -u '+%Y-%m-%dT%H:%M:%SZ')'",
    "metricCategory": "CPU",
    "metricName": "Percent",
    "metricValue": 45.5
  }'
```

**Verify in Grafana**:
- Open dashboard
- Click panel title → "Edit"
- Click "Query inspector" → "Refresh"
- Check if query returns data

---

## Performance Tuning

### Datasource Connection Pooling

In `grafana/provisioning/datasources/monitoringdb.yml`:

```yaml
jsonData:
  maxOpenConns: 10        # Max concurrent connections
  maxIdleConns: 5         # Max idle connections in pool
  connMaxLifetime: 14400  # Connection lifetime (seconds)
```

**Recommendations**:
- **Low traffic**: maxOpenConns=5, maxIdleConns=2
- **Medium traffic**: maxOpenConns=10, maxIdleConns=5
- **High traffic**: maxOpenConns=20, maxIdleConns=10

### Dashboard Refresh Rates

Modify in dashboard JSON:
```json
{
  "refresh": "30s"  // Options: "5s", "10s", "30s", "1m", "5m", etc.
}
```

**Recommendations**:
- **Production monitoring**: 30s - 1m
- **Troubleshooting**: 5s - 10s
- **Historical analysis**: Disable auto-refresh

---

## Security Considerations

### 1. Secure Passwords in Provisioning

**Current (Test Environment)**:
```yaml
secureJsonData:
  password: 'Gv51076!'  # Plain text - OK for testing
```

**Production (Use Environment Variables)**:
```yaml
secureJsonData:
  password: '${MSSQL_PASSWORD}'  # Read from environment
```

In `.env`:
```bash
MSSQL_PASSWORD=YourSecurePassword123!
```

### 2. Read-Only Dashboards

Set `editable: false` in dashboard JSON to prevent modifications:
```json
{
  "editable": false
}
```

### 3. Grafana Admin Password

Change default password in `.env`:
```bash
GRAFANA_ADMIN_PASSWORD=YourStrongPasswordHere!
```

---

## Next Steps

1. **Monitor Real Servers**: Add production SQL Servers to monitoring
2. **Create Custom Dashboards**: Build dashboards for specific metrics
3. **Set Up Alerts**: Configure email/Slack notifications
4. **Automate Metric Collection**: Create SQL Agent jobs to collect metrics
5. **Add More Metrics**: CPU, Memory, Disk, Network, Query Performance

---

## Resources

- **Grafana Provisioning Docs**: https://grafana.com/docs/grafana/latest/administration/provisioning/
- **MSSQL Plugin Docs**: https://grafana.com/docs/grafana/latest/datasources/mssql/
- **Dashboard JSON Schema**: https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/view-dashboard-json-model/

---

## Summary

✅ **Fully Automated**: No manual Grafana configuration needed
✅ **Pre-Built Dashboards**: 2 dashboards ready to use
✅ **Auto-Configured Data Source**: MSSQL connection to MonitoringDB
✅ **Instant Deployment**: Just run `docker-compose up -d`
✅ **Easily Customizable**: Add dashboards by copying JSON files

**Access Now**: http://localhost:3000 (admin / Admin123!)
