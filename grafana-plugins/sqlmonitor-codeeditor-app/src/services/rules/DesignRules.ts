/**
 * Design Rules (D001-D005)
 *
 * Rules that detect database design issues and best practices violations.
 */

import { BaseRule } from './RuleBase';
import type { AnalysisResult, FixSuggestion } from '../../types/analysis';

/**
 * D001: Missing primary key
 * Detects CREATE TABLE without PRIMARY KEY constraint
 */
export class MissingPrimaryKeyRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'D001',
      severity: 'Warning',
      category: 'Design',
      message: 'Table missing PRIMARY KEY constraint',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];

    // Match CREATE TABLE statements
    const createTablePattern = /CREATE\s+TABLE\s+(?:\[?\w+\]?\.)?((\[?\w+\]?))\s*\(([\s\S]*?)\)/gi;
    const matches = code.matchAll(createTablePattern);

    for (const match of matches) {
      const tableName = match[1];
      const tableBody = match[3];

      // Check if PRIMARY KEY constraint exists
      if (!/PRIMARY\s+KEY/i.test(tableBody)) {
        const lineNumber = code.substring(0, match.index).split('\n').length;
        const columnNumber = match.index! - code.substring(0, match.index).lastIndexOf('\n');

        results.push({
          ruleId: this.ruleId,
          severity: this.severity,
          category: this.category,
          message: `Table ${tableName} missing PRIMARY KEY constraint`,
          line: lineNumber,
          column: columnNumber,
          before: null,
          after: null,
          explanation:
            'Every table should have a PRIMARY KEY to uniquely identify rows. ' +
            'Without a primary key, you cannot establish foreign key relationships or use certain replication features.',
        });
      }
    }

    return results;
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Add PRIMARY KEY constraint',
      before: 'CREATE TABLE Customers (\n  CustomerID INT,\n  Name NVARCHAR(100)\n)',
      after:
        'CREATE TABLE Customers (\n  CustomerID INT PRIMARY KEY,\n  Name NVARCHAR(100)\n)\n-- or:\nALTER TABLE Customers ADD CONSTRAINT PK_Customers PRIMARY KEY (CustomerID)',
      explanation: 'Add PRIMARY KEY constraint to ensure row uniqueness and enable foreign key relationships.',
      estimatedImpact: 'High',
      autoFixAvailable: false,
    };
  }
}

/**
 * D002: Missing foreign key constraint
 * Detects columns that appear to be foreign keys but lack FK constraints
 */
export class MissingForeignKeyRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'D002',
      severity: 'Info',
      category: 'Design',
      message: 'Consider adding FOREIGN KEY constraint for referential integrity',
      enabled: false, // Disabled by default (can have false positives)
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];

    // Match column definitions that end with "ID" but no FK constraint nearby
    const pattern = /(\w+ID)\s+(INT|BIGINT|UNIQUEIDENTIFIER)/gi;
    const matches = this.findMatches(code, pattern);

    for (const match of matches) {
      // Check if FOREIGN KEY or REFERENCES is mentioned nearby
      const context = this.getCodeSnippet(code, match.line - 1, 10);
      if (!/FOREIGN\s+KEY|REFERENCES/i.test(context)) {
        results.push(
          this.createResult(
            match,
            match.match,
            null,
            'Columns ending with "ID" often reference other tables. ' +
              'Consider adding FOREIGN KEY constraints to enforce referential integrity.'
          )
        );
      }
    }

    return results;
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Add FOREIGN KEY constraint',
      before: 'CREATE TABLE Orders (\n  OrderID INT PRIMARY KEY,\n  CustomerID INT\n)',
      after:
        'CREATE TABLE Orders (\n  OrderID INT PRIMARY KEY,\n  CustomerID INT,\n  CONSTRAINT FK_Orders_Customers FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID)\n)',
      explanation: 'Foreign key constraints prevent orphaned records and maintain data integrity.',
      estimatedImpact: 'Medium',
      autoFixAvailable: false,
    };
  }
}

/**
 * D003: VARCHAR without explicit length
 * Detects VARCHAR(MAX) or VARCHAR without length specification
 */
export class VarcharWithoutLengthRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'D003',
      severity: 'Warning',
      category: 'Design',
      message: 'VARCHAR without explicit length - specify appropriate length',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];

    // Match VARCHAR without parentheses (implicit length) - not valid in SQL Server, but check anyway
    // Also warn on VARCHAR(MAX) for columns that likely don't need MAX
    const pattern = /\b(N?VARCHAR)\s*(\(MAX\))?(?!\s*\()/gi;
    const matches = this.findMatches(code, pattern);

    for (const match of matches) {
      if (this.isInComment(code, match.line - 1, match.column - 1)) {
        continue;
      }

      // Check if it's VARCHAR(MAX) in a column definition (not parameter)
      const lineText = match.fullLineText || '';
      const isColumnDef = /CREATE\s+TABLE|ALTER\s+TABLE|ADD\s+COLUMN/i.test(
        this.getCodeSnippet(code, match.line - 1, 3)
      );

      if (match.match.includes('MAX') && isColumnDef) {
        results.push(
          this.createResult(
            match,
            match.match,
            'VARCHAR(100)',
            'VARCHAR(MAX) can cause performance issues and prevents effective indexing. ' +
              'Use an explicit length that matches your data requirements (e.g., VARCHAR(100), VARCHAR(500)).'
          )
        );
      }
    }

    return results;
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Specify explicit VARCHAR length',
      before: 'CREATE TABLE Products (\n  ProductName VARCHAR(MAX)\n)',
      after: 'CREATE TABLE Products (\n  ProductName VARCHAR(200)\n)',
      explanation:
        'Use VARCHAR(MAX) only for truly large text (>8000 bytes). For typical string columns, use explicit lengths.',
      estimatedImpact: 'Medium',
      autoFixAvailable: false,
    };
  }
}

