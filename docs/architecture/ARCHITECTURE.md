# SQL Server Monitor - Technical Architecture

## Architecture Overview

**Design Philosophy**: Self-hosted, minimal infrastructure, open-source only, runs anywhere.

### Core Principles

1. **Zero Cloud Lock-In**: Deploy on-prem, any cloud, or hybrid
2. **Minimal Containers**: 1-2 containers max (UI+API combined or separate)
3. **Self-Hosted Database**: MonitoringDB on one of your existing SQL Servers
4. **Open Source Only**: No commercial licenses (Grafana, ASP.NET Core, PostgreSQL option)
5. **Simple Deployment**: `docker-compose up` and you're running

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                     MONITORED SQL SERVERS                           │
│  (Production workload + one server hosts MonitoringDB)              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  SQL-PROD-01              SQL-PROD-02              SQL-PROD-03      │
│  ┌──────────────┐        ┌──────────────┐        ┌──────────────┐  │
│  │ Extended     │        │ Extended     │        │ MonitoringDB │  │
│  │ Events       │        │ Events       │        │ (Warehouse)  │  │
│  │ Query Store  │        │ Query Store  │        │              │  │
│  │ DMVs         │        │ DMVs         │        │ + Extended   │  │
│  └──────┬───────┘        └──────┬───────┘        │   Events     │  │
│         │                       │                │ + Query St.  │  │
│         │                       │                │ + DMVs       │  │
│         │                       │                └──────┬───────┘  │
│         │ Every 5 min           │ Every 5 min           │          │
│         │ (local SP call)       │ (local SP call)       │ (local)  │
└─────────┼───────────────────────┼───────────────────────┼──────────┘
          │                       │                       │
          │ Remote-exec SP        │ Remote-exec SP        │ Local SP
          │ via Linked Server     │ via Linked Server     │
          │                       │                       │
          └───────────┬───────────┴───────────────────────┘
                      │ All metrics stored in MonitoringDB
                      │ via stored procedures only
                      ▼
          ┌─────────────────────────────────────┐
          │   SQL-PROD-03 (hosts MonitoringDB)  │
          │   - Partitioned tables              │
          │   - Columnstore indexes             │
          │   - Stored procedures for ETL       │
          │   - 90-day retention                │
          └───────────────┬─────────────────────┘
                          │
                          │ TCP 5000 (HTTP)
                          │ SQL Connection (TLS)
                          │
          ┌───────────────▼─────────────────────┐
          │  DOCKER HOST (anywhere)             │
          │                                     │
          │  ┌───────────────────────────────┐  │
          │  │  Container: sql-monitor       │  │
          │  │                               │  │
          │  │  ┌─────────────────────────┐  │  │
          │  │  │  ASP.NET Core API       │  │  │
          │  │  │  - REST endpoints       │  │  │
          │  │  │  - Calls SPs only       │  │  │
          │  │  │  - Port 5000            │  │  │
          │  │  └────────┬────────────────┘  │  │
          │  │           │                   │  │
          │  │  ┌────────▼────────────────┐  │  │
          │  │  │  Grafana OSS            │  │  │
          │  │  │  - SQL datasource       │  │  │
          │  │  │  - Dashboards           │  │  │
          │  │  │  - Port 3000            │  │  │
          │  │  └─────────────────────────┘  │  │
          │  │                               │  │
          │  │  Environment:                 │  │
          │  │  - DB_CONNECTION_STRING       │  │
          │  │  - MONITORING_SERVERS (JSON)  │  │
          │  └───────────────────────────────┘  │
          └─────────────────────────────────────┘
                          │
                          │ Port 3000 (Grafana)
                          │ Port 5000 (API)
                          ▼
                   ┌──────────────┐
                   │   Users      │
                   │  (Browser)   │
                   └──────────────┘
```

## Component Architecture

### 1. Data Collection Layer

**Collection Method**: SQL Agent Jobs (no external agents needed!)

Each monitored SQL Server runs lightweight SQL Agent jobs that call stored procedures in MonitoringDB:

```sql
-- Job: Collect_Metrics (runs every 5 minutes)
EXEC [MonitoringDB].[dbo].[usp_CollectMetrics_RemoteServer]
    @ServerName = @@SERVERNAME

