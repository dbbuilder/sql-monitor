# SQL Server Monitor - Platform Architecture Decision

## Executive Summary

After analyzing requirements1-3.md, this document recommends the **optimal platform architecture** for a SQL Server monitoring solution that works seamlessly across:
- **On-Premises SQL Server** (2016+)
- **Azure SQL VM**
- **Azure SQL Managed Instance**
- **AWS EC2 SQL Server**
- **Azure SQL Database** (Phase 2)

**Recommended Architecture**: **Hybrid Container-Based Collection with Central Cloud Warehouse**

## Key Requirements Analysis

### Critical Requirements from requirements*.md

1. **Cross-Platform Support**: AWS EC2, Azure VM/MI, On-Prem, future Azure SQL DB
2. **Easy Deployment**: Install collectors on new networks with minimal effort
3. **Developer-Focused**: Stored procedure introspection, parameter sniffing, plan regression
4. **DBA-Focused**: Wait stats, blocking, deadlocks, I/O stalls
5. **No SaaS Dependencies**: Full control, no recurring licensing fees
6. **Minimal Overhead**: <3% CPU impact on monitored servers
7. **Historical Retention**: 90+ days detailed, 1+ year aggregated
8. **20-100 Instances**: Scalable to enterprise scale
9. **Extended Events + Query Store**: Deep telemetry capture
10. **RESTful API**: Integration with CI/CD and automation

## Platform Architecture Recommendation

### Central Data Warehouse: **Azure SQL Database (Hyperscale)**

**Why Azure SQL Database Hyperscale?**

| Requirement | Azure SQL DB Hyperscale | AWS RDS SQL | On-Prem SQL | Azure SQL MI |
|-------------|-------------------------|-------------|-------------|--------------|
| **Cross-Cloud Ingestion** | ✅ HTTPS/TLS from any cloud | ⚠️ VPN required for Azure | ⚠️ Complex networking | ⚠️ VPN for AWS |
| **Scalability (100+ instances)** | ✅ 100TB+, compute scales independently | ⚠️ Limited to 16TB | ❌ Hardware limits | ⚠️ 8-16TB typical |
| **Cost Efficiency** | ✅ Serverless option, storage $0.10/GB | ⚠️ Higher storage costs | ⚠️ Hardware/licensing | ⚠️ Expensive for warehouse |
| **Easy Setup** | ✅ 5 minutes via ARM template | ⚠️ AWS console setup | ❌ Hardware procurement | ⚠️ Complex provisioning |
| **Managed Identity** | ✅ Native Azure AD integration | ❌ IAM roles only | ❌ Manual auth | ✅ Azure AD |
| **Backup/DR** | ✅ Automated point-in-time recovery | ⚠️ Manual configuration | ❌ Manual backup strategy | ✅ Automated |
| **Global Availability** | ✅ Read replicas in any region | ⚠️ Limited regions | ❌ Single location | ⚠️ Limited regions |

**Decision**: **Azure SQL Database Hyperscale (General Purpose tier for cost, Hyperscale for 20+ instances)**

### Data Collection Agent: **Containerized PowerShell/T-SQL Collector**

**Why Containerized Collectors?**

| Approach | Pros | Cons | Verdict |
|----------|------|------|---------|
| **SQL Agent Jobs Only** | Native, no external dependencies | ❌ Won't work on Azure SQL DB, complex deployment, no version control | ❌ Not cross-platform |
| **.NET Core Service** | Cross-platform, modern | ❌ Requires .NET runtime, more overhead | ⚠️ Overkill for lightweight collection |
| **PowerShell Scripts + Scheduler** | Simple, cross-platform | ❌ Different schedulers per OS, hard to manage | ⚠️ Inconsistent |
| **🏆 Docker Container (PowerShell + dbatools)** | ✅ Identical deployment everywhere, version controlled, lightweight, scheduler built-in | Requires Docker (widely available) | ✅ **WINNER** |

