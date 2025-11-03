# Phase 3 Feature #7 - T-SQL Code Editor Plugin Architecture

**Purpose**: Technical architecture document for the Grafana app plugin that provides T-SQL code editing, analysis, and query execution.

**Date**: 2025-11-02
**Status**: Design Complete - Ready for Implementation

---

## Overview

This document defines the architecture for a Grafana app plugin that provides:
- T-SQL code editor with syntax highlighting
- Real-time code analysis (~30 rules)
- Query execution with results grid
- Index recommendations based on our monitoring data
- Integration with existing SQL Monitor dashboards

**Plugin Type**: App Plugin (allows custom pages within Grafana)
**Technology Stack**: TypeScript + React + Grafana UI Components
**Development Tool**: `@grafana/create-plugin` CLI

---

## Plugin Structure

```
grafana-plugins/
└── sqlmonitor-codeeditor-app/
    ├── src/
    │   ├── components/
    │   │   ├── App/
    │   │   │   ├── App.tsx                    # Main app container with routing
    │   │   │   └── App.test.tsx
    │   │   ├── CodeEditor/
    │   │   │   ├── CodeEditorPage.tsx         # Main code editor page
    │   │   │   ├── EditorPanel.tsx            # Monaco Editor wrapper
    │   │   │   ├── AnalysisPanel.tsx          # Analysis results sidebar
    │   │   │   ├── ResultsPanel.tsx           # Query results grid
    │   │   │   └── ToolbarActions.tsx         # Execute, Analyze, Save buttons
    │   │   ├── Analysis/
    │   │   │   ├── AnalysisEngine.ts          # Core analysis engine
    │   │   │   ├── RuleBase.ts                # Base class for rules
    │   │   │   ├── rules/
    │   │   │   │   ├── PerformanceRules.ts    # P001-P010 (10 rules)
    │   │   │   │   ├── DeprecatedRules.ts     # DP001-DP008 (8 rules)
    │   │   │   │   ├── SecurityRules.ts       # S001-S005 (5 rules)
    │   │   │   │   ├── CodeSmellRules.ts      # C001-C008 (8 rules)
    │   │   │   │   ├── DesignRules.ts         # D001-D005 (5 rules)
    │   │   │   │   └── NamingRules.ts         # N001-N005 (5 rules)
    │   │   │   └── FixSuggestions.ts          # Auto-fix suggestion engine
    │   │   ├── QueryExecution/
    │   │   │   ├── QueryExecutor.ts           # API calls to execute queries
    │   │   │   ├── ResultsGrid.tsx            # ag-Grid results display
    │   │   │   └── ExecutionPlanViewer.tsx    # Execution plan visualization
    │   │   ├── IndexAdvisor/
    │   │   │   ├── IndexRecommendations.tsx   # Index recommendations panel
    │   │   │   └── IndexAdvisorService.ts     # Query monitoring data for recommendations
    │   │   └── Config/
    │   │       ├── ConfigPage.tsx             # Plugin configuration page
    │   │       └── RuleSettings.tsx           # Enable/disable rules
    │   ├── services/
    │   │   ├── apiClient.ts                   # HTTP client for SQL Monitor API
    │   │   └── codeAnalysisService.ts         # Wrapper for analysis engine
    │   ├── types/
    │   │   ├── analysis.ts                    # AnalysisResult, FixSuggestion types
    │   │   ├── query.ts                       # QueryResult, ExecutionPlan types
    │   │   └── config.ts                      # Plugin configuration types
    │   ├── utils/
    │   │   ├── sqlParser.ts                   # Lightweight SQL parsing utilities
    │   │   └── formatters.ts                  # Result formatting utilities
    │   ├── module.ts                          # Plugin entry point
    │   └── plugin.json                        # Plugin metadata
    ├── package.json
    ├── tsconfig.json
    ├── webpack.config.ts
    ├── docker-compose.yaml                    # Development environment
    └── README.md
```

---

## Component Architecture

### 1. CodeEditorPage (Main Component)

