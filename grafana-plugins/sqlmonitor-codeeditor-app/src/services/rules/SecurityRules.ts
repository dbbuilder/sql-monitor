/**
 * Security Rules (S001-S005)
 *
 * Rules that detect potential security vulnerabilities in T-SQL code.
 */

import { BaseRule } from './RuleBase';
import type { AnalysisResult, FixSuggestion } from '../../types/analysis';

/**
 * S001: Dynamic SQL without sp_executesql
 * Detects EXEC(@sql) which is vulnerable to SQL injection
 */
export class DynamicSqlWithoutParametersRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'S001',
      severity: 'Error',
      category: 'Security',
      message: 'Use sp_executesql with parameters instead of EXEC(@sql) to prevent SQL injection',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    // Match EXEC(@variable) or EXECUTE(@variable)
    const pattern = /\bEXEC(?:UTE)?\s*\(\s*@\w+\s*\)/gi;
    const matches = this.findMatches(code, pattern);

    for (const match of matches) {
      if (this.isInComment(code, match.line - 1, match.column - 1)) {
        continue;
      }

      results.push(
        this.createResult(
          match,
          match.match,
          'sp_executesql @sql, N\'@param INT\', @param = @value',
          'EXEC(@sql) is vulnerable to SQL injection. Use sp_executesql with parameterized queries instead.'
        )
      );
    }

    return results;
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Use sp_executesql with parameters',
      before: "DECLARE @sql NVARCHAR(MAX) = 'SELECT * FROM Users WHERE ID = ' + @UserID;\nEXEC(@sql);",
      after: "DECLARE @sql NVARCHAR(MAX) = 'SELECT * FROM Users WHERE ID = @ID';\nEXEC sp_executesql @sql, N'@ID INT', @ID = @UserID;",
      explanation: 'Parameterized queries prevent SQL injection by treating input as data, not executable code.',
      estimatedImpact: 'Very High',
      autoFixAvailable: false,
    };
  }
}

/**
 * S002: Unencrypted password storage
 * Detects columns that might store passwords without encryption
 */
export class UnencryptedPasswordRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'S002',
      severity: 'Error',
      category: 'Security',
      message: 'Password columns should use hashing (not encryption) - consider HASHBYTES',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    // Match password-related columns with VARCHAR/NVARCHAR (not hashed)
    const pattern = /(\w*password\w*)\s+(N?VARCHAR|CHAR)/gi;
    const matches = this.findMatches(code, pattern);

    for (const match of matches) {
      if (this.isInComment(code, match.line - 1, match.column - 1)) {
        continue;
      }

      // Check if HASHBYTES or similar is used nearby
      const context = this.getCodeSnippet(code, match.line - 1, 5);
      if (!/HASHBYTES|PWDENCRYPT|ENCRYPT/i.test(context)) {
        results.push(
          this.createResult(
            match,
            match.match,
            'PasswordHash VARBINARY(64) -- use HASHBYTES',
            'Passwords should never be stored in plain text or encrypted (reversible). Use one-way hashing with HASHBYTES.'
          )
        );
      }
    }

    return results;
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Use HASHBYTES for password storage',
      before: "Password NVARCHAR(50)",
      after: "PasswordHash VARBINARY(64)\n-- Store: UPDATE Users SET PasswordHash = HASHBYTES('SHA2_512', @Password + @Salt)",
      explanation: 'Hash passwords with a salt using HASHBYTES. Never store passwords in reversible form.',
      estimatedImpact: 'Very High',
      autoFixAvailable: false,
    };
  }
}

/**
 * S003: xp_cmdshell usage
 * Detects xp_cmdshell which can be a security risk
 */
export class XpCmdshellUsageRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'S003',
      severity: 'Error',
      category: 'Security',
      message: 'xp_cmdshell is a security risk - avoid if possible',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    const pattern = /\bxp_cmdshell\b/gi;
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
          'xp_cmdshell executes OS commands and is a major security risk. ' +
          'Consider alternatives like CLR integration, SQL Agent jobs, or external services.'
        )
      );
    }

    return results;
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Replace xp_cmdshell with safer alternatives',
      before: "EXEC xp_cmdshell 'dir C:\\'",
      after: '-- Use SQL Agent Job, CLR, or external service instead',
      explanation: 'xp_cmdshell grants OS-level access which can be exploited. Use safer alternatives.',
      estimatedImpact: 'Very High',
      autoFixAvailable: false,
    };
  }
}

/**
 * S004: TRUSTWORTHY database property
 * Detects TRUSTWORTHY ON which can be a security risk
 */
export class TrustworthyDatabaseRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'S004',
      severity: 'Warning',
      category: 'Security',
      message: 'TRUSTWORTHY ON is a security risk - only enable if absolutely necessary',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    const pattern = /TRUSTWORTHY\s+ON/gi;
    const matches = this.findMatches(code, pattern);

    for (const match of matches) {
      results.push(
        this.createResult(
          match,
          match.match,
          'TRUSTWORTHY OFF',
          'TRUSTWORTHY ON allows code in the database to access resources outside the database. ' +
          'This is a security risk and should only be enabled when absolutely necessary.'
        )
      );
    }

    return results;
  }
}

/**
 * S005: Granting excessive permissions
 * Detects GRANT ALL or overly broad permissions
 */
export class ExcessivePermissionsRule extends BaseRule {
  constructor() {
    super({
      ruleId: 'S005',
      severity: 'Warning',
      category: 'Security',
      message: 'Avoid GRANT ALL - grant only necessary permissions',
    });
  }

  public async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];

    // Match GRANT ALL
    const grantAllPattern = /\bGRANT\s+ALL\b/gi;
    const grantAllMatches = this.findMatches(code, grantAllPattern);

    for (const match of grantAllMatches) {
      if (this.isInComment(code, match.line - 1, match.column - 1)) {
        continue;
      }

      results.push(
        this.createResult(
          match,
          match.match,
          'GRANT SELECT, INSERT, UPDATE',
          'GRANT ALL gives excessive permissions. Grant only the minimum necessary permissions (principle of least privilege).'
        )
      );
    }

    // Match GRANT ... TO PUBLIC
    const grantPublicPattern = /\bGRANT\s+\w+\s+.*?\bTO\s+PUBLIC\b/gi;
    const grantPublicMatches = this.findMatches(code, grantPublicPattern);

    for (const match of grantPublicMatches) {
      if (this.isInComment(code, match.line - 1, match.column - 1)) {
        continue;
      }

      results.push(
        this.createResult(
          match,
          match.match,
          'GRANT ... TO <specific_role>',
          'GRANT TO PUBLIC gives permissions to all users. Create specific roles instead.'
        )
      );
    }

    return results;
  }

  public suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Grant specific permissions to specific roles',
      before: 'GRANT ALL ON dbo.Customers TO PUBLIC',
      after: 'GRANT SELECT, INSERT ON dbo.Customers TO AppRole',
      explanation: 'Follow the principle of least privilege - grant only necessary permissions to specific roles.',
      estimatedImpact: 'High',
      autoFixAvailable: false,
    };
  }
}

/**
 * Export all security rules
 */
export const securityRules = [
  new DynamicSqlWithoutParametersRule(),
  new UnencryptedPasswordRule(),
  new XpCmdshellUsageRule(),
  new TrustworthyDatabaseRule(),
  new ExcessivePermissionsRule(),
];
