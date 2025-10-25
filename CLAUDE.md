# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SQL Server Monitor is a **self-hosted, enterprise-grade monitoring solution** for SQL Server instances providing real-time performance metrics, historical trend analysis, alerting capabilities, and automated recommendations.

### Architectural Direction (2025-10-25)

**Critical Decision: Self-Hosted, Minimal Infrastructure**

After requirements analysis, we have pivoted to a **self-hosted architecture** that eliminates cloud dependencies and reduces infrastructure complexity:

#### Core Principles

1. **Database on Existing SQL Server**: MonitoringDB lives on one of the monitored SQL Servers (not Azure SQL Database)
2. **Minimal Containers**: 1-2 Docker containers max (API + Grafana, combined or separate)
3. **No Cloud Lock-In**: Runs entirely on-prem, any cloud, or hybrid
4. **100% Open Source**: All components use free commercial licenses (Apache 2.0, MIT)
5. **Simple Collection**: SQL Agent jobs calling stored procedures via linked servers (no external agents)
6. **Cost Target**: $0-$1,500/year vs. $27k-$37k for commercial solutions

#### Technology Stack (Final)

| Component | Technology | License | Why |
|-----------|-----------|---------|-----|
| **Database** | SQL Server (existing infrastructure) | Your license | Zero additional cost, leverage existing |
| **API** | ASP.NET Core 8.0 | MIT | Native async, excellent performance |
| **Data Access** | Dapper | Apache 2.0 | Lightweight, perfect for SP-only pattern |
| **UI** | Grafana OSS 10.x | Apache 2.0 | Industry standard, beautiful, SQL datasource |
| **Containers** | Docker + Docker Compose | Apache 2.0 | Cross-platform, simple deployment |
| **Collection** | SQL Agent Jobs + Linked Servers | Built-in | No external dependencies |

**Rejected Alternatives**:
- ❌ Azure SQL Database (cost, cloud lock-in)
- ❌ Azure Functions (replaced with ASP.NET Core in Docker)
- ❌ Azure Key Vault (replaced with Docker secrets/.env)
- ❌ PowerShell collectors (replaced with SQL Agent jobs)
- ❌ HangFire (replaced with SQL Agent for scheduling)
- ❌ Vue.js frontend (replaced with Grafana OSS)

## Development Methodology

### Test-Driven Development (TDD) - MANDATORY

**All code must follow TDD approach**:

1. **Write Tests First**: Before any implementation, write the test
2. **Red-Green-Refactor**:
   - Red: Write failing test
   - Green: Write minimal code to pass
   - Refactor: Improve code while keeping tests green
3. **Test Coverage**: Minimum 80% for all business logic
4. **Test Pyramid**:
   - Unit tests: 70% (fast, isolated, business logic)
   - Integration tests: 20% (database SPs, API endpoints)
   - E2E tests: 10% (full workflow validation)

#### TDD Workflow Example

```csharp
// 1. WRITE TEST FIRST (Red)
[Fact]
public async Task GetServers_ShouldReturnAllActiveServers()
{
    // Arrange
    var service = new ServerService(_mockConnection.Object);

    // Act
    var result = await service.GetServersAsync();

    // Assert
    Assert.NotEmpty(result);
    Assert.All(result, s => Assert.True(s.IsActive));
}

// 2. WRITE MINIMAL IMPLEMENTATION (Green)
public async Task<IEnumerable<ServerModel>> GetServersAsync()
{
    using var connection = new SqlConnection(_connectionString);
    return await connection.QueryAsync<ServerModel>(
        "dbo.usp_GetServers",
        commandType: CommandType.StoredProcedure
    );
}

// 3. REFACTOR (Keep tests green)
// Add error handling, logging, caching, etc.
```

#### Test File Structure

```
tests/
├── SqlServerMonitor.Api.Tests/
│   ├── Controllers/
│   │   ├── ServersControllerTests.cs
│   │   ├── MetricsControllerTests.cs
│   │   └── HealthControllerTests.cs
│   ├── Services/
│   │   ├── ServerServiceTests.cs
│   │   ├── MetricsServiceTests.cs
│   │   └── SqlServiceTests.cs
│   └── Integration/
│       ├── DatabaseIntegrationTests.cs
│       └── ApiEndpointTests.cs
└── SqlServerMonitor.Database.Tests/
    ├── StoredProcedures/
    │   ├── usp_GetServers_Tests.sql
    │   ├── usp_CollectMetrics_Tests.sql
    │   └── usp_EvaluateAlerts_Tests.sql
    └── TestData/
        └── SeedTestData.sql
```

