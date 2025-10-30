# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SQL Server Monitor is a **self-hosted, enterprise-grade monitoring solution** for SQL Server instances providing real-time performance metrics, historical trend analysis, alerting capabilities, and automated recommendations.

**Current Phase**: Phase 2.0 (SOC 2 Compliance) - Authentication, Authorization, and Audit Logging ✅

### Project Evolution

The project has evolved from a simple monitoring solution to an enterprise-grade platform with:
- ✅ **Phase 1.0**: Core database foundation, DMV collection, Grafana dashboards
- ✅ **Phase 1.25**: Schema browser with metadata caching (615 objects in 250ms)
- 🔄 **Phase 2.0**: Authentication (JWT + MFA), RBAC, audit logging, session management
- 📋 **Phase 2.5+**: GDPR, PCI-DSS, HIPAA, FERPA compliance frameworks
- 📋 **Phase 3+**: Killer features, code editor, AI layer

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
| **Authentication** | JWT + BCrypt + TOTP | MIT | Industry-standard security |

**Rejected Alternatives**:
- ❌ Azure SQL Database (cost, cloud lock-in)
- ❌ Azure Functions (replaced with ASP.NET Core in Docker)
- ❌ Azure Key Vault (replaced with Docker secrets/.env)
- ❌ PowerShell collectors (replaced with SQL Agent jobs)
- ❌ HangFire (replaced with SQL Agent for scheduling)
- ❌ Vue.js frontend (replaced with Grafana OSS)

## Project Structure

```
sql-monitor/
├── api/                         # ASP.NET Core 8.0 REST API
│   ├── Controllers/             # Auth, MFA, Session, Server, Metrics, Code
│   ├── Services/                # SQL, JWT, Password, TOTP, BackupCode
│   ├── Models/                  # DTOs (Server, Metrics, Auth, MFA, Session)
│   ├── Middleware/              # Audit logging, authorization
│   ├── Attributes/              # RequirePermission attribute
│   ├── Program.cs               # Startup, DI, JWT config
│   └── Dockerfile
├── database/                    # MonitoringDB schema (numbered for deployment order)
│   ├── 01-create-database.sql
│   ├── 02-create-tables.sql
│   ├── 03-create-partitions.sql
│   ├── 04-create-procedures.sql
│   ├── 05-create-rds-equivalent-procedures.sql
│   ├── 06-create-drilldown-tables.sql
│   ├── 07-create-drilldown-procedures.sql
│   ├── 08-create-master-collection-procedure.sql
│   ├── 09-create-sql-agent-jobs.sql
│   ├── 10-create-extended-events-tables.sql
│   ├── 11-create-extended-events-procedures.sql
│   ├── 12-create-alerting-system.sql
│   ├── 13-create-index-maintenance.sql
│   ├── 14-create-schema-metadata-infrastructure.sql
│   └── (15-20): Phase 2.0 auth/audit tables and procedures
├── tests/                       # xUnit tests (TDD-first approach)
│   └── SqlMonitor.Api.Tests/
│       └── Services/            # BackupCodeServiceTests, TotpServiceTests
├── dashboards/                  # Grafana dashboard JSON templates
│   └── grafana/
│       ├── provisioning/        # Datasources and dashboard providers
│       └── dashboards/          # Instance health, developer, DBA, code browser
├── scripts/                     # Deployment and maintenance scripts
├── sql-monitor-agent/           # Lightweight DMV collector for Linux SQL Server
│   └── (SQL scripts for DBATools database with SQL Agent jobs)
├── sql-http-bridge/             # Cross-platform HTTP-to-sqlcmd bridge
│   ├── service/                 # Python HTTP service (localhost-only)
│   ├── linux/                   # systemd service definition
│   └── windows/                 # NSSM Windows Service setup
├── docker-compose.yml           # API (port 9000) + Grafana (port 9001)
├── .env                         # Environment variables (DB connection, JWT secret)
└── docs/                        # Phase plans and implementation guides
    ├── phases/                  # Detailed phase documentation
    ├── milestones/              # Phase completion summaries
    └── TACTICAL-IMPLEMENTATION-GUIDE.md
```

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
└── SqlMonitor.Api.Tests/
    ├── Controllers/
    │   ├── AuthControllerTests.cs
    │   ├── MfaControllerTests.cs
    │   ├── SessionControllerTests.cs
    │   ├── ServersControllerTests.cs
    │   ├── MetricsControllerTests.cs
    │   └── HealthControllerTests.cs
    ├── Services/
    │   ├── ServerServiceTests.cs
    │   ├── MetricsServiceTests.cs
    │   ├── SqlServiceTests.cs
    │   ├── JwtServiceTests.cs
    │   ├── PasswordServiceTests.cs
    │   ├── TotpServiceTests.cs
    │   └── BackupCodeServiceTests.cs
    ├── Middleware/
    │   ├── AuditMiddlewareTests.cs
    │   └── AuthorizationMiddlewareTests.cs
    └── Integration/
        ├── DatabaseIntegrationTests.cs
        └── ApiEndpointTests.cs
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

