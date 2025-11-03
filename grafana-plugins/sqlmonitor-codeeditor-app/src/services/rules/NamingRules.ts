/**
 * Naming Rules (N001-N005)
 *
 * Rules that enforce consistent naming conventions in T-SQL code.
 */

import { BaseRule } from './RuleBase';
import type { AnalysisResult, FixSuggestion } from '../../types/analysis';

/**
 * N001: Table names not using PascalCase
 * Detects table names with underscores or non-standard casing
 */
export class TableNamingConventionRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'N001',
      severity: 'Info',
      category: 'Naming',
      message: 'Table name should use PascalCase without underscores',
      enabled: false, // Disabled by default (style preference)
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];

    // Match CREATE TABLE statements
    const pattern = /CREATE\s+TABLE\s+(?:\[?\w+\]?\.)?((\[?)(\w+)(\]?))/gi;
    const matches = code.matchAll(pattern);

    for (const match of matches) {
      const fullTableName = match[1];
      const tableName = match[3]; // Without brackets

      // Check for underscores or non-PascalCase
      if (tableName.includes('_') || /^[a-z]/.test(tableName)) {
        const lineNumber = code.substring(0, match.index).split('\n').length;
        const columnNumber = match.index! - code.substring(0, match.index).lastIndexOf('\n');

        // Suggest PascalCase version
        const suggestedName = this.toPascalCase(tableName);

        results.push({
          ruleId: this.ruleId,
          severity: this.severity,
          category: this.category,
          message: `Table name "${tableName}" should use PascalCase: "${suggestedName}"`,
          line: lineNumber,
          column: columnNumber,
          before: fullTableName,
          after: suggestedName,
          explanation:
            'Use PascalCase for table names (e.g., CustomerOrders, not customer_orders or customerorders). ' +
            'Consistent naming conventions improve code readability and maintainability.',
        });
      }
    }

    return results;
  }

  private toPascalCase(str: string): string {
    return str
      .split('_')
      .map((word) => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
      .join('');
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Use PascalCase for table names',
      before: 'CREATE TABLE customer_orders (\n  order_id INT\n)',
      after: 'CREATE TABLE CustomerOrders (\n  OrderID INT\n)',
      explanation: 'PascalCase is the standard naming convention for SQL Server tables.',
      estimatedImpact: 'Low',
      autoFixAvailable: false,
    };
  }
}

/**
 * N002: Column names not using PascalCase
 * Detects column names with underscores or non-standard casing
 */
export class ColumnNamingConventionRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'N002',
      severity: 'Info',
      category: 'Naming',
      message: 'Column name should use PascalCase without underscores',
      enabled: false, // Disabled by default (style preference)
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];

    // Match column definitions in CREATE/ALTER TABLE
    const pattern =
      /(?:CREATE|ALTER)\s+TABLE[\s\S]*?\(\s*((?:\[?\w+\]?\s+(?:INT|VARCHAR|NVARCHAR|DECIMAL|DATETIME|BIT|UNIQUEIDENTIFIER|BIGINT|SMALLINT|TINYINT|CHAR|NCHAR|TEXT|NTEXT|FLOAT|REAL|MONEY|SMALLMONEY|DATE|TIME|DATETIME2|DATETIMEOFFSET)\b[\s\S]*?(?:,|\)))+)/gi;

    const columnPattern = /(\[?)(\w+)(\]?)\s+(?:INT|VARCHAR|NVARCHAR|DECIMAL|DATETIME|BIT|UNIQUEIDENTIFIER)/gi;

    const tableMatches = code.matchAll(pattern);

    for (const tableMatch of tableMatches) {
      const columnBlock = tableMatch[1];
      const columnMatches = columnBlock.matchAll(columnPattern);

      for (const colMatch of columnMatches) {
        const columnName = colMatch[2];

        // Check for underscores or non-PascalCase (but allow common patterns like ID)
        if (
          columnName.includes('_') &&
          !columnName.endsWith('ID') &&
          columnName !== 'ID' &&
          !/^[A-Z][a-z]*(?:[A-Z][a-z]*)*$/.test(columnName)
        ) {
          // Find position in original code
          const columnIndex = code.indexOf(colMatch[0], tableMatch.index || 0);
          if (columnIndex >= 0) {
            const lineNumber = code.substring(0, columnIndex).split('\n').length;
            const columnNumber = columnIndex - code.substring(0, columnIndex).lastIndexOf('\n');

            const suggestedName = this.toPascalCase(columnName);

            results.push({
              ruleId: this.ruleId,
              severity: this.severity,
              category: this.category,
              message: `Column name "${columnName}" should use PascalCase: "${suggestedName}"`,
              line: lineNumber,
              column: columnNumber,
              before: columnName,
              after: suggestedName,
              explanation:
                'Use PascalCase for column names (e.g., FirstName, not first_name). ' +
                'Consistent naming conventions improve code readability.',
            });
          }
        }
      }
    }

    return results;
  }

  private toPascalCase(str: string): string {
    return str
      .split('_')
      .map((word) => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
      .join('');
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Use PascalCase for column names',
      before: 'CREATE TABLE Customers (\n  customer_id INT,\n  first_name NVARCHAR(100)\n)',
      after: 'CREATE TABLE Customers (\n  CustomerID INT,\n  FirstName NVARCHAR(100)\n)',
      explanation: 'PascalCase is the standard naming convention for SQL Server columns.',
      estimatedImpact: 'Low',
      autoFixAvailable: false,
    };
  }
}

