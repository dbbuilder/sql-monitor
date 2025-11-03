/**
 * Application Constants
 *
 * Centralized location for all magic numbers and constant values used throughout the application.
 * Improves maintainability and makes it easier to adjust values in one place.
 *
 * Code Optimization: Extract magic numbers (from code review)
 */

/**
 * Editor-related constants
 */
export const EDITOR_CONSTANTS = {
  /** Minimum font size (pixels) */
  FONT_SIZE_MIN: 10,

  /** Maximum font size (pixels) */
  FONT_SIZE_MAX: 24,

  /** Default font size (pixels) */
  FONT_SIZE_DEFAULT: 14,

  /** Line height offset added to font size for proper spacing */
  LINE_HEIGHT_OFFSET: 6,

  /** Minimum tab size (spaces) */
  TAB_SIZE_MIN: 2,

  /** Maximum tab size (spaces) */
  TAB_SIZE_MAX: 8,

  /** Default tab size (spaces) */
  TAB_SIZE_DEFAULT: 4,

  /** Default editor height */
  DEFAULT_HEIGHT: '100%',

  /** Default language */
  DEFAULT_LANGUAGE: 'sql' as const,
} as const;

/**
 * Auto-save related constants
 */
export const AUTO_SAVE_CONSTANTS = {
  /** Minimum auto-save delay (milliseconds) */
  DELAY_MIN_MS: 1000,

  /** Maximum auto-save delay (milliseconds) */
  DELAY_MAX_MS: 30000,

  /** Default auto-save delay (milliseconds) */
  DELAY_DEFAULT_MS: 5000,

  /** Debounce time for auto-save (milliseconds) */
  DEBOUNCE_MS: 2000,

  /** Maximum number of auto-save slots */
  MAX_AUTO_SAVE_COUNT: 10,

  /** Auto-save enabled by default */
  ENABLED_BY_DEFAULT: true,
} as const;

/**
 * Query execution related constants
 */
export const QUERY_CONSTANTS = {
  /** Minimum query timeout (seconds) */
  TIMEOUT_MIN_SEC: 5,

  /** Maximum query timeout (seconds) */
  TIMEOUT_MAX_SEC: 300,

  /** Default query timeout (seconds) */
  TIMEOUT_DEFAULT_SEC: 60,

  /** Maximum query size (bytes) - 1MB */
  MAX_QUERY_SIZE_BYTES: 1000000,

  /** Maximum result rows to fetch */
  MAX_RESULT_ROWS: 10000,

  /** Query execution retry attempts */
  MAX_RETRY_ATTEMPTS: 3,

  /** Retry delay (milliseconds) */
  RETRY_DELAY_MS: 1000,
} as const;

/**
 * Results grid related constants
 */
export const RESULTS_GRID_CONSTANTS = {
  /** Default page size for results pagination */
  PAGE_SIZE_DEFAULT: 50,

  /** Available page size options */
  PAGE_SIZE_OPTIONS: [10, 25, 50, 100, 500, 1000] as const,

  /** Maximum column width (pixels) */
  MAX_COLUMN_WIDTH: 500,

  /** Minimum column width (pixels) */
  MIN_COLUMN_WIDTH: 50,

  /** Default column width (pixels) */
  DEFAULT_COLUMN_WIDTH: 150,

  /** Row buffer for virtual scrolling */
  ROW_BUFFER: 10,

  /** Cache block size for pagination */
  CACHE_BLOCK_SIZE: 100,

  /** Maximum blocks in cache */
  MAX_BLOCKS_IN_CACHE: 10,
} as const;

/**
 * Code analysis related constants
 */
export const ANALYSIS_CONSTANTS = {
  /** Maximum script size for analysis (bytes) - 50KB */
  MAX_ANALYSIS_SIZE: 50000,

  /** Analysis timeout (milliseconds) - 10 seconds */
  ANALYSIS_TIMEOUT_MS: 10000,

  /** Debounce time for auto-analysis (milliseconds) */
  DEBOUNCE_MS: 2000,

  /** Auto-run analysis enabled by default */
  AUTO_RUN_BY_DEFAULT: true,

  /** Maximum number of analysis results to display */
  MAX_RESULTS_DISPLAY: 100,

  /** Severity levels */
  SEVERITY: {
    ERROR: 'error' as const,
    WARNING: 'warning' as const,
    INFO: 'info' as const,
  },
} as const;

/**
 * Storage keys for localStorage
 */
export const STORAGE_KEYS = {
  /** Settings storage key */
  SETTINGS: 'sqlmonitor-codeeditor-settings',

  /** Saved scripts storage key */
  SCRIPTS: 'sqlmonitor-scripts',

  /** Current script state storage key */
  CURRENT_SCRIPT: 'sqlmonitor-current-script',

  /** Tab state storage key */
  TAB_STATE: 'sqlmonitor-tab-state',

  /** Analysis cache storage key */
  ANALYSIS_CACHE: 'sqlmonitor-analysis-cache',

  /** Object metadata cache storage key */
  OBJECT_METADATA_CACHE: 'sqlmonitor-object-metadata-cache',

  /** Query history storage key */
  QUERY_HISTORY: 'sqlmonitor-query-history',
} as const;

/**
 * UI-related constants
 */
