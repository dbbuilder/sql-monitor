# Phase 3 Feature #7 - Nice-to-Have Features

**Purpose**: Document user experience enhancements and quality-of-life features for the T-SQL Code Editor

**Date**: 2025-11-02
**Status**: Design - To be implemented during Week 1-4

---

## Overview

This document catalogs "nice-to-have" features that significantly improve user experience without adding substantial complexity. These features make the code editor feel professional and polished.

**Implementation Priority**: HIGH - Include in initial 55-hour build
**Rationale**: Small investment (5-10 additional hours) for significant UX improvement

---

## 1. Auto-Save Functionality ⭐ CRITICAL

### Why Important
- Prevents data loss from browser crashes, accidental tab closes
- Reduces user anxiety ("Did I save my work?")
- Industry standard (VSCode, SSMS, all modern editors have it)

### Implementation Strategy

**Auto-Save to Browser localStorage**:
```typescript
// src/services/autoSaveService.ts
import { debounce } from 'lodash';

export interface SavedScript {
  id: string;
  name: string;
  content: string;
  serverId?: number;
  databaseName?: string;
  lastModified: Date;
  autoSaved: boolean;
}

export class AutoSaveService {
  private static STORAGE_KEY = 'sqlmonitor-autosave';
  private static CURRENT_SCRIPT_KEY = 'sqlmonitor-current-script';

  // Debounced auto-save (save 2 seconds after user stops typing)
  public static autoSave = debounce((content: string, scriptId?: string) => {
    const script: SavedScript = {
      id: scriptId || 'auto-save-temp',
      name: scriptId ? this.getScriptName(scriptId) : 'Unsaved Script',
      content,
      lastModified: new Date(),
      autoSaved: true
    };

    localStorage.setItem(this.CURRENT_SCRIPT_KEY, JSON.stringify(script));
    console.log('[Auto-Save] Script saved to localStorage');
  }, 2000);

  // Manual save (Ctrl+S)
  public static manualSave(script: SavedScript): void {
    script.autoSaved = false;
    script.lastModified = new Date();

    // Save to saved scripts list
    const scripts = this.getAllScripts();
    const existingIndex = scripts.findIndex(s => s.id === script.id);

    if (existingIndex >= 0) {
      scripts[existingIndex] = script;
    } else {
      scripts.push(script);
    }

    localStorage.setItem(this.STORAGE_KEY, JSON.stringify(scripts));
    localStorage.setItem(this.CURRENT_SCRIPT_KEY, JSON.stringify(script));

    console.log('[Manual Save] Script saved:', script.name);
  }

  // Restore last session
  public static restoreLastSession(): SavedScript | null {
    const stored = localStorage.getItem(this.CURRENT_SCRIPT_KEY);
    if (!stored) return null;

    try {
      const script = JSON.parse(stored) as SavedScript;
      console.log('[Restore] Loaded auto-saved script:', script.name);
      return script;
    } catch (error) {
      console.error('[Restore] Failed to parse saved script:', error);
      return null;
    }
  }

  // Get all saved scripts
  public static getAllScripts(): SavedScript[] {
    const stored = localStorage.getItem(this.STORAGE_KEY);
    if (!stored) return [];

    try {
      return JSON.parse(stored);
    } catch (error) {
      console.error('[Load] Failed to parse scripts:', error);
      return [];
    }
  }

  // Delete script
  public static deleteScript(scriptId: string): void {
    const scripts = this.getAllScripts().filter(s => s.id !== scriptId);
    localStorage.setItem(this.STORAGE_KEY, JSON.stringify(scripts));
  }

  // Clear auto-save
  public static clearAutoSave(): void {
    localStorage.removeItem(this.CURRENT_SCRIPT_KEY);
  }

  private static getScriptName(scriptId: string): string {
    const scripts = this.getAllScripts();
    const script = scripts.find(s => s.id === scriptId);
    return script?.name || 'Untitled Script';
  }
}
```

