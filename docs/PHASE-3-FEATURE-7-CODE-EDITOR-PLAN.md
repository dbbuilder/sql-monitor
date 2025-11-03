# Phase 3 - Feature #7: T-SQL Code Editor & Analyzer

**Date**: 2025-11-02
**Status**: Planning
**Priority**: Medium
**Estimated Effort**: 32 hours budgeted, 10-12 hours estimated actual

---

## IMPORTANT: Independent Implementation Notice

This feature implements **our own T-SQL code analysis system** from scratch. While inspired by concepts from commercial tools like SQLenlight, this is an **independent implementation** with:
- Our own rule engine and detection logic
- Our own pattern matching algorithms
- Our own integration with SQL Server DMVs
- Apache 2.0 open-source license
- No use of proprietary code or algorithms

**Goal**: Provide practical T-SQL code analysis integrated with our monitoring system, not replicate commercial products.

---

## Overview

A web-based T-SQL code editor and analyzer integrated into Grafana that provides:
1. **Monaco Editor Integration**: Industry-standard code editor (VSCode engine)
2. **Real-Time Code Analysis**: Detect common T-SQL issues as you type
3. **Query Execution**: Run queries against monitored servers
4. **Performance Insights**: Integrate with our existing monitoring data
5. **Code Quality Rules**: Our own implementation of T-SQL best practices

### Value Proposition

**vs. SSMS**:
- ✅ Web-based (no installation)
- ✅ Integrated with monitoring (see index usage, execution stats inline)
- ✅ Real-time code analysis feedback
- ❌ Not a full replacement (SSMS still primary tool)

**vs. SQLenlight** (commercial $199-$399):
- ✅ Free and open source
- ✅ Integrated with our monitoring system
- ✅ Real-time feedback in browser
- ❌ Fewer rules (focus on most critical issues)
- ❌ Simpler analysis (pattern-based, not full AST parsing)

**Our Unique Value**:
- Integration with existing DMV data (indexes, stats, query plans)
- Historical context (compare current query with past performance)
- Multi-server query execution from single interface
- Zero cost

---

## Architecture

### Component Stack

```
┌─────────────────────────────────────────────────────────┐
│                  Grafana Dashboard                       │
│  (loads our custom panel plugin)                        │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│           Custom Grafana Panel Plugin                    │
│  - React-based frontend                                  │
│  - Monaco Editor component                               │
│  - Code Analysis Engine (JavaScript)                     │
│  - Query execution handler                               │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│              SQL Monitor API (ASP.NET Core)              │
│  - POST /api/code/execute (run query)                    │
│  - GET /api/code/suggestions (auto-complete)             │
│  - GET /api/code/performance-hints (query analysis)      │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│                 MonitoringDB + Remote Servers            │
│  - Execute queries via linked servers                    │
│  - Return results as JSON                                │
└─────────────────────────────────────────────────────────┘
```

### Data Flow

**1. Code Editing**:
```
User types T-SQL → Monaco Editor → Code Analysis Engine (browser)
                 ↓
            Real-time feedback (warnings/errors inline)
```

**2. Query Execution**:
```
User clicks "Execute" → API POST /api/code/execute
                      ↓
                SQL Server (via Dapper + OPENQUERY)
                      ↓
                Results returned as JSON
                      ↓
                Displayed in grid (ag-Grid or similar)
```

**3. Performance Insights**:
```
User types SELECT * FROM Table → API GET /api/code/performance-hints
                                ↓
                Query IndexFragmentation table
                Query QueryPerformanceMetrics table
                                ↓
                Return inline suggestions (e.g., "Table has 45% fragmentation")
```

---

## Our T-SQL Code Analysis Engine

### Analysis Categories (Our Implementation)

We will implement **7 categories** of analysis rules, prioritizing most impactful issues:

#### 1. Performance Anti-Patterns (Priority: High)