**Collector Stack**:
- **Base Image**: `mcr.microsoft.com/powershell:lts-alpine-3.18` (lightweight Linux)
- **Collection Logic**: PowerShell scripts using `dbatools` module
- **Scheduler**: Built-in cron via `cronie` package
- **API Push**: HTTPS POST to Azure Function (Data Collector API)
- **Local Cache**: SQLite database for offline buffering when network unavailable

**Deployment Options**:
1. **Docker Compose** (on-prem, EC2, Azure VM)
2. **Azure Container Instances** (serverless, for Azure-native monitoring)
3. **Kubernetes** (Phase 2, for large-scale 50+ instance deployments)

### Data Collector API: **Azure Functions (Consumption Plan)**

**Why Azure Functions?**

- **Cost**: $0.20/million requests (essentially free for monitoring workload)
- **Security**: Managed Identity, no exposed SQL endpoints
- **Cross-Cloud**: HTTPS endpoint reachable from AWS/On-Prem via public internet (with API key auth)
- **Scalability**: Auto-scales to handle burst traffic during collection windows
- **Integration**: Native Azure SQL connection via Managed Identity

**Alternative Considered**: AWS API Gateway + Lambda
- **Rejected**: Adds complexity with cross-cloud auth, higher cost, dual implementation burden

### Visualization: **Grafana (OSS) + Power BI Templates**

**Why Grafana?**
- **Open Source**: No licensing costs, huge community
- **SQL Plugin**: Native Azure SQL data source
- **Time-Series**: Built for metrics visualization
- **Developer-Friendly**: JSON dashboards in version control

**Why Power BI Templates?**
- **DBA-Friendly**: Enterprise standard for reporting
- **Azure Integration**: Native Azure AD, published to Power BI Service
- **Executive Reporting**: Better for scheduled reports and executive summaries

**Decision**: Provide **both** - Grafana for real-time operational dashboards, Power BI for reporting/analysis.

## Installation Architecture: "One-Command Deployment"

### Design Goal: **Deploy monitoring to a new SQL Server in <5 minutes**

### Installation Script: `install-sql-monitor.ps1`

```powershell
# Example usage:
./install-sql-monitor.ps1 `
    -ServerName "sql-prod-01.company.com" `
    -EnvironmentType "Production" `
    -CollectorApiUrl "https://sql-monitor-api.azurewebsites.net/api/ingest" `
    -ApiKey "xxxxx" `
    -DeploymentMode "Docker"