**Usage in CodeEditorPage**:
```typescript
import { AutoSaveService } from '../../services/autoSaveService';

export const CodeEditorPage: React.FC = () => {
  const [code, setCode] = useState<string>('');
  const [currentScript, setCurrentScript] = useState<SavedScript | null>(null);
  const [hasUnsavedChanges, setHasUnsavedChanges] = useState(false);

  // Restore last session on mount
  useEffect(() => {
    const restored = AutoSaveService.restoreLastSession();
    if (restored) {
      setCode(restored.content);
      setCurrentScript(restored);

      // Confirm with user
      if (restored.autoSaved) {
        // Show toast notification
        console.log('Restored auto-saved script from', restored.lastModified);
      }
    }
  }, []);

  // Auto-save on code change
  const handleCodeChange = (newCode: string) => {
    setCode(newCode);
    setHasUnsavedChanges(true);
    AutoSaveService.autoSave(newCode, currentScript?.id);
  };

  // Manual save (Ctrl+S)
  const handleSave = () => {
    const script: SavedScript = {
      id: currentScript?.id || generateId(),
      name: currentScript?.name || 'Untitled Script',
      content: code,
      lastModified: new Date(),
      autoSaved: false
    };

    AutoSaveService.manualSave(script);
    setCurrentScript(script);
    setHasUnsavedChanges(false);
  };

  return (
    <div>
      <div className="header">
        <h2>{currentScript?.name || 'New Script'}</h2>
        {hasUnsavedChanges && <span className="unsaved-indicator">● Unsaved changes</span>}
      </div>
      {/* ... rest of component */}
    </div>
  );
};
```

**Visual Indicator**:
```css
.unsaved-indicator {
  color: orange;
  font-size: 12px;
  margin-left: 10px;
}
```

**Implementation Time**: 3 hours

---

## 2. Script Management (Save/Load/Delete) ⭐ HIGH PRIORITY

### Why Important
- Users need to save commonly-used queries
- Enables building a personal query library
- Supports collaboration (share scripts with team)

### Features

**Saved Scripts Page** (`/a/sqlmonitor-codeeditor-app/scripts`):
- List all saved scripts with metadata
- Search/filter by name, date, database
- Click to load into editor
- Delete saved scripts
- Export/import scripts (JSON format)

**Implementation**:
```typescript
// src/components/Scripts/SavedScriptsPage.tsx
export const SavedScriptsPage: React.FC = () => {
  const [scripts, setScripts] = useState<SavedScript[]>([]);

  useEffect(() => {
    setScripts(AutoSaveService.getAllScripts());
  }, []);

  const handleLoad = (script: SavedScript) => {
    // Navigate to editor with script loaded
    window.location.href = `/a/sqlmonitor-codeeditor-app/editor?scriptId=${script.id}`;
  };

  const handleDelete = (scriptId: string) => {
    if (confirm('Are you sure you want to delete this script?')) {
      AutoSaveService.deleteScript(scriptId);
      setScripts(scripts.filter(s => s.id !== scriptId));
    }
  };

  return (
    <div className="saved-scripts-page">
      <h2>Saved Scripts</h2>
      <table>
        <thead>
          <tr>
            <th>Name</th>
            <th>Database</th>
            <th>Last Modified</th>
            <th>Size</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          {scripts.map(script => (
            <tr key={script.id}>
              <td>{script.name}</td>
              <td>{script.databaseName || 'N/A'}</td>
              <td>{new Date(script.lastModified).toLocaleString()}</td>
              <td>{script.content.length} chars</td>
              <td>
                <Button onClick={() => handleLoad(script)}>Load</Button>
                <Button onClick={() => handleDelete(script.id)} variant="destructive">Delete</Button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
};
```

**Implementation Time**: 4 hours

---

## 3. Keyboard Shortcuts ⭐ HIGH PRIORITY

### Why Important
- Power users demand keyboard efficiency
- Standard shortcuts feel familiar (VSCode, SSMS)
- Increases productivity

### Standard Shortcuts