### UI/UX Design Guidelines

**Material Design Aesthetic with Minimalist Coloring**

#### Color Palette (Minimalist)

```css
/* Primary Colors - Cool, professional grays */
--primary-bg: #FAFAFA;        /* Almost white background */
--secondary-bg: #FFFFFF;       /* Pure white for cards */
--surface: #F5F5F5;            /* Subtle surface */

/* Text Colors - High contrast for readability */
--text-primary: #212121;       /* Almost black */
--text-secondary: #757575;     /* Medium gray */
--text-disabled: #BDBDBD;      /* Light gray */

/* Accent Colors - Minimal use, high impact */
--accent-primary: #1976D2;     /* Material Blue - primary actions */
--accent-success: #388E3C;     /* Material Green - healthy status */
--accent-warning: #F57C00;     /* Material Orange - warnings */
--accent-error: #D32F2F;       /* Material Red - critical alerts */

/* Chart Colors - Data visualization */
--chart-cpu: #1976D2;          /* Blue */
--chart-memory: #7B1FA2;       /* Purple */
--chart-io: #388E3C;           /* Green */
--chart-waits: #F57C00;        /* Orange */
```

#### Typography

```css
/* Roboto font family (Material Design standard) */
font-family: 'Roboto', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;

/* Type Scale */
--font-h1: 2.5rem;    /* 40px - Page titles */
--font-h2: 2rem;      /* 32px - Section headers */
--font-h3: 1.5rem;    /* 24px - Card titles */
--font-body: 1rem;    /* 16px - Body text */
--font-caption: 0.875rem; /* 14px - Captions, labels */
--font-small: 0.75rem;    /* 12px - Tiny text */

/* Font Weights */
--weight-light: 300;
--weight-regular: 400;
--weight-medium: 500;
--weight-bold: 700;
```

#### Grafana Dashboard Design

**Panel Layout**:
- **Grid System**: 24 columns, 12px gutter
- **Card Elevation**: Subtle shadow (2dp), no heavy borders
- **Spacing**: Generous whitespace between panels (24px)
- **Rounding**: Subtle border-radius (4px)

**Example Dashboard JSON** (minimalist theme):

```json
{
  "dashboard": {
    "title": "Instance Health",
    "theme": "light",
    "style": "dark",
    "panels": [
      {
        "type": "stat",
        "title": "CPU Utilization",
        "fieldConfig": {
          "defaults": {
            "thresholds": {
              "mode": "absolute",
              "steps": [
                { "value": 0, "color": "#388E3C" },
                { "value": 70, "color": "#F57C00" },
                { "value": 90, "color": "#D32F2F" }
              ]
            },
            "unit": "percent",
            "color": { "mode": "thresholds" }
          }
        }
      }
    ]
  }
}
```

#### Design Principles

1. **Minimalism**: Remove unnecessary elements, focus on data
2. **Clarity**: High contrast text, clear labels, no ambiguity
3. **Consistency**: Same spacing, colors, typography throughout
4. **Responsiveness**: Works on desktop (primary), tablet, mobile
5. **Accessibility**: WCAG 2.1 AA compliance (4.5:1 contrast ratio minimum)

## Database Setup

Execute database scripts in numbered order from the `database/` directory:

```bash
# Connect to SQL Server (note: remove apostrophes from password in actual command)
sqlcmd -S <server> -U <username> -P <password> -C

# Execute deployment script (runs all in order)
:r database/deploy-all.sql
```

**Important**: Use `Connection Timeout` (with space), NOT `ConnectTimeout` for connection strings with Microsoft.Data.SqlClient 5.2+.

## Development Commands

### API Development

```bash
cd api

# Restore packages
dotnet restore

# Build the project
dotnet build

# Run tests (TDD - run before and after implementation)
dotnet test

# Run API in development mode (available at http://localhost:5000)
dotnet run

# Run with specific environment
ASPNETCORE_ENVIRONMENT=Development dotnet run

# Swagger UI available at: http://localhost:5000/swagger
```

### Container Development

```bash
# Build and run containers
docker-compose up --build

# Run in background
docker-compose up -d

# View logs
docker-compose logs -f

# Stop containers
docker-compose down

# Access Grafana: http://localhost:3000 (admin/admin)
# Access API: http://localhost:5000
```