-- This SP uses OPENQUERY or sp_executesql to gather:
-- - DMV snapshots (sys.dm_exec_procedure_stats, sys.dm_os_wait_stats, etc.)
-- - Extended Event exports
-- - Query Store snapshots
```

**Key Advantages**:
- ✅ No Docker/PowerShell needed on monitored servers
- ✅ Uses existing SQL Agent infrastructure
- ✅ Native SQL Server-to-SQL Server communication
- ✅ Linked servers or remote connections
- ✅ Minimal overhead (<1% CPU)

**Configuration Options**:

| Method | When to Use | Setup |
|--------|-------------|-------|
| **Linked Servers** | Same domain/network | Create linked server from each SQL to MonitoringDB server |
| **Direct Connection** | Cross-domain | Store credentials in MonitoringDB, use `sp_executesql` with explicit auth |
| **Always Encrypted** | High security | Use certificate-based authentication |

### 2. Data Warehouse (MonitoringDB)

**Location**: Any one of your existing SQL Servers (recommend least-critical production or dedicated monitoring instance)

**Database Schema**:

```sql
-- Core tables
dbo.Servers                    -- Inventory of monitored instances
dbo.PerformanceMetrics         -- Time-series metrics (partitioned monthly)
dbo.ProcedureStats             -- Stored procedure performance
dbo.QueryStoreSnapshots        -- Query Store data
dbo.WaitStatistics             -- Wait stats
dbo.BlockingEvents             -- Blocking chains
dbo.DeadlockEvents             -- Deadlock graphs
dbo.IndexRecommendations       -- Missing/unused indexes
dbo.ConfigurationHistory       -- Server config changes

-- Partitioning scheme
CREATE PARTITION FUNCTION PF_MonitoringByMonth (DATETIME2)
AS RANGE RIGHT FOR VALUES (
    '2025-01-01', '2025-02-01', '2025-03-01', ... -- 12 months
);

CREATE PARTITION SCHEME PS_MonitoringByMonth
AS PARTITION PF_MonitoringByMonth ALL TO ([PRIMARY]);

-- Columnstore for fast aggregation
CREATE COLUMNSTORE INDEX IX_PerformanceMetrics_CS
ON dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
ON PS_MonitoringByMonth(CollectionTime);
```

**Storage Requirements**:

| Servers Monitored | Daily Data | 90-Day Total | With Compression |
|-------------------|------------|--------------|------------------|
| 5 servers | ~500 MB | ~45 GB | ~10 GB |
| 20 servers | ~2 GB | ~180 GB | ~40 GB |
| 50 servers | ~5 GB | ~450 GB | ~100 GB |

**Data Retention Strategy**:

```sql
-- Automatic partition sliding window
-- Daily job: Drop oldest partition, add new partition
EXEC dbo.usp_ManagePartitions
    @RetentionDays = 90,
    @ArchiveToFileShare = 'NULL\\backups\\monitoring-archive'
```

### 3. API Layer (ASP.NET Core)

**Technology**: ASP.NET Core 8.0 (LTS), runs in Docker

**Port**: 5000 (HTTP) or 5001 (HTTPS with self-signed cert)

**Architecture Pattern**: Thin API, business logic in SQL stored procedures

```
api/
├── Program.cs                    # Startup and DI configuration
├── Controllers/
│   ├── ServersController.cs      # GET /api/servers
│   ├── MetricsController.cs      # GET /api/metrics/{serverId}
│   ├── AlertsController.cs       # GET /api/alerts
│   └── HealthController.cs       # GET /health
├── Services/
│   ├── ISqlService.cs            # Interface for SQL operations
│   └── SqlService.cs             # Executes stored procedures via Dapper
├── Models/
│   ├── ServerModel.cs
│   ├── MetricModel.cs
│   └── AlertModel.cs
└── appsettings.json
    {
      "ConnectionStrings": {
        "MonitoringDB": "Server=sql-prod-03;Database=MonitoringDB;..."
      },
      "MonitoredServers": [
        { "ServerName": "sql-prod-01", "Environment": "Production" },
        { "ServerName": "sql-prod-02", "Environment": "Production" }
      ]
    }
```

**Data Access Pattern** (Dapper for simplicity):

```csharp
// Services/SqlService.cs
public async Task<IEnumerable<ServerModel>> GetServers()
{
    using var connection = new SqlConnection(_connectionString);
    return await connection.QueryAsync<ServerModel>(
        "dbo.usp_GetServers",
        commandType: CommandType.StoredProcedure
    );
}

