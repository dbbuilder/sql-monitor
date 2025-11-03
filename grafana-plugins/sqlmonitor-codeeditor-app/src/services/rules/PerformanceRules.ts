/**
 * Performance Rules (P001-P010)
 *
 * Rules that detect performance issues in T-SQL code.
 */

import { BaseRule } from './RuleBase';
import type { AnalysisResult, FixSuggestion } from '../../types/analysis';

/**
 * P001: SELECT * usage
 * Detects SELECT * which can cause performance issues
 */
export class SelectStarRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'P001',
      severity: 'Warning',
      category: 'Performance',
      message: 'Avoid SELECT * - specify column names explicitly',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    const pattern = /SELECT\s+\*/gi;
    const matches = this.findMatches(code, pattern);

    for (const match of matches) {
      // Skip if inside comment or string
      if (this.isInComment(code, match.line - 1, match.column - 1) ||
          this.isInString(code, match.line - 1, match.column - 1)) {
        continue;
      }

      results.push(
        this.createResult(
          match,
          match.match,
          'SELECT Column1, Column2, Column3',
          'SELECT * retrieves all columns which can lead to unnecessary data transfer and memory usage. ' +
          'Explicitly list only the columns you need.'
        )
      );
    }

    return results;
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Replace SELECT * with explicit column list',
      before: 'SELECT * FROM Customers',
      after: 'SELECT CustomerID, FirstName, LastName, Email FROM Customers',
      explanation: 'Listing columns explicitly improves query performance and prevents breaking changes when table schema changes.',
      estimatedImpact: 'Medium',
      autoFixAvailable: false,
    };
  }
}

/**
 * P002: Missing WHERE clause in UPDATE/DELETE
 * Detects UPDATE/DELETE without WHERE which can affect all rows
 */
export class MissingWhereClauseRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'P002',
      severity: 'Error',
      category: 'Performance',
      message: 'UPDATE/DELETE without WHERE clause affects all rows',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];

    // Match UPDATE without WHERE
    const updatePattern = /UPDATE\s+(?:\[?\w+\]?\.)?(?:\[?\w+\]?\.)?(\[?\w+\]?)\s+SET\s+[^;]*?(?=;|\bGO\b|$)/gis;
    const updateMatches = code.matchAll(updatePattern);

    for (const match of updateMatches) {
      if (!match[0].match(/\bWHERE\b/i)) {
        const lineNumber = code.substring(0, match.index).split('\n').length;
        const columnNumber = match.index! - code.substring(0, match.index).lastIndexOf('\n');

        results.push({
          ruleId: this.ruleId,
          severity: this.severity,
          category: this.category,
          message: 'UPDATE without WHERE clause will affect all rows in the table',
          line: lineNumber,
          column: columnNumber,
          before: match[0],
          after: match[0] + ' WHERE <condition>',
          explanation: 'Always include a WHERE clause in UPDATE statements to avoid unintentionally modifying all rows.',
        });
      }
    }

    // Match DELETE without WHERE
    const deletePattern = /DELETE\s+(?:FROM\s+)?(?:\[?\w+\]?\.)?(?:\[?\w+\]?\.)?(\[?\w+\]?)\s*(?=;|\bGO\b|$)/gis;
    const deleteMatches = code.matchAll(deletePattern);

    for (const match of deleteMatches) {
      if (!match[0].match(/\bWHERE\b/i)) {
        const lineNumber = code.substring(0, match.index).split('\n').length;
        const columnNumber = match.index! - code.substring(0, match.index).lastIndexOf('\n');

        results.push({
          ruleId: this.ruleId,
          severity: this.severity,
          category: this.category,
          message: 'DELETE without WHERE clause will delete all rows in the table',
          line: lineNumber,
          column: columnNumber,
          before: match[0],
          after: match[0] + ' WHERE <condition>',
          explanation: 'Always include a WHERE clause in DELETE statements to avoid unintentionally deleting all rows.',
        });
      }
    }

    return results;
  }
}

/**
 * P003: LIKE with leading wildcard
 * Detects LIKE patterns starting with % which prevents index usage
 */
export class LeadingWildcardRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'P003',
      severity: 'Warning',
      category: 'Performance',
      message: 'LIKE with leading wildcard (%) prevents index usage',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    const pattern = /LIKE\s+N?'%/gi;
    const matches = this.findMatches(code, pattern);

    for (const match of matches) {
      if (this.isInComment(code, match.line - 1, match.column - 1)) {
        continue;
      }

      results.push(
        this.createResult(
          match,
          match.match,
          "LIKE 'SearchTerm%'",
          'Leading wildcards in LIKE patterns force full table scans. ' +
          'If possible, move the wildcard to the end or use full-text search for substring matching.'
        )
      );
    }

    return results;
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Move wildcard to end or use full-text search',
      before: "WHERE Name LIKE '%Smith'",
      after: "WHERE Name LIKE 'Smith%'  -- or use CONTAINS(Name, 'Smith') for full-text search",
      explanation: 'Leading wildcards prevent index seeks. Trailing wildcards can use indexes.',
      estimatedImpact: 'High',
      autoFixAvailable: false,
    };
  }
}