## Database Setup

Execute database scripts in numbered order from the `database/` directory:

```bash
# Connect to SQL Server (WSL environment note: use host IP, not localhost)
sqlcmd -S 172.31.208.1,14333 -U sv -P YourPassword -C

# Execute deployment script (runs all in order)
:r database/deploy-all.sql
```

**Important Connection String Notes**:
- Use `Connection Timeout` (with space), NOT `ConnectTimeout` for Microsoft.Data.SqlClient 5.2+
- WSL Environment: Use WSL host IP (e.g., 172.31.208.1), not localhost
- Port Syntax: Use comma separator (e.g., `server,port`)

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

# Run API in development mode
dotnet run
# Available at: http://localhost:9000
# Swagger UI: http://localhost:9000/swagger

# Run with specific environment
ASPNETCORE_ENVIRONMENT=Development dotnet run

# Run tests with coverage
dotnet test --collect:"XPlat Code Coverage"
```

### Container Development

```bash
# Build and run containers
docker-compose up --build

# Run in background
docker-compose up -d

# View logs
docker-compose logs -f api
docker-compose logs -f grafana

# Stop containers
docker-compose down

# Rebuild single service
docker-compose up --build api

# Access services:
# - Grafana: http://localhost:9001 (admin/admin)
# - API: http://localhost:9000
# - Swagger: http://localhost:9000/swagger
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

### Running Single Tests

```bash
# Run specific test file
dotnet test --filter "FullyQualifiedName~TotpServiceTests"

# Run specific test method
dotnet test --filter "FullyQualifiedName~TotpServiceTests.GenerateSecretKey_ShouldReturnBase32String"

# Run tests by category (if using [Trait] attributes)
dotnet test --filter "Category=Unit"
```

## Architecture and Code Structure

### Authentication & Authorization (Phase 2.0)

**Security Architecture**:
- **Authentication**: JWT tokens with 8-hour expiration, 5-minute clock skew
- **MFA**: TOTP (Time-based One-Time Password) with QR code generation
- **Backup Codes**: 10 single-use codes generated at MFA setup
- **Password Hashing**: BCrypt with automatic salt generation
- **Session Management**: Server-side session tracking with automatic cleanup
- **Audit Logging**: All API requests logged with user, action, IP, timestamp

**API Endpoints**:
```
POST /api/auth/register          # Create new user account
POST /api/auth/login             # Username/password authentication
POST /api/mfa/setup              # Generate MFA secret + QR code
POST /api/mfa/verify             # Verify TOTP code, return JWT
POST /api/mfa/validate           # Validate backup code
GET  /api/session/active         # List active sessions
DELETE /api/session/{id}         # Terminate session
```

**Authorization Middleware**:
- Custom `AuthorizationMiddleware` enforces permissions before controller execution
- `[RequirePermission("permission_name")]` attribute on controller actions
- Permissions cached in IMemoryCache for performance
- Row-level security via `@UserID` parameter in stored procedures

**Audit Middleware**:
- `AuditMiddleware` logs all requests BEFORE authentication
- Captures: UserId, Action, Resource, IP, UserAgent, Timestamp, Success/Failure
- Stored in `dbo.AuditLog` table via `usp_LogAuditEntry` stored procedure

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

**Core Monitoring**:
- `usp_GetServers`, `usp_AddServer`, `usp_UpdateServer` - Server management
- `usp_CollectMetrics_RemoteServer` - Remote metrics collection
- `usp_GetMetricHistory`, `usp_GetServerSummary` - Data retrieval
- `usp_EvaluateAlertRules`, `usp_CreateAlert` - Alert management
- `usp_AnalyzeIndexFragmentation`, `usp_GetRecommendations` - Analysis
- `usp_ManagePartitions`, `usp_CleanupOldMetrics` - Maintenance

