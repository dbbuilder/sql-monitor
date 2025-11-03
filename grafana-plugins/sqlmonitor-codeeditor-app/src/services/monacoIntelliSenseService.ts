/**
 * Monaco IntelliSense Service
 *
 * Provides schema-aware IntelliSense for T-SQL code:
 * - Completion provider (autocomplete for tables, columns, stored procedures, functions)
 * - Definition provider (F12 - Go to Definition)
 * - Hover provider (tooltips for database objects)
 *
 * Week 3: Will fetch metadata from SqlMonitorApiClient
 */

import * as monaco from 'monaco-editor';

/**
 * Database object metadata for IntelliSense
 */
export interface DatabaseObject {
  name: string;
  type: 'table' | 'view' | 'procedure' | 'function' | 'column';
  schema: string;
  database: string;
  serverId: number;
  description?: string;
  definition?: string;
  /** For columns: parent table/view name */
  parentObject?: string;
  /** For columns: data type */
  dataType?: string;
}

/**
 * Monaco IntelliSense Service
 */
export class MonacoIntelliSenseService {
  private static instance: MonacoIntelliSenseService;
  private objectMetadata: DatabaseObject[] = [];
  private completionProvider: monaco.IDisposable | null = null;
  private definitionProvider: monaco.IDisposable | null = null;
  private hoverProvider: monaco.IDisposable | null = null;

  private constructor() {
    // Singleton pattern
  }

  /**
   * Get singleton instance
   */
  public static getInstance(): MonacoIntelliSenseService {
    if (!MonacoIntelliSenseService.instance) {
      MonacoIntelliSenseService.instance = new MonacoIntelliSenseService();
    }
    return MonacoIntelliSenseService.instance;
  }

  /**
   * Initialize IntelliSense providers for SQL language
   */
  public initialize(): void {
    console.log('[MonacoIntelliSense] Initializing IntelliSense providers...');

    // Load mock metadata (will be replaced with API call in Week 3)
    this.loadMockMetadata();

    // Register providers
    this.registerCompletionProvider();
    this.registerDefinitionProvider();
    this.registerHoverProvider();

    console.log('[MonacoIntelliSense] IntelliSense providers registered');
  }

  /**
   * Dispose all providers
   */
  public dispose(): void {
    this.completionProvider?.dispose();
    this.definitionProvider?.dispose();
    this.hoverProvider?.dispose();
  }

  /**
   * Load object metadata (mock data for now)
   * TODO: Week 3 - Fetch from SqlMonitorApiClient.getObjectMetadata(serverId, databaseName)
   */
  private loadMockMetadata(): void {
    this.objectMetadata = [
      // Tables
      {
        name: 'Customers',
        type: 'table',
        schema: 'dbo',
        database: 'SalesDB',
        serverId: 1,
        description: 'Customer master table',
      },
      {
        name: 'Orders',
        type: 'table',
        schema: 'dbo',
        database: 'SalesDB',
        serverId: 1,
        description: 'Sales orders table',
      },
      {
        name: 'Products',
        type: 'table',
        schema: 'dbo',
        database: 'SalesDB',
        serverId: 1,
        description: 'Product catalog',
      },

      // Columns for Customers table
      {
        name: 'CustomerID',
        type: 'column',
        schema: 'dbo',
        database: 'SalesDB',
        serverId: 1,
        parentObject: 'Customers',
        dataType: 'INT',
        description: 'Primary key',
      },
      {
        name: 'CustomerName',
        type: 'column',
        schema: 'dbo',
        database: 'SalesDB',
        serverId: 1,
        parentObject: 'Customers',
        dataType: 'NVARCHAR(200)',
        description: 'Customer full name',
      },
      {
        name: 'Email',
        type: 'column',
        schema: 'dbo',
        database: 'SalesDB',
        serverId: 1,
        parentObject: 'Customers',
        dataType: 'NVARCHAR(100)',
        description: 'Customer email address',
      },

      // Columns for Orders table
      {
        name: 'OrderID',
        type: 'column',
        schema: 'dbo',
        database: 'SalesDB',
        serverId: 1,
        parentObject: 'Orders',
        dataType: 'INT',
        description: 'Primary key',
      },
      {
        name: 'CustomerID',
        type: 'column',
        schema: 'dbo',
        database: 'SalesDB',
        serverId: 1,
        parentObject: 'Orders',
        dataType: 'INT',
        description: 'Foreign key to Customers',
      },
      {
        name: 'OrderDate',
        type: 'column',
        schema: 'dbo',
        database: 'SalesDB',
        serverId: 1,
        parentObject: 'Orders',
        dataType: 'DATETIME2',
        description: 'Order date',
      },

      // Views
      {
        name: 'vw_ActiveOrders',
        type: 'view',
        schema: 'dbo',
        database: 'SalesDB',
        serverId: 1,
        description: 'View of active orders',
      },

      // Stored Procedures
      {
        name: 'usp_GetCustomers',
        type: 'procedure',
        schema: 'dbo',
        database: 'SalesDB',
        serverId: 1,
        description: 'Retrieve customer list',
        definition: 'CREATE PROCEDURE dbo.usp_GetCustomers\nAS\nBEGIN\n  SELECT * FROM dbo.Customers;\nEND',
      },
      {
        name: 'usp_GetOrders',
        type: 'procedure',
        schema: 'dbo',
        database: 'SalesDB',
        serverId: 1,
        description: 'Retrieve orders for a customer',
        definition:
          'CREATE PROCEDURE dbo.usp_GetOrders\n  @CustomerID INT\nAS\nBEGIN\n  SELECT * FROM dbo.Orders WHERE CustomerID = @CustomerID;\nEND',
      },

      // Functions
      {
        name: 'fn_CalculateDiscount',
        type: 'function',
        schema: 'dbo',
        database: 'SalesDB',
        serverId: 1,
        description: 'Calculate discount percentage',
        definition:
          'CREATE FUNCTION dbo.fn_CalculateDiscount(@Amount DECIMAL(10,2))\nRETURNS DECIMAL(5,2)\nAS\nBEGIN\n  RETURN @Amount * 0.1;\nEND',
      },
    ];

    console.log('[MonacoIntelliSense] Loaded', this.objectMetadata.length, 'metadata objects');
  }

