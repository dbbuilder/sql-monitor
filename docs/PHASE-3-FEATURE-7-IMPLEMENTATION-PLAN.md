# Phase 3 Feature #7 - T-SQL Code Editor Implementation Plan

**Feature**: Grafana App Plugin for T-SQL Code Editing, Analysis, and Query Execution
**Status**: Planning Complete - Ready for Implementation
**Total Estimated Time**: 55 hours (5 weeks)
**Start Date**: 2025-11-02
**Target Completion**: 2025-12-06

---

## Overview

This document provides a detailed, step-by-step implementation plan for Feature #7: T-SQL Code Editor with integrated code analysis and query execution capabilities.

**Deliverables**:
1. Grafana app plugin with Monaco Editor integration
2. T-SQL code analysis engine with ~30 rules
3. Query execution with results grid
4. Index recommendations based on monitoring data
5. SolarWinds DPA-inspired features (percentiles, query rewrites, wait categorization)

**Related Documents**:
- Architecture: `PHASE-3-FEATURE-7-PLUGIN-ARCHITECTURE.md`
- Planning: `PHASE-3-FEATURE-7-CODE-EDITOR-PLAN.md`
- Competitive Analysis: `COMPETITIVE-FEATURE-ANALYSIS.md`
- Future Rules: `FUTURE-ANALYSIS-RULES-REFERENCE.md`

---

## Week 1: Core Editor Foundation (10 hours)

### Day 1: Plugin Scaffolding (3 hours)

**Task 1.1**: Create plugin structure with @grafana/create-plugin
```bash
cd /mnt/d/Dev2/sql-monitor
mkdir grafana-plugins
cd grafana-plugins

npx @grafana/create-plugin@latest
# Select: app
# Plugin name: sqlmonitor-codeeditor-app
# Organization: sqlmonitor

cd sqlmonitor-codeeditor-app
npm install
```

**Deliverables**:
- ✅ Plugin directory structure created
- ✅ package.json with dependencies configured
- ✅ TypeScript config (tsconfig.json)
- ✅ Webpack config
- ✅ Docker Compose for development

**Verification**:
```bash
npm run dev
docker compose up
# Access http://localhost:3000
# Verify plugin appears in Administration > Plugins
```

---

**Task 1.2**: Configure plugin metadata (plugin.json)

Edit `src/plugin.json`:
```json
{
  "type": "app",
  "name": "SQL Monitor Code Editor",
  "id": "sqlmonitor-codeeditor-app",
  "info": {
    "description": "T-SQL code editor with real-time analysis, query execution, and index recommendations",
    "author": {
      "name": "SQL Monitor",
      "url": "https://github.com/sql-monitor"
    },
    "keywords": ["sql", "tsql", "code editor", "analysis", "monitoring"],
    "version": "1.0.0",
    "updated": "2025-11-02"
  },
  "includes": [
    {
      "type": "page",
      "name": "Code Editor",
      "path": "/a/sqlmonitor-codeeditor-app/editor",
      "role": "Viewer",
      "addToNav": true,
      "defaultNav": true
    },
    {
      "type": "page",
      "name": "Configuration",
      "path": "/a/sqlmonitor-codeeditor-app/config",
      "role": "Admin",
      "addToNav": true
    }
  ],
  "dependencies": {
    "grafanaDependency": ">=10.0.0",
    "plugins": []
  }
}
```

**Deliverables**:
- ✅ Plugin metadata configured
- ✅ Two pages defined (Editor, Configuration)
- ✅ Navigation menu entries added

---

**Task 1.3**: Install additional dependencies

```bash
npm install --save @monaco-editor/react ag-grid-react ag-grid-community lodash
npm install --save-dev @types/node @types/lodash
```

**Deliverables**:
- ✅ Monaco Editor React wrapper installed
- ✅ ag-Grid for results display installed
- ✅ TypeScript type definitions installed

---

### Day 2: Basic Layout & Routing (4 hours)

**Task 1.4**: Create type definitions

Create `src/types/analysis.ts`:
```typescript
export type Severity = 'Error' | 'Warning' | 'Info';
export type Category = 'Performance' | 'Deprecated' | 'Security' | 'CodeSmell' | 'Design' | 'Naming';

export interface AnalysisResult {
  ruleId: string;
  severity: Severity;
  category: Category;
  message: string;
  line: number;
  column: number;
  before: string | null;
  after: string | null;
  explanation: string | null;
}

export interface FixSuggestion {
  ruleId: string;
  description: string;
  before: string;
  after: string;
  explanation: string;
  estimatedImpact: 'Low' | 'Medium' | 'High' | 'Very High';
  autoFixAvailable: boolean;
}
```

Create `src/types/query.ts`:
```typescript
export interface QueryRequest {
  serverId: number;
  databaseName: string;
  query: string;
  timeout?: number;
  includeExecutionPlan?: boolean;
}

export interface QueryResult {
  success: boolean;
  executionTime: number;
  rowCount: number;
  columns: ColumnInfo[];
  rows: any[];
  messages: string[];
  executionPlan?: ExecutionPlan;
  error?: string;
}

export interface ColumnInfo {
  name: string;
  type: string;
  nullable: boolean;
}

export interface ExecutionPlan {
  xml: string;
  estimatedCost: number;
  warnings: string[];
}
```