public async Task<IEnumerable<MetricModel>> GetMetrics(int serverId, DateTime startTime)
{
    using var connection = new SqlConnection(_connectionString);
    return await connection.QueryAsync<MetricModel>(
        "dbo.usp_GetMetricHistory",
        new { ServerId = serverId, StartTime = startTime },
        commandType: CommandType.StoredProcedure
    );
}
```

**Why Dapper?**
- ✅ Open source (Apache 2.0 license)
- ✅ Minimal overhead (essentially raw ADO.NET)
- ✅ Perfect for stored procedure-only pattern
- ✅ No EF Core complexity

### 4. UI Layer (Grafana OSS)

**Technology**: Grafana OSS 10.x (Apache 2.0 license)

**Port**: 3000

**Data Sources**:
1. **Primary**: Direct SQL connection to MonitoringDB
2. **Secondary**: API endpoint (for some dashboards)

**Dashboard Categories**:

```
grafana/dashboards/
├── 01-instance-health.json           # Overview of all servers
├── 02-developer-procedures.json      # Top procedures by resource
├── 03-dba-waits.json                 # Wait statistics analysis
├── 04-blocking-deadlocks.json        # Real-time blocking chains
├── 05-query-store.json               # Plan regressions
└── 06-capacity-planning.json         # Growth trends
```

**Grafana Configuration**:

```yaml
# grafana/provisioning/datasources/monitoringdb.yaml
apiVersion: 1
datasources:
  - name: MonitoringDB
    type: mssql
    url: sql-prod-03:1433
    database: MonitoringDB
    user: grafana_reader
    secureJsonData:
      password: ${GRAFANA_SQL_PASSWORD}
    jsonData:
      encrypt: true
      sslmode: require
```

**Example Dashboard Query** (SQL):

```sql
-- Top 10 procedures by average duration (last 24 hours)
SELECT TOP 10
    ServerName,
    DatabaseName,
    ProcedureName,
    AVG(AvgDurationMs) AS AvgDuration,
    SUM(ExecutionCount) AS TotalExecutions
FROM dbo.vw_ProcedureStats_24h
WHERE $__timeFilter(CollectionTime)
GROUP BY ServerName, DatabaseName, ProcedureName
ORDER BY AvgDuration DESC
```

### 5. Container Deployment

**Option A: Single Container** (Simplest)

```dockerfile
# Dockerfile (multi-stage)
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /app
COPY api/ ./
RUN dotnet publish -c Release -o out

FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
COPY --from=build /app/out .

# Install Grafana
RUN apt-get update && apt-get install -y wget
RUN wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -
RUN echo "deb https://packages.grafana.com/oss/deb stable main" | tee -a /etc/apt/sources.list.d/grafana.list
RUN apt-get update && apt-get install -y grafana

# Copy Grafana dashboards
COPY dashboards/grafana/ /etc/grafana/provisioning/dashboards/

# Startup script
COPY docker-entrypoint.sh /
RUN chmod +x /docker-entrypoint.sh

EXPOSE 3000 5000
ENTRYPOINT ["/docker-entrypoint.sh"]
```

```bash
# docker-entrypoint.sh
#!/bin/bash
# Start Grafana in background
grafana-server --homepath=/usr/share/grafana &

# Start API in foreground
exec dotnet SqlServerMonitor.Api.dll
```

```yaml
# docker-compose.yml
version: '3.8'
services:
  sql-monitor:
    build: .
    container_name: sql-monitor
    ports:
      - "3000:3000"  # Grafana
      - "5000:5000"  # API
    environment:
      - ConnectionStrings__MonitoringDB=Server=sql-prod-03;Database=MonitoringDB;User Id=monitor_api;Password=${DB_PASSWORD};TrustServerCertificate=True;
      - GRAFANA_SQL_PASSWORD=${DB_PASSWORD}
    restart: unless-stopped
    volumes:
      - grafana-data:/var/lib/grafana
      - ./dashboards:/etc/grafana/provisioning/dashboards

volumes:
  grafana-data:
```

**Option B: Two Containers** (Cleaner separation)

```yaml
# docker-compose.yml
version: '3.8'

services:
  api:
    build: ./api
    container_name: sql-monitor-api
    ports:
      - "5000:5000"
    environment:
      - ConnectionStrings__MonitoringDB=Server=sql-prod-03;Database=MonitoringDB;User Id=monitor_api;Password=${DB_PASSWORD};TrustServerCertificate=True;
    restart: unless-stopped

  grafana:
    image: grafana/grafana-oss:10.2.0
    container_name: sql-monitor-ui
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
      - GF_INSTALL_PLUGINS=
      - GRAFANA_SQL_PASSWORD=${DB_PASSWORD}
    volumes:
      - grafana-data:/var/lib/grafana
      - ./dashboards/grafana/provisioning:/etc/grafana/provisioning
    restart: unless-stopped
    depends_on:
      - api