**Authentication & Authorization (Phase 2.0)**:
- `usp_CreateUser`, `usp_GetUserByUsername` - User management
- `usp_UpdateUserPassword` - Password changes
- `usp_CreateRole`, `usp_AssignRoleToUser` - RBAC
- `usp_CreatePermission`, `usp_AssignPermissionToRole` - Permissions
- `usp_GetUserPermissions` - Permission resolution
- `usp_CreateSession`, `usp_UpdateSessionStatus`, `usp_GetActiveSessions` - Sessions
- `usp_EnableMFA`, `usp_GetUserMFA`, `usp_GenerateBackupCodes` - MFA
- `usp_LogAuditEntry`, `usp_GetAuditLog` - Audit logging

**Key Tables**:
- `Servers` - Monitored SQL Server instances inventory
- `PerformanceMetrics` - Time-series metrics (partitioned monthly, columnstore)
- `ProcedureStats` - Stored procedure performance tracking
- `QueryStoreSnapshots` - Query Store data snapshots
- `WaitStatistics` - Wait stats deltas
- `BlockingEvents`, `DeadlockEvents` - Blocking/deadlock history
- `AlertRules`, `AlertHistory` - Alerting configuration and history
- `Users`, `Roles`, `Permissions` - RBAC tables (Phase 2.0)
- `UserRoles`, `RolePermissions` - Many-to-many relationships
- `UserSessions` - Active session tracking
- `UserMFA` - MFA configuration (TOTP secrets, backup codes)
- `AuditLog` - Comprehensive audit trail

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
├── Program.cs                    # Startup, DI, middleware, JWT config
├── Controllers/
│   ├── AuthController.cs         # POST /api/auth/register, /login
│   ├── MfaController.cs          # POST /api/mfa/setup, /verify, /validate
│   ├── SessionController.cs      # GET/DELETE /api/session
│   ├── ServerController.cs       # GET/POST/PUT/DELETE /api/servers
│   ├── MetricsController.cs      # GET /api/metrics/{serverId}
│   ├── CodeController.cs         # GET /api/code/objects (Phase 1.25)
│   └── HealthController.cs       # GET /health
├── Services/
│   ├── ISqlService.cs            # Interface for SQL operations
│   ├── SqlService.cs             # Dapper-based SP execution
│   ├── IJwtService.cs            # JWT token generation/validation
│   ├── JwtService.cs             # Implementation
│   ├── IPasswordService.cs       # Password hashing/verification
│   ├── PasswordService.cs        # BCrypt implementation
│   ├── ITotpService.cs           # TOTP generation/validation
│   ├── TotpService.cs            # Otp.NET + QRCoder
│   ├── IBackupCodeService.cs     # Backup code management
│   └── BackupCodeService.cs      # Implementation
├── Middleware/
│   ├── AuditMiddleware.cs        # Request logging (before auth)
│   └── AuthorizationMiddleware.cs # Permission enforcement (after auth)
├── Attributes/
│   └── RequirePermissionAttribute.cs # Declarative permission checks
├── Models/
│   ├── Server.cs
│   ├── PerformanceMetric.cs
│   ├── ObjectCode.cs             # Phase 1.25: Schema metadata
│   ├── UserAuthInfo.cs           # Authentication DTOs
│   ├── UserMFA.cs                # MFA setup/verification DTOs
│   └── UserSession.cs            # Session management DTOs
└── appsettings.json
    {
      "ConnectionStrings": {
        "MonitoringDB": "Server=...;Database=MonitoringDB;..."
      },
      "Jwt": {
        "SecretKey": "your-256-bit-secret",
        "Issuer": "SqlMonitor.Api",
        "Audience": "SqlMonitor.Client",
        "ExpirationHours": 8
      }
    }
```

**Data Access Pattern** (Dapper):

```csharp
// Services/SqlService.cs
public class SqlService : ISqlService
{
    private readonly SqlConnectionFactory _connectionFactory;

    public async Task<IEnumerable<ServerModel>> GetServersAsync()
    {
        using var connection = _connectionFactory.CreateConnection();
        return await connection.QueryAsync<ServerModel>(
            "dbo.usp_GetServers",
            commandType: CommandType.StoredProcedure
        );
    }