### Database Testing

```sql
-- Run stored procedure tests (tSQLt framework)
EXEC tSQLt.RunAll;

-- Run specific test class
EXEC tSQLt.Run 'usp_GetServers_Tests';

-- View test results
SELECT * FROM tSQLt.TestResult;
```

## Architecture and Code Structure

### Data Collection Architecture (SQL Agent + Linked Servers)

**Collection happens server-side**, no external agents required:

```sql
-- Each monitored SQL Server runs a SQL Agent Job (every 5 minutes):
-- Job: Collect_Metrics_To_MonitoringDB

EXEC [MONITORINGDB_SERVER].[MonitoringDB].[dbo].[usp_CollectMetrics_RemoteServer]
    @ServerName = @@SERVERNAME;

-- This stored procedure uses OPENQUERY to pull DMVs:
INSERT INTO PerformanceMetrics_Staging
EXEC sp_executesql
    N'SELECT * FROM OPENQUERY([REMOTE_SERVER],
        ''SELECT @@SERVERNAME, GETUTCDATE(), counter_name, cntr_value
          FROM sys.dm_os_performance_counters''
    )';
```

**Key Advantages**:
- ✅ No PowerShell/Python/external dependencies
- ✅ Uses existing SQL Agent infrastructure
- ✅ Native SQL Server-to-SQL Server communication
- ✅ <1% CPU overhead (vs. 3% for external agents)

### Database Architecture (Stored Procedure Only Pattern)

All data access is through stored procedures - **no dynamic SQL in application code**. This is a critical architectural decision for security and performance.

**Stored Procedure Categories**:
- `usp_GetServers`, `usp_AddServer`, `usp_UpdateServer` - Server management
- `usp_CollectMetrics_RemoteServer` - Remote metrics collection
- `usp_GetMetricHistory`, `usp_GetServerSummary` - Data retrieval
- `usp_EvaluateAlertRules`, `usp_CreateAlert` - Alert management
- `usp_AnalyzeIndexFragmentation`, `usp_GetRecommendations` - Analysis
- `usp_ManagePartitions`, `usp_CleanupOldMetrics` - Maintenance

**Key Tables**:
- `Servers` - Monitored SQL Server instances inventory
- `PerformanceMetrics` - Time-series metrics (partitioned monthly, columnstore)
- `ProcedureStats` - Stored procedure performance tracking
- `QueryStoreSnapshots` - Query Store data snapshots
- `WaitStatistics` - Wait stats deltas
- `BlockingEvents`, `DeadlockEvents` - Blocking/deadlock history
- `AlertRules`, `AlertHistory` - Alerting configuration and history

**Partitioning Strategy**:

```sql
-- Monthly partitions, sliding window (keep 90 days)
CREATE PARTITION FUNCTION PF_MonitoringByMonth (DATETIME2)
AS RANGE RIGHT FOR VALUES (
    '2025-01-01', '2025-02-01', '2025-03-01', ...
);

-- Columnstore for 10x compression + fast queries
CREATE COLUMNSTORE INDEX IX_PerformanceMetrics_CS
ON dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
ON PS_MonitoringByMonth(CollectionTime);
```

### API Architecture (ASP.NET Core + Dapper)

**Thin API, business logic in SQL**:

```
api/
├── Program.cs                    # Startup, DI, middleware
├── Controllers/
│   ├── ServersController.cs      # GET/POST/PUT/DELETE /api/servers
│   ├── MetricsController.cs      # GET /api/metrics/{serverId}
│   ├── AlertsController.cs       # GET /api/alerts, alert rules
│   ├── RecommendationsController.cs # GET /api/recommendations/{serverId}
│   └── HealthController.cs       # GET /health
├── Services/
│   ├── ISqlService.cs            # Interface
│   └── SqlService.cs             # Dapper-based SP execution
├── Models/
│   ├── ServerModel.cs
│   ├── MetricModel.cs
│   ├── AlertModel.cs
│   └── RecommendationModel.cs
└── appsettings.json
```

**Data Access Pattern** (Dapper):