**Responsibility**: Layout and state management for the code editor page

```typescript
// src/components/CodeEditor/CodeEditorPage.tsx
import React, { useState } from 'react';
import { EditorPanel } from './EditorPanel';
import { AnalysisPanel } from './AnalysisPanel';
import { ResultsPanel } from './ResultsPanel';
import { ToolbarActions } from './ToolbarActions';
import { AnalysisResult } from '../../types/analysis';
import { QueryResult } from '../../types/query';

export const CodeEditorPage: React.FC = () => {
  const [code, setCode] = useState<string>('');
  const [analysisResults, setAnalysisResults] = useState<AnalysisResult[]>([]);
  const [queryResults, setQueryResults] = useState<QueryResult | null>(null);
  const [isExecuting, setIsExecuting] = useState(false);
  const [isAnalyzing, setIsAnalyzing] = useState(false);

  const handleAnalyze = async () => {
    setIsAnalyzing(true);
    const results = await analyzeCode(code);
    setAnalysisResults(results);
    setIsAnalyzing(false);
  };

  const handleExecute = async () => {
    setIsExecuting(true);
    const results = await executeQuery(code);
    setQueryResults(results);
    setIsExecuting(false);
  };

  return (
    <div className="code-editor-layout">
      <ToolbarActions
        onAnalyze={handleAnalyze}
        onExecute={handleExecute}
        isAnalyzing={isAnalyzing}
        isExecuting={isExecuting}
      />
      <div className="editor-container">
        <EditorPanel
          value={code}
          onChange={setCode}
          analysisResults={analysisResults}
        />
        <AnalysisPanel results={analysisResults} />
      </div>
      {queryResults && <ResultsPanel results={queryResults} />}
    </div>
  );
};
```

### 2. EditorPanel (Monaco Editor Wrapper)

**Responsibility**: Wrap Grafana's CodeEditor component with analysis integration

```typescript
// src/components/CodeEditor/EditorPanel.tsx
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
  // Convert analysis results to Monaco markers (error squiggles)
  const getMonacoMarkers = () => {
    return analysisResults.map(result => ({
      severity: result.severity === 'Error' ? 8 : 4, // MarkerSeverity.Error : Warning
      startLineNumber: result.line,
      startColumn: result.column,
      endLineNumber: result.line,
      endColumn: result.column + (result.before?.length || 10),
      message: `${result.ruleId}: ${result.message}`
    }));
  };

  const handleEditorDidMount = (editor: any, monaco: any) => {
    // Set markers for analysis results
    const model = editor.getModel();
    if (model) {
      monaco.editor.setModelMarkers(model, 'tsql-analysis', getMonacoMarkers());
    }

    // Add quick fix action (Ctrl+. to show suggestions)
    editor.addAction({
      id: 'show-quick-fixes',
      label: 'Show Quick Fixes',
      keybindings: [monaco.KeyMod.CtrlCmd | monaco.KeyCode.Period],
      contextMenuGroupId: 'navigation',
      run: (ed: any) => {
        // Show quick fix menu
        ed.trigger('keyboard', 'editor.action.quickFix', null);
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
      onBlur={onChange}
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

### 3. AnalysisEngine (Core Analysis Logic)

**Responsibility**: Run all analysis rules and aggregate results

```typescript
// src/components/Analysis/AnalysisEngine.ts
import { AnalysisRule } from './RuleBase';
import { AnalysisResult } from '../../types/analysis';
import { performanceRules } from './rules/PerformanceRules';
import { deprecatedRules } from './rules/DeprecatedRules';
import { securityRules } from './rules/SecurityRules';
import { codeSmellRules } from './rules/CodeSmellRules';
import { designRules } from './rules/DesignRules';
import { namingRules } from './rules/NamingRules';

export class AnalysisEngine {
  private rules: AnalysisRule[] = [];

  constructor() {
    // Load all rules
    this.rules = [
      ...performanceRules,
      ...deprecatedRules,
      ...securityRules,
      ...codeSmellRules,
      ...designRules,
      ...namingRules
    ];
  }

