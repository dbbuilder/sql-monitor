# Developer Onboarding Guide
## SQL Server Monitor - Phase 1.9

**Last Updated:** 2025-10-28
**Target Audience:** Developers joining the sql-monitor project

## Welcome!

This guide will help you get up and running with the sql-monitor codebase. By the end, you'll be able to:
- Set up your development environment
- Run the application locally
- Make code changes
- Run tests
- Deploy to test environments

## Project Overview

**SQL Server Monitor** is a self-hosted, enterprise-grade monitoring solution for SQL Server instances. It provides:
- Real-time performance metrics
- Historical trend analysis
- Query performance analysis
- Alerting capabilities
- Automated recommendations

### Architecture

```
┌─────────────────┐
│  Grafana OSS    │  UI Layer (dashboards, visualization)
└────────┬────────┘
         │ HTTP/REST
┌────────▼────────┐
│  ASP.NET Core   │  API Layer (REST endpoints)
│      API        │
└────────┬────────┘
         │ Dapper (stored procedures only)
┌────────▼────────┐
│   SQL Server    │  Database Layer (MonitoringDB)
│  (MonitoringDB) │  - Tables (metrics storage)
│                 │  - Stored Procedures (business logic)
│                 │  - SQL Agent Jobs (collection)
└─────────────────┘
```

### Technology Stack

| Component | Technology | Why |
|-----------|-----------|-----|
| **API** | ASP.NET Core 8.0 | Native async, excellent performance |
| **Data Access** | Dapper | Lightweight, perfect for SP-only pattern |
| **Database** | SQL Server 2019+ | Existing infrastructure, zero cost |
| **UI** | Grafana OSS 10.x | Industry standard, beautiful dashboards |
| **Testing** | xUnit + FluentAssertions + Moq | TDD-friendly, readable assertions |
| **Containers** | Docker + Docker Compose | Cross-platform, simple deployment |

## Prerequisites

### Required Software