**Deliverables**:
- ✅ Type definitions for analysis results
- ✅ Type definitions for query execution
- ✅ Type definitions for fix suggestions

---

**Task 1.5**: Create CodeEditorPage layout

Create `src/components/CodeEditor/CodeEditorPage.tsx`:
```typescript
import React, { useState } from 'react';
import { css } from '@emotion/css';
import { useStyles2 } from '@grafana/ui';
import { GrafanaTheme2 } from '@grafana/data';

export const CodeEditorPage: React.FC = () => {
  const styles = useStyles2(getStyles);
  const [code, setCode] = useState<string>('');

  return (
    <div className={styles.container}>
      <div className={styles.toolbar}>
        <h2>T-SQL Code Editor</h2>
        {/* Toolbar actions will go here */}
      </div>
      <div className={styles.editorContainer}>
        <div className={styles.editor}>
          {/* Monaco Editor will go here */}
          <textarea
            className={styles.placeholder}
            value={code}
            onChange={(e) => setCode(e.target.value)}
            placeholder="Write or paste T-SQL code here..."
          />
        </div>
        <div className={styles.sidebar}>
          {/* Analysis panel will go here */}
          <h3>Analysis Results</h3>
          <p>Run analysis to see results</p>
        </div>
      </div>
    </div>
  );
};

const getStyles = (theme: GrafanaTheme2) => ({
  container: css`
    display: flex;
    flex-direction: column;
    height: 100%;
    padding: ${theme.spacing(2)};
  `,
  toolbar: css`
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: ${theme.spacing(2)};
    padding: ${theme.spacing(1)};
    background: ${theme.colors.background.secondary};
    border-radius: ${theme.shape.borderRadius()};
  `,
  editorContainer: css`
    display: flex;
    gap: ${theme.spacing(2)};
    flex: 1;
  `,
  editor: css`
    flex: 3;
    border: 1px solid ${theme.colors.border.medium};
    border-radius: ${theme.shape.borderRadius()};
  `,
  sidebar: css`
    flex: 1;
    background: ${theme.colors.background.secondary};
    border-radius: ${theme.shape.borderRadius()};
    padding: ${theme.spacing(2)};
  `,
  placeholder: css`
    width: 100%;
    height: 100%;
    padding: ${theme.spacing(2)};
    font-family: monospace;
    font-size: 14px;
    border: none;
    background: ${theme.colors.background.primary};
    color: ${theme.colors.text.primary};
    resize: none;
  `
});
```

**Deliverables**:
- ✅ Basic page layout with toolbar, editor area, sidebar
- ✅ Grafana theme integration
- ✅ Placeholder textarea (will be replaced with Monaco)

---

**Task 1.6**: Configure routing in App.tsx

Edit `src/components/App/App.tsx`:
```typescript
import React from 'react';
import { Route, Routes } from 'react-router-dom';
import { CodeEditorPage } from '../CodeEditor/CodeEditorPage';
import { ConfigPage } from '../Config/ConfigPage';

export function App() {
  return (
    <Routes>
      <Route path="/editor" element={<CodeEditorPage />} />
      <Route path="/config" element={<ConfigPage />} />
      <Route path="/" element={<CodeEditorPage />} />
    </Routes>
  );
}
```

**Deliverables**:
- ✅ Routing configured for Editor and Config pages
- ✅ Default route points to Editor page

---

### Day 3: Monaco Editor Integration (3 hours)

**Task 1.7**: Create EditorPanel component

Create `src/components/CodeEditor/EditorPanel.tsx`:
```typescript
import React from 'react';
import { CodeEditor } from '@grafana/ui';
import { AnalysisResult } from '../../types/analysis';

interface EditorPanelProps {
  value: string;
  onChange: (value: string) => void;
  analysisResults: AnalysisResult[];
}

export const EditorPanel: React.FC<EditorPanelProps> = ({
  value,
  onChange,
  analysisResults
}) => {
  const handleEditorDidMount = (editor: any, monaco: any) => {
    console.log('Monaco editor mounted');

    // Add Ctrl+S / Cmd+S save action
    editor.addAction({
      id: 'save-code',
      label: 'Save Code',
      keybindings: [
        monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS
      ],
      run: (ed: any) => {
        const code = ed.getValue();
        onChange(code);
        console.log('Code saved');
      }
    });
  };

  return (
    <CodeEditor
      value={value}
      language="sql"
      width="100%"
      height="600px"
      showLineNumbers={true}
      showMiniMap={true}
      onBlur={(code) => onChange(code)}
      onSave={(code) => onChange(code)}
      onEditorDidMount={handleEditorDidMount}
      monacoOptions={{
        tabSize: 4,
        fontSize: 14,
        formatOnPaste: true,
        formatOnType: true,
        automaticLayout: true,
        minimap: { enabled: true },
        scrollbar: {
          vertical: 'auto',
          horizontal: 'auto',
          useShadows: true
        }
      }}
    />
  );
};
```

**Deliverables**:
- ✅ Monaco Editor integrated via Grafana CodeEditor component
- ✅ SQL syntax highlighting enabled
- ✅ Line numbers and minimap enabled
- ✅ Save action (Ctrl+S) configured

---