**Our Rules** (pattern-based detection):
- **Rule P001**: `SELECT *` usage (suggest explicit columns)
- **Rule P002**: Missing `WHERE` clause on large tables
- **Rule P003**: `DISTINCT` without `ORDER BY` (often indicates design issue)
- **Rule P004**: Implicit conversions in `WHERE` (e.g., `WHERE VarcharColumn = 123`)
- **Rule P005**: Functions in `WHERE` clause (non-SARGable)
- **Rule P006**: `OR` in `WHERE` clause (suggest `UNION` for better plan)
- **Rule P007**: `CURSOR` usage (suggest set-based alternative)
- **Rule P008**: `WHILE` loop for data manipulation (suggest set-based)
- **Rule P009**: Nested `SELECT` in column list (correlated subquery)
- **Rule P010**: Missing `NOLOCK` or `READ UNCOMMITTED` hint (with warning)

**Implementation Approach**:
- Regex patterns for quick detection
- Integration with DMV data (check if table is "large" using our IndexFragmentation data)

#### 2. Missing Indexes (Priority: High)

**Our Rules** (integrated with our data):
- **Rule I001**: Query references table with high fragmentation
- **Rule I002**: Query filters on column with no supporting index (query sys.indexes)
- **Rule I003**: Join on columns without index
- **Rule I004**: `ORDER BY` on non-indexed columns

**Implementation Approach**:
- Parse `FROM` and `JOIN` clauses to extract table names
- Query our `IndexFragmentation` table for status
- Query DMV `sys.indexes` for index definitions
- Provide inline suggestions: "Table Orders has 45% fragmentation (last checked 2 hours ago)"

#### 3. Deprecated Features (Priority: Medium)

**Our Rules** (SQL Server 2019+ deprecated features):
- **Rule D001**: `TEXT`, `NTEXT`, `IMAGE` data types (suggest `VARCHAR(MAX)`, `NVARCHAR(MAX)`, `VARBINARY(MAX)`)
- **Rule D002**: `FASTFIRSTROW` hint (suggest `OPTION (FAST N)`)
- **Rule D003**: `COMPUTE` clause (deprecated)
- **Rule D004**: `GROUP BY ALL` (deprecated)
- **Rule D005**: `TIMESTAMP` data type (suggest `ROWVERSION`)
- **Rule D006**: `sp_*` system procedures (suggest `sys.*` DMVs)
- **Rule D007**: `::` function call syntax (suggest ANSI syntax)
- **Rule D008**: `SET ROWCOUNT` for DML (suggest `TOP`)

**Implementation Approach**:
- Simple string/regex matching
- Provide replacement suggestions with examples

#### 4. Code Smells (Priority: Medium)

**Our Rules**:
- **Rule C001**: Inconsistent case (MixedCase vs. lowercase vs. UPPERCASE)
- **Rule C002**: Missing `SET NOCOUNT ON` in stored procedure
- **Rule C003**: Missing error handling (`TRY/CATCH`)
- **Rule C004**: Hardcoded connection strings
- **Rule C005**: Dynamic SQL without `sp_executesql` (SQL injection risk)
- **Rule C006**: Missing transaction for multi-statement DML
- **Rule C007**: `RAISERROR` without severity level
- **Rule C008**: Comments in production code (excessive)

**Implementation Approach**:
- Pattern matching with configurable severity (warning vs. error)

#### 5. Design Issues (Priority: Low)

**Our Rules**:
- **Rule E001**: Wide `SELECT *` in `INSERT INTO` (fragile, breaks if columns added)
- **Rule E002**: No primary key on table (check sys.indexes)
- **Rule E003**: No clustered index on table
- **Rule E004**: Heap table (no clustered index)
- **Rule E005**: Missing foreign key constraints (orphaned data risk)

**Implementation Approach**:
- Query DMVs to validate design
- Provide architectural suggestions

#### 6. Security Issues (Priority: Medium)

