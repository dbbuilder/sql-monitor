# Grafana Setup Guide - SQL Server Monitor

## Overview

This guide explains how to set up and use Grafana for visualizing SQL Server monitoring data from MonitoringDB.

**Last Updated**: 2025-10-28
**Grafana Version**: 10.2.0 (OSS)
**Architecture**: Docker Compose

---

## Quick Start

### 1. Start Grafana

```bash
# From project root
docker-compose up -d grafana

# Check status
docker-compose ps

# View logs
docker-compose logs -f grafana
```

### 2. Access Grafana

- **URL**: http://localhost:9001
- **Username**: `admin`
- **Password**: `Admin123!` (configured in `.env`)

### 3. Navigate to Dashboards

1. Click **Dashboards** (left sidebar)
2. Select **SQL Server Monitoring - Overview**
3. Enjoy real-time metrics!

---

## Configuration

### Environment Variables

Configure Grafana in `.env` file:

```bash
# Grafana Configuration
GRAFANA_ADMIN_PASSWORD=Admin123!      # Change in production!
GF_SERVER_HTTP_PORT=9001              # External port
```

### Docker Compose Configuration

```yaml
grafana:
  image: grafana/grafana-oss:10.2.0
  ports:
    - "${GF_SERVER_HTTP_PORT:-9001}:3000"
  environment:
    - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
    - GF_SERVER_ROOT_URL=http://localhost:${GF_SERVER_HTTP_PORT:-9001}
    - GF_AUTH_ANONYMOUS_ENABLED=false
  volumes:
    - grafana-data:/var/lib/grafana
    - ./dashboards/grafana/provisioning/datasources:/etc/grafana/provisioning/datasources:ro
    - ./dashboards/grafana/provisioning/dashboards:/etc/grafana/provisioning/dashboards:ro
    - ./dashboards/grafana/dashboards:/var/lib/grafana/dashboards:ro
```

---

## Datasource Configuration

The MonitoringDB datasource is automatically provisioned from `dashboards/grafana/provisioning/datasources/monitoringdb.yaml`:

```yaml
datasources:
  - name: MonitoringDB
    type: mssql                           # SQL Server plugin
    access: proxy                          # Grafana queries on behalf of user
    url: sqltest.schoolvision.net:14333
    database: MonitoringDB
    user: sv
    jsonData:
      encrypt: 'true'
      sslmode: 'disable'
      tlsSkipVerify: true
      authenticator: 'SQL Server Authentication'
    secureJsonData:
      password: 'Gv51076!'                # Encrypted by Grafana
    isDefault: true
    editable: false
```

**Security Note**: In production, use a dedicated monitoring SQL login with **least privilege** (see `docs/SQL-MONITOR-PERMISSIONS.md`).

---

## Available Dashboards

### 1. SQL Server Monitoring - Overview
**File**: `00-sql-server-monitoring.json`

**Panels**:
- Server Health Overview
  - Active Servers count
  - Active Critical Alerts
  - Metrics Collected (7 days)
  - Current CPU gauge (with thresholds)
  - Current Memory gauge (with thresholds)

- Performance Trends
  - CPU Usage % (timeseries, 24h)
  - Memory Usage % (timeseries, 24h)

- Database Performance
  - Top 10 Databases by Size (MB)
  - Top 10 Slowest Procedures (Last Hour)

- Wait Statistics
  - Top 15 Wait Events by Database (Last Hour)

**Features**:
- **Auto-refresh**: 30 seconds
- **Time range**: Last 24 hours (configurable)
- **Variables**: Datasource selector
- **Dark theme**: Professional look
- **Interactive**: Click legend to hide/show series

### 2. Table Browser
**File**: `01-table-browser.json`
- Browse all tables in monitored databases
- View table metadata, row counts, sizes

### 3. Table Details
**File**: `02-table-details.json`
- Detailed table information
- Column definitions, indexes, foreign keys