**Task 1.8**: Update CodeEditorPage to use EditorPanel

```typescript
// In CodeEditorPage.tsx
import { EditorPanel } from './EditorPanel';

// Replace placeholder textarea with:
<div className={styles.editor}>
  <EditorPanel
    value={code}
    onChange={setCode}
    analysisResults={[]}
  />
</div>
```

**Deliverables**:
- ✅ EditorPanel integrated into main page
- ✅ Code state managed in CodeEditorPage
- ✅ Monaco Editor functional with SQL highlighting

---

**Week 1 Checkpoint**:
- ✅ Plugin scaffolded and running in Grafana
- ✅ Monaco Editor integrated with SQL syntax highlighting
- ✅ Basic layout with editor, toolbar, sidebar
- ✅ Type definitions in place
- ✅ Routing configured

---

## Week 2: Code Analysis Engine (20 hours)

### Day 4-5: Analysis Engine Foundation (8 hours)

**Task 2.1**: Create RuleBase interface

Create `src/components/Analysis/RuleBase.ts`:
```typescript
import { AnalysisResult, FixSuggestion } from '../../types/analysis';

export interface AnalysisRule {
  ruleId: string;
  severity: 'Error' | 'Warning' | 'Info';
  category: 'Performance' | 'Deprecated' | 'Security' | 'CodeSmell' | 'Design' | 'Naming';
  message: string;
  enabled: boolean;

  detect(code: string): Promise<AnalysisResult[]>;
  suggest?(match: AnalysisResult): FixSuggestion | null;
}

export abstract class BaseRule implements AnalysisRule {
  abstract ruleId: string;
  abstract severity: 'Error' | 'Warning' | 'Info';
  abstract category: 'Performance' | 'Deprecated' | 'Security' | 'CodeSmell' | 'Design' | 'Naming';
  abstract message: string;
  enabled = true;

  abstract detect(code: string): Promise<AnalysisResult[]>;

  suggest(match: AnalysisResult): FixSuggestion | null {
    return null;  // Override in subclass if fix available
  }

  protected getLineNumber(code: string, index: number): number {
    return code.substring(0, index).split('\n').length;
  }

  protected getColumnNumber(code: string, index: number): number {
    const lastNewline = code.lastIndexOf('\n', index);
    return index - lastNewline;
  }

  protected createResult(
    line: number,
    column: number,
    before: string,
    after: string | null = null,
    explanation: string | null = null
  ): AnalysisResult {
    return {
      ruleId: this.ruleId,
      severity: this.severity,
      category: this.category,
      message: this.message,
      line,
      column,
      before,
      after,
      explanation
    };
  }
}
```

**Deliverables**:
- ✅ AnalysisRule interface defined
- ✅ BaseRule abstract class with helper methods
- ✅ Line/column calculation utilities
- ✅ Result creation helper

---

**Task 2.2**: Create AnalysisEngine

Create `src/components/Analysis/AnalysisEngine.ts`:
```typescript
import { AnalysisRule } from './RuleBase';
import { AnalysisResult } from '../../types/analysis';

export class AnalysisEngine {
  private rules: AnalysisRule[] = [];

  constructor(rules: AnalysisRule[]) {
    this.rules = rules;
  }

  public async analyze(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];

    for (const rule of this.rules) {
      if (!rule.enabled) {
        continue;
      }

      try {
        const ruleResults = await rule.detect(code);
        results.push(...ruleResults);
      } catch (error) {
        console.error(`Rule ${rule.ruleId} failed:`, error);
      }
    }

    // Sort by severity (Error > Warning > Info), then by line number
    return this.sortResults(results);
  }

  public getRuleById(ruleId: string): AnalysisRule | undefined {
    return this.rules.find(r => r.ruleId === ruleId);
  }

  public enableRule(ruleId: string): void {
    const rule = this.getRuleById(ruleId);
    if (rule) {
      rule.enabled = true;
    }
  }

  public disableRule(ruleId: string): void {
    const rule = this.getRuleById(ruleId);
    if (rule) {
      rule.enabled = false;
    }
  }

  public getEnabledRules(): AnalysisRule[] {
    return this.rules.filter(r => r.enabled);
  }

  private sortResults(results: AnalysisResult[]): AnalysisResult[] {
    const severityOrder = { Error: 0, Warning: 1, Info: 2 };
    return results.sort((a, b) => {
      if (severityOrder[a.severity] !== severityOrder[b.severity]) {
        return severityOrder[a.severity] - severityOrder[b.severity];
      }
      return a.line - b.line;
    });
  }
}
```

**Deliverables**:
- ✅ AnalysisEngine class with analyze() method
- ✅ Rule management (enable/disable)
- ✅ Result sorting by severity and line number
- ✅ Error handling for failed rules

---

### Day 6-8: Implement 30 Analysis Rules (12 hours)

**Task 2.3**: Performance Rules (P001-P010) - 4 hours

Create `src/components/Analysis/rules/PerformanceRules.ts`:

Implement 10 rules:
- P001: SELECT * detection
- P002: Missing WHERE clause on large tables
- P003: CURSOR usage
- P004: Functions in WHERE clause (non-SARGable)
- P005: Scalar UDF in SELECT list
- P006: SELECT DISTINCT without understanding
- P007: Nested loops on large datasets
- P008: Implicit conversions
- P009: LIKE with leading wildcard
- P010: Multiple OR conditions

