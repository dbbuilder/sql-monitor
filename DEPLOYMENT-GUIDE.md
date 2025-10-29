# SQL Monitor Deployment Guide

**Two-Part Deployment Architecture for Multi-Client Installations**

**Last Updated**: 2025-10-29

---

## Overview

SQL Monitor uses a **two-part deployment strategy** that allows complete data isolation for each client while supporting flexible infrastructure options.

### Architecture

```
CLIENT 1 (ArcTrade)
├── Central Grafana (Visualization Layer)
│   └── Deployed to: Local Docker / Azure / AWS
│       └── Connects to: MonitoringDB on Server X
└── MonitoringDB (Data Collection Layer)
    └── Hosted on: Server X
    └── Collects from: Servers Z, W, T, U (and optionally X)

CLIENT 2 (Another Company)
├── Central Grafana (Visualization Layer)
│   └── Deployed to: Local Docker / Azure / AWS
│       └── Connects to: MonitoringDB on Server Y
└── MonitoringDB (Data Collection Layer)
    └── Hosted on: Server Y
    └── Collects from: Servers A, B, C (and optionally Y)
```

**Key Principles**:
- ✅ Complete data isolation per client (separate Grafana + MonitoringDB)
- ✅ Privacy and compliance (separate networks)
- ✅ Flexible infrastructure (local, Azure, AWS, hybrid)
- ✅ Minimal dependencies (SQL Server + Docker only)

---

## Part 1: Deploy MonitoringDB (Data Collection Layer)

**Script**: `deploy-monitoring.sh`

**What It Does**:
1. Deploys MonitoringDB schema to central server X
2. Registers all monitored servers in inventory
3. Configures linked servers for remote collection
4. Creates SQL Agent jobs on each monitored server (collects every 5 minutes)
5. Triggers initial metadata collection

### Prerequisites

**Central Server (Server X)**:
- SQL Server 2019+ (any edition)
- SQL Agent enabled
- SQL authentication enabled
- Firewall allows connections from monitored servers

**Monitored Servers (Z, W, T, U)**:
- SQL Server 2019+ (any edition)
- SQL Agent enabled
- SQL authentication enabled
- Network connectivity to central server X