| Shortcut | Action | Implementation |
|----------|--------|----------------|
| **Ctrl+S** | Save script | Manual save to localStorage |
| **Ctrl+Shift+S** | Save As (rename) | Prompt for new name |
| **Ctrl+Enter** | Execute query | Run query on selected server |
| **Ctrl+Shift+A** | Analyze code | Run analysis engine |
| **Ctrl+K, Ctrl+C** | Comment lines | Toggle `--` comments |
| **Ctrl+K, Ctrl+U** | Uncomment lines | Remove `--` comments |
| **Ctrl+/** | Toggle comment | Single-line comment toggle |
| **Ctrl+F** | Find | Monaco built-in |
| **Ctrl+H** | Find & Replace | Monaco built-in |
| **Ctrl+Shift+F** | Format code | Monaco format document |
| **F5** | Execute query | Alternative to Ctrl+Enter |
| **Ctrl+L** | Clear editor | Confirm then clear |
| **Ctrl+D** | Duplicate line | Monaco built-in |
| **Alt+Up/Down** | Move line up/down | Monaco built-in |
| **Ctrl+Shift+K** | Delete line | Monaco built-in |

**Implementation**:
```typescript
// src/components/CodeEditor/EditorPanel.tsx
const handleEditorDidMount = (editor: any, monaco: any) => {
  // Save (Ctrl+S)
  editor.addAction({
    id: 'save-script',
    label: 'Save Script',
    keybindings: [monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS],
    run: () => {
      onSave();
    }
  });

  // Execute query (Ctrl+Enter or F5)
  editor.addAction({
    id: 'execute-query',
    label: 'Execute Query',
    keybindings: [
      monaco.KeyMod.CtrlCmd | monaco.KeyCode.Enter,
      monaco.KeyCode.F5
    ],
    run: () => {
      onExecute();
    }
  });

  // Analyze code (Ctrl+Shift+A)
  editor.addAction({
    id: 'analyze-code',
    label: 'Analyze Code',
    keybindings: [monaco.KeyMod.CtrlCmd | monaco.KeyMod.Shift | monaco.KeyCode.KeyA],
    run: () => {
      onAnalyze();
    }
  });

  // Clear editor (Ctrl+L)
  editor.addAction({
    id: 'clear-editor',
    label: 'Clear Editor',
    keybindings: [monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyL],
    run: () => {
      if (confirm('Clear all code? This cannot be undone.')) {
        editor.setValue('');
      }
    }
  });
};
```

**Keyboard Shortcuts Help** (Ctrl+? or F1):
```typescript
// src/components/CodeEditor/KeyboardShortcutsHelp.tsx
export const KeyboardShortcutsHelp: React.FC = () => {
  return (
    <Modal title="Keyboard Shortcuts">
      <table>
        <thead>
          <tr>
            <th>Action</th>
            <th>Shortcut</th>
          </tr>
        </thead>
        <tbody>
          <tr><td>Save Script</td><td>Ctrl+S</td></tr>
          <tr><td>Execute Query</td><td>Ctrl+Enter or F5</td></tr>
          <tr><td>Analyze Code</td><td>Ctrl+Shift+A</td></tr>
          <tr><td>Find</td><td>Ctrl+F</td></tr>
          <tr><td>Format Code</td><td>Ctrl+Shift+F</td></tr>
          {/* ... more shortcuts */}
        </tbody>
      </table>
    </Modal>
  );
};
```

**Implementation Time**: 2 hours

---

## 4. Code Formatting (Auto-Format) ⭐ MEDIUM PRIORITY

### Why Important
- Clean, readable code is easier to analyze
- Consistent formatting across team
- Standard feature in modern editors

### Implementation

**Use SQL Formatter Library**:
```bash
npm install --save sql-formatter
```

**Integration**:
```typescript
import { format } from 'sql-formatter';

const formatCode = (code: string): string => {
  return format(code, {
    language: 'tsql',
    indent: '  ',  // 2 spaces
    uppercase: true,  // Keywords in uppercase
    linesBetweenQueries: 2
  });
};

// Add to Monaco Editor
editor.addAction({
  id: 'format-code',
  label: 'Format Document',
  keybindings: [monaco.KeyMod.CtrlCmd | monaco.KeyMod.Shift | monaco.KeyCode.KeyF],
  run: (ed) => {
    const formatted = formatCode(ed.getValue());
    ed.setValue(formatted);
  }
});
```

**Auto-Format on Paste**:
```typescript
monacoOptions={{
  formatOnPaste: true,  // Auto-format when pasting code
  formatOnType: false   // Don't auto-format as user types (annoying)
}}
```

**Implementation Time**: 1 hour

---

## 5. Execution History ⭐ MEDIUM PRIORITY

### Why Important
- Review past queries and results
- Re-run previous queries easily
- Track query performance over time

### Features

**Execution History Panel**:
- List last 50 executions (most recent first)
- Show: Query (truncated), Execution Time, Row Count, Timestamp
- Click to load query into editor
- Click to view full results (if cached)

**Implementation**:
```typescript
interface ExecutionHistoryEntry {
  id: string;
  query: string;
  serverId: number;
  databaseName: string;
  executionTime: number;
  rowCount: number;
  success: boolean;
  error?: string;
  timestamp: Date;
}