**Example Implementation**:
```typescript
import { BaseRule } from '../RuleBase';
import { AnalysisResult, FixSuggestion } from '../../../types/analysis';

export class SelectStarRule extends BaseRule {
  ruleId = 'P001';
  severity = 'Warning' as const;
  category = 'Performance' as const;
  message = 'SELECT * used - specify explicit columns for maintainability';

  async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    const regex = /SELECT\s+\*/gi;
    let match;

    while ((match = regex.exec(code)) !== null) {
      const line = this.getLineNumber(code, match.index);
      const column = this.getColumnNumber(code, match.index);
      results.push(this.createResult(line, column, match[0]));
    }

    return results;
  }

  suggest(match: AnalysisResult): FixSuggestion {
    return {
      ruleId: this.ruleId,
      description: 'Replace SELECT * with explicit column list',
      before: 'SELECT *',
      after: 'SELECT [Col1], [Col2], [Col3]',
      explanation: 'Explicit columns improve maintainability, reduce network traffic, and prevent breaking changes',
      estimatedImpact: 'Medium',
      autoFixAvailable: false
    };
  }
}

// Export all performance rules
export const performanceRules = [
  new SelectStarRule(),
  new MissingWhereRule(),
  new CursorUsageRule(),
  new NonSargableFunctionRule(),
  new ScalarUdfRule(),
  new SelectDistinctRule(),
  new NestedLoopRule(),
  new ImplicitConversionRule(),
  new LeadingWildcardRule(),
  new MultipleOrRule()
];
```

**Deliverables**:
- ✅ 10 performance rules implemented
- ✅ Each rule with detect() method
- ✅ Fix suggestions for applicable rules
- ✅ All rules exported as array

---

**Task 2.4**: Deprecated Features Rules (DP001-DP008) - 2 hours

Create `src/components/Analysis/rules/DeprecatedRules.ts`:

Implement 8 rules:
- DP001: TEXT, NTEXT, IMAGE types
- DP002: FASTFIRSTROW hint
- DP003: GROUP BY ALL
- DP004: TIMESTAMP datatype
- DP005: Old outer join syntax (*=, =*)
- DP006: READTEXT, WRITETEXT, UPDATETEXT
- DP007: sp_ prefix for user procedures
- DP008: @@ROWCOUNT after IF EXISTS

**Deliverables**:
- ✅ 8 deprecated feature rules implemented
- ✅ Fix suggestions with modern alternatives

---

**Task 2.5**: Security Rules (S001-S005) - 2 hours

Create `src/components/Analysis/rules/SecurityRules.ts`:

Implement 5 rules:
- S001: SQL injection patterns
- S002: xp_cmdshell usage
- S003: Plaintext passwords in code
- S004: Dynamic SQL without sp_executesql
- S005: EXECUTE string without parameters

**Deliverables**:
- ✅ 5 security rules implemented
- ✅ High severity (Error level)
- ✅ Fix suggestions with parameterization

---

**Task 2.6**: Code Smell Rules (C001-C008) - 2 hours

Create `src/components/Analysis/rules/CodeSmellRules.ts`:

Implement 8 rules:
- C001: Missing error handling (no TRY/CATCH)
- C002: Missing NOCOUNT in procedures
- C003: Missing transaction handling
- C004: Uncommitted transactions
- C005: Excessive nesting depth (>4 levels)
- C006: Long procedures (>300 lines)
- C007: Too many parameters (>10)
- C008: Missing comments on complex logic

**Deliverables**:
- ✅ 8 code smell rules implemented
- ✅ Maintainability-focused

---

**Task 2.7**: Design Rules (D001-D005) - 1 hour

Create `src/components/Analysis/rules/DesignRules.ts`:

Implement 5 rules:
- D001: Missing primary key
- D002: Heap tables (no clustered index)
- D003: Wide tables (>15 columns)
- D004: Missing foreign key constraints
- D005: Nullable columns in primary keys

**Deliverables**:
- ✅ 5 design rules implemented
- ✅ Schema analysis focused

---

**Task 2.8**: Naming Convention Rules (N001-N005) - 1 hour

Create `src/components/Analysis/rules/NamingRules.ts`:

Implement 5 rules:
- N001: sp_ prefix on user procedures
- N002: Hungarian notation detection
- N003: Inconsistent naming (PascalCase vs snake_case)
- N004: Reserved keyword usage
- N005: Unclear abbreviations

**Deliverables**:
- ✅ 5 naming convention rules implemented
- ✅ Configurable (low priority warnings)

---

**Week 2 Checkpoint**:
- ✅ AnalysisEngine operational
- ✅ 30 analysis rules implemented across 6 categories
- ✅ Fix suggestions for applicable rules
- ✅ Error handling and sorting

---

## Week 3: Query Execution & Results (10 hours)

### Day 9-10: API Client & Query Execution (6 hours)

**Task 3.1**: Create API client service

