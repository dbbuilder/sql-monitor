# SQL Server Monitor - Setup Guide

## Overview

This guide provides step-by-step instructions for deploying SQL Server Monitor in a **100% air-gapped, firewall-safe environment**. The solution runs entirely within your network with no external dependencies.

**Deployment Time**: 30-60 minutes for initial setup

**Architecture**:
```
Monitored SQL Servers → MonitoringDB (Internal SQL) → Docker (API + Grafana) → Users
```

## Prerequisites

### Required Software

| Component | Version | Purpose | Installation |
|-----------|---------|---------|--------------|
| **SQL Server** | 2016+ | MonitoringDB host | Already installed (use existing) |
| **Docker** | 20.10+ | Container runtime | [Install Docker](https://docs.docker.com/engine/install/) |
| **Docker Compose** | 2.0+ | Container orchestration | Included with Docker Desktop |
| **sqlcmd** | Any | Database deployment | SQL Server client tools |

### Network Requirements

- **Internal network connectivity** between:
  - All monitored SQL Servers ↔ MonitoringDB server (port 1433)
  - Docker host ↔ MonitoringDB server (port 1433)
  - User workstations ↔ Docker host (ports 3000, 5000)
- **No internet required** (air-gap deployment supported)

### Permissions Required

| Task | Permission Needed |
|------|-------------------|
| Create MonitoringDB | `sysadmin` on chosen SQL Server (one-time) |
| Create linked servers | `sysadmin` on each monitored SQL Server (one-time) |
| Deploy containers | Docker host administrator |
| Access Grafana | Any user (Grafana login) |

## Phase 1: MonitoringDB Setup (15-20 minutes)

### Step 1.1: Choose MonitoringDB Host

Select one SQL Server to host the MonitoringDB database:

**Criteria**:
- ✅ Least-critical production instance OR dedicated monitoring server
- ✅ Sufficient disk space (plan 2GB/month per 10 monitored servers)
- ✅ Network connectivity to all monitored servers
- ✅ SQL Server 2016+ (any edition: Express, Standard, Enterprise)

**Example**: `SQL-PROD-03` (has extra capacity, good network access)

### Step 1.2: Deploy Database Schema

```bash
# 1. Navigate to repository
cd /path/to/sql-monitor

# 2. Connect to chosen SQL Server
sqlcmd -S SQL-PROD-03 -U sa -P YourPassword -C

# 3. Execute master deployment script
:r database/deploy-all.sql
GO

# 4. Verify database created
USE MonitoringDB;
SELECT DB_NAME();
GO

# 5. Check tables created
SELECT TABLE_SCHEMA, TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
ORDER BY TABLE_SCHEMA, TABLE_NAME;
GO
```

**Expected Output**:
```
TABLE_SCHEMA  TABLE_NAME
dbo           Servers
dbo           PerformanceMetrics
dbo           ProcedureStats
dbo           WaitStatistics
dbo           BlockingEvents
dbo           DeadlockEvents
dbo           AlertRules
dbo           AlertHistory
dbo           Recommendations
```

### Step 1.3: Create Database Users

```sql
-- Run on MonitoringDB
USE MonitoringDB;
GO

-- 1. API service user (for ASP.NET Core container)
CREATE USER [monitor_api] WITH PASSWORD = 'SecureApiPassword123!';
GRANT EXECUTE ON SCHEMA::dbo TO [monitor_api];
GRANT SELECT ON dbo.Servers TO [monitor_api];
GRANT SELECT ON dbo.AlertRules TO [monitor_api];
GO

-- 2. Grafana read-only user
CREATE USER [grafana_reader] WITH PASSWORD = 'SecureGrafanaPassword456!';
GRANT SELECT ON SCHEMA::dbo TO [grafana_reader];
GO

-- 3. Collector service user (for SQL Agent jobs on monitored servers)
CREATE USER [monitor_collector] WITH PASSWORD = 'SecureCollectorPassword789!';
GRANT EXECUTE ON SCHEMA::dbo TO [monitor_collector];
GO

-- 4. Verify users created
SELECT name, type_desc, create_date
FROM sys.database_principals
WHERE name LIKE 'monitor_%' OR name LIKE 'grafana_%';
GO
```

### Step 1.4: Register Monitored Servers

```sql
-- Add each SQL Server to monitoring inventory
USE MonitoringDB;
GO

EXEC dbo.usp_AddServer
    @ServerName = 'SQL-PROD-01',
    @Environment = 'Production',
    @Description = 'Primary application database server';

EXEC dbo.usp_AddServer
    @ServerName = 'SQL-PROD-02',
    @Environment = 'Production',
    @Description = 'Reporting database server';

EXEC dbo.usp_AddServer
    @ServerName = 'SQL-PROD-03',
    @Environment = 'Production',
    @Description = 'Monitoring database host (self-monitored)';

-- Verify servers registered
SELECT ServerID, ServerName, Environment, IsActive, CreatedDate
FROM dbo.Servers;
GO
```

### Step 1.5: Configure Linked Servers (Each Monitored SQL Server)

**Run on EACH monitored SQL Server** to enable collection:

```sql
-- Run this on SQL-PROD-01, SQL-PROD-02, SQL-PROD-03, etc.

-- 1. Create linked server to MonitoringDB
EXEC sp_addlinkedserver
    @server = 'MONITORINGDB_SERVER',
    @srvproduct = '',
    @provider = 'SQLNCLI',
    @datasrc = 'SQL-PROD-03';  -- Change to your MonitoringDB host
GO

-- 2. Configure linked server security
EXEC sp_addlinkedsrvlogin
    @rmtsrvname = 'MONITORINGDB_SERVER',
    @useself = 'FALSE',
    @rmtuser = 'monitor_collector',
    @rmtpassword = 'SecureCollectorPassword789!';
GO

-- 3. Test linked server connection
SELECT * FROM OPENQUERY(MONITORINGDB_SERVER,
    'SELECT DB_NAME() AS DatabaseName, GETDATE() AS CurrentTime');
GO

-- Expected output: DatabaseName = 'MonitoringDB', CurrentTime = current timestamp
```

**Troubleshooting Linked Server**:

```sql
-- If connection fails, check:

-- A. Verify SQL Server allows remote connections
EXEC sp_configure 'remote access', 1;
RECONFIGURE;
GO

-- B. Check firewall (port 1433 open between servers)
-- From monitored server command line:
-- telnet SQL-PROD-03 1433

-- C. Verify login works directly
sqlcmd -S SQL-PROD-03 -U monitor_collector -P SecureCollectorPassword789! -Q "SELECT DB_NAME()"
```

### Step 1.6: Deploy SQL Agent Collection Jobs

**Run on EACH monitored SQL Server**:

```sql
-- Deploy collection job (runs every 5 minutes)
USE msdb;
GO

-- 1. Create job
EXEC sp_add_job
    @job_name = N'SQLMonitor_CollectMetrics',
    @enabled = 1,
    @description = N'Collect performance metrics and send to MonitoringDB',
    @category_name = N'Database Maintenance';
GO

-- 2. Add job step
EXEC sp_add_jobstep
    @job_name = N'SQLMonitor_CollectMetrics',
    @step_name = N'Execute Collection Procedure',
    @subsystem = N'TSQL',
    @command = N'
        EXEC [MONITORINGDB_SERVER].[MonitoringDB].[dbo].[usp_CollectMetrics_RemoteServer]
            @ServerName = @@SERVERNAME;
    ',
    @database_name = N'master',
    @retry_attempts = 3,
    @retry_interval = 1;
GO

-- 3. Create schedule (every 5 minutes)
EXEC sp_add_schedule
    @schedule_name = N'Every5Minutes',
    @freq_type = 4,  -- Daily
    @freq_interval = 1,
    @freq_subday_type = 4,  -- Minutes
    @freq_subday_interval = 5,
    @active_start_time = 0;
GO

-- 4. Attach schedule to job
EXEC sp_attach_schedule
    @job_name = N'SQLMonitor_CollectMetrics',
    @schedule_name = N'Every5Minutes';
GO

-- 5. Add job to local server
EXEC sp_add_jobserver
    @job_name = N'SQLMonitor_CollectMetrics',
    @server_name = N'(local)';
GO

-- 6. Verify job created
SELECT job_id, name, enabled, date_created
FROM msdb.dbo.sysjobs
WHERE name = 'SQLMonitor_CollectMetrics';
GO

-- 7. Test job manually (optional)
EXEC sp_start_job @job_name = N'SQLMonitor_CollectMetrics';
GO

-- Wait 10 seconds, then check job history
SELECT TOP 5
    j.name AS JobName,
    h.run_date,
    h.run_time,
    h.run_status,  -- 1 = Success
    h.message
FROM msdb.dbo.sysjobhistory h
INNER JOIN msdb.dbo.sysjobs j ON h.job_id = j.job_id
WHERE j.name = 'SQLMonitor_CollectMetrics'
ORDER BY h.run_date DESC, h.run_time DESC;
GO
```

**Verify Collection Working**:

```sql
-- Run on MonitoringDB server
USE MonitoringDB;
GO

-- Check metrics are being collected
SELECT TOP 10
    s.ServerName,
    pm.CollectionTime,
    pm.MetricCategory,
    pm.MetricName,
    pm.MetricValue
FROM dbo.PerformanceMetrics pm
INNER JOIN dbo.Servers s ON pm.ServerID = s.ServerID
ORDER BY pm.CollectionTime DESC;
GO

-- Should see recent metrics (within last 5 minutes) from all servers
```

## Phase 2: Container Deployment (10-15 minutes)

### Step 2.1: Prepare Docker Host

Choose a Docker host (can be Windows, Linux, or existing server):

**Requirements**:
- Docker Engine 20.10+
- 2 vCPU, 4 GB RAM minimum
- 50 GB disk space
- Network access to MonitoringDB server (port 1433)

**Install Docker** (if not already installed):

```bash
# Ubuntu/Debian
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Windows Server
Install-Module -Name DockerMsftProvider -Force
Install-Package -Name Docker -ProviderName DockerMsftProvider -Force
Restart-Computer

# Verify installation
docker --version
docker-compose --version
```

### Step 2.2: Create Configuration Files

```bash
# 1. Navigate to repository
cd /path/to/sql-monitor

# 2. Create .env file (secrets and connection strings)
cat > .env <<'EOF'
# Database connection (MonitoringDB)
DB_CONNECTION_STRING=Server=SQL-PROD-03;Database=MonitoringDB;User Id=monitor_api;Password=SecureApiPassword123!;Encrypt=True;TrustServerCertificate=True;Connection Timeout=30

# Grafana admin password
GRAFANA_ADMIN_PASSWORD=AdminPassword456!

# Grafana SQL datasource password
GRAFANA_SQL_PASSWORD=SecureGrafanaPassword456!

# Optional: SMTP settings for email alerts
SMTP_HOST=mail.company.local
SMTP_PORT=587
SMTP_USER=sqlmonitor@company.local
SMTP_PASSWORD=EmailPassword789!
EOF

# 3. Set restrictive permissions on .env
chmod 600 .env

# 4. Verify .env is in .gitignore (never commit secrets!)
grep -q "^\.env$" .gitignore || echo ".env" >> .gitignore
```

### Step 2.3: Create docker-compose.yml

```bash
cat > docker-compose.yml <<'EOF'
version: '3.8'

services:
  # ASP.NET Core API
  api:
    build:
      context: ./api
      dockerfile: Dockerfile
    container_name: sqlmonitor-api
    ports:
      - "5000:5000"
    environment:
      - ASPNETCORE_ENVIRONMENT=Production
      - ASPNETCORE_URLS=http://+:5000
      - ConnectionStrings__MonitoringDB=${DB_CONNECTION_STRING}
    volumes:
      - api-logs:/app/logs
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/health"]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 30s

  # Grafana OSS
  grafana:
    image: grafana/grafana-oss:10.2.3
    container_name: sqlmonitor-grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
      - GF_DATABASE_TYPE=sqlite3
      - GF_DATABASE_PATH=/var/lib/grafana/grafana.db
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_AUTH_ANONYMOUS_ENABLED=false
      - GF_INSTALL_PLUGINS=
    volumes:
      - grafana-data:/var/lib/grafana
      - ./dashboards/grafana/provisioning:/etc/grafana/provisioning
    restart: unless-stopped
    depends_on:
      - api
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/health"]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 30s

volumes:
  api-logs:
    driver: local
  grafana-data:
    driver: local
EOF
```

### Step 2.4: Build and Start Containers

```bash
# 1. Build API container
docker-compose build api

# Expected output: Successfully built, Successfully tagged

# 2. Start all containers
docker-compose up -d

# Expected output:
# Creating network "sql-monitor_default" with the default driver
# Creating volume "sql-monitor_api-logs" with local driver
# Creating volume "sql-monitor_grafana-data" with local driver
# Creating sqlmonitor-api ... done
# Creating sqlmonitor-grafana ... done

# 3. Verify containers running
docker-compose ps

# Expected output:
# NAME                  STATE    PORTS
# sqlmonitor-api        Up       0.0.0.0:5000->5000/tcp
# sqlmonitor-grafana    Up       0.0.0.0:3000->3000/tcp

# 4. Check container logs
docker-compose logs -f api     # API logs
docker-compose logs -f grafana # Grafana logs

# Press Ctrl+C to exit logs

# 5. Verify health checks passing
docker inspect sqlmonitor-api | grep -A 5 Health
docker inspect sqlmonitor-grafana | grep -A 5 Health
```

**Troubleshooting Container Startup**:

```bash
# If API fails to start:

# A. Check API logs for database connection errors
docker logs sqlmonitor-api

# B. Test database connectivity from container
docker exec -it sqlmonitor-api /bin/bash
apt-get update && apt-get install -y telnet
telnet SQL-PROD-03 1433

# C. Verify connection string in .env
cat .env | grep DB_CONNECTION_STRING

# If Grafana fails to start:

# A. Check Grafana logs
docker logs sqlmonitor-grafana

# B. Verify permissions on Grafana volume
docker volume inspect sql-monitor_grafana-data

# C. Reset Grafana container
docker-compose down
docker volume rm sql-monitor_grafana-data
docker-compose up -d grafana
```

## Phase 3: Grafana Configuration (10-15 minutes)

### Step 3.1: Initial Login

1. Open browser: `http://<docker-host>:3000`
2. Login credentials:
   - Username: `admin`
   - Password: (from .env `GRAFANA_ADMIN_PASSWORD`)
3. Change password (optional, recommended)

### Step 3.2: Add SQL Server Data Source

**Method A: Automated (Provisioning)**

```bash
# 1. Create provisioning directory structure
mkdir -p dashboards/grafana/provisioning/datasources

# 2. Create datasource configuration
cat > dashboards/grafana/provisioning/datasources/monitoringdb.yaml <<EOF
apiVersion: 1

datasources:
  - name: MonitoringDB
    type: mssql
    access: proxy
    url: SQL-PROD-03:1433
    database: MonitoringDB
    user: grafana_reader
    jsonData:
      encrypt: 'true'
      sslmode: 'require'
      authenticationType: SQL
    secureJsonData:
      password: SecureGrafanaPassword456!
    isDefault: true
    editable: false
EOF

# 3. Restart Grafana to apply
docker-compose restart grafana

# 4. Verify datasource auto-created
# Navigate to: Configuration → Data Sources → MonitoringDB
```

**Method B: Manual (via UI)**

1. Navigate to: **Configuration** (gear icon) → **Data Sources**
2. Click **Add data source**
3. Select **Microsoft SQL Server**
4. Configure:
   - **Name**: `MonitoringDB`
   - **Host**: `SQL-PROD-03:1433`
   - **Database**: `MonitoringDB`
   - **User**: `grafana_reader`
   - **Password**: `SecureGrafanaPassword456!`
   - **Encrypt**: ✅ Enabled
   - **TLS/SSL Mode**: `require`
5. Click **Save & Test**
6. Expected: ✅ "Database Connection OK"

**Troubleshooting Data Source**:

```sql
-- If connection fails:

-- A. Test credentials directly from Docker host
sqlcmd -S SQL-PROD-03 -U grafana_reader -P SecureGrafanaPassword456! -Q "SELECT DB_NAME()"

-- B. Check firewall between Docker host and SQL server
telnet SQL-PROD-03 1433

-- C. Verify SQL Server allows SQL authentication
-- Run on SQL-PROD-03:
SELECT SERVERPROPERTY('IsIntegratedSecurityOnly');
-- Should return 0 (mixed mode)

-- If returns 1, enable mixed mode:
USE master;
EXEC xp_instance_regwrite
    N'HKEY_LOCAL_MACHINE',
    N'Software\Microsoft\MSSQLServer\MSSQLServer',
    N'LoginMode', REG_DWORD, 2;
-- Then restart SQL Server service
```

### Step 3.3: Import Dashboards

**Create First Dashboard (Instance Health Overview)**:

1. Click **+ (Create)** → **Dashboard**
2. Click **Add Panel**
3. Configure query:

```sql
-- Panel: Server CPU Utilization (Last Hour)
SELECT
    $__timeGroup(CollectionTime, '1m') AS time,
    ServerName,
    AVG(MetricValue) AS cpu_percent
FROM dbo.PerformanceMetrics pm
INNER JOIN dbo.Servers s ON pm.ServerID = s.ServerID
WHERE
    pm.MetricCategory = 'CPU'
    AND pm.MetricName = 'Processor_Percent'
    AND $__timeFilter(CollectionTime)
GROUP BY $__timeGroup(CollectionTime, '1m'), ServerName
ORDER BY time
```

4. Set visualization:
   - **Type**: Time series
   - **Legend**: Show, Bottom
   - **Axes**: Left Y-axis = Percent (0-100)
5. Click **Apply**
6. Click **Save Dashboard** (top right)
   - **Name**: `Instance Health`
   - **Folder**: (Create new) `SQL Server Monitor`
7. Click **Save**

**Import Pre-Built Dashboards** (when available):

```bash
# Export dashboard JSON
# In Grafana: Dashboard → Share → Export → Save to file

# Copy to provisioning directory
cp ~/Downloads/instance-health.json dashboards/grafana/dashboards/

# Create dashboard provisioning config
cat > dashboards/grafana/provisioning/dashboards/dashboards.yaml <<EOF
apiVersion: 1

providers:
  - name: 'SQL Server Monitor'
    orgId: 1
    folder: 'SQL Server Monitor'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards
EOF

# Restart Grafana
docker-compose restart grafana
```

### Step 3.4: Create Critical Dashboards

**Dashboard 1: Instance Health**

Panels:
- CPU Utilization (all servers, time series)
- Memory Usage (Page Life Expectancy, Buffer Cache Hit Ratio)
- Disk I/O Latency
- Active Connections
- Batch Requests/sec

**Dashboard 2: Developer (Stored Procedures)**

Panels:
- Top 10 Procedures by Duration
- Top 10 Procedures by Execution Count
- Top 10 Procedures by Logical Reads
- Procedure Execution Timeline
- Parameter Sniffing Detection

Example Query:

```sql
-- Top 10 Procedures by Avg Duration (Last 24h)
SELECT TOP 10
    DatabaseName,
    ProcedureName,
    AVG(AvgDurationMs) AS AvgDuration,
    SUM(ExecutionCount) AS TotalExecutions,
    MAX(MaxDurationMs) AS MaxDuration
FROM dbo.ProcedureStats ps
INNER JOIN dbo.Servers s ON ps.ServerID = s.ServerID
WHERE
    s.ServerName = '$ServerName'
    AND $__timeFilter(CollectionTime)
GROUP BY DatabaseName, ProcedureName
ORDER BY AvgDuration DESC
```

**Dashboard 3: DBA (Waits & Blocking)**

Panels:
- Wait Statistics Breakdown (pie chart)
- Top Waits Over Time
- Blocking Chains (table)
- Deadlock History
- Index Fragmentation

**Dashboard 4: Capacity Planning**

Panels:
- Database Size Growth (time series)
- Log File Usage Trend
- Disk Space Remaining (gauge)
- VLF Count (table)

## Phase 4: Validation & Testing (10 minutes)

### Step 4.1: Verify Data Collection

```sql
-- Run on MonitoringDB
USE MonitoringDB;
GO

-- 1. Check all servers reporting metrics
SELECT
    s.ServerName,
    MAX(pm.CollectionTime) AS LastCollection,
    DATEDIFF(MINUTE, MAX(pm.CollectionTime), GETUTCDATE()) AS MinutesSinceLastCollection,
    COUNT(DISTINCT pm.MetricCategory) AS MetricCategoriesCollected
FROM dbo.Servers s
LEFT JOIN dbo.PerformanceMetrics pm ON s.ServerID = pm.ServerID
WHERE s.IsActive = 1
GROUP BY s.ServerName
ORDER BY s.ServerName;
GO

-- Expected: All servers with LastCollection < 5 minutes ago

-- 2. Check metric variety
SELECT
    MetricCategory,
    COUNT(DISTINCT MetricName) AS UniqueMetrics,
    COUNT(*) AS TotalRows,
    MIN(CollectionTime) AS FirstCollection,
    MAX(CollectionTime) AS LastCollection
FROM dbo.PerformanceMetrics
GROUP BY MetricCategory
ORDER BY MetricCategory;
GO

-- Expected: Multiple categories (CPU, Memory, IO, Wait, etc.)

-- 3. Verify SQL Agent jobs running
SELECT
    j.name AS JobName,
    ja.run_requested_date AS LastRun,
    CASE ja.last_run_outcome
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 3 THEN 'Canceled'
        ELSE 'Unknown'
    END AS LastOutcome,
    js.next_run_date,
    js.next_run_time
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobactivity ja ON j.job_id = ja.job_id
INNER JOIN msdb.dbo.sysjobschedules js ON j.job_id = js.job_id
WHERE j.name = 'SQLMonitor_CollectMetrics'
ORDER BY ja.run_requested_date DESC;
GO
```

### Step 4.2: Test API Endpoints

```bash
# From Docker host or any machine with network access

# 1. Health check
curl http://localhost:5000/health

# Expected output (JSON):
# {
#   "status": "Healthy",
#   "database": "Connected",
#   "lastCollection": "2025-10-25T10:35:00Z",
#   "serversMonitored": 3,
#   "staleServers": 0
# }

# 2. Get servers
curl http://localhost:5000/api/servers

# Expected: JSON array of registered servers

# 3. Get metrics for server
curl "http://localhost:5000/api/metrics/1?startTime=2025-10-25T00:00:00Z"

# Expected: JSON array of metrics

# 4. Swagger UI (browser)
# Navigate to: http://localhost:5000/swagger
# Expected: Interactive API documentation
```

### Step 4.3: Test Grafana Dashboards

1. Login to Grafana: `http://localhost:3000`
2. Navigate to: **Dashboards** → **SQL Server Monitor** → **Instance Health**
3. Verify:
   - ✅ Data loading (no "No data" messages)
   - ✅ Charts showing recent metrics (last 1 hour)
   - ✅ All servers visible in dropdowns
   - ✅ Auto-refresh working (30 second interval)

### Step 4.4: Test Alert Delivery (Optional)

```sql
-- Create test alert rule
USE MonitoringDB;
GO

EXEC dbo.usp_CreateAlertRule
    @RuleName = 'Test Alert - High CPU',
    @MetricCategory = 'CPU',
    @MetricName = 'Processor_Percent',
    @Threshold = 5.0,  -- Intentionally low to trigger
    @Severity = 'Warning',
    @Enabled = 1;
GO

-- Wait 5 minutes for next collection cycle

-- Check if alert triggered
SELECT TOP 5 *
FROM dbo.AlertHistory
ORDER BY AlertTime DESC;
GO

-- Disable test alert
UPDATE dbo.AlertRules
SET Enabled = 0
WHERE RuleName = 'Test Alert - High CPU';
GO
```

## Phase 5: Production Hardening (Optional, 15 minutes)

### Step 5.1: Enable HTTPS (TLS)

```bash
# 1. Generate self-signed certificate (or use company CA cert)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout ./certs/sqlmonitor.key \
    -out ./certs/sqlmonitor.crt \
    -subj "/CN=sqlmonitor.company.local"

# 2. Update docker-compose.yml to add HTTPS
cat >> docker-compose.yml <<'EOF'
  nginx:
    image: nginx:alpine
    container_name: sqlmonitor-nginx
    ports:
      - "443:443"
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./certs:/etc/nginx/certs:ro
    depends_on:
      - api
      - grafana
    restart: unless-stopped
EOF

# 3. Create nginx.conf (reverse proxy with TLS)
cat > nginx.conf <<'EOF'
events {
    worker_connections 1024;
}

http {
    upstream api {
        server api:5000;
    }

    upstream grafana {
        server grafana:3000;
    }

    server {
        listen 443 ssl;
        server_name sqlmonitor.company.local;

        ssl_certificate /etc/nginx/certs/sqlmonitor.crt;
        ssl_certificate_key /etc/nginx/certs/sqlmonitor.key;
        ssl_protocols TLSv1.2 TLSv1.3;

        location / {
            proxy_pass http://grafana;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }

        location /api/ {
            proxy_pass http://api/api/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }

    server {
        listen 80;
        return 301 https://$host$request_uri;
    }
}
EOF

# 4. Restart with HTTPS
docker-compose up -d

# 5. Access via HTTPS
# https://sqlmonitor.company.local
```

### Step 5.2: Configure Backup

```bash
# 1. Backup MonitoringDB daily
sqlcmd -S SQL-PROD-03 -Q "
BACKUP DATABASE MonitoringDB
TO DISK = '/var/opt/mssql/backup/MonitoringDB_$(date +%Y%m%d).bak'
WITH COMPRESSION, INIT;
"

# 2. Backup Grafana dashboards
docker exec sqlmonitor-grafana grafana-cli admin export > grafana-backup.json

# 3. Backup Docker volumes
docker run --rm -v sql-monitor_grafana-data:/data -v $(pwd):/backup \
    alpine tar czf /backup/grafana-data-backup.tar.gz /data
```

### Step 5.3: Performance Tuning

```sql
-- Run on MonitoringDB
USE MonitoringDB;
GO

-- 1. Update statistics
EXEC sp_updatestats;
GO

-- 2. Rebuild fragmented indexes
EXEC dbo.usp_RebuildFragmentedIndexes;
GO

-- 3. Check partition health
SELECT
    OBJECT_NAME(p.object_id) AS TableName,
    p.partition_number,
    p.rows,
    ps.name AS PartitionScheme
FROM sys.partitions p
INNER JOIN sys.indexes i ON p.object_id = i.object_id AND p.index_id = i.index_id
INNER JOIN sys.partition_schemes ps ON i.data_space_id = ps.data_space_id
WHERE OBJECT_NAME(p.object_id) = 'PerformanceMetrics'
ORDER BY p.partition_number;
GO
```

## Troubleshooting

### Issue: No Metrics Showing in Grafana

**Diagnosis**:

```sql
-- Check if any data exists
USE MonitoringDB;
SELECT COUNT(*) FROM dbo.PerformanceMetrics;

-- If zero:
-- A. Check SQL Agent jobs running
EXEC sp_help_job @job_name = 'SQLMonitor_CollectMetrics';

-- B. Check job history for errors
SELECT TOP 10 * FROM msdb.dbo.sysjobhistory
WHERE job_id = (SELECT job_id FROM msdb.dbo.sysjobs WHERE name = 'SQLMonitor_CollectMetrics')
ORDER BY run_date DESC, run_time DESC;

-- C. Test collection SP manually
EXEC dbo.usp_CollectMetrics_RemoteServer @ServerName = 'SQL-PROD-01';
```

### Issue: API Not Connecting to Database

**Diagnosis**:

```bash
# Check API logs
docker logs sqlmonitor-api | grep -i error

# Test database connection from container
docker exec -it sqlmonitor-api /bin/bash
apt-get update && apt-get install -y telnet
telnet SQL-PROD-03 1433

# Verify connection string
cat .env | grep DB_CONNECTION_STRING

# Test connection string manually
sqlcmd -S SQL-PROD-03 -U monitor_api -P SecureApiPassword123! -Q "SELECT DB_NAME()"
```

### Issue: Grafana Datasource Connection Failed

**Diagnosis**:

```bash
# Check Grafana logs
docker logs sqlmonitor-grafana | grep -i datasource

# Test from Grafana container
docker exec -it sqlmonitor-grafana /bin/bash
nc -zv SQL-PROD-03 1433

# Verify SQL Server allows connections
# On SQL-PROD-03:
SELECT SERVERPROPERTY('IsIntegratedSecurityOnly');
EXEC sp_configure 'remote access';
```

## Maintenance

### Daily Tasks (Automated)

- ✅ SQL Agent jobs collect metrics every 5 minutes
- ✅ Alert evaluation runs every 5 minutes
- ✅ Database backup (if configured)

### Weekly Tasks (Manual)

- Review alert history for false positives
- Check disk space on MonitoringDB server
- Review Grafana dashboard for anomalies

### Monthly Tasks (Manual)

- Rebuild fragmented indexes: `EXEC dbo.usp_RebuildFragmentedIndexes;`
- Update statistics: `EXEC sp_updatestats;`
- Review partition scheme: `EXEC dbo.usp_ManagePartitions;`
- Update Grafana/API containers: `docker-compose pull && docker-compose up -d`

## Next Steps

1. ✅ **Customize Dashboards**: Add company-specific metrics and alerts
2. ✅ **Configure Alerts**: Setup email/webhook notifications
3. ✅ **User Training**: Train developers and DBAs on dashboard usage
4. ✅ **Expand Monitoring**: Add more SQL Servers to inventory
5. ✅ **Performance Baselines**: Establish normal baselines for each server

## Support

For issues:
1. Check logs: `docker-compose logs`
2. Review `/health` endpoint: `curl http://localhost:5000/health`
3. Verify SQL Agent jobs: `EXEC msdb.dbo.sp_help_job;`
4. Check GitHub issues: [Repository URL]

---

**Deployment Complete!** You now have a fully functional, air-gapped SQL Server monitoring solution.

- **Grafana**: `http://localhost:3000` (or `https://sqlmonitor.company.local`)
- **API**: `http://localhost:5000` (Swagger at `/swagger`)
- **Metrics**: Collecting every 5 minutes via SQL Agent jobs