    public async Task<IEnumerable<MetricModel>> GetMetricHistoryAsync(
        int serverId, DateTime startTime, DateTime endTime)
    {
        using var connection = _connectionFactory.CreateConnection();
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
    ├── 06-capacity-planning.json    # Growth trends
    └── 07-code-browser.json         # Phase 1.25: Schema browser
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
  "Jwt": {
    "SecretKey": "your-super-secret-256-bit-key-here",
    "Issuer": "SqlMonitor.Api",
    "Audience": "SqlMonitor.Client",
    "ExpirationHours": 8
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
      - "9000:9000"
    environment:
      - ConnectionStrings__MonitoringDB=${DB_CONNECTION_STRING}
      - Jwt__SecretKey=${JWT_SECRET_KEY}
      - ASPNETCORE_ENVIRONMENT=${ASPNETCORE_ENVIRONMENT:-Development}
    restart: unless-stopped

  grafana:
    image: grafana/grafana-oss:10.2.0
    ports:
      - "9001:3000"
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
DB_CONNECTION_STRING=Server=172.31.208.1,14333;Database=MonitoringDB;User Id=monitor_api;Password=SecurePass123;Encrypt=True;TrustServerCertificate=True;Connection Timeout=30
JWT_SECRET_KEY=your-super-secret-256-bit-key-change-this-in-production
GRAFANA_PASSWORD=AdminPass456
ASPNETCORE_ENVIRONMENT=Development
GF_SERVER_HTTP_PORT=9001
```

## Development Guidelines

### TDD Workflow (Step-by-Step)

1. **Create Test File First**:
   ```bash
   # Create test before implementation
   cd tests/SqlMonitor.Api.Tests
   mkdir -p Services
   touch Services/TotpServiceTests.cs
   ```

2. **Write Failing Test**:
   ```csharp
   [Fact]
   public void GenerateSecretKey_ShouldReturnBase32String()
   {
       // Arrange
       var service = new TotpService();

       // Act
       var secret = service.GenerateSecretKey();

       // Assert
       Assert.NotEmpty(secret);
       Assert.Matches(@"^[A-Z2-7]+$", secret); // Base32 format
   }
   ```

3. **Run Test (Should Fail)**:
   ```bash
   dotnet test  # RED - test fails (class doesn't exist)
   ```

4. **Write Minimal Implementation**:
   ```csharp
   public class TotpService : ITotpService
   {
       public string GenerateSecretKey()
       {
           var key = KeyGeneration.GenerateRandomKey(20);
           return Base32Encoding.ToString(key);
       }
   }
   ```

5. **Run Test (Should Pass)**:
   ```bash
   dotnet test  # GREEN - test passes
   ```

6. **Refactor** (add logging, error handling):
   ```csharp
   public string GenerateSecretKey()
   {
       try
       {
           var key = KeyGeneration.GenerateRandomKey(20);
           var base32Secret = Base32Encoding.ToString(key);
           _logger.LogInformation("Generated TOTP secret key");
           return base32Secret;
       }
       catch (Exception ex)
       {
           _logger.LogError(ex, "Failed to generate TOTP secret");
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

// Security logging (authentication events)
_logger.LogWarning("Failed login attempt for user {Username} from IP {IpAddress}",
    username, ipAddress);

_logger.LogInformation("User {Username} logged in successfully with MFA",
    username);
```

## Common Pitfalls

1. **Connection Strings**: Use `Connection Timeout` (with space), not `ConnectTimeout` (Microsoft.Data.SqlClient 5.2+)
2. **TDD**: Never write implementation before tests (breaks TDD discipline)
3. **Dynamic SQL**: Never use - all data access via stored procedures only
4. **Secrets**: Never commit to source control - use .env file (in .gitignore)
5. **Data Retention**: Large metric datasets require partitioning and cleanup
6. **Testing**: Integration tests need test database (not production)
7. **JWT Secrets**: Use 256-bit keys (32+ characters), rotate regularly
8. **Password Storage**: Never store plaintext passwords, always use BCrypt
9. **MFA Backup Codes**: Generate 10 codes, mark as used after validation
10. **Audit Logging**: Log before authentication to capture unauthorized attempts

## Deployment

### Azure Grafana Container Deployment (2025-10-30)

**Production Container:**
- **Name:** grafana-schoolvision
- **Resource Group:** rg-sqlmonitor-schoolvision
- **Subscription:** Test Environment (7b2beff3-b38a-4516-a75f-3216725cc4e9)
- **Registry:** sqlmonitoracr.azurecr.io
- **URL:** http://schoolvision-sqlmonitor.eastus.azurecontainer.io:3000
- **Credentials:** admin / NewSecurePassword123

**Deployment Script (No Docker Desktop Required):**
```powershell
# From D:\Dev2\sql-monitor
.\Deploy-Grafana-Update-ACR.ps1
```

**This script:**
- ✅ Uses `az acr build` (builds in Azure, not locally)
- ✅ No Docker Desktop installation required
- ✅ Builds image in Azure Container Registry
- ✅ Restarts container automatically
- ✅ Verifies deployment with logs
- ✅ Time: 3-5 minutes

**Key Features (2025-10-30):**
- ✅ **15 dashboards** (including AWS RDS Performance Insights)
- ✅ **Auto-refresh system** - Webhook on port 8888
- ✅ **Dashboard refresh button** - Update from GitHub without rebuild
- ✅ **Zero downtime updates** - Add dashboards via UI button

**Dashboard Management:**
1. Navigate to: http://schoolvision-sqlmonitor.eastus.azurecontainer.io:3000/d/admin-dashboard-refresh
2. Click "Refresh Dashboards from GitHub"
3. Wait 15 seconds
4. New dashboards appear automatically!

**Alternative Deployment (Requires Docker Desktop):**
```powershell
.\Deploy-Grafana-Update.ps1
```

### Development Environment

```bash
# 1. Setup database
sqlcmd -S 172.31.208.1,14333 -U sa -P YourPassword -C -i database/deploy-all.sql

# 2. Create .env file
cat > .env <<EOF
DB_CONNECTION_STRING=Server=172.31.208.1,14333;Database=MonitoringDB;Integrated Security=false;User Id=sa;Password=YourPassword;Encrypt=True;TrustServerCertificate=True;Connection Timeout=30
JWT_SECRET_KEY=$(openssl rand -base64 32)
GRAFANA_PASSWORD=admin
ASPNETCORE_ENVIRONMENT=Development
GF_SERVER_HTTP_PORT=9001
EOF

# 3. Start containers
docker-compose up --build

# 4. Access
# Grafana: http://localhost:9001 (admin/admin)
# API: http://localhost:9000/swagger
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
  CMD curl -f http://localhost:9000/health || exit 1
```

## Key Performance Metrics

Monitor these metrics for the monitoring system itself:

- **Collection Latency**: Time from metric occurrence to storage (<5 minutes target)
- **Database Size**: MonitoringDB growth rate (<2GB/month per 10 servers)
- **Query Performance**: Dashboard queries <500ms
- **API Response Time**: <200ms for 95th percentile
- **Container Resources**: API <512MB RAM, Grafana <1GB RAM
- **Auth Performance**: JWT generation <50ms, BCrypt hashing <200ms
- **MFA Validation**: TOTP verification <100ms

## Related Components

### sql-monitor-agent

Lightweight DMV collector for Linux SQL Server 2022 Standard Edition. Creates a minimal monitoring infrastructure in a `DBATools` database with SQL Agent jobs that collect server health, database statistics, and active workload every 5 minutes.

**Key Features**:
- Minimal performance overhead (DMV sampling only)
- Linux-compatible (no Windows-specific features)
- SQL Server Standard Edition compatible
- Self-contained within DBATools database

**Installation**: Execute scripts in `sql-monitor-agent/` directory in numerical order.

### sql-http-bridge

Cross-platform HTTP-to-sqlcmd bridge that provides a localhost-only HTTP service for executing allowlisted stored procedures. Works on both Linux (systemd) and Windows Server (NSSM service).

**Security Model**:
- Localhost bind only (127.0.0.1:8080)
- SQL auth required on every call
- Least-privilege SQL login with EXECUTE-only permissions
- Allowlist of stored procedures (no dynamic SQL)
- Comprehensive audit logging

**Installation**: See `sql-http-bridge/README.md` for Linux/Windows setup instructions.

## References

- **ASP.NET Core**: https://learn.microsoft.com/en-us/aspnet/core/
- **Dapper**: https://github.com/DapperLib/Dapper
- **Grafana**: https://grafana.com/docs/
- **Material Design**: https://m3.material.io/
- **TDD Best Practices**: https://martinfowler.com/bliki/TestDrivenDevelopment.html
- **SQL Server DMVs**: https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/
- **JWT Authentication**: https://jwt.io/introduction
- **TOTP (RFC 6238)**: https://datatracker.ietf.org/doc/html/rfc6238
- **BCrypt**: https://github.com/BcryptNet/bcrypt.net
