/**
 * AutoSaveService
 *
 * Provides automatic saving of scripts to browser localStorage.
 * Features:
 * - Auto-save with configurable debounce (from SettingsService)
 * - Manual save (Ctrl+S)
 * - Session restore on page load
 * - Script management (get all, delete, clear)
 *
 * Week 5 Day 18: Integrated with SettingsService for auto-save settings
 */

import { debounce } from 'lodash';
import type {
  SavedScript,
  SaveScriptRequest,
  SaveScriptResponse,
  GetScriptsRequest,
  GetScriptsResponse,
  DeleteScriptRequest,
  DeleteScriptResponse,
  AutoSaveConfig,
  ScriptMetadata,
} from '../types/savedScript';
import { settingsService } from './settingsService';

/**
 * Storage keys for localStorage
 */
const STORAGE_KEYS = {
  /** All saved scripts */
  SCRIPTS: 'sqlmonitor-scripts',
  /** Current script being edited */
  CURRENT: 'sqlmonitor-current-script',
  /** Auto-save configuration */
  CONFIG: 'sqlmonitor-autosave-config',
} as const;

/**
 * AutoSaveService class
 * Manages script saving, loading, and auto-save functionality
 *
 * Week 5 Day 18: Uses SettingsService for configuration instead of local config
 */
export class AutoSaveService {
  private static debouncedAutoSave: ReturnType<typeof debounce> | null = null;

  /**
   * Initialize the service (Week 5 Day 18: no longer needed, kept for compatibility)
   */
  public static initialize(): void {
    console.log('[AutoSave] Service initialized (using SettingsService for config)');
    this.recreateDebouncedFunction();
  }

  /**
   * Get current configuration from SettingsService (Week 5 Day 18)
   */
  public static getConfig(): AutoSaveConfig {
    const settings = settingsService.getSettings();
    return {
      enabled: settings.autoSaveEnabled,
      debounceMs: settings.autoSaveDelayMs,
      showNotifications: false,
      maxAutoSaveCount: 10,
    };
  }

  /**
   * Update configuration via SettingsService (Week 5 Day 18)
   */
  public static updateConfig(config: Partial<AutoSaveConfig>): void {
    const updates: any = {};
    if (config.enabled !== undefined) {
      updates.autoSaveEnabled = config.enabled;
    }
    if (config.debounceMs !== undefined) {
      updates.autoSaveDelayMs = config.debounceMs;
    }
    settingsService.updateSettings(updates);
    this.recreateDebouncedFunction();
  }

  /**
   * Recreate debounced function with current delay from settings (Week 5 Day 18)
   */
  private static recreateDebouncedFunction(): void {
    const config = this.getConfig();
    this.debouncedAutoSave = debounce(this.autoSaveImplementation.bind(this), config.debounceMs);
    console.log(`[AutoSave] Debounce recreated with ${config.debounceMs}ms delay`);
  }

  /**
   * Auto-save implementation (Week 5 Day 18: now called by dynamic debounced function)
   */
  private static autoSaveImplementation(content: string, scriptId?: string, metadata?: Partial<SavedScript>): void {
    const config = this.getConfig();
    if (!config.enabled) {
      console.log('[AutoSave] Auto-save is disabled');
      return;
    }

    const script: SavedScript = {
      id: scriptId || 'auto-save-temp',
      name: metadata?.name || 'Unsaved Script',
      content,
      serverId: metadata?.serverId,
      serverName: metadata?.serverName,
      databaseName: metadata?.databaseName,
      description: metadata?.description,
      tags: metadata?.tags,
      createdAt: metadata?.createdAt || new Date(),
      lastModified: new Date(),
      autoSaved: true,
      createdBy: metadata?.createdBy,
      isFavorite: metadata?.isFavorite,
      category: metadata?.category,
    };

    // Save to current script
    localStorage.setItem(STORAGE_KEYS.CURRENT, JSON.stringify(script));

    // Clean up old auto-saves
    this.cleanupAutoSaves();

    console.log('[AutoSave] Script auto-saved at', new Date().toLocaleTimeString());
  }