volumes:
  grafana-data:
```

**Deployment**:

```bash
# 1. Create .env file
cat > .env <<EOF
DB_PASSWORD=YourSecurePassword123
GRAFANA_ADMIN_PASSWORD=AdminPassword456
EOF

# 2. Start containers
docker-compose up -d

# 3. Access
# Grafana: http://localhost:3000 (admin / AdminPassword456)
# API: http://localhost:5000/swagger
```

## Data Flow Architecture

### Collection Flow

```
┌─────────────────────────────────────────────────────────────┐
│ Step 1: SQL Agent Job (on each monitored server)           │
│ Runs every 5 minutes                                        │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ Step 2: Execute remote stored procedure                    │
│                                                             │
│ -- On SQL-PROD-01:                                          │
│ EXEC [SQL-PROD-03].[MonitoringDB].[dbo].[usp_CollectMetrics_RemoteServer]
│     @ServerName = 'SQL-PROD-01'                             │
│                                                             │
│ -- Or via OPENQUERY:                                        │
│ INSERT INTO [SQL-PROD-03].[MonitoringDB].[dbo].[PerformanceMetrics_Staging]
│ SELECT * FROM OPENQUERY(                                    │
│     [SQL-PROD-01],                                          │
│     'SELECT @@SERVERNAME, getdate(), counter_name, cntr_value │
│      FROM sys.dm_os_performance_counters'                   │
│ )                                                           │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ Step 3: MonitoringDB processes data                        │
│                                                             │
│ - Inserts into staging tables                              │
│ - Calculates deltas (for cumulative counters)              │
│ - Inserts into partitioned fact tables                     │
│ - Updates aggregation tables                               │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ Step 4: Data available immediately                         │
│                                                             │
│ - Grafana queries MonitoringDB views                       │
│ - API queries MonitoringDB stored procedures               │
│ - Users see metrics within 5 minutes                       │
└─────────────────────────────────────────────────────────────┘
```

### Alert Flow

```
SQL Agent Job → Check Alert Rules SP → Alert Threshold Exceeded?
                                              │
                                              ├─ YES → Insert into dbo.AlertHistory
                                              │        Call dbo.usp_SendAlert
                                              │        (Database Mail or API webhook)
                                              │
                                              └─ NO  → Continue
```

## Security Architecture

### Database Security

**MonitoringDB Permissions**:

```sql
-- Create minimal-privilege users
CREATE USER [monitor_collector] WITH PASSWORD = 'SecurePassword1';
CREATE USER [monitor_api] WITH PASSWORD = 'SecurePassword2';
CREATE USER [grafana_reader] WITH PASSWORD = 'SecurePassword3';

-- Collector: Execute SPs only
GRANT EXECUTE ON SCHEMA::dbo TO [monitor_collector];

-- API: Execute SPs + read config tables
GRANT EXECUTE ON SCHEMA::dbo TO [monitor_api];
GRANT SELECT ON dbo.Servers TO [monitor_api];
GRANT SELECT ON dbo.AlertRules TO [monitor_api];

-- Grafana: Read views only
GRANT SELECT ON SCHEMA::dbo TO [grafana_reader];
DENY SELECT ON dbo.Servers TO [grafana_reader]; -- Config tables
```

**Monitored Server Permissions**:

```sql
-- On each monitored server, create login for linked server
CREATE LOGIN [DOMAIN\MonitoringService] FROM WINDOWS;
GRANT VIEW SERVER STATE TO [DOMAIN\MonitoringService];
GRANT VIEW DATABASE STATE TO [DOMAIN\MonitoringService];
-- NO sysadmin, NO db_owner
```

### Network Security

```
Monitored Servers ─┬─ Port 1433 (SQL) ──→ MonitoringDB Server
                   │  (TLS encrypted)
                   │
Docker Host ───────┴─ Port 1433 (SQL) ──→ MonitoringDB Server
                      Port 3000 (HTTP) ──→ Users (Grafana)
                      Port 5000 (HTTP) ──→ Users (API)
