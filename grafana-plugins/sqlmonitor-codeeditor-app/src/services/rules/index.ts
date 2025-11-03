/**
 * Rule Index
 *
 * Exports all analysis rules and registers them with the global AnalysisEngine.
 */

import { analysisEngine } from '../codeAnalysisService';

// Import all rule arrays
import { performanceRules } from './PerformanceRules';
import { deprecatedRules } from './DeprecatedRules';
import { securityRules } from './SecurityRules';
import { codeSmellRules } from './CodeSmellRules';
import { designRules } from './DesignRules';
import { namingRules } from './NamingRules';

/**
 * All available rules organized by category
 */
export const allRules = {
  performance: performanceRules,     // 10 rules (P001-P010)
  deprecated: deprecatedRules,       // 8 rules (DP001-DP008)
  security: securityRules,           // 5 rules (S001-S005)
  codeSmell: codeSmellRules,         // 8 rules (C001-C008)
  design: designRules,               // 5 rules (D001-D005)
  naming: namingRules,               // 5 rules (N001-N005)
};

/**
 * Flattened array of all rules (41 total)
 */
export const allRulesArray = [
  ...performanceRules,
  ...deprecatedRules,
  ...securityRules,
  ...codeSmellRules,
  ...designRules,
  ...namingRules,
];

/**
 * Rule count by category
 */
export const ruleStats = {
  performance: performanceRules.length,
  deprecated: deprecatedRules.length,
  security: securityRules.length,
  codeSmell: codeSmellRules.length,
  design: designRules.length,
  naming: namingRules.length,
  total: allRulesArray.length,
};

/**
 * Initialize the analysis engine with all rules
 * This is called automatically when this module is imported
 */
export function initializeAnalysisEngine(): void {
  analysisEngine.registerRules(allRulesArray);

  console.log(`[CodeAnalysisService] Registered ${ruleStats.total} analysis rules:`);
  console.log(`  - Performance: ${ruleStats.performance} rules`);
  console.log(`  - Deprecated: ${ruleStats.deprecated} rules`);
  console.log(`  - Security: ${ruleStats.security} rules`);
  console.log(`  - Code Smell: ${ruleStats.codeSmell} rules`);
  console.log(`  - Design: ${ruleStats.design} rules`);
  console.log(`  - Naming: ${ruleStats.naming} rules`);
}

// Auto-initialize on module load
initializeAnalysisEngine();

/**
 * Re-export individual rule categories for granular imports
 */
export { performanceRules, deprecatedRules, securityRules, codeSmellRules, designRules, namingRules };

/**
 * Re-export BaseRule for custom rule creation
 */
export { BaseRule } from './RuleBase';
