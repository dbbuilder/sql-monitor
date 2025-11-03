/**
 * CodeEditorPage
 *
 * Main code editor page with:
 * - Toolbar (Run, Save, Format, Settings)
 * - Editor panel (Monaco editor - will be added in Week 1 Day 3)
 * - Analysis panel (Results sidebar)
 * - Results panel (Query results grid)
 * - Auto-save integration
 *
 * Week 5 Day 18: Integrated with SettingsService
 */

import React, { useState, useEffect, useCallback, useRef } from 'react';
import { css } from '@emotion/css';
import { GrafanaTheme2 } from '@grafana/data';
import { useStyles2, Button, Select, Icon, Tooltip } from '@grafana/ui';
import { useSearchParams } from 'react-router-dom';
import { AutoSaveService } from '../../services/autoSaveService';
import { TabStateService, TabState } from '../../services/tabStateService';
import { analysisEngine } from '../../services/codeAnalysisService';
import '../../services/rules'; // Auto-initializes all 41 analysis rules
import { sqlMonitorApiClient } from '../../services/sqlMonitorApiClient';
import { settingsService } from '../../services/settingsService';
import { EditorPanel } from './EditorPanel';
import { TabBar } from './TabBar';
import { KeyboardShortcutsHelp } from './KeyboardShortcutsHelp';
import { QuickOpenDialog, QuickOpenItem } from './QuickOpenDialog';
import { ObjectBrowser, TreeNode } from './ObjectBrowser';
import { ResultsGrid } from './ResultsGrid';
import type { SavedScript } from '../../types/savedScript';
import type { ServerInfo, QueryExecutionResult } from '../../types/query';
import type { AnalysisResult } from '../../types/analysis';
import type * as monacoEditor from 'monaco-editor';

/**
 * Component state interface
 */
interface CodeEditorState {
  /** All open tabs */
  tabs: TabState[];
  /** Index of active tab */
  activeTabIndex: number;
  /** Selected server for execution */
  selectedServerId: number | null;
  /** Selected database for execution */
  selectedDatabase: string | null;
  /** Analysis results */
  analysisResults: AnalysisResult[];
  /** Whether analysis is running */
  isAnalyzing: boolean;
  /** Whether query is executing */
  isExecuting: boolean;
  /** Current query result */
  queryResult: QueryExecutionResult | null;
  /** Query execution history (last 10) */
  executionHistory: QueryExecutionResult[];
}

/**
 * CodeEditorPage component
 */
