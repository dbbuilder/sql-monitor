/**
 * TabStateService
 *
 * Manages editor tab state, persistence, and navigation.
 * Features:
 * - Tab state persistence to localStorage
 * - Tab ordering and pinning
 * - Recent files tracking
 * - LRU (Least Recently Used) management
 */

/**
 * Tab state interface
 */
export interface TabState {
  /** Unique tab identifier */
  id: string;

  /** Tab type */
  type: 'untitled' | 'script' | 'object';

  /** Display title */
  title: string;

  /** Server ID (for database objects) */
  serverId?: number;

  /** Server name (for display) */
  serverName?: string;

  /** Database name (for database objects) */
  databaseName?: string;

  /** Schema name (for database objects) */
  schemaName?: string;

  /** Object name (for database objects) */
  objectName?: string;

  /** Object type (for database objects) */
  objectType?: 'table' | 'view' | 'procedure' | 'function';

  /** Script ID (for saved scripts) */
  scriptId?: string;

  /** Code content */
  content: string;

  /** Cursor position */
  cursorPosition: { line: number; column: number };

  /** Scroll position */
  scrollPosition: number;

  /** Whether tab is pinned */
  isPinned: boolean;

  /** Whether tab has unsaved changes */
  isModified: boolean;

  /** Last accessed timestamp */
  lastAccessedAt: Date;
}

/**
 * Editor state interface
 */
export interface EditorState {
  /** All open tabs */
  tabs: TabState[];

  /** Index of active tab */
  activeTabIndex: number;

  /** Split mode */
  splitMode: 'single' | 'vertical' | 'horizontal' | 'grid';

  /** Split pane sizes (percentages) */
  splitSizes: number[];

  /** Active pane index (for split mode) */
  activePaneIndex: number;
}

/**
 * Storage keys
 */
const STORAGE_KEYS = {
  EDITOR_STATE: 'sqlmonitor-editor-state',
  RECENT_FILES: 'sqlmonitor-recent-files',
} as const;

/**
 * Default editor state
 */
const DEFAULT_EDITOR_STATE: EditorState = {
  tabs: [],
  activeTabIndex: -1,
  splitMode: 'single',
  splitSizes: [50, 50],
  activePaneIndex: 0,
};

/**
 * Maximum number of recent files to track
 */
const MAX_RECENT_FILES = 10;

/**
 * TabStateService class
 */
export class TabStateService {
  private static editorState: EditorState = DEFAULT_EDITOR_STATE;
  private static nextUntitledNumber = 1;

  /**
   * Initialize the service
   */
  public static initialize(): void {
    const stored = localStorage.getItem(STORAGE_KEYS.EDITOR_STATE);
    if (stored) {
      try {
        const parsed = JSON.parse(stored) as EditorState;

        // Convert date strings back to Date objects
        parsed.tabs.forEach((tab) => {
          tab.lastAccessedAt = new Date(tab.lastAccessedAt);
        });

        this.editorState = parsed;
        console.log('[TabState] Restored editor state:', this.editorState.tabs.length, 'tabs');
      } catch (error) {
        console.error('[TabState] Failed to parse editor state:', error);
        this.editorState = DEFAULT_EDITOR_STATE;
      }
    }
  }

  /**
   * Get current editor state
   */
  public static getState(): EditorState {
    return { ...this.editorState };
  }

  /**
   * Get all tabs
   */
  public static getTabs(): TabState[] {
    return [...this.editorState.tabs];
  }

  /**
   * Get active tab
   */
  public static getActiveTab(): TabState | null {
    if (this.editorState.activeTabIndex < 0 || this.editorState.activeTabIndex >= this.editorState.tabs.length) {
      return null;
    }
    return this.editorState.tabs[this.editorState.activeTabIndex];
  }

  /**
   * Get tab by ID
   */
  public static getTabById(id: string): TabState | null {
    return this.editorState.tabs.find((tab) => tab.id === id) || null;
  }

