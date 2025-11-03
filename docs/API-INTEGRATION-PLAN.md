# API Integration Plan - Week 6

**Feature**: Phase 3 Feature #7 - T-SQL Code Editor & Analyzer
**Date**: 2025-11-02
**Status**: Planning

---

## Overview

This document outlines the complete plan for integrating the Grafana plugin frontend with the ASP.NET Core backend API. Currently, all data interactions use mock implementations in `sqlMonitorApiClient.ts`. This plan details the backend endpoints to create and frontend changes needed for full integration.

---

## Table of Contents

1. [Backend API Endpoints](#backend-api-endpoints)
2. [Frontend API Client Updates](#frontend-api-client-updates)
3. [Data Models and DTOs](#data-models-and-dtos)
4. [Error Handling Strategy](#error-handling-strategy)
5. [Authentication & Authorization](#authentication--authorization)
6. [Testing Strategy](#testing-strategy)
7. [Implementation Phases](#implementation-phases)
8. [Rollback Plan](#rollback-plan)

---

## Backend API Endpoints

### 1. Query Execution API

#### `POST /api/code/execute`

**Purpose**: Execute T-SQL query against a monitored SQL Server.

**Request Body**:
```csharp
public class QueryExecutionRequest
{
    [Required]
    public int ServerId { get; set; }

    [Required]
    public string DatabaseName { get; set; }

    [Required]
    [MaxLength(1000000)] // 1MB limit
    public string Query { get; set; }

    public int TimeoutSeconds { get; set; } = 60;
}
```

**Response**:
```csharp
public class QueryExecutionResult
{
    public bool Success { get; set; }
    public string ExecutionId { get; set; }
    public int RowsAffected { get; set; }
    public List<ResultSet> ResultSets { get; set; }
    public List<string> Messages { get; set; }
    public List<QueryError> Errors { get; set; }
    public long ExecutionTimeMs { get; set; }
    public string ServerName { get; set; }
    public string DatabaseName { get; set; }
    public DateTime ExecutedAt { get; set; }
}

public class ResultSet
{
    public List<ColumnMetadata> Columns { get; set; }
    public List<Dictionary<string, object>> Rows { get; set; }
    public int RowCount { get; set; }
}

public class ColumnMetadata
{
    public string Name { get; set; }
    public string DataType { get; set; }
    public int Ordinal { get; set; }
}

public class QueryError
{
    public string Message { get; set; }
    public int? LineNumber { get; set; }
    public string Severity { get; set; }
}
```

**Implementation** (ASP.NET Core):
```csharp
[HttpPost("execute")]
[RequirePermission("code.execute")]
public async Task<ActionResult<QueryExecutionResult>> ExecuteQuery(
    [FromBody] QueryExecutionRequest request)
{
    var startTime = DateTime.UtcNow;
    var executionId = Guid.NewGuid().ToString();

    try
    {
        // Get server connection info
        var server = await _serverService.GetServerByIdAsync(request.ServerId);
        if (server == null)
        {
            return NotFound(new { message = "Server not found" });
        }

        // Build connection string
        var connectionString = BuildConnectionString(server, request.DatabaseName);

        // Execute query with timeout
        var (resultSets, rowsAffected, messages, errors) = await _sqlExecutionService
            .ExecuteQueryAsync(connectionString, request.Query, request.TimeoutSeconds);

        var result = new QueryExecutionResult
        {
            Success = errors.Count == 0,
            ExecutionId = executionId,
            RowsAffected = rowsAffected,
            ResultSets = resultSets,
            Messages = messages,
            Errors = errors,
            ExecutionTimeMs = (long)(DateTime.UtcNow - startTime).TotalMilliseconds,
            ServerName = server.ServerName,
            DatabaseName = request.DatabaseName,
            ExecutedAt = DateTime.UtcNow
        };

        // Log execution to audit log
        await _auditService.LogQueryExecutionAsync(
            userId: User.GetUserId(),
            serverId: request.ServerId,
            database: request.DatabaseName,
            query: request.Query,
            success: result.Success,
            executionTimeMs: result.ExecutionTimeMs
        );

        return Ok(result);
    }
    catch (SqlException ex)
    {
        return Ok(new QueryExecutionResult
        {
            Success = false,
            ExecutionId = executionId,
            Errors = new List<QueryError>
            {
                new QueryError
                {
                    Message = ex.Message,
                    LineNumber = ex.LineNumber,
                    Severity = "Error"
                }
            },
            ExecutionTimeMs = (long)(DateTime.UtcNow - startTime).TotalMilliseconds,
            ServerName = server?.ServerName,
            DatabaseName = request.DatabaseName,
            ExecutedAt = DateTime.UtcNow
        });
    }
}
```

**Stored Procedure** (optional, recommended):
```sql
CREATE PROCEDURE dbo.usp_ExecuteQueryWithTimeout
    @Query NVARCHAR(MAX),
    @TimeoutSeconds INT = 60
AS
BEGIN
    SET NOCOUNT ON;

    -- Set query timeout
    DECLARE @SqlCommand NVARCHAR(MAX) =
        N'SET LOCK_TIMEOUT ' + CAST(@TimeoutSeconds * 1000 AS NVARCHAR(10)) + N'; ' +
        @Query;

    -- Execute query
    EXEC sp_executesql @SqlCommand;
END
GO
```

---

#### `POST /api/code/cancel`

**Purpose**: Cancel a running query execution.

**Request Body**:
```csharp
public class CancelQueryRequest
{
    [Required]
    public string ExecutionId { get; set; }
}
```

**Response**:
```csharp
public class CancelQueryResponse
{
    public bool Success { get; set; }
    public string Message { get; set; }
}
```

**Implementation**:
```csharp
[HttpPost("cancel")]
[RequirePermission("code.execute")]
public async Task<ActionResult<CancelQueryResponse>> CancelQuery(
    [FromBody] CancelQueryRequest request)
{
    // Track running queries in a concurrent dictionary
    if (_runningQueries.TryGetValue(request.ExecutionId, out var cancellationTokenSource))
    {
        cancellationTokenSource.Cancel();
        _runningQueries.TryRemove(request.ExecutionId, out _);

        return Ok(new CancelQueryResponse
        {
            Success = true,
            Message = "Query cancelled successfully"
        });
    }

    return NotFound(new CancelQueryResponse
    {
        Success = false,
        Message = "Query not found or already completed"
    });
}
```

---

### 2. Server & Database Metadata API

#### `GET /api/code/servers`

**Purpose**: Get list of monitored SQL Servers.

**Response**:
```csharp
public class ServerInfo
{
    public int ServerId { get; set; }
    public string ServerName { get; set; }
    public string ServerType { get; set; }
    public bool IsActive { get; set; }
    public bool HasPermission { get; set; } // User has access
}
```

**Implementation**:
```csharp
[HttpGet("servers")]
[RequirePermission("code.view")]
public async Task<ActionResult<List<ServerInfo>>> GetServers()
{
    var userId = User.GetUserId();
    var servers = await _sqlService.ExecuteQueryAsync<ServerInfo>(
        "dbo.usp_GetServersForUser",
        new { UserId = userId }
    );

    return Ok(servers);
}
```

**Stored Procedure**:
```sql
CREATE PROCEDURE dbo.usp_GetServersForUser
    @UserId INT
AS
BEGIN
    SELECT
        s.ServerID AS ServerId,
        s.ServerName,
        s.ServerType,
        s.IsActive,
        CASE WHEN usr.UserID IS NOT NULL THEN 1 ELSE 0 END AS HasPermission
    FROM dbo.Servers s
    LEFT JOIN dbo.UserServerAccess usa ON s.ServerID = usa.ServerID AND usa.UserID = @UserId
    LEFT JOIN dbo.Users usr ON usr.UserID = @UserId
    WHERE s.IsActive = 1
        AND (usr.IsAdmin = 1 OR usa.UserID IS NOT NULL)
    ORDER BY s.ServerName;
END
GO
```

---

#### `GET /api/code/servers/{serverId}/databases`

**Purpose**: Get list of databases for a specific server.

**Response**:
```csharp
public class DatabaseInfo
{
    public string DatabaseName { get; set; }
    public string Status { get; set; }
    public long SizeMB { get; set; }
    public DateTime LastBackup { get; set; }
}
```

**Implementation**:
```csharp
[HttpGet("servers/{serverId}/databases")]
[RequirePermission("code.view")]
public async Task<ActionResult<List<string>>> GetDatabases(int serverId)
{
    var databases = await _sqlService.ExecuteQueryAsync<string>(
        "dbo.usp_GetDatabasesForServer",
        new { ServerId = serverId }
    );

    return Ok(databases);
}
```

**Stored Procedure**:
```sql
CREATE PROCEDURE dbo.usp_GetDatabasesForServer
    @ServerId INT
AS
BEGIN
    -- Connect to remote server via linked server
    DECLARE @ServerName NVARCHAR(128);
    SELECT @ServerName = ServerName FROM dbo.Servers WHERE ServerID = @ServerId;

    DECLARE @Sql NVARCHAR(MAX) = N'
        SELECT name
        FROM sys.databases
        WHERE state = 0 -- ONLINE
            AND name NOT IN (''master'', ''tempdb'', ''model'', ''msdb'')
        ORDER BY name';

    -- Execute on remote server via OPENQUERY
    EXEC sp_executesql @Sql;
END
GO
```

---

### 3. Object Metadata API (IntelliSense)

#### `GET /api/code/servers/{serverId}/databases/{databaseName}/objects`

**Purpose**: Get schema metadata for IntelliSense (tables, views, procedures, functions).

**Response**:
```csharp
public class ObjectMetadata
{
    public int ServerId { get; set; }
    public string ServerName { get; set; }
    public string DatabaseName { get; set; }
    public string SchemaName { get; set; }
    public string ObjectName { get; set; }
    public string ObjectType { get; set; } // table, view, procedure, function
    public string Definition { get; set; }
    public string Description { get; set; }
    public List<ColumnMetadata> Columns { get; set; }
}
```

**Implementation**:
```csharp
[HttpGet("servers/{serverId}/databases/{databaseName}/objects")]
[RequirePermission("code.view")]
public async Task<ActionResult<List<ObjectMetadata>>> GetObjectMetadata(
    int serverId,
    string databaseName)
{
    var objects = await _sqlService.ExecuteQueryAsync<ObjectMetadata>(
        "dbo.usp_GetObjectMetadataForDatabase",
        new { ServerId = serverId, DatabaseName = databaseName }
    );

    return Ok(objects);
}
```

**Stored Procedure**:
```sql
CREATE PROCEDURE dbo.usp_GetObjectMetadataForDatabase
    @ServerId INT,
    @DatabaseName NVARCHAR(128)
AS
BEGIN
    -- Check if metadata is cached (from Phase 1.25)
    IF EXISTS (
        SELECT 1 FROM dbo.SchemaMetadataCache
        WHERE ServerID = @ServerId
            AND DatabaseName = @DatabaseName
            AND LastRefreshed > DATEADD(hour, -24, GETUTCDATE())
    )
    BEGIN
        -- Return cached metadata
        SELECT * FROM dbo.SchemaMetadataCache
        WHERE ServerID = @ServerId AND DatabaseName = @DatabaseName;
    END
    ELSE
    BEGIN
        -- Refresh metadata from remote server
        EXEC dbo.usp_RefreshSchemaMetadata @ServerId, @DatabaseName;

        -- Return fresh metadata
        SELECT * FROM dbo.SchemaMetadataCache
        WHERE ServerID = @ServerId AND DatabaseName = @DatabaseName;
    END
END
GO
```

---

#### `GET /api/code/servers/{serverId}/databases/{databaseName}/objects/{schemaName}/{objectName}/code`

**Purpose**: Get object definition (CREATE script) for viewing.

**Response**:
```csharp
public class ObjectCodeResponse
{
    public string ObjectName { get; set; }
    public string ObjectType { get; set; }
    public string Code { get; set; }
    public DateTime LastModified { get; set; }
}
```

**Implementation**:
```csharp
[HttpGet("servers/{serverId}/databases/{databaseName}/objects/{schemaName}/{objectName}/code")]
[RequirePermission("code.view")]
public async Task<ActionResult<ObjectCodeResponse>> GetObjectCode(
    int serverId,
    string databaseName,
    string schemaName,
    string objectName)
{
    var code = await _sqlService.ExecuteScalarAsync<string>(
        "dbo.usp_GetObjectDefinition",
        new { ServerId = serverId, DatabaseName = databaseName, SchemaName = schemaName, ObjectName = objectName }
    );

    if (string.IsNullOrEmpty(code))
    {
        return NotFound();
    }

    return Ok(new ObjectCodeResponse
    {
        ObjectName = $"{schemaName}.{objectName}",
        ObjectType = "procedure", // TODO: Detect type
        Code = code,
        LastModified = DateTime.UtcNow
    });
}
```

---

### 4. Saved Scripts API (Future Phase)

#### `GET /api/code/scripts`

**Purpose**: Get saved scripts for the current user.

#### `POST /api/code/scripts`

**Purpose**: Save a script to the server.

#### `PUT /api/code/scripts/{scriptId}`

**Purpose**: Update an existing script.

#### `DELETE /api/code/scripts/{scriptId}`

**Purpose**: Delete a script.

**Note**: Currently, scripts are saved in browser localStorage. Server-side storage is a future enhancement.

---

## Frontend API Client Updates

### Current State (Mock Implementation)

File: `src/services/sqlMonitorApiClient.ts`

All methods return hardcoded mock data:
- `executeQuery()` - Returns mock result set
- `cancelQuery()` - Returns mock success
- `getServers()` - Returns 3 mock servers
- `getDatabases()` - Returns 5 mock databases
- `getObjectMetadata()` - Returns 2 mock tables
- `getObjectCode()` - Returns mock CREATE script

### Required Changes

#### 1. Add Grafana Backend Service Integration

```typescript
import { getBackendSrv } from '@grafana/runtime';

/**
 * Get Grafana datasource UID from plugin configuration
 */
private getDatasourceUid(): string {
  // TODO: Get from plugin configuration
  return 'sql-monitor-datasource-uid';
}

/**
 * Build API URL with datasource proxy
 */
private buildApiUrl(endpoint: string): string {
  const dsUid = this.getDatasourceUid();
  return `/api/datasources/proxy/uid/${dsUid}${endpoint}`;
}
```

#### 2. Replace Mock Methods with Real API Calls

```typescript
/**
 * Execute SQL query (REAL IMPLEMENTATION)
 */
public async executeQuery(request: QueryExecutionRequest): Promise<QueryExecutionResult> {
  console.log('[SqlMonitorApiClient] Executing query:', {
    serverId: request.serverId,
    database: request.databaseName,
    queryLength: request.query.length,
  });

  const startTime = Date.now();

  try {
    const response = await getBackendSrv().post(
      this.buildApiUrl('/api/code/execute'),
      request,
      {
        timeout: request.timeoutSeconds ? request.timeoutSeconds * 1000 : 60000,
      }
    );

    console.log('[SqlMonitorApiClient] Query executed:', {
      success: response.success,
      executionTime: `${response.executionTimeMs}ms`,
      rowsAffected: response.rowsAffected,
    });

    return response;
  } catch (error) {
    console.error('[SqlMonitorApiClient] Query execution failed:', error);

    // Return error response
    return {
      success: false,
      executionId: this.generateExecutionId(),
      rowsAffected: 0,
      resultSets: [],
      messages: [],
      errors: [
        {
          message: error instanceof Error ? error.message : 'Unknown error occurred',
          lineNumber: null,
          severity: 'Error',
        },
      ],
      executionTimeMs: Date.now() - startTime,
      serverName: '',
      databaseName: request.databaseName,
      executedAt: new Date().toISOString(),
    };
  }
}

/**
 * Get list of monitored servers (REAL IMPLEMENTATION)
 */
public async getServers(): Promise<ServerInfo[]> {
  console.log('[SqlMonitorApiClient] Fetching servers...');

  try {
    const response = await getBackendSrv().get(this.buildApiUrl('/api/code/servers'));
    return response;
  } catch (error) {
    console.error('[SqlMonitorApiClient] Failed to fetch servers:', error);
    return [];
  }
}

/**
 * Get databases for a server (REAL IMPLEMENTATION)
 */
public async getDatabases(serverId: number): Promise<string[]> {
  console.log('[SqlMonitorApiClient] Fetching databases for server:', serverId);

  try {
    const response = await getBackendSrv().get(
      this.buildApiUrl(`/api/code/servers/${serverId}/databases`)
    );
    return response;
  } catch (error) {
    console.error('[SqlMonitorApiClient] Failed to fetch databases:', error);
    return [];
  }
}

/**
 * Get object metadata for IntelliSense (REAL IMPLEMENTATION)
 */
public async getObjectMetadata(serverId: number, databaseName: string): Promise<ObjectMetadata[]> {
  console.log('[SqlMonitorApiClient] Fetching object metadata:', { serverId, databaseName });

  try {
    const response = await getBackendSrv().get(
      this.buildApiUrl(`/api/code/servers/${serverId}/databases/${databaseName}/objects`)
    );
    return response;
  } catch (error) {
    console.error('[SqlMonitorApiClient] Failed to fetch object metadata:', error);
    return [];
  }
}

/**
 * Get object code definition (REAL IMPLEMENTATION)
 */
public async getObjectCode(
  serverId: number,
  databaseName: string,
  schemaName: string,
  objectName: string,
  objectType: 'table' | 'view' | 'procedure' | 'function'
): Promise<string> {
  console.log('[SqlMonitorApiClient] Fetching object code:', {
    serverId,
    databaseName,
    schemaName,
    objectName,
    objectType,
  });

  try {
    const response = await getBackendSrv().get(
      this.buildApiUrl(
        `/api/code/servers/${serverId}/databases/${databaseName}/objects/${schemaName}/${objectName}/code`
      )
    );
    return response.code;
  } catch (error) {
    console.error('[SqlMonitorApiClient] Failed to fetch object code:', error);
    return `-- Error loading object code: ${error instanceof Error ? error.message : 'Unknown error'}`;
  }
}
```

#### 3. Add Configuration for API Base URL

```typescript
/**
 * API configuration
 */
interface ApiConfig {
  datasourceUid: string;
  baseUrl?: string;
  timeout?: number;
}

export class SqlMonitorApiClient {
  private static instance: SqlMonitorApiClient;
  private config: ApiConfig;

  private constructor(config?: Partial<ApiConfig>) {
    this.config = {
      datasourceUid: config?.datasourceUid || 'sql-monitor-datasource',
      baseUrl: config?.baseUrl || '/api/code',
      timeout: config?.timeout || 60000,
    };
  }

  /**
   * Configure the API client
   */
  public static configure(config: Partial<ApiConfig>): void {
    if (SqlMonitorApiClient.instance) {
      SqlMonitorApiClient.instance.config = {
        ...SqlMonitorApiClient.instance.config,
        ...config,
      };
    }
  }
}
```

---

## Data Models and DTOs

### Backend Models (C#)

Create in `api/Models/Code/`:

```
api/Models/Code/
├── QueryExecutionRequest.cs
├── QueryExecutionResult.cs
├── ResultSet.cs
├── ColumnMetadata.cs
├── QueryError.cs
├── CancelQueryRequest.cs
├── CancelQueryResponse.cs
├── ServerInfo.cs
├── DatabaseInfo.cs
├── ObjectMetadata.cs
└── ObjectCodeResponse.cs
```

### Frontend Types (TypeScript)

Already exists in `src/types/query.ts` - needs minor updates to match backend DTOs exactly.

---

## Error Handling Strategy

### Backend Error Responses

```csharp
public class ApiErrorResponse
{
    public string Message { get; set; }
    public string Code { get; set; }
    public Dictionary<string, string[]> Errors { get; set; } // Validation errors
    public string StackTrace { get; set; } // Development only
}
```

### Frontend Error Handling

```typescript
try {
  const result = await sqlMonitorApiClient.executeQuery(request);
  if (!result.success) {
    // Display errors from result.errors
    showErrorNotification(result.errors[0].message);
  }
} catch (error) {
  // Network or HTTP errors
  if (error.status === 401) {
    showErrorNotification('Unauthorized. Please log in.');
  } else if (error.status === 403) {
    showErrorNotification('Access denied. You do not have permission to execute queries.');
  } else if (error.status === 500) {
    showErrorNotification('Server error. Please try again later.');
  } else {
    showErrorNotification('An unexpected error occurred.');
  }
}
```

---

## Authentication & Authorization

### Required Permissions

| Endpoint | Permission | Description |
|----------|-----------|-------------|
| `POST /api/code/execute` | `code.execute` | Execute queries |
| `POST /api/code/cancel` | `code.execute` | Cancel queries |
| `GET /api/code/servers` | `code.view` | View servers |
| `GET /api/code/servers/{id}/databases` | `code.view` | View databases |
| `GET /api/code/servers/{id}/databases/{db}/objects` | `code.view` | View object metadata |
| `GET /api/code/servers/{id}/databases/{db}/objects/{obj}/code` | `code.view` | View object definitions |

### JWT Token Handling

Frontend already handles JWT tokens via Grafana's `getBackendSrv()`. No additional work needed.

---

## Testing Strategy

### Backend Unit Tests

Create in `tests/SqlMonitor.Api.Tests/Controllers/`:

```csharp
public class CodeControllerTests
{
    [Fact]
    public async Task ExecuteQuery_ValidRequest_ReturnsResults()
    {
        // Arrange
        var controller = new CodeController(_mockSqlService.Object);
        var request = new QueryExecutionRequest
        {
            ServerId = 1,
            DatabaseName = "TestDB",
            Query = "SELECT TOP 10 * FROM Customers",
            TimeoutSeconds = 30
        };

        // Act
        var result = await controller.ExecuteQuery(request);

        // Assert
        Assert.IsType<OkObjectResult>(result.Result);
        var okResult = result.Result as OkObjectResult;
        var queryResult = okResult.Value as QueryExecutionResult;
        Assert.True(queryResult.Success);
        Assert.NotEmpty(queryResult.ResultSets);
    }

    [Fact]
    public async Task ExecuteQuery_InvalidServer_ReturnsNotFound()
    {
        // Arrange
        var controller = new CodeController(_mockSqlService.Object);
        var request = new QueryExecutionRequest
        {
            ServerId = 999,
            DatabaseName = "TestDB",
            Query = "SELECT 1",
        };

        _mockServerService.Setup(x => x.GetServerByIdAsync(999))
            .ReturnsAsync((Server)null);

        // Act
        var result = await controller.ExecuteQuery(request);

        // Assert
        Assert.IsType<NotFoundObjectResult>(result.Result);
    }
}
```

### Integration Tests

```csharp
[Collection("Integration")]
public class CodeApiIntegrationTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public CodeApiIntegrationTests(WebApplicationFactory<Program> factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task GetServers_ReturnsListOfServers()
    {
        // Arrange
        var token = await GetAuthTokenAsync();
        _client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

        // Act
        var response = await _client.GetAsync("/api/code/servers");

        // Assert
        response.EnsureSuccessStatusCode();
        var servers = await response.Content.ReadAsAsync<List<ServerInfo>>();
        Assert.NotEmpty(servers);
    }
}
```

### Frontend Testing

Update existing tests to use real API calls instead of mocks (with test API server).

---

## Implementation Phases

### Phase 1: Backend Scaffolding (4 hours)
1. Create CodeController
2. Create DTOs/Models
3. Create SqlExecutionService
4. Add unit tests for models
5. Configure routing and permissions

### Phase 2: Query Execution (4 hours)
1. Implement `POST /api/code/execute`
2. Implement `POST /api/code/cancel`
3. Add error handling and logging
4. Add audit logging
5. Write unit tests
6. Write integration tests

### Phase 3: Metadata APIs (3 hours)
1. Implement `GET /api/code/servers`
2. Implement `GET /api/code/servers/{id}/databases`
3. Implement `GET /api/code/servers/{id}/databases/{db}/objects`
4. Implement `GET /api/code/servers/{id}/databases/{db}/objects/{obj}/code`
5. Write unit tests

### Phase 4: Frontend Integration (3 hours)
1. Update sqlMonitorApiClient.ts with real API calls
2. Add configuration for datasource UID
3. Update error handling
4. Test with backend
5. Update monacoIntelliSenseService to use real metadata

### Phase 5: Testing & Validation (2 hours)
1. End-to-end testing
2. Performance testing
3. Security testing (SQL injection prevention)
4. Error scenario testing
5. Documentation updates

**Total Estimated Time**: 16 hours

---

## Rollback Plan

### If API Integration Fails

1. **Keep Mock Implementation**: Rename current `sqlMonitorApiClient.ts` to `sqlMonitorApiClient.mock.ts`
2. **Feature Flag**: Add environment variable `USE_MOCK_API=true`
3. **Conditional Import**:
   ```typescript
   const apiClient = process.env.USE_MOCK_API
     ? require('./sqlMonitorApiClient.mock')
     : require('./sqlMonitorApiClient');
   ```
4. **Gradual Migration**: Migrate endpoint by endpoint with feature flags per endpoint

### Rollback Procedure

1. Set `USE_MOCK_API=true` in environment
2. Redeploy frontend
3. No backend changes needed (endpoints remain available)
4. Fix issues offline
5. Re-enable real API when ready

---

## Security Considerations

### SQL Injection Prevention

1. **Never concatenate user input into queries**
2. Use **parameterized queries** for all dynamic SQL
3. Validate user input (max length, allowed characters)
4. Use **sp_executesql** for dynamic SQL in stored procedures
5. Implement **query whitelisting** for production environments (optional)

### Authorization

1. Verify user has access to server before executing query
2. Check database-level permissions
3. Log all query executions to audit table
4. Rate limiting (max 100 queries per user per minute)
5. Query size limits (max 1MB query text)

### Data Protection

1. Encrypt connection strings in configuration
2. Use Windows Authentication where possible
3. Never log sensitive data (passwords, SSNs, etc.)
4. Mask sensitive columns in results (configurable per table)

---

## Performance Considerations

### Query Execution

1. **Timeout Handling**: Default 60s, configurable per query
2. **Result Set Limits**: Default 10,000 rows, configurable
3. **Connection Pooling**: Reuse connections for same server
4. **Async Execution**: Use async/await throughout

### Metadata Caching

1. Cache object metadata for 24 hours (already implemented in Phase 1.25)
2. Refresh cache on demand via API endpoint
3. Use Redis for distributed caching (future enhancement)

### API Response Size

1. Compress responses with gzip
2. Paginate large result sets (future enhancement)
3. Stream large result sets (future enhancement)

---

## Next Steps

1. **Review this plan** with team/stakeholders
2. **Create backend branch**: `feature/code-api`
3. **Create frontend branch**: `feature/api-integration`
4. **Implement Phase 1**: Backend scaffolding
5. **Test Phase 1** with Postman/curl
6. **Implement Phase 2-5** incrementally
7. **Merge to main** after testing

---

**Prepared By**: Claude Code Assistant
**Date**: 2025-11-02
**Status**: Ready for implementation
**Estimated Effort**: 16 hours (2 days)
