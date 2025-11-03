/**
 * Settings Service
 *
 * Centralized service for managing plugin configuration settings.
 * Loads settings from localStorage and provides type-safe access.
 *
 * Week 5 Day 18 implementation
 */

/**
 * Plugin settings interface
 */
export interface PluginSettings {
  // Editor settings
  editorFontSize: number;
  editorTabSize: number;
  editorLineNumbers: boolean;
  editorMinimap: boolean;
  editorWordWrap: boolean;

  // Auto-save settings
  autoSaveEnabled: boolean;
  autoSaveDelayMs: number;

  // Query execution settings
  queryTimeoutSeconds: number;
  maxRowsPerPage: number;

  // Analysis settings
  analysisAutoRun: boolean;
  disabledRules: string[];

  // UI settings
  showObjectBrowserByDefault: boolean;
  showAnalysisPanelByDefault: boolean;
}

/**
 * Default settings
 */
export const DEFAULT_SETTINGS: PluginSettings = {
  // Editor settings
  editorFontSize: 14,
  editorTabSize: 4,
  editorLineNumbers: true,
  editorMinimap: true,
  editorWordWrap: false,

  // Auto-save settings
  autoSaveEnabled: true,
  autoSaveDelayMs: 5000,

  // Query execution settings
  queryTimeoutSeconds: 60,
  maxRowsPerPage: 50,

  // Analysis settings
  analysisAutoRun: true,
  disabledRules: [],

  // UI settings
  showObjectBrowserByDefault: true,
  showAnalysisPanelByDefault: true,
};

/**
 * Settings change listener callback
 */
type SettingsChangeListener = (settings: PluginSettings) => void;

/**
 * Settings Service
 *
 * Singleton service for managing plugin configuration.
 */
export class SettingsService {
  private static instance: SettingsService;
  private static readonly STORAGE_KEY = 'sqlmonitor-codeeditor-settings';
  private settings: PluginSettings;
  private listeners: SettingsChangeListener[] = [];
  private pendingSave: Promise<void> | null = null;
  private saveQueue: Array<() => void> = [];

  private constructor() {
    this.settings = this.loadSettings();
    console.log('[SettingsService] Initialized with settings:', this.settings);
  }

  /**
   * Get singleton instance
   */
  public static getInstance(): SettingsService {
    if (!SettingsService.instance) {
      SettingsService.instance = new SettingsService();
    }
    return SettingsService.instance;
  }

  /**
   * Get current settings
   */
  public getSettings(): PluginSettings {
    return { ...this.settings };
  }

  /**
   * Get specific setting value
   */
  public getSetting<K extends keyof PluginSettings>(key: K): PluginSettings[K] {
    return this.settings[key];
  }

  /**
   * Update settings (async to prevent race conditions)
   * Code Optimization: Fix race condition from code review
   */
  public async updateSettings(updates: Partial<PluginSettings>): Promise<void> {
    console.log('[SettingsService] Updating settings:', updates);

    // Wait for any pending save to complete
    if (this.pendingSave) {
      console.log('[SettingsService] Waiting for pending save to complete');
      await this.pendingSave;
    }

    // Update settings
    this.settings = {
      ...this.settings,
      ...updates,
    };

    // Save to storage (with queue management)
    await this.saveSettingsAsync();

    // Notify listeners after save completes
    this.notifyListeners();
  }

  /**
   * Reset to default settings (async to prevent race conditions)
   */
  public async resetToDefaults(): Promise<void> {
    console.log('[SettingsService] Resetting to default settings');

    // Wait for any pending save to complete
    if (this.pendingSave) {
      await this.pendingSave;
    }

    this.settings = { ...DEFAULT_SETTINGS };
    await this.saveSettingsAsync();
    this.notifyListeners();
  }

  /**
   * Check if a specific analysis rule is enabled
   */
  public isRuleEnabled(ruleId: string): boolean {
    return !this.settings.disabledRules.includes(ruleId);
  }

  /**
   * Enable specific analysis rule (async to prevent race conditions)
   */
  public async enableRule(ruleId: string): Promise<void> {
    if (this.isRuleEnabled(ruleId)) {
      return; // Already enabled
    }

    console.log('[SettingsService] Enabling rule:', ruleId);

    // Wait for any pending save
    if (this.pendingSave) {
      await this.pendingSave;
    }

    this.settings.disabledRules = this.settings.disabledRules.filter((id) => id !== ruleId);
    await this.saveSettingsAsync();
    this.notifyListeners();
  }

