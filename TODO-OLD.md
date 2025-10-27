# SQL Server Monitor - Implementation TODO

**Last Updated**: 2025-10-25
**Methodology**: Test-Driven Development (TDD) - Red-Green-Refactor
**Status**: Phase 1 (Database Foundation) - 0% Complete

## Implementation Principles

1. **TDD is MANDATORY**: Write tests BEFORE implementation
2. **Red-Green-Refactor Cycle**:
   - 🔴 RED: Write failing test
   - 🟢 GREEN: Write minimal code to pass
   - 🔵 REFACTOR: Improve code (test stays green)
3. **Test Coverage**: Minimum 80% for all business logic
4. **Material Design**: Minimalist colors, Grafana dashboards
5. **Air-Gap Compliance**: Zero external dependencies

## Progress Tracking

| Phase | Status | Progress | Est. Hours |
|-------|--------|----------|------------|
| **Phase 1: Database Foundation** | 🔴 Not Started | 0/25 tasks | 40h |
| **Phase 2: API Development** | ⚪ Blocked | 0/20 tasks | 30h |
| **Phase 3: Grafana Dashboards** | ⚪ Blocked | 0/15 tasks | 20h |
| **Phase 4: Integration & Testing** | ⚪ Blocked | 0/10 tasks | 15h |
| **Phase 5: Documentation & Deployment** | ⚪ Blocked | 0/8 tasks | 10h |
| **TOTAL** | 🔴 0% | 0/78 tasks | **115h** |

---

## Phase 1: Database Foundation (TDD with tSQLt)

**Goal**: Create MonitoringDB schema, stored procedures, and SQL Agent jobs with full test coverage.

**Prerequisites**:
- SQL Server 2016+ instance chosen for MonitoringDB
- SQL Server Management Studio (SSMS) or Azure Data Studio
- Git repository cloned locally

### 1.1: Test Framework Setup

- [ ] **Task 1.1.1**: Install tSQLt framework in MonitoringDB
  ```sql
  -- Download tSQLt.zip from https://tsqlt.org
  -- Extract and run:
  EXEC sp_configure 'clr enabled', 1; RECONFIGURE;
  EXEC sp_executesql @stmt = N'...'; -- tSQLt installation SQL
  EXEC tSQLt.RunAll; -- Verify installation
  ```
  **Acceptance**: `SELECT * FROM tSQLt.TestClasses;` returns system test classes

- [ ] **Task 1.1.2**: Create test database structure
  ```
  database/tests/
  ├── 00_Setup_tSQLt.sql
  ├── 01_TestClass_ServerManagement.sql
  ├── 02_TestClass_MetricsCollection.sql
  ├── 03_TestClass_Alerting.sql
  └── 04_TestClass_Reporting.sql
  ```
  **Acceptance**: Directory structure exists, files created

- [ ] **Task 1.1.3**: Create test data fixtures
  ```sql
  CREATE PROCEDURE [ServerManagement].[Setup_TestServers]
  AS
  BEGIN
      -- Create fake test servers
      INSERT INTO dbo.Servers (ServerName, Environment, IsActive)
      VALUES ('TEST-SQL-01', 'Test', 1),
             ('TEST-SQL-02', 'Test', 1);
  END
  ```
  **Acceptance**: Test fixture procedures created for all test classes

### 1.2: Schema Development (TDD)