```

**Firewall Rules**:
- MonitoringDB Server: Allow 1433 from monitored servers + Docker host
- Docker Host: Allow 3000, 5000 from user subnet
- All SQL connections: Enforce encryption (`Encrypt=True` in connection strings)

### Secrets Management

**No Azure Key Vault Required** - Use Docker secrets or environment variables:

```bash
# Option 1: Docker secrets (recommended for Swarm/Kubernetes)
echo "Server=sql-prod-03;Database=MonitoringDB;User Id=monitor_api;Password=SecurePass123;Encrypt=True;" | docker secret create db_connection_string -

# Option 2: .env file (for docker-compose)
cat > .env <<EOF
DB_PASSWORD=SecurePass123
GRAFANA_ADMIN_PASSWORD=AdminPass456
EOF
chmod 600 .env
```

## Scalability Architecture

### Vertical Scaling (MonitoringDB Server)

| Servers Monitored | Recommended Specs | Storage |
|-------------------|-------------------|---------|
| 1-10 servers | 4 vCPU, 16 GB RAM | 100 GB SSD |
| 11-30 servers | 8 vCPU, 32 GB RAM | 500 GB SSD |
| 31-50 servers | 16 vCPU, 64 GB RAM | 1 TB SSD |
| 51-100 servers | 32 vCPU, 128 GB RAM | 2 TB SSD |

### Horizontal Scaling (Multiple MonitoringDB Instances)

For 100+ servers, shard by geography or environment:

```
Monitoring Region 1 (MonitoringDB-US)    ← Collects from US SQL Servers
Monitoring Region 2 (MonitoringDB-EU)    ← Collects from EU SQL Servers
Monitoring Region 3 (MonitoringDB-APAC)  ← Collects from APAC SQL Servers
           │                │                    │
           └────────────────┴────────────────────┘
                            │
                    Grafana Federation
                 (queries all 3 data sources)
```

## Technology Stack Summary

| Component | Technology | License | Why |
|-----------|-----------|---------|-----|
| **API** | ASP.NET Core 8.0 | MIT | Best performance, native async, mature |
| **Data Access** | Dapper | Apache 2.0 | Lightweight, perfect for SP-only pattern |
| **UI** | Grafana OSS | Apache 2.0 | Industry standard, SQL datasource, beautiful |
| **Database** | SQL Server | Your license | Leverages existing infrastructure |
| **Containerization** | Docker | Apache 2.0 | Cross-platform, easy deployment |
| **Orchestration** | Docker Compose | Apache 2.0 | Simple, built-in, no Kubernetes needed |

**Alternative Database Option** (if you prefer):
- **PostgreSQL** with TimescaleDB extension (Apache 2.0) - Better for pure time-series
- **Pro**: Free, excellent time-series performance
- **Con**: Need separate PostgreSQL instance, less SQL Server-native integration

## Deployment Topologies

### Topology 1: On-Premises (Single Site)

```
                    ┌─────────────────┐
                    │  Corporate LAN  │
                    └────────┬────────┘
           ┌────────────────┼────────────────┐
           │                │                │
      SQL-PROD-01      SQL-PROD-02      SQL-PROD-03
      (Monitored)      (Monitored)   (Monitored + MonitoringDB)
           │                │                │
           └────────────────┴────────────────┘
                            │
                    ┌───────▼────────┐
                    │  Docker Host   │
                    │  (VM or Linux) │
                    │  sql-monitor   │
                    └────────────────┘
```

### Topology 2: Multi-Cloud (Hybrid)

```
    On-Prem                Azure                    AWS
┌──────────────┐      ┌──────────────┐       ┌──────────────┐
│ SQL-ONPREM-01│      │ SQL-AzureVM  │       │ SQL-EC2-01   │
└──────┬───────┘      └──────┬───────┘       └──────┬───────┘
       │                     │                      │
       │    VPN/ExpressRoute │         VPN          │
       └─────────────────────┼──────────────────────┘
                             │
                    ┌────────▼─────────┐
                    │ MonitoringDB     │
                    │ (on any SQL)     │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │  Docker Host     │
                    │  (anywhere)      │
                    └──────────────────┘
```

### Topology 3: Kubernetes (Enterprise Scale)

```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sql-monitor
spec:
  replicas: 2  # HA for UI/API
  template:
    spec:
      containers:
      - name: api
        image: yourregistry/sql-monitor-api:latest
        env:
        - name: ConnectionStrings__MonitoringDB
          valueFrom:
            secretKeyRef:
              name: sql-monitor-secrets
              key: db-connection-string
      - name: grafana
        image: grafana/grafana-oss:10.2.0
        volumeMounts:
        - name: dashboards
          mountPath: /etc/grafana/provisioning