/**
 * P004: DISTINCT usage
 * Detects DISTINCT which can be expensive
 */
export class DistinctUsageRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'P004',
      severity: 'Info',
      category: 'Performance',
      message: 'DISTINCT can be expensive - ensure it is necessary',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    const pattern = /SELECT\s+DISTINCT\b/gi;
    const matches = this.findMatches(code, pattern);

    for (const match of matches) {
      if (this.isInComment(code, match.line - 1, match.column - 1) ||
          this.isInString(code, match.line - 1, match.column - 1)) {
        continue;
      }

      results.push(
        this.createResult(
          match,
          match.match,
          null,
          'DISTINCT requires sorting and deduplication which can be expensive. ' +
          'Ensure duplicates need to be removed and consider if the query can be rewritten to avoid DISTINCT.'
        )
      );
    }

    return results;
  }
}

/**
 * P005: OR in WHERE clause
 * Detects OR conditions which can prevent index usage
 */
export class OrInWhereClauseRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'P005',
      severity: 'Warning',
      category: 'Performance',
      message: 'OR in WHERE clause can prevent index usage',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    // Match OR in WHERE clause (simplified - may have false positives)
    const pattern = /WHERE\s+[^;]*?\bOR\b/gis;
    const matches = code.matchAll(pattern);

    for (const match of matches) {
      const lineNumber = code.substring(0, match.index).split('\n').length;
      const columnNumber = match.index! - code.substring(0, match.index).lastIndexOf('\n');

      results.push({
        ruleId: this.ruleId,
        severity: this.severity,
        category: this.category,
        message: this.message,
        line: lineNumber,
        column: columnNumber,
        before: match[0],
        after: 'WHERE Column IN (Value1, Value2)  -- or use UNION',
        explanation: 'OR conditions can prevent index usage. Consider using IN clause or UNION instead.',
      });
    }

    return results;
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Replace OR with IN or UNION',
      before: "WHERE Status = 'Active' OR Status = 'Pending'",
      after: "WHERE Status IN ('Active', 'Pending')",
      explanation: 'IN clauses can use indexes more effectively than OR conditions.',
      estimatedImpact: 'Medium',
      autoFixAvailable: false,
    };
  }
}

/**
 * P006: Function on indexed column in WHERE
 * Detects functions applied to columns in WHERE clause
 */
export class FunctionOnIndexedColumnRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'P006',
      severity: 'Warning',
      category: 'Performance',
      message: 'Function on column in WHERE clause prevents index usage',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    // Match common functions on columns in WHERE
    const pattern = /WHERE\s+[^;]*?\b(?:UPPER|LOWER|LTRIM|RTRIM|SUBSTRING|LEFT|RIGHT|DATEPART|YEAR|MONTH|DAY|CAST|CONVERT)\s*\([^)]*?\b\w+\b[^)]*?\)\s*=/gis;
    const matches = code.matchAll(pattern);

    for (const match of matches) {
      const lineNumber = code.substring(0, match.index).split('\n').length;
      const columnNumber = match.index! - code.substring(0, match.index).lastIndexOf('\n');

      results.push({
        ruleId: this.ruleId,
        severity: this.severity,
        category: this.category,
        message: this.message,
        line: lineNumber,
        column: columnNumber,
        before: match[0],
        after: null,
        explanation: 'Applying functions to columns in WHERE clause prevents index usage. ' +
                     'Apply the function to the comparison value instead, or use computed columns with indexes.',
      });
    }

    return results;
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Apply function to comparison value instead',
      before: "WHERE UPPER(Name) = 'SMITH'",
      after: "WHERE Name = 'Smith'  -- or use case-insensitive collation",
      explanation: 'Functions on indexed columns force table scans. Apply functions to the search value instead.',
      estimatedImpact: 'High',
      autoFixAvailable: false,
    };
  }
}

/**
 * P007: NOT IN usage
 * Detects NOT IN which can be slow
 */