  public async analyze(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];

    for (const rule of this.rules) {
      try {
        const ruleResults = await rule.detect(code);
        results.push(...ruleResults);
      } catch (error) {
        console.error(`Rule ${rule.ruleId} failed:`, error);
      }
    }

    // Sort by severity (Error > Warning > Info), then by line number
    return results.sort((a, b) => {
      const severityOrder = { Error: 0, Warning: 1, Info: 2 };
      if (severityOrder[a.severity] !== severityOrder[b.severity]) {
        return severityOrder[a.severity] - severityOrder[b.severity];
      }
      return a.line - b.line;
    });
  }

  public getRuleById(ruleId: string): AnalysisRule | undefined {
    return this.rules.find(r => r.ruleId === ruleId);
  }
}
```

### 4. RuleBase (Abstract Base Class)

**Responsibility**: Define contract for all analysis rules

```typescript
// src/components/Analysis/RuleBase.ts
import { AnalysisResult, FixSuggestion } from '../../types/analysis';

export interface AnalysisRule {
  ruleId: string;                         // P001, DP001, S001, etc.
  severity: 'Error' | 'Warning' | 'Info';
  category: 'Performance' | 'Deprecated' | 'Security' | 'CodeSmell' | 'Design' | 'Naming';
  message: string;
  enabled: boolean;

  // Detection logic
  detect(code: string): Promise<AnalysisResult[]>;

  // Fix suggestion (optional)
  suggest?(match: AnalysisResult): FixSuggestion | null;
}

// Example implementation
export class SelectStarRule implements AnalysisRule {
  ruleId = 'P001';
  severity = 'Warning' as const;
  category = 'Performance' as const;
  message = 'SELECT * used - specify explicit columns for maintainability';
  enabled = true;

  async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    const regex = /SELECT\s+\*/gi;
    let match;

    while ((match = regex.exec(code)) !== null) {
      const line = this.getLineNumber(code, match.index);
      const column = this.getColumnNumber(code, match.index);

      results.push({
        ruleId: this.ruleId,
        severity: this.severity,
        category: this.category,
        message: this.message,
        line,
        column,
        before: match[0],
        after: null,
        explanation: null
      });
    }

    return results;
  }

  suggest(match: AnalysisResult): FixSuggestion | null {
    return {
      ruleId: this.ruleId,
      description: 'Replace SELECT * with explicit column list',
      before: match.before || 'SELECT *',
      after: 'SELECT [Col1], [Col2], [Col3]',
      explanation: 'Explicit column list improves maintainability, reduces network traffic, and prevents breaking changes when table schema changes',
      estimatedImpact: 'Medium',
      autoFixAvailable: false  // Requires schema knowledge
    };
  }

  private getLineNumber(code: string, index: number): number {
    return code.substring(0, index).split('\n').length;
  }

  private getColumnNumber(code: string, index: number): number {
    const lastNewline = code.lastIndexOf('\n', index);
    return index - lastNewline;
  }
}
```

---

## Type Definitions

### Analysis Types

```typescript
// src/types/analysis.ts

export type Severity = 'Error' | 'Warning' | 'Info';

export type Category =
  | 'Performance'
  | 'Deprecated'
  | 'Security'
  | 'CodeSmell'
  | 'Design'
  | 'Naming';

export interface AnalysisResult {
  ruleId: string;              // P001, DP001, S001, etc.
  severity: Severity;
  category: Category;
  message: string;
  line: number;
  column: number;
  before: string | null;       // Original code snippet
  after: string | null;        // Suggested fix (if available)
  explanation: string | null;  // Why this is an issue
}

export interface FixSuggestion {
  ruleId: string;
  description: string;         // Short description of fix
  before: string;              // Original code
  after: string;               // Fixed code
  explanation: string;         // Detailed explanation of why this is better
  estimatedImpact: 'Low' | 'Medium' | 'High' | 'Very High';
  autoFixAvailable: boolean;   // Can this be auto-applied?
}