1. **[.NET 8.0 SDK](https://dotnet.microsoft.com/download)**
   ```bash
   dotnet --version  # Should be 8.0.x
   ```

2. **[Docker Desktop](https://www.docker.com/products/docker-desktop)**
   ```bash
   docker --version
   docker-compose --version
   ```

3. **[Git](https://git-scm.com/downloads)**
   ```bash
   git --version
   ```

4. **[Visual Studio Code](https://code.visualstudio.com/)** (recommended) OR **Visual Studio 2022**

   **VS Code Extensions:**
   - C# (Microsoft)
   - C# Dev Kit (Microsoft)
   - Docker (Microsoft)
   - SQL Server (mssql) (Microsoft)
   - REST Client (Huachao Mao)

5. **[SQL Server Management Studio (SSMS)](https://learn.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms)** OR **[Azure Data Studio](https://azure.microsoft.com/en-us/products/data-studio/)**

   For database development and debugging.

### Optional Tools

- **[Postman](https://www.postman.com/downloads/)**: API testing
- **[K6](https://k6.io/docs/get-started/installation/)**: Load testing
- **[BenchmarkDotNet](https://benchmarkdotnet.org/)**: Microbenchmarking

## Setup Instructions

### Step 1: Clone the Repository

```bash
cd /mnt/d/dev2  # Or your preferred location
git clone https://github.com/your-org/sql-monitor.git
cd sql-monitor
```

### Step 2: Configure Environment Variables

Create a `.env` file in the project root (copy from `.env.example`):

```bash
cp .env.example .env
```

Edit `.env` with your test database connection:

```bash
# sql-monitor/.env
DB_CONNECTION_STRING=Server=sqltest.schoolvision.net,14333;Database=MonitoringDB_Dev;User Id=sv;Password=Gv51076!;TrustServerCertificate=True;Encrypt=Optional;Connection Timeout=30
GRAFANA_ADMIN_PASSWORD=Admin123!
GF_SERVER_HTTP_PORT=3000
```

⚠️ **Important:** Never commit `.env` file to source control (it's in `.gitignore`).

### Step 3: Deploy Database Schema

```bash
# Connect to your dev database
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -Q "CREATE DATABASE MonitoringDB_Dev"

# Deploy schema
cd database
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -d MonitoringDB_Dev -i deploy-all.sql
```

### Step 4: Build and Run Locally

**Option A: Run Without Containers**

```bash
# Terminal 1: Run API
cd api
dotnet restore
dotnet build
dotnet run  # Listens on http://localhost:5000

# Terminal 2: Run Grafana (Docker)
docker run -d \
  -p 3000:3000 \
  -e GF_SECURITY_ADMIN_PASSWORD=Admin123! \
  -v $(pwd)/dashboards/grafana/provisioning:/etc/grafana/provisioning \
  --name sql-monitor-grafana \
  grafana/grafana-oss:10.2.0
```

**Option B: Run With Docker Compose** (Recommended)

```bash
# Build and start all containers
docker-compose up --build -d

# View logs
docker-compose logs -f

# Stop containers
docker-compose down
```

### Step 5: Verify Setup

1. **API Health Check:**
   ```bash
   curl http://localhost:9000/health
   # Should return: {"status":"Healthy",...}
   ```

2. **API Swagger UI:**
   Open browser: `http://localhost:9000/swagger`

3. **Grafana:**
   Open browser: `http://localhost:9001`
   - Username: `admin`
   - Password: `Admin123!` (from `.env`)

## Project Structure

```
sql-monitor/
├── api/                        # ASP.NET Core REST API
│   ├── Controllers/            # REST endpoints
│   │   ├── ServersController.cs
│   │   └── QueriesController.cs
│   ├── Services/               # Business logic layer
│   │   ├── IServerService.cs
│   │   ├── ServerService.cs
│   │   ├── IQueryService.cs
│   │   └── QueryService.cs
│   ├── Models/                 # DTOs
│   │   ├── ServerModels.cs
│   │   └── QueryModels.cs
│   ├── Program.cs              # Startup & DI config
│   ├── appsettings.json        # Configuration
│   └── Dockerfile
├── api.tests/                  # xUnit tests
│   ├── Controllers/            # Controller unit tests
│   ├── Services/               # Service unit tests
│   ├── Integration/            # Integration tests
│   └── appsettings.Test.json
├── database/                   # SQL scripts
│   ├── 01-CREATE-DATABASE.sql
│   ├── 02-CREATE-TABLES.sql
│   ├── ...
│   ├── 26-create-aggregation-procedures.sql
│   └── deploy-all.sql
├── dashboards/grafana/         # Grafana dashboards
│   ├── provisioning/
│   │   ├── datasources/
│   │   └── dashboards/
│   └── dashboards/
│       ├── 01-instance-health.json
│       └── ...
├── docs/                       # Documentation
│   ├── api/                    # API docs (Postman, etc.)
│   ├── guides/                 # User guides
│   └── phases/                 # Phase completion docs
├── scripts/                    # Utility scripts
│   ├── k6-load-test.js
│   └── ...
├── docker-compose.yml          # Docker orchestration
├── .env                        # Environment config (DO NOT COMMIT)
├── .env.example                # Environment template
├── .gitignore
├── README.md
├── CLAUDE.md                   # AI assistant context
└── TODO.md
```

## Development Workflow

### 1. Create Feature Branch

```bash
git checkout -b feature/your-feature-name
```

### 2. Make Changes (TDD Approach)

**ALWAYS follow Test-Driven Development:**

1. **Write Test First** (RED)
   ```csharp
   // api.tests/Controllers/ServersControllerTests.cs
   [Fact]
   public async Task GetServer_ShouldReturnNotFound_WhenServerDoesNotExist()
   {
       // Arrange
       _mockServerService.Setup(s => s.GetServerByIdAsync(999))
           .ReturnsAsync((ServerModel?)null);

       // Act
       var result = await _controller.GetServer(999);

       // Assert
       result.Result.Should().BeOfType<NotFoundObjectResult>();
   }
   ```

2. **Run Test (Should Fail)**
   ```bash
   cd api.tests
   dotnet test
   # Test should fail (RED)
   ```

3. **Write Minimal Code** (GREEN)
   ```csharp
   // api/Controllers/ServersController.cs
   [HttpGet("{id}")]
   public async Task<ActionResult<ServerModel>> GetServer(int id)
   {
       var server = await _serverService.GetServerByIdAsync(id);
       if (server == null)
           return NotFound(new { error = $"Server {id} not found" });
       return Ok(server);
   }
   ```

4. **Run Test Again (Should Pass)**
   ```bash
   dotnet test
   # Test should pass (GREEN)
   ```

5. **Refactor** (REFACTOR)
   - Add logging
   - Add error handling
   - Add validation
   - Run tests again (should still pass)

### 3. Run Tests

```bash
# All tests
dotnet test

# Unit tests only (fast)
dotnet test --filter "Category!=Integration"

# Integration tests only (requires database)
dotnet test --filter "Category=Integration"

# Specific test
dotnet test --filter "FullyQualifiedName~GetServer_ShouldReturnNotFound_WhenServerDoesNotExist"

# With code coverage
dotnet test /p:CollectCoverage=true /p:CoverletOutputFormat=opencover
```

### 4. Run Locally

```bash
# Start API
cd api
dotnet run --urls "http://localhost:5000"

# Start containers
docker-compose up -d
```

### 5. Manual Testing

**Using Swagger UI:**
- Navigate to `http://localhost:5000/swagger`
- Try API endpoints interactively

**Using Postman:**
- Import `docs/api/sql-monitor-api.postman_collection.json`
- Import environment: `docs/api/sql-monitor-environments.postman_environment.json`
- Run requests

**Using cURL:**
```bash
# Get all servers
curl http://localhost:5000/api/servers

# Get server health
curl http://localhost:5000/api/servers/health

# Get top queries
curl "http://localhost:5000/api/queries/top?topN=10"
```

### 6. Commit Changes

```bash
git add .
git commit -m "feat: Add GetServer endpoint with 404 handling"
```

**Commit Message Format:**
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation only
- `test:` Adding tests
- `refactor:` Code restructuring
- `perf:` Performance improvement

### 7. Push and Create Pull Request

```bash
git push origin feature/your-feature-name
```

Then create a Pull Request on GitHub.

## Common Development Tasks

### Adding a New API Endpoint

1. **Define the interface:**
   ```csharp
   // api/Services/IServerService.cs
   Task<IEnumerable<ServerModel>> GetServersByEnvironmentAsync(string environment);
   ```

2. **Write unit test:**
   ```csharp
   // api.tests/Services/ServerServiceTests.cs
   [Fact]
   public async Task GetServersByEnvironmentAsync_ShouldReturnFilteredServers()
   {
       // Test implementation
   }
   ```

3. **Implement service method:**
   ```csharp
   // api/Services/ServerService.cs
   public async Task<IEnumerable<ServerModel>> GetServersByEnvironmentAsync(string environment)
   {
       using var connection = new SqlConnection(_connectionString);
       return await connection.QueryAsync<ServerModel>(
           "dbo.usp_GetServers",
           new { Environment = environment },
           commandType: CommandType.StoredProcedure);
   }
   ```

4. **Add controller action:**
   ```csharp
   // api/Controllers/ServersController.cs
   [HttpGet("by-environment/{environment}")]
   public async Task<ActionResult<IEnumerable<ServerModel>>> GetServersByEnvironment(string environment)
   {
       var servers = await _serverService.GetServersByEnvironmentAsync(environment);
       return Ok(servers);
   }
   ```

5. **Test manually** via Swagger or Postman

### Adding a New Stored Procedure

1. **Create SQL file:**
   ```sql
   -- database/27-create-new-procedure.sql
   CREATE PROCEDURE dbo.usp_GetTopDatabases
       @ServerID INT = NULL,
       @TopN INT = 10
   AS
   BEGIN
       SELECT TOP (@TopN)
           ServerID,
           DatabaseName,
           TotalSizeMB
       FROM dbo.DatabaseSnapshots
       WHERE (@ServerID IS NULL OR ServerID = @ServerID)
       ORDER BY TotalSizeMB DESC;
   END
   GO
   ```

2. **Deploy to dev database:**
   ```bash
   sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -d MonitoringDB_Dev -i database/27-create-new-procedure.sql
   ```

3. **Update deploy-all.sql:**
   Add `:r 27-create-new-procedure.sql` to `database/deploy-all.sql`

4. **Use in service layer** (see "Adding a New API Endpoint")

### Debugging

**VS Code:**
1. Set breakpoint (click left of line number)
2. Press F5 (or Run > Start Debugging)
3. Select ".NET Core Launch (web)"
4. Trigger the endpoint

**Visual Studio 2022:**
1. Open `api/SqlMonitor.Api.csproj`
2. Set breakpoint
3. Press F5
4. Trigger the endpoint

**Database Debugging:**
1. Open SSMS
2. Right-click stored procedure > "Execute Stored Procedure..."
3. Set input parameters
4. View results or use `PRINT` statements

## Testing Guidelines

### Unit Test Structure

```csharp
[Fact]  // or [Theory] with [InlineData]
public async Task MethodName_ShouldExpectedBehavior_WhenCondition()
{
    // Arrange: Set up test data and mocks
    var mockService = new Mock<IServerService>();
    mockService.Setup(s => s.GetServerByIdAsync(1))
        .ReturnsAsync(new ServerModel { ServerID = 1, ServerName = "TEST" });

    var controller = new ServersController(mockService.Object, _mockLogger.Object);

    // Act: Execute the method under test
    var result = await controller.GetServer(1);

    // Assert: Verify expectations
    var okResult = result.Result.Should().BeOfType<OkObjectResult>().Subject;
    var server = okResult.Value.Should().BeOfType<ServerModel>().Subject;
    server.ServerID.Should().Be(1);
}
```

### Integration Test Structure

```csharp
[Trait("Category", "Integration")]
[Collection("Database")]
public class ServerServiceIntegrationTests : IAsyncLifetime
{
    public async Task InitializeAsync()
    {
        // Setup: Create test data
    }

    public async Task DisposeAsync()
    {
        // Cleanup: Remove test data
    }

    [Fact]
    public async Task GetServersAsync_ShouldReturnServers_WhenDatabaseHasData()
    {
        // Integration test with real database
    }
}
```

### Test Coverage Goals

- **Unit Tests:** 80%+ coverage
- **Integration Tests:** All service methods
- **E2E Tests:** Critical user workflows

## Code Style

### General Guidelines

- Follow [Microsoft C# Coding Conventions](https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/coding-style/coding-conventions)
- Use meaningful variable names
- Keep methods small (< 50 lines)
- Use async/await consistently
- Add XML comments for public APIs
- No emojis in code (unless user requests)

### Naming Conventions

| Type | Convention | Example |
|------|-----------|---------|
| Classes | PascalCase | `ServerService` |
| Interfaces | IPascalCase | `IServerService` |
| Methods | PascalCase | `GetServerByIdAsync` |
| Parameters | camelCase | `serverId` |
| Private fields | _camelCase | `_logger` |
| Constants | UPPER_CASE | `MAX_RETRIES` |

### Example Good Code

```csharp
/// <summary>
/// Retrieves server health status with 24-hour metrics
/// </summary>
/// <param name="serverId">Server ID to query</param>
/// <returns>Server health data or null if not found</returns>
public async Task<ServerHealthModel?> GetServerHealthStatusAsync(int serverId)
{
    try
    {
        using var connection = new SqlConnection(_connectionString);

        var health = await connection.QueryAsync<ServerHealthModel>(
            "dbo.usp_GetServerHealthStatus",
            new { ServerID = serverId },
            commandType: CommandType.StoredProcedure);

        var result = health.FirstOrDefault();

        _logger.LogInformation(
            "Retrieved health status for server {ServerId}: {HealthStatus}",
            serverId,
            result?.HealthStatus ?? "Not found");

        return result;
    }
    catch (Exception ex)
    {
        _logger.LogError(ex, "Error retrieving health status for server {ServerId}", serverId);
        throw;
    }
}
```

## Troubleshooting

### Connection String Issues

**Error:** "Keyword not supported: 'ConnectTimeout'"

**Solution:** Use `Connection Timeout` (with space):
```
Connection Timeout=30  ✅
ConnectTimeout=30      ❌
```

### Docker Build Failures

**Error:** "Cannot connect to Docker daemon"

**Solution:**
```bash
# Start Docker Desktop
# Or on Linux:
sudo systemctl start docker
```

### Test Database Issues

**Error:** "Database 'MonitoringDB_Dev' does not exist"

**Solution:**
```bash
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -Q "CREATE DATABASE MonitoringDB_Dev"
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -d MonitoringDB_Dev -i database/deploy-all.sql
```

### Missing NuGet Packages

**Error:** "The type or namespace name 'Dapper' could not be found"

**Solution:**
```bash
cd api
dotnet restore
dotnet build
```

## Getting Help

1. **Check Documentation:**
   - `README.md` - Project overview
   - `CLAUDE.md` - Architecture and patterns
   - `docs/` folder - Comprehensive guides

2. **Ask Team:**
   - Slack: #sql-monitor-dev
   - Email: dev-team@yourcompany.com

3. **Debug Yourself:**
   - Check logs: `docker-compose logs -f`
   - Check database: Connect via SSMS
   - Check API: `http://localhost:5000/swagger`

## Next Steps

1. ✅ Complete setup (you're here!)
2. 📚 Read `ARCHITECTURE.md` for deep-dive
3. 🧪 Run all tests: `dotnet test`
4. 🚀 Deploy to dev environment
5. 🎯 Pick up a task from Jira/GitHub Issues
6. 🤝 Create your first Pull Request!

## Quick Reference

```bash
# Start everything
docker-compose up -d

# Stop everything
docker-compose down

# View logs
docker-compose logs -f

# Run tests
dotnet test

# Start API only
cd api && dotnet run

# Deploy database
cd database && sqlcmd -S server -U user -P pass -C -d db -i deploy-all.sql

# Health check
curl http://localhost:9000/health

# Swagger UI
open http://localhost:9000/swagger

# Grafana
open http://localhost:9001  # admin/Admin123!
```

Welcome to the team! 🎉
