# Integration Tests - Phase 1.9

Integration tests for sql-monitor API services (Phase 1.9: Multi-server support).

## Prerequisites

1. **Test Database**: Create a separate test database
   ```sql
   CREATE DATABASE MonitoringDB_Test;
   GO
   ```

2. **Deploy Schema**: Run all database scripts from `database/` directory
   ```bash
   cd /mnt/d/dev2/sql-monitor/database
   sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -d MonitoringDB_Test -i deploy-all.sql
   ```

3. **Configure Connection**: Edit `appsettings.Test.json` with test database connection string
   ```json
   {
     "ConnectionStrings": {
       "MonitoringDB": "Server=sqltest.schoolvision.net,14333;Database=MonitoringDB_Test;User Id=sv;Password=Gv51076!;..."
     }
   }
   ```

## Running Integration Tests

### Run All Integration Tests

```bash
cd /mnt/d/dev2/sql-monitor/api.tests
dotnet test --filter "Category=Integration"
```

### Run Specific Test Class

```bash
# Server service tests only
dotnet test --filter "FullyQualifiedName~ServerServiceIntegrationTests"

# Query service tests only
dotnet test --filter "FullyQualifiedName~QueryServiceIntegrationTests"
```

### Run Specific Test

```bash
dotnet test --filter "FullyQualifiedName~GetServersAsync_ShouldReturnServers_WhenDatabaseHasData"
```

### Run with Detailed Output

```bash
dotnet test --filter "Category=Integration" --logger "console;verbosity=detailed"
```

## Test Data Requirements

### ServerService Tests

- At least 1 server registered in `dbo.Servers` table
- Test data can be auto-created during test execution
- Cleanup: Tests create test servers with unique names (TEST-SERVER-*)

### QueryService Tests

- Query Store enabled on at least one test database
- Query Store snapshots collected via `usp_CollectQueryStoreSnapshot`
- **Seed Test Data**:
  ```sql
  -- Enable Query Store on test database
  ALTER DATABASE MonitoringDB_Test SET QUERY_STORE = ON;

  -- Run collection procedures to populate data
  EXEC dbo.DBA_CollectPerformanceSnapshot @EnableP1 = 1;
  ```

## Test Categories

### Unit Tests
- Fast, no database required
- Mock dependencies
- Test business logic and validation
- Run with: `dotnet test --filter "Category!=Integration"`

### Integration Tests
- Require test database
- Test actual data access via Dapper
- Verify stored procedure execution
- Validate data mapping
- Run with: `dotnet test --filter "Category=Integration"`

## Continuous Integration (CI)

### GitHub Actions / Azure Pipelines

```yaml
# Example CI configuration
steps:
  - name: Setup Test Database
    run: |
      sqlcmd -S ${{ secrets.TEST_DB_SERVER }} -U ${{ secrets.TEST_DB_USER }} -P ${{ secrets.TEST_DB_PASSWORD }} -Q "CREATE DATABASE MonitoringDB_Test"
      sqlcmd -S ${{ secrets.TEST_DB_SERVER }} -U ${{ secrets.TEST_DB_USER }} -P ${{ secrets.TEST_DB_PASSWORD }} -d MonitoringDB_Test -i database/deploy-all.sql

  - name: Run Unit Tests
    run: dotnet test --filter "Category!=Integration"

  - name: Run Integration Tests
    run: dotnet test --filter "Category=Integration"
    env:
      ConnectionStrings__MonitoringDB: ${{ secrets.TEST_CONNECTION_STRING }}

  - name: Cleanup Test Database
    run: sqlcmd -S ${{ secrets.TEST_DB_SERVER }} -U ${{ secrets.TEST_DB_USER }} -P ${{ secrets.TEST_DB_PASSWORD }} -Q "DROP DATABASE MonitoringDB_Test"
```

## Test Isolation

### Transaction Rollback Pattern