```

**What it does**:
1. **Validates** SQL Server connectivity and version (2016+)
2. **Creates** monitoring user with minimal permissions (VIEW SERVER STATE, VIEW DATABASE STATE)
3. **Configures** Extended Events sessions (deadlocks, blocking, query performance)
4. **Enables** Query Store on all user databases (if not already enabled)
5. **Deploys** Docker container for local collection agent OR
6. **Deploys** SQL Agent jobs for pure T-SQL collection (fallback)
7. **Registers** server in central inventory table via API call
8. **Tests** data flow end-to-end

**Deployment Time**: 3-5 minutes per server

### Multi-Server Deployment: `deploy-fleet.ps1`

```powershell
# Deploy to 20 servers from CSV
./deploy-fleet.ps1 -ServerListCsv "servers.csv" -Parallelism 5
```

Reads CSV with server list and deploys collectors in parallel (5 at a time).

## Detailed Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    MONITORED SQL SERVERS                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  On-Prem SQL 2019        AWS EC2 SQL 2022       Azure SQL VM   │
│  ┌──────────────┐        ┌──────────────┐       ┌───────────┐  │
│  │ Extended     │        │ Extended     │       │ Extended  │  │
│  │ Events       │        │ Events       │       │ Events    │  │
│  │ Query Store  │        │ Query Store  │       │ Query St. │  │
│  │ DMVs         │        │ DMVs         │       │ DMVs      │  │
│  └──────┬───────┘        └──────┬───────┘       └─────┬─────┘  │
│         │                       │                     │        │
│    ┌────▼─────┐           ┌────▼─────┐         ┌─────▼────┐   │
│    │ Collector│           │ Collector│         │Collector │   │
│    │Container │           │Container │         │Container │   │
│    │(Docker)  │           │(Docker)  │         │(Docker)  │   │
│    └────┬─────┘           └────┬─────┘         └─────┬────┘   │
│         │                      │                     │        │
└─────────┼──────────────────────┼─────────────────────┼────────┘
          │                      │                     │
          │ HTTPS POST           │ HTTPS POST          │ HTTPS POST
          │ (every 5 min)        │ (every 5 min)       │ (every 5 min)
          │                      │                     │
          └──────────┬───────────┴─────────────────────┘
                     │
                     ▼
         ┌───────────────────────────┐
         │  Azure Function App       │
         │  (Data Collector API)     │
         │  - Validates API key      │
         │  - Writes to staging      │
         │  - Managed Identity auth  │
         └──────────┬────────────────┘
                    │
                    ▼
         ┌────────────────────────────────┐
         │ Azure SQL Database (Hyperscale)│
         │ - Monitoring Database Schema   │
         │ - Partitioned time-series      │
         │ - Columnstore indexes          │
         │ - 90-day retention             │
         └──────────┬─────────────────────┘
                    │
        ┌───────────┴──────────┬──────────────────┐
        │                      │                  │
        ▼                      ▼                  ▼
┌───────────────┐    ┌──────────────────┐  ┌──────────────┐
│ Grafana OSS   │    │ Power BI Desktop │  │ Alert Engine │
│ Dashboards    │    │ Templates        │  │ (Function)   │
│ (Real-time)   │    │ (Reports)        │  │ - Email      │
└───────────────┘    └──────────────────┘  │ - Slack      │
                                           │ - Webhook    │
                                           └──────────────┘
```

## Collector Container Architecture

### Container Components

```dockerfile
FROM mcr.microsoft.com/powershell:lts-alpine-3.18

# Install SQL Server tools
RUN apk add --no-cache \
    curl \
    unixodbc \
    freetds \
    cronie

# Install PowerShell modules
RUN pwsh -Command "Install-Module -Name dbatools -Force -AllowClobber -Scope AllUsers"
RUN pwsh -Command "Install-Module -Name SqlServer -Force -AllowClobber -Scope AllUsers"

# Copy collection scripts
COPY scripts/ /app/scripts/
COPY config/crontab /etc/crontabs/root

# Start cron in foreground
CMD ["crond", "-f", "-l", "2"]
```

### Collection Script: `collect-metrics.ps1`

```powershell
# Runs every 5 minutes via cron
param(
    [string]$ServerName = $env:SQL_SERVER,
    [string]$ApiUrl = $env:COLLECTOR_API_URL,
    [string]$ApiKey = $env:API_KEY
)

# Collect DMV snapshots
$metrics = @{
    Timestamp = (Get-Date).ToUniversalTime()
    ServerName = $ServerName
    WaitStats = Get-DbaWaitStatistic -SqlInstance $ServerName
    PerfCounters = Get-DbaPerformanceCounter -SqlInstance $ServerName
    ProcStats = Get-DbaProcedureCache -SqlInstance $ServerName | Select -First 100
    QueryStoreStats = Get-DbaQueryStoreTopQuery -SqlInstance $ServerName
    BlockingChains = Get-DbaProcess -SqlInstance $ServerName | Where IsBlocked
}

# Push to API
Invoke-RestMethod -Uri "$ApiUrl/ingest" `
    -Method POST `
    -Headers @{ "X-API-Key" = $ApiKey } `
    -Body ($metrics | ConvertTo-Json -Depth 5) `
    -ContentType "application/json"
```

### Crontab Configuration

```cron
# Metrics collection every 5 minutes
*/5 * * * * pwsh /app/scripts/collect-metrics.ps1

# Extended Event export every 15 minutes
*/15 * * * * pwsh /app/scripts/export-extended-events.ps1

# Query Store snapshot every 10 minutes
*/10 * * * * pwsh /app/scripts/collect-querystore.ps1

# Health check every 1 minute (fast local DMV check)
* * * * * pwsh /app/scripts/health-check.ps1
```

