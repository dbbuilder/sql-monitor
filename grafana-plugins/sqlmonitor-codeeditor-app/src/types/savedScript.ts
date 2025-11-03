/**
 * Type definitions for script management
 *
 * These types define the structure for:
 * - Saved scripts
 * - Script metadata
 * - Script import/export
 * - Script search/filtering
 */

/**
 * Saved T-SQL script
 */
export interface SavedScript {
  /** Unique identifier for the script */
  id: string;

  /** Script name */
  name: string;

  /** T-SQL code content */
  content: string;

  /** Server ID this script is associated with (optional) */
  serverId?: number;

  /** Server name (for display) */
  serverName?: string;

  /** Database name this script is associated with (optional) */
  databaseName?: string;

  /** Script description */
  description?: string;

  /** Tags for categorization and search */
  tags?: string[];

  /** When the script was created */
  createdAt: Date;

  /** When the script was last modified */
  lastModified: Date;

  /** Whether this script was auto-saved (vs manually saved) */
  autoSaved: boolean;

  /** User who created the script (if multi-user support added later) */
  createdBy?: string;

  /** Whether this script is marked as favorite */
  isFavorite?: boolean;

  /** Script category (e.g., "Query", "Stored Procedure", "Report") */
  category?: string;
}

/**
 * Request to save a script
 */
export interface SaveScriptRequest {
  /** Script ID (if updating existing script, otherwise generate new) */
  id?: string;

  /** Script name */
  name: string;

  /** T-SQL code content */
  content: string;

  /** Server ID (optional) */
  serverId?: number;

  /** Database name (optional) */
  databaseName?: string;

  /** Script description (optional) */
  description?: string;

  /** Tags (optional) */
  tags?: string[];

  /** Whether this is an auto-save */
  autoSaved: boolean;

  /** Script category (optional) */
  category?: string;
}

/**
 * Response from saving a script
 */
export interface SaveScriptResponse {
  /** Whether the save was successful */
  success: boolean;

  /** The saved script (includes generated ID if new) */
  script?: SavedScript;

  /** Error message (if success = false) */
  error?: string;
}

/**
 * Request to get all saved scripts
 */
export interface GetScriptsRequest {
  /** Filter by server ID (optional) */
  serverId?: number;

  /** Filter by database name (optional) */
  databaseName?: string;

  /** Filter by tags (optional) */
  tags?: string[];

  /** Filter by category (optional) */
  category?: string;

  /** Whether to include auto-saved scripts (default: false) */
  includeAutoSaved?: boolean;

  /** Search query (searches name, description, content) */
  searchQuery?: string;

  /** Sort by field (default: "lastModified") */
  sortBy?: 'name' | 'lastModified' | 'createdAt' | 'size';

  /** Sort order (default: "desc") */
  sortOrder?: 'asc' | 'desc';

  /** Whether to include favorites only (default: false) */
  favoritesOnly?: boolean;
}

/**
 * Response with list of scripts
 */
export interface GetScriptsResponse {
  /** Whether the request was successful */
  success: boolean;

  /** List of scripts */
  scripts: SavedScript[];

  /** Total count (may be different from scripts.length if pagination added later) */
  totalCount: number;

  /** Error message (if success = false) */
  error?: string;
}

/**
 * Request to delete a script
 */
export interface DeleteScriptRequest {
  /** Script ID to delete */
  id: string;
}

/**
 * Response from deleting a script
 */
export interface DeleteScriptResponse {
  /** Whether the delete was successful */
  success: boolean;

  /** Error message (if success = false) */
  error?: string;
}

/**
 * Request to export scripts
 */
export interface ExportScriptsRequest {
  /** Script IDs to export (if empty, export all) */
  scriptIds?: string[];

  /** Export format */
  format: 'json' | 'sql' | 'zip';
}

/**
 * Response from exporting scripts
 */
export interface ExportScriptsResponse {
  /** Whether the export was successful */
  success: boolean;

  /** Exported data (format depends on request.format) */
  data?: string | Blob;

  /** Filename for download */
  filename?: string;

  /** Error message (if success = false) */
  error?: string;
}

/**
 * Request to import scripts
 */
export interface ImportScriptsRequest {
  /** Imported data (JSON string or file) */
  data: string | File;

  /** Import mode */
  mode: 'merge' | 'replace';

  /** Whether to overwrite existing scripts with same name */
  overwriteExisting?: boolean;
}

/**
 * Response from importing scripts
 */
export interface ImportScriptsResponse {
  /** Whether the import was successful */
  success: boolean;

  /** Number of scripts imported */
  importedCount?: number;

  /** Number of scripts skipped (e.g., duplicates) */
  skippedCount?: number;

  /** Error messages (if any) */
  errors?: string[];

  /** Error message (if success = false) */
  error?: string;
}

/**
 * Auto-save configuration
 */
export interface AutoSaveConfig {
  /** Whether auto-save is enabled */
  enabled: boolean;

  /** Debounce delay in milliseconds (default: 2000) */
  debounceMs: number;

  /** Whether to show notifications on auto-save */
  showNotifications: boolean;

  /** Maximum number of auto-save entries to keep */
  maxAutoSaveCount: number;
}

/**
 * Script metadata (lightweight version for list views)
 */
export interface ScriptMetadata {
  /** Script ID */
  id: string;

  /** Script name */
  name: string;

  /** Script description */
  description?: string;

  /** Server name (if associated with a server) */
  serverName?: string;

  /** Database name (if associated with a database) */
  databaseName?: string;

  /** Tags */
  tags?: string[];

  /** When last modified */
  lastModified: Date;

  /** Size in characters */
  size: number;

  /** Whether this is an auto-saved script */
  autoSaved: boolean;

  /** Whether this is marked as favorite */
  isFavorite?: boolean;

  /** Script category */
  category?: string;
}