  /**
   * Register completion provider (autocomplete)
   */
  private registerCompletionProvider(): void {
    this.completionProvider = monaco.languages.registerCompletionItemProvider('sql', {
      provideCompletionItems: (model, position) => {
        const word = model.getWordUntilPosition(position);
        const range = {
          startLineNumber: position.lineNumber,
          startColumn: word.startColumn,
          endLineNumber: position.lineNumber,
          endColumn: word.endColumn,
        };

        const suggestions: monaco.languages.CompletionItem[] = [];

        // Detect context (after FROM/JOIN/UPDATE/INTO = suggest tables/views)
        const lineText = model.getLineContent(position.lineNumber).substring(0, position.column - 1);
        const afterFrom = /\b(FROM|JOIN|UPDATE|INTO)\s+$/i.test(lineText);
        const afterDot = /\b(\w+)\.$/i.test(lineText); // After "table."

        if (afterDot) {
          // After dot: suggest columns for that table
          const match = lineText.match(/\b(\w+)\.$/i);
          if (match) {
            const tableName = match[1];
            const columns = this.objectMetadata.filter(
              (obj) => obj.type === 'column' && obj.parentObject?.toLowerCase() === tableName.toLowerCase()
            );

            columns.forEach((col) => {
              suggestions.push({
                label: col.name,
                kind: monaco.languages.CompletionItemKind.Field,
                detail: col.dataType || 'Column',
                documentation: col.description,
                insertText: col.name,
                range,
              });
            });
          }
        } else if (afterFrom) {
          // After FROM/JOIN: suggest tables and views
          const tablesAndViews = this.objectMetadata.filter((obj) => obj.type === 'table' || obj.type === 'view');

          tablesAndViews.forEach((obj) => {
            suggestions.push({
              label: `${obj.schema}.${obj.name}`,
              kind: obj.type === 'table' ? monaco.languages.CompletionItemKind.Class : monaco.languages.CompletionItemKind.Interface,
              detail: obj.type === 'table' ? 'Table' : 'View',
              documentation: obj.description,
              insertText: `${obj.schema}.${obj.name}`,
              range,
            });
          });
        } else {
          // General context: suggest all objects
          this.objectMetadata.forEach((obj) => {
            if (obj.type === 'table' || obj.type === 'view') {
              suggestions.push({
                label: `${obj.schema}.${obj.name}`,
                kind: obj.type === 'table' ? monaco.languages.CompletionItemKind.Class : monaco.languages.CompletionItemKind.Interface,
                detail: obj.type === 'table' ? 'Table' : 'View',
                documentation: obj.description,
                insertText: `${obj.schema}.${obj.name}`,
                range,
              });
            } else if (obj.type === 'procedure' || obj.type === 'function') {
              suggestions.push({
                label: `${obj.schema}.${obj.name}`,
                kind: obj.type === 'procedure' ? monaco.languages.CompletionItemKind.Method : monaco.languages.CompletionItemKind.Function,
                detail: obj.type === 'procedure' ? 'Stored Procedure' : 'Function',
                documentation: obj.description,
                insertText: `${obj.schema}.${obj.name}`,
                range,
              });
            }
          });

          // Add SQL keywords
          const keywords = [
            'SELECT', 'FROM', 'WHERE', 'JOIN', 'INNER', 'LEFT', 'RIGHT', 'FULL', 'OUTER',
            'ON', 'AND', 'OR', 'NOT', 'IN', 'EXISTS', 'BETWEEN', 'LIKE', 'IS', 'NULL',
            'ORDER', 'BY', 'ASC', 'DESC', 'GROUP', 'HAVING', 'COUNT', 'SUM', 'AVG', 'MAX', 'MIN',
            'INSERT', 'INTO', 'VALUES', 'UPDATE', 'SET', 'DELETE', 'CREATE', 'ALTER', 'DROP',
            'TABLE', 'VIEW', 'PROCEDURE', 'FUNCTION', 'BEGIN', 'END', 'IF', 'ELSE', 'WHILE',
            'DECLARE', 'INT', 'VARCHAR', 'NVARCHAR', 'DECIMAL', 'DATETIME', 'BIT'
          ];

          keywords.forEach((keyword) => {
            suggestions.push({
              label: keyword,
              kind: monaco.languages.CompletionItemKind.Keyword,
              insertText: keyword,
              range,
            });
          });
        }

        return { suggestions };
      },
    });
  }