Create `src/services/apiClient.ts`:
```typescript
import { getBackendSrv } from '@grafana/runtime';
import { QueryRequest, QueryResult } from '../types/query';

export class SqlMonitorApiClient {
  private baseUrl: string;

  constructor(baseUrl: string = '/api/datasources/proxy/1') {
    this.baseUrl = baseUrl;
  }

  async executeQuery(request: QueryRequest): Promise<QueryResult> {
    try {
      const response = await getBackendSrv().post(
        `${this.baseUrl}/api/query/execute`,
        request
      );
      return response;
    } catch (error: any) {
      console.error('Query execution failed:', error);
      return {
        success: false,
        executionTime: 0,
        rowCount: 0,
        columns: [],
        rows: [],
        messages: [],
        error: error.message || 'Unknown error'
      };
    }
  }

  async getServers(): Promise<any[]> {
    try {
      const response = await getBackendSrv().get(`${this.baseUrl}/api/servers`);
      return response;
    } catch (error) {
      console.error('Failed to get servers:', error);
      return [];
    }
  }

  async getDatabases(serverId: number): Promise<string[]> {
    try {
      const response = await getBackendSrv().get(
        `${this.baseUrl}/api/servers/${serverId}/databases`
      );
      return response;
    } catch (error) {
      console.error('Failed to get databases:', error);
      return [];
    }
  }
}
```

**Deliverables**:
- ✅ API client with executeQuery method
- ✅ getServers and getDatabases helpers
- ✅ Error handling

---

**Task 3.2**: Create ASP.NET Core API endpoint

In `api/Controllers/`, create `QueryController.cs`:
```csharp
using Microsoft.AspNetCore.Mvc;
using System.Data;
using Microsoft.Data.SqlClient;

[ApiController]
[Route("api/query")]
public class QueryController : ControllerBase
{
    private readonly ISqlService _sqlService;

    [HttpPost("execute")]
    public async Task<ActionResult<QueryResult>> ExecuteQuery([FromBody] QueryRequest request)
    {
        var result = new QueryResult
        {
            Success = false,
            ExecutionTime = 0,
            RowCount = 0,
            Columns = new List<ColumnInfo>(),
            Rows = new List<Dictionary<string, object>>(),
            Messages = new List<string>()
        };

        var startTime = DateTime.UtcNow;

        try
        {
            using var connection = new SqlConnection(GetConnectionString(request.ServerId));
            await connection.OpenAsync();

            using var command = new SqlCommand(request.Query, connection);
            command.CommandTimeout = request.Timeout ?? 60;

            using var reader = await command.ExecuteReaderAsync();

            // Get column info
            for (int i = 0; i < reader.FieldCount; i++)
            {
                result.Columns.Add(new ColumnInfo
                {
                    Name = reader.GetName(i),
                    Type = reader.GetDataTypeName(i),
                    Nullable = true  // Would need schema query for accurate info
                });
            }

            // Read rows
            while (await reader.ReadAsync())
            {
                var row = new Dictionary<string, object>();
                for (int i = 0; i < reader.FieldCount; i++)
                {
                    row[reader.GetName(i)] = reader.IsDBNull(i) ? null : reader.GetValue(i);
                }
                result.Rows.Add(row);
            }

            result.RowCount = result.Rows.Count;
            result.Success = true;
        }
        catch (Exception ex)
        {
            result.Error = ex.Message;
        }

        result.ExecutionTime = (int)(DateTime.UtcNow - startTime).TotalMilliseconds;
        return Ok(result);
    }
}
```

**Deliverables**:
- ✅ QueryController with execute endpoint
- ✅ Query execution with timeout
- ✅ Column metadata extraction
- ✅ Row data serialization

---

### Day 11: Results Grid (4 hours)

**Task 3.3**: Create ResultsPanel with ag-Grid

Create `src/components/CodeEditor/ResultsPanel.tsx`:
```typescript
import React, { useMemo } from 'react';
import { AgGridReact } from 'ag-grid-react';
import 'ag-grid-community/styles/ag-grid.css';
import 'ag-grid-community/styles/ag-theme-alpine.css';
import { QueryResult } from '../../types/query';

interface ResultsPanelProps {
  results: QueryResult;
}

export const ResultsPanel: React.FC<ResultsPanelProps> = ({ results }) => {
  const columnDefs = useMemo(() => {
    return results.columns.map(col => ({
      field: col.name,
      headerName: col.name,
      sortable: true,
      filter: true,
      resizable: true
    }));
  }, [results.columns]);

  return (
    <div style={{ height: '400px', width: '100%' }}>
      <div style={{ marginBottom: '10px' }}>
        <strong>Execution Time:</strong> {results.executionTime}ms |{' '}
        <strong>Rows:</strong> {results.rowCount}
        {results.error && (
          <div style={{ color: 'red', marginTop: '5px' }}>
            <strong>Error:</strong> {results.error}
          </div>
        )}
      </div>

      <div className="ag-theme-alpine" style={{ height: '350px', width: '100%' }}>
        <AgGridReact
          columnDefs={columnDefs}
          rowData={results.rows}
          pagination={true}
          paginationPageSize={100}
          enableCellTextSelection={true}
        />
      </div>
    </div>
  );
};
```

**Deliverables**:
- ✅ ag-Grid results display
- ✅ Sortable, filterable columns
- ✅ Pagination (100 rows per page)
- ✅ Execution time and row count display
- ✅ Error message display

---

**Task 3.4**: Create ToolbarActions component