```csharp
// Services/SqlService.cs
public class SqlService : ISqlService
{
    private readonly string _connectionString;

    public async Task<IEnumerable<ServerModel>> GetServersAsync()
    {
        using var connection = new SqlConnection(_connectionString);
        return await connection.QueryAsync<ServerModel>(
            "dbo.usp_GetServers",
            commandType: CommandType.StoredProcedure
        );
    }

    public async Task<IEnumerable<MetricModel>> GetMetricHistoryAsync(
        int serverId, DateTime startTime, DateTime endTime)
    {
        using var connection = new SqlConnection(_connectionString);
        return await connection.QueryAsync<MetricModel>(
            "dbo.usp_GetMetricHistory",
            new { ServerId = serverId, StartTime = startTime, EndTime = endTime },
            commandType: CommandType.StoredProcedure
        );
    }
}
```

**Why Dapper?**
- ✅ Apache 2.0 license (free)
- ✅ Minimal overhead (thin wrapper over ADO.NET)
- ✅ Perfect for stored procedure-only pattern
- ✅ No ORM complexity (EF Core overkill for SP-only)

### UI Architecture (Grafana OSS)

**Grafana provides the entire UI** - no custom frontend needed:

```
dashboards/grafana/
├── provisioning/
│   ├── datasources/
│   │   └── monitoringdb.yaml       # SQL Server datasource
│   └── dashboards/
│       └── dashboards.yaml          # Dashboard provider config
└── dashboards/
    ├── 01-instance-health.json      # Overview of all servers
    ├── 02-developer-procedures.json # Stored procedure performance
    ├── 03-dba-waits.json            # Wait statistics analysis
    ├── 04-blocking-deadlocks.json   # Real-time blocking chains
    ├── 05-query-store.json          # Plan regressions
    └── 06-capacity-planning.json    # Growth trends
```

**Grafana Dashboard Queries** (SQL):

```sql
-- Example: Top 10 procedures by avg duration (last 24 hours)
-- Grafana variable: $serverId, $__timeFilter()

SELECT TOP 10
    DatabaseName,
    ProcedureName,
    AVG(AvgDurationMs) AS AvgDuration,
    SUM(ExecutionCount) AS TotalExecutions,
    MAX(MaxDurationMs) AS MaxDuration
FROM dbo.ProcedureStats
WHERE ServerID = $serverId
  AND $__timeFilter(CollectionTime)
GROUP BY DatabaseName, ProcedureName
ORDER BY AvgDuration DESC
```

## Configuration

### API Configuration (appsettings.json)

```json
{
  "ConnectionStrings": {
    "MonitoringDB": "Server=sql-prod-03;Database=MonitoringDB;User Id=monitor_api;Password=PLACEHOLDER;Encrypt=True;TrustServerCertificate=True;Connection Timeout=30"
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  }
}
```

### Docker Configuration (docker-compose.yml)

```yaml
version: '3.8'
services:
  api:
    build: ./api
    ports:
      - "5000:5000"
    environment:
      - ConnectionStrings__MonitoringDB=${DB_CONNECTION_STRING}
    restart: unless-stopped

  grafana:
    image: grafana/grafana-oss:10.2.0
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
      - GF_DATABASE_TYPE=sqlite3
    volumes:
      - grafana-data:/var/lib/grafana
      - ./dashboards/grafana/provisioning:/etc/grafana/provisioning
    restart: unless-stopped

volumes:
  grafana-data:
```

### Environment Variables (.env)

```bash
DB_CONNECTION_STRING=Server=sql-prod-03;Database=MonitoringDB;User Id=monitor_api;Password=SecurePass123;Encrypt=True;TrustServerCertificate=True;
GRAFANA_PASSWORD=AdminPass456
```

## Development Guidelines

### TDD Workflow (Step-by-Step)

1. **Create Test File First**:
   ```bash
   # Create test before implementation
   touch tests/SqlServerMonitor.Api.Tests/Services/ServerServiceTests.cs
   ```

2. **Write Failing Test**:
   ```csharp
   [Fact]
   public async Task GetServersAsync_ShouldReturnActiveServers()
   {
       // Arrange
       var service = new ServerService(_connectionString);

       // Act
       var result = await service.GetServersAsync();

       // Assert
       Assert.NotEmpty(result);
   }
   ```

3. **Run Test (Should Fail)**:
   ```bash
   dotnet test  # RED - test fails (class doesn't exist)
   ```

4. **Write Minimal Implementation**:
   ```csharp
   public class ServerService : IServerService
   {
       public async Task<IEnumerable<ServerModel>> GetServersAsync()
       {
           using var connection = new SqlConnection(_connectionString);
           return await connection.QueryAsync<ServerModel>(
               "dbo.usp_GetServers",
               commandType: CommandType.StoredProcedure
           );
       }
   }
   ```