export interface RuleConfiguration {
  ruleId: string;
  enabled: boolean;
  severity?: Severity;  // Allow user to override severity
}
```

### Query Types

```typescript
// src/types/query.ts

export interface QueryRequest {
  serverId: number;
  databaseName: string;
  query: string;
  timeout?: number;       // seconds
  includeExecutionPlan?: boolean;
}

export interface QueryResult {
  success: boolean;
  executionTime: number;  // milliseconds
  rowCount: number;
  columns: ColumnInfo[];
  rows: any[];
  messages: string[];
  executionPlan?: ExecutionPlan;
  error?: string;
}

export interface ColumnInfo {
  name: string;
  type: string;           // SQL Server type (int, varchar, etc.)
  nullable: boolean;
}

export interface ExecutionPlan {
  xml: string;
  estimatedCost: number;
  warnings: string[];
}
```

---

## API Integration

### SQL Monitor API Client

```typescript
// src/services/apiClient.ts
import { getBackendSrv } from '@grafana/runtime';
import { QueryRequest, QueryResult } from '../types/query';
import { IndexRecommendation } from '../types/indexAdvisor';

export class SqlMonitorApiClient {
  private baseUrl: string;

  constructor(baseUrl: string = '/api/datasources/proxy/1') {
    this.baseUrl = baseUrl;
  }

  /**
   * Execute T-SQL query against specified server
   */
  async executeQuery(request: QueryRequest): Promise<QueryResult> {
    try {
      const response = await getBackendSrv().post(
        `${this.baseUrl}/api/query/execute`,
        request
      );
      return response;
    } catch (error) {
      console.error('Query execution failed:', error);
      throw error;
    }
  }

  /**
   * Get index recommendations based on monitoring data
   */
  async getIndexRecommendations(
    serverId: number,
    databaseName?: string
  ): Promise<IndexRecommendation[]> {
    try {
      const response = await getBackendSrv().get(
        `${this.baseUrl}/api/index/recommendations`,
        { serverId, databaseName }
      );
      return response;
    } catch (error) {
      console.error('Failed to get index recommendations:', error);
      throw error;
    }
  }

