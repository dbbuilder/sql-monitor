# SQL Monitor Code Editor - Feature Overview

**Version**: 1.0
**Last Updated**: 2025-11-02
**Status**: Production Ready

---

## Introduction

The SQL Monitor Code Editor is a web-based T-SQL development environment integrated into Grafana. It provides a modern, feature-rich alternative to SSMS for writing, executing, and analyzing SQL Server queries across all your monitored servers.

### Key Differentiators

vs. **SSMS (SQL Server Management Studio)**:
- ✅ Web-based - no installation required
- ✅ Integrated with SQL Server monitoring data
- ✅ Real-time code analysis and suggestions
- ✅ Cross-platform (works on Mac, Linux, Chromebook)
- ❌ Not a full SSMS replacement (missing advanced features)

vs. **Azure Data Studio**:
- ✅ Lighter weight and faster
- ✅ Integrated monitoring context
- ✅ No installation required
- ❌ Fewer extensions and customizations

vs. **SQL Prompt / SQLenlight**:
- ✅ Free and open source
- ✅ Integrated with monitoring system
- ✅ 41 analysis rules out of the box
- ❌ Simpler analysis (pattern-based vs. full AST parsing)

---

## Table of Contents

1. [Core Features](#core-features)
2. [Code Editing](#code-editing)
3. [Query Execution](#query-execution)
4. [Code Analysis](#code-analysis)
5. [IntelliSense & Auto-Completion](#intellisense--auto-completion)
6. [Navigation & Discovery](#navigation--discovery)
7. [Script Management](#script-management)
8. [Configuration & Customization](#configuration--customization)
9. [Keyboard Shortcuts](#keyboard-shortcuts)
10. [Use Cases](#use-cases)

---

## Core Features

### 1. Multi-Server Query Execution

**What**: Execute queries against any monitored SQL Server from a single interface.

**How it Works**:
1. Select server from dropdown (top toolbar)
2. Select database from dropdown
3. Write query
4. Click "Run Query" or press Ctrl+Enter
5. Results appear in bottom panel

**Benefits**:
- No need to switch between multiple SSMS windows
- Consistent interface across all servers
- Integrated with monitoring data (see server health inline)

**Supported Servers**:
- SQL Server 2012+
- Azure SQL Database
- SQL Server on Linux
- All servers in your SQL Monitor inventory

---

### 2. Monaco Editor Integration

**What**: Industry-standard code editor (same engine as VSCode).

**Features**:
- Syntax highlighting for T-SQL
- Line numbers and minimap
- Code folding (collapse/expand blocks)
- Multi-cursor editing
- Find and replace
- Bracket matching
- Auto-indentation
- Code formatting

**Why Monaco?**:
- Battle-tested by millions of developers
- Regular updates and bug fixes
- Extensible architecture
- Excellent performance

---

### 3. Real-Time Code Analysis

**What**: Analyze your SQL code as you type for performance issues, security risks, and best practices violations.

**41 Analysis Rules** across 6 categories:
- Performance (10 rules)
- Deprecated Features (8 rules)
- Security (5 rules)
- Code Smells (8 rules)
- Design Issues (5 rules)
- Naming Conventions (5 rules)

**Analysis Panel**:
- Color-coded severity (Error, Warning, Info)
- Click to jump to issue
- Detailed explanation and suggestions
- Quick fixes (planned for future release)

**Example Rules**:
- P001: Avoid SELECT * (specify explicit columns)
- P002: Missing WHERE clause in UPDATE/DELETE
- S001: SQL injection risk (dynamic SQL with user input)
- D001: SELECT DISTINCT may hide design flaw
- N001: Non-standard naming (Hungarian notation)

---

### 4. IntelliSense & Schema Awareness

**What**: Context-aware auto-completion for tables, columns, procedures, and functions.

**Features**:
- Autocomplete table names after FROM/JOIN
- Autocomplete column names after table prefix (e.g., `Customers.`)
- Autocomplete stored procedure names after EXEC
- Hover tooltips with object definitions
- Go to definition (F12) for any object

**Performance**:
- Schema metadata cached for 24 hours
- Sub-second autocomplete response
- Background refresh (non-blocking)

---

### 5. Query Results Grid

**What**: Professional data grid for displaying query results.

**Features**:
- **Multiple result sets** - tabbed interface for queries returning multiple sets
- **Sorting** - click column headers to sort
- **Filtering** - built-in column filters
- **Pagination** - configurable rows per page (10-1000)
- **Export** - CSV, JSON, or Excel format
- **Copy to clipboard** - tab-delimited for pasting into Excel
- **Messages tab** - View PRINT statements and row counts

**Performance**:
- Virtual scrolling for large result sets
- Client-side sorting/filtering (no server round-trip)
- Lazy loading for 10,000+ row datasets

---

### 6. Object Browser

**What**: Hierarchical tree view of database objects.

**Features**:
- Servers → Databases → Objects hierarchy
- Object types: Tables, Views, Procedures, Functions
- Double-click to view definition
- Context menu for common actions
- Search/filter objects (planned)

**Use Cases**:
- Explore unfamiliar databases
- Find object names for IntelliSense
- View table schemas
- Copy object names to editor

---

### 7. Tab Management

**What**: Work on multiple scripts simultaneously with VSCode-style tabs.

**Features**:
- Multiple tabs open at once
- Tab reordering (drag and drop)
- Close tab (Ctrl+W)
- Close all tabs
- Duplicate tab
- Reopen closed tab (Ctrl+Shift+T)
- Tab context menu (rename, duplicate, close others)

**Tab Types**:
- New script (blank)
- Saved script (from localStorage)
- Object definition (read-only view of table/procedure)

**Auto-Save**:
- Each tab auto-saves every 5 seconds (configurable)
- Recover work after browser crash
- No manual save needed (but Ctrl+S available)

---

## Code Editing

### Syntax Highlighting

T-SQL keywords, operators, functions, and comments are color-coded for readability.

**Color Scheme**:
- Keywords (SELECT, FROM, WHERE): Blue
- Strings: Red
- Numbers: Green
- Comments: Gray/Green
- Functions: Purple
- Operators: White/Black

**Dark Mode Support**: Automatically matches your Grafana theme.

---

### Code Formatting

**What**: Automatically format messy SQL into clean, readable code.

**Shortcut**: `Shift+Alt+F`

**Before**:
```sql
select top 10 customerid,customername,email,ordercount from customers where ordercount>10 order by ordercount desc
```

**After**:
```sql
SELECT TOP 10
    CustomerID,
    CustomerName,
    Email,
    OrderCount
FROM Customers
WHERE OrderCount > 10
ORDER BY OrderCount DESC;
```

**Formatting Rules**:
- Keywords uppercase
- Proper indentation (4 spaces)
- Line breaks after major clauses
- Column lists on separate lines

---

### Multi-Cursor Editing

**What**: Edit multiple locations simultaneously.

**Use Cases**:
- Rename variables across multiple lines
- Add/remove prefixes to multiple columns
- Delete multiple similar lines at once

**How to Use**:
1. `Ctrl+D` - Select next occurrence of word under cursor
2. `Ctrl+Alt+Up/Down` - Add cursor above/below current line
3. `Shift+Alt+I` - Add cursor at end of each selected line

**Example**:
```sql
-- Select "Customer" and press Ctrl+D three times
SELECT CustomerID, CustomerName, CustomerEmail FROM Customers

-- All three "Customer" words selected, type "Order":
SELECT OrderID, OrderName, OrderEmail FROM Orders
```

---

### Code Folding

**What**: Collapse/expand code blocks for easier navigation.

**Shortcuts**:
- `Ctrl+Shift+[` - Fold current block
- `Ctrl+Shift+]` - Unfold current block
- `Ctrl+K Ctrl+0` - Fold all
- `Ctrl+K Ctrl+J` - Unfold all

**Foldable Blocks**:
- Stored procedures (CREATE PROCEDURE...END)
- Functions (CREATE FUNCTION...END)
- BEGIN...END blocks
- CTE (WITH) definitions
- Multi-line comments

---

### Find & Replace

**What**: Search and replace text within your script.

**Features**:
- Case-sensitive search
- Whole word matching
- Regular expression support
- Replace single occurrence
- Replace all occurrences
- Find in selection only

**Shortcuts**:
- `Ctrl+F` - Find
- `Ctrl+H` - Find and replace
- `F3` - Find next
- `Shift+F3` - Find previous

---

## Query Execution

### Execute Query

**What**: Run T-SQL queries against your selected server/database.

**Shortcuts**:
- `Ctrl+Enter` or `F5` - Run entire query
- `Ctrl+E` - Run selected text only

**Execution Process**:
1. Query sent to backend API
2. API connects to selected SQL Server
3. Query executed with configured timeout (default 60s)
4. Results streamed back to browser
5. Results displayed in grid

**Timeout Handling**:
- Queries timeout after configured seconds (5-300s)
- Timeout error displayed with suggestion to increase limit
- Can cancel running query with Esc key

---

### Execution History

**What**: Keep track of your last 10 query executions.

**Information Stored**:
- Query text (first 100 characters)
- Execution time
- Rows affected / returned
- Server and database
- Success/failure status

**Use Cases**:
- Re-run previous query
- Compare execution times
- Debug query variations

**Future Enhancement**: Full execution history with filtering and export.

---

### Query Results Display

**Multiple Result Sets**:
- Queries returning multiple result sets show tabbed interface
- Each result set in its own tab
- Switch between tabs to view different result sets

**Messages Tab**:
- PRINT statements
- Row count messages ("5 rows affected")
- Informational messages

**Footer Information**:
- Execution time (milliseconds)
- Rows affected
- Total rows returned
- Server and database name
- Execution timestamp

---

## Code Analysis

### Analysis Engine

**What**: Pattern-based static analysis of T-SQL code.

**How it Works**:
1. You type SQL code
2. Analysis engine scans code (debounced 2 seconds after typing)
3. 41 rules check for issues
4. Warnings displayed in Analysis Panel
5. Click warning to jump to line in editor

**Rule Categories**:

#### 1. Performance Rules (10 rules)
- P001: SELECT * instead of explicit columns
- P002: Missing WHERE clause in UPDATE/DELETE
- P003: Non-SARGable WHERE clause (functions on columns)
- P004: Missing ORDER BY in SELECT TOP
- P005: DISTINCT without clear reason
- P006: Using NOLOCK hint (dirty reads)
- P007: Implicit conversion in WHERE clause
- P008: Multiple COUNT(*) in single query
- P009: Missing index hints for known scenarios
- P010: Inefficient LIKE pattern ('%value%')

#### 2. Deprecated Features (8 rules)
- D001: Old-style JOIN syntax (FROM A, B WHERE A.ID = B.ID)
- D002: Using sp_* prefix for user stored procedures
- D003: TEXT/NTEXT/IMAGE data types
- D004: Using @@ROWCOUNT after SELECT
- D005: FASTFIRSTROW hint
- D006: SET ROWCOUNT
- D007: Using system tables instead of catalog views
- D008: Old-style RAISERROR

#### 3. Security Issues (5 rules)
- S001: SQL injection risk (dynamic SQL with concatenation)
- S002: EXECUTE AS without REVERT
- S003: xp_cmdshell usage
- S004: Plaintext passwords in code
- S005: WITH GRANT OPTION usage

#### 4. Code Smells (8 rules)
- C001: Long stored procedure (>500 lines)
- C002: Deep nesting (>5 levels)
- C003: Too many parameters (>10)
- C004: Magic numbers (hardcoded values)
- C005: Commented-out code
- C006: Unused variables
- C007: Copy-paste code (duplicate logic)
- C008: Poor error handling

#### 5. Design Issues (5 rules)
- DS001: SELECT DISTINCT may hide data quality issue
- DS002: Cursors used where set-based logic possible
- DS003: Nested subqueries (>3 levels)
- DS004: Cross-database query (portability issue)
- DS005: SELECT INTO in stored procedure

#### 6. Naming Conventions (5 rules)
- N001: Table names not singular (e.g., `Customer` not `Customers`)
- N002: Hungarian notation in column names (e.g., `strFirstName`)
- N003: Stored procedure without `usp_` prefix
- N004: Reserved keywords used as identifiers
- N005: Inconsistent casing

---

### Configuring Analysis Rules

**Enable/Disable Individual Rules**:
1. Go to Configuration page
2. Scroll to "Code Analysis Settings"
3. Find the rule (e.g., P001)
4. Toggle ON/OFF
5. Click "Save"

**Enable/Disable Entire Categories**:
1. Go to Configuration page
2. Find category (e.g., "Performance")
3. Click "Disable All" or "Enable All"
4. Click "Save"

**Common Configurations**:
- **Development**: Disable P001 (SELECT *), P002 (missing WHERE)
- **Production**: Enable all rules
- **Learning**: Enable all rules for suggestions

---

## IntelliSense & Auto-Completion

### Autocomplete Triggers

**After FROM / JOIN**:
- Suggests tables and views
- Shows schema prefix (e.g., `dbo.Customers`)

**After table prefix**:
- Type `Customers.` and autocomplete suggests columns
- Shows column data type and nullability

**After EXEC**:
- Suggests stored procedures
- Shows procedure parameters

**Keywords**:
- SQL keywords (SELECT, FROM, WHERE, etc.)
- Functions (GETDATE, CAST, CONVERT, etc.)

---

### Hover Tooltips

**What**: Move mouse over object name to see definition.

**Information Shown**:
- Object type (table, view, procedure, function)
- Schema and database
- Column list (for tables/views)
- Parameters (for procedures/functions)
- Description (if available)

---

### Go to Definition

**What**: Jump to the definition of any database object.

**Shortcut**: `F12` or right-click → "Go to Definition"

**How it Works**:
1. Place cursor on object name (e.g., `Customers`)
2. Press F12
3. New tab opens with object's CREATE script
4. View structure, modify, or copy code

**Peek Definition** (Alt+F12):
- View definition in popup overlay
- No new tab opened
- Quick reference without context switch

---

## Navigation & Discovery

### Quick Open

**What**: Fuzzy search for database objects and saved scripts.

**Shortcut**: `Ctrl+P`

**Features**:
- Fuzzy matching (type "custord" to find "CustomerOrders")
- Type filters:
  - `@table` - Show only tables
  - `@view` - Show only views
  - `@sp` or `@procedure` - Show only stored procedures
  - `@fn` or `@function` - Show only functions
- Recent files shown first
- Keyboard navigation (up/down arrows, Enter to select)

**Examples**:
- `Ctrl+P` → Type "customer" → See all objects with "customer" in name
- `Ctrl+P` → Type "@table cust" → See only tables with "cust" in name

---

### Object Browser

**What**: Sidebar panel with hierarchical view of database objects.

**Toggle**: `Ctrl+B` or click button in toolbar

**Tree Structure**:
```
SQL-PROD-01
├─ SalesDB
│  ├─ Tables
│  │  ├─ dbo.Customers
│  │  ├─ dbo.Orders
│  │  └─ ...
│  ├─ Views
│  ├─ Procedures
│  └─ Functions
├─ InventoryDB
└─ ...
```

**Actions**:
- Double-click object → View definition
- Right-click → Context menu
  - Script as SELECT
  - Script as INSERT
  - Script as CREATE
  - Copy name
  - Refresh

---

## Script Management

### Auto-Save

**What**: Automatically save your work as you type.

**How it Works**:
1. You type code
2. After 5 seconds of inactivity, code is auto-saved to browser localStorage
3. If browser crashes, your work is recovered on next visit

**Configuration**:
- Enable/disable auto-save
- Adjust delay (1-30 seconds)
- Settings in Configuration page

**Storage Limit**: Browser localStorage (typically 5-10MB)

---

### Saved Scripts

**What**: Permanently save scripts for future use.

**How to Save**:
1. Write query
2. Press Ctrl+S or click "Save" button
3. Enter script name
4. Script saved to localStorage

**Features**:
- Search saved scripts
- Sort by name, date, server
- Export to JSON file
- Import from JSON file
- Delete scripts
- Rename scripts

**Saved Scripts Page**:
- Click "Saved Scripts" in navigation bar
- View all saved scripts
- Manage scripts (rename, delete, export)
- Import scripts from team members

---

### Export Scripts

**Single Script**:
1. Open script in editor
2. Go to Saved Scripts page
3. Click "Export" button next to script
4. JSON file downloaded

**All Scripts**:
1. Go to Saved Scripts page
2. Click "Export All" button
3. JSON file with all scripts downloaded

**JSON Format**:
```json
{
  "name": "Get Top Customers",
  "content": "SELECT TOP 10 * FROM Customers...",
  "serverId": 1,
  "databaseName": "SalesDB",
  "exportedAt": "2025-11-02T10:30:00.000Z"
}
```

---

### Import Scripts

**Single Script**:
1. Go to Saved Scripts page
2. Click "Import" button
3. Select JSON file
4. Script imported and available

**Batch Import**:
- Import JSON file with array of scripts
- All scripts imported at once

**Use Cases**:
- Share scripts with team members
- Backup scripts before major changes
- Transfer scripts between browsers/computers

---

## Configuration & Customization

See [Configuration Guide](USER-CONFIGURATION-GUIDE.md) for complete details.

### Configurable Settings

**Editor**:
- Font size (10-24px)
- Tab size (2-8 spaces)
- Line numbers (on/off)
- Minimap (on/off)
- Word wrap (on/off)

**Auto-Save**:
- Enabled (on/off)
- Delay (1-30 seconds)

**Query Execution**:
- Timeout (5-300 seconds)
- Max rows per page (10-1000)

**Code Analysis**:
- Auto-run (on/off)
- 41 individual rules (on/off)
- Category-level enable/disable

**UI**:
- Show Object Browser by default
- Show Analysis Panel by default

---

## Keyboard Shortcuts

See [Keyboard Shortcuts Reference](KEYBOARD-SHORTCUTS-REFERENCE.md) for complete list.

### Most Common Shortcuts

| Action | Shortcut |
|--------|----------|
| Run Query | Ctrl+Enter or F5 |
| Save Script | Ctrl+S |
| Quick Open | Ctrl+P |
| Find | Ctrl+F |
| Format Code | Shift+Alt+F |
| Toggle Object Browser | Ctrl+B |
| Next Tab | Ctrl+Tab |
| Close Tab | Ctrl+W |

---

## Use Cases

### Use Case 1: Quick Query on Production Server

**Scenario**: Need to check customer order count quickly.

**Steps**:
1. Open Code Editor
2. Select "SQL-PROD-01" server
3. Select "SalesDB" database
4. Type query: `SELECT CustomerID, COUNT(*) FROM Orders GROUP BY CustomerID`
5. Press Ctrl+Enter
6. View results in grid
7. Export to CSV if needed

**Time**: < 30 seconds

---

### Use Case 2: Analyze Slow Query

**Scenario**: Query running slow, need to find issues.

**Steps**:
1. Paste slow query into editor
2. Click "Analyze" button (or wait for auto-analysis)
3. Review warnings in Analysis Panel
4. Click warning to jump to issue
5. Apply suggested fix (e.g., add WHERE clause, remove SELECT *)
6. Re-run query
7. Compare execution times

**Time**: 2-5 minutes

---

### Use Case 3: Explore Unfamiliar Database

**Scenario**: New database, need to understand schema.

**Steps**:
1. Toggle Object Browser (Ctrl+B)
2. Select server and database
3. Expand "Tables" node
4. Double-click table name to view structure
5. Note column names and types
6. Use Quick Open (Ctrl+P) to search for specific objects
7. Write query using IntelliSense

**Time**: 5-10 minutes

---

### Use Case 4: Share Query with Team

**Scenario**: Wrote useful query, want to share with team.

**Steps**:
1. Write and test query
2. Save script (Ctrl+S)
3. Go to Saved Scripts page
4. Click "Export" button next to script
5. Send JSON file to team via email/Slack
6. Team members import JSON file

**Time**: 1 minute

---

### Use Case 5: Debugging Stored Procedure

**Scenario**: Stored procedure has bug, need to test modifications.

**Steps**:
1. Use Quick Open (Ctrl+P) to find procedure
2. Press F12 to view definition
3. Copy code to new tab
4. Modify code (add PRINT statements, change logic)
5. Run modified code to test
6. Once working, apply changes to actual procedure in SSMS

**Time**: 10-20 minutes

---

## Future Enhancements

**Planned for Future Releases**:
- Execution plan visualization
- Query performance comparison (before/after)
- Git integration for version control
- Team collaboration features (comments, sharing)
- Automated refactoring suggestions
- Advanced IntelliSense (JOIN suggestions, query templates)
- Custom snippets
- Theme customization
- More export formats (Excel with formatting, PDF)
- Query history with full search
- Scheduled query execution
- Query result caching

---

## Support & Feedback

**Documentation**:
- [Configuration Guide](USER-CONFIGURATION-GUIDE.md)
- [Keyboard Shortcuts Reference](KEYBOARD-SHORTCUTS-REFERENCE.md)
- [Troubleshooting Guide](TROUBLESHOOTING.md)

**Help**:
- Press F1 in Code Editor for shortcuts reference
- Check console (F12) for error messages
- Contact your system administrator

**Feedback**:
- Report bugs: GitHub Issues
- Request features: GitHub Discussions
- Contribute: Pull requests welcome!

---

**Version**: 1.0
**Last Updated**: 2025-11-02
**Prepared By**: SQL Monitor Development Team