For tests that modify data, consider using transaction rollback:

```csharp
public class MyIntegrationTests : IAsyncLifetime
{
    private TransactionScope _transactionScope = null!;

    public Task InitializeAsync()
    {
        // Start transaction before each test
        _transactionScope = new TransactionScope(TransactionScopeAsyncFlowOption.Enabled);
        return Task.CompletedTask;
    }

    public Task DisposeAsync()
    {
        // Rollback transaction after each test
        _transactionScope.Dispose();
        return Task.CompletedTask;
    }
}
```

### Database Reset

For clean test runs, reset test database between test sessions:

```bash
# Drop and recreate test database
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -Q "DROP DATABASE IF EXISTS MonitoringDB_Test; CREATE DATABASE MonitoringDB_Test;"

# Redeploy schema
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -d MonitoringDB_Test -i database/deploy-all.sql
```

## Performance Testing

### Benchmark Tests

Integration tests include performance assertions:

```csharp
[Fact]
public async Task GetTopQueriesAsync_ShouldBeFast_WithSmallTopN()
{
    var stopwatch = Stopwatch.StartNew();
    var queries = await _service.GetTopQueriesAsync(topN: 10);
    stopwatch.Stop();

    stopwatch.ElapsedMilliseconds.Should().BeLessThan(1000);
}
```

### Large Dataset Tests

For performance testing with large datasets:

1. Seed large volumes of test data
2. Run queries with high `topN` values
3. Verify query plans use indexes
4. Measure response times

## Troubleshooting

### Connection Errors

**Error**: "A network-related or instance-specific error occurred"

**Solution**: Verify connection string syntax (use `Connection Timeout` with space)

```json
{
  "ConnectionStrings": {
    "MonitoringDB": "Server=server,port;Database=db;User Id=user;Password=pass;Encrypt=True;TrustServerCertificate=True;Connection Timeout=30"
  }
}
```

### Missing Stored Procedures

**Error**: "Could not find stored procedure 'dbo.usp_GetServers'"

**Solution**: Ensure all database scripts are deployed

```bash
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P Gv51076! -C -d MonitoringDB_Test -i database/deploy-all.sql
```

### Empty Test Results

**Issue**: Tests pass but return empty results

**Solution**: Seed test data

```sql
-- Register test server
INSERT INTO dbo.Servers (ServerName, Environment, IsActive)
VALUES ('TEST-SERVER-01', 'Testing', 1);

-- Run collection procedures
DECLARE @ServerID INT = 1;
EXEC dbo.DBA_CollectPerformanceSnapshot @ServerID = @ServerID OUTPUT;
```

## Test Coverage

Current integration test coverage:

### ServerService (11 tests)
- ✅ GetServersAsync (4 tests)
- ✅ GetServerByIdAsync (2 tests)
- ✅ GetServerByNameAsync (2 tests)
- ✅ GetServerHealthStatusAsync (3 tests)
- ✅ GetResourceTrendsAsync (2 tests)
- ✅ GetDatabaseSummaryAsync (3 tests)
- ✅ RegisterServerAsync (2 tests)
- ✅ UpdateServerAsync (3 tests)

### QueryService (12 tests)
- ✅ GetTopQueriesAsync with default parameters
- ✅ Filter by ServerID
- ✅ Limit by TopN
- ✅ Order by AvgCpu, TotalReads, AvgDuration
- ✅ Filter by MinExecutionCount
- ✅ Property mapping validation
- ✅ Performance benchmarks
- ✅ Multi-server queries

**Total**: 23 integration tests

## Future Enhancements

1. **Parallel Test Execution**: Use xUnit test collections for isolation
2. **Test Data Builders**: Fluent API for creating test data
3. **Snapshot Testing**: Compare query results against baseline snapshots
4. **Load Testing**: Test concurrent API access patterns
5. **Docker Test Containers**: Spin up SQL Server in Docker for CI/CD
