/**
 * Code Smell Rules (C001-C008)
 *
 * Rules that detect code quality issues and anti-patterns.
 */

import { BaseRule } from './RuleBase';
import type { AnalysisResult } from '../../types/analysis';

/**
 * C001: Too many columns in SELECT
 * Detects SELECT statements with excessive columns
 */
export class TooManyColumnsRule extends BaseRule {
  private maxColumns = 20;

  constructor() {
    super({
      ruleId: 'C001',
      severity: 'Info',
      category: 'CodeSmell',
      message: 'SELECT statement has many columns - consider if all are necessary',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    // Match SELECT ... FROM (simplified - may have false positives)
    const pattern = /SELECT\s+(.*?)\s+FROM/gis;
    const matches = code.matchAll(pattern);

    for (const match of matches) {
      const columnList = match[1];
      // Count commas as a proxy for column count
      const columnCount = (columnList.match(/,/g) || []).length + 1;

      if (columnCount > this.maxColumns) {
        const lineNumber = code.substring(0, match.index).split('\n').length;
        const columnNumber = match.index! - code.substring(0, match.index).lastIndexOf('\n');

        results.push({
          ruleId: this.ruleId,
          severity: this.severity,
          category: this.category,
          message: `SELECT statement has ${columnCount} columns - consider if all are necessary`,
          line: lineNumber,
          column: columnNumber,
          before: null,
          after: null,
          explanation: 'Selecting many columns can impact performance and maintainability. ' +
                       'Consider if all columns are needed or if multiple queries would be clearer.',
        });
      }
    }

    return results;
  }
}

/**
 * C002: Long procedure/function
 * Detects procedures/functions with excessive lines
 */
export class LongProcedureRule extends BaseRule {
  private maxLines = 300;

  constructor() {
    super({
      ruleId: 'C002',
      severity: 'Warning',
      category: 'CodeSmell',
      message: 'Procedure/function is very long - consider refactoring',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    const lineCount = code.split('\n').length;

    if (lineCount > this.maxLines && this.isApplicableToCode(code, 'procedure')) {
      const objectName = this.getObjectName(code);
      results.push({
        ruleId: this.ruleId,
        severity: this.severity,
        category: this.category,
        message: `Procedure ${objectName || 'unknown'} has ${lineCount} lines - consider refactoring into smaller procedures`,
        line: 1,
        column: 1,
        before: null,
        after: null,
        explanation: 'Long procedures are hard to maintain and test. Consider breaking into smaller, focused procedures.',
      });
    }

    return results;
  }
}

/**
 * C003: Deep nesting
 * Detects deeply nested IF/BEGIN blocks
 */
export class DeepNestingRule extends BaseRule {
  private maxNestingLevel = 4;

  constructor() {
    super({
      ruleId: 'C003',
      severity: 'Warning',
      category: 'CodeSmell',
      message: 'Deep nesting detected - consider early returns or refactoring',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    const lines = code.split('\n');
    let currentLevel = 0;
    let maxLevelLine = 0;
    let maxLevel = 0;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];

      // Increment level on BEGIN
      if (/\bBEGIN\b/i.test(line)) {
        currentLevel++;
        if (currentLevel > maxLevel) {
          maxLevel = currentLevel;
          maxLevelLine = i + 1;
        }
      }

      // Decrement level on END
      if (/\bEND\b/i.test(line)) {
        currentLevel--;
      }
    }

    if (maxLevel > this.maxNestingLevel) {
      results.push({
        ruleId: this.ruleId,
        severity: this.severity,
        category: this.category,
        message: `Nesting level ${maxLevel} exceeds recommended maximum of ${this.maxNestingLevel}`,
        line: maxLevelLine,
        column: 1,
        before: null,
        after: null,
        explanation: 'Deep nesting makes code hard to read. Use early returns, guard clauses, or extract logic into separate procedures.',
      });
    }

    return results;
  }
}

/**
 * C004: Magic numbers
 * Detects numeric literals that should be constants
 */
export class MagicNumbersRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'C004',
      severity: 'Info',
      category: 'CodeSmell',
      message: 'Consider declaring magic numbers as named constants',
      enabled: false, // Disabled by default (can have many false positives)
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    // Match numeric literals (exclude 0, 1, -1)
    const pattern = /(?<![0-9])\b(?!-?[01]\b)-?\d{2,}\b/g;
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
          'DECLARE @MaxRetries INT = ' + match.match,
          'Magic numbers reduce code readability. Declare them as named constants.'
        )
      );
    }