5. **Run Test (Should Pass)**:
   ```bash
   dotnet test  # GREEN - test passes
   ```

6. **Refactor** (add logging, error handling, caching):
   ```csharp
   public async Task<IEnumerable<ServerModel>> GetServersAsync()
   {
       _logger.LogInformation("Fetching all servers");

       try
       {
           using var connection = new SqlConnection(_connectionString);
           var servers = await connection.QueryAsync<ServerModel>(
               "dbo.usp_GetServers",
               commandType: CommandType.StoredProcedure
           );

           _logger.LogInformation("Fetched {Count} servers", servers.Count());
           return servers;
       }
       catch (Exception ex)
       {
           _logger.LogError(ex, "Failed to fetch servers");
           throw;
       }
   }
   ```

7. **Run Test Again (Should Still Pass)**:
   ```bash
   dotnet test  # GREEN - test still passes after refactor
   ```

### When Adding New Features

1. **Database First** (TDD for SQL):
   - Write tSQLt test for stored procedure
   - Run test (fails)
   - Create stored procedure
   - Run test (passes)
   - Refactor SP

2. **API Layer** (TDD for C#):
   - Write xUnit test for service method
   - Run test (fails)
   - Implement service method (calls SP)
   - Run test (passes)
   - Write controller test
   - Implement controller action
   - Refactor

3. **UI Layer** (Grafana):
   - Create dashboard JSON
   - Test query in Grafana UI
   - Export JSON to `dashboards/`
   - Commit to version control

### Logging Standards

```csharp
// Use ILogger<T> with structured logging
_logger.LogInformation("Collecting metrics for server {ServerName} at {Timestamp}",
    serverName, DateTime.UtcNow);

_logger.LogWarning("Metrics collection took {DurationMs}ms for server {ServerName}",
    durationMs, serverName);

_logger.LogError(ex, "Failed to collect metrics for server {ServerName}", serverName);
```

## Common Pitfalls

1. **Connection Strings**: Use `Connection Timeout` (with space), not `ConnectTimeout`
2. **TDD**: Never write implementation before tests (breaks TDD discipline)
3. **Dynamic SQL**: Never use - all data access via stored procedures only
4. **Secrets**: Never commit to source control - use .env file (in .gitignore)
5. **Data Retention**: Large metric datasets require partitioning and cleanup
6. **Testing**: Integration tests need test database (not production)

## Deployment

### Development Environment

```bash
# 1. Setup database
sqlcmd -S localhost -d master -i database/deploy-all.sql

# 2. Create .env file
cat > .env <<EOF
DB_CONNECTION_STRING=Server=localhost;Database=MonitoringDB;Integrated Security=true;Encrypt=True;TrustServerCertificate=True;
GRAFANA_PASSWORD=admin
EOF

# 3. Start containers
docker-compose up --build

# 4. Access
# Grafana: http://localhost:3000 (admin/admin)
# API: http://localhost:5000/swagger
```

### Production Deployment

See [SETUP.md](SETUP.md) for complete production deployment guide.

## Health and Monitoring

**Health Check Endpoint**: `GET /health`

Returns:
```json
{
  "status": "Healthy",
  "database": "Connected",
  "lastCollection": "2025-10-25T10:30:00Z",
  "serversMonitored": 20,
  "staleServers": 0
}
```

**Docker Health Check**:

```dockerfile
HEALTHCHECK --interval=60s --timeout=5s --retries=3 \
  CMD curl -f http://localhost:5000/health || exit 1
```

## Key Performance Metrics

Monitor these metrics for the monitoring system itself:

- **Collection Latency**: Time from metric occurrence to storage (<5 minutes target)
- **Database Size**: MonitoringDB growth rate (<2GB/month per 10 servers)
- **Query Performance**: Dashboard queries <500ms
- **API Response Time**: <200ms for 95th percentile
- **Container Resources**: API <512MB RAM, Grafana <1GB RAM

## References

- **ASP.NET Core**: https://learn.microsoft.com/en-us/aspnet/core/
- **Dapper**: https://github.com/DapperLib/Dapper
- **Grafana**: https://grafana.com/docs/
- **Material Design**: https://m3.material.io/
- **TDD Best Practices**: https://martinfowler.com/bliki/TestDrivenDevelopment.html
- **SQL Server DMVs**: https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/