export class ExecutionHistoryService {
  private static STORAGE_KEY = 'sqlmonitor-execution-history';
  private static MAX_ENTRIES = 50;

  public static addEntry(entry: ExecutionHistoryEntry): void {
    const history = this.getHistory();
    history.unshift(entry);  // Add to beginning

    // Keep only last 50
    if (history.length > this.MAX_ENTRIES) {
      history.splice(this.MAX_ENTRIES);
    }

    localStorage.setItem(this.STORAGE_KEY, JSON.stringify(history));
  }

  public static getHistory(): ExecutionHistoryEntry[] {
    const stored = localStorage.getItem(this.STORAGE_KEY);
    if (!stored) return [];

    try {
      return JSON.parse(stored);
    } catch {
      return [];
    }
  }

  public static clearHistory(): void {
    localStorage.removeItem(this.STORAGE_KEY);
  }
}
```

**UI Component**:
```typescript
export const ExecutionHistoryPanel: React.FC = () => {
  const [history, setHistory] = useState<ExecutionHistoryEntry[]>([]);

  useEffect(() => {
    setHistory(ExecutionHistoryService.getHistory());
  }, []);

  return (
    <div className="execution-history">
      <h4>Execution History</h4>
      <ul>
        {history.map(entry => (
          <li key={entry.id} className={entry.success ? 'success' : 'error'}>
            <div className="query-preview">
              {entry.query.substring(0, 100)}...
            </div>
            <div className="metadata">
              <span>{entry.executionTime}ms</span>
              <span>{entry.rowCount} rows</span>
              <span>{new Date(entry.timestamp).toLocaleTimeString()}</span>
            </div>
            <Button onClick={() => loadQueryIntoEditor(entry.query)}>Load</Button>
          </li>
        ))}
      </ul>
    </div>
  );
};
```

**Implementation Time**: 3 hours

---

## 6. Snippets / Code Templates ⭐ LOW PRIORITY

### Why Important
- Speed up common query patterns
- Reduce typos and syntax errors
- Industry standard (SSMS has snippets, VSCode has snippets)

### Common T-SQL Snippets

| Trigger | Expansion |
|---------|-----------|
| `sel` | `SELECT * FROM TableName` |
| `ins` | `INSERT INTO TableName (Col1, Col2) VALUES (Val1, Val2)` |
| `upd` | `UPDATE TableName SET Col1 = Val1 WHERE ID = 1` |
| `del` | `DELETE FROM TableName WHERE ID = 1` |
| `cte` | `WITH CTE AS (SELECT ...) SELECT * FROM CTE` |
| `proc` | Full stored procedure template |
| `try` | `BEGIN TRY ... END TRY BEGIN CATCH ... END CATCH` |
| `if` | `IF EXISTS (SELECT ...) BEGIN ... END` |

**Monaco Snippets Implementation**:
```typescript
monaco.languages.registerCompletionItemProvider('sql', {
  provideCompletionItems: (model, position) => {
    const word = model.getWordUntilPosition(position);
    const range = {
      startLineNumber: position.lineNumber,
      endLineNumber: position.lineNumber,
      startColumn: word.startColumn,
      endColumn: word.endColumn
    };

    const suggestions = [
      {
        label: 'sel',
        kind: monaco.languages.CompletionItemKind.Snippet,
        insertText: 'SELECT ${1:*}\nFROM ${2:TableName}\nWHERE ${3:Condition};',
        insertTextRules: monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet,
        documentation: 'SELECT statement template',
        range
      },
      {
        label: 'proc',
        kind: monaco.languages.CompletionItemKind.Snippet,
        insertText: `CREATE PROCEDURE dbo.usp_\${1:ProcedureName}
    @\${2:ParameterName} \${3:INT}
AS
BEGIN
    SET NOCOUNT ON;

    \${4:-- Your code here}

END;
GO`,
        insertTextRules: monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet,
        documentation: 'Stored procedure template',
        range
      },
      {
        label: 'try',
        kind: monaco.languages.CompletionItemKind.Snippet,
        insertText: `BEGIN TRY
    \${1:-- Your code here}
END TRY
BEGIN CATCH
    DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
    RAISERROR(@ErrorMessage, @ErrorSeverity, 1);
END CATCH;`,
        insertTextRules: monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet,
        documentation: 'TRY/CATCH error handling template',
        range
      }
    ];

    return { suggestions };
  }
});
```

**Implementation Time**: 2 hours

---

## 7. Dark Mode Support ⭐ LOW PRIORITY

### Why Important
- Reduces eye strain during long coding sessions
- User preference (some prefer dark, some prefer light)
- Industry standard (all modern editors support themes)

### Implementation

**Respect Grafana Theme**:
```typescript
import { useTheme2 } from '@grafana/ui';