    return results;
  }
}

/**
 * C005: Commented-out code
 * Detects large blocks of commented code
 */
export class CommentedCodeRule extends BaseRule {
  private minCommentedLines = 5;

  constructor() {
    super({
      ruleId: 'C005',
      severity: 'Info',
      category: 'CodeSmell',
      message: 'Remove commented-out code - use version control instead',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    const lines = code.split('\n');
    let consecutiveComments = 0;
    let commentStartLine = 0;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();

      if (line.startsWith('--')) {
        if (consecutiveComments === 0) {
          commentStartLine = i + 1;
        }
        consecutiveComments++;
      } else {
        if (consecutiveComments >= this.minCommentedLines) {
          results.push({
            ruleId: this.ruleId,
            severity: this.severity,
            category: this.category,
            message: `${consecutiveComments} consecutive commented lines detected`,
            line: commentStartLine,
            column: 1,
            before: null,
            after: null,
            explanation: 'Large blocks of commented code clutter the codebase. Remove them and rely on version control.',
          });
        }
        consecutiveComments = 0;
      }
    }

    return results;
  }
}

/**
 * C006: Missing error handling
 * Detects procedures without TRY...CATCH
 */
export class MissingErrorHandlingRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'C006',
      severity: 'Warning',
      category: 'CodeSmell',
      message: 'Procedure missing error handling - consider adding TRY...CATCH',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];

    // Check if this is a procedure
    if (!this.isApplicableToCode(code, 'procedure')) {
      return results;
    }

    // Check if TRY...CATCH exists
    if (!/\bBEGIN\s+TRY\b/i.test(code)) {
      const objectName = this.getObjectName(code);
      results.push({
        ruleId: this.ruleId,
        severity: this.severity,
        category: this.category,
        message: `Procedure ${objectName || 'unknown'} missing error handling`,
        line: 1,
        column: 1,
        before: null,
        after: null,
        explanation: 'Add TRY...CATCH blocks to handle errors gracefully and provide better diagnostics.',
      });
    }

    return results;
  }
}

/**
 * C007: Missing transaction handling
 * Detects BEGIN TRANSACTION without ROLLBACK/COMMIT
 */
export class MissingTransactionHandlingRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'C007',
      severity: 'Error',
      category: 'CodeSmell',
      message: 'BEGIN TRANSACTION without corresponding COMMIT/ROLLBACK',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];

    const beginTranCount = (code.match(/\bBEGIN\s+TRAN(?:SACTION)?\b/gi) || []).length;
    const commitCount = (code.match(/\bCOMMIT\s+TRAN(?:SACTION)?\b/gi) || []).length;
    const rollbackCount = (code.match(/\bROLLBACK\s+TRAN(?:SACTION)?\b/gi) || []).length;

    if (beginTranCount > 0 && (commitCount + rollbackCount) < beginTranCount) {
      const pattern = /\bBEGIN\s+TRAN(?:SACTION)?\b/gi;
      const matches = this.findMatches(code, pattern);

      for (const match of matches) {
        results.push(
          this.createResult(
            match,
            match.match,
            null,
            'Every BEGIN TRANSACTION must have a corresponding COMMIT or ROLLBACK. ' +
            'Ensure error handling includes ROLLBACK in CATCH block.'
          )
        );
      }
    }

    return results;
  }
}

/**
 * C008: Hardcoded connection strings or credentials
 * Detects potential hardcoded credentials
 */
export class HardcodedCredentialsRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'C008',
      severity: 'Error',
      category: 'CodeSmell',
      message: 'Potential hardcoded credentials detected',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];

    // Detect password= patterns
    const pattern = /(password\s*=\s*['"][^'"]+['"]|pwd\s*=\s*['"][^'"]+['"])/gi;
    const matches = this.findMatches(code, pattern);

    for (const match of matches) {
      if (this.isInComment(code, match.line - 1, match.column - 1)) {
        continue;
      }

      results.push(
        this.createResult(
          match,
          match.match,
          'Password=[stored in secure configuration]',
          'Hardcoded credentials are a security risk. Use configuration files, environment variables, or secure vaults.'
        )
      );
    }

    return results;
  }
}

/**
 * Export all code smell rules
 */
export const codeSmellRules = [
  new TooManyColumnsRule(),
  new LongProcedureRule(),
  new DeepNestingRule(),
  new MagicNumbersRule(),
  new CommentedCodeRule(),
  new MissingErrorHandlingRule(),
  new MissingTransactionHandlingRule(),
  new HardcodedCredentialsRule(),
];
