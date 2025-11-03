/**
 * CodeAnalysisService
 *
 * Main service for T-SQL code analysis.
 * Orchestrates all analysis rules and provides summary results.
 *
 * Week 5 Day 18: Integrated with SettingsService to respect disabled rules
 */

import type {
  IAnalysisRule,
  AnalysisResult,
  AnalysisSummary,
  RuleConfiguration,
  AnalysisEngineConfig,
} from '../types/analysis';
import { settingsService } from './settingsService';

/**
 * AnalysisEngine class
 *
 * Manages rule execution, configuration, and result aggregation.
 * Code Optimization: Added performance improvements (early exit, size limits)
 */
export class AnalysisEngine {
  private rules: Map<string, IAnalysisRule> = new Map();
  private config: AnalysisEngineConfig;

  /** Maximum script size for analysis (50KB) - Code Optimization */
  private static readonly MAX_ANALYSIS_SIZE = 50000;

  /** Analysis timeout (10 seconds) - Code Optimization */
  private static readonly ANALYSIS_TIMEOUT_MS = 10000;

  constructor(config?: Partial<AnalysisEngineConfig>) {
    this.config = {
      ruleConfigurations: [],
      maxExecutionTimeMs: AnalysisEngine.ANALYSIS_TIMEOUT_MS,
      runInParallel: true,
      ...config,
    };
  }

  /**
   * Register an analysis rule
   */
  public registerRule(rule: IAnalysisRule): void {
    this.rules.set(rule.ruleId, rule);
    console.log(`[AnalysisEngine] Registered rule: ${rule.ruleId} - ${rule.message}`);
  }

  /**
   * Register multiple rules at once
   */
  public registerRules(rules: IAnalysisRule[]): void {
    rules.forEach((rule) => this.registerRule(rule));
  }

  /**
   * Get all registered rules
   */
  public getRules(): IAnalysisRule[] {
    return Array.from(this.rules.values());
  }

  /**
   * Get rule by ID
   */
  public getRule(ruleId: string): IAnalysisRule | undefined {
    return this.rules.get(ruleId);
  }

  /**
   * Enable/disable a rule
   */
  public setRuleEnabled(ruleId: string, enabled: boolean): void {
    const rule = this.rules.get(ruleId);
    if (rule) {
      rule.enabled = enabled;
      console.log(`[AnalysisEngine] Rule ${ruleId} ${enabled ? 'enabled' : 'disabled'}`);
    }
  }

  /**
   * Update rule configuration
   */
  public updateConfig(config: Partial<AnalysisEngineConfig>): void {
    this.config = { ...this.config, ...config };

    // Apply rule configurations
    config.ruleConfigurations?.forEach((ruleConfig) => {
      const rule = this.rules.get(ruleConfig.ruleId);
      if (rule) {
        rule.enabled = ruleConfig.enabled;

        if (ruleConfig.severityOverride) {
          rule.severity = ruleConfig.severityOverride;
        }

        if (ruleConfig.messageOverride) {
          rule.message = ruleConfig.messageOverride;
        }
      }
    });
  }