/**
 * N003: Stored procedures not using standard prefix
 * Detects stored procedures without usp_, uspx_ or organizational prefix
 */
export class ProcedureNamingConventionRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'N003',
      severity: 'Info',
      category: 'Naming',
      message: 'Stored procedure should use standard prefix (usp_, uspx_, etc.)',
      enabled: false, // Disabled by default (organizational preference)
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];

    // Match CREATE PROCEDURE statements
    const pattern = /CREATE\s+PROCEDURE\s+(?:\[?dbo\]?\.)?((\[?)(\w+)(\]?))/gi;
    const matches = code.matchAll(pattern);

    for (const match of matches) {
      const fullProcName = match[1];
      const procName = match[3]; // Without brackets

      // Check if it has a standard prefix (usp_, uspx_, sp_Get, sp_Insert, etc.)
      const hasStandardPrefix = /^(usp_|uspx_)/i.test(procName);
      const hasSpPrefix = /^sp_/i.test(procName); // sp_ is reserved for system procedures

      if (hasSpPrefix) {
        // Already handled by DP006 (sp_ prefix rule)
        continue;
      }

      if (!hasStandardPrefix && !this.isCommonPattern(procName)) {
        const lineNumber = code.substring(0, match.index).split('\n').length;
        const columnNumber = match.index! - code.substring(0, match.index).lastIndexOf('\n');

        const suggestedName = `usp_${procName}`;

        results.push({
          ruleId: this.ruleId,
          severity: this.severity,
          category: this.category,
          message: `Stored procedure "${procName}" missing standard prefix`,
          line: lineNumber,
          column: columnNumber,
          before: fullProcName,
          after: suggestedName,
          explanation:
            'Use prefixes like usp_ (user stored procedure) or uspx_ (extended) for clarity. ' +
            'This distinguishes user procedures from system procedures and improves organization.',
        });
      }
    }

    return results;
  }

  private isCommonPattern(name: string): boolean {
    // Allow common organizational patterns (Get*, Insert*, Update*, Delete*, Process*, etc.)
    return /^(Get|Insert|Update|Delete|Create|Process|Calculate|Generate|Validate|Execute)[A-Z]/.test(name);
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Add standard prefix to stored procedure',
      before: 'CREATE PROCEDURE GetCustomerOrders',
      after: 'CREATE PROCEDURE usp_GetCustomerOrders',
      explanation:
        'Use usp_ prefix for user stored procedures. This is a common organizational convention.',
      estimatedImpact: 'Low',
      autoFixAvailable: true,
    };
  }
}

/**
 * N004: Variables not using standard naming
 * Detects variables not using @camelCase or @PascalCase convention
 */
