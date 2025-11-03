/**
 * Type definitions for T-SQL code analysis
 *
 * These types define the structure for:
 * - Analysis rules and their detection logic
 * - Analysis results returned from rules
 * - Fix suggestions for detected issues
 * - Rule configuration (enable/disable, severity overrides)
 */

/**
 * Severity levels for analysis results
 */
export type Severity = 'Error' | 'Warning' | 'Info';

/**
 * Categories for grouping analysis rules
 */
export type Category =
  | 'Performance'      // P001-P010, P050+
  | 'Deprecated'       // DP001-DP008
  | 'Security'         // S001-S005
  | 'CodeSmell'        // C001-C008
  | 'Design'           // D001-D005
  | 'Naming';          // N001-N005

/**
 * Result of a single analysis rule detection
 */
export interface AnalysisResult {
  /** Rule identifier (e.g., P001, DP001, S001) */
  ruleId: string;

  /** Severity level of the issue */
  severity: Severity;

  /** Category this rule belongs to */
  category: Category;

  /** Human-readable message describing the issue */
  message: string;

  /** Line number where the issue was detected (1-indexed) */
  line: number;

  /** Column number where the issue was detected (1-indexed) */
  column: number;

  /** Original code snippet that triggered the rule */
  before: string | null;

  /** Suggested fix (if available) */
  after: string | null;

  /** Explanation of why this is an issue */
  explanation: string | null;
}

/**
 * Suggested fix for an analysis result
 * Provides detailed information about how to fix the issue
 */
export interface FixSuggestion {
  /** Rule identifier this suggestion applies to */
  ruleId: string;

  /** Short description of the fix */
  description: string;

  /** Original code (before fix) */
  before: string;

  /** Fixed code (after fix) */
  after: string;

  /** Detailed explanation of why this fix is better */
  explanation: string;

  /** Estimated performance impact of this fix */
  estimatedImpact: 'Low' | 'Medium' | 'High' | 'Very High';

  /** Whether this fix can be automatically applied */
  autoFixAvailable: boolean;

  /** Additional context or notes about the fix */
  notes?: string;
}

/**
 * Configuration for a single rule
 * Allows users to enable/disable rules and override severity
 */
export interface RuleConfiguration {
  /** Rule identifier */
  ruleId: string;

  /** Whether this rule is enabled */
  enabled: boolean;

  /** Override severity (if null, use rule's default) */
  severityOverride?: Severity | null;

  /** Custom message (if null, use rule's default) */
  messageOverride?: string | null;
}

/**
 * Summary of analysis results
 * Provides aggregate counts for quick overview
 */
export interface AnalysisSummary {
  /** Total number of issues found */
  totalIssues: number;

  /** Number of errors */
  errorCount: number;

  /** Number of warnings */
  warningCount: number;

  /** Number of info messages */
  infoCount: number;

  /** Number of rules that were executed */
  rulesExecuted: number;

  /** Number of rules that were skipped (disabled) */
  rulesSkipped: number;

  /** Analysis execution time in milliseconds */
  executionTimeMs: number;

  /** Timestamp when analysis was performed */
  timestamp: Date;
}

/**
 * Request to analyze code
 */
export interface AnalyzeCodeRequest {
  /** T-SQL code to analyze */
  code: string;

  /** Server ID (optional, for schema-aware analysis) */
  serverId?: number;

  /** Database name (optional, for schema-aware analysis) */
  databaseName?: string;

  /** Rule IDs to execute (if null, execute all enabled rules) */
  ruleIds?: string[] | null;
}

/**
 * Response from code analysis
 */
export interface AnalyzeCodeResponse {
  /** Whether analysis completed successfully */
  success: boolean;

  /** Analysis results (issues found) */
  results: AnalysisResult[];

  /** Summary of analysis */
  summary: AnalysisSummary;

  /** Error message (if success = false) */
  error?: string;
}

/**
 * Analysis rule interface
 * All analysis rules must implement this interface
 */
export interface IAnalysisRule {
  /** Unique rule identifier (e.g., P001, DP001) */
  ruleId: string;

  /** Severity level of issues detected by this rule */
  severity: Severity;

  /** Category this rule belongs to */
  category: Category;

  /** Human-readable message describing what this rule checks */
  message: string;

  /** Whether this rule is currently enabled */
  enabled: boolean;

  /**
   * Detect issues in the provided code
   * @param code T-SQL code to analyze
   * @returns Array of analysis results (empty if no issues found)
   */
  detect(code: string): Promise<AnalysisResult[]>;

  /**
   * Provide a fix suggestion for a detected issue
   * @param match The analysis result to provide a fix for
   * @returns Fix suggestion, or null if no fix available
   */
  suggest?(match: AnalysisResult): FixSuggestion | null;
}

/**
 * Analysis engine configuration
 */
export interface AnalysisEngineConfig {
  /** Rule configurations (enable/disable, severity overrides) */
  ruleConfigurations: RuleConfiguration[];

  /** Maximum analysis time in milliseconds (default: 10000) */
  maxExecutionTimeMs?: number;

  /** Whether to run rules in parallel (default: true) */
  runInParallel?: boolean;
}
