/**
 * Query validation utilities
 *
 * Validates user input before sending to API to prevent:
 * - SQL injection (defense in depth)
 * - Dangerous operations (xp_cmdshell, sp_OACreate, etc.)
 * - Oversized queries
 * - Empty queries
 *
 * Code Optimization: Security improvement from code review
 */

/**
 * Validation result interface
 */
export interface ValidationResult {
  /** Whether the validation passed */
  valid: boolean;

  /** List of validation error messages */
  errors: string[];

  /** List of warnings (non-blocking) */
  warnings: string[];
}

/**
 * QueryValidator class for validating SQL queries
 */
export class QueryValidator {
  /** Maximum query length (1MB) */
  private static readonly MAX_QUERY_LENGTH = 1000000;

  /** Minimum query length (at least 3 characters like "1=1") */
  private static readonly MIN_QUERY_LENGTH = 3;

  /**
   * Dangerous SQL patterns that should be blocked or warned about
   * These patterns represent high-risk operations that should rarely be used
   */
  private static readonly DANGEROUS_PATTERNS: Array<{ pattern: RegExp; message: string; severity: 'error' | 'warning' }> = [
    {
      pattern: /xp_cmdshell/i,
      message: 'xp_cmdshell is not allowed (command execution risk)',
      severity: 'error',
    },
    {
      pattern: /sp_OACreate/i,
      message: 'sp_OACreate is not allowed (OLE Automation risk)',
      severity: 'error',
    },
    {
      pattern: /sp_OAMethod/i,
      message: 'sp_OAMethod is not allowed (OLE Automation risk)',
      severity: 'error',
    },
    {
      pattern: /sp_OAGetProperty/i,
      message: 'sp_OAGetProperty is not allowed (OLE Automation risk)',
      severity: 'error',
    },
    {
      pattern: /sp_OASetProperty/i,
      message: 'sp_OASetProperty is not allowed (OLE Automation risk)',
      severity: 'error',
    },
    {
      pattern: /sp_OADestroy/i,
      message: 'sp_OADestroy is not allowed (OLE Automation risk)',
      severity: 'error',
    },
    {
      pattern: /OPENROWSET/i,
      message: 'OPENROWSET may pose security risks (ad-hoc distributed queries)',
      severity: 'warning',
    },
    {
      pattern: /OPENDATASOURCE/i,
      message: 'OPENDATASOURCE may pose security risks (ad-hoc distributed queries)',
      severity: 'warning',
    },
    {
      pattern: /BULK\s+INSERT/i,
      message: 'BULK INSERT may pose security risks (file system access)',
      severity: 'warning',
    },
    {
      pattern: /xp_regread/i,
      message: 'xp_regread is not recommended (registry access)',
      severity: 'warning',
    },
    {
      pattern: /xp_regwrite/i,
      message: 'xp_regwrite is not allowed (registry modification)',
      severity: 'error',
    },
    {
      pattern: /xp_regdeletekey/i,
      message: 'xp_regdeletekey is not allowed (registry deletion)',
      severity: 'error',
    },
    {
      pattern: /xp_regdeletevalue/i,
      message: 'xp_regdeletevalue is not allowed (registry deletion)',
      severity: 'error',
    },
  ];

  /**
   * Validate a SQL query
   *
   * @param query - The SQL query to validate
   * @returns Validation result with errors and warnings
   */
  static validate(query: string): ValidationResult {
    const errors: string[] = [];
    const warnings: string[] = [];

    // Trim whitespace for validation
    const trimmedQuery = query.trim();

    // 1. Check for empty query
    if (trimmedQuery.length === 0) {
      errors.push('Query cannot be empty');
      return { valid: false, errors, warnings };
    }

    // 2. Check minimum length
    if (trimmedQuery.length < this.MIN_QUERY_LENGTH) {
      errors.push(`Query is too short (minimum ${this.MIN_QUERY_LENGTH} characters)`);
    }

    // 3. Check maximum length
    if (trimmedQuery.length > this.MAX_QUERY_LENGTH) {
      errors.push(
        `Query is too large (${trimmedQuery.length.toLocaleString()} characters). Maximum allowed: ${this.MAX_QUERY_LENGTH.toLocaleString()} characters (1MB)`
      );
    }

    // 4. Check for dangerous patterns
    for (const { pattern, message, severity } of this.DANGEROUS_PATTERNS) {
      if (pattern.test(trimmedQuery)) {
        if (severity === 'error') {
          errors.push(message);
        } else {
          warnings.push(message);
        }
      }
    }

    // 5. Check for potentially unsafe dynamic SQL
    if (/EXEC\s*\(\s*@/i.test(trimmedQuery) || /EXECUTE\s*\(\s*@/i.test(trimmedQuery)) {
      warnings.push(
        'Dynamic SQL with variables detected (EXEC(@var) or EXECUTE(@var)). Ensure proper input validation is in place.'
      );
    }

    // 6. Check for SQL comments that might be used for comment-based injection
    if (/--.*DROP\s+/i.test(trimmedQuery) || /\/\*.*DROP\s+/i.test(trimmedQuery)) {
      warnings.push('DROP statement found in comment. Ensure this is intentional.');
    }

    // Validation passes if there are no errors
    const valid = errors.length === 0;

    return { valid, errors, warnings };
  }

  /**
   * Validate query and throw error if invalid
   *
   * @param query - The SQL query to validate
   * @throws Error if validation fails
   */
  static validateOrThrow(query: string): void {
    const result = this.validate(query);

    if (!result.valid) {
      throw new Error(`Query validation failed:\n${result.errors.join('\n')}`);
    }
  }

  /**
   * Check if a query contains dangerous patterns (convenience method)
   *
   * @param query - The SQL query to check
   * @returns True if dangerous patterns are detected
   */
  static hasDangerousPatterns(query: string): boolean {
    const result = this.validate(query);
    return result.errors.some((error) => error.includes('not allowed'));
  }

  /**
   * Get formatted validation message for display
   *
   * @param result - Validation result
   * @returns Formatted message string
   */
  static getFormattedMessage(result: ValidationResult): string {
    const lines: string[] = [];

    if (result.errors.length > 0) {
      lines.push('❌ Validation Errors:');
      result.errors.forEach((error, index) => {
        lines.push(`  ${index + 1}. ${error}`);
      });
    }

    if (result.warnings.length > 0) {
      if (lines.length > 0) {
        lines.push('');
      }
      lines.push('⚠️  Warnings:');
      result.warnings.forEach((warning, index) => {
        lines.push(`  ${index + 1}. ${warning}`);
      });
    }

    return lines.join('\n');
  }
}
