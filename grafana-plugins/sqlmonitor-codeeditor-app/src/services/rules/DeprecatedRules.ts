/**
 * Deprecated Rules (DP001-DP008)
 *
 * Rules that detect usage of deprecated T-SQL features.
 */

import { BaseRule } from './RuleBase';
import type { AnalysisResult, FixSuggestion } from '../../types/analysis';

/**
 * DP001: Text/NText usage
 * Detects deprecated TEXT/NTEXT data types
 */
export class TextNTextUsageRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'DP001',
      severity: 'Warning',
      category: 'Deprecated',
      message: 'TEXT/NTEXT data types are deprecated - use VARCHAR(MAX)/NVARCHAR(MAX)',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    const pattern = /\b(TEXT|NTEXT|IMAGE)\b/gi;
    const matches = this.findMatches(code, pattern);

    for (const match of matches) {
      if (this.isInComment(code, match.line - 1, match.column - 1)) {
        continue;
      }

      const replacement = match.match.toUpperCase() === 'TEXT' ? 'VARCHAR(MAX)' :
                          match.match.toUpperCase() === 'NTEXT' ? 'NVARCHAR(MAX)' :
                          'VARBINARY(MAX)';

      results.push(
        this.createResult(
          match,
          match.match,
          replacement,
          `${match.match.toUpperCase()} is deprecated since SQL Server 2005. ` +
          `Use ${replacement} instead for better performance and compatibility.`
        )
      );
    }

    return results;
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Replace deprecated data type',
      before: 'CREATE TABLE Documents (Content TEXT)',
      after: 'CREATE TABLE Documents (Content VARCHAR(MAX))',
      explanation: 'VARCHAR(MAX) provides better performance and is supported by all modern features.',
      estimatedImpact: 'Low',
      autoFixAvailable: true,
    };
  }
}

/**
 * DP002: RAISERROR with old syntax
 * Detects old RAISERROR syntax instead of THROW
 */
export class RaiserrorOldSyntaxRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'DP002',
      severity: 'Info',
      category: 'Deprecated',
      message: 'Consider using THROW instead of RAISERROR for SQL Server 2012+',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    const pattern = /\bRAISERROR\s*\(/gi;
    const matches = this.findMatches(code, pattern);

    for (const match of matches) {
      if (this.isInComment(code, match.line - 1, match.column - 1)) {
        continue;
      }

      results.push(
        this.createResult(
          match,
          match.match,
          'THROW',
          'THROW (introduced in SQL Server 2012) is simpler and preferred over RAISERROR for new code.'
        )
      );
    }

    return results;
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Replace RAISERROR with THROW',
      before: "RAISERROR('Error message', 16, 1)",
      after: "THROW 50000, 'Error message', 1",
      explanation: 'THROW is simpler and automatically includes line numbers in error messages.',
      estimatedImpact: 'Low',
      autoFixAvailable: false,
    };
  }
}

/**
 * DP003: Old-style JOINs
 * Detects old SQL-89 join syntax
 */
export class OldStyleJoinRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'DP003',
      severity: 'Warning',
      category: 'Deprecated',
      message: 'Use ANSI SQL-92 JOIN syntax instead of old comma-separated joins',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    // Match comma-separated tables with WHERE clause conditions
    const pattern = /FROM\s+(\w+)\s*,\s*(\w+)/gi;
    const matches = this.findMatches(code, pattern);

    for (const match of matches) {
      if (this.isInComment(code, match.line - 1, match.column - 1)) {
        continue;
      }

      results.push(
        this.createResult(
          match,
          match.match,
          'FROM Table1 INNER JOIN Table2 ON ...',
          'Old-style comma joins are deprecated and harder to read. Use explicit JOIN syntax.'
        )
      );
    }

    return results;
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Convert to ANSI JOIN syntax',
      before: 'FROM Customers c, Orders o WHERE c.CustomerID = o.CustomerID',
      after: 'FROM Customers c INNER JOIN Orders o ON c.CustomerID = o.CustomerID',
      explanation: 'ANSI JOIN syntax is more readable and separates join conditions from filter conditions.',
      estimatedImpact: 'Low',
      autoFixAvailable: false,
    };
  }
}

/**
 * DP004: TIMESTAMP data type
 * Detects deprecated TIMESTAMP usage
 */
export class TimestampUsageRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'DP004',
      severity: 'Warning',
      category: 'Deprecated',
      message: 'TIMESTAMP is deprecated - use ROWVERSION',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    const pattern = /\bTIMESTAMP\b/gi;
    const matches = this.findMatches(code, pattern);

    for (const match of matches) {
      if (this.isInComment(code, match.line - 1, match.column - 1)) {
        continue;
      }

      results.push(
        this.createResult(
          match,
          'TIMESTAMP',
          'ROWVERSION',
          'TIMESTAMP is deprecated. Use ROWVERSION for the same functionality with clearer naming.'
        )
      );
    }

    return results;
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Replace TIMESTAMP with ROWVERSION',
      before: 'CREATE TABLE MyTable (RowVer TIMESTAMP)',
      after: 'CREATE TABLE MyTable (RowVer ROWVERSION)',
      explanation: 'ROWVERSION is the preferred name and avoids confusion with datetime timestamps.',
      estimatedImpact: 'Low',
      autoFixAvailable: true,
    };
  }
}