export const CodeEditorPage: React.FC = () => {
  const theme = useTheme2();
  const isDark = theme.isDark;

  return (
    <EditorPanel
      theme={isDark ? 'vs-dark' : 'vs-light'}
      // ... other props
    />
  );
};
```

**Monaco Theme**:
```typescript
monacoOptions={{
  theme: isDark ? 'vs-dark' : 'vs-light',
  // ... other options
}}
```

**Implementation Time**: 30 minutes

---

## 8. Split View (Side-by-Side Code Comparison) ⭐ LOW PRIORITY

### Why Important
- Compare before/after versions
- Compare different stored procedures
- Useful for code review

### Implementation

**Split Editor Component**:
```typescript
import { MonacoDiffEditor } from '@monaco-editor/react';

export const SplitViewEditor: React.FC = () => {
  const [originalCode, setOriginalCode] = useState('');
  const [modifiedCode, setModifiedCode] = useState('');

  return (
    <MonacoDiffEditor
      original={originalCode}
      modified={modifiedCode}
      language="sql"
      height="600px"
      options={{
        readOnly: false,
        renderSideBySide: true
      }}
    />
  );
};
```

**Use Cases**:
- Compare auto-fix suggestion (before/after)
- Compare stored procedure versions
- Review query rewrites

**Implementation Time**: 2 hours

---

## 9. Export Results (CSV, Excel, JSON) ⭐ MEDIUM PRIORITY

### Why Important
- Users need to share query results
- Common workflow (run query → export → send to stakeholder)
- Standard feature in SSMS, SQL Prompt, etc.

### Implementation

**Export Buttons in Results Panel**:
```typescript
const exportToCSV = (results: QueryResult) => {
  const header = results.columns.map(col => col.name).join(',');
  const rows = results.rows.map(row =>
    results.columns.map(col => {
      const value = row[col.name];
      return typeof value === 'string' && value.includes(',')
        ? `"${value.replace(/"/g, '""')}"`  // Escape quotes
        : value;
    }).join(',')
  );

  const csv = [header, ...rows].join('\n');
  const blob = new Blob([csv], { type: 'text/csv' });
  const url = URL.createObjectURL(blob);

  const a = document.createElement('a');
  a.href = url;
  a.download = `query-results-${Date.now()}.csv`;
  a.click();

  URL.revokeObjectURL(url);
};

const exportToJSON = (results: QueryResult) => {
  const json = JSON.stringify(results.rows, null, 2);
  const blob = new Blob([json], { type: 'application/json' });
  const url = URL.createObjectURL(blob);

  const a = document.createElement('a');
  a.href = url;
  a.download = `query-results-${Date.now()}.json`;
  a.click();

  URL.revokeObjectURL(url);
};

// For Excel, use a library like xlsx
import * as XLSX from 'xlsx';

const exportToExcel = (results: QueryResult) => {
  const worksheet = XLSX.utils.json_to_sheet(results.rows);
  const workbook = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(workbook, worksheet, 'Results');
  XLSX.writeFile(workbook, `query-results-${Date.now()}.xlsx`);
};
```

**UI**:
```typescript
<div className="export-buttons">
  <Button onClick={() => exportToCSV(results)}>Export CSV</Button>
  <Button onClick={() => exportToJSON(results)}>Export JSON</Button>
  <Button onClick={() => exportToExcel(results)}>Export Excel</Button>