  /**
   * Create new untitled tab
   */
  public static createUntitledTab(): TabState {
    const tab: TabState = {
      id: `untitled-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
      type: 'untitled',
      title: `Untitled-${this.nextUntitledNumber++}`,
      content: '',
      cursorPosition: { line: 1, column: 1 },
      scrollPosition: 0,
      isPinned: false,
      isModified: false,
      lastAccessedAt: new Date(),
    };

    this.addTab(tab);
    return tab;
  }

  /**
   * Create tab for database object
   */
  public static createObjectTab(
    serverId: number,
    serverName: string,
    databaseName: string,
    schemaName: string,
    objectName: string,
    objectType: 'table' | 'view' | 'procedure' | 'function',
    content: string
  ): TabState {
    const fullyQualifiedName = `${schemaName}.${objectName}`;

    // Check if tab already exists
    const existingTab = this.editorState.tabs.find(
      (tab) =>
        tab.type === 'object' &&
        tab.serverId === serverId &&
        tab.databaseName === databaseName &&
        tab.objectName === fullyQualifiedName
    );

    if (existingTab) {
      // Activate existing tab
      this.setActiveTab(existingTab.id);
      return existingTab;
    }

    // Create new tab
    const tab: TabState = {
      id: `object-${serverId}-${databaseName}-${fullyQualifiedName}-${Date.now()}`,
      type: 'object',
      title: fullyQualifiedName,
      serverId,
      serverName,
      databaseName,
      schemaName,
      objectName: fullyQualifiedName,
      objectType,
      content,
      cursorPosition: { line: 1, column: 1 },
      scrollPosition: 0,
      isPinned: false,
      isModified: false,
      lastAccessedAt: new Date(),
    };

    this.addTab(tab);
    this.addToRecentFiles(tab);
    return tab;
  }

  /**
   * Create tab for saved script
   */
  public static createScriptTab(scriptId: string, title: string, content: string): TabState {
    // Check if tab already exists
    const existingTab = this.editorState.tabs.find(
      (tab) => tab.type === 'script' && tab.scriptId === scriptId
    );

    if (existingTab) {
      // Activate existing tab
      this.setActiveTab(existingTab.id);
      return existingTab;
    }

    // Create new tab
    const tab: TabState = {
      id: `script-${scriptId}-${Date.now()}`,
      type: 'script',
      title,
      scriptId,
      content,
      cursorPosition: { line: 1, column: 1 },
      scrollPosition: 0,
      isPinned: false,
      isModified: false,
      lastAccessedAt: new Date(),
    };

    this.addTab(tab);
    this.addToRecentFiles(tab);
    return tab;
  }

  /**
   * Add tab to editor state
   */
  private static addTab(tab: TabState): void {
    this.editorState.tabs.push(tab);
    this.editorState.activeTabIndex = this.editorState.tabs.length - 1;
    this.persist();
  }

  /**
   * Close tab by ID
   */
  public static closeTab(id: string): void {
    const index = this.editorState.tabs.findIndex((tab) => tab.id === id);
    if (index < 0) {
      return;
    }

    // Remove tab
    this.editorState.tabs.splice(index, 1);

    // Update active index
    if (this.editorState.activeTabIndex >= this.editorState.tabs.length) {
      this.editorState.activeTabIndex = this.editorState.tabs.length - 1;
    }

    this.persist();
  }

  /**
   * Close all tabs
   */
  public static closeAllTabs(): void {
    this.editorState.tabs = [];
    this.editorState.activeTabIndex = -1;
    this.persist();
  }

  /**
   * Close other tabs (except specified tab)
   */
  public static closeOtherTabs(id: string): void {
    const tab = this.editorState.tabs.find((t) => t.id === id);
    if (!tab) {
      return;
    }

    this.editorState.tabs = [tab];
    this.editorState.activeTabIndex = 0;
    this.persist();
  }

  /**
   * Close tabs to the right
   */
  public static closeTabsToRight(id: string): void {
    const index = this.editorState.tabs.findIndex((tab) => tab.id === id);
    if (index < 0) {
      return;
    }

    this.editorState.tabs = this.editorState.tabs.slice(0, index + 1);

    // Update active index
    if (this.editorState.activeTabIndex > index) {
      this.editorState.activeTabIndex = index;
    }

    this.persist();
  }

  /**
   * Set active tab by ID
   */
  public static setActiveTab(id: string): void {
    const index = this.editorState.tabs.findIndex((tab) => tab.id === id);
    if (index < 0) {
      return;
    }

    this.editorState.activeTabIndex = index;
    this.editorState.tabs[index].lastAccessedAt = new Date();
    this.persist();
  }

  /**
   * Pin/unpin tab
   */
  public static togglePinTab(id: string): void {
    const tab = this.editorState.tabs.find((t) => t.id === id);
    if (!tab) {
      return;
    }

    tab.isPinned = !tab.isPinned;
    this.persist();
  }

  /**
   * Update tab content
   */
  public static updateTabContent(id: string, content: string, cursorPosition?: { line: number; column: number }): void {
    const tab = this.editorState.tabs.find((t) => t.id === id);
    if (!tab) {
      return;
    }

    tab.content = content;
    tab.isModified = true;
    tab.lastAccessedAt = new Date();

    if (cursorPosition) {
      tab.cursorPosition = cursorPosition;
    }

    this.persist();
  }

  /**
   * Mark tab as saved
   */
  public static markTabAsSaved(id: string): void {
    const tab = this.editorState.tabs.find((t) => t.id === id);
    if (!tab) {
      return;
    }

    tab.isModified = false;
    this.persist();
  }

  /**
   * Reorder tabs
   */
  public static moveTab(fromIndex: number, toIndex: number): void {
    if (fromIndex < 0 || fromIndex >= this.editorState.tabs.length) {
      return;
    }
    if (toIndex < 0 || toIndex >= this.editorState.tabs.length) {
      return;
    }

    const [tab] = this.editorState.tabs.splice(fromIndex, 1);
    this.editorState.tabs.splice(toIndex, 0, tab);

    // Update active index
    if (this.editorState.activeTabIndex === fromIndex) {
      this.editorState.activeTabIndex = toIndex;
    } else if (fromIndex < this.editorState.activeTabIndex && toIndex >= this.editorState.activeTabIndex) {
      this.editorState.activeTabIndex--;
    } else if (fromIndex > this.editorState.activeTabIndex && toIndex <= this.editorState.activeTabIndex) {
      this.editorState.activeTabIndex++;
    }

    this.persist();
  }

  /**
   * Get recent files
   */
  public static getRecentFiles(): TabState[] {
    const stored = localStorage.getItem(STORAGE_KEYS.RECENT_FILES);
    if (!stored) {
      return [];
    }

    try {
      const files = JSON.parse(stored) as TabState[];
      files.forEach((file) => {
        file.lastAccessedAt = new Date(file.lastAccessedAt);
      });
      return files;
    } catch (error) {
      console.error('[TabState] Failed to parse recent files:', error);
      return [];
    }
  }

  /**
   * Add to recent files
   */
  private static addToRecentFiles(tab: TabState): void {
    const recent = this.getRecentFiles();

    // Remove existing entry if present
    const existingIndex = recent.findIndex(
      (file) =>
        file.type === tab.type &&
        ((tab.type === 'script' && file.scriptId === tab.scriptId) ||
          (tab.type === 'object' &&
            file.serverId === tab.serverId &&
            file.databaseName === tab.databaseName &&
            file.objectName === tab.objectName))
    );

    if (existingIndex >= 0) {
      recent.splice(existingIndex, 1);
    }

    // Add to front
    recent.unshift({
      ...tab,
      lastAccessedAt: new Date(),
    });

    // Keep only MAX_RECENT_FILES
    const trimmed = recent.slice(0, MAX_RECENT_FILES);

    localStorage.setItem(STORAGE_KEYS.RECENT_FILES, JSON.stringify(trimmed));
  }

  /**
   * Persist editor state to localStorage
   */
  private static persist(): void {
    try {
      localStorage.setItem(STORAGE_KEYS.EDITOR_STATE, JSON.stringify(this.editorState));
    } catch (error) {
      console.error('[TabState] Failed to persist editor state:', error);
    }
  }

  /**
   * Clear all state (for testing/debugging)
   */
  public static clear(): void {
    this.editorState = DEFAULT_EDITOR_STATE;
    localStorage.removeItem(STORAGE_KEYS.EDITOR_STATE);
    localStorage.removeItem(STORAGE_KEYS.RECENT_FILES);
  }
}

// Initialize on module load
TabStateService.initialize();