### 4. Code Browser
**File**: `03-code-browser.json`
- Browse stored procedures, functions, views
- View source code with syntax highlighting (Phase 1.25)

### 5. Performance Analysis
**File**: `05-performance-analysis.json`
- Deep-dive performance metrics
- Query execution statistics
- Index usage analysis

### 6. Audit Logging
**File**: `07-audit-logging.json`
- View audit trail (Phase 2.0)
- User activity, authentication events
- SOC 2 compliance reporting

---

## Creating Custom Dashboards

### Step 1: Create New Dashboard

1. Click **Dashboards** → **New** → **New Dashboard**
2. Click **Add visualization**
3. Select **MonitoringDB** datasource
4. Choose panel type (Time series, Table, Gauge, etc.)

### Step 2: Write SQL Query

Example: Recent CPU usage

```sql
SELECT
  CollectionTime AS time,
  MetricValue AS value,
  s.ServerName AS metric
FROM dbo.PerformanceMetrics pm
INNER JOIN dbo.Servers s ON pm.ServerID = s.ServerID
WHERE pm.MetricCategory = 'CPU'
  AND pm.MetricName = 'Percent'
  AND pm.CollectionTime >= $__timeFrom()
  AND pm.CollectionTime <= $__timeTo()
ORDER BY pm.CollectionTime ASC
```

**Grafana Macros**:
- `$__timeFrom()` - Dashboard start time
- `$__timeTo()` - Dashboard end time
- `$__interval` - Auto-calculated interval
- `${variable}` - Dashboard variable

### Step 3: Configure Panel

- **Title**: CPU Usage Over Time
- **Unit**: Percent (0-100)
- **Thresholds**:
  - Green: 0-70
  - Yellow: 70-85
  - Red: 85-100
- **Legend**: Show, Table mode, Calculations (Mean, Last, Max)

### Step 4: Save Dashboard

1. Click **Save dashboard** (top right)
2. Enter name: "My Custom Dashboard"
3. Click **Save**

---

## Query Examples

### Top 10 Slowest Queries

```sql
SELECT TOP 10
  DatabaseName,
  QueryHash,
  ExecutionCount,
  AvgDurationMs,
  MaxDurationMs,
  TotalCPUTimeMs
FROM dbo.QueryMetrics
WHERE CollectionTime >= $__timeFrom()
ORDER BY AvgDurationMs DESC
```

**Panel Type**: Table

### Database Growth Trend

```sql
SELECT
  CollectionTime AS time,
  DataSizeMB AS value,
  DatabaseName AS metric
FROM dbo.DatabaseMetrics
WHERE DatabaseName IN ('ProductionDB', 'ArchiveDB')
  AND CollectionTime >= $__timeFrom()
  AND CollectionTime <= $__timeTo()
ORDER BY CollectionTime ASC
```

**Panel Type**: Time series

### Active Blocking Sessions

```sql
SELECT
  BlockingTime AS time,
  WaitTimeMs AS value,
  CONCAT(BlockedSPID, ' blocked by ', BlockingSPID) AS metric
FROM dbo.BlockingEvents
WHERE BlockingTime >= $__timeFrom()
  AND BlockingTime <= $__timeTo()
  AND IsResolved = 0
ORDER BY BlockingTime ASC
```

**Panel Type**: Time series, Stacked

### Server Health Heatmap

```sql
SELECT
  CollectionTime AS time,
  ServerName AS metric,
  MetricValue AS value
FROM dbo.PerformanceMetrics pm
INNER JOIN dbo.Servers s ON pm.ServerID = s.ServerID
WHERE pm.MetricCategory = 'CPU'
  AND pm.MetricName = 'Percent'
  AND pm.CollectionTime >= $__timeFrom()
  AND pm.CollectionTime <= $__timeTo()
ORDER BY CollectionTime ASC
```

**Panel Type**: Heatmap

