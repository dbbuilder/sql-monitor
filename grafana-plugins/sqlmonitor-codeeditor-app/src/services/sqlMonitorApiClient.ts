/**
 * SQL Monitor API Client
 *
 * Handles all communication with the SQL Monitor API backend:
 * - Query execution with timeout
 * - Object metadata retrieval (for IntelliSense)
 * - Server/database listing
 * - Schema browsing
 * - Code object retrieval
 *
 * Week 3: Query execution implementation
 * Week 4: Metadata and schema browsing
 */

import { getBackendSrv } from '@grafana/runtime';
import type { QueryExecutionResult, QueryExecutionRequest } from '../types/query';

/**
 * API configuration
 * Points to the ASP.NET Core API (port 9000) running alongside Grafana
 */
const API_BASE_URL = '/api'; // Will be proxied through Grafana to http://sql-monitor-api:9000/api
const DEFAULT_TIMEOUT_MS = 60000; // 60 seconds

/**
 * Server information
 */
export interface ServerInfo {
  serverId: number;
  serverName: string;
  serverType: string;
  isActive: boolean;
  connectionString?: string;
}

/**
 * Database object metadata (for IntelliSense)
 */
export interface ObjectMetadata {
  serverId: number;
  serverName: string;
  databaseName: string;
  schemaName: string;
  objectName: string;
  objectType: 'table' | 'view' | 'procedure' | 'function';
  definition?: string;
  description?: string;
  columns?: ColumnMetadata[];
}

/**
 * Column metadata
 */
export interface ColumnMetadata {
  columnName: string;
  dataType: string;
  isNullable: boolean;
  defaultValue?: string;
  description?: string;
}

/**
 * SQL Monitor API Client
 */
export class SqlMonitorApiClient {
  private static instance: SqlMonitorApiClient;

  private constructor() {
    // Singleton pattern
  }

  /**
   * Get singleton instance
   */
  public static getInstance(): SqlMonitorApiClient {
    if (!SqlMonitorApiClient.instance) {
      SqlMonitorApiClient.instance = new SqlMonitorApiClient();
    }
    return SqlMonitorApiClient.instance;
  }

  /**
   * Execute SQL query
   * Updated to use real backend API (Feature #7 integration)
   */
  public async executeQuery(request: QueryExecutionRequest): Promise<QueryExecutionResult> {
    console.log('[SqlMonitorApiClient] Executing query:', {
      serverId: request.serverId,
      database: request.databaseName,
      queryLength: request.query.length,
    });

    const startTime = Date.now();

    try {
      // Call real backend API endpoint
      const apiRequest = {
        serverId: request.serverId,
        database: request.databaseName,
        query: request.query,
        timeoutSeconds: request.timeoutSeconds || 60,
        maxRows: request.maxRows || 5000,
      };

      const response = await getBackendSrv().post(`${API_BASE_URL}/code/execute`, apiRequest, {
        timeout: request.timeoutSeconds ? request.timeoutSeconds * 1000 : DEFAULT_TIMEOUT_MS,
      });

      // Map backend response to frontend format
      const result: QueryExecutionResult = {
        success: response.success,
        executionId: this.generateExecutionId(),
        rowsAffected: response.rowsAffected || 0,
        resultSets: response.resultSets.map((rs: any, index: number) => ({
          columns: rs.columns.map((col: any, ordinal: number) => ({
            name: col.name,
            dataType: col.dataType,
            ordinal,
          })),
          rows: rs.rows,
          rowCount: rs.rowCount || rs.rows.length,
        })),
        messages: response.messages || [],
        errors: response.error
          ? [
              {
                message: response.error,
                lineNumber: 0,
                severity: 'Error',
              },
            ]
          : [],
        executionTimeMs: response.executionTimeMs || Date.now() - startTime,
        serverName: `Server${request.serverId}`,
        databaseName: request.databaseName,
        executedAt: new Date().toISOString(),
      };

      console.log('[SqlMonitorApiClient] Query execution completed:', {
        success: result.success,
        resultSets: result.resultSets.length,
        executionTimeMs: result.executionTimeMs,
      });

      return result;
    } catch (error) {
      console.error('[SqlMonitorApiClient] Query execution failed:', error);

      const errorResult: QueryExecutionResult = {
        success: false,
        executionId: this.generateExecutionId(),
        rowsAffected: 0,
        resultSets: [],
        messages: [],
        errors: [
          {
            message: error instanceof Error ? error.message : 'Unknown error occurred',
            lineNumber: 0,
            severity: 'Error',
          },
        ],
        executionTimeMs: Date.now() - startTime,
        serverName: `Server${request.serverId}`,
        databaseName: request.databaseName,
        executedAt: new Date().toISOString(),
      };

      return errorResult;
    }
  }

