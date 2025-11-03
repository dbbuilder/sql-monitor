# SQL Monitor Code Editor - Grafana App Plugin

T-SQL code editor with real-time analysis, query execution, and index recommendations.

## Features

- ✅ **Monaco Editor Integration** - VSCode-quality SQL editing experience
- ✅ **Real-Time Code Analysis** - 30+ analysis rules across 6 categories
- ✅ **Auto-Save** - Never lose your work (saves to browser localStorage every 2 seconds)
- ✅ **Keyboard Shortcuts** - 20+ shortcuts for power users (Ctrl+S, Ctrl+Enter, F5, etc.)
- ✅ **IntelliSense** - Schema-aware auto-completion for tables and columns
- ✅ **Query Execution** - Execute queries against monitored SQL Servers
- ✅ **Results Grid** - Sortable, filterable results with ag-Grid
- ✅ **Export Results** - CSV, JSON, Excel export options
- ✅ **Execution History** - Review last 50 queries
- ✅ **Script Management** - Save, load, and organize your SQL scripts
- ✅ **Code Formatting** - Auto-format T-SQL code
- ✅ **Performance Insights** - Response time percentiles (P50, P95, P99)
- ✅ **Query Rewrites** - Automated optimization suggestions
- ✅ **Dark Mode** - Respects Grafana theme preference

## Installation

### Development

```bash
# Install dependencies
npm install

# Start development server
npm run dev

# In another terminal, start Grafana
npm run server
```

Access Grafana at http://localhost:3000 and navigate to the SQL Monitor Code Editor plugin.

### Production

```bash
# Build production bundle
npm run build

# Copy to Grafana plugins directory
cp -r dist/ /var/lib/grafana/plugins/sqlmonitor-codeeditor-app/

# Restart Grafana
docker compose restart grafana
```

## Architecture

### Components

- **CodeEditorPage** - Main editor page with toolbar, editor, and results
- **EditorPanel** - Monaco Editor wrapper with T-SQL syntax highlighting
- **AnalysisPanel** - Display analysis results with severity badges
- **ResultsPanel** - ag-Grid results display with export options
- **ToolbarActions** - Server/database selection and action buttons

### Services

- **AutoSaveService** - Auto-save to localStorage every 2 seconds
- **ExecutionHistoryService** - Track query execution history
- **SqlMonitorApiClient** - API client for SQL Monitor backend
- **AnalysisEngine** - Code analysis engine with 30+ rules

### Analysis Rules

**Performance (P001-P010)**:
- SELECT * usage
- Missing WHERE clauses
- CURSOR usage
- Non-SARGable functions
- And more...

**Security (S001-S005)**:
- SQL injection patterns
- xp_cmdshell usage
- Plaintext passwords
- Dynamic SQL vulnerabilities

**Deprecated Features (DP001-DP008)**:
- TEXT/NTEXT/IMAGE types
- Old syntax patterns
- Legacy functions

**Code Smells (C001-C008)**:
- Missing error handling
- Long procedures
- Excessive nesting

**Design Issues (D001-D005)**:
- Missing primary keys
- Heap tables
- Wide tables

**Naming Conventions (N001-N005)**:
- sp_ prefix detection
- Inconsistent naming
- Reserved keywords

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| **Ctrl+S** | Save script |
| **Ctrl+Enter** or **F5** | Execute query |
| **Ctrl+Shift+A** | Analyze code |
| **Ctrl+F** | Find |
| **Ctrl+H** | Find & Replace |
| **Ctrl+Shift+F** | Format code |
| **Ctrl+/** | Toggle comment |
| **Ctrl+L** | Clear editor |

## Auto-Save

The editor automatically saves your work to browser localStorage every 2 seconds after you stop typing. On page reload, your last session is restored automatically.

**Manual Save**: Press Ctrl+S to manually save your script with a custom name.

## Script Management

Navigate to "Saved Scripts" to view all your saved scripts. You can:
- Load scripts into the editor
- Delete old scripts
- Search/filter by name or database
- Export/import scripts

## Query Execution

1. Select a server from the dropdown
2. Select a database
3. Write or paste your T-SQL query
4. Press Ctrl+Enter or F5 to execute
5. View results in the grid below
6. Export results to CSV, JSON, or Excel

## Code Analysis

Click "Analyze" or press Ctrl+Shift+A to run code analysis. The Analysis Panel shows:
- Error count (red badge)
- Warning count (orange badge)
- Info count (blue badge)

Click any issue to jump to that line in the editor.

## Performance Insights

When viewing procedure performance, the editor shows:
- Median (P50) duration
- 95th percentile (P95) duration
- 99th percentile (P99) duration
- Performance variance warnings (P95/P50 > 5x indicates parameter sniffing)

## Development

### Adding New Analysis Rules

```typescript
// src/components/Analysis/rules/MyRules.ts
import { BaseRule } from '../RuleBase';

export class MyCustomRule extends BaseRule {
  ruleId = 'C009';
  severity = 'Warning' as const;
  category = 'CodeSmell' as const;
  message = 'Custom rule description';

  async detect(code: string): Promise<AnalysisResult[]> {
    const results: AnalysisResult[] = [];
    // Your detection logic here
    return results;
  }

  suggest(match: AnalysisResult): FixSuggestion {
    return {
      ruleId: this.ruleId,
      description: 'How to fix',
      before: '// Bad code',
      after: '// Good code',
      explanation: 'Why this is better',
      estimatedImpact: 'High',
      autoFixAvailable: false
    };
  }
}
```

### Testing

```bash
# Run tests in watch mode
npm test

# Run tests once (CI)
npm run test:ci

# Type checking
npm run typecheck

# Linting
npm run lint
npm run lint:fix
```

## License

Apache 2.0

## Support

- Documentation: https://github.com/sql-monitor/docs
- Issues: https://github.com/sql-monitor/issues
- License: https://github.com/sql-monitor/LICENSE