Create `src/components/CodeEditor/ToolbarActions.tsx`:
```typescript
import React from 'react';
import { Button, Select } from '@grafana/ui';

interface ToolbarActionsProps {
  servers: any[];
  databases: string[];
  selectedServer: number | null;
  selectedDatabase: string | null;
  onServerChange: (serverId: number) => void;
  onDatabaseChange: (database: string) => void;
  onAnalyze: () => void;
  onExecute: () => void;
  isAnalyzing: boolean;
  isExecuting: boolean;
}

export const ToolbarActions: React.FC<ToolbarActionsProps> = ({
  servers,
  databases,
  selectedServer,
  selectedDatabase,
  onServerChange,
  onDatabaseChange,
  onAnalyze,
  onExecute,
  isAnalyzing,
  isExecuting
}) => {
  return (
    <div style={{ display: 'flex', gap: '10px', alignItems: 'center' }}>
      <Select
        options={servers.map(s => ({ label: s.ServerName, value: s.ServerID }))}
        value={selectedServer}
        onChange={(option) => onServerChange(option.value!)}
        placeholder="Select Server"
        width={30}
      />

      <Select
        options={databases.map(db => ({ label: db, value: db }))}
        value={selectedDatabase}
        onChange={(option) => onDatabaseChange(option.value!)}
        placeholder="Select Database"
        width={30}
        disabled={!selectedServer}
      />

      <Button onClick={onAnalyze} disabled={isAnalyzing} variant="secondary">
        {isAnalyzing ? 'Analyzing...' : 'Analyze'}
      </Button>

      <Button onClick={onExecute} disabled={isExecuting || !selectedServer} variant="primary">
        {isExecuting ? 'Executing...' : 'Execute'}
      </Button>
    </div>
  );
};
```

**Deliverables**:
- ✅ Server/database selection dropdowns
- ✅ Analyze and Execute buttons
- ✅ Loading states
- ✅ Disabled states when appropriate

---

**Week 3 Checkpoint**:
- ✅ API client operational
- ✅ Query execution endpoint in ASP.NET Core API
- ✅ Results grid with ag-Grid
- ✅ Toolbar with server/database selection

---

## Week 3-4: SolarWinds DPA Features (10 hours)

### Day 12-13: Response Time Percentiles (5 hours)

**Task 4.1**: Add percentile columns to ProcedureStats

```sql
-- In database/87-add-percentile-columns.sql
ALTER TABLE dbo.ProcedureStats ADD
    P50_DurationMs BIGINT NULL,
    P95_DurationMs BIGINT NULL,
    P99_DurationMs BIGINT NULL;
GO

-- Update usp_CollectProcedureStats
ALTER PROCEDURE dbo.usp_CollectProcedureStats
    @ServerID INT
AS
BEGIN
    -- Existing collection logic...

    -- Add percentile calculations
    SELECT
        @ServerID AS ServerID,
        DB_NAME(database_id) AS DatabaseName,
        OBJECT_NAME(object_id, database_id) AS ProcedureName,
        execution_count AS ExecutionCount,
        total_elapsed_time / execution_count / 1000 AS AvgDurationMs,
        max_elapsed_time / 1000 AS MaxDurationMs,
        -- NEW: Percentile calculations
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_elapsed_time / execution_count) OVER() / 1000 AS P50_DurationMs,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY total_elapsed_time / execution_count) OVER() / 1000 AS P95_DurationMs,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY total_elapsed_time / execution_count) OVER() / 1000 AS P99_DurationMs,
        GETUTCDATE() AS CollectionTime
    FROM sys.dm_exec_procedure_stats
    WHERE database_id = DB_ID(@DatabaseName);
END;
GO
```

**Deliverables**:
- ✅ Percentile columns added to ProcedureStats table
- ✅ Collection procedure updated with percentile calculation
- ✅ Deployed to production database

---

**Task 4.2**: Display percentiles in Code Editor

Create `src/components/IndexAdvisor/PerformanceInsights.tsx`:
```typescript
import React from 'react';

interface ProcedurePerformance {
  procedureName: string;
  avgDurationMs: number;
  p50DurationMs: number;
  p95DurationMs: number;
  p99DurationMs: number;
  executionCount: number;
}

export const PerformanceInsights: React.FC<{ stats: ProcedurePerformance }> = ({ stats }) => {
  const variance = (stats.p95DurationMs / stats.p50DurationMs).toFixed(2);
  const isHighVariance = parseFloat(variance) > 5;

  return (
    <div className="performance-card">
      <h4>{stats.procedureName}</h4>
      <table>
        <tbody>
          <tr>
            <td>Median (P50):</td>
            <td>{stats.p50DurationMs}ms</td>
          </tr>
          <tr>
            <td>95th Percentile:</td>
            <td>{stats.p95DurationMs}ms</td>
          </tr>
          <tr>
            <td>99th Percentile:</td>
            <td>{stats.p99DurationMs}ms</td>
          </tr>
          <tr>
            <td>P95/P50 Ratio:</td>
            <td>
              {variance}x
              {isHighVariance && (
                <span style={{ color: 'orange', marginLeft: '5px' }}>
                  ⚠️ High variance - investigate parameter sniffing
                </span>
              )}
            </td>
          </tr>
          <tr>
            <td>Executions:</td>
            <td>{stats.executionCount.toLocaleString()}</td>
          </tr>
        </tbody>
      </table>
    </div>
  );
};
```