  /**
   * Disable specific analysis rule (async to prevent race conditions)
   */
  public async disableRule(ruleId: string): Promise<void> {
    if (!this.isRuleEnabled(ruleId)) {
      return; // Already disabled
    }

    console.log('[SettingsService] Disabling rule:', ruleId);

    // Wait for any pending save
    if (this.pendingSave) {
      await this.pendingSave;
    }

    this.settings.disabledRules = [...this.settings.disabledRules, ruleId];
    await this.saveSettingsAsync();
    this.notifyListeners();
  }

  /**
   * Subscribe to settings changes
   */
  public subscribe(listener: SettingsChangeListener): () => void {
    console.log('[SettingsService] Adding settings change listener');

    this.listeners.push(listener);

    // Return unsubscribe function
    return () => {
      console.log('[SettingsService] Removing settings change listener');
      this.listeners = this.listeners.filter((l) => l !== listener);
    };
  }

  /**
   * Export settings to JSON
   */
  public exportSettings(): string {
    return JSON.stringify(this.settings, null, 2);
  }

  /**
   * Import settings from JSON (async to prevent race conditions)
   */
  public async importSettings(json: string): Promise<void> {
    try {
      const imported = JSON.parse(json);

      // Validate imported settings
      if (typeof imported !== 'object' || imported === null) {
        throw new Error('Invalid settings format');
      }

      console.log('[SettingsService] Importing settings:', imported);

      // Wait for any pending save
      if (this.pendingSave) {
        await this.pendingSave;
      }

      // Merge with defaults to ensure all keys exist
      this.settings = {
        ...DEFAULT_SETTINGS,
        ...imported,
      };

      await this.saveSettingsAsync();
      this.notifyListeners();

      console.log('[SettingsService] Settings imported successfully');
    } catch (error) {
      console.error('[SettingsService] Failed to import settings:', error);
      throw new Error('Failed to import settings. Please check the file format.');
    }
  }

  /**
   * Load settings from localStorage
   */
  private loadSettings(): PluginSettings {
    try {
      const stored = localStorage.getItem(SettingsService.STORAGE_KEY);

      if (stored) {
        const parsed = JSON.parse(stored);
        console.log('[SettingsService] Loaded settings from localStorage');

        // Merge with defaults to handle new settings added in updates
        return {
          ...DEFAULT_SETTINGS,
          ...parsed,
        };
      }
    } catch (error) {
      console.error('[SettingsService] Failed to load settings from localStorage:', error);
    }

    console.log('[SettingsService] Using default settings');
    return { ...DEFAULT_SETTINGS };
  }

  /**
   * Save settings to localStorage (async with queue management)
   * Code Optimization: Prevents race conditions from concurrent saves
   */
  private async saveSettingsAsync(): Promise<void> {
    // Create the save operation
    const saveOperation = async () => {
      try {
        localStorage.setItem(SettingsService.STORAGE_KEY, JSON.stringify(this.settings));
        console.log('[SettingsService] Settings saved to localStorage');
      } catch (error) {
        console.error('[SettingsService] Failed to save settings to localStorage:', error);
        throw error;
      }
    };

    // If no pending save, start immediately
    if (!this.pendingSave) {
      this.pendingSave = saveOperation().finally(() => {
        this.pendingSave = null;

        // Process any queued saves
        if (this.saveQueue.length > 0) {
          const nextSave = this.saveQueue.shift();
          if (nextSave) {
            nextSave();
          }
        }
      });

      return this.pendingSave;
    }

    // Queue this save if one is already pending
    return new Promise<void>((resolve, reject) => {
      this.saveQueue.push(async () => {
        try {
          await this.saveSettingsAsync();
          resolve();
        } catch (error) {
          reject(error);
        }
      });
    });
  }

  /**
   * Save settings to localStorage (synchronous, for backward compatibility)
   * @deprecated Use saveSettingsAsync instead
   */
  private saveSettings(): void {
    try {
      localStorage.setItem(SettingsService.STORAGE_KEY, JSON.stringify(this.settings));
      console.log('[SettingsService] Settings saved to localStorage (sync)');
    } catch (error) {
      console.error('[SettingsService] Failed to save settings to localStorage:', error);
    }
  }

  /**
   * Notify all listeners of settings change
   */
  private notifyListeners(): void {
    console.log('[SettingsService] Notifying', this.listeners.length, 'listeners of settings change');

    this.listeners.forEach((listener) => {
      try {
        listener(this.getSettings());
      } catch (error) {
        console.error('[SettingsService] Listener error:', error);
      }
    });
  }
}

/**
 * Singleton instance export
 */
export const settingsService = SettingsService.getInstance();