  /**
   * Get procedure performance statistics
   */
  async getProcedureStats(
    serverId: number,
    databaseName: string,
    procedureName: string
  ): Promise<any> {
    try {
      const response = await getBackendSrv().get(
        `${this.baseUrl}/api/procedure/stats`,
        { serverId, databaseName, procedureName }
      );
      return response;
    } catch (error) {
      console.error('Failed to get procedure stats:', error);
      throw error;
    }
  }
}
```

---

## Plugin Configuration

### plugin.json

```json
{
  "$schema": "https://raw.githubusercontent.com/grafana/grafana/master/docs/sources/developers/plugins/plugin.schema.json",
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
    "logos": {
      "small": "img/logo.svg",
      "large": "img/logo.svg"
    },
    "links": [
      {
        "name": "Documentation",
        "url": "https://github.com/sql-monitor/docs"
      }
    ],
    "screenshots": [],
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

---

## Development Workflow

### Initial Setup

```bash
# Navigate to Grafana plugins directory
cd /mnt/d/Dev2/sql-monitor/grafana-plugins

# Create plugin using official scaffolding tool
npx @grafana/create-plugin@latest

# Select:
# - Plugin type: app
# - Plugin name: sqlmonitor-codeeditor-app
# - Organization: sqlmonitor

# Navigate to plugin directory
cd sqlmonitor-codeeditor-app

# Install dependencies
npm install

# Install additional dependencies
npm install --save @monaco-editor/react ag-grid-react ag-grid-community
npm install --save-dev @types/node

# Start development environment
npm run dev

# In another terminal, start Grafana with plugin
docker compose up
```

### Development Loop

1. **Edit Code**: Modify TypeScript/React components in `src/`
2. **Auto-Compile**: Webpack watches for changes and rebuilds
3. **Refresh Browser**: Reload Grafana at `http://localhost:3000`
4. **Test**: Verify functionality in Grafana UI
5. **Iterate**: Repeat until feature complete

### Build for Production

```bash
# Build optimized production bundle
npm run build

# Sign plugin (for distribution)
npm run sign

# Package plugin
npm run package
```

---

## Integration with Existing Dashboards

### Drill-Down Links from Dashboards

Add links to Code Editor from existing dashboards:

```json
{
  "fieldConfig": {
    "overrides": [
      {
        "matcher": { "id": "byName", "options": "ProcedureName" },
        "properties": [
          {
            "id": "links",
            "value": [
              {
                "title": "Open in Code Editor",
                "url": "/a/sqlmonitor-codeeditor-app/editor?server=${ServerID}&database=${DatabaseName}&object=${__data.fields.ProcedureName}&action=load"
              }
            ]
          }
        ]
      }
    ]
  }
}
```

### Deep Linking Support

Code Editor page supports URL parameters:

- `?server=1` - Select server
- `?database=MyDB` - Select database
- `?object=usp_GetOrders` - Load stored procedure code
- `?action=load` - Auto-load object on page load
- `?action=analyze` - Auto-analyze code on load

**Example URL**:
```
http://localhost:3000/a/sqlmonitor-codeeditor-app/editor?server=1&database=SalesDB&object=usp_GetTopCustomers&action=analyze
```

---

## SolarWinds DPA Features Integration

### 1. Response Time Percentiles Display

When viewing procedure performance, show percentile breakdown:

```typescript
// src/components/IndexAdvisor/ProcedurePerformance.tsx
interface ProcedureStats {
  procedureName: string;
  avgDurationMs: number;
  p50DurationMs: number;  // Median
  p95DurationMs: number;  // 95th percentile
  p99DurationMs: number;  // 99th percentile
  executionCount: number;
}

const PerformanceCard: React.FC<{ stats: ProcedureStats }> = ({ stats }) => {
  const variance = (stats.p95DurationMs / stats.p50DurationMs).toFixed(2);

  return (
    <div className="performance-card">
      <h4>{stats.procedureName}</h4>
      <div className="metrics">
        <div>Median (P50): {stats.p50DurationMs}ms</div>
        <div>95th Percentile: {stats.p95DurationMs}ms</div>
        <div>99th Percentile: {stats.p99DurationMs}ms</div>
        <div>
          Variance: {variance}x
          {variance > 5 && <span className="warning"> ⚠️ High variance - investigate parameter sniffing</span>}
        </div>
      </div>
    </div>
  );
};
```

### 2. Query Rewrite Suggestions

Implement pattern-based query rewriting as analysis rules:

```typescript
// src/components/Analysis/rules/QueryRewriteRules.ts
export class NonSargableFunctionRule implements AnalysisRule {
  ruleId = 'P004';
  severity = 'Warning' as const;
  category = 'Performance' as const;
  message = 'Function applied to column in WHERE clause prevents index usage';
  enabled = true;

  async detect(code: string): Promise<AnalysisResult[]> {
    // Detect: WHERE YEAR(OrderDate) = 2024
    const pattern = /WHERE\s+(\w+)\s*\(\s*(\w+)\s*\)\s*=\s*(\S+)/gi;
    // Implementation...
  }

  suggest(match: AnalysisResult): FixSuggestion {
    return {
      ruleId: this.ruleId,
      description: 'Rewrite to use SARGable predicate',
      before: 'WHERE YEAR(OrderDate) = 2024',
      after: 'WHERE OrderDate >= \'2024-01-01\' AND OrderDate < \'2025-01-01\'',
      explanation: 'Allows index on OrderDate to be used, improving query performance by 10x-100x',
      estimatedImpact: 'Very High',
      autoFixAvailable: false  // Requires date range calculation
    };
  }
}
```

### 3. Wait Time Categorization

Display wait statistics with categorization:

```typescript
// src/components/QueryExecution/WaitAnalysis.tsx
const categorizeWaitType = (waitType: string): string => {
  if (waitType.startsWith('PAGEIOLATCH') || waitType.startsWith('WRITELOG')) {
    return 'I/O Contention';
  }
  if (waitType.startsWith('LCK_')) {
    return 'Blocking/Locking';
  }
  if (waitType.includes('RESOURCE_SEMAPHORE')) {
    return 'Memory Pressure';
  }
  // ... additional categorizations
  return 'Other';
};
```

---

## Performance Considerations

### 1. Analysis Engine Optimization

- **Debounce Analysis**: Don't run analysis on every keystroke
- **Web Worker**: Run analysis in background thread to avoid UI blocking
- **Incremental Analysis**: Only re-analyze changed portions of code

```typescript
import { debounce } from 'lodash';

const debouncedAnalyze = debounce(async (code: string) => {
  const results = await analyzeCode(code);
  setAnalysisResults(results);
}, 500);  // Wait 500ms after user stops typing
```

### 2. Query Results Pagination

- Don't load all rows at once
- Use ag-Grid's virtual scrolling
- Lazy load additional pages

### 3. Monaco Editor Performance

- Disable minimap for small code snippets
- Limit syntax highlighting to visible viewport
- Use web workers for large files

---

## Security Considerations

### 1. Query Execution

- **Authentication**: Require valid Grafana session
- **Authorization**: Check user permissions before executing queries
- **SQL Injection Prevention**: Use parameterized queries in API
- **Timeout Enforcement**: Hard limit on query execution time (60 seconds)
- **Resource Limits**: Limit result set size (10,000 rows max)

### 2. Code Storage

- **No Persistent Storage**: Code is session-only (not saved to database)
- **Optional Save**: Allow users to save to browser localStorage (encrypted)
- **Audit Logging**: Log all query executions to AuditLog table

---

## Testing Strategy

### Unit Tests

```typescript
// src/components/Analysis/__tests__/SelectStarRule.test.ts
import { SelectStarRule } from '../rules/PerformanceRules';

describe('SelectStarRule', () => {
  it('should detect SELECT * usage', async () => {
    const rule = new SelectStarRule();
    const code = 'SELECT * FROM Customers';

    const results = await rule.detect(code);

    expect(results).toHaveLength(1);
    expect(results[0].ruleId).toBe('P001');
    expect(results[0].severity).toBe('Warning');
  });

  it('should provide fix suggestion', () => {
    const rule = new SelectStarRule();
    const match = {
      ruleId: 'P001',
      severity: 'Warning',
      message: 'SELECT * used',
      line: 1,
      column: 8,
      before: 'SELECT *'
    };

    const suggestion = rule.suggest(match);

    expect(suggestion).not.toBeNull();
    expect(suggestion?.after).toContain('SELECT [Col1]');
  });
});
```

### Integration Tests

```typescript
// src/services/__tests__/apiClient.test.ts
import { SqlMonitorApiClient } from '../apiClient';

describe('SqlMonitorApiClient', () => {
  it('should execute query successfully', async () => {
    const client = new SqlMonitorApiClient();
    const request = {
      serverId: 1,
      databaseName: 'TestDB',
      query: 'SELECT 1 AS Test'
    };

    const result = await client.executeQuery(request);

    expect(result.success).toBe(true);
    expect(result.rowCount).toBe(1);
    expect(result.columns).toHaveLength(1);
  });
});
```

---

## Deployment

### Plugin Installation

1. **Copy Plugin**: Copy built plugin to Grafana plugins directory
   ```bash
   cp -r dist/ /var/lib/grafana/plugins/sqlmonitor-codeeditor-app/
   ```

2. **Restart Grafana**:
   ```bash
   docker compose restart grafana
   ```

3. **Enable Plugin**: Navigate to Configuration > Plugins > SQL Monitor Code Editor > Enable

### Docker Compose Integration

```yaml
# docker-compose.yml
services:
  grafana:
    image: grafana/grafana-oss:10.2.0
    ports:
      - "9001:3000"
    volumes:
      - grafana-data:/var/lib/grafana
      - ./dashboards/grafana/provisioning:/etc/grafana/provisioning
      - ./grafana-plugins/sqlmonitor-codeeditor-app/dist:/var/lib/grafana/plugins/sqlmonitor-codeeditor-app
    environment:
      - GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=sqlmonitor-codeeditor-app
```

---

## Implementation Phases

### Phase 1: Core Editor (Week 1, 10 hours)
- [ ] Scaffold plugin with @grafana/create-plugin
- [ ] Create CodeEditorPage with layout
- [ ] Integrate Monaco Editor (CodeEditor component)
- [ ] Add toolbar actions (Execute, Analyze, Save)
- [ ] Test basic editing functionality

### Phase 2: Code Analysis (Week 2, 20 hours)
- [ ] Implement AnalysisEngine
- [ ] Create RuleBase abstract class
- [ ] Implement 30 analysis rules:
  - [ ] 10 Performance rules (P001-P010)
  - [ ] 8 Deprecated rules (DP001-DP008)
  - [ ] 5 Security rules (S001-S005)
  - [ ] 8 Code Smell rules (C001-C008)
  - [ ] 5 Design rules (D001-D005)
  - [ ] 5 Naming rules (N001-N005)
- [ ] Create AnalysisPanel to display results
- [ ] Add Monaco markers for error squiggles

### Phase 3: Query Execution (Week 3, 10 hours)
- [ ] Implement QueryExecutor service
- [ ] Create API endpoint in ASP.NET Core API
- [ ] Implement ResultsPanel with ag-Grid
- [ ] Add execution plan viewer
- [ ] Add error handling and timeout

### Phase 4: SolarWinds Features (Week 3-4, 10 hours)
- [ ] Add response time percentiles display
- [ ] Implement 5-10 query rewrite suggestion rules
- [ ] Add wait time categorization
- [ ] Create performance insights panel

### Phase 5: Polish & Documentation (Week 4, 5 hours)
- [ ] Write user documentation
- [ ] Create demo video/screenshots
- [ ] Write developer documentation
- [ ] Add unit tests (80% coverage)
- [ ] Code review and refactoring

**Total Estimated Time**: 55 hours (expanded from original 40 hours to include SolarWinds features)

---

## Success Criteria

1. **Functionality**:
   - ✅ Code editor with T-SQL syntax highlighting
   - ✅ Real-time code analysis with 30+ rules
   - ✅ Query execution with results grid
   - ✅ Auto-fix suggestions for common issues
   - ✅ Index recommendations based on monitoring data

2. **Performance**:
   - ✅ Analysis completes in <2 seconds for 1000-line files
   - ✅ Query execution timeout enforced (60 seconds)
   - ✅ UI remains responsive during analysis

3. **Usability**:
   - ✅ Intuitive UI matching Grafana design patterns
   - ✅ Clear error messages and suggestions
   - ✅ Drill-down links from dashboards work
   - ✅ Configuration page for enabling/disabling rules

4. **Quality**:
   - ✅ 80%+ unit test coverage
   - ✅ No TypeScript compilation errors
   - ✅ No console errors in browser
   - ✅ Works in Chrome, Firefox, Edge

---

## Future Enhancements (Phase 4+)

1. **Advanced Features** (210+ rules from SQLenlight)
2. **Collaboration** (Share code snippets with team)
3. **Version Control** (Save code versions, compare diffs)
4. **Execution History** (Track query performance over time)
5. **AI-Powered Suggestions** (Use LLM for advanced query optimization)
6. **Multi-Query Execution** (Execute multiple queries in batch)
7. **Dark Mode Support** (Respect Grafana theme)
8. **Keyboard Shortcuts** (Vim/Emacs modes)

---

**Document Version**: 1.0
**Last Updated**: 2025-11-02
**Status**: Design Complete - Ready for Implementation