export class NotInUsageRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'P007',
      severity: 'Warning',
      category: 'Performance',
      message: 'NOT IN can be slow - consider NOT EXISTS or LEFT JOIN',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    const pattern = /\bNOT\s+IN\s*\(/gi;
    const matches = this.findMatches(code, pattern);

    for (const match of matches) {
      if (this.isInComment(code, match.line - 1, match.column - 1)) {
        continue;
      }

      results.push(
        this.createResult(
          match,
          match.match,
          'NOT EXISTS (SELECT 1 FROM ...)',
          'NOT IN can be inefficient, especially with subqueries. ' +
          'Consider using NOT EXISTS or LEFT JOIN with NULL check instead.'
        )
      );
    }

    return results;
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Replace NOT IN with NOT EXISTS',
      before: "WHERE CustomerID NOT IN (SELECT CustomerID FROM Orders)",
      after: "WHERE NOT EXISTS (SELECT 1 FROM Orders WHERE Orders.CustomerID = Customers.CustomerID)",
      explanation: 'NOT EXISTS can short-circuit and is generally faster than NOT IN.',
      estimatedImpact: 'Medium',
      autoFixAvailable: false,
    };
  }
}

/**
 * P008: UNION without ALL
 * Detects UNION which performs deduplication
 */
export class UnionWithoutAllRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'P008',
      severity: 'Info',
      category: 'Performance',
      message: 'UNION performs deduplication - use UNION ALL if duplicates are acceptable',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    // Match UNION without ALL
    const pattern = /\bUNION\s+(?!ALL\b)/gi;
    const matches = this.findMatches(code, pattern);

    for (const match of matches) {
      if (this.isInComment(code, match.line - 1, match.column - 1)) {
        continue;
      }

      results.push(
        this.createResult(
          match,
          match.match,
          'UNION ALL',
          'UNION without ALL performs DISTINCT which adds overhead. ' +
          'If duplicates are not a concern, use UNION ALL for better performance.'
        )
      );
    }

    return results;
  }
}

/**
 * P009: Missing NOLOCK hint
 * Detects queries without NOLOCK in read-heavy scenarios
 */
export class MissingNolockRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'P009',
      severity: 'Info',
      category: 'Performance',
      message: 'Consider NOLOCK hint for read-only queries to avoid blocking',
      enabled: false, // Disabled by default (controversial)
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    // Match SELECT FROM without WITH (NOLOCK)
    const pattern = /SELECT\s+[^;]*?FROM\s+(\[?\w+\]?\.)?(\[?\w+\]?\.)?(\[?\w+\]?)(?!\s+WITH\s*\(\s*NOLOCK\s*\))/gis;
    const matches = code.matchAll(pattern);

    for (const match of matches) {
      const lineNumber = code.substring(0, match.index).split('\n').length;
      const columnNumber = match.index! - code.substring(0, match.index).lastIndexOf('\n');

      results.push({
        ruleId: this.ruleId,
        severity: this.severity,
        category: this.category,
        message: this.message,
        line: lineNumber,
        column: columnNumber,
        before: match[0],
        after: match[0] + ' WITH (NOLOCK)',
        explanation: 'NOLOCK hint allows dirty reads but prevents read queries from blocking writes. ' +
                     'Only use in scenarios where slightly stale data is acceptable.',
      });
    }

    return results;
  }
}

/**
 * P010: Implicit conversion in WHERE
 * Detects potential implicit conversions
 */
export class ImplicitConversionRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'P010',
      severity: 'Warning',
      category: 'Performance',
      message: 'Potential implicit conversion - ensure data types match',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    // Detect INT/VARCHAR comparisons (simplified)
    const pattern = /WHERE\s+(\w+)\s*=\s*'(\d+)'/gi;
    const matches = this.findMatches(code, pattern);

    for (const match of matches) {
      if (this.isInComment(code, match.line - 1, match.column - 1)) {
        continue;
      }

      results.push(
        this.createResult(
          match,
          match.match,
          null,
          'Comparing different data types can cause implicit conversions which prevent index usage. ' +
          'Ensure WHERE clause values match the column data type.'
        )
      );
    }

    return results;
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Match data types in comparisons',
      before: "WHERE CustomerID = '123'  -- CustomerID is INT",
      after: "WHERE CustomerID = 123",
      explanation: 'Implicit conversions prevent index seeks. Always match the column data type.',
      estimatedImpact: 'High',
      autoFixAvailable: false,
    };
  }
}

/**
 * Export all performance rules
 */
export const performanceRules = [
  new SelectStarRule(),
  new MissingWhereClauseRule(),
  new LeadingWildcardRule(),
  new DistinctUsageRule(),
  new OrInWhereClauseRule(),
  new FunctionOnIndexedColumnRule(),
  new NotInUsageRule(),
  new UnionWithoutAllRule(),
  new MissingNolockRule(),
  new ImplicitConversionRule(),
];
