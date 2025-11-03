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
 */
const API_BASE_URL = '/api/datasources/proxy/uid'; // Grafana datasource proxy
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
   * Week 3 Day 9-10 implementation
   */
  public async executeQuery(request: QueryExecutionRequest): Promise<QueryExecutionResult> {
    console.log('[SqlMonitorApiClient] Executing query:', {
      serverId: request.serverId,
      database: request.databaseName,
      queryLength: request.query.length,
    });

    const startTime = Date.now();

    try {
      // TODO: Replace with actual API endpoint
      // const response = await getBackendSrv().post('/api/sqlmonitor/execute', request, {
      //   timeout: request.timeoutSeconds ? request.timeoutSeconds * 1000 : DEFAULT_TIMEOUT_MS,
      // });

      // MOCK IMPLEMENTATION (Week 3 - will be replaced with real API)
      await this.mockDelay(1000); // Simulate 1 second query execution

      // Parse query type to determine response
      const queryUpper = request.query.trim().toUpperCase();
      const isSelect = queryUpper.startsWith('SELECT');
      const isInsert = queryUpper.startsWith('INSERT');
      const isUpdate = queryUpper.startsWith('UPDATE');
      const isDelete = queryUpper.startsWith('DELETE');
      const isExec = queryUpper.startsWith('EXEC');

      if (isSelect) {
        // Return mock result set
        const mockResult: QueryExecutionResult = {
          success: true,
          executionId: this.generateExecutionId(),
          rowsAffected: 0,
          resultSets: [
            {
              columns: [
                { name: 'CustomerID', dataType: 'int', ordinal: 0 },
                { name: 'CustomerName', dataType: 'nvarchar', ordinal: 1 },
                { name: 'Email', dataType: 'nvarchar', ordinal: 2 },
                { name: 'OrderCount', dataType: 'int', ordinal: 3 },
              ],
              rows: [
                { CustomerID: 1, CustomerName: 'Acme Corp', Email: 'contact@acme.com', OrderCount: 15 },
                { CustomerID: 2, CustomerName: 'TechStart Inc', Email: 'info@techstart.com', OrderCount: 8 },
                { CustomerID: 3, CustomerName: 'Global Solutions', Email: 'hello@global.com', OrderCount: 23 },
                { CustomerID: 4, CustomerName: 'Innovation Labs', Email: 'team@innovation.com', OrderCount: 12 },
                { CustomerID: 5, CustomerName: 'Smart Systems', Email: 'contact@smart.com', OrderCount: 19 },
              ],
              rowCount: 5,
            },
          ],
          messages: ['(5 rows affected)'],
          executionTimeMs: Date.now() - startTime,
          serverName: `Server${request.serverId}`,
          databaseName: request.databaseName,
          executedAt: new Date().toISOString(),
        };

        return mockResult;
      } else if (isInsert || isUpdate || isDelete) {
        // Return mock modification result
        const mockRowsAffected = Math.floor(Math.random() * 10) + 1;
        const mockResult: QueryExecutionResult = {
          success: true,
          executionId: this.generateExecutionId(),
          rowsAffected: mockRowsAffected,
          resultSets: [],
          messages: [`(${mockRowsAffected} rows affected)`],
          executionTimeMs: Date.now() - startTime,
          serverName: `Server${request.serverId}`,
          databaseName: request.databaseName,
          executedAt: new Date().toISOString(),
        };

        return mockResult;
      } else if (isExec) {
        // Return mock stored procedure result
        const mockResult: QueryExecutionResult = {
          success: true,
          executionId: this.generateExecutionId(),
          rowsAffected: 0,
          resultSets: [
            {
              columns: [
                { name: 'StatusCode', dataType: 'int', ordinal: 0 },
                { name: 'Message', dataType: 'nvarchar', ordinal: 1 },
              ],
              rows: [{ StatusCode: 0, Message: 'Stored procedure executed successfully' }],
              rowCount: 1,
            },
          ],
          messages: ['Stored procedure completed successfully'],
          executionTimeMs: Date.now() - startTime,
          serverName: `Server${request.serverId}`,
          databaseName: request.databaseName,
          executedAt: new Date().toISOString(),
        };

        return mockResult;
      } else {
        // Return mock success for DDL/other statements
        const mockResult: QueryExecutionResult = {
          success: true,
          executionId: this.generateExecutionId(),
          rowsAffected: 0,
          resultSets: [],
          messages: ['Command completed successfully'],
          executionTimeMs: Date.now() - startTime,
          serverName: `Server${request.serverId}`,
          databaseName: request.databaseName,
          executedAt: new Date().toISOString(),
        };

        return mockResult;
      }
    } catch (error) {
      console.error('[SqlMonitorApiClient] Query execution failed:', error);

      const mockErrorResult: QueryExecutionResult = {
        success: false,
        executionId: this.generateExecutionId(),
        rowsAffected: 0,
        resultSets: [],
        messages: [],
        errors: [
          {
            message: error instanceof Error ? error.message : 'Unknown error occurred',
            lineNumber: 1,
            severity: 'Error',
          },
        ],
        executionTimeMs: Date.now() - startTime,
        serverName: `Server${request.serverId}`,
        databaseName: request.databaseName,
        executedAt: new Date().toISOString(),
      };

      return mockErrorResult;
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