---

## Dashboard Variables

Variables make dashboards dynamic and reusable.

### Example: Server Selector

1. **Dashboard Settings** (gear icon) → **Variables** → **New variable**

2. **General**:
   - Name: `server`
   - Label: `Server`
   - Type: `Query`

3. **Query options**:
   - Data source: `MonitoringDB`
   - Query: `SELECT ServerName FROM dbo.Servers WHERE IsActive = 1 ORDER BY ServerName`

4. **Selection options**:
   - Multi-value: Yes
   - Include All option: Yes

5. **Use in queries**:
   ```sql
   WHERE s.ServerName IN ($server)
   ```

### Built-in Variables

- `$__timeFrom()` - Start of time range
- `$__timeTo()` - End of time range
- `$__interval` - Current interval
- `$__interval_ms` - Interval in milliseconds

---

## Alerting

Grafana can send alerts based on metric thresholds.

### Example: High CPU Alert

1. Edit panel → **Alert** tab
2. **Create alert rule from this panel**
3. **Condition**:
   - WHEN: `avg()` of query `A`
   - IS ABOVE: `85`
   - FOR: `5m` (5 minutes)
4. **Notifications**:
   - Send to: Email, Slack, PagerDuty, etc.
5. **Save**

### Alert Channels

Configure in **Alerting** → **Notification channels**:

- **Email**: SMTP server required
- **Slack**: Webhook URL
- **PagerDuty**: Integration key
- **Webhook**: Generic HTTP POST

---

## Performance Optimization

### Query Performance Tips

1. **Use time filters**: Always filter by `CollectionTime` with Grafana time macros
   ```sql
   WHERE CollectionTime >= $__timeFrom()
     AND CollectionTime <= $__timeTo()
   ```

2. **Limit rows**: Use `TOP` or `LIMIT` for large datasets
   ```sql
   SELECT TOP 100 * FROM ...
   ```

3. **Aggregate data**: Use `GROUP BY` for time series
   ```sql
   GROUP BY DATEADD(minute, DATEDIFF(minute, 0, CollectionTime) / 5 * 5, 0)
   ```

4. **Index columns**: Ensure `CollectionTime` and foreign keys are indexed

### Dashboard Performance

- **Refresh interval**: 30s minimum (avoid 1s refresh)
- **Time range**: Don't default to "Last 90 days"
- **Panel count**: <30 panels per dashboard
- **Query timeout**: Set reasonable limits (30s max)

---

## Troubleshooting

### Dashboard shows "No data"

**Check**:
1. Datasource connection: **Configuration** → **Data sources** → **Test**
2. Data exists: Run query in SQL Management Studio
3. Time range: Expand to "Last 7 days"
4. Permissions: User has SELECT permission on tables

### "Login failed for user 'sv'"

**Fix**:
1. Check SQL Server authentication mode (Mixed Mode)
2. Verify password in `monitoringdb.yaml`
3. Test connection: `sqlcmd -S server -U sv -P password`

### Panels show errors

**Common issues**:
- **Invalid column name**: Check table schema
- **Syntax error**: Test SQL in SSMS first
- **Timeout**: Optimize query or increase timeout

### Grafana container won't start

**Check**:
```bash
# View logs
docker-compose logs grafana

# Common issues:
# - Port 9001 already in use
# - Volume permissions
# - Invalid datasource YAML
```

**Fix port conflict**:
```bash
# Change port in .env
GF_SERVER_HTTP_PORT=9002

# Restart
docker-compose restart grafana
```

---

## Production Best Practices

### Security

1. **Change default password**:
   ```bash
   # In .env
   GRAFANA_ADMIN_PASSWORD=YourStrongPassword123!
   ```

2. **Use dedicated SQL login** (see `docs/SQL-MONITOR-PERMISSIONS.md`):
   ```sql
   CREATE LOGIN [grafana_reader] WITH PASSWORD = 'SecurePass!';
   ALTER ROLE db_datareader ADD MEMBER [grafana_reader];
   ```