## Database Schema Design

### MonitoringDB Schema

```sql
-- Server inventory
CREATE TABLE dbo.Servers (
    ServerID INT IDENTITY PRIMARY KEY,
    ServerName NVARCHAR(256) NOT NULL UNIQUE,
    EnvironmentType NVARCHAR(50), -- Production, Staging, Dev
    Platform NVARCHAR(50), -- OnPrem, AzureVM, AzureMI, AWSEC2
    SqlVersion NVARCHAR(50),
    CollectorVersion NVARCHAR(20),
    LastHeartbeat DATETIME2,
    IsActive BIT DEFAULT 1,
    CreatedDate DATETIME2 DEFAULT SYSUTCDATETIME()
);

-- Time-series metrics (partitioned by month)
CREATE TABLE dbo.PerformanceMetrics (
    MetricID BIGINT IDENTITY NOT NULL,
    ServerID INT NOT NULL,
    CollectionTime DATETIME2 NOT NULL,
    MetricCategory NVARCHAR(50), -- Memory, CPU, IO, Wait, Query
    MetricName NVARCHAR(100),
    MetricValue DECIMAL(18,4),
    CONSTRAINT PK_PerformanceMetrics PRIMARY KEY (CollectionTime, MetricID)
) ON PS_MonitoringByMonth(CollectionTime);

CREATE COLUMNSTORE INDEX IX_PerformanceMetrics_CS
    ON dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue);

-- Stored procedure performance
CREATE TABLE dbo.ProcedureStats (
    ProcStatID BIGINT IDENTITY NOT NULL,
    ServerID INT NOT NULL,
    DatabaseName NVARCHAR(128),
    SchemaName NVARCHAR(128),
    ProcedureName NVARCHAR(128),
    CollectionTime DATETIME2 NOT NULL,
    ExecutionCount BIGINT,
    TotalWorkerTime BIGINT,
    TotalElapsedTime BIGINT,
    TotalLogicalReads BIGINT,
    AvgDurationMs AS (TotalElapsedTime / NULLIF(ExecutionCount, 0) / 1000.0),
    CONSTRAINT PK_ProcedureStats PRIMARY KEY (CollectionTime, ProcStatID)
) ON PS_MonitoringByMonth(CollectionTime);

-- Query Store integration
CREATE TABLE dbo.QueryStoreSnapshots (
    SnapshotID BIGINT IDENTITY NOT NULL,
    ServerID INT NOT NULL,
    DatabaseName NVARCHAR(128),
    QueryID BIGINT,
    PlanID BIGINT,
    CollectionTime DATETIME2 NOT NULL,
    ExecutionCount BIGINT,
    AvgDurationMs DECIMAL(18,2),
    AvgCPUMs DECIMAL(18,2),
    AvgLogicalReads BIGINT,
    QueryText NVARCHAR(MAX),
    CONSTRAINT PK_QueryStoreSnapshots PRIMARY KEY (CollectionTime, SnapshotID)
) ON PS_MonitoringByMonth(CollectionTime);

-- Wait statistics
CREATE TABLE dbo.WaitStatistics (
    WaitStatID BIGINT IDENTITY NOT NULL,
    ServerID INT NOT NULL,
    CollectionTime DATETIME2 NOT NULL,
    WaitType NVARCHAR(100),
    WaitTimeMs BIGINT,
    WaitCount BIGINT,
    SignalWaitTimeMs BIGINT,
    CONSTRAINT PK_WaitStatistics PRIMARY KEY (CollectionTime, WaitStatID)
) ON PS_MonitoringByMonth(CollectionTime);

-- Blocking and deadlock events
CREATE TABLE dbo.BlockingEvents (
    BlockingEventID BIGINT IDENTITY PRIMARY KEY,
    ServerID INT NOT NULL,
    EventTime DATETIME2 NOT NULL,
    BlockedSPID INT,
    BlockingSPID INT,
    BlockedProcedure NVARCHAR(256),
    BlockingProcedure NVARCHAR(256),
    WaitTimeSeconds INT,
    BlockingChainXML XML
);

CREATE TABLE dbo.DeadlockEvents (
    DeadlockEventID BIGINT IDENTITY PRIMARY KEY,
    ServerID INT NOT NULL,
    EventTime DATETIME2 NOT NULL,
    DeadlockGraphXML XML,
    VictimProcedure NVARCHAR(256),
    ProcessList XML
);
```