  /**
   * Auto-save a script (debounced) - Public API (Week 5 Day 18)
   */
  public static autoSave(content: string, scriptId?: string, metadata?: Partial<SavedScript>): void {
    if (!this.debouncedAutoSave) {
      this.recreateDebouncedFunction();
    }
    this.debouncedAutoSave!(content, scriptId, metadata);
  }

  /**
   * Manually save a script
   * Called when user presses Ctrl+S
   */
  public static manualSave(request: SaveScriptRequest): SaveScriptResponse {
    try {
      const script: SavedScript = {
        id: request.id || this.generateId(),
        name: request.name,
        content: request.content,
        serverId: request.serverId,
        databaseName: request.databaseName,
        description: request.description,
        tags: request.tags || [],
        createdAt: request.id ? this.getScriptById(request.id)?.createdAt || new Date() : new Date(),
        lastModified: new Date(),
        autoSaved: false,
        category: request.category,
      };

      // Get all scripts
      const scripts = this.getAllScriptsInternal();

      // Update existing or add new
      const existingIndex = scripts.findIndex((s) => s.id === script.id);
      if (existingIndex >= 0) {
        scripts[existingIndex] = script;
      } else {
        scripts.push(script);
      }

      // Save to localStorage
      localStorage.setItem(STORAGE_KEYS.SCRIPTS, JSON.stringify(scripts));

      // Also update current script
      localStorage.setItem(STORAGE_KEYS.CURRENT, JSON.stringify(script));

      console.log('[ManualSave] Script saved:', script.name);

      return {
        success: true,
        script,
      };
    } catch (error) {
      console.error('[ManualSave] Failed to save script:', error);
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error',
      };
    }
  }

  /**
   * Restore last session
   * Called when page loads to restore user's work
   */
  public static restoreLastSession(): SavedScript | null {
    const stored = localStorage.getItem(STORAGE_KEYS.CURRENT);
    if (!stored) {
      return null;
    }

    try {
      const script = JSON.parse(stored) as SavedScript;

      // Convert date strings back to Date objects
      script.createdAt = new Date(script.createdAt);
      script.lastModified = new Date(script.lastModified);

      console.log('[Restore] Loaded script:', script.name, 'from', script.lastModified);

      return script;
    } catch (error) {
      console.error('[Restore] Failed to parse saved script:', error);
      return null;
    }
  }

  /**
   * Get all saved scripts
   */
  public static getAllScripts(request: GetScriptsRequest = {}): GetScriptsResponse {
    try {
      let scripts = this.getAllScriptsInternal();

      // Apply filters
      if (request.serverId !== undefined) {
        scripts = scripts.filter((s) => s.serverId === request.serverId);
      }

      if (request.databaseName) {
        scripts = scripts.filter((s) => s.databaseName === request.databaseName);
      }

      if (request.category) {
        scripts = scripts.filter((s) => s.category === request.category);
      }

      if (request.tags && request.tags.length > 0) {
        scripts = scripts.filter((s) => request.tags!.some((tag) => s.tags?.includes(tag)));
      }

      if (!request.includeAutoSaved) {
        scripts = scripts.filter((s) => !s.autoSaved);
      }

      if (request.favoritesOnly) {
        scripts = scripts.filter((s) => s.isFavorite);
      }

      // Apply search query
      if (request.searchQuery) {
        const query = request.searchQuery.toLowerCase();
        scripts = scripts.filter(
          (s) =>
            s.name.toLowerCase().includes(query) ||
            s.description?.toLowerCase().includes(query) ||
            s.content.toLowerCase().includes(query)
        );
      }

      // Sort
      const sortBy = request.sortBy || 'lastModified';
      const sortOrder = request.sortOrder || 'desc';

      scripts.sort((a, b) => {
        let comparison = 0;

        switch (sortBy) {
          case 'name':
            comparison = a.name.localeCompare(b.name);
            break;
          case 'lastModified':
            comparison = a.lastModified.getTime() - b.lastModified.getTime();
            break;
          case 'createdAt':
            comparison = a.createdAt.getTime() - b.createdAt.getTime();
            break;
          case 'size':
            comparison = a.content.length - b.content.length;
            break;
        }

        return sortOrder === 'asc' ? comparison : -comparison;
      });

      return {
        success: true,
        scripts,
        totalCount: scripts.length,
      };
    } catch (error) {
      console.error('[GetScripts] Failed to get scripts:', error);
      return {
        success: false,
        scripts: [],
        totalCount: 0,
        error: error instanceof Error ? error.message : 'Unknown error',
      };
    }
  }

  /**
   * Get script metadata (lightweight)
   */
  public static getAllScriptMetadata(): ScriptMetadata[] {
    const scripts = this.getAllScriptsInternal();
    return scripts.map((s) => ({
      id: s.id,
      name: s.name,
      description: s.description,
      serverName: s.serverName,
      databaseName: s.databaseName,
      tags: s.tags,
      lastModified: s.lastModified,
      size: s.content.length,
      autoSaved: s.autoSaved,
      isFavorite: s.isFavorite,
      category: s.category,
    }));
  }

  /**
   * Get a single script by ID
   */
  public static getScriptById(id: string): SavedScript | null {
    const scripts = this.getAllScriptsInternal();
    const script = scripts.find((s) => s.id === id);
    return script || null;
  }

  /**
   * Delete a script
   */
  public static deleteScript(request: DeleteScriptRequest): DeleteScriptResponse {
    try {
      const scripts = this.getAllScriptsInternal();
      const filteredScripts = scripts.filter((s) => s.id !== request.id);

      if (filteredScripts.length === scripts.length) {
        // Script not found
        return {
          success: false,
          error: `Script with ID ${request.id} not found`,
        };
      }

      localStorage.setItem(STORAGE_KEYS.SCRIPTS, JSON.stringify(filteredScripts));

      // If this was the current script, clear it
      const current = this.restoreLastSession();
      if (current?.id === request.id) {
        localStorage.removeItem(STORAGE_KEYS.CURRENT);
      }

      console.log('[Delete] Script deleted:', request.id);

      return {
        success: true,
      };
    } catch (error) {
      console.error('[Delete] Failed to delete script:', error);
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error',
      };
    }
  }

  /**
   * Clear all auto-saved scripts
   */
  public static clearAutoSaves(): void {
    const scripts = this.getAllScriptsInternal();
    const manualScripts = scripts.filter((s) => !s.autoSaved);
    localStorage.setItem(STORAGE_KEYS.SCRIPTS, JSON.stringify(manualScripts));
    console.log('[Clear] Auto-saved scripts cleared');
  }

  /**
   * Clear current script (new blank editor)
   */
  public static clearCurrentScript(): void {
    localStorage.removeItem(STORAGE_KEYS.CURRENT);
    console.log('[Clear] Current script cleared');
  }

  /**
   * Mark script as favorite
   */
  public static toggleFavorite(scriptId: string): boolean {
    const scripts = this.getAllScriptsInternal();
    const script = scripts.find((s) => s.id === scriptId);

    if (!script) {
      return false;
    }

    script.isFavorite = !script.isFavorite;
    script.lastModified = new Date();

    localStorage.setItem(STORAGE_KEYS.SCRIPTS, JSON.stringify(scripts));

    // Update current script if it's the one being toggled
    const current = this.restoreLastSession();
    if (current?.id === scriptId) {
      localStorage.setItem(STORAGE_KEYS.CURRENT, JSON.stringify(script));
    }

    return script.isFavorite;
  }

  /**
   * Export scripts to JSON
   */
  public static exportScripts(scriptIds?: string[]): string {
    let scripts = this.getAllScriptsInternal();

    if (scriptIds && scriptIds.length > 0) {
      scripts = scripts.filter((s) => scriptIds.includes(s.id));
    }

    return JSON.stringify(scripts, null, 2);
  }

  /**
   * Import scripts from JSON
   */
  public static importScripts(jsonData: string, overwriteExisting: boolean = false): number {
    try {
      const importedScripts = JSON.parse(jsonData) as SavedScript[];
      const existingScripts = this.getAllScriptsInternal();

      let importCount = 0;

      for (const imported of importedScripts) {
        // Convert date strings to Date objects
        imported.createdAt = new Date(imported.createdAt);
        imported.lastModified = new Date(imported.lastModified);

        const existingIndex = existingScripts.findIndex((s) => s.id === imported.id);

        if (existingIndex >= 0) {
          if (overwriteExisting) {
            existingScripts[existingIndex] = imported;
            importCount++;
          }
          // else skip
        } else {
          existingScripts.push(imported);
          importCount++;
        }
      }

      localStorage.setItem(STORAGE_KEYS.SCRIPTS, JSON.stringify(existingScripts));

      console.log('[Import] Imported', importCount, 'scripts');

      return importCount;
    } catch (error) {
      console.error('[Import] Failed to import scripts:', error);
      throw error;
    }
  }

  /**
   * Get storage usage statistics
   */
  public static getStorageStats(): {
    totalScripts: number;
    manualScripts: number;
    autoSavedScripts: number;
    totalSizeBytes: number;
    estimatedStorageUsed: string;
  } {
    const scripts = this.getAllScriptsInternal();
    const manualScripts = scripts.filter((s) => !s.autoSaved);
    const autoSavedScripts = scripts.filter((s) => s.autoSaved);

    const totalSizeBytes = scripts.reduce((sum, s) => sum + s.content.length, 0);

    // Estimate total localStorage usage for our keys
    let totalStorageBytes = 0;
    for (const key of Object.values(STORAGE_KEYS)) {
      const item = localStorage.getItem(key);
      if (item) {
        totalStorageBytes += item.length;
      }
    }

    return {
      totalScripts: scripts.length,
      manualScripts: manualScripts.length,
      autoSavedScripts: autoSavedScripts.length,
      totalSizeBytes,
      estimatedStorageUsed: this.formatBytes(totalStorageBytes),
    };
  }

  /**
   * Private: Get all scripts from localStorage (internal use)
   */
  private static getAllScriptsInternal(): SavedScript[] {
    const stored = localStorage.getItem(STORAGE_KEYS.SCRIPTS);
    if (!stored) {
      return [];
    }

    try {
      const scripts = JSON.parse(stored) as SavedScript[];

      // Convert date strings back to Date objects
      for (const script of scripts) {
        script.createdAt = new Date(script.createdAt);
        script.lastModified = new Date(script.lastModified);
      }

      return scripts;
    } catch (error) {
      console.error('[GetScriptsInternal] Failed to parse scripts:', error);
      return [];
    }
  }

  /**
   * Private: Generate unique ID for new scripts
   */
  private static generateId(): string {
    return `script-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  }

  /**
   * Private: Clean up old auto-saves
   * Keep only the most recent N auto-saves
   */
  private static cleanupAutoSaves(): void {
    const config = this.getConfig();
    const scripts = this.getAllScriptsInternal();
    const autoSaves = scripts.filter((s) => s.autoSaved).sort((a, b) => b.lastModified.getTime() - a.lastModified.getTime());

    if (autoSaves.length > config.maxAutoSaveCount) {
      const toKeep = autoSaves.slice(0, config.maxAutoSaveCount);
      const toKeepIds = new Set(toKeep.map((s) => s.id));

      const filteredScripts = scripts.filter((s) => !s.autoSaved || toKeepIds.has(s.id));

      localStorage.setItem(STORAGE_KEYS.SCRIPTS, JSON.stringify(filteredScripts));

      console.log('[Cleanup] Removed', autoSaves.length - config.maxAutoSaveCount, 'old auto-saves');
    }
  }

  /**
   * Private: Format bytes to human-readable string
   */
  private static formatBytes(bytes: number): string {
    if (bytes === 0) {
      return '0 Bytes';
    }

    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));

    return Math.round((bytes / Math.pow(k, i)) * 100) / 100 + ' ' + sizes[i];
  }
}

// Initialize on module load
AutoSaveService.initialize();