  /**
   * Cancel running query
   * Week 3 Day 9-10 implementation
   */
  public async cancelQuery(executionId: string): Promise<boolean> {
    console.log('[SqlMonitorApiClient] Canceling query:', executionId);

    try {
      // TODO: Replace with actual API endpoint
      // await getBackendSrv().post('/api/sqlmonitor/cancel', { executionId });

      // MOCK IMPLEMENTATION
      await this.mockDelay(500);
      return true;
    } catch (error) {
      console.error('[SqlMonitorApiClient] Query cancellation failed:', error);
      return false;
    }
  }

  /**
   * Get list of monitored servers
   * Week 4 implementation (for now, returns mock data)
   */
  public async getServers(): Promise<ServerInfo[]> {
    console.log('[SqlMonitorApiClient] Fetching servers...');

    try {
      // TODO: Replace with actual API endpoint
      // const response = await getBackendSrv().get('/api/sqlmonitor/servers');

      // MOCK IMPLEMENTATION
      await this.mockDelay(300);

      const mockServers: ServerInfo[] = [
        {
          serverId: 1,
          serverName: 'SQL-PROD-01',
          serverType: 'SQL Server 2019',
          isActive: true,
        },
        {
          serverId: 2,
          serverName: 'SQL-DEV-01',
          serverType: 'SQL Server 2022',
          isActive: true,
        },
        {
          serverId: 3,
          serverName: 'SQL-TEST-01',
          serverType: 'SQL Server 2019',
          isActive: true,
        },
      ];

      return mockServers;
    } catch (error) {
      console.error('[SqlMonitorApiClient] Failed to fetch servers:', error);
      return [];
    }
  }

  /**
   * Get databases for a server
   * Week 4 implementation (for now, returns mock data)
   */
  public async getDatabases(serverId: number): Promise<string[]> {
    console.log('[SqlMonitorApiClient] Fetching databases for server:', serverId);

    try {
      // TODO: Replace with actual API endpoint
      // const response = await getBackendSrv().get(`/api/sqlmonitor/servers/${serverId}/databases`);

      // MOCK IMPLEMENTATION
      await this.mockDelay(300);

      const mockDatabases = ['master', 'SalesDB', 'InventoryDB', 'HRDB', 'AnalyticsDB'];
      return mockDatabases;
    } catch (error) {
      console.error('[SqlMonitorApiClient] Failed to fetch databases:', error);
      return [];
    }
  }