## Easy Installation Guide

### Phase 1: Setup Central Warehouse (One-Time, 15 minutes)

#### Step 1: Deploy Azure Resources

```bash
# Clone repository
git clone https://github.com/yourorg/sql-monitor.git
cd sql-monitor

# Deploy Azure infrastructure (uses Bicep/ARM template)
az deployment group create \
    --resource-group rg-sql-monitor-prod \
    --template-file infrastructure/azure-deploy.bicep \
    --parameters @infrastructure/parameters.prod.json

# Output:
# - Azure SQL Database (Hyperscale or General Purpose)
# - Azure Function App (Consumption plan)
# - Storage Account (for Extended Event file staging)
# - Application Insights (telemetry)
```

**Resources Created** (cost estimate: $150-300/month for 20 servers):
- Azure SQL Database (GP Gen5 8 vCore): ~$200/month
- Azure Function (Consumption): ~$5/month
- Storage (100GB): ~$2/month
- Application Insights: ~$5/month

#### Step 2: Initialize Database Schema

```bash
# Run database initialization script
sqlcmd -S sql-monitor-prod.database.windows.net \
    -d MonitoringDB \
    -U sqladmin \
    -P <password> \
    -i database/01-create-schema.sql

# Create partitions for 12 months
sqlcmd -S sql-monitor-prod.database.windows.net \
    -d MonitoringDB \
    -U sqladmin \
    -P <password> \
    -i database/02-create-partitions.sql

# Create stored procedures
sqlcmd -S sql-monitor-prod.database.windows.net \
    -d MonitoringDB \
    -U sqladmin \
    -P <password> \
    -i database/03-create-procedures.sql
```

#### Step 3: Deploy Azure Function (Data Collector API)

```bash
cd collector-api
func azure functionapp publish sql-monitor-api-prod

# Get API key
az functionapp keys list \
    --name sql-monitor-api-prod \
    --resource-group rg-sql-monitor-prod \
    --query "functionKeys.default" -o tsv
```

#### Step 4: Deploy Grafana Dashboards

```bash
# Option A: Use Grafana Cloud (free tier: 10k series, 14-day retention)
# Import dashboards from grafana/dashboards/*.json

# Option B: Self-host Grafana in Azure Container Instance
az deployment group create \
    --resource-group rg-sql-monitor-prod \
    --template-file infrastructure/grafana-deploy.bicep
```

### Phase 2: Deploy Collector to SQL Servers (3-5 minutes per server)

#### Installation Script

```powershell
# Download and run installer
Invoke-WebRequest -Uri "https://github.com/yourorg/sql-monitor/releases/latest/download/install-sql-monitor.ps1" `
    -OutFile "install-sql-monitor.ps1"

# Install on local SQL Server
./install-sql-monitor.ps1 `
    -ServerName "localhost" `
    -EnvironmentType "Production" `
    -CollectorApiUrl "https://sql-monitor-api-prod.azurewebsites.net" `
    -ApiKey "xxxxx" `
    -DeploymentMode "Docker"
```

**What Happens**:
1. ✅ Checks Docker is installed (or installs it)
2. ✅ Creates monitoring user: `sqlmon_collector` with VIEW SERVER STATE permission
3. ✅ Configures Extended Events sessions
4. ✅ Enables Query Store on all user databases
5. ✅ Pulls Docker image: `youracr.azurecr.io/sql-monitor-collector:latest`
6. ✅ Creates `docker-compose.yml` with connection details
7. ✅ Starts collector container
8. ✅ Registers server in central inventory
9. ✅ Tests data flow (waits for first metrics push)