**Our Rules**:
- **Rule S001**: Dynamic SQL with concatenated user input (SQL injection)
- **Rule S002**: Use of `EXECUTE AS` without reverting
- **Rule S003**: `xp_cmdshell` usage
- **Rule S004**: Plaintext passwords in code
- **Rule S005**: `WITH GRANT OPTION` usage (excessive permissions)

**Implementation Approach**:
- String matching for dangerous patterns
- Warn about security implications

#### 7. Naming Conventions (Priority: Low)

**Our Rules** (configurable):
- **Rule N001**: Table names not singular (e.g., `Customers` → `Customer`)
- **Rule N002**: Column names with Hungarian notation (e.g., `strFirstName`)
- **Rule N003**: Stored procedure without `usp_` prefix
- **Rule N004**: Reserved keywords used as identifiers
- **Rule N005**: Inconsistent casing in object names

**Implementation Approach**:
- Configurable rules (user can enable/disable)
- Suggest naming conventions

---

### Rule Severity Levels

Each rule has a severity:
- **Error** (red): Will cause runtime errors or major performance issues
- **Warning** (orange): Should be fixed, but won't break
- **Info** (blue): Best practice suggestion

---

### Analysis Engine Architecture

**Browser-Side (JavaScript/TypeScript)**:

```javascript
// Code Analysis Engine (runs in browser)
class TSQLAnalyzer {
    private rules: AnalysisRule[] = [];

    constructor() {
        // Register all analysis rules
        this.registerPerformanceRules();
        this.registerDeprecatedFeatureRules();
        this.registerCodeSmellRules();
        // etc.
    }

    analyze(code: string): AnalysisResult[] {
        const results: AnalysisResult[] = [];

        // Run all rules against code
        for (const rule of this.rules) {
            const matches = rule.detect(code);
            results.push(...matches);
        }

        return results;
    }
}

// Example rule implementation
class SelectStarRule implements AnalysisRule {
    ruleId = 'P001';
    severity = 'Warning';
    category = 'Performance';

    detect(code: string): AnalysisResult[] {
        const results: AnalysisResult[] = [];
        const regex = /SELECT\s+\*/gi;
        let match;

        while ((match = regex.exec(code)) !== null) {
            results.push({
                ruleId: this.ruleId,
                severity: this.severity,
                line: getLineNumber(code, match.index),
                column: getColumnNumber(code, match.index),
                message: 'Avoid SELECT *. Specify explicit columns for better performance and maintainability.',
                suggestion: 'SELECT Column1, Column2, Column3 FROM ...'
            });
        }

        return results;
    }
}
```

**Server-Side (ASP.NET Core API)**:

```csharp
// API for enhanced analysis (using our monitoring data)
[HttpPost("api/code/analyze")]
public async Task<ActionResult<CodeAnalysisResult>> AnalyzeCode(
    [FromBody] CodeAnalysisRequest request)
{
    var results = new List<CodeIssue>();

    // Extract table names from query
    var tables = ParseTableNames(request.Code);

    // Check our monitoring data for each table
    foreach (var table in tables)
    {
        // Query IndexFragmentation table
        var fragmentation = await _sqlService.GetTableFragmentation(
            request.ServerId, request.DatabaseName, table);

        if (fragmentation?.FragmentationPercent > 30)
        {
            results.Add(new CodeIssue
            {
                RuleId = "I001",
                Severity = "Warning",
                Message = $"Table '{table}' has {fragmentation.FragmentationPercent}% fragmentation (high). Consider running index maintenance.",
                Line = GetTableReferenceLine(request.Code, table),
                ActionableAdvice = $"EXEC dbo.usp_PerformIndexMaintenance @DatabaseName = '{request.DatabaseName}';"
            });
        }
    }

    return Ok(new CodeAnalysisResult { Issues = results });
}
```

---

## Monaco Editor Integration

### Setup