export class VariableNamingConventionRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'N004',
      severity: 'Info',
      category: 'Naming',
      message: 'Variable should use @camelCase or @PascalCase convention',
      enabled: false, // Disabled by default (style preference)
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];

    // Match DECLARE @variable statements
    const pattern = /DECLARE\s+(@\w+)/gi;
    const matches = this.findMatches(code, pattern);

    for (const match of matches) {
      const varName = match.match.replace('DECLARE', '').trim();

      if (this.isInComment(code, match.line - 1, match.column - 1)) {
        continue;
      }

      // Check for underscores (discouraged in variable names)
      if (varName.includes('_') && !varName.startsWith('@@')) {
        results.push(
          this.createResult(
            match,
            varName,
            this.toCamelCase(varName),
            'Variable names should use camelCase or PascalCase without underscores (e.g., @customerId or @CustomerID). ' +
              'Underscores make variable names harder to read and are not the SQL Server convention.'
          )
        );
      }
    }

    return results;
  }

  private toCamelCase(varName: string): string {
    // Remove @ symbol
    const name = varName.startsWith('@') ? varName.substring(1) : varName;

    // Convert snake_case to camelCase
    const parts = name.split('_');
    if (parts.length === 1) return varName; // Already no underscores

    const camelCase =
      parts[0].toLowerCase() + parts.slice(1).map((p) => p.charAt(0).toUpperCase() + p.slice(1).toLowerCase()).join('');

    return '@' + camelCase;
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Use camelCase for variables',
      before: 'DECLARE @customer_id INT;\nDECLARE @order_total DECIMAL(10,2);',
      after: 'DECLARE @customerId INT;\nDECLARE @orderTotal DECIMAL(10,2);',
      explanation: 'Use @camelCase for local variables and @PascalCase for parameters.',
      estimatedImpact: 'Low',
      autoFixAvailable: false,
    };
  }
}

/**
 * N005: Hungarian notation usage
 * Detects Hungarian notation prefixes (str, int, dt, etc.) which are discouraged
 */
export class HungarianNotationRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'N005',
      severity: 'Info',
      category: 'Naming',
      message: 'Avoid Hungarian notation - use descriptive names instead',
      enabled: false, // Disabled by default (style preference)
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];

    // Match variables or columns with Hungarian notation prefixes
    const pattern =
      /(@|\b)(str|int|dt|dec|flt|bln|bit|chr|dbl|lng|sng|obj|tbl|vw|sp|fn)[A-Z][a-z]*\b/g;
    const matches = this.findMatches(code, pattern);

    for (const match of matches) {
      if (this.isInComment(code, match.line - 1, match.column - 1)) {
        continue;
      }

      const name = match.match;
      const prefix = match.match.match(/^(?:@)?(str|int|dt|dec|flt|bln|bit|chr|dbl|lng|sng|obj|tbl|vw|sp|fn)/i)?.[1];

      if (prefix) {
        // Remove Hungarian prefix
        const cleanName = name.replace(
          new RegExp(`^(@)?(${prefix})`, 'i'),
          (_full, atSign) => atSign || ''
        );

        results.push(
          this.createResult(
            match,
            name,
            cleanName,
            'Hungarian notation (prefixes like str, int, dt) is discouraged in modern SQL. ' +
              'Use descriptive names that convey meaning, not data type (e.g., CustomerName, not strCustomerName).'
          )
        );
      }
    }

    return results;
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Remove Hungarian notation prefixes',
      before: 'DECLARE @strCustomerName NVARCHAR(100);\nDECLARE @intOrderCount INT;\nDECLARE @dtOrderDate DATETIME;',
      after: 'DECLARE @customerName NVARCHAR(100);\nDECLARE @orderCount INT;\nDECLARE @orderDate DATETIME;',
      explanation: 'Descriptive names are more readable than type-prefixed names.',
      estimatedImpact: 'Low',
      autoFixAvailable: false,
    };
  }
}

/**
 * Export all naming rules
 */
export const namingRules = [
  new TableNamingConventionRule(),
  new ColumnNamingConventionRule(),
  new ProcedureNamingConventionRule(),
  new VariableNamingConventionRule(),
  new HungarianNotationRule(),
];