**Deliverables**:
- ✅ Performance insights component
- ✅ Percentile display
- ✅ High variance warning (P95/P50 > 5x)

---

### Day 14: Query Rewrite Suggestions (3 hours)

**Task 4.3**: Implement query rewrite rules

Add to `src/components/Analysis/rules/QueryRewriteRules.ts`:

```typescript
// Rule: OR to IN conversion
export class OrToInRule extends BaseRule {
  ruleId = 'P050';
  severity = 'Info' as const;
  category = 'Performance' as const;
  message = 'Multiple OR conditions - consider using IN for better readability';

  async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    // Detect: WHERE col = 'A' OR col = 'B' OR col = 'C'
    const regex = /WHERE\s+(\w+)\s*=\s*'([^']+)'\s*(?:OR\s+\1\s*=\s*'([^']+)'\s*)+/gi;
    let match;

    while ((match = regex.exec(code)) !== null) {
      const line = this.getLineNumber(code, match.index);
      const column = this.getColumnNumber(code, match.index);
      results.push(this.createResult(line, column, match[0]));
    }

    return results;
  }

  suggest(match: AnalysisResult): FixSuggestion {
    return {
      ruleId: this.ruleId,
      description: 'Replace OR conditions with IN clause',
      before: "WHERE Status = 'Active' OR Status = 'Pending' OR Status = 'Processing'",
      after: "WHERE Status IN ('Active', 'Pending', 'Processing')",
      explanation: 'IN clause is more readable and may perform better with proper indexes',
      estimatedImpact: 'Low',
      autoFixAvailable: true
    };
  }
}

// Add 4-9 more rewrite rules...
```

Implement additional rewrite rules (total 5-10):
- P051: Subquery in SELECT list → JOIN
- P052: Non-SARGable LIKE → pattern optimization
- P053: DISTINCT masking design issues
- P054: Scalar UDF replacement with inline TVF

**Deliverables**:
- ✅ 5-10 query rewrite suggestion rules
- ✅ Auto-fix hints where applicable
- ✅ Estimated performance impact

---

### Day 15: Wait Time Categorization (2 hours)

**Task 4.4**: Create wait categorization function

Add to database:
```sql
CREATE FUNCTION dbo.fn_CategorizeWaitType (@WaitType NVARCHAR(60))
RETURNS VARCHAR(50)
AS
BEGIN
    RETURN CASE
        WHEN @WaitType IN ('SOS_SCHEDULER_YIELD', 'THREADPOOL', 'RESOURCE_SEMAPHORE')
            THEN 'CPU Pressure'
        WHEN @WaitType LIKE 'PAGEIOLATCH%' OR @WaitType LIKE 'WRITELOG%'
            THEN 'I/O Contention'
        WHEN @WaitType LIKE 'LCK%'
            THEN 'Blocking/Locking'
        WHEN @WaitType LIKE 'RESOURCE_SEMAPHORE%'
            THEN 'Memory Pressure'
        WHEN @WaitType LIKE 'ASYNC_NETWORK_IO%'
            THEN 'Network Latency'
        WHEN @WaitType LIKE 'CXPACKET%' OR @WaitType = 'CXCONSUMER'
            THEN 'Parallelism'
        ELSE 'Other'
    END;
END;
GO
```

**Deliverables**:
- ✅ Wait categorization function
- ✅ Deployed to MonitoringDB
- ✅ Tested with existing WaitStatistics data

---

**Week 3-4 Checkpoint**:
- ✅ Response time percentiles collected and displayed
- ✅ Query rewrite suggestions (5-10 rules)
- ✅ Wait time categorization
- ✅ Performance variance warnings

---

## Week 4: Polish & Documentation (5 hours)

### Day 16: AnalysisPanel Component (2 hours)

**Task 5.1**: Create AnalysisPanel

Create `src/components/CodeEditor/AnalysisPanel.tsx`:
```typescript
import React from 'react';
import { AnalysisResult } from '../../types/analysis';
import { Badge } from '@grafana/ui';

interface AnalysisPanelProps {
  results: AnalysisResult[];
  onResultClick: (result: AnalysisResult) => void;
}

export const AnalysisPanel: React.FC<AnalysisPanelProps> = ({ results, onResultClick }) => {
  const errorCount = results.filter(r => r.severity === 'Error').length;
  const warningCount = results.filter(r => r.severity === 'Warning').length;
  const infoCount = results.filter(r => r.severity === 'Info').length;

  const getSeverityColor = (severity: string) => {
    switch (severity) {
      case 'Error': return 'red';
      case 'Warning': return 'orange';
      case 'Info': return 'blue';
      default: return 'gray';
    }
  };

  return (
    <div className="analysis-panel">
      <div className="summary">
        <h3>Analysis Results</h3>
        <div className="counts">
          {errorCount > 0 && <Badge text={`${errorCount} Errors`} color="red" />}
          {warningCount > 0 && <Badge text={`${warningCount} Warnings`} color="orange" />}
          {infoCount > 0 && <Badge text={`${infoCount} Info`} color="blue" />}
        </div>
      </div>

      <div className="results-list">
        {results.length === 0 ? (
          <p>No issues found. Great job!</p>
        ) : (
          results.map((result, index) => (
            <div
              key={index}
              className="result-item"
              onClick={() => onResultClick(result)}
              style={{ cursor: 'pointer', borderLeft: `3px solid ${getSeverityColor(result.severity)}` }}
            >
              <div className="result-header">
                <Badge text={result.ruleId} color={getSeverityColor(result.severity)} />
                <span className="line-number">Line {result.line}</span>
              </div>
              <div className="result-message">{result.message}</div>
              {result.after && (
                <div className="result-fix">
                  <small>💡 Suggested fix: {result.after}</small>
                </div>
              )}
            </div>
          ))
        )}
      </div>
    </div>
  );
};
```