- [ ] **Task 1.2.1**: Write test for Servers table
  ```sql
  CREATE PROCEDURE [ServerManagement].[test Servers table should exist with required columns]
  AS
  BEGIN
      EXEC tSQLt.AssertObjectExists @ObjectName = 'dbo.Servers';
      EXEC tSQLt.AssertResultSetsHaveSameMetaData
          'SELECT ServerID, ServerName, Environment, IsActive FROM dbo.Servers WHERE 1=0',
          'SELECT 1 AS ServerID, ''SQL-01'' AS ServerName, ''Production'' AS Environment, 1 AS IsActive WHERE 1=0';
  END
  ```
  🔴 **RED**: Run `EXEC tSQLt.Run '[ServerManagement]'` → Fails (table doesn't exist)

- [ ] **Task 1.2.2**: Create Servers table
  ```sql
  CREATE TABLE dbo.Servers (
      ServerID INT IDENTITY(1,1) PRIMARY KEY,
      ServerName NVARCHAR(256) NOT NULL UNIQUE,
      Environment NVARCHAR(50) NULL,
      Description NVARCHAR(500) NULL,
      IsActive BIT NOT NULL DEFAULT 1,
      CreatedDate DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
      ModifiedDate DATETIME2 NULL
  );
  ```
  🟢 **GREEN**: Run test → Passes

- [ ] **Task 1.2.3**: Write test for PerformanceMetrics table with partitioning
  ```sql
  CREATE PROCEDURE [MetricsCollection].[test PerformanceMetrics should be partitioned by month]
  AS
  BEGIN
      DECLARE @PartitionCount INT;
      SELECT @PartitionCount = COUNT(DISTINCT partition_number)
      FROM sys.partitions
      WHERE object_id = OBJECT_ID('dbo.PerformanceMetrics');

      EXEC tSQLt.AssertEquals @Expected = 12, @Actual = @PartitionCount;
  END
  ```
  🔴 **RED**: Run test → Fails

- [ ] **Task 1.2.4**: Create partition function and scheme
  ```sql
  CREATE PARTITION FUNCTION PF_MonitoringByMonth (DATETIME2)
  AS RANGE RIGHT FOR VALUES (
      '2025-01-01', '2025-02-01', '2025-03-01', '2025-04-01',
      '2025-05-01', '2025-06-01', '2025-07-01', '2025-08-01',
      '2025-09-01', '2025-10-01', '2025-11-01', '2025-12-01'
  );

  CREATE PARTITION SCHEME PS_MonitoringByMonth
  AS PARTITION PF_MonitoringByMonth ALL TO ([PRIMARY]);
  ```
  🟢 **GREEN**: Run test → Passes

- [ ] **Task 1.2.5**: Create PerformanceMetrics table with columnstore
  ```sql
  CREATE TABLE dbo.PerformanceMetrics (
      MetricID BIGINT IDENTITY(1,1) NOT NULL,
      ServerID INT NOT NULL,
      CollectionTime DATETIME2 NOT NULL,
      MetricCategory NVARCHAR(50) NOT NULL,
      MetricName NVARCHAR(100) NOT NULL,
      MetricValue DECIMAL(18,4) NULL,
      CONSTRAINT PK_PerformanceMetrics PRIMARY KEY (CollectionTime, MetricID)
  ) ON PS_MonitoringByMonth(CollectionTime);

  CREATE COLUMNSTORE INDEX IX_PerformanceMetrics_CS
  ON dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
  ON PS_MonitoringByMonth(CollectionTime);
  ```
  🟢 **GREEN**: Run test → Passes

- [ ] **Task 1.2.6**: Create remaining tables (ProcedureStats, WaitStatistics, AlertRules, etc.)
  **TDD Process**: Write test for each table → Create table → Refactor
  - ProcedureStats (partitioned)
  - QueryStoreSnapshots (partitioned)
  - WaitStatistics (partitioned)
  - BlockingEvents
  - DeadlockEvents
  - AlertRules
  - AlertHistory
  - Recommendations

### 1.3: Stored Procedures - Server Management (TDD)

- [ ] **Task 1.3.1**: Write test for usp_GetServers
  ```sql
  CREATE PROCEDURE [ServerManagement].[test usp_GetServers should return all active servers]
  AS
  BEGIN
      -- Arrange
      EXEC tSQLt.FakeTable @TableName = 'dbo.Servers';
      INSERT INTO dbo.Servers (ServerName, Environment, IsActive)
      VALUES ('SQL-01', 'Production', 1),
             ('SQL-02', 'Production', 1),
             ('SQL-03', 'Production', 0); -- Inactive

      -- Act
      CREATE TABLE #Actual (ServerID INT, ServerName NVARCHAR(256), IsActive BIT);
      INSERT INTO #Actual
      EXEC dbo.usp_GetServers;

      -- Assert
      SELECT TOP 0 * INTO #Expected FROM #Actual;
      INSERT INTO #Expected VALUES (1, 'SQL-01', 1), (2, 'SQL-02', 1);

      EXEC tSQLt.AssertEqualsTable '#Expected', '#Actual';
  END
  ```
  🔴 **RED**: Run test → Fails (SP doesn't exist)

- [ ] **Task 1.3.2**: Create usp_GetServers
  ```sql
  CREATE OR ALTER PROCEDURE dbo.usp_GetServers
  AS
  BEGIN
      SET NOCOUNT ON;

      SELECT
          ServerID,
          ServerName,
          Environment,
          Description,
          IsActive,
          CreatedDate,
          ModifiedDate
      FROM dbo.Servers
      WHERE IsActive = 1
      ORDER BY ServerName;
  END
  ```
  🟢 **GREEN**: Run test → Passes

- [ ] **Task 1.3.3**: Refactor usp_GetServers (add error handling, logging)
  ```sql
  CREATE OR ALTER PROCEDURE dbo.usp_GetServers
  AS
  BEGIN
      SET NOCOUNT ON;

      BEGIN TRY
          SELECT
              ServerID,
              ServerName,
              Environment,
              Description,
              IsActive,
              CreatedDate,
              ModifiedDate
          FROM dbo.Servers
          WHERE IsActive = 1
          ORDER BY ServerName;
      END TRY
      BEGIN CATCH
          DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
          RAISERROR(@ErrorMessage, 16, 1);
      END CATCH
  END
  ```
  🟢 **GREEN**: Run test again → Still passes

- [ ] **Task 1.3.4**: TDD for usp_AddServer
  - Write test (RED)
  - Create minimal SP (GREEN)
  - Add validation, error handling (REFACTOR)

- [ ] **Task 1.3.5**: TDD for usp_UpdateServer
- [ ] **Task 1.3.6**: TDD for usp_DeleteServer (soft delete, set IsActive = 0)

### 1.4: Stored Procedures - Metrics Collection (TDD)

- [ ] **Task 1.4.1**: TDD for usp_CollectMetrics_RemoteServer (master collection SP)
  ```sql
  -- Test: Should call remote server and insert metrics
  CREATE PROCEDURE [MetricsCollection].[test usp_CollectMetrics should collect from remote server]
  AS
  BEGIN
      -- Arrange
      EXEC tSQLt.FakeTable @TableName = 'dbo.PerformanceMetrics';
      EXEC tSQLt.ApplyConstraint @TableName = 'dbo.PerformanceMetrics', @ConstraintName = 'PK_PerformanceMetrics';

      -- Act
      EXEC dbo.usp_CollectMetrics_RemoteServer @ServerName = 'TEST-SQL-01';

      -- Assert
      DECLARE @RowCount INT;
      SELECT @RowCount = COUNT(*) FROM dbo.PerformanceMetrics;
      EXEC tSQLt.AssertEquals @Expected = 1, @Actual = @RowCount, @Message = 'Should insert at least one metric';
  END
  ```
  🔴 **RED**: Run test → Fails

- [ ] **Task 1.4.2**: Create usp_CollectMetrics_RemoteServer
  ```sql
  CREATE OR ALTER PROCEDURE dbo.usp_CollectMetrics_RemoteServer
      @ServerName NVARCHAR(256)
  AS
  BEGIN
      SET NOCOUNT ON;

      DECLARE @ServerID INT;
      SELECT @ServerID = ServerID FROM dbo.Servers WHERE ServerName = @ServerName;

      -- Collect CPU metrics via OPENQUERY (example)
      INSERT INTO dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
      SELECT
          @ServerID,
          GETUTCDATE(),
          'CPU',
          counter_name,
          cntr_value
      FROM OPENQUERY([MONITORINGDB_SERVER],
          'SELECT counter_name, cntr_value
           FROM sys.dm_os_performance_counters
           WHERE object_name LIKE ''%Processor%''
           AND counter_name = ''% Processor Time''');
  END
  ```
  🟢 **GREEN**: Run test → Passes

- [ ] **Task 1.4.3**: Refactor with error handling, retry logic

- [ ] **Task 1.4.4**: TDD for additional collection SPs:
  - usp_CollectProcedureStats
  - usp_CollectWaitStats
  - usp_CollectQueryStoreStats
  - usp_CollectBlockingEvents
  - usp_CollectIndexStats

### 1.5: Stored Procedures - Reporting Views (TDD)

- [ ] **Task 1.5.1**: TDD for usp_GetMetricHistory
  ```sql
  -- Test: Should return metrics for date range
  CREATE PROCEDURE [Reporting].[test usp_GetMetricHistory should filter by date range]
  AS
  BEGIN
      -- Arrange
      EXEC tSQLt.FakeTable @TableName = 'dbo.PerformanceMetrics';
      INSERT INTO dbo.PerformanceMetrics (ServerID, CollectionTime, MetricCategory, MetricName, MetricValue)
      VALUES (1, '2025-10-25 10:00', 'CPU', 'Processor_Percent', 50.0),
             (1, '2025-10-25 11:00', 'CPU', 'Processor_Percent', 60.0),
             (1, '2025-10-25 12:00', 'CPU', 'Processor_Percent', 70.0);

      -- Act
      CREATE TABLE #Actual (CollectionTime DATETIME2, MetricValue DECIMAL(18,4));
      INSERT INTO #Actual
      EXEC dbo.usp_GetMetricHistory
          @ServerID = 1,
          @StartTime = '2025-10-25 10:30',
          @EndTime = '2025-10-25 11:30';

      -- Assert
      SELECT TOP 0 * INTO #Expected FROM #Actual;
      INSERT INTO #Expected VALUES ('2025-10-25 11:00', 60.0);
      EXEC tSQLt.AssertEqualsTable '#Expected', '#Actual';
  END
  ```
  🔴 **RED**: Run test → Fails

- [ ] **Task 1.5.2**: Create usp_GetMetricHistory
  🟢 **GREEN**: Run test → Passes

- [ ] **Task 1.5.3**: Refactor with performance optimizations

- [ ] **Task 1.5.4**: TDD for additional reporting SPs:
  - usp_GetServerSummary
  - usp_GetTopProcedures
  - usp_GetWaitStatsSummary
  - usp_GetBlockingChains

### 1.6: Stored Procedures - Alerting (TDD)

- [ ] **Task 1.6.1**: TDD for usp_EvaluateAlertRules
- [ ] **Task 1.6.2**: TDD for usp_CreateAlert
- [ ] **Task 1.6.3**: TDD for usp_GetActiveAlerts

### 1.7: SQL Agent Jobs (Integration Testing)

- [ ] **Task 1.7.1**: Create job deployment script (`04-sql-agent-jobs.sql`)
- [ ] **Task 1.7.2**: Test job execution manually
- [ ] **Task 1.7.3**: Verify job runs on schedule (5 minute interval)

### 1.8: Database Documentation

- [ ] **Task 1.8.1**: Add XML documentation to all stored procedures
  ```sql
  /*
  =====================================================
  Stored Procedure: dbo.usp_GetServers
  Description: Retrieves all active monitored SQL Server instances
  Parameters: None
  Returns: ResultSet (ServerID, ServerName, Environment, ...)
  Author: SQL Server Monitor Project
  Date: 2025-10-25
  =====================================================
  */
  ```
- [ ] **Task 1.8.2**: Generate data dictionary (tables, columns, indexes)
- [ ] **Task 1.8.3**: Create ER diagram (dbdiagram.io or SSMS diagram)

---

## Phase 2: API Development (TDD with xUnit)

**Goal**: Build ASP.NET Core 8.0 API with Dapper, 80%+ test coverage.

**Prerequisites**:
- Phase 1 complete (database deployed)
- .NET 8.0 SDK installed
- Docker installed

### 2.1: Project Setup

- [ ] **Task 2.1.1**: Create solution and projects
  ```bash
  dotnet new sln -n SqlServerMonitor
  dotnet new webapi -n SqlServerMonitor.Api -o api
  dotnet new xunit -n SqlServerMonitor.Api.Tests -o tests/SqlServerMonitor.Api.Tests
  dotnet sln add api/SqlServerMonitor.Api.csproj
  dotnet sln add tests/SqlServerMonitor.Api.Tests/SqlServerMonitor.Api.Tests.csproj
  ```

- [ ] **Task 2.1.2**: Install NuGet packages
  ```bash
  # API project
  cd api
  dotnet add package Dapper
  dotnet add package Microsoft.Data.SqlClient
  dotnet add package Serilog.AspNetCore
  dotnet add package Swashbuckle.AspNetCore

  # Test project
  cd ../tests/SqlServerMonitor.Api.Tests
  dotnet add package Moq
  dotnet add package FluentAssertions
  dotnet add package Microsoft.AspNetCore.Mvc.Testing
  dotnet add reference ../../api/SqlServerMonitor.Api.csproj
  ```

- [ ] **Task 2.1.3**: Setup project structure
  ```
  api/
  ├── Program.cs
  ├── appsettings.json
  ├── Controllers/
  ├── Services/
  │   ├── ISqlService.cs
  │   └── SqlService.cs
  ├── Models/
  │   ├── ServerModel.cs
  │   ├── MetricModel.cs
  │   └── HealthModel.cs
  └── Dockerfile
  ```

### 2.2: Data Access Layer (TDD)

- [ ] **Task 2.2.1**: Write test for SqlService.GetServersAsync
  ```csharp
  // tests/SqlServerMonitor.Api.Tests/Services/SqlServiceTests.cs
  public class SqlServiceTests
  {
      [Fact]
      public async Task GetServersAsync_ShouldReturnServers()
      {
          // Arrange
          var connectionString = "Server=...;Database=MonitoringDB;...";
          var service = new SqlService(connectionString);

          // Act
          var result = await service.GetServersAsync();

          // Assert
          result.Should().NotBeEmpty();
          result.Should().AllSatisfy(s => s.IsActive.Should().BeTrue());
      }
  }
  ```
  🔴 **RED**: Run `dotnet test` → Fails (class doesn't exist)

- [ ] **Task 2.2.2**: Create SqlService with GetServersAsync
  ```csharp
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
  }
  ```
  🟢 **GREEN**: Run test → Passes

- [ ] **Task 2.2.3**: Refactor (add logging, error handling, connection pooling)

- [ ] **Task 2.2.4**: TDD for remaining SqlService methods:
  - GetMetricHistoryAsync
  - GetServerSummaryAsync
  - GetActiveAlertsAsync

### 2.3: API Controllers (TDD)

- [ ] **Task 2.3.1**: Write test for ServersController.Get
  ```csharp
  public class ServersControllerTests
  {
      [Fact]
      public async Task Get_ShouldReturnOkWithServers()
      {
          // Arrange
          var mockService = new Mock<ISqlService>();
          mockService.Setup(s => s.GetServersAsync())
              .ReturnsAsync(new List<ServerModel> { new ServerModel { ServerID = 1 } });
          var controller = new ServersController(mockService.Object);

          // Act
          var result = await controller.Get();

          // Assert
          result.Should().BeOfType<OkObjectResult>();
      }
  }
  ```
  🔴 **RED**: Run test → Fails

- [ ] **Task 2.3.2**: Create ServersController
  🟢 **GREEN**: Run test → Passes

- [ ] **Task 2.3.3**: TDD for remaining controllers:
  - MetricsController
  - AlertsController
  - RecommendationsController
  - HealthController

### 2.4: Containerization

- [ ] **Task 2.4.1**: Create Dockerfile
  ```dockerfile
  FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
  WORKDIR /app
  EXPOSE 5000

  FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
  WORKDIR /src
  COPY ["SqlServerMonitor.Api.csproj", "./"]
  RUN dotnet restore
  COPY . .
  RUN dotnet build -c Release -o /app/build

  FROM build AS publish
  RUN dotnet publish -c Release -o /app/publish

  FROM base AS final
  WORKDIR /app
  COPY --from=publish /app/publish .
  HEALTHCHECK --interval=60s --timeout=10s --retries=3 \
    CMD curl -f http://localhost:5000/health || exit 1
  ENTRYPOINT ["dotnet", "SqlServerMonitor.Api.dll"]
  ```

- [ ] **Task 2.4.2**: Create docker-compose.yml
- [ ] **Task 2.4.3**: Test container build and run

### 2.5: Integration Testing

- [ ] **Task 2.5.1**: Setup integration test project with WebApplicationFactory
- [ ] **Task 2.5.2**: Write end-to-end tests for all API endpoints
- [ ] **Task 2.5.3**: Test with real database (test container or dedicated test DB)

---

## Phase 3: Grafana Dashboards

**Goal**: Create 6 core dashboards with SQL queries, Material Design aesthetic.

### 3.1: Dashboard 1 - Instance Health

- [ ] **Task 3.1.1**: Create dashboard JSON structure
- [ ] **Task 3.1.2**: Add panel: CPU Utilization (time series)
  ```sql
  SELECT
      $__timeGroup(CollectionTime, '1m') AS time,
      AVG(MetricValue) AS cpu_percent
  FROM dbo.PerformanceMetrics
  WHERE MetricCategory = 'CPU' AND MetricName = 'Processor_Percent'
    AND ServerID = $ServerID
    AND $__timeFilter(CollectionTime)
  GROUP BY $__timeGroup(CollectionTime, '1m')
  ORDER BY time
  ```
- [ ] **Task 3.1.3**: Add panel: Memory (Page Life Expectancy)
- [ ] **Task 3.1.4**: Add panel: Disk I/O Latency
- [ ] **Task 3.1.5**: Add panel: Active Connections (stat panel)
- [ ] **Task 3.1.6**: Apply Material Design colors
  - Success: #388E3C (green)
  - Warning: #F57C00 (orange)
  - Error: #D32F2F (red)
  - Primary: #1976D2 (blue)
- [ ] **Task 3.1.7**: Export dashboard JSON to `dashboards/grafana/01-instance-health.json`

### 3.2: Dashboard 2 - Developer (Procedures)

- [ ] **Task 3.2.1**: Panel: Top 10 Procedures by Duration
- [ ] **Task 3.2.2**: Panel: Procedure Execution Timeline
- [ ] **Task 3.2.3**: Panel: Parameter Sniffing Detection
- [ ] **Task 3.2.4**: Export JSON

### 3.3: Dashboard 3 - DBA (Waits & Blocking)

- [ ] **Task 3.3.1**: Panel: Wait Stats Breakdown (pie chart)
- [ ] **Task 3.3.2**: Panel: Top Waits Over Time
- [ ] **Task 3.3.3**: Panel: Current Blocking Chains (table)
- [ ] **Task 3.3.4**: Export JSON

### 3.4: Dashboard 4 - Capacity Planning

- [ ] **Task 3.4.1**: Panel: Database Size Growth
- [ ] **Task 3.4.2**: Panel: Log File Usage
- [ ] **Task 3.4.3**: Panel: Disk Space Projection
- [ ] **Task 3.4.4**: Export JSON

### 3.5: Dashboard 5 - Query Store

- [ ] **Task 3.5.1**: Panel: Plan Regressions
- [ ] **Task 3.5.2**: Panel: Forced Plans
- [ ] **Task 3.5.3**: Export JSON

### 3.6: Dashboard 6 - Alerts

- [ ] **Task 3.6.1**: Panel: Active Alerts (table)
- [ ] **Task 3.6.2**: Panel: Alert History (time series)
- [ ] **Task 3.6.3**: Export JSON

---

## Phase 4: Integration & Testing

- [ ] **Task 4.1**: End-to-end collection test (SQL Agent → DB → API → Grafana)
- [ ] **Task 4.2**: Multi-server test (3+ SQL Servers monitored)
- [ ] **Task 4.3**: Alert generation test
- [ ] **Task 4.4**: Performance test (20 servers, 90 days data)
- [ ] **Task 4.5**: Failover test (stop MonitoringDB, verify graceful degradation)
- [ ] **Task 4.6**: Security test (pen test, SQL injection validation)
- [ ] **Task 4.7**: Air-gap deployment test (completely offline network)
- [ ] **Task 4.8**: Backup and restore test
- [ ] **Task 4.9**: Upgrade test (database schema migration)
- [ ] **Task 4.10**: Load test (1000 concurrent Grafana users)

---

## Phase 5: Documentation & Deployment

- [ ] **Task 5.1**: Finalize SETUP.md ✅ (already complete)
- [ ] **Task 5.2**: Create TROUBLESHOOTING.md
- [ ] **Task 5.3**: Create MIGRATION-GUIDE.md (for existing monitoring solutions)
- [ ] **Task 5.4**: Create VIDEO-WALKTHROUGH.md (links to demo videos)
- [ ] **Task 5.5**: Update README.md with final architecture ⏳ (in progress)
- [ ] **Task 5.6**: Create deployment scripts (Bash + PowerShell)
- [ ] **Task 5.7**: Create uninstall/cleanup scripts
- [ ] **Task 5.8**: Final code review and refactoring

---

## Definition of Done (DoD)

A task is complete when ALL of the following are true:

- ✅ **Tests written FIRST** (Red phase)
- ✅ **Tests passing** (Green phase)
- ✅ **Code refactored** (Refactor phase)
- ✅ **Code coverage ≥80%** (for business logic)
- ✅ **Documentation updated** (inline comments, XML docs)
- ✅ **Peer reviewed** (if working in team)
- ✅ **Integration tested** (works with other components)
- ✅ **No compiler warnings**

## Testing Checklist

Before marking any phase complete:

- [ ] Unit tests pass: `dotnet test`
- [ ] Integration tests pass
- [ ] tSQLt tests pass: `EXEC tSQLt.RunAll;`
- [ ] Code coverage report generated and ≥80%
- [ ] Manual smoke test performed
- [ ] Performance acceptable (<500ms API response, <2s dashboard load)

## Next Steps After Completion

1. User acceptance testing (UAT) with developers and DBAs
2. Production rollout (pilot 3 servers → full fleet)
3. Training documentation and video walkthroughs
4. Feedback collection and iteration
5. Plan Phase 2 features (Agent job monitoring, backup tracking, etc.)

---

**Last Updated**: 2025-10-25
**Current Phase**: Phase 1.1 (Test Framework Setup)
**Next Milestone**: Complete database schema with 100% tSQLt coverage