/**
 * DP005: SET ROWCOUNT
 * Detects deprecated SET ROWCOUNT usage
 */
export class SetRowcountRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'DP005',
      severity: 'Warning',
      category: 'Deprecated',
      message: 'SET ROWCOUNT is deprecated - use TOP instead',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    const pattern = /\bSET\s+ROWCOUNT\b/gi;
    const matches = this.findMatches(code, pattern);

    for (const match of matches) {
      if (this.isInComment(code, match.line - 1, match.column - 1)) {
        continue;
      }

      results.push(
        this.createResult(
          match,
          match.match,
          'SELECT TOP (n)',
          'SET ROWCOUNT is deprecated. Use TOP clause in SELECT statements instead.'
        )
      );
    }

    return results;
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Replace SET ROWCOUNT with TOP',
      before: 'SET ROWCOUNT 10;\nSELECT * FROM Customers;',
      after: 'SELECT TOP (10) * FROM Customers;',
      explanation: 'TOP is more explicit and works better with query optimization.',
      estimatedImpact: 'Low',
      autoFixAvailable: false,
    };
  }
}

/**
 * DP006: sp_ prefix for stored procedures
 * Detects sp_ prefix which SQL Server checks in master database first
 */
export class SpPrefixRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'DP006',
      severity: 'Warning',
      category: 'Deprecated',
      message: 'Avoid sp_ prefix for user stored procedures (causes master database lookup)',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    const pattern = /CREATE\s+PROCEDURE\s+(?:\[?dbo\]?\.)?(\[?sp_\w+\]?)/gi;
    const matches = this.findMatches(code, pattern);

    for (const match of matches) {
      results.push(
        this.createResult(
          match,
          match.match,
          match.match.replace(/sp_/gi, 'usp_'),
          'sp_ prefix is reserved for system stored procedures and causes performance overhead. Use usp_ prefix instead.'
        )
      );
    }

    return results;
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Replace sp_ with usp_ prefix',
      before: 'CREATE PROCEDURE sp_GetCustomers',
      after: 'CREATE PROCEDURE usp_GetCustomers',
      explanation: 'SQL Server checks master database first for sp_ procedures, causing extra overhead.',
      estimatedImpact: 'Low',
      autoFixAvailable: true,
    };
  }
}

/**
 * DP007: @@ERROR usage
 * Detects old @@ERROR instead of TRY...CATCH
 */
export class ErrorUsageRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'DP007',
      severity: 'Info',
      category: 'Deprecated',
      message: 'Consider TRY...CATCH instead of @@ERROR for SQL Server 2005+',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    const pattern = /@@ERROR/gi;
    const matches = this.findMatches(code, pattern);

    for (const match of matches) {
      if (this.isInComment(code, match.line - 1, match.column - 1)) {
        continue;
      }

      results.push(
        this.createResult(
          match,
          match.match,
          'TRY...CATCH',
          'TRY...CATCH provides better error handling than @@ERROR and is the modern approach.'
        )
      );
    }

    return results;
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Use TRY...CATCH for error handling',
      before: `IF @@ERROR <> 0\n  PRINT 'Error occurred'`,
      after: `BEGIN TRY\n  -- code\nEND TRY\nBEGIN CATCH\n  PRINT ERROR_MESSAGE()\nEND CATCH`,
      explanation: 'TRY...CATCH is more robust and provides better error information.',
      estimatedImpact: 'Low',
      autoFixAvailable: false,
    };
  }
}

/**
 * DP008: Table hints without WITH
 * Detects old table hint syntax without WITH keyword
 */
export class TableHintsWithoutWithRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'DP008',
      severity: 'Warning',
      category: 'Deprecated',
      message: 'Use WITH keyword for table hints (SQL Server 2008+ requirement)',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    // Match table hints without WITH
    const pattern = /FROM\s+\w+\s+(NOLOCK|ROWLOCK|UPDLOCK|HOLDLOCK|READPAST)/gi;
    const matches = this.findMatches(code, pattern);

    for (const match of matches) {
      if (this.isInComment(code, match.line - 1, match.column - 1)) {
        continue;
      }

      results.push(
        this.createResult(
          match,
          match.match,
          match.match.replace(/(\w+)\s+(NOLOCK|ROWLOCK|UPDLOCK|HOLDLOCK|READPAST)/i, '$1 WITH ($2)'),
          'Table hints must use WITH keyword in SQL Server 2008+.'
        )
      );
    }

    return results;
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Add WITH keyword for table hints',
      before: 'FROM Customers NOLOCK',
      after: 'FROM Customers WITH (NOLOCK)',
      explanation: 'WITH keyword is required for forward compatibility.',
      estimatedImpact: 'Low',
      autoFixAvailable: true,
    };
  }
}

/**
 * Export all deprecated rules
 */
export const deprecatedRules = [
  new TextNTextUsageRule(),
  new RaiserrorOldSyntaxRule(),
  new OldStyleJoinRule(),
  new TimestampUsageRule(),
  new SetRowcountRule(),
  new SpPrefixRule(),
  new ErrorUsageRule(),
  new TableHintsWithoutWithRule(),
];
