/**
 * Logger utility
 *
 * Provides structured logging with configurable log levels.
 * Automatically adjusts log level based on environment (development vs production).
 * Replaces direct console.* calls throughout the application.
 *
 * Usage:
 *   Logger.debug('[Component] Action performed', { data: 'value' });
 *   Logger.info('[Component] User action', { userId: 123 });
 *   Logger.warn('[Component] Potential issue', { details: 'info' });
 *   Logger.error('[Component] Error occurred', error);
 *
 * Code Optimization: Best practice from code review
 */

/**
 * Log level enumeration
 */
export enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3,
  NONE = 4, // Disable all logging
}

/**
 * Logger configuration
 */
interface LoggerConfig {
  /** Minimum log level to display */
  level: LogLevel;

  /** Whether to include timestamps in logs */
  includeTimestamp: boolean;

  /** Whether to include log level in output */
  includeLevel: boolean;

  /** Prefix to add to all log messages */
  prefix: string;
}

/**
 * Logger class for structured logging
 */
export class Logger {
  /**
   * Current log level (defaults based on environment)
   */
  private static level: LogLevel =
    process.env.NODE_ENV === 'production' ? LogLevel.WARN : LogLevel.DEBUG;

  /**
   * Logger configuration
   */
  private static config: LoggerConfig = {
    level: Logger.level,
    includeTimestamp: true,
    includeLevel: true,
    prefix: '[SQLMonitor]',
  };

  /**
   * Set the log level
   *
   * @param level - The log level to set
   */
  static setLevel(level: LogLevel): void {
    Logger.level = level;
    Logger.config.level = level;
    Logger.info('[Logger] Log level changed', { newLevel: LogLevel[level] });
  }

  /**
   * Get the current log level
   *
   * @returns The current log level
   */
  static getLevel(): LogLevel {
    return Logger.level;
  }

  /**
   * Configure the logger
   *
   * @param config - Partial configuration to apply
   */
  static configure(config: Partial<LoggerConfig>): void {
    Logger.config = { ...Logger.config, ...config };
    if (config.level !== undefined) {
      Logger.level = config.level;
    }
  }

  /**
   * Format a log message with metadata
   *
   * @param level - Log level
   * @param message - Log message
   * @param args - Additional arguments
   * @returns Formatted message parts
   */
  private static formatMessage(level: LogLevel, message: string, args: any[]): any[] {
    const parts: any[] = [];

    // Add prefix
    if (Logger.config.prefix) {
      parts.push(Logger.config.prefix);
    }

    // Add timestamp
    if (Logger.config.includeTimestamp) {
      const timestamp = new Date().toISOString();
      parts.push(`[${timestamp}]`);
    }

    // Add log level
    if (Logger.config.includeLevel) {
      parts.push(`[${LogLevel[level]}]`);
    }

    // Add message
    parts.push(message);

    // Add additional arguments
    if (args.length > 0) {
      parts.push(...args);
    }

    return parts;
  }

  /**
   * Log a debug message
   *
   * Debug messages are only shown in development mode by default.
   * Use for detailed diagnostic information.
   *
   * @param message - Log message
   * @param args - Additional arguments (objects, errors, etc.)
   */
  static debug(message: string, ...args: any[]): void {
    if (Logger.level <= LogLevel.DEBUG) {
      console.log(...Logger.formatMessage(LogLevel.DEBUG, message, args));
    }
  }

  /**
   * Log an info message
   *
   * Info messages are shown in development and can be shown in production.
   * Use for general informational messages about application state.
   *
   * @param message - Log message
   * @param args - Additional arguments (objects, errors, etc.)
   */
  static info(message: string, ...args: any[]): void {
    if (Logger.level <= LogLevel.INFO) {
      console.log(...Logger.formatMessage(LogLevel.INFO, message, args));
    }
  }

  /**
   * Log a warning message
   *
   * Warning messages are shown in all environments by default.
   * Use for non-critical issues that should be investigated.
   *
   * @param message - Log message
   * @param args - Additional arguments (objects, errors, etc.)
   */
  static warn(message: string, ...args: any[]): void {
    if (Logger.level <= LogLevel.WARN) {
      console.warn(...Logger.formatMessage(LogLevel.WARN, message, args));
    }
  }

  /**
   * Log an error message
   *
   * Error messages are always shown (unless logging is completely disabled).
   * Use for errors and exceptions that need immediate attention.
   *
   * @param message - Log message
   * @param args - Additional arguments (errors, stack traces, etc.)
   */
  static error(message: string, ...args: any[]): void {
    if (Logger.level <= LogLevel.ERROR) {
      console.error(...Logger.formatMessage(LogLevel.ERROR, message, args));
    }
  }

  /**
   * Log a group (for related log messages)
   *
   * @param label - Group label
   * @param fn - Function to execute within the group
   */
  static group(label: string, fn: () => void): void {
    if (Logger.level <= LogLevel.INFO) {
      console.group(label);
      try {
        fn();
      } finally {
        console.groupEnd();
      }
    }
  }

  /**
   * Log a collapsed group (for related log messages)
   *
   * @param label - Group label
   * @param fn - Function to execute within the group
   */
  static groupCollapsed(label: string, fn: () => void): void {
    if (Logger.level <= LogLevel.INFO) {
      console.groupCollapsed(label);
      try {
        fn();
      } finally {
        console.groupEnd();
      }
    }
  }

  /**
   * Log a table (for structured data)
   *
   * @param data - Tabular data to display
   * @param columns - Optional column names
   */
  static table(data: any, columns?: string[]): void {
    if (Logger.level <= LogLevel.DEBUG) {
      console.table(data, columns);
    }
  }

  /**
   * Start a timer
   *
   * @param label - Timer label
   */
  static time(label: string): void {
    if (Logger.level <= LogLevel.DEBUG) {
      console.time(label);
    }
  }

  /**
   * End a timer and log the elapsed time
   *
   * @param label - Timer label
   */
  static timeEnd(label: string): void {
    if (Logger.level <= LogLevel.DEBUG) {
      console.timeEnd(label);
    }
  }

  /**
   * Assert a condition and log an error if false
   *
   * @param condition - Condition to assert
   * @param message - Error message if assertion fails
   * @param args - Additional arguments
   */
  static assert(condition: boolean, message: string, ...args: any[]): void {
    if (!condition) {
      Logger.error(`Assertion failed: ${message}`, ...args);
    }
  }
}

/**
 * Create a namespaced logger for a specific component or module
 *
 * @param namespace - Namespace (e.g., 'CodeEditor', 'AnalysisEngine')
 * @returns Object with namespaced logging methods
 *
 * @example
 * const logger = createLogger('CodeEditor');
 * logger.debug('Component mounted');
 * logger.info('Query executed', { duration: 123 });
 */
export function createLogger(namespace: string) {
  return {
    debug: (message: string, ...args: any[]) => Logger.debug(`[${namespace}] ${message}`, ...args),
    info: (message: string, ...args: any[]) => Logger.info(`[${namespace}] ${message}`, ...args),
    warn: (message: string, ...args: any[]) => Logger.warn(`[${namespace}] ${message}`, ...args),
    error: (message: string, ...args: any[]) => Logger.error(`[${namespace}] ${message}`, ...args),
    time: (label: string) => Logger.time(`[${namespace}] ${label}`),
    timeEnd: (label: string) => Logger.timeEnd(`[${namespace}] ${label}`),
  };
}