**Deliverables**:
- ✅ Analysis results sidebar
- ✅ Summary badges (error/warning/info counts)
- ✅ Clickable results (jump to line)
- ✅ Fix suggestions display

---

### Day 17: Documentation (3 hours)

**Task 5.2**: Create user documentation

Create `grafana-plugins/sqlmonitor-codeeditor-app/docs/USER-GUIDE.md`:

**Contents**:
1. Introduction
2. Getting Started
3. Code Editor Features
4. Analysis Rules Reference (all 30 rules)
5. Query Execution
6. Performance Insights
7. Configuration
8. Keyboard Shortcuts
9. Troubleshooting
10. FAQ

**Deliverables**:
- ✅ Comprehensive user guide (1000+ lines)
- ✅ Screenshots/examples for each feature
- ✅ Rule reference table

---

**Task 5.3**: Create developer documentation

Create `grafana-plugins/sqlmonitor-codeeditor-app/docs/DEVELOPER-GUIDE.md`:

**Contents**:
1. Architecture Overview
2. Building from Source
3. Adding New Rules
4. Testing
5. Debugging
6. Contributing Guidelines

**Deliverables**:
- ✅ Developer guide
- ✅ Code examples for adding rules
- ✅ Testing instructions

---

**Task 5.4**: Update project README

Update `grafana-plugins/sqlmonitor-codeeditor-app/README.md`:

**Contents**:
- Project overview
- Quick start
- Features list
- Installation
- Configuration
- Links to documentation
- License (Apache 2.0)

**Deliverables**:
- ✅ Professional README
- ✅ Badge links (build status, version, license)

---

## Testing & Quality Assurance (Built into each phase)

### Unit Tests (20+ tests)

**Performance Rules Tests**:
```typescript
// src/components/Analysis/rules/__tests__/PerformanceRules.test.ts
describe('SelectStarRule', () => {
  it('should detect SELECT * usage', async () => {
    const rule = new SelectStarRule();
    const code = 'SELECT * FROM Customers';
    const results = await rule.detect(code);
    expect(results).toHaveLength(1);
    expect(results[0].ruleId).toBe('P001');
  });

  it('should provide fix suggestion', () => {
    const rule = new SelectStarRule();
    const match = { /* ... */ };
    const suggestion = rule.suggest(match);
    expect(suggestion?.after).toContain('SELECT');
  });
});
```

**Target**: 80%+ code coverage

---

## Deployment Plan

### Phase 1: Development Environment
```bash
cd grafana-plugins/sqlmonitor-codeeditor-app
npm run build
docker compose up
```

### Phase 2: Production Deployment
```bash
# Build optimized bundle
npm run build

# Copy to Grafana plugins directory
cp -r dist/ /var/lib/grafana/plugins/sqlmonitor-codeeditor-app/

# Restart Grafana
docker compose restart grafana
```

### Phase 3: Enable in Grafana
1. Navigate to Configuration > Plugins
2. Search for "SQL Monitor Code Editor"
3. Click "Enable"
4. Navigate to SQL Monitor Code Editor from sidebar

---

## Success Metrics

**Functionality** (All ✅):
- Code editor with T-SQL syntax highlighting
- Real-time code analysis with 30+ rules
- Query execution with results grid
- Auto-fix suggestions
- Index recommendations
- Performance insights (percentiles, variance)
- Wait time categorization

**Performance** (All ✅):
- Analysis completes in <2 seconds for 1000-line files
- Query execution timeout enforced
- UI remains responsive

**Quality** (All ✅):
- 80%+ unit test coverage
- Zero TypeScript errors
- No console errors
- Works in Chrome, Firefox, Edge

---

## Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Monaco Editor integration issues | High | Use Grafana's built-in CodeEditor component |
| Analysis engine performance | Medium | Debounce analysis, use web workers |
| Query timeout issues | Medium | Hard 60-second limit, user configurable |
| API authentication | High | Leverage Grafana's existing auth |
| Browser compatibility | Low | Test in Chrome, Firefox, Edge |

---

## Post-Implementation

### Phase 4 Enhancements (Future)
1. Implement 210+ deferred rules (305 hours)
2. Advanced query rewriting (AST parsing)
3. Collaboration features (share code snippets)
4. Version control integration
5. AI-powered suggestions (LLM integration)

---

**Document Version**: 1.0
**Last Updated**: 2025-11-02
**Status**: Ready for Implementation
**Estimated Completion**: 2025-12-06 (5 weeks, 55 hours)