</div>
```

**Implementation Time**: 2 hours

---

## 10. Query Execution Plan Visualization ⭐ LOW PRIORITY

### Why Important
- Essential for performance troubleshooting
- Visualize operator costs, joins, scans
- Industry standard (SSMS, Azure Data Studio)

### Implementation

**Use existing library or custom visualization**:
```typescript
// Option 1: Use SQL Server execution plan XML parser
import { parseExecutionPlan } from 'sql-execution-plan-parser';

const visualizeExecutionPlan = (planXml: string) => {
  const parsed = parseExecutionPlan(planXml);

  // Render as tree or graph
  return (
    <div className="execution-plan">
      <TreeView data={parsed} />
    </div>
  );
};

// Option 2: Simple table view of operators
const showExecutionPlanTable = (planXml: string) => {
  // Parse XML to extract operators
  // Display as table with: Operator, Cost, Rows, Details
};
```

**Defer to Phase 4**: This is complex and requires significant effort. For Phase 3, just display raw XML and add visualization in Phase 4.

**Implementation Time (simple)**: 1 hour (display XML)
**Implementation Time (full viz)**: 10 hours (defer to Phase 4)

---

## 11. Collaborative Features (Future Phase 4+)

### Features (Not in Phase 3)
- Share scripts via URL (generate shareable link)
- Real-time collaboration (Google Docs-style, multiple users editing)
- Comments/annotations on code
- Code review workflow

**Reason for Deferral**: Requires backend infrastructure (API endpoints, database storage)

---

## 12. IntelliSense / Auto-Complete ⭐ HIGH PRIORITY

### Why Important
- Speeds up coding
- Reduces typos
- Provides table/column suggestions from schema metadata

### Implementation

**Basic IntelliSense** (Keywords only - 1 hour):
```typescript
monaco.languages.registerCompletionItemProvider('sql', {
  provideCompletionItems: () => {
    const suggestions = [
      { label: 'SELECT', kind: monaco.languages.CompletionItemKind.Keyword },
      { label: 'FROM', kind: monaco.languages.CompletionItemKind.Keyword },
      { label: 'WHERE', kind: monaco.languages.CompletionItemKind.Keyword },
      { label: 'JOIN', kind: monaco.languages.CompletionItemKind.Keyword },
      { label: 'GROUP BY', kind: monaco.languages.CompletionItemKind.Keyword },
      { label: 'ORDER BY', kind: monaco.languages.CompletionItemKind.Keyword },
      // ... all T-SQL keywords
    ];
    return { suggestions };
  }
});
```

**Advanced IntelliSense** (Schema-aware - 3 hours):
```typescript
// Fetch schema metadata from SQL Monitor API
const getSchemaMetadata = async (serverId: number, databaseName: string) => {
  const response = await apiClient.get(`/api/schema/metadata`, {
    serverId,
    databaseName
  });
  return response;  // Returns tables, columns, types
};