**Workstation**:
- `sqlcmd` installed ([Linux](https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-setup-tools) | [Windows](https://learn.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms))
- Bash shell (Linux, macOS, WSL, Git Bash)

### Deployment Steps

#### 1. Configure Environment Variables

Create `.env.monitoring` file:

```bash
# Central MonitoringDB server (where database will be created)
export CENTRAL_SERVER="sql-prod-01"
export CENTRAL_PORT="1433"
export CENTRAL_USER="sa"
export CENTRAL_PASSWORD="YourSecurePassword123"
export CENTRAL_DATABASE="MonitoringDB"

# Monitored servers (comma-separated list)
export MONITORED_SERVERS="sql-prod-02,sql-prod-03,sql-prod-04,sql-prod-05"

# SQL authentication for monitored servers
export MONITORED_USER="monitor_collector"
export MONITORED_PASSWORD="MonitorPass456"
export MONITORED_PORT="1433"

# Collection frequency (minutes)
export COLLECTION_INTERVAL="5"

# Client identification
export CLIENT_NAME="ArcTrade"

# Should central server monitor itself? (true/false)
export MONITOR_CENTRAL_SERVER="true"
```

**Security Note**: Use least-privilege accounts. Create dedicated SQL logins:

```sql
-- On central server X
CREATE LOGIN monitor_api WITH PASSWORD = 'YourSecurePassword123';
CREATE USER monitor_api FOR LOGIN monitor_api;
GRANT EXECUTE ON SCHEMA::dbo TO monitor_api;

-- On monitored servers (Z, W, T, U)
CREATE LOGIN monitor_collector WITH PASSWORD = 'MonitorPass456';
CREATE USER monitor_collector FOR LOGIN monitor_collector;
GRANT VIEW SERVER STATE TO monitor_collector;
GRANT VIEW DATABASE STATE TO monitor_collector;
```

#### 2. Run Deployment Script

```bash
# Load environment variables
source .env.monitoring

# Run deployment
./deploy-monitoring.sh
```

**Expected Output**:

```
========================================
SQL Monitor - Deploy MonitoringDB and Monitored Servers
========================================

  ℹ  Client: ArcTrade
  ℹ  Central Server: sql-prod-01:1433
  ℹ  Central Database: MonitoringDB
  ℹ  Monitored Servers: sql-prod-02,sql-prod-03,sql-prod-04,sql-prod-05
  ℹ  Collection Interval: 5 minutes
  ℹ  Monitor Central Server: true

========================================
Validating Configuration
========================================

  ✓ Configuration valid

========================================
Deploying MonitoringDB Schema
========================================

  ℹ  Found 28 database scripts to execute
  Executing: 01-create-database.sql
  ✓ 01-create-database.sql executed successfully
  Executing: 02-create-tables.sql
  ✓ 02-create-tables.sql executed successfully
  ... (26 more scripts)
  ✓ MonitoringDB schema deployed

========================================
Registering Monitored Servers
========================================

  Registering server: sql-prod-02
  ✓ Server registered: sql-prod-02
  ... (4 more servers)
  ✓ Server registered: sql-prod-01 (central server)

========================================
Configuring Linked Servers
========================================

  Creating linked server: sql-prod-02
  ✓ Linked server configured: sql-prod-02
  ... (3 more linked servers)
  ℹ  Skipping linked server to self: sql-prod-01

========================================
Configuring SQL Agent Jobs
========================================

  Creating SQL Agent job on: sql-prod-02
  ✓ SQL Agent job created on: sql-prod-02
  ... (4 more servers)

========================================
Collecting Initial Metadata
========================================

  Triggering initial collection for: sql-prod-02
  ✓ Initial data collected: sql-prod-02
  ... (4 more servers)

========================================
Verifying Deployment
========================================

  Checking registered servers...
ServerID ServerName     Environment IsActive MonitoringEnabled CollectionIntervalMinutes
-------- -------------- ----------- -------- ----------------- -------------------------
1        sql-prod-01    Production  1        1                 5
2        sql-prod-02    Production  1        1                 5
3        sql-prod-03    Production  1        1                 5
4        sql-prod-04    Production  1        1                 5
5        sql-prod-05    Production  1        1                 5

  Checking recent metrics...
ServerName    CollectionTime           MetricCategory MetricCount
------------- ------------------------ -------------- -----------
sql-prod-01   2025-10-29 10:35:00      CPU            24
sql-prod-02   2025-10-29 10:35:00      Memory         18
... (more metrics)

  ✓ Verification complete

========================================
Deployment Complete!
========================================

  ℹ  Next steps:
  ℹ  1. Verify SQL Agent jobs are running on all monitored servers
  ℹ  2. Check SQL Agent job history
  ℹ  3. Deploy Grafana using deploy-grafana.sh
```

#### 3. Verify SQL Agent Jobs

On each monitored server, check SQL Agent job status:

```sql
-- Check if job exists and is enabled
SELECT
    j.name AS JobName,
    j.enabled AS IsEnabled,
    ja.run_requested_date AS LastRunDate,
    CASE ja.last_run_outcome
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 3 THEN 'Cancelled'
        WHEN 5 THEN 'Unknown'
    END AS LastRunStatus
FROM msdb.dbo.sysjobs j
LEFT JOIN msdb.dbo.sysjobactivity ja ON j.job_id = ja.job_id
WHERE j.name = 'SQLMonitor_CollectMetrics'
ORDER BY ja.run_requested_date DESC;

-- Check job history (last 10 runs)
SELECT TOP 10
    j.name AS JobName,
    h.run_date AS RunDate,
    h.run_time AS RunTime,
    h.run_duration AS DurationSeconds,
    CASE h.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Cancelled'
    END AS Status,
    h.message AS Message
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobhistory h ON j.job_id = h.job_id
WHERE j.name = 'SQLMonitor_CollectMetrics'
ORDER BY h.run_date DESC, h.run_time DESC;
```

---

## Part 2: Deploy Grafana (Visualization Layer)

**Script**: `deploy-grafana.sh`

**What It Does**:
1. Creates datasource configuration pointing to MonitoringDB
2. Deploys Grafana container to local, Azure, or AWS
3. Provisions all 9 dashboards automatically
4. Configures blog panel with 12 SQL optimization articles

### Prerequisites

**Deployment Target Options**:

**Option 1: Local Docker** (Recommended for testing)
- Docker + Docker Compose installed
- Port 9002 available

**Option 2: Azure Container Instances**
- Azure CLI installed (`az --version`)
- Logged in to Azure (`az login`)
- Resource group created
- Port 3000 publicly accessible

**Option 3: AWS ECS Fargate**
- AWS CLI installed (`aws --version`)
- AWS credentials configured (`aws configure`)
- ECS cluster created
- VPC, subnets, security groups configured

### Deployment Steps

#### 1. Configure Environment Variables

Create `.env.grafana` file:

```bash
# Deployment target (local, azure, aws)
export DEPLOYMENT_TARGET="local"

# Grafana configuration
export GRAFANA_PORT="9002"
export GRAFANA_ADMIN_PASSWORD="Admin123!"

# MonitoringDB connection (from Part 1)
export MONITORINGDB_SERVER="sql-prod-01"
export MONITORINGDB_PORT="1433"
export MONITORINGDB_DATABASE="MonitoringDB"
export MONITORINGDB_USER="monitor_api"
export MONITORINGDB_PASSWORD="YourSecurePassword123"

# Client identification
export CLIENT_NAME="ArcTrade"
export CLIENT_ORG="ArcTrade"

# Azure-specific (if DEPLOYMENT_TARGET=azure)
export AZURE_RESOURCE_GROUP="rg-arctrade-monitoring"
export AZURE_CONTAINER_NAME="grafana-arctrade"
export AZURE_LOCATION="eastus"
export AZURE_DNS_LABEL="arctrade-monitor"

# AWS-specific (if DEPLOYMENT_TARGET=aws)
export AWS_CLUSTER="sql-monitor-cluster"
export AWS_TASK_DEFINITION="grafana-arctrade"
export AWS_SERVICE_NAME="grafana-arctrade"
```

#### 2. Run Deployment Script

**Local Deployment**:

```bash
# Load environment variables
source .env.grafana

# Deploy to local Docker
./deploy-grafana.sh
```

**Expected Output**:

```
========================================
SQL Monitor - Deploy Central Grafana Server
========================================

  ℹ  Client: ArcTrade
  ℹ  Target: local
  ℹ  MonitoringDB: sql-prod-01:1433/MonitoringDB

========================================
Validating Configuration
========================================

  ✓ Configuration valid

========================================
Creating Datasource Configuration
========================================

  ✓ Datasource configuration created

========================================
Deploying Grafana Locally (Docker Compose)
========================================

  Starting Grafana container...
  ✓ Grafana deployed locally on port 9002
  ℹ  Access at: http://localhost:9002
  ℹ  Username: admin
  ℹ  Password: Admin123!

========================================
Deployment Complete!
========================================

  ℹ  Next steps:
  ℹ  1. Access Grafana at the URL shown above
  ℹ  2. Login with admin / Admin123!
  ℹ  3. Verify MonitoringDB datasource connection
  ℹ  4. Open Dashboard Browser (should be home page)
  ℹ  5. Verify all 9 dashboards load correctly
```

**Azure Deployment**:

```bash
export DEPLOYMENT_TARGET="azure"
source .env.grafana
./deploy-grafana.sh
```

**AWS Deployment**:

```bash
export DEPLOYMENT_TARGET="aws"
source .env.grafana
./deploy-grafana.sh
```

#### 3. Verify Grafana Deployment

1. **Access Grafana**:
   - Local: http://localhost:9002
   - Azure: http://arctrade-monitor.eastus.azurecontainer.io:3000
   - AWS: (provided in deployment output)

2. **Login**: admin / Admin123! (or your configured password)

3. **Verify Datasource**:
   - Navigate to: Configuration → Data sources
   - Click "MonitoringDB"
   - Click "Save & test"
   - Should show: "Database Connection OK"

4. **Open Dashboard Browser**:
   - Should be the default home page
   - Shows 9 cards:
     - 📊 Instance Health
     - 🚀 Developer: Procedures
     - 🛠️ DBA: Wait Stats
     - 🔗 Blocking & Deadlocks
     - 📈 Query Store
     - 💾 Capacity Planning
     - 🔍 Code Browser
     - 💡 Insights
     - 🩺 DBCC Integrity
   - Scroll down to see blog panel with 12 SQL optimization articles

5. **Test Each Dashboard**:
   - Click each card to open dashboard
   - Verify data loads from all monitored servers
   - Check server filter dropdown works

---

## Multi-Client Deployment Example

### Scenario: Deploy for 3 Clients

**Client 1: ArcTrade**
- Central Server: sql-arctrade-01
- Monitored Servers: sql-arctrade-02, sql-arctrade-03, sql-arctrade-04
- Grafana: Local Docker (port 9002)

**Client 2: AcmeCorp**
- Central Server: sql-acme-01
- Monitored Servers: sql-acme-02, sql-acme-03
- Grafana: Azure Container Instances

**Client 3: WidgetCo**
- Central Server: sql-widget-01
- Monitored Servers: sql-widget-02, sql-widget-03, sql-widget-04, sql-widget-05
- Grafana: AWS ECS Fargate

### Step-by-Step for Each Client

**Client 1: ArcTrade**

```bash
# Part 1: Deploy MonitoringDB
cat > .env.arctrade-monitoring <<EOF
export CENTRAL_SERVER="sql-arctrade-01"
export CENTRAL_PORT="1433"
export CENTRAL_USER="sa"
export CENTRAL_PASSWORD="ArcTradeMonitor123"
export MONITORED_SERVERS="sql-arctrade-02,sql-arctrade-03,sql-arctrade-04"
export MONITORED_USER="monitor_collector"
export MONITORED_PASSWORD="CollectorPass123"
export CLIENT_NAME="ArcTrade"
export MONITOR_CENTRAL_SERVER="true"
EOF

source .env.arctrade-monitoring
./deploy-monitoring.sh

# Part 2: Deploy Grafana (Local Docker)
cat > .env.arctrade-grafana <<EOF
export DEPLOYMENT_TARGET="local"
export GRAFANA_PORT="9002"
export GRAFANA_ADMIN_PASSWORD="ArcTradeAdmin!"
export MONITORINGDB_SERVER="sql-arctrade-01"
export MONITORINGDB_USER="monitor_api"
export MONITORINGDB_PASSWORD="ArcTradeMonitor123"
export CLIENT_NAME="ArcTrade"
EOF

source .env.arctrade-grafana
./deploy-grafana.sh
```

**Client 2: AcmeCorp**

```bash
# Part 1: Deploy MonitoringDB
cat > .env.acme-monitoring <<EOF
export CENTRAL_SERVER="sql-acme-01"
export CENTRAL_PORT="1433"
export CENTRAL_USER="sa"
export CENTRAL_PASSWORD="AcmeMonitor456"
export MONITORED_SERVERS="sql-acme-02,sql-acme-03"
export MONITORED_USER="monitor_collector"
export MONITORED_PASSWORD="CollectorPass456"
export CLIENT_NAME="AcmeCorp"
export MONITOR_CENTRAL_SERVER="true"
EOF

source .env.acme-monitoring
./deploy-monitoring.sh

# Part 2: Deploy Grafana (Azure)
cat > .env.acme-grafana <<EOF
export DEPLOYMENT_TARGET="azure"
export GRAFANA_PORT="9002"
export GRAFANA_ADMIN_PASSWORD="AcmeAdmin!"
export MONITORINGDB_SERVER="sql-acme-01"
export MONITORINGDB_USER="monitor_api"
export MONITORINGDB_PASSWORD="AcmeMonitor456"
export CLIENT_NAME="AcmeCorp"
export AZURE_RESOURCE_GROUP="rg-acme-monitoring"
export AZURE_CONTAINER_NAME="grafana-acme"
export AZURE_LOCATION="eastus"
export AZURE_DNS_LABEL="acme-monitor"
EOF

source .env.acme-grafana
./deploy-grafana.sh
```

**Client 3: WidgetCo**

```bash
# Part 1: Deploy MonitoringDB
cat > .env.widget-monitoring <<EOF
export CENTRAL_SERVER="sql-widget-01"
export CENTRAL_PORT="1433"
export CENTRAL_USER="sa"
export CENTRAL_PASSWORD="WidgetMonitor789"
export MONITORED_SERVERS="sql-widget-02,sql-widget-03,sql-widget-04,sql-widget-05"
export MONITORED_USER="monitor_collector"
export MONITORED_PASSWORD="CollectorPass789"
export CLIENT_NAME="WidgetCo"
export MONITOR_CENTRAL_SERVER="true"
EOF

source .env.widget-monitoring
./deploy-monitoring.sh

# Part 2: Deploy Grafana (AWS ECS)
cat > .env.widget-grafana <<EOF
export DEPLOYMENT_TARGET="aws"
export GRAFANA_ADMIN_PASSWORD="WidgetAdmin!"
export MONITORINGDB_SERVER="sql-widget-01"
export MONITORINGDB_USER="monitor_api"
export MONITORINGDB_PASSWORD="WidgetMonitor789"
export CLIENT_NAME="WidgetCo"
export AWS_CLUSTER="sql-monitor-cluster"
export AWS_TASK_DEFINITION="grafana-widget"
export AWS_SERVICE_NAME="grafana-widget"
EOF

source .env.widget-grafana
./deploy-grafana.sh
```

---

## Maintenance

### Adding New Monitored Servers

After initial deployment, you can add new servers to monitoring:

**Option 1: Re-run deploy-monitoring.sh with updated MONITORED_SERVERS**

```bash
# Update .env.monitoring with new server list
export MONITORED_SERVERS="sql-prod-02,sql-prod-03,sql-prod-04,sql-prod-05,sql-prod-06"

# Re-run deployment (idempotent, won't break existing setup)
./deploy-monitoring.sh
```

**Option 2: Manual Registration**

```sql
-- On central server (MonitoringDB)
INSERT INTO dbo.Servers (ServerName, Environment, IsActive, MonitoringEnabled)
VALUES ('sql-prod-06', 'Production', 1, 1);

-- Create linked server
EXEC sp_addlinkedserver @server = 'sql-prod-06', @datasrc = 'sql-prod-06,1433';
EXEC sp_addlinkedsrvlogin @rmtsrvname = 'sql-prod-06', @rmtuser = 'monitor_collector', @rmtpassword = 'CollectorPass123';

-- On new server (sql-prod-06), create SQL Agent job
-- Use deploy-monitoring.sh output as template
```

### Removing Monitored Servers

```sql
-- On central server (MonitoringDB)
UPDATE dbo.Servers
SET IsActive = 0, MonitoringEnabled = 0
WHERE ServerName = 'sql-prod-06';

-- Drop linked server
EXEC sp_dropserver @server = 'sql-prod-06', @droplogins = 'droplogins';

-- On removed server, disable or delete SQL Agent job
EXEC msdb.dbo.sp_update_job @job_name = 'SQLMonitor_CollectMetrics', @enabled = 0;
```

### Updating Dashboards

```bash
# 1. Edit dashboard JSON files in dashboards/grafana/dashboards/

# 2. Restart Grafana to pick up changes
docker compose -f docker-compose-grafana.yml restart grafana

# Or for Azure/AWS, redeploy container with updated dashboard volume mount
```

### Database Maintenance

**Partition Management** (automatic, runs daily):

```sql
-- Check partition status
SELECT
    p.partition_number,
    p.rows,
    rv.value AS PartitionBoundary
FROM sys.partitions p
INNER JOIN sys.partition_functions pf ON pf.name = 'PF_MonitoringByMonth'
INNER JOIN sys.partition_range_values rv ON rv.function_id = pf.function_id
WHERE p.object_id = OBJECT_ID('dbo.PerformanceMetrics')
ORDER BY p.partition_number;
```

**Manual Partition Addition** (if automatic fails):

```sql
-- Add new partition for next month
EXEC dbo.usp_ManagePartitions @Action = 'ADD', @PartitionDate = '2025-12-01';
```

**Data Cleanup** (90 days retention by default):

```sql
-- Check old data size
SELECT
    SUM(ps.reserved_page_count) * 8.0 / 1024 / 1024 AS SizeGB,
    COUNT(*) AS RowCount
FROM dbo.PerformanceMetrics pm
INNER JOIN sys.dm_db_partition_stats ps ON ps.object_id = pm.ServerID
WHERE pm.CollectionTime < DATEADD(DAY, -90, GETUTCDATE());

-- Manual cleanup (if automatic fails)
EXEC dbo.usp_CleanupOldMetrics @RetentionDays = 90;
```

---

## Troubleshooting

### Issue: SQL Agent Job Not Running

**Symptoms**: No data in dashboards, LastCollectionTime is NULL

**Solutions**:

1. **Check SQL Agent Service**:
   ```sql
   -- Verify SQL Agent is running
   EXEC xp_servicecontrol 'QueryState', 'SQLServerAgent';
   ```

2. **Check Job Status**:
   ```sql
   SELECT
       j.name,
       j.enabled,
       ja.start_execution_date,
       ja.stop_execution_date,
       ja.last_executed_step_id,
       ja.last_executed_step_date
   FROM msdb.dbo.sysjobs j
   LEFT JOIN msdb.dbo.sysjobactivity ja ON j.job_id = ja.job_id
   WHERE j.name = 'SQLMonitor_CollectMetrics';
   ```

3. **Check Job History for Errors**:
   ```sql
   SELECT TOP 10 *
   FROM msdb.dbo.sysjobhistory
   WHERE job_id = (SELECT job_id FROM msdb.dbo.sysjobs WHERE name = 'SQLMonitor_CollectMetrics')
   ORDER BY run_date DESC, run_time DESC;
   ```

4. **Manually Run Job**:
   ```sql
   EXEC msdb.dbo.sp_start_job @job_name = 'SQLMonitor_CollectMetrics';
   ```

### Issue: Linked Server Connection Fails

**Symptoms**: "Login failed for user 'monitor_collector'" in job history

**Solutions**:

1. **Test Linked Server**:
   ```sql
   SELECT * FROM OPENQUERY([sql-prod-02], 'SELECT @@SERVERNAME');
   ```

2. **Verify Credentials**:
   ```sql
   -- Check linked server login mapping
   SELECT
       s.name AS LinkedServer,
       l.remote_name AS RemoteUser
   FROM sys.servers s
   LEFT JOIN sys.linked_logins l ON s.server_id = l.server_id
   WHERE s.name = 'sql-prod-02';
   ```

3. **Re-create Linked Server Login**:
   ```sql
   EXEC sp_droplinkedsrvlogin @rmtsrvname = 'sql-prod-02', @locallogin = NULL;
   EXEC sp_addlinkedsrvlogin
       @rmtsrvname = 'sql-prod-02',
       @useself = 'FALSE',
       @rmtuser = 'monitor_collector',
       @rmtpassword = 'CollectorPass123';
   ```

### Issue: Grafana Datasource Connection Fails

**Symptoms**: "Database Connection Error" in datasource test

**Solutions**:

1. **Check MonitoringDB Server Connectivity**:
   ```bash
   # From Grafana container
   docker exec -it sql-monitor-grafana-arctrade nc -zv sql-prod-01 1433
   ```

2. **Verify SQL User Permissions**:
   ```sql
   -- On MonitoringDB server
   SELECT
       dp.name AS UserName,
       dp.type_desc AS UserType,
       pe.permission_name,
       pe.state_desc
   FROM sys.database_principals dp
   LEFT JOIN sys.database_permissions pe ON dp.principal_id = pe.grantee_principal_id
   WHERE dp.name = 'monitor_api';
   ```

3. **Check Connection String in Grafana**:
   - Navigate to: Configuration → Data sources → MonitoringDB
   - Verify: Server, Port, Database, User
   - Test connection

4. **Check SQL Server Firewall**:
   ```sql
   -- On MonitoringDB server
   EXEC sp_configure 'remote access', 1;
   RECONFIGURE;

   -- Enable TCP/IP protocol in SQL Server Configuration Manager
   ```

### Issue: Dashboard Shows "No Data"

**Symptoms**: Dashboard loads but panels show "No data"

**Solutions**:

1. **Check Data in MonitoringDB**:
   ```sql
   -- Verify recent metrics exist
   SELECT TOP 10
       s.ServerName,
       pm.CollectionTime,
       pm.MetricCategory,
       COUNT(*) AS MetricCount
   FROM dbo.PerformanceMetrics pm
   INNER JOIN dbo.Servers s ON pm.ServerID = s.ServerID
   WHERE pm.CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE())
   GROUP BY s.ServerName, pm.CollectionTime, pm.MetricCategory
   ORDER BY pm.CollectionTime DESC;
   ```

2. **Check Time Range in Grafana**:
   - Ensure time range in top right covers period when data was collected
   - Try "Last 24 hours"

3. **Check Server Filter**:
   - Verify server filter dropdown shows your servers
   - Try "All" servers

4. **Check Dashboard Query**:
   - Edit panel
   - View query
   - Click "Run query" manually

---

## Cost Comparison

**SQL Monitor (Self-Hosted)**:
- MonitoringDB: $0 (uses existing SQL Server license)
- Grafana: $0 (OSS edition, Apache 2.0)
- Infrastructure:
  - Local Docker: $0
  - Azure Container Instances: ~$50/month (2 vCPU, 4GB RAM)
  - AWS ECS Fargate: ~$60/month (1 vCPU, 2GB RAM)
- **Total**: $0-$60/month ($0-$720/year)

**Commercial Alternatives**:
- SolarWinds DPA: $2,995/year per server (20 servers = $59,900/year)
- Redgate SQL Monitor: $1,495/year per server (20 servers = $29,900/year)
- Quest Spotlight: $1,295/year per server (20 servers = $25,900/year)

**Savings**: $25,000-$59,000 per year (for 20 servers)

---

## Security Best Practices

1. **Use Least-Privilege Accounts**:
   - Create dedicated SQL logins for monitoring
   - Grant only required permissions (VIEW SERVER STATE, EXECUTE)

2. **Secure Passwords**:
   - Use strong passwords (20+ characters)
   - Store in .env files (add to .gitignore)
   - Rotate passwords quarterly

3. **Network Security**:
   - Firewall rules: Allow only necessary ports
   - SQL Server: Encrypt connections (TrustServerCertificate=True for testing only)
   - Grafana: Use HTTPS in production

4. **Audit Logging**:
   - Monitor SQL Agent job failures
   - Track Grafana user access
   - Review MonitoringDB access logs

5. **Data Retention**:
   - 90 days default (configurable)
   - Consider compliance requirements (HIPAA, PCI-DSS, SOC 2)

---

## Support

For issues, feature requests, or questions:

1. Check this guide first
2. Review logs:
   - SQL Agent job history
   - Grafana logs: `docker logs sql-monitor-grafana-arctrade`
   - MonitoringDB error log
3. Contact: support@arctrade.com

---

**Last Updated**: 2025-10-29
**Version**: 2.0
**Author**: ArcTrade Technical Team
