# Phase 3 Feature #7 - Navigation Architecture

**Document Version**: 1.0
**Date**: 2025-11-02
**Status**: Design Document - For Implementation in Week 1 Day 3 (Extended) + Week 2

---

## Table of Contents

1. [Overview](#overview)
2. [Navigation Patterns](#navigation-patterns)
3. [URL Routing and Deep Linking](#url-routing-and-deep-linking)
4. [Multi-Tab Editor](#multi-tab-editor)
5. [Quick Open and Search](#quick-open-and-search)
6. [Object Browser Sidebar](#object-browser-sidebar)
7. [Jump to Definition/References](#jump-to-definitionreferences)
8. [Hyperlinks from Grafana Dashboards](#hyperlinks-from-grafana-dashboards)
9. [Context Menu Actions](#context-menu-actions)
10. [Implementation Plan](#implementation-plan)

---

## Overview

The Code Editor needs a sophisticated navigation system to support:

1. **External Navigation** - Deep links from Grafana dashboards to specific database objects
2. **Internal Navigation** - Quick open, search, filter, object browser
3. **Code Intelligence** - Jump to definition, find references, peek definition
4. **Multi-Window** - Tab management, split editor, side-by-side comparison
5. **Breadcrumbs** - Show current location (Server > Database > Schema > Object)

**Design Principles**:
- **VSCode-like UX** - Users familiar with VSCode should feel at home
- **URL-driven** - All navigation states should be URL-addressable
- **Keyboard-first** - Every action has a keyboard shortcut
- **Context-aware** - Right-click menus show relevant actions
- **Performance** - Lazy loading, virtualized lists, debounced search

---

## Navigation Patterns

### 1. Entry Points

Users can open the Code Editor from:

| Source | Action | URL Pattern |
|--------|--------|-------------|
| **Grafana Menu** | Click "Code Editor" in sidebar | `/a/sqlmonitor-codeeditor-app/editor` |
| **Dashboard Link** | Click procedure name in "Top 10 Slowest Procedures" | `/a/sqlmonitor-codeeditor-app/editor?server=1&db=MyDB&object=dbo.usp_GetOrders` |
| **Saved Scripts** | Click saved script in "Saved Scripts" page | `/a/sqlmonitor-codeeditor-app/editor?script=abc-123` |
| **Object Browser** | Click table/view/SP in browser | `/a/sqlmonitor-codeeditor-app/editor?server=1&db=MyDB&object=dbo.Customers` |
| **Quick Open** | Press Ctrl+P and select object | Updates URL with selected object |

### 2. Navigation Hierarchy

```
SQL Monitor
├── Code Editor (default page)
│   ├── Recent Files (last 10)
│   ├── Saved Scripts
│   └── Database Objects
│       ├── Server 1
│       │   ├── Database A
│       │   │   ├── dbo
│       │   │   │   ├── Tables
│       │   │   │   ├── Views
│       │   │   │   ├── Stored Procedures
│       │   │   │   └── Functions
│       │   │   └── schema2
│       │   └── Database B
│       └── Server 2
├── Saved Scripts (list page)
└── Configuration (settings page)
```

### 3. Navigation Actions

| Action | Keyboard Shortcut | Description |
|--------|-------------------|-------------|
| **Quick Open** | `Ctrl+P` | Fuzzy search across all objects and scripts |
| **Go to Definition** | `F12` | Jump to table/view/SP definition |
| **Peek Definition** | `Alt+F12` | Inline preview of definition |
| **Find References** | `Shift+F12` | Find all usages of table/SP |
| **Go to Line** | `Ctrl+G` | Jump to specific line number |
| **Next Tab** | `Ctrl+Tab` | Switch to next open tab |
| **Previous Tab** | `Ctrl+Shift+Tab` | Switch to previous tab |
| **Close Tab** | `Ctrl+W` | Close current tab |
| **Close All Tabs** | `Ctrl+K W` | Close all open tabs |
| **Split Editor** | `Ctrl+\` | Split editor side-by-side |
| **Toggle Sidebar** | `Ctrl+B` | Show/hide object browser |
| **Focus Breadcrumb** | `Ctrl+Shift+;` | Navigate via breadcrumb trail |

---

## URL Routing and Deep Linking

### URL Schema

All editor states are encoded in the URL for shareability and browser navigation.

**Base URL**: `/a/sqlmonitor-codeeditor-app/editor`

**Query Parameters**:

| Parameter | Type | Example | Description |
|-----------|------|---------|-------------|
| `server` | number | `?server=1` | Server ID |
| `db` | string | `&db=MyDB` | Database name |
| `schema` | string | `&schema=dbo` | Schema name (default: dbo) |
| `object` | string | `&object=dbo.usp_GetOrders` | Fully qualified object name |
| `type` | string | `&type=procedure` | Object type (table, view, procedure, function) |
| `line` | number | `&line=42` | Jump to specific line number |
| `column` | number | `&column=10` | Jump to specific column |
| `script` | string | `&script=abc-123-def-456` | Saved script ID |
| `tabs` | string[] | `&tabs=obj1,obj2,obj3` | Open tabs (comma-separated) |
| `active` | number | `&active=1` | Active tab index |
| `split` | boolean | `&split=true` | Split editor mode |

**Example URLs**:

```
# Open blank editor
/a/sqlmonitor-codeeditor-app/editor

# Open specific procedure
/a/sqlmonitor-codeeditor-app/editor?server=1&db=MyDB&object=dbo.usp_GetOrders

# Open procedure at specific line
/a/sqlmonitor-codeeditor-app/editor?server=1&db=MyDB&object=dbo.usp_GetOrders&line=42

# Open saved script
/a/sqlmonitor-codeeditor-app/editor?script=abc-123-def-456

# Open multiple tabs
/a/sqlmonitor-codeeditor-app/editor?tabs=dbo.usp_GetOrders,dbo.Customers,dbo.Orders&active=0

# Split editor with two objects
/a/sqlmonitor-codeeditor-app/editor?tabs=dbo.usp_GetOrders,dbo.Customers&active=0&split=true
```

### React Router Integration

```typescript
// src/components/App/App.tsx
import { Route, Routes, useSearchParams } from 'react-router-dom';

function App() {
  return (
    <Routes>
      <Route path="/editor" element={<CodeEditorPage />} />
      <Route path="/scripts" element={<SavedScriptsPage />} />
      <Route path="/config" element={<ConfigPage />} />
    </Routes>
  );
}

// src/components/CodeEditor/CodeEditorPage.tsx
function CodeEditorPage() {
  const [searchParams, setSearchParams] = useSearchParams();

  useEffect(() => {
    const server = searchParams.get('server');
    const db = searchParams.get('db');
    const object = searchParams.get('object');
    const scriptId = searchParams.get('script');
    const line = searchParams.get('line');

    if (scriptId) {
      // Load saved script by ID
      loadScript(scriptId);
    } else if (server && db && object) {
      // Load database object code
      loadObjectCode(parseInt(server), db, object, parseInt(line || '0'));
    }
  }, [searchParams]);

  const openObject = (server: number, db: string, object: string) => {
    setSearchParams({
      server: server.toString(),
      db,
      object,
    });
  };
}
```

---

## Multi-Tab Editor

### Tab Management

**Tab States**:
- **Untitled** - New blank script (not yet saved)
- **Saved Script** - Loaded from localStorage or API
- **Database Object** - Loaded from database (read-only or editable)
- **Modified** - Has unsaved changes (● indicator)
- **Pinned** - Cannot be auto-closed

**Tab UI**:

```
┌─────────────────────────────────────────────────────────────────┐
│ ● Untitled-1  │  dbo.usp_GetOrders*  │  📌 dbo.Customers  │  +  │
└─────────────────────────────────────────────────────────────────┘
    └─ Unsaved       └─ Modified            └─ Pinned       └─ New Tab
```

**Tab Actions** (Right-click menu):
- Close
- Close Others
- Close All
- Close to the Right
- Pin Tab / Unpin Tab
- Copy Path
- Reveal in Object Browser
- Split Right
- Split Down

**Tab Ordering**:
- Drag and drop to reorder
- Auto-group by type (scripts, tables, procedures)
- LRU (Least Recently Used) for auto-close

### Split Editor

**Split Modes**:
- **Single** - One editor pane (default)
- **Vertical Split** - Side-by-side (Ctrl+\)
- **Horizontal Split** - Top/bottom (Ctrl+Shift+\)
- **Grid** - 2x2 grid (up to 4 panes)

**Split Navigation**:
- `Ctrl+1` - Focus left pane
- `Ctrl+2` - Focus right pane
- `Ctrl+3` - Focus bottom pane
- `Alt+Left/Right/Up/Down` - Move focus between panes

**Use Cases**:
1. **Compare two procedures** - Open both in split view
2. **Reference while coding** - View table schema while writing INSERT
3. **Multi-file editing** - Edit trigger and table side-by-side

### Tab State Persistence

**localStorage Schema**:

```typescript
interface TabState {
  id: string;
  type: 'untitled' | 'script' | 'object';
  title: string;
  serverId?: number;
  databaseName?: string;
  objectName?: string;
  scriptId?: string;
  content: string;
  cursorPosition: { line: number; column: number };
  scrollPosition: number;
  isPinned: boolean;
  isModified: boolean;
}

interface EditorState {
  tabs: TabState[];
  activeTabIndex: number;
  splitMode: 'single' | 'vertical' | 'horizontal' | 'grid';
  splitSizes: number[];
}

// Persist to localStorage on every change
localStorage.setItem('sqlmonitor-editor-state', JSON.stringify(editorState));

// Restore on page load
const editorState = JSON.parse(localStorage.getItem('sqlmonitor-editor-state') || '{}');
```

---

## Quick Open and Search

### Quick Open (Ctrl+P)

**Features**:
- Fuzzy search across all objects (tables, views, SPs, functions)
- Fuzzy search across all saved scripts
- Recent files at the top (last 10)
- Type filters: `@table`, `@sp`, `@view`, `@script`
- Search by schema: `dbo:` prefix
- Search by server: `server1:` prefix

**UI**:

```
┌──────────────────────────────────────────────────────────┐
│ 🔍 Type to search objects, scripts...                    │
├──────────────────────────────────────────────────────────┤
│ RECENT                                                    │
│ 📄 dbo.usp_GetOrders          [Server1/MyDB]             │
│ 📄 dbo.Customers              [Server1/MyDB]             │
│                                                           │
│ OBJECTS                                                   │
│ 🔧 dbo.usp_GetOrdersByCustomer  [Server1/MyDB] Procedure │
│ 📊 dbo.Orders                   [Server1/MyDB] Table     │
│ 👁️  dbo.vw_CustomerOrders       [Server1/MyDB] View      │
│                                                           │
│ SAVED SCRIPTS                                             │
│ 💾 Weekly Sales Report         Modified 2 hours ago      │
│ 💾 Cleanup Old Data             Modified yesterday        │
└──────────────────────────────────────────────────────────┘
```

**Implementation**:

```typescript
interface QuickOpenItem {
  type: 'object' | 'script' | 'recent';
  id: string;
  title: string;
  subtitle?: string; // Server/Database or last modified
  icon: string;
  serverId?: number;
  databaseName?: string;
  objectName?: string;
  objectType?: 'table' | 'view' | 'procedure' | 'function';
  scriptId?: string;
}

function QuickOpenDialog() {
  const [query, setQuery] = useState('');
  const [items, setItems] = useState<QuickOpenItem[]>([]);

  // Fuzzy search with debounce
  const searchItems = useDebouncedCallback((query: string) => {
    const results = fuzzySearch(query, allItems);
    setItems(results);
  }, 200);

  const handleSelect = (item: QuickOpenItem) => {
    if (item.type === 'script') {
      openScript(item.scriptId!);
    } else {
      openObject(item.serverId!, item.databaseName!, item.objectName!);
    }
  };

  return (
    <Modal>
      <Input
        value={query}
        onChange={(e) => {
          setQuery(e.target.value);
          searchItems(e.target.value);
        }}
        placeholder="Type to search objects, scripts..."
        autoFocus
      />
      <VirtualizedList items={items} onSelect={handleSelect} />
    </Modal>
  );
}
```

### Fuzzy Search Algorithm

Use **Fuse.js** for fuzzy search with weighted scoring:

```typescript
import Fuse from 'fuse.js';

const fuse = new Fuse(allItems, {
  keys: [
    { name: 'title', weight: 0.7 },
    { name: 'subtitle', weight: 0.2 },
    { name: 'objectType', weight: 0.1 },
  ],
  threshold: 0.4,
  includeScore: true,
  minMatchCharLength: 2,
});

const results = fuse.search(query);
```

---

## Object Browser Sidebar

### Tree View Structure

```
📂 SQL Servers
├── 📡 Server1 (sqltest.schoolvision.net,14333)
│   ├── 💾 MyDB
│   │   ├── 📂 dbo
│   │   │   ├── 📊 Tables (42)
│   │   │   │   ├── 📊 Customers
│   │   │   │   ├── 📊 Orders
│   │   │   │   └── 📊 OrderDetails
│   │   │   ├── 👁️ Views (12)
│   │   │   │   ├── 👁️ vw_CustomerOrders
│   │   │   │   └── 👁️ vw_ActiveCustomers
│   │   │   ├── 🔧 Stored Procedures (87)
│   │   │   │   ├── 🔧 usp_GetOrders
│   │   │   │   ├── 🔧 usp_CreateOrder
│   │   │   │   └── 🔧 usp_DeleteOrder
│   │   │   └── ƒ Functions (15)
│   │   │       ├── ƒ fn_GetCustomerName
│   │   │       └── ƒ fn_CalculateTotal
│   │   └── 📂 sales
│   └── 💾 TestDB
└── 📡 Server2 (suncity.schoolvision.net,14333)

💾 Saved Scripts (23)
├── 📄 Weekly Sales Report
├── 📄 Cleanup Old Data
└── 📄 Index Maintenance
```

### Object Browser Features

**Filter/Search**:
- Search box at top of sidebar
- Filter by object type (Tables, Views, SPs, Functions)
- Filter by schema
- Show only modified objects
- Show only favorites

**Context Menu** (Right-click):
- **Tables**: Open Definition, View Data (Top 1000), Design Table, Script as CREATE, Script as DROP
- **Views**: Open Definition, View Data, Script as CREATE
- **Stored Procedures**: Open Definition, Execute, Analyze Performance, Script as CREATE, Script as ALTER, Script as DROP
- **Functions**: Open Definition, Test Function, Script as CREATE

**Drag and Drop**:
- Drag table/view name into editor → Inserts `dbo.TableName`
- Drag SP name into editor → Inserts `EXEC dbo.ProcName @Param1 = NULL`
- Drag column name (after expanding table) → Inserts column name

### Implementation

```typescript
interface TreeNode {
  id: string;
  label: string;
  icon: string;
  type: 'server' | 'database' | 'schema' | 'folder' | 'object';
  children?: TreeNode[];
  isExpanded: boolean;
  serverId?: number;
  databaseName?: string;
  schemaName?: string;
  objectName?: string;
  objectType?: 'table' | 'view' | 'procedure' | 'function';
}

function ObjectBrowser() {
  const [tree, setTree] = useState<TreeNode[]>([]);
  const [filter, setFilter] = useState('');

  const handleNodeClick = (node: TreeNode) => {
    if (node.type === 'object') {
      openObject(node.serverId!, node.databaseName!, node.objectName!);
    } else {
      // Expand/collapse folder
      toggleExpand(node.id);
    }
  };

  const handleContextMenu = (node: TreeNode, event: React.MouseEvent) => {
    event.preventDefault();
    showContextMenu(node, event.clientX, event.clientY);
  };

  return (
    <div className="object-browser">
      <Input
        placeholder="Search objects..."
        value={filter}
        onChange={(e) => setFilter(e.target.value)}
      />
      <TreeView
        tree={tree}
        onNodeClick={handleNodeClick}
        onContextMenu={handleContextMenu}
      />
    </div>
  );
}
```

---

## Jump to Definition/References

### F12: Go to Definition

**Supported Objects**:
- **Tables** - Jump to CREATE TABLE definition
- **Views** - Jump to CREATE VIEW definition
- **Stored Procedures** - Jump to CREATE PROCEDURE definition
- **Functions** - Jump to CREATE FUNCTION definition
- **User-Defined Types** - Jump to CREATE TYPE definition

**Algorithm**:

1. **Parse current word under cursor**:
   ```typescript
   const cursorPosition = editor.getPosition();
   const word = editor.getModel().getWordAtPosition(cursorPosition);
   const objectName = parseObjectName(word.word); // e.g., "dbo.Customers"
   ```

2. **Resolve object type**:
   ```typescript
   const objectType = await apiClient.getObjectType(serverId, databaseName, objectName);
   ```

3. **Fetch definition**:
   ```typescript
   const definition = await apiClient.getObjectDefinition(serverId, databaseName, objectName, objectType);
   ```

4. **Open in new tab or navigate**:
   ```typescript
   openObject(serverId, databaseName, objectName);
   ```

### Alt+F12: Peek Definition

**Inline Preview**:
- Show definition in inline widget (no tab switch)
- Allow editing in peek view
- Press `Esc` to close

**Monaco Integration**:

```typescript
monaco.languages.registerDefinitionProvider('sql', {
  provideDefinition: async (model, position, token) => {
    const word = model.getWordAtPosition(position);
    if (!word) return null;

    const objectName = parseObjectName(word.word);
    const definition = await fetchObjectDefinition(objectName);

    if (!definition) return null;

    // Create virtual document for definition
    const uri = monaco.Uri.parse(`inmemory:///${objectName}.sql`);
    monaco.editor.createModel(definition.code, 'sql', uri);

    return {
      uri,
      range: new monaco.Range(1, 1, 1, 1),
    };
  },
});
```

### Shift+F12: Find All References

**Show all usages** of a table/view/SP across:
- Stored procedures
- Views
- Functions
- Triggers

**API Call**:

```sql
-- Find all references to dbo.Customers table
SELECT DISTINCT
    OBJECT_SCHEMA_NAME(referencing_id) AS ReferencingSchema,
    OBJECT_NAME(referencing_id) AS ReferencingObject,
    o.type_desc AS ObjectType
FROM sys.sql_expression_dependencies sed
INNER JOIN sys.objects o ON sed.referencing_id = o.object_id
WHERE referenced_entity_name = 'Customers'
  AND referenced_schema_name = 'dbo'
ORDER BY ObjectType, ReferencingSchema, ReferencingObject;
```

**UI**:

```
REFERENCES TO dbo.Customers (12 results in 8 files)

📂 Stored Procedures (7)
  🔧 dbo.usp_GetCustomerOrders (2)
    Line 12: FROM dbo.Customers c
    Line 45: JOIN dbo.Customers c2 ON ...
  🔧 dbo.usp_CreateOrder (1)
    Line 23: INSERT INTO dbo.Customers (...)

📂 Views (3)
  👁️ dbo.vw_ActiveCustomers (1)
    Line 5: FROM dbo.Customers

📂 Functions (2)
  ƒ dbo.fn_GetCustomerCount (1)
    Line 8: FROM dbo.Customers
```

---

## Hyperlinks from Grafana Dashboards

### Dashboard Integration

**Use Case**: User viewing "Top 10 Slowest Procedures" dashboard, clicks on procedure name to open code.

**Dashboard JSON** (Grafana transformation):

```json
{
  "type": "table",
  "transformations": [
    {
      "id": "organize",
      "options": {
        "renameByName": {
          "ProcedureName": "Procedure"
        },
        "indexByName": {
          "Procedure": 0,
          "AvgDurationMs": 1,
          "ExecutionCount": 2
        }
      }
    },
    {
      "id": "convertFieldType",
      "options": {
        "conversions": [
          {
            "targetField": "Procedure",
            "destinationType": "string",
            "dateFormat": ""
          }
        ]
      }
    }
  ],
  "fieldConfig": {
    "overrides": [
      {
        "matcher": {
          "id": "byName",
          "options": "Procedure"
        },
        "properties": [
          {
            "id": "links",
            "value": [
              {
                "title": "Open in Code Editor",
                "url": "/a/sqlmonitor-codeeditor-app/editor?server=${__field.labels.ServerId}&db=${__field.labels.DatabaseName}&object=${__value.text}",
                "targetBlank": false
              }
            ]
          }
        ]
      }
    ]
  }
}
```

**SQL Query** (include metadata for linking):

```sql
SELECT
    s.ServerID,
    s.ServerName,
    ps.DatabaseName,
    ps.ProcedureName,
    AVG(ps.AvgDurationMs) AS AvgDurationMs,
    SUM(ps.ExecutionCount) AS ExecutionCount
FROM dbo.ProcedureStats ps
INNER JOIN dbo.Servers s ON ps.ServerID = s.ServerID
WHERE ps.CollectionTime >= DATEADD(hour, -24, GETUTCDATE())
GROUP BY s.ServerID, s.ServerName, ps.DatabaseName, ps.ProcedureName
ORDER BY AvgDurationMs DESC
```

### Code Browser Dashboard (Existing)

**Phase 1.25 Code Browser** already supports:
- Expandable tree view of all databases/objects
- Click to view code (read-only)

**Enhancement**: Add "Edit in Code Editor" button

```json
{
  "type": "table",
  "fieldConfig": {
    "overrides": [
      {
        "matcher": { "id": "byName", "options": "ObjectName" },
        "properties": [
          {
            "id": "links",
            "value": [
              {
                "title": "View Code (Read-Only)",
                "url": "/d/code-browser?var-object=${__value.text}",
                "targetBlank": false
              },
              {
                "title": "Edit in Code Editor ✏️",
                "url": "/a/sqlmonitor-codeeditor-app/editor?server=${__field.labels.ServerId}&db=${__field.labels.DatabaseName}&object=${__value.text}",
                "targetBlank": true
              }
            ]
          }
        ]
      }
    ]
  }
}
```

---

## Context Menu Actions

### Right-Click on Code Tokens

**Table Names** (e.g., `dbo.Customers`):
- Go to Definition (F12)
- Peek Definition (Alt+F12)
- Find All References (Shift+F12)
- View Table Data (Top 1000 rows)
- View Table Schema
- Design Table
- Script as SELECT
- Script as INSERT
- Copy Qualified Name

**Stored Procedure Names** (e.g., `dbo.usp_GetOrders`):
- Go to Definition (F12)
- Peek Definition (Alt+F12)
- Find All References (Shift+F12)
- Execute Procedure
- View Execution Plan
- Analyze Performance (last 24h)
- Script as EXEC
- Script as CREATE
- Script as ALTER
- Copy Qualified Name

**Column Names** (after IntelliSense recognizes context):
- Go to Table Definition
- View Column Statistics
- Find Column Usage
- Copy Column Name

### Implementation

```typescript
// Register Monaco context menu
editor.addAction({
  id: 'sql.goToDefinition',
  label: 'Go to Definition',
  keybindings: [monaco.KeyCode.F12],
  contextMenuGroupId: 'navigation',
  contextMenuOrder: 1,
  run: async (editor) => {
    const position = editor.getPosition();
    const word = editor.getModel().getWordAtPosition(position);
    if (!word) return;

    const objectName = parseObjectName(word.word);
    await goToDefinition(objectName);
  },
});

editor.addAction({
  id: 'sql.findReferences',
  label: 'Find All References',
  keybindings: [monaco.KeyMod.Shift | monaco.KeyCode.F12],
  contextMenuGroupId: 'navigation',
  contextMenuOrder: 2,
  run: async (editor) => {
    const position = editor.getPosition();
    const word = editor.getModel().getWordAtPosition(position);
    if (!word) return;

    const objectName = parseObjectName(word.word);
    await findReferences(objectName);
  },
});

editor.addAction({
  id: 'sql.viewTableData',
  label: 'View Table Data (Top 1000)',
  contextMenuGroupId: 'sql',
  contextMenuOrder: 1,
  precondition: 'editorHasSelection && selectedTextIsTableName',
  run: async (editor) => {
    const position = editor.getPosition();
    const word = editor.getModel().getWordAtPosition(position);
    if (!word) return;

    const tableName = parseObjectName(word.word);
    await viewTableData(tableName);
  },
});
```

---

## Implementation Plan

### Week 1 Day 3 Extension (+3 hours)

**Total Week 1**: 15h → 18h

**Add Navigation Foundations**:

1. **URL Routing** (1.5h):
   - Install `react-router-dom` (already in package.json)
   - Create routes for `/editor`, `/scripts`, `/config`
   - Parse query parameters (`server`, `db`, `object`, `script`, `line`)
   - Update URL when opening objects

2. **Tab Management** (1.5h):
   - Create `TabBar` component
   - Tab state management (open, close, switch, pin)
   - Persist tabs to localStorage
   - Unsaved changes indicator (● dot)

**Files to Create**:
- `src/components/App/App.tsx` - React Router setup
- `src/components/CodeEditor/TabBar.tsx` - Tab management UI
- `src/services/tabStateService.ts` - Tab state persistence

### Week 2 Day 8 Extension (+6 hours)

**Original**: IntelliSense (4h) + Formatter (1h) + Snippets (1h) = 6h
**Extended**: +6h for navigation = 12h total

**Add Navigation Features**:

1. **Quick Open Dialog** (2h):
   - Create `QuickOpenDialog.tsx` component
   - Integrate Fuse.js for fuzzy search
   - Recent files, saved scripts, database objects
   - Keyboard navigation (Up/Down/Enter)

2. **Object Browser Sidebar** (3h):
   - Create `ObjectBrowserPanel.tsx` component
   - Tree view with expand/collapse
   - Load servers/databases from API
   - Context menu actions

3. **Go to Definition** (1h):
   - Register Monaco definition provider
   - Parse object names under cursor
   - Fetch object definitions from API
   - Open in new tab or navigate

### Week 3 Extension (+2 hours)

**Add After Query Execution**:

1. **Find All References** (1h):
   - Create `ReferencesPanel.tsx` component
   - SQL query to find object dependencies
   - Show references grouped by type

2. **Hyperlink Support** (1h):
   - Update dashboard JSON templates
   - Add "Open in Code Editor" links
   - Test deep linking from dashboards

### Total Navigation Time: +11 hours

**Updated Feature #7 Estimate**: 75h → 86h

---

## API Endpoints Needed

### Object Metadata

```csharp
// GET /api/code/objects/definition
// Returns: CREATE TABLE/VIEW/PROCEDURE script
public class GetObjectDefinitionRequest
{
    public int ServerId { get; set; }
    public string DatabaseName { get; set; }
    public string ObjectName { get; set; } // Fully qualified: dbo.Customers
    public string ObjectType { get; set; } // table, view, procedure, function
}

public class GetObjectDefinitionResponse
{
    public bool Success { get; set; }
    public string Code { get; set; }
    public string ObjectType { get; set; }
    public DateTime CreatedDate { get; set; }
    public DateTime ModifiedDate { get; set; }
    public string Error { get; set; }
}
```

### Object References

```csharp
// GET /api/code/objects/references
// Returns: List of objects that reference this object
public class GetObjectReferencesRequest
{
    public int ServerId { get; set; }
    public string DatabaseName { get; set; }
    public string ObjectName { get; set; }
    public string SchemaName { get; set; } // Default: dbo
}

public class ObjectReference
{
    public string ReferencingSchema { get; set; }
    public string ReferencingObject { get; set; }
    public string ObjectType { get; set; } // P (procedure), V (view), FN (function)
    public int LineNumber { get; set; }
}

public class GetObjectReferencesResponse
{
    public bool Success { get; set; }
    public List<ObjectReference> References { get; set; }
    public int TotalCount { get; set; }
    public string Error { get; set; }
}
```

### Object Search

```csharp
// GET /api/code/objects/search
// Returns: Fuzzy search results across all objects
public class SearchObjectsRequest
{
    public int? ServerId { get; set; } // Optional filter
    public string DatabaseName { get; set; } // Optional filter
    public string Query { get; set; } // Search term
    public string[] ObjectTypes { get; set; } // Filter by types
    public int MaxResults { get; set; } // Default: 50
}

public class ObjectSearchResult
{
    public int ServerId { get; set; }
    public string ServerName { get; set; }
    public string DatabaseName { get; set; }
    public string SchemaName { get; set; }
    public string ObjectName { get; set; }
    public string ObjectType { get; set; }
    public string FullyQualifiedName { get; set; } // dbo.usp_GetOrders
}

public class SearchObjectsResponse
{
    public bool Success { get; set; }
    public List<ObjectSearchResult> Results { get; set; }
    public int TotalCount { get; set; }
    public string Error { get; set; }
}
```

---

## Database Schema Extensions

### Navigation Metadata Tables

```sql
-- Track recently accessed objects per user
CREATE TABLE dbo.UserObjectHistory (
    UserObjectHistoryID BIGINT IDENTITY(1,1) PRIMARY KEY,
    UserID INT NOT NULL REFERENCES dbo.Users(UserID),
    ServerID INT NOT NULL REFERENCES dbo.Servers(ServerID),
    DatabaseName NVARCHAR(128) NOT NULL,
    SchemaName NVARCHAR(128) NOT NULL,
    ObjectName NVARCHAR(128) NOT NULL,
    ObjectType VARCHAR(20) NOT NULL, -- table, view, procedure, function
    LastAccessedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    AccessCount INT NOT NULL DEFAULT 1,
    INDEX IX_UserObjectHistory_User_LastAccessed (UserID, LastAccessedAt DESC)
);

-- Track object favorites/bookmarks
CREATE TABLE dbo.UserObjectFavorites (
    UserObjectFavoriteID BIGINT IDENTITY(1,1) PRIMARY KEY,
    UserID INT NOT NULL REFERENCES dbo.Users(UserID),
    ServerID INT NOT NULL REFERENCES dbo.Servers(ServerID),
    DatabaseName NVARCHAR(128) NOT NULL,
    SchemaName NVARCHAR(128) NOT NULL,
    ObjectName NVARCHAR(128) NOT NULL,
    ObjectType VARCHAR(20) NOT NULL,
    CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    UNIQUE (UserID, ServerID, DatabaseName, SchemaName, ObjectName)
);
```

### Stored Procedures

```sql
-- Log object access
CREATE PROCEDURE dbo.usp_LogObjectAccess
    @UserID INT,
    @ServerID INT,
    @DatabaseName NVARCHAR(128),
    @SchemaName NVARCHAR(128),
    @ObjectName NVARCHAR(128),
    @ObjectType VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    -- Update existing or insert new
    MERGE dbo.UserObjectHistory AS target
    USING (
        SELECT @UserID AS UserID, @ServerID AS ServerID, @DatabaseName AS DatabaseName,
               @SchemaName AS SchemaName, @ObjectName AS ObjectName, @ObjectType AS ObjectType
    ) AS source
    ON target.UserID = source.UserID
       AND target.ServerID = source.ServerID
       AND target.DatabaseName = source.DatabaseName
       AND target.SchemaName = source.SchemaName
       AND target.ObjectName = source.ObjectName
    WHEN MATCHED THEN
        UPDATE SET
            LastAccessedAt = SYSUTCDATETIME(),
            AccessCount = AccessCount + 1
    WHEN NOT MATCHED THEN
        INSERT (UserID, ServerID, DatabaseName, SchemaName, ObjectName, ObjectType, LastAccessedAt, AccessCount)
        VALUES (source.UserID, source.ServerID, source.DatabaseName, source.SchemaName, source.ObjectName, source.ObjectType, SYSUTCDATETIME(), 1);
END;
GO

-- Get recent objects for user
CREATE PROCEDURE dbo.usp_GetRecentObjects
    @UserID INT,
    @MaxResults INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (@MaxResults)
        h.ServerID,
        s.ServerName,
        h.DatabaseName,
        h.SchemaName,
        h.ObjectName,
        h.ObjectType,
        h.LastAccessedAt,
        h.AccessCount
    FROM dbo.UserObjectHistory h
    INNER JOIN dbo.Servers s ON h.ServerID = s.ServerID
    WHERE h.UserID = @UserID
    ORDER BY h.LastAccessedAt DESC;
END;
GO
```

---

## Success Criteria

**Navigation is successful when**:

1. ✅ **Deep Linking Works**:
   - User clicks procedure name in Grafana dashboard
   - Code Editor opens with that procedure loaded
   - URL contains all necessary parameters

2. ✅ **Quick Open is Fast**:
   - Ctrl+P opens dialog in <100ms
   - Fuzzy search returns results in <200ms
   - Can search across 1000+ objects smoothly

3. ✅ **Multi-Tab Works Like VSCode**:
   - Open 10+ tabs without performance issues
   - Tabs persist across page refreshes
   - Unsaved changes are tracked correctly

4. ✅ **Go to Definition is Accurate**:
   - F12 on table name opens CREATE TABLE script
   - F12 on procedure name opens CREATE PROCEDURE script
   - Handles 3-part names (Server.Database.Schema.Object)

5. ✅ **Object Browser is Usable**:
   - Loads 100+ servers with 1000+ objects
   - Filtering/search updates in <100ms
   - Context menu shows relevant actions

6. ✅ **Browser Navigation Works**:
   - Back button returns to previous object
   - Forward button re-navigates
   - URL updates when switching tabs

---

## Future Enhancements (Phase 4+)

### Advanced Navigation

1. **Breadcrumb Navigation** - `Server > Database > Schema > Object`
2. **Symbol Outline** - Show functions, triggers, variables in sidebar
3. **Minimap Decorations** - Show errors, warnings, breakpoints in minimap
4. **Code Lens** - Show references count above definitions
5. **Hover Tooltips** - Show table schema on hover
6. **Parameter Hints** - Show procedure parameters as you type

### Collaboration

1. **Shared Tabs** - Share editor state via URL
2. **Real-time Collaboration** - Multi-user editing (like Google Docs)
3. **Comments** - Add inline comments to code
4. **Code Reviews** - Approve/reject changes

### Performance

1. **Virtual Scrolling** - Handle 100k+ line files
2. **Incremental Parsing** - Parse code as you type
3. **Web Workers** - Offload analysis to background thread
4. **IndexedDB** - Store object cache in browser

---

**Document Version**: 1.0
**Last Updated**: 2025-11-02
**Status**: Ready for Implementation