export const CodeEditorPage: React.FC = () => {
  const styles = useStyles2(getStyles);
  const editorRef = useRef<monacoEditor.editor.IStandaloneCodeEditor | null>(null);
  const [searchParams, setSearchParams] = useSearchParams();

  // State
  const [state, setState] = useState<CodeEditorState>({
    tabs: TabStateService.getTabs(),
    activeTabIndex: TabStateService.getState().activeTabIndex,
    selectedServerId: null,
    selectedDatabase: null,
    analysisResults: [],
    isAnalyzing: false,
    isExecuting: false,
    queryResult: null,
    executionHistory: [],
  });

  // Server and database lists
  const [servers, setServers] = useState<ServerInfo[]>([]);
  const [databases, setDatabases] = useState<string[]>([]);

  // Dialog states
  const [showKeyboardShortcuts, setShowKeyboardShortcuts] = useState(false);
  const [showQuickOpen, setShowQuickOpen] = useState(false);
  const [showObjectBrowser, setShowObjectBrowser] = useState(
    settingsService.getSetting('showObjectBrowserByDefault')
  );

  // Get active tab
  const activeTab = state.activeTabIndex >= 0 ? state.tabs[state.activeTabIndex] : null;

  /**
   * Load settings on mount and subscribe to changes (Week 5 Day 18)
   */
  useEffect(() => {
    console.log('[CodeEditorPage] Loading settings from service');

    // Load initial settings
    const settings = settingsService.getSettings();
    setShowObjectBrowser(settings.showObjectBrowserByDefault);

    // Subscribe to settings changes
    const unsubscribe = settingsService.subscribe((updatedSettings) => {
      console.log('[CodeEditorPage] Settings updated, applying changes');
      setShowObjectBrowser(updatedSettings.showObjectBrowserByDefault);
    });

    return unsubscribe;
  }, []);

  /**
   * Load servers on mount
   */
  useEffect(() => {
    const loadServers = async () => {
      try {
        const serverList = await sqlMonitorApiClient.getServers();
        setServers(serverList);

        // Auto-select first server
        if (serverList.length > 0 && !state.selectedServerId) {
          setState((prev) => ({ ...prev, selectedServerId: serverList[0].serverId }));
        }

        console.log('[CodeEditor] Loaded servers:', serverList.length);
      } catch (error) {
        console.error('[CodeEditor] Failed to load servers:', error);
      }
    };

    loadServers();
  }, []);

  /**
   * Load databases when server selection changes
   */
  useEffect(() => {
    if (!state.selectedServerId) {
      setDatabases([]);
      return;
    }

    const loadDatabases = async () => {
      try {
        const dbList = await sqlMonitorApiClient.getDatabases(state.selectedServerId!);
        setDatabases(dbList);

        // Auto-select first database
        if (dbList.length > 0 && !state.selectedDatabase) {
          setState((prev) => ({ ...prev, selectedDatabase: dbList[0] }));
        }

        console.log('[CodeEditor] Loaded databases:', dbList.length);
      } catch (error) {
        console.error('[CodeEditor] Failed to load databases:', error);
      }
    };

    loadDatabases();
  }, [state.selectedServerId]);

  /**
   * Initialize: Handle URL parameters and load object/script
   */
  useEffect(() => {
    const server = searchParams.get('server');
    const db = searchParams.get('db');
    const object = searchParams.get('object');
    const scriptId = searchParams.get('script');
    const line = searchParams.get('line');

    if (scriptId) {
      // Load saved script by ID
      const script = AutoSaveService.getScriptById(scriptId);
      if (script) {
        const tab = TabStateService.createScriptTab(scriptId, script.name, script.content);
        updateTabsState();
        console.log('[CodeEditor] Loaded script from URL:', script.name);
      }
    } else if (server && db && object) {
      // Load database object
      // TODO: Week 3 - Fetch object code from API
      // For now, create a placeholder tab
      const serverId = parseInt(server);
      const [schema, objectName] = object.includes('.') ? object.split('.') : ['dbo', object];

      const tab = TabStateService.createObjectTab(
        serverId,
        `Server${serverId}`, // Placeholder
        db,
        schema,
        objectName,
        'procedure', // Default to procedure
        `-- Loading ${object}...\n-- (Week 3: Will fetch from API)`
      );

      updateTabsState();
      console.log('[CodeEditor] Loaded object from URL:', object);

      // Jump to line if specified
      if (line && editorRef.current) {
        const lineNum = parseInt(line);
        editorRef.current.setPosition({ lineNumber: lineNum, column: 1 });
        editorRef.current.revealLineInCenter(lineNum);
      }
    } else if (state.tabs.length === 0) {
      // No URL parameters and no tabs - create first untitled tab
      TabStateService.createUntitledTab();
      updateTabsState();
      console.log('[CodeEditor] Created initial untitled tab');
    }
  }, [searchParams]);

  /**
   * Update tabs state from TabStateService
   */
  const updateTabsState = useCallback(() => {
    setState((prev) => ({
      ...prev,
      tabs: TabStateService.getTabs(),
      activeTabIndex: TabStateService.getState().activeTabIndex,
    }));
  }, []);

  /**
   * Auto-save: Save active tab to localStorage when code changes
   */
  useEffect(() => {
    if (activeTab && activeTab.content.trim()) {
      AutoSaveService.autoSave(activeTab.content, activeTab.scriptId, {
        name: activeTab.title,
        serverId: activeTab.serverId,
        databaseName: activeTab.databaseName,
      });
    }
  }, [activeTab?.content]);

  /**
   * Handle code change from editor
   */
  const handleCodeChange = useCallback((newCode: string) => {
    if (!activeTab) return;

    // Get cursor position from editor
    const cursorPosition = editorRef.current?.getPosition();

    // Update tab content in TabStateService
    TabStateService.updateTabContent(activeTab.id, newCode, cursorPosition ? {
      line: cursorPosition.lineNumber,
      column: cursorPosition.column
    } : undefined);

    updateTabsState();
  }, [activeTab, updateTabsState]);

  /**
   * Handle manual save (Ctrl+S)
   */
  const handleManualSave = useCallback(() => {
    if (!activeTab) return;

    const scriptName = activeTab.title !== 'Untitled Script' && !activeTab.title.startsWith('Untitled-')
      ? activeTab.title
      : prompt('Enter script name:', 'Untitled Script');

    if (!scriptName) {
      return;
    }

    const response = AutoSaveService.manualSave({
      id: activeTab.scriptId,
      name: scriptName,
      content: activeTab.content,
      serverId: activeTab.serverId,
      databaseName: activeTab.databaseName,
      autoSaved: false,
    });

    if (response.success && response.script) {
      // Mark tab as saved
      TabStateService.markTabAsSaved(activeTab.id);
      updateTabsState();
      console.log('[CodeEditor] Script saved:', scriptName);
    } else {
      console.error('[CodeEditor] Failed to save script:', response.error);
      alert(`Failed to save script: ${response.error}`);
    }
  }, [activeTab, updateTabsState]);

  /**
   * Handle Run Query (Ctrl+Enter, F5)
   * Week 3 Day 9-10 implementation
   */
  const handleRunQuery = useCallback(async () => {
    if (!activeTab || !activeTab.content.trim()) {
      alert('No query to execute');
      return;
    }

    // Validate server/database selection
    if (!state.selectedServerId) {
      alert('Please select a server');
      return;
    }

    if (!state.selectedDatabase) {
      alert('Please select a database');
      return;
    }

    console.log('[CodeEditor] Running query...', {
      serverId: state.selectedServerId,
      database: state.selectedDatabase,
      queryLength: activeTab.content.length,
    });

    setState((prev) => ({ ...prev, isExecuting: true }));

    try {
      // Execute query via API client (Week 5 Day 18: using timeout from settings)
      const queryTimeout = settingsService.getSetting('queryTimeoutSeconds');
      const result = await sqlMonitorApiClient.executeQuery({
        serverId: state.selectedServerId!,
        databaseName: state.selectedDatabase!,
        query: activeTab.content,
        timeoutSeconds: queryTimeout,
      });

      console.log('[CodeEditor] Query executed:', {
        success: result.success,
        executionTime: `${result.executionTimeMs}ms`,
        rowsAffected: result.rowsAffected,
        resultSets: result.resultSets?.length || 0,
      });

      // Update state with result
      setState((prev) => ({
        ...prev,
        isExecuting: false,
        queryResult: result,
        executionHistory: [result, ...prev.executionHistory].slice(0, 10), // Keep last 10
      }));

      // Show success notification for non-SELECT queries
      if (result.success && (!result.resultSets || result.resultSets.length === 0)) {
        alert(`Query executed successfully\n${result.messages?.join('\n') || 'No messages'}`);
      }
    } catch (error) {
      console.error('[CodeEditor] Query execution failed:', error);
      setState((prev) => ({ ...prev, isExecuting: false }));
      alert(`Query execution failed: ${error instanceof Error ? error.message : String(error)}`);
    }
  }, [activeTab, state.selectedServerId, state.selectedDatabase]);

  /**
   * Handle Analyze Code
   * Runs the analysis engine on the active tab's code
   */
  const handleAnalyze = useCallback(async () => {
    if (!activeTab || !activeTab.content.trim()) {
      return;
    }

    console.log('[CodeEditor] Running code analysis...');
    setState((prev) => ({ ...prev, isAnalyzing: true }));

    try {
      // Run analysis engine
      const { results, summary } = await analysisEngine.analyze(activeTab.content);

      console.log('[CodeEditor] Analysis complete:', {
        total: results.length,
        errors: summary.errorCount,
        warnings: summary.warningCount,
        info: summary.infoCount,
        executionTime: `${summary.executionTimeMs}ms`,
      });

      setState((prev) => ({
        ...prev,
        isAnalyzing: false,
        analysisResults: results,
      }));
    } catch (error) {
      console.error('[CodeEditor] Analysis failed:', error);
      setState((prev) => ({
        ...prev,
        isAnalyzing: false,
        analysisResults: [],
      }));
      alert(`Analysis failed: ${error instanceof Error ? error.message : String(error)}`);
    }
  }, [activeTab]);

  /**
   * Handle Format Code
   * Uses Monaco's built-in formatter (sql-formatter integration in next step)
   */
  const handleFormat = useCallback(() => {
    if (editorRef.current) {
      editorRef.current.getAction('editor.action.formatDocument')?.run();
      console.log('[CodeEditor] Code formatted');
    }
  }, []);

  /**
   * Handle New Script
   */
  const handleNewScript = useCallback(() => {
    TabStateService.createUntitledTab();
    updateTabsState();
  }, [updateTabsState]);

  /**
   * Handle tab click
   */
  const handleTabClick = useCallback((tabId: string) => {
    TabStateService.setActiveTab(tabId);
    updateTabsState();
  }, [updateTabsState]);

  /**
   * Handle tab close
   */
  const handleTabClose = useCallback((tabId: string) => {
    const tab = TabStateService.getTabById(tabId);
    if (!tab) return;

    // Check for unsaved changes
    if (tab.isModified) {
      const confirmed = confirm(`"${tab.title}" has unsaved changes. Close anyway?`);
      if (!confirmed) {
        return;
      }
    }

    TabStateService.closeTab(tabId);
    updateTabsState();
  }, [updateTabsState]);

  /**
   * Handle tab context menu actions
   */
  const handleTabContextAction = useCallback((tabId: string, action: string) => {
    switch (action) {
      case 'close':
        handleTabClose(tabId);
        break;
      case 'closeOthers':
        TabStateService.closeOtherTabs(tabId);
        updateTabsState();
        break;
      case 'closeAll':
        const confirmed = confirm('Close all tabs?');
        if (confirmed) {
          TabStateService.closeAllTabs();
          updateTabsState();
        }
        break;
      case 'closeToRight':
        TabStateService.closeTabsToRight(tabId);
        updateTabsState();
        break;
      case 'togglePin':
        TabStateService.togglePinTab(tabId);
        updateTabsState();
        break;
      case 'copyPath':
        const tab = TabStateService.getTabById(tabId);
        if (tab && tab.type === 'object') {
          const path = `${tab.serverName} / ${tab.databaseName} / ${tab.objectName}`;
          navigator.clipboard.writeText(path);
          console.log('[CodeEditor] Copied path:', path);
        }
        break;
      case 'revealInBrowser':
        // TODO: Week 2 - Reveal in object browser
        console.log('[CodeEditor] Reveal in browser (Week 2)');
        break;
      case 'splitRight':
        // TODO: Week 2 - Split editor
        console.log('[CodeEditor] Split right (Week 2)');
        break;
    }
  }, [handleTabClose, updateTabsState]);

  /**
   * Handle tab reorder
   */
  const handleTabReorder = useCallback((fromIndex: number, toIndex: number) => {
    TabStateService.moveTab(fromIndex, toIndex);
    updateTabsState();
  }, [updateTabsState]);

  /**
   * Handle editor ready
   */
  const handleEditorReady = useCallback((editor: monacoEditor.editor.IStandaloneCodeEditor) => {
    editorRef.current = editor;
    console.log('[CodeEditor] Monaco editor initialized');
  }, []);

  /**
   * Handle analysis result click - jump to line in editor
   */
  const handleAnalysisResultClick = useCallback((result: AnalysisResult) => {
    if (editorRef.current) {
      // Set cursor position
      editorRef.current.setPosition({
        lineNumber: result.line,
        column: result.column,
      });

      // Reveal line in center of editor
      editorRef.current.revealLineInCenter(result.line);

      // Focus editor
      editorRef.current.focus();

      console.log('[CodeEditor] Jumped to line:', result.line);
    }
  }, []);

  /**
   * Handle Quick Open item selection
   */
  const handleQuickOpenSelect = useCallback((item: QuickOpenItem) => {
    console.log('[CodeEditor] Quick Open selected:', item);

    if (item.type === 'script' && item.scriptId) {
      // Load saved script
      const script = AutoSaveService.getScriptById(item.scriptId);
      if (script) {
        TabStateService.createScriptTab(script.id, script.name, script.content);
        updateTabsState();
      }
    } else if (item.serverId && item.databaseName && item.objectName) {
      // Load database object
      // TODO: Week 3 - Fetch object code from API
      TabStateService.createObjectTab(
        item.serverId,
        item.serverName || `Server${item.serverId}`,
        item.databaseName,
        item.schemaName || 'dbo',
        item.objectName,
        item.type === 'table' ? 'table' : item.type === 'view' ? 'view' : item.type === 'function' ? 'function' : 'procedure',
        `-- Loading ${item.schemaName}.${item.objectName}...\n-- (Week 3: Will fetch from API)`
      );
      updateTabsState();
    }
  }, [updateTabsState]);

  /**
   * Handle Object Browser object open
   */
  const handleObjectBrowserOpen = useCallback((node: TreeNode) => {
    console.log('[CodeEditor] Object Browser opened:', node);

    if (node.serverId && node.databaseName && node.objectName) {
      // TODO: Week 3 - Fetch object code from API
      TabStateService.createObjectTab(
        node.serverId,
        node.serverName || `Server${node.serverId}`,
        node.databaseName,
        node.schemaName || 'dbo',
        node.objectName,
        node.objectType || 'procedure',
        `-- Loading ${node.schemaName}.${node.objectName}...\n-- (Week 3: Will fetch from API)`
      );
      updateTabsState();
    }
  }, [updateTabsState]);

  /**
   * Handle keyboard shortcuts from EditorPanel
   */
  const handleKeyboardShortcut = useCallback((action: string) => {
    switch (action) {
      case 'save':
        handleManualSave();
        break;
      case 'run':
        handleRunQuery();
        break;
      case 'format':
        handleFormat();
        break;
      case 'quickOpen':
        setShowQuickOpen(true);
        break;
      case 'showKeyboardShortcuts':
        setShowKeyboardShortcuts(true);
        break;
      default:
        console.log('[CodeEditor] Unknown keyboard shortcut:', action);
    }
  }, [handleManualSave, handleRunQuery, handleFormat]);

  return (
    <div className={styles.container}>
      {/* Tab Bar */}
      <TabBar
        tabs={state.tabs}
        activeTabIndex={state.activeTabIndex}
        onTabClick={handleTabClick}
        onTabClose={handleTabClose}
        onNewTab={handleNewScript}
        onTabContextAction={handleTabContextAction}
        onTabReorder={handleTabReorder}
      />

      {/* Toolbar */}
      <div className={styles.toolbar}>
        <div className={styles.toolbarLeft}>
          <Button
            icon="file-blank"
            variant="secondary"
            size="sm"
            onClick={handleNewScript}
            tooltip="New Script (Ctrl+N)"
          >
            New
          </Button>

          <Button
            icon="save"
            variant="secondary"
            size="sm"
            onClick={handleManualSave}
            disabled={!activeTab}
            tooltip="Save Script (Ctrl+S)"
          >
            Save
          </Button>

          <Button
            icon="play"
            variant="primary"
            size="sm"
            onClick={handleRunQuery}
            disabled={state.isExecuting || !activeTab || !activeTab.content.trim()}
            tooltip="Run Query (Ctrl+Enter or F5)"
          >
            {state.isExecuting ? 'Running...' : 'Run Query'}
          </Button>

          <Button
            icon="bolt"
            variant="secondary"
            size="sm"
            onClick={handleAnalyze}
            disabled={state.isAnalyzing || !activeTab || !activeTab.content.trim()}
            tooltip="Analyze Code"
          >
            {state.isAnalyzing ? 'Analyzing...' : 'Analyze'}
          </Button>

          <Button
            icon="brackets-curly"
            variant="secondary"
            size="sm"
            onClick={handleFormat}
            disabled={!activeTab || !activeTab.content.trim()}
            tooltip="Format Code (Ctrl+Shift+F)"
          >
            Format
          </Button>

          <Button
            icon="keyboard"
            variant="secondary"
            size="sm"
            onClick={() => setShowKeyboardShortcuts(true)}
            tooltip="Keyboard Shortcuts (Ctrl+K Ctrl+H)"
          >
            Shortcuts
          </Button>

          <Button
            icon={showObjectBrowser ? 'angle-double-left' : 'angle-double-right'}
            variant="secondary"
            size="sm"
            onClick={() => setShowObjectBrowser((prev) => !prev)}
            tooltip={showObjectBrowser ? 'Hide Object Browser' : 'Show Object Browser'}
          />
        </div>

        <div className={styles.toolbarRight}>
          {/* Server Selection */}
          <div className={styles.selectGroup}>
            <label className={styles.selectLabel}>Server:</label>
            <Select
              options={servers.map((s) => ({ label: s.serverName, value: s.serverId }))}
              value={state.selectedServerId}
              onChange={(option) => {
                setState((prev) => ({
                  ...prev,
                  selectedServerId: option.value!,
                  selectedDatabase: null, // Reset database when server changes
                }));
              }}
              placeholder="Select server..."
              width={25}
            />
          </div>

          {/* Database Selection */}
          <div className={styles.selectGroup}>
            <label className={styles.selectLabel}>Database:</label>
            <Select
              options={databases.map((db) => ({ label: db, value: db }))}
              value={state.selectedDatabase}
              onChange={(option) => {
                setState((prev) => ({ ...prev, selectedDatabase: option.value! }));
              }}
              placeholder="Select database..."
              width={25}
              disabled={!state.selectedServerId}
            />
          </div>

          {/* Unsaved Changes Indicator */}
          {activeTab && activeTab.isModified && (
            <Tooltip content="You have unsaved changes">
              <div className={styles.unsavedIndicator}>
                <Icon name="circle" size="xs" />
                <span>Unsaved changes</span>
              </div>
            </Tooltip>
          )}
        </div>
      </div>

      {/* Main Content Area */}
      <div className={styles.mainContent}>
        {/* Object Browser Sidebar (optional, toggle-able) */}
        {showObjectBrowser && (
          <div className={styles.objectBrowserPanel}>
            <ObjectBrowser
              onObjectOpen={handleObjectBrowserOpen}
              onObjectOpenInNewTab={handleObjectBrowserOpen}
            />
          </div>
        )}

        {/* Editor Panel (Monaco Editor) */}
        <div className={styles.editorPanel}>
          {activeTab ? (
            <EditorPanel
              key={activeTab.id}
              value={activeTab.content}
              onChange={handleCodeChange}
              onEditorReady={handleEditorReady}
              onKeyboardShortcut={handleKeyboardShortcut}
            />
          ) : (
            <div className={styles.noTabsMessage}>
              <Icon name="file-code-o" size="xxxl" />
              <h2>No tabs open</h2>
              <p>Click "New" to create a new script or open a saved script</p>
            </div>
          )}
        </div>

        {/* Analysis Results Panel (Sidebar) */}
        <div className={styles.analysisPanel}>
          <div className={styles.analysisPanelHeader}>
            <h3>Analysis Results</h3>
            <span className={styles.resultCount}>
              {state.analysisResults.length} {state.analysisResults.length === 1 ? 'issue' : 'issues'}
            </span>
          </div>
          <div className={styles.analysisPanelContent}>
            {state.analysisResults.length === 0 ? (
              <div className={styles.emptyState}>
                <Icon name="check-circle" size="xl" />
                <p>No issues found</p>
                <p className={styles.emptyStateHint}>Click "Analyze" to check your code</p>
              </div>
            ) : (
              <div className={styles.resultsList}>
                {state.analysisResults.map((result, index) => (
                  <div
                    key={index}
                    className={styles.resultItem}
                    onClick={() => handleAnalysisResultClick(result)}
                    title="Click to jump to line"
                  >
                    <div className={styles.resultHeader}>
                      <span className={`${styles.severity} ${styles[`severity${result.severity}`]}`}>
                        {result.severity}
                      </span>
                      <span className={styles.ruleId}>{result.ruleId}</span>
                    </div>
                    <div className={styles.resultMessage}>{result.message}</div>
                    <div className={styles.resultLocation}>
                      Line {result.line}, Column {result.column}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Results Panel (Query Results Grid) */}
      <div className={styles.resultsPanel}>
        <ResultsGrid result={state.queryResult} />
      </div>

      {/* Keyboard Shortcuts Help Dialog */}
      <KeyboardShortcutsHelp
        isOpen={showKeyboardShortcuts}
        onClose={() => setShowKeyboardShortcuts(false)}
      />

      {/* Quick Open Dialog (Ctrl+P) */}
      <QuickOpenDialog
        isOpen={showQuickOpen}
        onClose={() => setShowQuickOpen(false)}
        onSelect={handleQuickOpenSelect}
      />
    </div>
  );
};

/**
 * Component styles
 */
const getStyles = (theme: GrafanaTheme2) => ({
  container: css`
    display: flex;
    flex-direction: column;
    height: 100%;
    background-color: ${theme.colors.background.primary};
  `,

  toolbar: css`
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: ${theme.spacing(1.5)};
    background-color: ${theme.colors.background.secondary};
    border-bottom: 1px solid ${theme.colors.border.weak};
    gap: ${theme.spacing(1)};
  `,

  toolbarLeft: css`
    display: flex;
    gap: ${theme.spacing(1)};
    align-items: center;
  `,

  toolbarRight: css`
    display: flex;
    gap: ${theme.spacing(2)};
    align-items: center;
  `,

  selectGroup: css`
    display: flex;
    align-items: center;
    gap: ${theme.spacing(1)};
  `,

  selectLabel: css`
    font-size: ${theme.typography.bodySmall.fontSize};
    color: ${theme.colors.text.secondary};
    white-space: nowrap;
  `,

  unsavedIndicator: css`
    display: flex;
    align-items: center;
    gap: ${theme.spacing(0.5)};
    color: ${theme.colors.warning.text};
    font-size: ${theme.typography.bodySmall.fontSize};
    padding: ${theme.spacing(0.5, 1)};
    background-color: ${theme.colors.warning.transparent};
    border-radius: ${theme.shape.borderRadius()};
  `,

  mainContent: css`
    display: flex;
    flex: 1;
    overflow: hidden;
  `,

  objectBrowserPanel: css`
    width: 300px;
    display: flex;
    flex-direction: column;
    background-color: ${theme.colors.background.secondary};
    border-right: 1px solid ${theme.colors.border.weak};
    overflow: hidden;
  `,

  editorPanel: css`
    flex: 1;
    display: flex;
    flex-direction: column;
    border-right: 1px solid ${theme.colors.border.weak};
    overflow: hidden;
  `,

  noTabsMessage: css`
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    height: 100%;
    color: ${theme.colors.text.secondary};
    text-align: center;

    h2 {
      margin-top: ${theme.spacing(2)};
      font-size: ${theme.typography.h3.fontSize};
    }

    p {
      margin-top: ${theme.spacing(1)};
      color: ${theme.colors.text.disabled};
    }
  `,

  analysisPanel: css`
    width: 350px;
    display: flex;
    flex-direction: column;
    background-color: ${theme.colors.background.secondary};
    border-right: 1px solid ${theme.colors.border.weak};
  `,

  analysisPanelHeader: css`
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: ${theme.spacing(2)};
    border-bottom: 1px solid ${theme.colors.border.weak};

    h3 {
      margin: 0;
      font-size: ${theme.typography.h5.fontSize};
      font-weight: ${theme.typography.h5.fontWeight};
    }
  `,

  resultCount: css`
    font-size: ${theme.typography.bodySmall.fontSize};
    color: ${theme.colors.text.secondary};
    padding: ${theme.spacing(0.5, 1)};
    background-color: ${theme.colors.background.canvas};
    border-radius: ${theme.shape.borderRadius()};
  `,

  analysisPanelContent: css`
    flex: 1;
    overflow-y: auto;
    padding: ${theme.spacing(2)};
  `,

  emptyState: css`
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    height: 100%;
    color: ${theme.colors.text.secondary};
    text-align: center;

    p {
      margin: ${theme.spacing(1, 0)};
    }
  `,

  emptyStateHint: css`
    font-size: ${theme.typography.bodySmall.fontSize};
    color: ${theme.colors.text.disabled};
  `,

  resultsList: css`
    display: flex;
    flex-direction: column;
    gap: ${theme.spacing(1)};
  `,

  resultItem: css`
    padding: ${theme.spacing(1.5)};
    background-color: ${theme.colors.background.canvas};
    border-left: 3px solid ${theme.colors.border.medium};
    border-radius: ${theme.shape.borderRadius()};
    cursor: pointer;

    &:hover {
      background-color: ${theme.colors.emphasize(theme.colors.background.canvas, 0.03)};
    }
  `,

  resultHeader: css`
    display: flex;
    gap: ${theme.spacing(1)};
    align-items: center;
    margin-bottom: ${theme.spacing(0.5)};
  `,

  severity: css`
    font-size: ${theme.typography.bodySmall.fontSize};
    font-weight: ${theme.typography.fontWeightMedium};
    padding: ${theme.spacing(0.25, 0.75)};
    border-radius: ${theme.shape.borderRadius()};
    text-transform: uppercase;
  `,

  severityError: css`
    background-color: ${theme.colors.error.transparent};
    color: ${theme.colors.error.text};
  `,

  severityWarning: css`
    background-color: ${theme.colors.warning.transparent};
    color: ${theme.colors.warning.text};
  `,

  severityInfo: css`
    background-color: ${theme.colors.info.transparent};
    color: ${theme.colors.info.text};
  `,

  ruleId: css`
    font-size: ${theme.typography.bodySmall.fontSize};
    color: ${theme.colors.text.secondary};
    font-family: ${theme.typography.fontFamilyMonospace};
  `,

  resultMessage: css`
    font-size: ${theme.typography.body.fontSize};
    color: ${theme.colors.text.primary};
    margin-bottom: ${theme.spacing(0.5)};
  `,

  resultLocation: css`
    font-size: ${theme.typography.bodySmall.fontSize};
    color: ${theme.colors.text.secondary};
    font-family: ${theme.typography.fontFamilyMonospace};
  `,

  resultsPanel: css`
    height: 300px;
    display: flex;
    flex-direction: column;
    background-color: ${theme.colors.background.secondary};
    border-top: 1px solid ${theme.colors.border.weak};
  `,

  resultsPanelHeader: css`
    padding: ${theme.spacing(2)};
    border-bottom: 1px solid ${theme.colors.border.weak};

    h3 {
      margin: 0;
      font-size: ${theme.typography.h5.fontSize};
      font-weight: ${theme.typography.h5.fontWeight};
    }
  `,

  resultsPanelContent: css`
    flex: 1;
    overflow-y: auto;
    padding: ${theme.spacing(2)};
  `,
});