  /**
   * Analyze T-SQL code
   * Code Optimization: Added early exit for large scripts
   *
   * @param code - T-SQL code to analyze
   * @param ruleIds - Optional list of specific rule IDs to run (if null, runs all enabled rules)
   * @returns Analysis results and summary
   */
  public async analyze(code: string, ruleIds?: string[] | null): Promise<{
    results: AnalysisResult[];
    summary: AnalysisSummary;
  }> {
    const startTime = performance.now();

    // Early exit for large scripts (Code Optimization)
    if (code.length > AnalysisEngine.MAX_ANALYSIS_SIZE) {
      console.warn(
        `[AnalysisEngine] Script too large for analysis (${code.length.toLocaleString()} characters). Maximum: ${AnalysisEngine.MAX_ANALYSIS_SIZE.toLocaleString()} characters. Skipping analysis.`
      );

      return {
        results: [],
        summary: {
          totalIssues: 0,
          errorCount: 0,
          warningCount: 0,
          infoCount: 0,
          rulesExecuted: 0,
          rulesSkipped: this.rules.size,
          executionTimeMs: performance.now() - startTime,
          timestamp: new Date(),
        },
      };
    }

    // Get rules to execute (Week 5 Day 18: respect disabled rules from settings)
    const disabledRules = settingsService.getSetting('disabledRules');
    let rulesToExecute = Array.from(this.rules.values()).filter(
      (rule) => rule.enabled && !disabledRules.includes(rule.ruleId)
    );

    if (ruleIds && ruleIds.length > 0) {
      rulesToExecute = rulesToExecute.filter((rule) => ruleIds.includes(rule.ruleId));
    }

    console.log(
      `[AnalysisEngine] Analyzing ${code.length.toLocaleString()} characters with ${rulesToExecute.length} rules (${disabledRules.length} disabled by settings)`
    );

    // Execute rules
    let allResults: AnalysisResult[] = [];

    if (this.config.runInParallel) {
      // Run rules in parallel
      const promises = rulesToExecute.map(async (rule) => {
        try {
          return await Promise.race([
            rule.detect(code),
            this.timeout(this.config.maxExecutionTimeMs!, `Rule ${rule.ruleId} timed out`),
          ]);
        } catch (error) {
          console.error(`[AnalysisEngine] Rule ${rule.ruleId} failed:`, error);
          return [];
        }
      });

      const resultsArrays = await Promise.all(promises);
      allResults = resultsArrays.flat();
    } else {
      // Run rules sequentially
      for (const rule of rulesToExecute) {
        try {
          const ruleResults = await Promise.race([
            rule.detect(code),
            this.timeout(this.config.maxExecutionTimeMs!, `Rule ${rule.ruleId} timed out`),
          ]);
          allResults.push(...ruleResults);
        } catch (error) {
          console.error(`[AnalysisEngine] Rule ${rule.ruleId} failed:`, error);
        }
      }
    }

    // Sort results by line number, then column
    allResults.sort((a, b) => {
      if (a.line !== b.line) {
        return a.line - b.line;
      }
      return a.column - b.column;
    });

    // Create summary
    const executionTime = performance.now() - startTime;
    const summary: AnalysisSummary = {
      totalIssues: allResults.length,
      errorCount: allResults.filter((r) => r.severity === 'Error').length,
      warningCount: allResults.filter((r) => r.severity === 'Warning').length,
      infoCount: allResults.filter((r) => r.severity === 'Info').length,
      rulesExecuted: rulesToExecute.length,
      rulesSkipped: this.rules.size - rulesToExecute.length,
      executionTimeMs: executionTime,
      timestamp: new Date(),
    };

    // Performance logging (Code Optimization)
    console.log(
      `[AnalysisEngine] Analysis complete: ${allResults.length} issues found in ${executionTime.toFixed(2)}ms (${(code.length / 1024).toFixed(1)}KB, ${rulesToExecute.length} rules)`
    );

    if (executionTime > 5000) {
      console.warn(`[AnalysisEngine] Slow analysis detected (${executionTime.toFixed(2)}ms). Consider disabling some rules for large scripts.`);
    }

    return { results: allResults, summary };
  }

  /**
   * Timeout helper
   */
  private timeout(ms: number, message: string): Promise<never> {
    return new Promise((_, reject) => {
      setTimeout(() => reject(new Error(message)), ms);
    });
  }

  /**
   * Clear all rules (for testing)
   */
  public clearRules(): void {
    this.rules.clear();
  }

  /**
   * Get rule statistics
   */
  public getRuleStats(): {
    totalRules: number;
    enabledRules: number;
    disabledRules: number;
    rulesByCategory: Record<string, number>;
    rulesBySeverity: Record<string, number>;
  } {
    const rules = Array.from(this.rules.values());

    const rulesByCategory: Record<string, number> = {};
    const rulesBySeverity: Record<string, number> = {};

    rules.forEach((rule) => {
      rulesByCategory[rule.category] = (rulesByCategory[rule.category] || 0) + 1;
      rulesBySeverity[rule.severity] = (rulesBySeverity[rule.severity] || 0) + 1;
    });

    return {
      totalRules: rules.length,
      enabledRules: rules.filter((r) => r.enabled).length,
      disabledRules: rules.filter((r) => !r.enabled).length,
      rulesByCategory,
      rulesBySeverity,
    };
  }
}

/**
 * Global analysis engine instance
 */
export const analysisEngine = new AnalysisEngine();
