# Grafana Quick Start - 30 Seconds

## 1. Start Containers
```bash
docker-compose up -d
```

## 2. Wait 15 Seconds
Grafana provisions automatically:
- ✅ MSSQL datasource (MonitoringDB)
- ✅ SQL Server Performance Overview dashboard
- ✅ Detailed Metrics View dashboard

## 3. Access Grafana
**URL**: http://localhost:3000

**Login**:
- Username: `admin`
- Password: `Admin123!`

## 4. View Dashboards

Click "Dashboards" in left menu, then select:
- **SQL Server Performance Overview** - Main dashboard
- **Detailed Metrics View** - Detailed metrics table

**Direct Links**:
- Overview: http://localhost:3000/d/sql-server-overview
- Detailed: http://localhost:3000/d/detailed-metrics

## 5. That's It!

Everything is pre-configured and ready to use.

---

## What You Get

### Dashboard 1: SQL Server Performance Overview
- CPU Usage (%) - Last 24h time series
- Memory Usage (%) - Last 24h time series
- Current CPU gauge
- Current Memory gauge
- Active servers count
- Metrics collected (24h)
- Disk I/O throughput
- Monitored servers table

### Dashboard 2: Detailed Metrics View
- Recent 100 metrics table
- All metrics time series

---

## Add Sample Metrics

```bash
# Insert CPU metric
curl -X POST http://localhost:5000/api/metrics \
  -H "Content-Type: application/json" \
  -d '{
    "serverID": 1,
    "collectionTime": "'$(date -u '+%Y-%m-%dT%H:%M:%SZ')'",
    "metricCategory": "CPU",
    "metricName": "Percent",
    "metricValue": 45.5
  }'

# Insert Memory metric
curl -X POST http://localhost:5000/api/metrics \
  -H "Content-Type: application/json" \
  -d '{
    "serverID": 1,
    "collectionTime": "'$(date -u '+%Y-%m-%dT%H:%M:%SZ')'",
    "metricCategory": "Memory",
    "metricName": "Percent",
    "metricValue": 65.2
  }'
```

---

## Customize

- **Add dashboards**: Drop JSON files in `grafana/dashboards/`
- **Add datasources**: Create YAML in `grafana/provisioning/datasources/`
- **Restart**: `docker-compose restart grafana`

See GRAFANA-AUTOMATED-SETUP.md for detailed customization guide.