#### Bulk Deployment

```powershell
# Create servers.csv
@"
ServerName,EnvironmentType,Platform
sql-prod-01.company.com,Production,OnPrem
sql-prod-02.company.com,Production,AzureVM
sql-prod-03.ec2.internal,Production,AWSEC2
"@ | Out-File servers.csv

# Deploy to all
./deploy-fleet.ps1 `
    -ServerListCsv "servers.csv" `
    -CollectorApiUrl "https://sql-monitor-api-prod.azurewebsites.net" `
    -ApiKey "xxxxx" `
    -Parallelism 5
```

## Cost Analysis (20 Servers for 1 Year)

| Component | Monthly Cost | Annual Cost |
|-----------|--------------|-------------|
| Azure SQL Database (GP 8 vCore) | $200 | $2,400 |
| Azure Function (Consumption) | $5 | $60 |
| Storage (500GB data) | $10 | $120 |
| Application Insights | $10 | $120 |
| Grafana Cloud (10k series) | $0 (free tier) | $0 |
| **Total** | **$225** | **$2,700** |

**vs. Commercial Solutions**:
- SolarWinds DPA: $1,995 per instance = **$39,900/year** for 20 servers
- Redgate SQL Monitor: $1,495 per instance = **$29,900/year**
- **Savings: $27,200 - $37,200/year**

## Decision Summary

### ✅ Chosen Architecture

1. **Central Warehouse**: Azure SQL Database (Hyperscale for 20+ instances)
2. **Collector**: Docker containers with PowerShell + dbatools
3. **API**: Azure Functions (Consumption plan)
4. **Visualization**: Grafana OSS + Power BI templates
5. **Alerting**: Azure Function with Logic App integration

### ✅ Why This Stack Wins

| Requirement | How Architecture Addresses |
|-------------|---------------------------|
| **Cross-platform** | Docker runs on Windows/Linux, any cloud |
| **Easy installation** | One script deploys collector in 3-5 minutes |
| **Developer focus** | Procedure stats, Query Store, parameter sniffing |
| **DBA focus** | Wait stats, blocking, deadlocks, I/O metrics |
| **No SaaS** | Fully self-hosted (except optional Grafana Cloud) |
| **Minimal overhead** | Containerized collection <1% CPU, API push async |
| **90+ day retention** | Partitioned tables with automated archival |
| **20-100 instances** | Hyperscale scales to 100TB, Function auto-scales |
| **Extended Events** | Native PowerShell XE export via dbatools |
| **RESTful API** | Azure Function with OpenAPI spec |

### 🚀 Next Steps

1. Review and approve this architecture
2. Provision Azure resources (15 minutes)
3. Deploy to 3 pilot servers (1 on-prem, 1 Azure, 1 AWS) - 15 minutes
4. Validate data collection for 7 days
5. Deploy to production fleet
6. Build Grafana dashboards
7. Configure alerting rules

## Alternative Architectures Considered (and Why Rejected)

### ❌ On-Prem Central Warehouse
- **Rejected**: Requires VPN from AWS, hardware procurement, manual HA setup, no auto-scaling

### ❌ AWS-Based Warehouse (RDS or EC2)
- **Rejected**: More expensive for storage, harder for Azure VM/MI to reach, less managed services

### ❌ Pure SQL Agent Jobs (No Containers)
- **Rejected**: Won't work on Azure SQL DB (Phase 2), inconsistent across platforms, hard to version control

### ❌ Commercial SaaS (Datadog, New Relic)
- **Rejected**: $1000+/month, limited SQL-specific features, no stored procedure introspection, data retention limits

### ❌ Open Source Forks (SQLWATCH, DBADash)
- **Considered**: Excellent starting point, but lack cross-cloud deployment automation and developer-focused features (parameter sniffing, procedure regression analysis)
- **Decision**: Use as inspiration, build custom for specific requirements