---
apiVersion: v1
kind: Service
metadata:
  name: sql-monitor
spec:
  type: LoadBalancer
  ports:
  - port: 3000
    name: grafana
  - port: 5000
    name: api
```

## Monitoring the Monitor

**How to ensure the monitoring system itself is healthy?**

```sql
-- Health check SP (called by Docker HEALTHCHECK)
CREATE PROCEDURE dbo.usp_HealthCheck
AS
BEGIN
    -- Check data freshness (last collection < 10 minutes ago)
    IF EXISTS (
        SELECT 1 FROM dbo.Servers s
        WHERE s.IsActive = 1
        AND NOT EXISTS (
            SELECT 1 FROM dbo.PerformanceMetrics pm
            WHERE pm.ServerID = s.ServerID
            AND pm.CollectionTime > DATEADD(MINUTE, -10, GETUTCDATE())
        )
    )
    BEGIN
        RAISERROR('Stale data detected', 16, 1);
        RETURN 1;
    END

    -- Check disk space on MonitoringDB
    IF EXISTS (
        SELECT 1 FROM sys.dm_os_volume_stats(DB_ID(), 1)
        WHERE (available_bytes * 1.0 / total_bytes) < 0.10  -- <10% free
    )
    BEGIN
        RAISERROR('Low disk space', 16, 1);
        RETURN 1;
    END

    RETURN 0; -- Healthy
END
```

```dockerfile
# Dockerfile (API)
HEALTHCHECK --interval=60s --timeout=5s --retries=3 \
  CMD curl -f http://localhost:5000/health || exit 1
```

## Performance Optimization

### Database Optimization

```sql
-- 1. Partition alignment check
SELECT
    OBJECT_NAME(p.object_id) AS TableName,
    i.name AS IndexName,
    p.partition_number,
    p.rows
FROM sys.partitions p
INNER JOIN sys.indexes i ON p.object_id = i.object_id AND p.index_id = i.index_id
WHERE OBJECT_NAME(p.object_id) IN ('PerformanceMetrics', 'ProcedureStats')
ORDER BY TableName, partition_number;

-- 2. Index fragmentation monitoring
SELECT
    OBJECT_NAME(ips.object_id) AS TableName,
    i.name AS IndexName,
    ips.avg_fragmentation_in_percent,
    ips.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'SAMPLED') ips
INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.avg_fragmentation_in_percent > 30
AND ips.page_count > 1000
ORDER BY ips.avg_fragmentation_in_percent DESC;

-- 3. Rebuild fragmented columnstore indexes
ALTER INDEX IX_PerformanceMetrics_CS ON dbo.PerformanceMetrics REBUILD PARTITION = ALL
WITH (ONLINE = ON, MAXDOP = 4);
```

### API Performance

```csharp
// Caching with IMemoryCache (ASP.NET Core built-in)
public class MetricsService
{
    private readonly IMemoryCache _cache;

    public async Task<IEnumerable<ServerModel>> GetServers()
    {
        return await _cache.GetOrCreateAsync("servers", async entry =>
        {
            entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(5);
            return await _sqlService.GetServers();
        });
    }
}
```

## Cost Analysis

### Infrastructure Costs (Self-Hosted)

| Component | Hardware | Annual Cost |
|-----------|----------|-------------|
| MonitoringDB (VM) | 8 vCPU, 32 GB, 500 GB SSD | $1,200/year (cloud VM) or $0 (existing server) |
| Docker Host (VM) | 2 vCPU, 4 GB | $300/year or $0 (existing Linux VM) |
| **Total** | - | **$0-$1,500/year** |

### vs. Azure Architecture

| Item | Self-Hosted | Azure Architecture |
|------|-------------|-------------------|
| Database | $0 (existing SQL) | $2,400/year (Azure SQL 8 vCore) |
| API/Functions | $0 (Docker) | $60/year |
| Storage | $0 (existing disk) | $120/year |
| Grafana | $0 (OSS) | $0 (OSS) |
| **Total** | **$0-$1,500** | **$2,580/year** |

### **Savings**: $1,000-$2,500/year compared to cloud-only, $27k-$37k/year compared to commercial tools!

## Next Steps

See [TODO.md](TODO.md) for implementation roadmap.
