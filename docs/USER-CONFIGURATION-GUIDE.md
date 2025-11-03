# SQL Monitor Code Editor - Configuration Guide

**Version**: 1.0
**Last Updated**: 2025-11-02
**Audience**: End Users

---

## Table of Contents

1. [Introduction](#introduction)
2. [Accessing Configuration](#accessing-configuration)
3. [Editor Settings](#editor-settings)
4. [Auto-Save Settings](#auto-save-settings)
5. [Query Execution Settings](#query-execution-settings)
6. [Code Analysis Settings](#code-analysis-settings)
7. [UI Preferences](#ui-preferences)
8. [Import/Export Settings](#importexport-settings)
9. [Troubleshooting](#troubleshooting)

---

## Introduction

The SQL Monitor Code Editor provides extensive configuration options to customize your coding experience. All settings are saved automatically to your browser and persist across sessions.

### Key Features

- **Real-time updates**: Changes apply immediately without page reload
- **Personal preferences**: Settings are unique to your browser/profile
- **Import/Export**: Share configurations with team members
- **Smart defaults**: Sensible defaults work for most users

---

## Accessing Configuration

### Method 1: Navigation Bar

1. Click the **Configuration** tab in the navigation bar at the top of the page
2. The Configuration page will open with all available settings

### Method 2: Direct URL

Navigate directly to: `http://your-grafana-url/plugins/sqlmonitor-codeeditor-app/config`

---

## Editor Settings

### Font Size

**Description**: Controls the size of text in the code editor.

**Range**: 10 - 24 pixels
**Default**: 14 pixels
**Recommended**:
- Small screens (laptops): 12-14px
- Large screens (desktop): 14-16px
- Presentations: 18-24px

**How to Change**:
1. Go to Configuration page
2. Find "Editor Settings" section
3. Adjust the "Font Size" slider
4. Click "Save"
5. Return to Code Editor to see changes

**Example Use Cases**:
- **Pair Programming**: Increase to 18-20px for better visibility
- **Personal Comfort**: Adjust based on your eyesight and screen distance
- **Screen Sharing**: Increase to 20-24px when presenting

---

### Tab Size

**Description**: Number of spaces inserted when you press the Tab key.

**Range**: 2 - 8 spaces
**Default**: 4 spaces
**Common Values**:
- 2 spaces: Compact code style (JavaScript convention)
- 4 spaces: SQL standard (recommended)
- 8 spaces: Legacy code style

**How to Change**:
1. Go to Configuration page
2. Find "Tab Size" input field
3. Enter your preferred value (2-8)
4. Click "Save"

**Impact**: Affects code indentation and readability.

---

### Show Line Numbers

**Description**: Display line numbers on the left side of the editor.

**Default**: ON
**Recommended**: Keep ON for easier debugging and collaboration

**When to Disable**:
- Writing short, simple queries
- Maximizing screen space for code
- Personal preference

**How to Toggle**:
1. Go to Configuration page
2. Find "Show Line Numbers" toggle
3. Click to enable/disable
4. Click "Save"

---

### Show Minimap

**Description**: Display a minimap (code overview) on the right side of the editor.

**Default**: ON
**Recommended**: ON for large scripts, OFF for small queries

**Benefits of Minimap**:
- Quickly navigate to different sections
- Visual overview of code structure
- See cursor position in context

**When to Disable**:
- Small queries (< 100 lines)
- Limited screen space
- Prefer clean, minimal interface

**How to Toggle**:
1. Go to Configuration page
2. Find "Show Minimap" toggle
3. Click to enable/disable
4. Click "Save"

---

### Word Wrap

**Description**: Wrap long lines of code to fit within the editor width.

**Default**: OFF
**Recommended**: OFF for SQL (horizontal scrolling is common)

**When to Enable**:
- Working on small screens
- Writing very long SQL comments
- Prefer not to scroll horizontally

**When to Disable**:
- Large monitors with plenty of horizontal space
- Prefer to see full line length
- Working with formatted SQL with long column lists

**How to Toggle**:
1. Go to Configuration page
2. Find "Word Wrap" toggle
3. Click to enable/disable
4. Click "Save"

---

## Auto-Save Settings

### Enable Auto-Save

**Description**: Automatically save your code to browser storage as you type.

**Default**: ON
**Recommended**: Keep ON to prevent data loss

**Benefits**:
- Never lose your work due to browser crashes
- Seamless workflow without manual saves
- Automatic script recovery on page reload

**When to Disable**:
- Privacy concerns (code stored in browser)
- Using shared/public computers
- Prefer explicit save actions

**How to Toggle**:
1. Go to Configuration page
2. Find "Auto-Save" section
3. Toggle "Enable Auto-Save"
4. Click "Save"

**Note**: Disabling auto-save requires manual saves (Ctrl+S) to persist changes.

---

### Auto-Save Delay

**Description**: Time delay (in milliseconds) after you stop typing before auto-save triggers.

**Range**: 1,000 - 30,000 milliseconds (1 - 30 seconds)
**Default**: 5,000 milliseconds (5 seconds)
**Recommended**:
- Fast typists: 3,000ms (3 seconds)
- Average: 5,000ms (5 seconds)
- Slow typists or thinking time: 10,000ms (10 seconds)

**How It Works**:
- You type code
- You stop typing
- After X seconds, code is automatically saved
- If you resume typing, the timer resets

**Performance Considerations**:
- Shorter delays = more frequent saves (slight overhead)
- Longer delays = less frequent saves (risk of losing recent work)

**How to Change**:
1. Go to Configuration page
2. Find "Auto-Save Delay" slider
3. Adjust to your preferred delay
4. Click "Save"

**Example**:
- Set to 2 seconds: Code saves 2 seconds after you stop typing
- Set to 10 seconds: Code saves 10 seconds after you stop typing

---

## Query Execution Settings

### Query Timeout

**Description**: Maximum time (in seconds) a query can run before being automatically cancelled.

**Range**: 5 - 300 seconds (5 seconds - 5 minutes)
**Default**: 60 seconds (1 minute)
**Recommended**:
- Development/Testing: 30-60 seconds
- Production queries: 60-120 seconds
- Long-running reports: 120-300 seconds

**Why This Matters**:
- Prevents runaway queries from consuming resources
- Protects against accidentally executing expensive queries
- Ensures responsive UI (queries don't hang forever)

**How to Change**:
1. Go to Configuration page
2. Find "Query Timeout" field
3. Enter your preferred timeout in seconds
4. Click "Save"

**Example Scenarios**:
- **Quick SELECT queries**: 30 seconds is plenty
- **Complex JOINs**: 60-90 seconds recommended
- **Data warehouse queries**: 120-300 seconds may be needed

**Note**: If a query times out, you'll see an error message with the option to increase the timeout and try again.

---

### Max Rows Per Page

**Description**: Number of rows displayed per page in the query results grid.

**Range**: 10 - 1,000 rows
**Default**: 50 rows
**Recommended**:
- Small datasets: 25-50 rows
- Large datasets: 100-500 rows
- Performance testing: 10-25 rows

**Impact on Performance**:
- Lower values = faster initial rendering
- Higher values = less pagination, more scrolling

**How to Change**:
1. Go to Configuration page
2. Find "Max Rows Per Page" field
3. Enter your preferred page size
4. Click "Save"

**Note**: This only affects the results grid display. All rows are still fetched from the database.

---

## Code Analysis Settings

### Auto-Run Analysis

**Description**: Automatically run code analysis as you type (with debounce).

**Default**: ON
**Recommended**: ON for real-time feedback

**Benefits**:
- Catch errors before running queries
- Learn best practices in real-time
- Improve code quality automatically

**When to Disable**:
- Working on large scripts (performance)
- Don't want real-time warnings
- Prefer to run analysis manually

**How to Toggle**:
1. Go to Configuration page
2. Find "Code Analysis Settings"
3. Toggle "Auto-Run Analysis"
4. Click "Save"

---

### Analysis Rules Configuration

**Description**: Enable or disable specific analysis rules to customize warnings.

**Total Rules**: 41 rules across 6 categories
**Categories**:
1. **Performance** (10 rules) - Query optimization tips
2. **Deprecated Features** (8 rules) - Outdated SQL features
3. **Security** (5 rules) - SQL injection and security risks
4. **Code Smells** (8 rules) - Poor coding practices
5. **Design** (5 rules) - Schema design issues
6. **Naming** (5 rules) - Naming convention suggestions

#### How to Disable Individual Rules

1. Go to Configuration page
2. Scroll to "Code Analysis Settings"
3. Expand the category containing the rule
4. Find the specific rule (e.g., "P001: Avoid SELECT *")
5. Toggle the rule OFF
6. Click "Save"

**Example**: If you frequently use `SELECT *` in development queries and don't want warnings, disable rule **P001**.

#### How to Disable All Rules in a Category

1. Go to Configuration page
2. Scroll to "Code Analysis Settings"
3. Find the category (e.g., "Performance")
4. Click "Disable All" button for that category
5. Click "Save"

**Example**: Disable all "Naming Convention" rules if your team doesn't follow standard naming conventions.

#### How to Enable All Rules in a Category

1. Go to Configuration page
2. Scroll to "Code Analysis Settings"
3. Find the category
4. Click "Enable All" button for that category
5. Click "Save"

---

### Common Rule Customizations

#### Scenario 1: Development Environment

**Goal**: Reduce noisy warnings for development/testing queries.

**Recommended Configuration**:
- Disable P001 (SELECT *) - common in dev queries
- Disable P002 (Missing WHERE clause) - testing often requires full table scans
- Enable all Security rules - still important in dev
- Disable Naming Convention rules - less important in dev

#### Scenario 2: Production Queries Only

**Goal**: Maximum strictness for production code.

**Recommended Configuration**:
- Enable all Performance rules
- Enable all Security rules
- Enable all Code Smell rules
- Enable all Design rules
- Disable or customize Naming rules based on team standards

#### Scenario 3: Learning SQL

**Goal**: Get helpful tips while learning.

**Recommended Configuration**:
- Enable all rules (default)
- Pay attention to suggestions
- Gradually disable rules as you master them

---

## UI Preferences

### Show Object Browser by Default

**Description**: Display the Object Browser sidebar when opening the Code Editor.

**Default**: ON
**Recommended**: ON for most users

**Benefits of Object Browser**:
- Quick access to tables, views, procedures
- Double-click to view object definitions
- Context menu for common actions
- Navigate server/database hierarchy

**When to Disable**:
- Prefer maximized code editor space
- Rarely browse database objects
- Know object names by heart

**How to Toggle**:
1. Go to Configuration page
2. Find "UI Preferences"
3. Toggle "Show Object Browser by Default"
4. Click "Save"

**Note**: You can always toggle the Object Browser on/off using the button in the Code Editor toolbar.

---

### Show Analysis Panel by Default

**Description**: Display the Analysis Panel (code warnings) when opening the Code Editor.

**Default**: ON
**Recommended**: ON if using code analysis

**When to Disable**:
- Don't use code analysis features
- Prefer clean, minimal interface
- Limited screen space

**How to Toggle**:
1. Go to Configuration page
2. Find "UI Preferences"
3. Toggle "Show Analysis Panel by Default"
4. Click "Save"

---

## Import/Export Settings

### Export Settings

**Purpose**: Save your configuration to a file for backup or sharing with team members.

**How to Export**:
1. Go to Configuration page
2. Click "Export Settings" button
3. A JSON file will be downloaded with name `sqlmonitor-settings-{timestamp}.json`
4. Save this file in a safe location

**Use Cases**:
- **Backup**: Save your settings before making changes
- **Team Sharing**: Share standard configuration with colleagues
- **Multiple Browsers**: Transfer settings between browsers/computers
- **Testing**: Export before testing new configurations

**File Format**: JSON
```json
{
  "settings": {
    "editorFontSize": 16,
    "editorTabSize": 4,
    "autoSaveEnabled": true,
    "autoSaveDelayMs": 5000,
    "disabledRules": ["P001", "P002"],
    ...
  },
  "exportedAt": "2025-11-02T10:30:00.000Z",
  "version": "1.0"
}
```

---

### Import Settings

**Purpose**: Load configuration from a previously exported file.

**How to Import**:
1. Go to Configuration page
2. Click "Import Settings" button
3. Select a JSON settings file (exported earlier)
4. Settings will be imported and applied immediately
5. Confirmation message will appear

**Important Notes**:
- Importing overwrites ALL current settings
- No undo available (export current settings first as backup)
- Invalid files will show an error message
- Settings apply immediately (no save button needed)

**Workflow for Safe Import**:
1. Export current settings (backup)
2. Import new settings
3. Review changes in Code Editor
4. If not satisfied, import backup file to restore

---

## Troubleshooting

### Settings Not Saving

**Symptoms**: Changes to settings don't persist after page reload.

**Possible Causes**:
- Browser's localStorage is disabled
- Private/Incognito browsing mode
- Browser storage quota exceeded

**Solutions**:
1. Check if you're in Private/Incognito mode (settings won't persist)
2. Clear browser cache and reload
3. Check browser console for errors (F12)
4. Try a different browser
5. Contact your administrator if issue persists

---

### Settings Not Updating in Code Editor

**Symptoms**: Change settings, but Code Editor doesn't reflect changes.

**Possible Causes**:
- Cache issue
- Multiple browser tabs open

**Solutions**:
1. Click "Save" button after making changes
2. Refresh the Code Editor page (F5)
3. Close all tabs and reopen the plugin
4. Check browser console for errors

---

### Auto-Save Not Working

**Symptoms**: Code is not being saved automatically.

**Possible Causes**:
- Auto-Save is disabled in settings
- Browser localStorage is full
- Auto-Save delay is set too high

**Solutions**:
1. Go to Configuration → Auto-Save Settings
2. Verify "Enable Auto-Save" is ON
3. Check Auto-Save Delay (reduce if too high)
4. Clear old saved scripts to free up storage
5. Use manual save (Ctrl+S) as backup

---

### Code Analysis Rules Not Working

**Symptoms**: Analysis warnings not appearing for known issues.

**Possible Causes**:
- Rule is disabled in settings
- Auto-Run Analysis is disabled
- Code doesn't trigger the rule

**Solutions**:
1. Go to Configuration → Code Analysis Settings
2. Check if rule is enabled
3. Check if "Auto-Run Analysis" is ON
4. Try clicking "Analyze" button manually
5. Verify code actually triggers the rule

---

### Import Settings Failed

**Symptoms**: Error message when importing settings file.

**Possible Causes**:
- Invalid JSON format
- File corrupted
- Wrong file selected

**Solutions**:
1. Verify file is a valid JSON file
2. Open file in text editor to check format
3. Re-export settings from working installation
4. Contact person who shared the file

---

## Best Practices

### 1. Export Settings Regularly

Create backups of your configuration weekly or before major changes.

### 2. Use Sensible Defaults

Don't over-customize initially. Start with defaults and adjust as needed.

### 3. Share Team Standards

If your team has coding standards, export a "team configuration" and share it with all members.

### 4. Test Changes in Dev

Before importing new settings in production work, test in a development environment.

### 5. Document Custom Configurations

If you disable specific analysis rules, document why (e.g., "P001 disabled for dev environment").

---

## Support

For additional help:
- **Documentation**: See full feature documentation
- **Keyboard Shortcuts**: Press `F1` in Code Editor for shortcuts reference
- **Issues**: Report bugs at [GitHub Issues](https://github.com/your-repo/issues)
- **Questions**: Contact your system administrator

---

## Appendix: Default Settings

```json
{
  "editorFontSize": 14,
  "editorTabSize": 4,
  "editorLineNumbers": true,
  "editorMinimap": true,
  "editorWordWrap": false,
  "autoSaveEnabled": true,
  "autoSaveDelayMs": 5000,
  "queryTimeoutSeconds": 60,
  "maxRowsPerPage": 50,
  "analysisAutoRun": true,
  "disabledRules": [],
  "showObjectBrowserByDefault": true,
  "showAnalysisPanelByDefault": true
}
```

---

**Version**: 1.0
**Last Updated**: 2025-11-02
**Prepared By**: SQL Monitor Development Team