/**
 * D004: FLOAT/REAL instead of DECIMAL
 * Detects FLOAT or REAL for monetary or precise numeric values
 */
export class FloatInsteadOfDecimalRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'D004',
      severity: 'Warning',
      category: 'Design',
      message: 'Avoid FLOAT/REAL for monetary values - use DECIMAL/NUMERIC',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];

    // Match columns with FLOAT or REAL that might be monetary
    const pattern =
      /(\w*(?:price|cost|amount|total|balance|salary|revenue|profit|fee|rate)\w*)\s+(FLOAT|REAL)/gi;
    const matches = this.findMatches(code, pattern);

    for (const match of matches) {
      if (this.isInComment(code, match.line - 1, match.column - 1)) {
        continue;
      }

      results.push(
        this.createResult(
          match,
          match.match,
          match.match.replace(/FLOAT|REAL/gi, 'DECIMAL(19, 4)'),
          'FLOAT and REAL are approximate numeric types that can cause rounding errors. ' +
            'For monetary values or precise calculations, use DECIMAL or NUMERIC with explicit precision.'
        )
      );
    }

    return results;
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Replace FLOAT with DECIMAL',
      before: 'CREATE TABLE Orders (\n  TotalPrice FLOAT\n)',
      after: 'CREATE TABLE Orders (\n  TotalPrice DECIMAL(19, 4)\n)',
      explanation:
        'DECIMAL provides exact precision for monetary values. FLOAT can introduce rounding errors (e.g., 1.10 may be stored as 1.0999999).',
      estimatedImpact: 'High',
      autoFixAvailable: true,
    };
  }
}

/**
 * D005: Missing index on foreign key columns
 * Detects foreign key columns without supporting indexes
 */
export class MissingIndexOnForeignKeyRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'D005',
      severity: 'Warning',
      category: 'Design',
      message: 'Foreign key column missing supporting index',
      enabled: false, // Disabled by default (requires context analysis)
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];

    // Match FOREIGN KEY constraints
    const fkPattern =
      /CONSTRAINT\s+(\w+)\s+FOREIGN\s+KEY\s*\(([^)]+)\)\s+REFERENCES\s+(\w+)\s*\(([^)]+)\)/gi;
    const matches = code.matchAll(fkPattern);

    for (const match of matches) {
      const constraintName = match[1];
      const fkColumn = match[2].trim();
      const refTable = match[3];

      // Check if there's a CREATE INDEX statement for this column
      const indexPattern = new RegExp(
        `CREATE\\s+(?:UNIQUE\\s+)?(?:CLUSTERED\\s+)?(?:NONCLUSTERED\\s+)?INDEX\\s+\\w+\\s+ON\\s+\\w+\\s*\\([^)]*\\b${this.escapeRegex(
          fkColumn
        )}\\b`,
        'i'
      );

      if (!indexPattern.test(code)) {
        const lineNumber = code.substring(0, match.index).split('\n').length;
        const columnNumber = match.index! - code.substring(0, match.index).lastIndexOf('\n');

        results.push({
          ruleId: this.ruleId,
          severity: this.severity,
          category: this.category,
          message: `Foreign key column "${fkColumn}" missing supporting index`,
          line: lineNumber,
          column: columnNumber,
          before: null,
          after: `CREATE NONCLUSTERED INDEX IX_TableName_${fkColumn} ON TableName (${fkColumn})`,
          explanation:
            'Foreign key columns should have supporting indexes to improve JOIN performance and prevent blocking during updates/deletes on the referenced table.',
        });
      }
    }

    return results;
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Create index on foreign key column',
      before:
        'CREATE TABLE Orders (\n  OrderID INT PRIMARY KEY,\n  CustomerID INT,\n  CONSTRAINT FK_Orders_Customers FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID)\n)',
      after:
        'CREATE TABLE Orders (\n  OrderID INT PRIMARY KEY,\n  CustomerID INT,\n  CONSTRAINT FK_Orders_Customers FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID)\n);\nCREATE NONCLUSTERED INDEX IX_Orders_CustomerID ON Orders (CustomerID);',
      explanation:
        'Indexes on foreign key columns significantly improve JOIN performance and prevent blocking during cascading operations.',
      estimatedImpact: 'High',
      autoFixAvailable: false,
    };
  }
}

/**
 * Export all design rules
 */
export const designRules = [
  new MissingPrimaryKeyRule(),
  new MissingForeignKeyRule(),
  new VarcharWithoutLengthRule(),
  new FloatInsteadOfDecimalRule(),
  new MissingIndexOnForeignKeyRule(),
];