  /**
   * Register definition provider (F12 - Go to Definition)
   */
  private registerDefinitionProvider(): void {
    this.definitionProvider = monaco.languages.registerDefinitionProvider('sql', {
      provideDefinition: (model, position) => {
        const word = model.getWordAtPosition(position);
        if (!word) return null;

        const objectName = word.word;

        // Find object in metadata
        const obj = this.objectMetadata.find(
          (o) =>
            (o.type === 'table' || o.type === 'view' || o.type === 'procedure' || o.type === 'function') &&
            o.name.toLowerCase() === objectName.toLowerCase()
        );

        if (!obj || !obj.definition) {
          return null;
        }

        // TODO: Week 3 - Open definition in new tab using TabStateService
        // For now, return null (no-op)
        console.log('[MonacoIntelliSense] Go to definition:', obj.name);

        return null;
      },
    });
  }

  /**
   * Register hover provider (tooltips)
   */
  private registerHoverProvider(): void {
    this.hoverProvider = monaco.languages.registerHoverProvider('sql', {
      provideHover: (model, position) => {
        const word = model.getWordAtPosition(position);
        if (!word) return null;

        const objectName = word.word;

        // Find object in metadata
        const obj = this.objectMetadata.find(
          (o) =>
            (o.type === 'table' || o.type === 'view' || o.type === 'procedure' || o.type === 'function' || o.type === 'column') &&
            o.name.toLowerCase() === objectName.toLowerCase()
        );

        if (!obj) return null;

        const typeLabel =
          obj.type === 'table'
            ? 'Table'
            : obj.type === 'view'
            ? 'View'
            : obj.type === 'procedure'
            ? 'Stored Procedure'
            : obj.type === 'function'
            ? 'Function'
            : 'Column';

        const contents = [
          { value: `**${obj.schema}.${obj.name}** (${typeLabel})` },
          { value: obj.description || 'No description available' },
        ];

        if (obj.type === 'column' && obj.dataType) {
          contents.push({ value: `**Data Type:** ${obj.dataType}` });
        }

        return {
          contents,
        };
      },
    });
  }

  /**
   * Update metadata (call when server/database selection changes)
   * TODO: Week 3 - Fetch from API
   */
  public async updateMetadata(serverId: number, databaseName: string): Promise<void> {
    console.log('[MonacoIntelliSense] Updating metadata for', serverId, databaseName);
    // TODO: Fetch from SqlMonitorApiClient.getObjectMetadata(serverId, databaseName)
    // For now, use mock data
    this.loadMockMetadata();
  }
}

/**
 * Singleton instance
 */
export const monacoIntelliSenseService = MonacoIntelliSenseService.getInstance();