export const UI_CONSTANTS = {
  /** Default panel split ratio (editor:results) */
  DEFAULT_SPLIT_RATIO: 0.6,

  /** Minimum panel width (pixels) */
  MIN_PANEL_WIDTH: 200,

  /** Object browser width (pixels) */
  OBJECT_BROWSER_WIDTH: 300,

  /** Analysis panel height (pixels) */
  ANALYSIS_PANEL_HEIGHT: 250,

  /** Tab bar height (pixels) */
  TAB_BAR_HEIGHT: 40,

  /** Toolbar height (pixels) */
  TOOLBAR_HEIGHT: 50,

  /** Default notification duration (milliseconds) */
  NOTIFICATION_DURATION_MS: 5000,

  /** Toast position */
  TOAST_POSITION: 'top-right' as const,
} as const;

/**
 * Performance-related constants
 */
export const PERFORMANCE_CONSTANTS = {
  /** Throttle time for resize events (milliseconds) */
  RESIZE_THROTTLE_MS: 100,

  /** Debounce time for search/filter (milliseconds) */
  SEARCH_DEBOUNCE_MS: 300,

  /** Timeout for API requests (milliseconds) */
  API_TIMEOUT_MS: 30000,

  /** Maximum retries for failed API requests */
  API_MAX_RETRIES: 3,

  /** Cache expiration time (milliseconds) - 5 minutes */
  CACHE_EXPIRATION_MS: 300000,
} as const;

/**
 * Object Browser constants
 */
export const OBJECT_BROWSER_CONSTANTS = {
  /** Default expanded depth */
  DEFAULT_EXPANDED_DEPTH: 1,

  /** Maximum tree depth */
  MAX_TREE_DEPTH: 5,

  /** Cache duration for object metadata (milliseconds) - 5 minutes */
  CACHE_DURATION_MS: 300000,

  /** Maximum objects to display per node */
  MAX_OBJECTS_PER_NODE: 1000,
} as const;

/**
 * Keyboard shortcut constants
 */
export const KEYBOARD_SHORTCUTS = {
  /** Run query */
  RUN_QUERY: ['Ctrl+Enter', 'F5'] as const,

  /** Save script */
  SAVE: 'Ctrl+S',

  /** Format code */
  FORMAT: 'Shift+Alt+F',

  /** Toggle comment */
  COMMENT: 'Ctrl+/',

  /** Duplicate line */
  DUPLICATE_LINE: 'Ctrl+D',

  /** Delete line */
  DELETE_LINE: 'Ctrl+Shift+K',

  /** Find */
  FIND: 'Ctrl+F',

  /** Replace */
  REPLACE: 'Ctrl+H',

  /** Go to line */
  GO_TO_LINE: 'Ctrl+G',

  /** Quick open */
  QUICK_OPEN: 'Ctrl+P',
} as const;

/**
 * Feature flags
 */
export const FEATURE_FLAGS = {
  /** Enable experimental features */
  ENABLE_EXPERIMENTAL_FEATURES: false,

  /** Enable telemetry */
  ENABLE_TELEMETRY: false,

  /** Enable advanced analysis rules */
  ENABLE_ADVANCED_ANALYSIS: true,

  /** Enable auto-completion */
  ENABLE_AUTO_COMPLETION: true,

  /** Enable IntelliSense */
  ENABLE_INTELLISENSE: true,
} as const;

/**
 * API endpoints (base paths)
 */
export const API_ENDPOINTS = {
  /** Execute query */
  EXECUTE_QUERY: '/api/code/execute',

  /** Cancel query */
  CANCEL_QUERY: '/api/code/cancel',

  /** Get servers */
  GET_SERVERS: '/api/code/servers',

  /** Get databases */
  GET_DATABASES: '/api/code/servers/:id/databases',

  /** Get objects */
  GET_OBJECTS: '/api/code/servers/:id/databases/:db/objects',

  /** Get object code */
  GET_OBJECT_CODE: '/api/code/servers/:id/databases/:db/objects/:obj/code',
} as const;

/**
 * Error messages
 */
export const ERROR_MESSAGES = {
  /** Generic error */
  GENERIC_ERROR: 'An unexpected error occurred',

  /** Network error */
  NETWORK_ERROR: 'Network error. Please check your connection.',

  /** Timeout error */
  TIMEOUT_ERROR: 'Request timed out. Please try again.',

  /** Authentication error */
  AUTH_ERROR: 'Authentication required. Please log in.',

  /** Permission error */
  PERMISSION_ERROR: 'You do not have permission to perform this action.',

  /** Query too large */
  QUERY_TOO_LARGE: 'Query is too large to execute',

  /** Query empty */
  QUERY_EMPTY: 'Query cannot be empty',

  /** Save failed */
  SAVE_FAILED: 'Failed to save script',

  /** Load failed */
  LOAD_FAILED: 'Failed to load script',
} as const;

/**
 * Success messages
 */
export const SUCCESS_MESSAGES = {
  /** Query executed */
  QUERY_EXECUTED: 'Query executed successfully',

  /** Script saved */
  SCRIPT_SAVED: 'Script saved successfully',

  /** Script loaded */
  SCRIPT_LOADED: 'Script loaded successfully',

  /** Settings saved */
  SETTINGS_SAVED: 'Settings saved successfully',

  /** Code formatted */
  CODE_FORMATTED: 'Code formatted successfully',
} as const;