// Register schema-aware completions
monaco.languages.registerCompletionItemProvider('sql', {
  provideCompletionItems: async (model, position) => {
    // Parse current context (are we after FROM? after SELECT?)
    const textBeforeCursor = model.getValueInRange({
      startLineNumber: position.lineNumber,
      startColumn: 1,
      endLineNumber: position.lineNumber,
      endColumn: position.column
    });

    // If after FROM, suggest tables
    if (/FROM\s+$/i.test(textBeforeCursor)) {
      const schema = await getSchemaMetadata(selectedServerId, selectedDatabase);
      return {
        suggestions: schema.tables.map(table => ({
          label: table.name,
          kind: monaco.languages.CompletionItemKind.Class,
          insertText: table.name,
          documentation: `${table.schemaName}.${table.name}`
        }))
      };
    }

    // If after SELECT, suggest columns
    if (/SELECT\s+$/i.test(textBeforeCursor)) {
      const schema = await getSchemaMetadata(selectedServerId, selectedDatabase);
      const columns = schema.tables.flatMap(t =>
        t.columns.map(c => ({
          label: c.name,
          kind: monaco.languages.CompletionItemKind.Field,
          insertText: c.name,
          documentation: `${t.name}.${c.name} (${c.type})`
        }))
      );
      return { suggestions: columns };
    }

    return { suggestions: [] };
  }
});
```

**Implementation Time**: 4 hours (basic + schema-aware)

---

## Summary: Implementation Priority Matrix

| # | Feature | Priority | Effort (hours) | Phase | Value |
|---|---------|----------|----------------|-------|-------|
| 1 | Auto-Save (localStorage) | ⭐ CRITICAL | 3 | Week 1 | Very High |
| 2 | Script Management (Save/Load/Delete) | ⭐ HIGH | 4 | Week 1 | Very High |
| 3 | Keyboard Shortcuts (20+ shortcuts) | ⭐ HIGH | 2 | Week 1 | High |
| 4 | IntelliSense (Schema-aware) | ⭐ HIGH | 4 | Week 2 | Very High |
| 5 | Code Formatting (sql-formatter) | ⭐ MEDIUM | 1 | Week 1 | Medium |
| 6 | Execution History (Last 50) | ⭐ MEDIUM | 3 | Week 3 | Medium |
| 7 | Export Results (CSV/JSON/Excel) | ⭐ MEDIUM | 2 | Week 3 | Medium |
| 8 | Dark Mode (Grafana theme) | ⭐ LOW | 0.5 | Week 1 | Low |
| 9 | Snippets / Templates | ⭐ LOW | 2 | Week 2 | Low |
| 10 | Split View (Diff Editor) | ⭐ LOW | 2 | Phase 4 | Low |
| 11 | Execution Plan Viz (simple) | ⭐ LOW | 1 | Week 3 | Low |
| **TOTAL** | | | **24.5 hours** | | |

**Recommendation**: Include features #1-7 + #8 in initial 55-hour build
**Additional Time Required**: ~20 hours (manageable within Phase 3 scope)
**Updated Total**: 55h (original) + 20h (nice-to-haves) = **75 hours**

---

## Revised Implementation Schedule

### Week 1: Core Editor + Auto-Save + Keyboard Shortcuts (15 hours)
- Day 1: Plugin scaffolding (3h)
- Day 2: Basic layout + Auto-Save service (6h) ← **+3h for auto-save**
- Day 3: Monaco Editor + Keyboard shortcuts (6h) ← **+2h for shortcuts**

### Week 2: Code Analysis + IntelliSense + Snippets (26 hours)
- Day 4-5: Analysis engine foundation (8h)
- Day 6-7: Implement 30 analysis rules (12h)
- Day 8: IntelliSense + Code Formatting (5h) ← **+4h for IntelliSense, +1h formatting**

### Week 3: Query Execution + Export + History (15 hours)
- Day 9-10: API client + query execution (6h)
- Day 11: Results grid + Export + History (9h) ← **+5h for export/history**

### Week 3-4: SolarWinds Features (10 hours)
- Day 12-13: Percentiles (5h)
- Day 14: Query rewrites (3h)
- Day 15: Wait categorization (2h)

### Week 4: Polish + Documentation + Script Management (9 hours)
- Day 16: AnalysisPanel + Script Management (6h) ← **+4h for script management**
- Day 17: Documentation (3h)

**TOTAL**: 75 hours (vs 55 hours original estimate)

---

## User Experience Benefits

**With Nice-to-Haves**:
- ✅ No data loss (auto-save every 2 seconds)
- ✅ Familiar keyboard shortcuts (muscle memory from SSMS/VSCode)
- ✅ Script library (save commonly-used queries)
- ✅ IntelliSense (faster coding, fewer typos)
- ✅ Execution history (review past queries)
- ✅ Export results (share with stakeholders)
- ✅ Clean code (auto-formatting)
- ✅ Dark mode (reduce eye strain)

**Competitive Position**:
- SQLenlight: No editor, only analysis ← We have full editor
- Redgate SQL Prompt: Desktop only ← We're web-based
- SSMS: No web version ← We run in browser
- Azure Data Studio: Desktop app ← We integrate with Grafana

**Unique Value Proposition**:
> "The only web-based T-SQL editor with real-time analysis, auto-save, IntelliSense, and integration with your monitoring data."

---

**Document Version**: 1.0
**Last Updated**: 2025-11-02
**Status**: Design Complete - Ready for Implementation
**Estimated Total Time**: 75 hours (55h core + 20h nice-to-haves)
