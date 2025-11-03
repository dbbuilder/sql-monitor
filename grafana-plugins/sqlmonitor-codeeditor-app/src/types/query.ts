/**
 * Type definitions for T-SQL query execution
 *
 * These types define the structure for:
 * - Query execution requests
 * - Query execution results
 * - Execution plans
 * - Column metadata
 */

/**
 * Request to execute a T-SQL query
 */
export interface QueryRequest {
  /** ID of the server to execute the query on */
  serverId: number;

  /** Name of the database to use */
  databaseName: string;

  /** T-SQL query to execute */
  query: string;

  /** Timeout in seconds (default: 60) */
  timeout?: number;

  /** Whether to include execution plan (default: false) */
  includeExecutionPlan?: boolean;

  /** Maximum number of rows to return (default: 10000) */
  maxRows?: number;
}

/**
 * Result of a query execution
 */
export interface QueryResult {
  /** Whether the query executed successfully */
  success: boolean;

  /** Execution time in milliseconds */
  executionTime: number;

  /** Number of rows returned */
  rowCount: number;

  /** Column metadata */
  columns: ColumnInfo[];

  /** Result rows */
  rows: any[];

  /** SQL Server messages (PRINT, RAISERROR, etc.) */
  messages: string[];

  /** Execution plan (if requested) */
  executionPlan?: ExecutionPlan;

  /** Error message (if success = false) */
  error?: string;

  /** Warning messages */
  warnings?: string[];

  /** Statistics (SET STATISTICS IO ON, etc.) */
  statistics?: QueryStatistics;
}

/**
 * Column metadata for query results
 */
export interface ColumnInfo {
  /** Column name */
  name: string;

  /** SQL Server data type (e.g., int, varchar, datetime2) */
  type: string;

  /** Whether the column is nullable */
  nullable: boolean;

  /** Maximum length (for string/binary types) */
  maxLength?: number;

  /** Precision (for decimal/numeric types) */
  precision?: number;

  /** Scale (for decimal/numeric types) */
  scale?: number;
}

/**
 * Execution plan information
 */
export interface ExecutionPlan {
  /** XML representation of the execution plan */
  xml: string;

  /** Estimated cost of the query */
  estimatedCost: number;

  /** Estimated number of rows */
  estimatedRows: number;

  /** Actual number of rows (if execution plan includes actual) */
  actualRows?: number;

  /** Execution plan warnings */
  warnings: string[];

  /** Missing index recommendations from execution plan */
  missingIndexes?: MissingIndexRecommendation[];
}

/**
 * Missing index recommendation from execution plan
 */
export interface MissingIndexRecommendation {
  /** Impact score (0-100) */
  impact: number;

  /** CREATE INDEX statement */
  createIndexStatement: string;

  /** Columns to include in index */
  includedColumns: string[];

  /** Equality columns */
  equalityColumns: string[];

  /** Inequality columns */
  inequalityColumns: string[];
}

/**
 * Query execution statistics
 */
export interface QueryStatistics {
  /** Logical reads */
  logicalReads: number;

  /** Physical reads */
  physicalReads: number;

  /** Read-ahead reads */
  readAheadReads: number;

  /** CPU time in milliseconds */
  cpuTimeMs: number;

  /** Elapsed time in milliseconds */
  elapsedTimeMs: number;

  /** Number of scans */
  scanCount?: number;

  /** Rows affected (for INSERT/UPDATE/DELETE) */
  rowsAffected?: number;
}

/**
 * Server information for query execution
 */
export interface ServerInfo {
  /** Server ID */
  serverId: number;

  /** Server name */
  serverName: string;

  /** Server description */
  description?: string;

  /** Whether the server is currently online */
  isOnline: boolean;

  /** SQL Server version */
  version?: string;

  /** SQL Server edition (Standard, Enterprise, etc.) */
  edition?: string;
}

/**
 * Database information
 */
export interface DatabaseInfo {
  /** Database name */
  databaseName: string;

  /** Database size in MB */
  sizeMB: number;

  /** Compatibility level (100, 110, 120, 130, 140, 150) */
  compatibilityLevel: number;

  /** Recovery model (FULL, SIMPLE, BULK_LOGGED) */
  recoveryModel: string;

  /** Whether the database is online */
  isOnline: boolean;

  /** Collation */
  collation?: string;
}

/**
 * Request to get list of servers
 */
export interface GetServersRequest {
  /** Whether to include offline servers (default: false) */
  includeOffline?: boolean;
}

/**
 * Response with list of servers
 */
export interface GetServersResponse {
  /** Whether the request was successful */
  success: boolean;

  /** List of servers */
  servers: ServerInfo[];

  /** Error message (if success = false) */
  error?: string;
}

/**
 * Request to get list of databases for a server
 */
export interface GetDatabasesRequest {
  /** Server ID */
  serverId: number;

  /** Whether to include system databases (default: false) */
  includeSystemDatabases?: boolean;
}

/**
 * Response with list of databases
 */
export interface GetDatabasesResponse {
  /** Whether the request was successful */
  success: boolean;

  /** List of databases */
  databases: DatabaseInfo[];

  /** Error message (if success = false) */
  error?: string;
}

/**
 * Query validation result
 * Checks query syntax without executing it
 */
export interface QueryValidationResult {
  /** Whether the query is syntactically valid */
  isValid: boolean;

  /** Validation errors */
  errors: ValidationError[];

  /** Validation warnings */
  warnings: ValidationWarning[];
}

/**
 * Validation error
 */
export interface ValidationError {
  /** Error message */
  message: string;

  /** Line number (1-indexed) */
  line: number;

  /** Column number (1-indexed) */
  column: number;

  /** Error severity (informational, warning, error) */
  severity: string;
}

/**
 * Validation warning
 */
export interface ValidationWarning {
  /** Warning message */
  message: string;

  /** Line number (1-indexed) */
  line?: number;

  /** Column number (1-indexed) */
  column?: number;
}
