/**
 * Code formatting utilities
 *
 * Provides T-SQL code formatting using sql-formatter library.
 * https://github.com/sql-formatter-org/sql-formatter
 */

import { format, FormatOptions } from 'sql-formatter';

/**
 * Default formatting options for T-SQL
 */
const DEFAULT_FORMAT_OPTIONS: FormatOptions = {
  language: 'tsql',
  tabWidth: 4,
  useTabs: false,
  keywordCase: 'upper',
  indentStyle: 'standard',
  logicalOperatorNewline: 'before',
  expressionWidth: 50,
  linesBetweenQueries: 2,
  denseOperators: false,
  newlineBeforeSemicolon: false,
};

/**
 * Format T-SQL code
 *
 * @param code - T-SQL code to format
 * @param options - Optional formatting options (merged with defaults)
 * @returns Formatted T-SQL code
 */
export function formatSql(code: string, options?: Partial<FormatOptions>): string {
  try {
    const formatOptions = { ...DEFAULT_FORMAT_OPTIONS, ...options };
    return format(code, formatOptions);
  } catch (error) {
    console.error('[Formatter] Failed to format SQL:', error);
    // Return original code if formatting fails
    return code;
  }
}

/**
 * Format selected T-SQL code
 *
 * @param code - Full code content
 * @param selection - Selected text
 * @param options - Optional formatting options
 * @returns Formatted selected code
 */
export function formatSqlSelection(
  code: string,
  selection: string,
  options?: Partial<FormatOptions>
): string {
  if (!selection || selection.trim() === '') {
    return code;
  }

  try {
    const formatOptions = { ...DEFAULT_FORMAT_OPTIONS, ...options };
    const formatted = format(selection, formatOptions);
    return code.replace(selection, formatted);
  } catch (error) {
    console.error('[Formatter] Failed to format SQL selection:', error);
    return code;
  }
}

/**
 * Check if code is valid SQL (basic syntax check)
 *
 * @param code - T-SQL code to validate
 * @returns true if code appears to be valid SQL
 */
export function isValidSql(code: string): boolean {
  if (!code || code.trim() === '') {
    return false;
  }

  try {
    // Try to format - if it succeeds, it's likely valid SQL
    format(code, { language: 'tsql' });
    return true;
  } catch (error) {
    return false;
  }
}

/**
 * Minify T-SQL code (remove unnecessary whitespace)
 *
 * @param code - T-SQL code to minify
 * @returns Minified T-SQL code
 */
export function minifySql(code: string): string {
  try {
    return code
      .replace(/--.*$/gm, '') // Remove line comments
      .replace(/\/\*[\s\S]*?\*\//g, '') // Remove block comments
      .replace(/\s+/g, ' ') // Collapse whitespace
      .replace(/\s*([(),;=<>])\s*/g, '$1') // Remove spaces around operators
      .trim();
  } catch (error) {
    console.error('[Formatter] Failed to minify SQL:', error);
    return code;
  }
}

/**
 * Get line count for formatted code
 *
 * @param code - T-SQL code
 * @returns Number of lines
 */
export function getLineCount(code: string): number {
  if (!code || code.trim() === '') {
    return 0;
  }
  return code.split('\n').length;
}

/**
 * Get character count (excluding whitespace)
 *
 * @param code - T-SQL code
 * @returns Number of non-whitespace characters
 */
export function getCharacterCount(code: string): number {
  if (!code || code.trim() === '') {
    return 0;
  }
  return code.replace(/\s/g, '').length;
}

/**
 * Extract SQL statements from code
 *
 * @param code - T-SQL code containing multiple statements
 * @returns Array of individual SQL statements
 */
export function extractStatements(code: string): string[] {
  if (!code || code.trim() === '') {
    return [];
  }

  // Simple statement extraction (split by semicolon, but not inside strings)
  const statements: string[] = [];
  let currentStatement = '';
  let inString = false;
  let stringChar = '';

  for (let i = 0; i < code.length; i++) {
    const char = code[i];

    if (char === "'" || char === '"') {
      if (!inString) {
        inString = true;
        stringChar = char;
      } else if (char === stringChar) {
        inString = false;
      }
    }

    if (char === ';' && !inString) {
      if (currentStatement.trim()) {
        statements.push(currentStatement.trim());
      }
      currentStatement = '';
    } else {
      currentStatement += char;
    }
  }

  // Add last statement if exists
  if (currentStatement.trim()) {
    statements.push(currentStatement.trim());
  }

  return statements;
}

/**
 * Get formatting statistics
 *
 * @param originalCode - Original code before formatting
 * @param formattedCode - Formatted code
 * @returns Statistics object
 */
export function getFormattingStats(originalCode: string, formattedCode: string) {
  return {
    originalLines: getLineCount(originalCode),
    formattedLines: getLineCount(formattedCode),
    originalCharacters: getCharacterCount(originalCode),
    formattedCharacters: getCharacterCount(formattedCode),
    linesDiff: getLineCount(formattedCode) - getLineCount(originalCode),
    charsDiff: getCharacterCount(formattedCode) - getCharacterCount(originalCode),
  };
}