  /**
   * Get object metadata for IntelliSense
   * Week 4 implementation (for now, returns mock data)
   */
  public async getObjectMetadata(serverId: number, databaseName: string): Promise<ObjectMetadata[]> {
    console.log('[SqlMonitorApiClient] Fetching object metadata:', { serverId, databaseName });

    try {
      // TODO: Replace with actual API endpoint
      // const response = await getBackendSrv().get(
      //   `/api/sqlmonitor/servers/${serverId}/databases/${databaseName}/objects`
      // );

      // MOCK IMPLEMENTATION
      await this.mockDelay(500);

      // Return mock metadata (same as monacoIntelliSenseService)
      const mockMetadata: ObjectMetadata[] = [
        {
          serverId,
          serverName: `Server${serverId}`,
          databaseName,
          schemaName: 'dbo',
          objectName: 'Customers',
          objectType: 'table',
          description: 'Customer master table',
          columns: [
            { columnName: 'CustomerID', dataType: 'INT', isNullable: false, description: 'Primary key' },
            { columnName: 'CustomerName', dataType: 'NVARCHAR(200)', isNullable: false, description: 'Customer full name' },
            { columnName: 'Email', dataType: 'NVARCHAR(100)', isNullable: true, description: 'Customer email' },
          ],
        },
        {
          serverId,
          serverName: `Server${serverId}`,
          databaseName,
          schemaName: 'dbo',
          objectName: 'Orders',
          objectType: 'table',
          description: 'Sales orders table',
          columns: [
            { columnName: 'OrderID', dataType: 'INT', isNullable: false, description: 'Primary key' },
            { columnName: 'CustomerID', dataType: 'INT', isNullable: false, description: 'Foreign key to Customers' },
            { columnName: 'OrderDate', dataType: 'DATETIME2', isNullable: false, description: 'Order date' },
          ],
        },
      ];

      return mockMetadata;
    } catch (error) {
      console.error('[SqlMonitorApiClient] Failed to fetch object metadata:', error);
      return [];
    }
  }

  /**
   * Get object code definition
   * Week 4 implementation (for now, returns mock data)
   */
  public async getObjectCode(
    serverId: number,
    databaseName: string,
    schemaName: string,
    objectName: string,
    objectType: 'table' | 'view' | 'procedure' | 'function'
  ): Promise<string> {
    console.log('[SqlMonitorApiClient] Fetching object code:', { serverId, databaseName, schemaName, objectName, objectType });

    try {
      // TODO: Replace with actual API endpoint
      // const response = await getBackendSrv().get(
      //   `/api/sqlmonitor/servers/${serverId}/databases/${databaseName}/objects/${schemaName}.${objectName}/code`
      // );

      // MOCK IMPLEMENTATION
      await this.mockDelay(500);

      if (objectType === 'procedure') {
        return `-- Mock stored procedure code
CREATE PROCEDURE ${schemaName}.${objectName}
  @Parameter1 INT = NULL,
  @Parameter2 NVARCHAR(100) = NULL
AS
BEGIN
  SET NOCOUNT ON;

  -- Sample query
  SELECT *
  FROM ${schemaName}.SomeTable
  WHERE Column1 = @Parameter1
    AND Column2 = @Parameter2;

  -- Return status
  RETURN 0;
END
GO`;
      } else if (objectType === 'function') {
        return `-- Mock function code
CREATE FUNCTION ${schemaName}.${objectName}(@Input INT)
RETURNS INT
AS
BEGIN
  DECLARE @Result INT;

  -- Sample calculation
  SET @Result = @Input * 2;

  RETURN @Result;
END
GO`;
      } else if (objectType === 'view') {
        return `-- Mock view code
CREATE VIEW ${schemaName}.${objectName}
AS
  SELECT
    Column1,
    Column2,
    Column3
  FROM ${schemaName}.BaseTable
  WHERE IsActive = 1;
GO`;
      } else {
        // Table - return CREATE TABLE statement
        return `-- Mock table definition
CREATE TABLE ${schemaName}.${objectName}
(
  ID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  Name NVARCHAR(200) NOT NULL,
  Description NVARCHAR(MAX) NULL,
  CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
  ModifiedDate DATETIME2 NULL
);
GO`;
      }
    } catch (error) {
      console.error('[SqlMonitorApiClient] Failed to fetch object code:', error);
      return `-- Error loading object code: ${error instanceof Error ? error.message : 'Unknown error'}`;
    }
  }

  /**
   * Helper: Generate unique execution ID
   */
  private generateExecutionId(): string {
    return `exec_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
  }

  /**
   * Helper: Mock delay for simulating API calls
   */
  private mockDelay(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}

/**
 * Singleton instance
 */
export const sqlMonitorApiClient = SqlMonitorApiClient.getInstance();
