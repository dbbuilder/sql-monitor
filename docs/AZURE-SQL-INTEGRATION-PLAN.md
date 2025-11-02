# Azure SQL Integration and Linked Server Elimination Plan

**Date**: 2025-10-31
**Status**: PLANNING PHASE
**Target Timeline**: Phase 3 (Q1-Q2 2026)

## Executive Summary

This document outlines the strategy to migrate SQL Server Monitor from an on-premises, linked-server architecture to a cloud-native Azure SQL platform that eliminates the need for linked servers while maintaining or improving functionality.

**Current Architecture Pain Points**:
- Linked servers create security concerns (credentials stored, network dependencies)
- Cross-server queries don't scale well to many monitored servers
- Difficult to monitor Azure SQL Database (doesn't support linked servers)
- Network latency can impact collection performance
- Configuration complexity (linked server setup on each remote server)

**Target Architecture Benefits**:
- ✅ Cloud-native, scalable data collection
- ✅ Unified monitoring for on-premises + Azure SQL
- ✅ No linked server configuration required
- ✅ Better security (Managed Identity, Key Vault)
- ✅ Built-in high availability and disaster recovery

## Architecture Evolution

### Phase 1: Current (On-Premises + Linked Servers)

```
┌─────────────────────────────────────────────────────────────┐
│                    Monitored Servers                        │
├─────────────────────────────────────────────────────────────┤
│  svweb (ServerID=5)        suncity (ServerID=4)            │
│  ┌─────────────────┐       ┌─────────────────┐            │
│  │ SQL Agent Job   │       │ SQL Agent Job   │            │
│  │ (every 5 min)   │       │ (every 5 min)   │            │
│  │                 │       │                 │            │
│  │ EXEC [sqltest]  │       │ EXEC [sqltest]  │            │
│  │   .MonitoringDB │       │   .MonitoringDB │            │
│  │   .dbo.usp_...  │       │   .dbo.usp_...  │            │
│  └────────┬────────┘       └────────┬────────┘            │
│           │                         │                      │
│           │   Linked Server Call    │                      │
│           └─────────────┬───────────┘                      │
└─────────────────────────┼──────────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────┐
│          sqltest.schoolvision.net,14333                     │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────┐  │
│  │              MonitoringDB                            │  │
│  │  - Tables (PerformanceMetrics, WaitStatsSnapshot)   │  │
│  │  - Stored Procedures (usp_CollectAllMetrics)        │  │
│  │  - Partitions (monthly, 90-day retention)           │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │      ASP.NET Core API (Docker, port 9000)            │  │
│  │  - Dapper-based SP execution                         │  │
│  │  - JWT authentication                                │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         Grafana OSS (Docker, port 9001)              │  │
│  │  - SQL Server datasource (MonitoringDB)              │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

**Issues**:
- Linked server credentials stored in plain text in SQL Server
- Each remote server must configure linked server to sqltest
- Doesn't work with Azure SQL Database (no linked servers)
- Network dependency: if linked server connection fails, no metrics collected
- Firewall rules required between all servers

### Phase 2: Hybrid (Transition Architecture - Optional)

```
┌─────────────────────────────────────────────────────────────┐
│              Monitored Servers (On-Premises)                │
├─────────────────────────────────────────────────────────────┤
│  svweb                     suncity                          │
│  ┌─────────────────┐       ┌─────────────────┐            │
│  │ Lightweight     │       │ Lightweight     │            │
│  │ Collector Agent │       │ Collector Agent │            │
│  │ (Python/PS)     │       │ (Python/PS)     │            │
│  │                 │       │                 │            │
│  │ HTTP POST       │       │ HTTP POST       │            │
│  │ metrics to API  │       │ metrics to API  │            │
│  └────────┬────────┘       └────────┬────────┘            │
│           │                         │                      │
│           └─────────────┬───────────┘                      │
└─────────────────────────┼──────────────────────────────────┘
                          │ HTTPS (TLS 1.2+)
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                  Azure Cloud                                │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────┐  │
│  │   Azure Container Instances (or App Service)         │  │
│  │   ┌───────────────────────────────────────────────┐  │  │
│  │   │    ASP.NET Core API                           │  │  │
│  │   │    - POST /api/metrics/collect                │  │  │
│  │   │    - Bulk insert to Azure SQL                 │  │  │
│  │   │    - JWT auth + Managed Identity              │  │  │
│  │   └───────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────┘  │
│                          │                                   │
│                          │ SQL connection                    │
│                          ▼                                   │
│  ┌──────────────────────────────────────────────────────┐  │
│  │   Azure SQL Database (Hyperscale or Business Critical)│  │
│  │   ┌───────────────────────────────────────────────┐  │  │
│  │   │    MonitoringDB                               │  │  │
│  │   │    - Same schema (tables, SPs)                │  │  │
│  │   │    - Automatic backups (PITR 35 days)         │  │  │
│  │   │    - Read replicas for Grafana                │  │  │
│  │   └───────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │   Grafana Cloud (or Azure Container Instance)        │  │
│  │   - Azure SQL datasource                             │  │
│  │   - Connects to read replica                         │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

**Advantages**:
- No linked servers required
- On-premises servers push metrics to cloud API
- Centralized Azure SQL database
- Grafana reads from Azure SQL (no impact on monitoring DB)

**Trade-offs**:
- Still requires agent on each monitored server (Python or PowerShell script)
- Outbound HTTPS from on-premises to Azure (firewall rules)
- API needs to handle high throughput (many servers pushing metrics)

### Phase 3: Cloud-Native (Target Architecture)

```
┌─────────────────────────────────────────────────────────────┐
│         Monitored Servers (On-Premises or Azure)            │
├─────────────────────────────────────────────────────────────┤
│  SQL Server (any)           Azure SQL Database              │
│  ┌─────────────────┐       ┌─────────────────┐            │
│  │ Extended Events │       │ Query Store     │            │
│  │ Query Store     │       │ DMVs            │            │
│  │ DMVs            │       │ Diagnostics     │            │
│  └────────┬────────┘       └────────┬────────┘            │
│           │ Read-only              │ Read-only            │
│           │ SQL connection         │ SQL connection       │
│           └─────────────┬───────────┘                      │
└─────────────────────────┼──────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    Azure Cloud                              │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────┐  │
│  │   Azure Function (Timer Trigger, every 5 minutes)    │  │
│  │   ┌───────────────────────────────────────────────┐  │  │
│  │   │  Collection Logic (C#)                        │  │  │
│  │   │  - Connect to each monitored server           │  │  │
│  │   │  - Execute DMV queries                        │  │  │
│  │   │  - Bulk insert to MonitoringDB                │  │  │
│  │   │  - Managed Identity (no credentials)          │  │  │
│  │   └───────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────┘  │
│           │                                                  │
│           │ Parallel collection (one task per server)       │
│           ▼                                                  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │   Azure SQL Database (MonitoringDB)                  │  │
│  │   - Hyperscale tier (100TB+, fast reads)             │  │
│  │   - Read replicas for Grafana                        │  │
│  │   - Auto-tuning enabled                              │  │
│  │   - Long-term retention (LTR) backups                │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │   Azure Container Instances (API + Grafana)          │  │
│  │   - ASP.NET Core API (port 9000)                     │  │
│  │   - Grafana OSS (port 9001)                          │  │
│  │   - Connects to read replica                         │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │   Azure Key Vault                                    │  │
│  │   - SQL connection strings (encrypted)               │  │
│  │   - JWT secrets                                      │  │
│  │   - Grafana admin password                           │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

**Key Benefits**:
- ✅ **No Linked Servers**: Azure Function connects directly to each monitored server
- ✅ **No Agents**: Zero software installation on monitored servers
- ✅ **Unified Platform**: Monitor on-prem SQL Server + Azure SQL Database with same code
- ✅ **Serverless Collection**: Azure Function scales automatically, pay-per-execution
- ✅ **Managed Identity**: No credentials in code or connection strings
- ✅ **High Availability**: Azure SQL auto-failover, read replicas
- ✅ **Cost-Effective**: Azure Function consumption plan (~$1-5/month for 288 executions/day)

## Technical Deep Dive

### Azure Function Collection Pattern

**Function Structure**:
```csharp
[FunctionName("CollectMetrics")]
public static async Task Run(
    [TimerTrigger("0 */5 * * * *")] TimerInfo timer,
    ILogger log)
{
    // 1. Get list of active servers from MonitoringDB
    var servers = await GetActiveServersAsync();

    // 2. Collect metrics in parallel (one task per server)
    var tasks = servers.Select(async server =>
    {
        try
        {
            // Connect to monitored server (read-only DMV queries)
            using var connection = new SqlConnection(server.ConnectionString);
            var metrics = await CollectServerMetricsAsync(connection, server.ServerId);

            // Bulk insert to MonitoringDB
            await BulkInsertMetricsAsync(metrics);

            log.LogInformation($"Collected {metrics.Count} metrics from {server.ServerName}");
        }
        catch (Exception ex)
        {
            log.LogError(ex, $"Failed to collect from {server.ServerName}");
            await RecordCollectionFailureAsync(server.ServerId, ex.Message);
        }
    });

    await Task.WhenAll(tasks);
}

private static async Task<List<Metric>> CollectServerMetricsAsync(
    SqlConnection connection, int serverId)
{
    var metrics = new List<Metric>();

    // Query Store
    if (await IsQueryStoreEnabledAsync(connection))
    {
        metrics.AddRange(await CollectQueryStoreAsync(connection, serverId));
    }

    // Wait Statistics
    metrics.AddRange(await CollectWaitStatsAsync(connection, serverId));

    // Blocking/Deadlocks
    metrics.AddRange(await CollectBlockingEventsAsync(connection, serverId));

    // Index Stats
    metrics.AddRange(await CollectIndexStatsAsync(connection, serverId));

    return metrics;
}
```

**Key Advantages**:
- **Parallel Collection**: All servers collected simultaneously (fast)
- **Error Isolation**: One server failure doesn't impact others
- **No Linked Servers**: Direct SQL connections (SqlConnection)
- **Serverless**: Only runs when triggered (cost-effective)
- **Scalable**: Handles 100+ monitored servers easily

### Connection String Management

**Azure Key Vault Pattern**:
```csharp
// Secrets stored in Key Vault, referenced by Azure Function
{
  "KeyVaultName": "sqlmonitor-kv",
  "Secrets": {
    "MonitoringDB-ConnectionString": "Server=tcp:sqlmonitor.database.windows.net,1433;Database=MonitoringDB;Authentication=Active Directory Managed Identity;",
    "Server-sqltest-ConnectionString": "Server=sqltest.schoolvision.net,14333;Database=master;User Id=monitor_reader;Password=<from-keyvault>;",
    "Server-svweb-ConnectionString": "Server=svweb,14333;Database=master;User Id=monitor_reader;Password=<from-keyvault>;"
  }
}

// Azure Function retrieves secrets at runtime
var keyVaultClient = new SecretClient(
    new Uri($"https://{keyVaultName}.vault.azure.net/"),
    new DefaultAzureCredential()
);

var connectionString = await keyVaultClient.GetSecretAsync("Server-sqltest-ConnectionString");
```

**Benefits**:
- Credentials never stored in code or config files
- Automatic rotation support
- Audit logging (who accessed which secret)
- RBAC (fine-grained access control)

### Azure SQL Database Tier Selection

**Recommended Tier: Hyperscale**

| Tier | vCores | Storage | Cost/Month | Use Case |
|------|--------|---------|------------|----------|
| General Purpose | 2-80 | 1TB max | $200-$8,000 | Small deployments (<10 servers) |
| **Hyperscale** | 2-80 | 100TB+ | $600-$10,000 | **Recommended** (10+ servers, read replicas) |
| Business Critical | 2-80 | 4TB max | $1,000-$20,000 | High IOPS requirements |

**Why Hyperscale?**:
- ✅ Near-instant backups (file snapshots, not database copies)
- ✅ Fast database restores (<15 minutes for any size)
- ✅ Up to 4 read replicas (Grafana queries don't impact monitoring)
- ✅ 100TB+ storage (metrics grow ~2GB/month per 10 servers)
- ✅ Automatic page server caching (faster queries)
- ✅ Log throughput: 100 MB/s (vs 48 MB/s General Purpose)

**Cost Estimate** (20 servers monitored):
- Hyperscale 4 vCores: ~$900/month
- 1 Read Replica (for Grafana): ~$225/month
- Storage (200GB): Included
- **Total**: ~$1,125/month

**Alternative (Budget)**: General Purpose 4 vCores (~$600/month, no read replicas)

### Migration from On-Premises to Azure SQL

**Step-by-Step Migration**:

1. **Create Azure SQL Database**:
   ```bash
   az sql db create \
     --resource-group rg-sqlmonitor \
     --server sqlmonitor-prod \
     --name MonitoringDB \
     --service-objective HS_Gen5_4 \  # Hyperscale 4 vCores
     --compute-model Provisioned \
     --backup-storage-redundancy Zone
   ```

2. **Migrate Schema** (Azure Database Migration Service or manual):
   ```bash
   # Export schema from on-premises
   sqlpackage /Action:Extract \
     /SourceServerName:sqltest.schoolvision.net,14333 \
     /SourceDatabaseName:MonitoringDB \
     /TargetFile:MonitoringDB.dacpac

   # Publish to Azure SQL
   sqlpackage /Action:Publish \
     /SourceFile:MonitoringDB.dacpac \
     /TargetServerName:sqlmonitor-prod.database.windows.net \
     /TargetDatabaseName:MonitoringDB \
     /TargetUser:sqladmin
   ```

3. **Data Migration** (Azure Data Factory or bcp):
   ```sql
   -- Use Azure Data Factory pipeline to copy historical data
   -- Or export/import using bcp for smaller datasets

   -- Example: Export from on-premises
   bcp MonitoringDB.dbo.PerformanceMetrics out metrics.dat -S sqltest -T -n

   -- Import to Azure SQL
   bcp MonitoringDB.dbo.PerformanceMetrics in metrics.dat -S sqlmonitor-prod.database.windows.net -U sqladmin -P <password> -n
   ```

4. **Update Connection Strings**:
   - API: Point to Azure SQL
   - Grafana: Point to read replica
   - Azure Function: Configure Key Vault secrets

5. **Cutover**:
   - Stop on-premises SQL Agent jobs
   - Enable Azure Function timer trigger
   - Verify metrics collection
   - Decommission old linked servers

### Azure SQL Compatibility Notes

**Features NOT Available in Azure SQL Database**:
- ❌ SQL Agent Jobs → Use Azure Function timer triggers
- ❌ Linked Servers → Not needed (Azure Function connects directly)
- ❌ xp_cmdshell → Not needed (no OS interaction)
- ❌ Trace Flags → Use Query Store and Extended Events instead

**Features Available in Azure SQL Database**:
- ✅ Query Store (enabled by default)
- ✅ Extended Events (system_health session)
- ✅ DMVs (sys.dm_os_wait_stats, sys.dm_db_index_usage_stats, etc.)
- ✅ Stored Procedures (all existing SPs work)
- ✅ Partitioning (monthly partition scheme works)
- ✅ Columnstore Indexes (for fast aggregation)

**Equivalent Features**:
| On-Premises | Azure SQL Database |
|-------------|---------------------|
| SQL Agent Jobs | Azure Function (Timer Trigger) |
| Trace Flag 1222 | Query Store + Extended Events |
| DBCC CHECKDB | Automatic integrity checks |
| Manual backups | Automatic backups (PITR 7-35 days) |
| Linked Servers | Azure Function (direct connections) |

## Cost Analysis

### Current Architecture (Self-Hosted)

| Component | Cost | Notes |
|-----------|------|-------|
| SQL Server | $0 | Existing on-premises license |
| Docker Containers | $0 | Running on existing server |
| Network | $0 | Internal network only |
| **Total/Month** | **$0** | (Assuming existing infrastructure) |

### Phase 2: Hybrid (On-Premises + Azure SQL)

| Component | Cost/Month | Notes |
|-----------|------------|-------|
| Azure SQL (General Purpose 4 vCores) | $600 | 20 servers monitored |
| Azure Container Instances (API) | $30 | 1 vCPU, 2GB RAM |
| Azure Container Instances (Grafana) | $30 | 1 vCPU, 2GB RAM |
| Outbound bandwidth | $10 | Metrics upload from on-prem |
| **Total/Month** | **$670** | |

### Phase 3: Cloud-Native (Full Azure)

| Component | Cost/Month | Notes |
|-----------|------------|-------|
| Azure SQL Hyperscale (4 vCores) | $900 | Primary database |
| Azure SQL Read Replica (1 replica) | $225 | For Grafana queries |
| Azure Function (Consumption Plan) | $2 | 288 executions/day × 30 days |
| Azure Container Instances (API + Grafana) | $60 | Combined container |
| Azure Key Vault | $1 | Secrets management |
| Azure Monitor (logs/metrics) | $20 | Application Insights |
| Outbound bandwidth | $5 | Minimal (inbound is free) |
| **Total/Month** | **$1,213** | |

**ROI Comparison**:
- vs. SolarWinds Database Performance Analyzer: $2,295/month (saves $1,082/month)
- vs. Redgate SQL Monitor: $3,200/month (saves $1,987/month)
- Break-even vs. self-hosted: Never (self-hosted is free if infrastructure exists)

**When to Migrate to Cloud**:
- ✅ Need to monitor Azure SQL Database (can't use linked servers)
- ✅ On-premises infrastructure end-of-life
- ✅ Want managed backups and high availability
- ✅ Monitoring 20+ servers (management complexity justifies cost)
- ❌ Small deployment (<5 servers) - self-hosted more cost-effective
- ❌ All servers on same LAN with existing infrastructure

## Implementation Phases

### Phase 2.5: Prepare for Azure (No Breaking Changes)

**Timeline**: 2-3 weeks
**Goal**: Make codebase Azure-ready without requiring Azure

**Tasks**:
1. **Refactor Collection Logic**:
   - Extract DMV collection code from stored procedures to C# library
   - Create `SqlMonitor.Collectors` project with methods like:
     ```csharp
     Task<List<WaitStat>> CollectWaitStatsAsync(SqlConnection connection);
     Task<List<BlockingEvent>> CollectBlockingEventsAsync(SqlConnection connection);
     ```
   - Unit tests for collection logic (mock SqlConnection)

2. **Abstract Connection Management**:
   - Create `IConnectionProvider` interface:
     ```csharp
     interface IConnectionProvider
     {
         Task<SqlConnection> GetConnectionAsync(int serverId);
         Task<IEnumerable<Server>> GetActiveServersAsync();
     }
     ```
   - Implementations:
     - `LinkedServerConnectionProvider` (current)
     - `DirectConnectionProvider` (future Azure Function)

3. **Configuration Flexibility**:
   - Support both `appsettings.json` (current) and Azure Key Vault
   - Environment variable overrides for connection strings

4. **Update Documentation**:
   - Architecture diagrams for all phases
   - Migration runbook (on-premises → Azure)

**Deliverables**:
- ✅ Collection logic extracted to reusable library
- ✅ Connection abstraction layer
- ✅ No breaking changes (linked servers still work)
- ✅ Ready to deploy to Azure Function (just change connection provider)

### Phase 3.0: Azure Function Deployment

**Timeline**: 1-2 weeks
**Goal**: Deploy collection logic to Azure Function (parallel with existing)

**Prerequisites**:
- Azure subscription with Contributor role
- Azure SQL Database provisioned
- Schema migrated from on-premises

**Tasks**:
1. **Create Azure Function**:
   ```bash
   func init SqlMonitor.Function --dotnet
   func new --name CollectMetrics --template TimerTrigger
   ```

2. **Deploy to Azure**:
   ```bash
   # Create Function App
   az functionapp create \
     --resource-group rg-sqlmonitor \
     --consumption-plan-location eastus \
     --runtime dotnet \
     --functions-version 4 \
     --name func-sqlmonitor-prod \
     --storage-account stsqlmonitor

   # Deploy function code
   func azure functionapp publish func-sqlmonitor-prod
   ```

3. **Configure Managed Identity**:
   ```bash
   # Enable system-assigned managed identity
   az functionapp identity assign \
     --name func-sqlmonitor-prod \
     --resource-group rg-sqlmonitor

   # Grant SQL access
   # (Run on Azure SQL Database)
   CREATE USER [func-sqlmonitor-prod] FROM EXTERNAL PROVIDER;
   ALTER ROLE db_datawriter ADD MEMBER [func-sqlmonitor-prod];
   GRANT EXECUTE TO [func-sqlmonitor-prod];
   ```

4. **Test Parallel Collection**:
   - Azure Function collects metrics to Azure SQL
   - Existing on-premises SQL Agent jobs still running
   - Compare data quality and latency
   - Grafana queries both sources (union)

5. **Cutover**:
   - Disable on-premises SQL Agent jobs
   - Grafana datasource points to Azure SQL only
   - Monitor for 1 week

**Rollback Plan**:
- Re-enable on-premises SQL Agent jobs
- Grafana datasource back to on-premises
- Debug Azure Function issues offline

### Phase 3.1: Read Replica for Grafana

**Timeline**: 1 week
**Goal**: Offload Grafana queries to read replica

**Tasks**:
1. **Create Read Replica**:
   ```bash
   az sql db replica create \
     --resource-group rg-sqlmonitor \
     --server sqlmonitor-prod \
     --name MonitoringDB \
     --secondary-type ReadScale \
     --partner-server sqlmonitor-prod-replica
   ```

2. **Update Grafana Datasource**:
   ```yaml
   # provisioning/datasources/monitoringdb.yaml
   datasources:
     - name: MonitoringDB
       type: mssql
       url: sqlmonitor-prod-replica.database.windows.net:1433
       database: MonitoringDB
       user: grafana_reader
       jsonData:
         encrypt: true
         readOnly: true
   ```

3. **Verify Query Performance**:
   - Dashboards load within 500ms
   - No impact on primary database (check wait stats)

### Phase 3.2: Azure SQL Managed Instance (Alternative)

**When to Use**:
- Need SQL Agent Jobs (don't want Azure Function)
- Need cross-database queries (linked servers within MI)
- Lift-and-shift from on-premises (minimal code changes)

**Cost**: ~$750/month (4 vCores General Purpose)

**Pros**:
- ✅ SQL Agent Jobs (keep existing collection scripts)
- ✅ Linked Servers (within Managed Instance VNet)
- ✅ Near 100% compatibility with on-premises SQL Server

**Cons**:
- ❌ More expensive than Azure SQL Database
- ❌ Requires VNet configuration
- ❌ Slower provisioning (4-6 hours for new MI)
- ❌ Still uses linked servers (architectural debt)

**Recommendation**: Only if lifting-and-shifting with zero code changes is required. Otherwise, Azure Function + Azure SQL Database is better long-term architecture.

## Security Considerations

### Managed Identity Flow

```
┌─────────────────────────────────────────────────────────────┐
│                  Azure Function                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  System-Assigned Managed Identity                     │  │
│  │  - Azure AD object ID                                 │  │
│  │  - No credentials in code                             │  │
│  └──────────────────────┬────────────────────────────────┘  │
└─────────────────────────┼──────────────────────────────────┘
                          │
                          │ 1. Request token from Azure AD
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    Azure Active Directory                   │
│  - Verifies Managed Identity                                │
│  - Issues access token (valid 1 hour)                       │
└──────────────────────────┬──────────────────────────────────┘
                           │ 2. Return token
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                  Azure SQL Database                         │
│  - Validates token                                          │
│  - Maps to database user (CREATE USER ... FROM EXTERNAL)   │
│  - Enforces RBAC permissions                                │
└─────────────────────────────────────────────────────────────┘
```

**Benefits**:
- No connection string passwords (token-based auth)
- Automatic token rotation (every hour)
- Centralized access control (Azure AD)
- Audit trail (who accessed what, when)

### Firewall Rules

**Azure SQL Database**:
```bash
# Allow Azure services (for Azure Function)
az sql server firewall-rule create \
  --resource-group rg-sqlmonitor \
  --server sqlmonitor-prod \
  --name AllowAzureServices \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0

# Allow on-premises SQL Servers (for migration period)
az sql server firewall-rule create \
  --resource-group rg-sqlmonitor \
  --server sqlmonitor-prod \
  --name AllowOnPremises \
  --start-ip-address 203.0.113.0 \
  --end-ip-address 203.0.113.255
```

**On-Premises SQL Servers**:
- Allow inbound from Azure Function (outbound from Azure = dynamic IPs)
- **Recommendation**: Use Azure VPN Gateway or ExpressRoute for secure connection
- **Alternative**: Public endpoint with SQL auth (less secure)

## Performance Optimization

### Bulk Insert Pattern

**Problem**: Inserting 150 wait stats × 20 servers = 3,000 rows every 5 minutes

**Inefficient**:
```csharp
foreach (var metric in metrics)
{
    await connection.ExecuteAsync(
        "INSERT INTO WaitStatsSnapshot (...) VALUES (...)",
        metric
    );
}
// Result: 3,000 individual SQL statements (slow)
```

**Efficient** (SqlBulkCopy):
```csharp
using var bulkCopy = new SqlBulkCopy(connection)
{
    DestinationTableName = "dbo.WaitStatsSnapshot",
    BatchSize = 1000,
    BulkCopyTimeout = 30
};

bulkCopy.ColumnMappings.Add("ServerID", "ServerID");
bulkCopy.ColumnMappings.Add("SnapshotTime", "SnapshotTime");
bulkCopy.ColumnMappings.Add("WaitType", "WaitType");
// ... more mappings

await bulkCopy.WriteToServerAsync(metricsTable);
// Result: 1 bulk insert (10-100x faster)
```

**Performance**: 3,000 rows in <100ms (vs 5+ seconds for individual INSERTs)

### Query Performance (Grafana)

**Partition Elimination**:
```sql
-- Grafana query with time range variables ($__timeFilter)
SELECT
    ServerID,
    AVG(CPUPercent) AS AvgCPU
FROM dbo.PerformanceMetrics
WHERE $__timeFilter(CollectionTime)  -- Partition elimination
  AND ServerID = $serverId
GROUP BY ServerID;
```

**Result**: Query scans only relevant monthly partitions (not entire table)

**Read Replica**:
- Grafana queries hit read replica (not primary)
- Primary database unaffected by dashboard load
- Read replica lags <1 second (near real-time)

## Monitoring the Monitor

**Azure Monitor Metrics** (for Azure Function):
- Function execution count (should be 288/day)
- Function duration (should be <30 seconds)
- Function failures (alert if >5%)

**Azure SQL Database Metrics**:
- DTU/vCore utilization (should be <70%)
- Data IO percentage (alert if >80%)
- Log IO percentage (alert if >80%)
- Deadlocks (should be 0)
- Failed connections (alert if >0)

**Application Insights**:
- Custom metrics: Servers collected, metrics per server, collection latency
- Alerts: Collection failure for any server, query store not enabled

## Decision Matrix

**Should you migrate to Azure SQL?**

| Factor | Self-Hosted (Current) | Azure SQL (Target) | Winner |
|--------|----------------------|--------------------|----|
| Cost (20 servers) | $0/month | $1,213/month | Self-Hosted |
| Setup complexity | Medium (Docker, SQL Server) | High (Azure resources) | Self-Hosted |
| Operational overhead | High (backups, patching) | Low (fully managed) | Azure SQL |
| Scalability | Manual (add hardware) | Automatic (adjust tier) | Azure SQL |
| High availability | Manual (AlwaysOn) | Automatic (99.99% SLA) | Azure SQL |
| Azure SQL monitoring | Not supported | Native support | Azure SQL |
| Linked server dependency | Yes (fragile) | No (Azure Function) | Azure SQL |
| Firewall configuration | Minimal (internal) | Moderate (Azure ↔ on-prem) | Self-Hosted |
| Backup/restore | Manual | Automatic (PITR 35 days) | Azure SQL |
| Performance tuning | Manual | Automatic (auto-tuning) | Azure SQL |

**Recommendation**:
- **Start with self-hosted** (Phase 1) for cost savings and simplicity
- **Prepare for Azure** (Phase 2.5) by refactoring collection logic
- **Migrate to Azure** (Phase 3) when:
  - Monitoring 20+ servers (complexity justifies cost)
  - Need to monitor Azure SQL Database
  - Want fully managed HA/DR
  - On-premises infrastructure end-of-life

## Risks and Mitigations

### Risk 1: Azure SQL Cost Overrun

**Risk**: Unexpected cost increases due to high IOPS or storage growth

**Mitigation**:
- Set Azure Cost Management budgets ($1,500/month alert threshold)
- Use Azure Advisor recommendations (right-size database tier)
- Implement aggressive data retention (keep 30 days vs 90 days)
- Use Hyperscale auto-pause for non-production environments

### Risk 2: Network Latency (On-Prem → Azure)

**Risk**: Collection from on-premises servers to Azure takes too long

**Mitigation**:
- Azure Function timeout: 10 minutes (enough for 100+ servers)
- Parallel collection (all servers at once, not sequential)
- ExpressRoute or VPN Gateway for dedicated connection (if needed)
- Fallback: Keep on-premises MonitoringDB, replicate to Azure (geo-replication)

### Risk 3: Azure Function Cold Start

**Risk**: First execution after idle period takes 5-10 seconds (serverless)

**Mitigation**:
- Use Premium Plan ($180/month) for always-on function (no cold starts)
- Or: Consumption Plan + warmup trigger (HTTP ping every 4 minutes)
- Collection happens every 5 minutes, so cold start only impacts first run

### Risk 4: Migration Downtime

**Risk**: Grafana dashboards unavailable during migration

**Mitigation**:
- Parallel run: Azure SQL + on-premises both collecting (dual-write)
- Grafana datasource union (query both sources)
- Cutover during maintenance window (low-traffic hours)
- Rollback plan tested in advance (switch back to on-premises)

## Conclusion

**Short-Term (Now - Q4 2025)**: Continue with self-hosted architecture, complete Phase 2 (SOC 2 compliance)

**Mid-Term (Q1 2026)**: Refactor collection logic to be Azure-ready (Phase 2.5), no breaking changes

**Long-Term (Q2-Q3 2026)**: Evaluate Azure migration based on:
- Number of servers monitored (break-even ~20 servers)
- Need to monitor Azure SQL Database
- On-premises infrastructure roadmap
- Budget approval

**Key Takeaway**: Eliminating linked servers is the right architectural goal, but **timing matters**. Azure SQL migration should be driven by business need (Azure SQL monitoring, HA/DR requirements) rather than technical purity. Self-hosted with linked servers is a valid architecture for small deployments.

---

**Document Version**: 1.0
**Last Updated**: 2025-10-31
**Author**: SQL Monitor Project
**Next Review**: Q1 2026 (reassess based on server count and Azure SQL adoption)