3. **Enable HTTPS** (reverse proxy):
   ```nginx
   server {
       listen 443 ssl;
       server_name grafana.example.com;

       ssl_certificate /etc/ssl/certs/grafana.crt;
       ssl_certificate_key /etc/ssl/private/grafana.key;

       location / {
           proxy_pass http://localhost:9001;
       }
   }
   ```

4. **Disable anonymous access** (default in docker-compose):
   ```yaml
   - GF_AUTH_ANONYMOUS_ENABLED=false
   ```

### Backup

```bash
# Backup Grafana data (dashboards, users, datasources)
docker cp sql-monitor-grafana:/var/lib/grafana ./grafana-backup-$(date +%Y%m%d).tar

# Restore
docker cp grafana-backup-20251028.tar sql-monitor-grafana:/var/lib/grafana
docker-compose restart grafana
```

### Monitoring Grafana

- **Health check**: http://localhost:9001/api/health
- **Metrics**: http://localhost:9001/metrics (Prometheus format)
- **Logs**: `docker-compose logs -f grafana`

---

## Advanced Features

### Annotations

Add event markers to graphs:

```sql
SELECT
  EventTime AS time,
  EventType AS text,
  CONCAT(EventType, ': ', Details) AS tags
FROM dbo.AuditLog
WHERE EventType IN ('DeploymentStart', 'DeploymentEnd', 'MaintenanceWindow')
  AND EventTime >= $__timeFrom()
  AND EventTime <= $__timeTo()
```

### Table Panel with Links

Create drilldown links:

```json
{
  "overrides": [
    {
      "matcher": {"id": "byName", "options": "DatabaseName"},
      "properties": [
        {
          "id": "links",
          "value": [
            {
              "title": "View Details",
              "url": "/d/table-details?var-database=${__data.fields.DatabaseName}"
            }
          ]
        }
      ]
    }
  ]
}
```

### Template Variables from Query

Dynamic dropdowns:

```sql
-- Database selector
SELECT DISTINCT DatabaseName
FROM dbo.DatabaseMetrics
WHERE CollectionTime >= DATEADD(day, -1, GETUTCDATE())
ORDER BY DatabaseName
```

---

## Resources

- **Grafana Documentation**: https://grafana.com/docs/grafana/latest/
- **SQL Server Plugin**: https://grafana.com/docs/grafana/latest/datasources/mssql/
- **Dashboard Best Practices**: https://grafana.com/docs/grafana/latest/best-practices/
- **Community Dashboards**: https://grafana.com/grafana/dashboards/

---

## Getting Help

### Dashboard Not Working?

1. **Check datasource**: Configuration → Data sources → Test
2. **Test SQL query**: Run in SSMS first
3. **Check permissions**: User must have SELECT on tables
4. **View panel JSON**: Edit → Panel JSON (look for query)
5. **Grafana logs**: `docker-compose logs grafana`

### Need More Metrics?

Add to database:
1. Create/modify stored procedure in `database/`
2. Deploy to MonitoringDB
3. Schedule SQL Agent job for collection
4. Query new table in Grafana

### Want Custom Visualizations?

1. **Install plugin**: https://grafana.com/grafana/plugins/
2. Add to docker-compose:
   ```yaml
   environment:
     - GF_INSTALL_PLUGINS=plugin-name
   ```
3. Restart Grafana

---

## Change Log

| Date | Version | Changes |
|------|---------|---------|
| 2025-10-28 | 1.0 | Initial Grafana setup guide |
| 2025-10-28 | 1.1 | Added SQL Server Monitoring - Overview dashboard |
| 2025-10-28 | 1.2 | Added production best practices and security |

---

**Status**: Production-Ready
**Next Steps**: Test dashboards, create custom panels, set up alerting