**Monaco Editor** (Microsoft's open-source editor, same engine as VSCode):
- Apache 2.0 license (free for commercial use)
- Built-in syntax highlighting for T-SQL
- IntelliSense support
- Theme support (dark mode)
- Diff editor (compare queries)

**NPM Package**: `monaco-editor` (latest: 0.44.0+)

**Integration**:
```typescript
import * as monaco from 'monaco-editor';

// Create editor instance
const editor = monaco.editor.create(document.getElementById('editor')!, {
    value: '-- Enter your T-SQL query here\nSELECT * FROM sys.tables;',
    language: 'sql',
    theme: 'vs-dark',
    automaticLayout: true,
    minimap: { enabled: true },
    scrollBeyondLastLine: false
});

// Register our custom T-SQL analyzer
monaco.languages.registerCodeActionProvider('sql', {
    provideCodeActions: (model, range, context, token) => {
        // Run our analysis engine
        const code = model.getValue();
        const issues = analyzer.analyze(code);

        // Convert to Monaco code actions (quick fixes)
        return {
            actions: issues.map(issue => ({
                title: issue.suggestion,
                kind: 'quickfix',
                diagnostics: [issue],
                edit: {
                    edits: [{
                        resource: model.uri,
                        edit: {
                            range: issue.range,
                            text: issue.suggestedCode
                        }
                    }]
                }
            })),
            dispose: () => {}
        };
    }
});
```

---

## Query Execution

### API Endpoint

```csharp
[HttpPost("api/code/execute")]
[RequirePermission("query_execute")]
public async Task<ActionResult<QueryExecutionResult>> ExecuteQuery(
    [FromBody] QueryExecutionRequest request)
{
    // Validate query (no DROP, ALTER, DELETE without confirmation)
    if (IsDestructiveQuery(request.Query) && !request.ConfirmDestructive)
    {
        return BadRequest(new {
            error = "Destructive query detected. Confirm to execute.",
            requiresConfirmation = true
        });
    }

    // Execute query with timeout
    try
    {
        using var connection = _connectionFactory.CreateConnection(request.ServerId);
        using var command = connection.CreateCommand();

        command.CommandText = request.Query;
        command.CommandTimeout = 30; // 30 seconds

        var results = new List<Dictionary<string, object>>();
        var stopwatch = Stopwatch.StartNew();

        using var reader = await command.ExecuteReaderAsync();

        while (await reader.ReadAsync())
        {
            var row = new Dictionary<string, object>();
            for (int i = 0; i < reader.FieldCount; i++)
            {
                row[reader.GetName(i)] = reader.GetValue(i);
            }
            results.Add(row);

            // Limit to 1000 rows
            if (results.Count >= 1000)
                break;
        }

        stopwatch.Stop();

        return Ok(new QueryExecutionResult
        {
            Rows = results,
            RowCount = results.Count,
            ExecutionTimeMs = stopwatch.ElapsedMilliseconds,
            Columns = Enumerable.Range(0, reader.FieldCount)
                .Select(i => new ColumnInfo
                {
                    Name = reader.GetName(i),
                    DataType = reader.GetFieldType(i).Name
                }).ToList()
        });
    }
    catch (SqlException ex)
    {
        return BadRequest(new {
            error = ex.Message,
            errorNumber = ex.Number,
            lineNumber = ex.LineNumber
        });
    }
}
```

### Safety Features

**Query Validation**:
- Detect `DROP`, `TRUNCATE`, `DELETE` without `WHERE`
- Require confirmation for destructive operations
- Timeout after 30 seconds
- Limit results to 1000 rows

**Permission-Based**:
- `query_execute` permission required
- `query_execute_write` for `INSERT/UPDATE/DELETE`
- `query_execute_admin` for `DROP/ALTER`

---

## Grafana Plugin Structure

```
grafana-sqlmonitor-codeeditor/
├── src/
│   ├── components/
│   │   ├── CodeEditor.tsx          # Monaco Editor wrapper
│   │   ├── ResultsGrid.tsx         # Query results display (ag-Grid)
│   │   ├── AnalysisPanel.tsx       # Code issues panel
│   │   ├── ServerSelector.tsx      # Select target server
│   │   └── ExecutionStats.tsx      # Execution time, rows, etc.
│   ├── services/
│   │   ├── AnalysisEngine.ts       # Our T-SQL analysis engine
│   │   ├── ApiClient.ts            # API calls to backend
│   │   └── MonacoConfig.ts         # Monaco editor configuration
│   ├── rules/
│   │   ├── PerformanceRules.ts     # Performance anti-patterns
│   │   ├── DeprecatedRules.ts      # Deprecated features
│   │   ├── CodeSmellRules.ts       # Code smells
│   │   ├── DesignRules.ts          # Design issues
│   │   ├── SecurityRules.ts        # Security issues
│   │   └── NamingRules.ts          # Naming conventions
│   ├── types/
│   │   └── index.d.ts              # TypeScript definitions
│   ├── module.ts                   # Grafana plugin entry point
│   └── plugin.json                 # Plugin manifest
├── package.json
├── tsconfig.json
├── webpack.config.js
└── README.md
```

---

## Implementation Plan

### Phase 1: Monaco Editor Integration (3 hours)

**Tasks**:
1. Create Grafana panel plugin scaffold
2. Add Monaco Editor component
3. Configure T-SQL syntax highlighting
4. Add basic toolbar (Execute, Clear, Save)

**Deliverable**: Working code editor in Grafana

---

### Phase 2: Query Execution (2 hours)

**Tasks**:
1. Create API endpoint `POST /api/code/execute`
2. Implement query execution via Dapper
3. Add results grid component (ag-Grid or Tabulator)
4. Handle errors gracefully

**Deliverable**: Execute queries and display results

---

### Phase 3: Code Analysis Engine (4 hours)

**Tasks**:
1. Implement base `AnalysisEngine` class
2. Create **Performance Rules** (10 rules)
3. Create **Deprecated Feature Rules** (8 rules)
4. Create **Code Smell Rules** (8 rules)
5. Integrate with Monaco diagnostics

**Deliverable**: Real-time code analysis with inline warnings

---

### Phase 4: Integration with Monitoring Data (2 hours)

**Tasks**:
1. Create API endpoint `GET /api/code/performance-hints`
2. Query `IndexFragmentation` table for referenced tables
3. Query `QueryPerformanceMetrics` for similar queries
4. Display inline suggestions

**Deliverable**: Context-aware suggestions based on monitoring data

---

### Phase 5: Polish & Documentation (1 hour)

**Tasks**:
1. Add keyboard shortcuts (Ctrl+Enter = Execute)
2. Add query history (localStorage)
3. Add saved queries feature
4. Write user documentation

**Deliverable**: Production-ready code editor

---

## Success Criteria

1. **Functionality**: Execute queries against all monitored servers
2. **Analysis**: Detect top 20 most critical T-SQL issues (our rules)
3. **Performance**: Analysis feedback < 500ms for typical query
4. **Usability**: Integrated into Grafana, no separate login required
5. **Documentation**: User guide with examples of all rule categories

---

## Estimated Timeline

| Task | Estimated Time |
|------|----------------|
| Monaco Editor integration | 3 hours |
| Query execution | 2 hours |
| Code analysis engine | 4 hours |
| Monitoring integration | 2 hours |
| Polish & documentation | 1 hour |
| **Total** | **12 hours** |

**Buffer**: 2 hours for testing/debugging
**Final Estimate**: 14 hours actual (vs. 32 hours budgeted = 56% efficiency)

---

## Limitations & Future Enhancements

**Current Limitations**:
- Simple pattern matching (not full AST parsing)
- ~30 rules (vs. SQLenlight's 260+)
- No refactoring capabilities
- No CI/CD integration

**Future Enhancements** (Phase 4+):
- Full T-SQL parser using ANTLR
- More advanced rules (control flow analysis)
- Automated refactoring suggestions
- Integration with git for code reviews
- Query plan visualization
- Performance comparison (before/after)

---

**Status**: Ready to implement
**Next Step**: Create Grafana plugin scaffold with Monaco Editor
