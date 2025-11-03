/**
 * Sensitive Data Detector
 *
 * Detects potentially sensitive information in SQL scripts before saving to localStorage.
 * Helps prevent accidental storage of:
 * - Passwords
 * - API keys
 * - Social Security Numbers (SSN)
 * - Credit card numbers
 * - Connection strings
 * - Email addresses (in some contexts)
 * - Phone numbers
 *
 * Code Optimization: Security improvement from code review
 */

/**
 * Sensitive data match result
 */
export interface SensitiveDataMatch {
  /** Type of sensitive data detected */
  type: string;

  /** Human-readable description */
  description: string;

  /** Pattern that matched */
  pattern: string;

  /** Number of matches found */
  count: number;

  /** Severity level */
  severity: 'high' | 'medium' | 'low';
}

/**
 * Sensitive data detection result
 */
export interface SensitiveDataResult {
  /** Whether sensitive data was found */
  found: boolean;

  /** List of detected sensitive data types */
  matches: SensitiveDataMatch[];

  /** Overall severity (highest severity from matches) */
  overallSeverity: 'high' | 'medium' | 'low' | 'none';
}

/**
 * SensitiveDataDetector class
 */
export class SensitiveDataDetector {
  /**
   * Sensitive data patterns with descriptions and severity levels
   */
  private static readonly PATTERNS: Array<{
    type: string;
    description: string;
    pattern: RegExp;
    severity: 'high' | 'medium' | 'low';
  }> = [
    // High severity patterns (credentials, keys)
    {
      type: 'password',
      description: 'Password in SQL query or connection string',
      pattern: /password\s*=\s*['"][^'"]+['"]/gi,
      severity: 'high',
    },
    {
      type: 'password_variable',
      description: 'Password variable assignment',
      pattern: /@password\s*=\s*['"][^'"]+['"]/gi,
      severity: 'high',
    },
    {
      type: 'pwd',
      description: 'PWD parameter in connection string',
      pattern: /pwd\s*=\s*['"][^'"]+['"]/gi,
      severity: 'high',
    },
    {
      type: 'api_key',
      description: 'API key',
      pattern: /api[_-]?key\s*[=:]\s*['"]?[a-zA-Z0-9_\-]{20,}['"]?/gi,
      severity: 'high',
    },
    {
      type: 'secret_key',
      description: 'Secret key',
      pattern: /secret[_-]?key\s*[=:]\s*['"]?[a-zA-Z0-9_\-]{20,}['"]?/gi,
      severity: 'high',
    },
    {
      type: 'access_token',
      description: 'Access token',
      pattern: /access[_-]?token\s*[=:]\s*['"]?[a-zA-Z0-9_\-]{20,}['"]?/gi,
      severity: 'high',
    },
    {
      type: 'bearer_token',
      description: 'Bearer token',
      pattern: /bearer\s+[a-zA-Z0-9_\-\.]{20,}/gi,
      severity: 'high',
    },

    // Medium severity patterns (PII)
    {
      type: 'ssn',
      description: 'Social Security Number (SSN)',
      pattern: /\b\d{3}-\d{2}-\d{4}\b/g,
      severity: 'medium',
    },
    {
      type: 'ssn_no_dash',
      description: 'Social Security Number (no dashes)',
      pattern: /\b\d{9}\b/g,
      severity: 'medium',
    },
    {
      type: 'credit_card',
      description: 'Credit card number',
      pattern: /\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/g,
      severity: 'medium',
    },
    {
      type: 'email',
      description: 'Email address (may contain sensitive information)',
      pattern: /\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\b/g,
      severity: 'medium',
    },

    // Low severity patterns (configuration)
    {
      type: 'connection_string',
      description: 'Database connection string',
      pattern: /server\s*=.*database\s*=.*user\s*id\s*=/gi,
      severity: 'low',
    },
    {
      type: 'phone_number',
      description: 'Phone number',
      pattern: /\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/g,
      severity: 'low',
    },
    {
      type: 'ip_address',
      description: 'IP address (may be sensitive in some contexts)',
      pattern: /\b(?:\d{1,3}\.){3}\d{1,3}\b/g,
      severity: 'low',
    },
  ];

  /**
   * Detect sensitive data in content
   *
   * @param content - The content to scan
   * @returns Detection result with matches
   */
  static detect(content: string): SensitiveDataResult {
    const matches: SensitiveDataMatch[] = [];

    // Scan for each pattern
    for (const { type, description, pattern, severity } of this.PATTERNS) {
      // Create a fresh regex for each scan (reset lastIndex)
      const regex = new RegExp(pattern.source, pattern.flags);
      const foundMatches = content.match(regex);

      if (foundMatches && foundMatches.length > 0) {
        matches.push({
          type,
          description,
          pattern: pattern.source,
          count: foundMatches.length,
          severity,
        });
      }
    }

    // Determine overall severity
    let overallSeverity: 'high' | 'medium' | 'low' | 'none' = 'none';
    if (matches.some((m) => m.severity === 'high')) {
      overallSeverity = 'high';
    } else if (matches.some((m) => m.severity === 'medium')) {
      overallSeverity = 'medium';
    } else if (matches.some((m) => m.severity === 'low')) {
      overallSeverity = 'low';
    }

    return {
      found: matches.length > 0,
      matches,
      overallSeverity,
    };
  }

  /**
   * Check if content contains high-severity sensitive data
   *
   * @param content - The content to check
   * @returns True if high-severity sensitive data is found
   */
  static hasHighRiskData(content: string): boolean {
    const result = this.detect(content);
    return result.matches.some((m) => m.severity === 'high');
  }

  /**
   * Get a formatted warning message for display
   *
   * @param result - Detection result
   * @returns Formatted warning message
   */
  static getWarningMessage(result: SensitiveDataResult): string {
    if (!result.found) {
      return '';
    }

    const lines: string[] = [];
    lines.push('⚠️  Sensitive data detected in your script:');
    lines.push('');

    // Group by severity
    const highSeverity = result.matches.filter((m) => m.severity === 'high');
    const mediumSeverity = result.matches.filter((m) => m.severity === 'medium');
    const lowSeverity = result.matches.filter((m) => m.severity === 'low');

    if (highSeverity.length > 0) {
      lines.push('🔴 High Risk:');
      highSeverity.forEach((match) => {
        lines.push(`  • ${match.description} (${match.count} instance${match.count > 1 ? 's' : ''})`);
      });
      lines.push('');
    }

    if (mediumSeverity.length > 0) {
      lines.push('🟡 Medium Risk:');
      mediumSeverity.forEach((match) => {
        lines.push(`  • ${match.description} (${match.count} instance${match.count > 1 ? 's' : ''})`);
      });
      lines.push('');
    }

    if (lowSeverity.length > 0) {
      lines.push('🟢 Low Risk:');
      lowSeverity.forEach((match) => {
        lines.push(`  • ${match.description} (${match.count} instance${match.count > 1 ? 's' : ''})`);
      });
      lines.push('');
    }

    lines.push('Saving this script will store it in your browser\'s localStorage.');
    lines.push('Consider removing sensitive data before saving.');

    return lines.join('\n');
  }

  /**
   * Get a short summary message for display
   *
   * @param result - Detection result
   * @returns Short summary message
   */
  static getSummaryMessage(result: SensitiveDataResult): string {
    if (!result.found) {
      return '';
    }

    const count = result.matches.length;
    const types = result.matches.map((m) => m.type).join(', ');

    if (result.overallSeverity === 'high') {
      return `⚠️  High-risk sensitive data detected (${count} type${count > 1 ? 's' : ''}: ${types})`;
    } else if (result.overallSeverity === 'medium') {
      return `⚠️  Sensitive data detected (${count} type${count > 1 ? 's' : ''}: ${types})`;
    } else {
      return `ℹ️  Potentially sensitive data detected (${count} type${count > 1 ? 's' : ''}: ${types})`;
    }
  }

  /**
   * Get a list of detected sensitive data types
   *
   * @param content - The content to scan
   * @returns Array of detected data type names
   */
  static getDetectedTypes(content: string): string[] {
    const result = this.detect(content);
    return result.matches.map((m) => m.type);
  }
}
