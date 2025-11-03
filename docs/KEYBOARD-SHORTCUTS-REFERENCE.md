# SQL Monitor Code Editor - Keyboard Shortcuts Reference

**Version**: 1.0
**Last Updated**: 2025-11-02
**Platform**: Windows, Mac, Linux

---

## Quick Access

Press **F1** in the Code Editor to display this shortcuts reference.

---

## Table of Contents

1. [File Operations](#file-operations)
2. [Editing](#editing)
3. [Navigation](#navigation)
4. [Query Execution](#query-execution)
5. [Code Analysis](#code-analysis)
6. [Search & Replace](#search--replace)
7. [Multi-Cursor Editing](#multi-cursor-editing)
8. [Code Folding](#code-folding)
9. [Editor View](#editor-view)
10. [Tab Management](#tab-management)

---

## Platform Key Notation

| Notation | Windows/Linux | Mac |
|----------|---------------|-----|
| `Ctrl` | Control | Command (⌘) |
| `Alt` | Alt | Option (⌥) |
| `Shift` | Shift | Shift (⇧) |
| `Enter` | Enter | Return (↩) |

---

## File Operations

| Action | Shortcut | Description |
|--------|----------|-------------|
| **New Script** | `Ctrl+N` | Create a new empty script tab |
| **Open Script** | `Ctrl+O` | Open Quick Open dialog to search for saved scripts |
| **Save Script** | `Ctrl+S` | Save current script to browser storage |
| **Save As** | `Ctrl+Shift+S` | Save current script with new name |
| **Close Tab** | `Ctrl+W` | Close current tab |
| **Reopen Closed Tab** | `Ctrl+Shift+T` | Reopen the last closed tab |

---

## Editing

| Action | Shortcut | Description |
|--------|----------|-------------|
| **Undo** | `Ctrl+Z` | Undo last change |
| **Redo** | `Ctrl+Y` or `Ctrl+Shift+Z` | Redo last undone change |
| **Cut Line** | `Ctrl+X` (no selection) | Cut entire line |
| **Copy Line** | `Ctrl+C` (no selection) | Copy entire line |
| **Delete Line** | `Ctrl+Shift+K` | Delete current line |
| **Duplicate Line** | `Ctrl+D` | Duplicate current line below |
| **Move Line Up** | `Alt+Up` | Move current line up |
| **Move Line Down** | `Alt+Down` | Move current line down |
| **Insert Line Above** | `Ctrl+Shift+Enter` | Insert new line above cursor |
| **Insert Line Below** | `Ctrl+Enter` | Insert new line below cursor |
| **Indent** | `Tab` | Indent selected lines or insert tab |
| **Outdent** | `Shift+Tab` | Decrease indent of selected lines |
| **Format Code** | `Shift+Alt+F` | Format entire SQL script |
| **Format Selection** | `Ctrl+K Ctrl+F` | Format selected code only |

---

## Navigation

| Action | Shortcut | Description |
|--------|----------|-------------|
| **Go to Line** | `Ctrl+G` | Jump to specific line number |
| **Go to Beginning of Line** | `Home` | Move cursor to start of line |
| **Go to End of Line** | `End` | Move cursor to end of line |
| **Go to Beginning of File** | `Ctrl+Home` | Jump to first line of script |
| **Go to End of File** | `Ctrl+End` | Jump to last line of script |
| **Go to Definition** | `F12` | Jump to definition of object under cursor |
| **Peek Definition** | `Alt+F12` | View definition in popup |
| **Go to Next Error** | `F8` | Jump to next code analysis warning |
| **Go to Previous Error** | `Shift+F8` | Jump to previous code analysis warning |
| **Navigate Back** | `Alt+Left` | Go back to previous cursor position |
| **Navigate Forward** | `Alt+Right` | Go forward to next cursor position |

---

## Query Execution

| Action | Shortcut | Description |
|--------|----------|-------------|
| **Run Query** | `Ctrl+Enter` or `F5` | Execute current query |
| **Run Selection** | `Ctrl+E` | Execute only selected text |
| **Cancel Execution** | `Esc` (during execution) | Cancel running query |
| **Clear Results** | `Ctrl+Shift+R` | Clear results grid |

---

## Code Analysis

| Action | Shortcut | Description |
|--------|----------|-------------|
| **Analyze Code** | `Ctrl+Shift+A` | Run code analysis manually |
| **Show Analysis Panel** | `Ctrl+Shift+E` | Toggle analysis panel visibility |
| **Next Warning** | `F8` | Jump to next analysis warning |
| **Previous Warning** | `Shift+F8` | Jump to previous analysis warning |

---

## Search & Replace

| Action | Shortcut | Description |
|--------|----------|-------------|
| **Find** | `Ctrl+F` | Open find dialog |
| **Replace** | `Ctrl+H` | Open find and replace dialog |
| **Find Next** | `F3` or `Ctrl+G` | Find next occurrence |
| **Find Previous** | `Shift+F3` or `Ctrl+Shift+G` | Find previous occurrence |
| **Find in Selection** | `Ctrl+F` (with selection) | Limit search to selected text |
| **Find All** | `Alt+Enter` (in find) | Select all occurrences |
| **Add Selection to Next Find Match** | `Ctrl+D` | Multi-cursor: select next match |

---

## Multi-Cursor Editing

| Action | Shortcut | Description |
|--------|----------|-------------|
| **Add Cursor Above** | `Ctrl+Alt+Up` | Add cursor on line above |
| **Add Cursor Below** | `Ctrl+Alt+Down` | Add cursor on line below |
| **Add Cursor to Line Ends** | `Shift+Alt+I` | Add cursor at end of each selected line |
| **Select All Occurrences** | `Ctrl+Shift+L` | Select all occurrences of current word |
| **Undo Last Cursor** | `Ctrl+U` | Remove last added cursor |
| **Column Selection** | `Shift+Alt+Drag` | Select rectangular region |

**Example Use Cases**:
- Rename multiple variables at once
- Add/remove prefixes from multiple lines
- Edit multiple similar lines simultaneously

---

## Code Folding

| Action | Shortcut | Description |
|--------|----------|-------------|
| **Fold** | `Ctrl+Shift+[` | Fold (collapse) current code block |
| **Unfold** | `Ctrl+Shift+]` | Unfold (expand) current code block |
| **Fold All** | `Ctrl+K Ctrl+0` | Fold all code blocks |
| **Unfold All** | `Ctrl+K Ctrl+J` | Unfold all code blocks |
| **Fold Level 1** | `Ctrl+K Ctrl+1` | Fold all level 1 blocks (procedures) |
| **Fold Level 2** | `Ctrl+K Ctrl+2` | Fold all level 2 blocks (BEGIN/END) |

---

## Editor View

| Action | Shortcut | Description |
|--------|----------|-------------|
| **Toggle Object Browser** | `Ctrl+B` | Show/hide Object Browser sidebar |
| **Toggle Analysis Panel** | `Ctrl+Shift+E` | Show/hide Analysis Panel |
| **Toggle Results Panel** | `Ctrl+Shift+P` | Show/hide Query Results |
| **Toggle Minimap** | *Via Configuration* | Show/hide minimap (code overview) |
| **Zoom In** | `Ctrl++` (plus) | Increase font size temporarily |
| **Zoom Out** | `Ctrl+-` (minus) | Decrease font size temporarily |
| **Reset Zoom** | `Ctrl+0` (zero) | Reset font size to configured size |
| **Toggle Full Screen** | `F11` | Enter/exit full screen mode |

---

## Tab Management

| Action | Shortcut | Description |
|--------|----------|-------------|
| **Next Tab** | `Ctrl+Tab` | Switch to next tab |
| **Previous Tab** | `Ctrl+Shift+Tab` | Switch to previous tab |
| **Close Tab** | `Ctrl+W` | Close current tab |
| **Close All Tabs** | `Ctrl+Shift+W` | Close all tabs |
| **Close Other Tabs** | *Right-click → Close Others* | Close all tabs except current |
| **New Tab** | `Ctrl+N` | Create new empty tab |
| **Duplicate Tab** | *Right-click → Duplicate* | Duplicate current tab |

---

## Advanced Shortcuts

### Selection

| Action | Shortcut | Description |
|--------|----------|-------------|
| **Select All** | `Ctrl+A` | Select all text in editor |
| **Expand Selection** | `Shift+Alt+Right` | Expand selection to next word/token |
| **Shrink Selection** | `Shift+Alt+Left` | Shrink selection to previous word/token |
| **Select Line** | `Ctrl+L` | Select entire current line |
| **Select Word** | `Ctrl+Shift+Right/Left` | Select word at cursor |

### Comments

| Action | Shortcut | Description |
|--------|----------|-------------|
| **Toggle Line Comment** | `Ctrl+/` | Add/remove `--` comment |
| **Toggle Block Comment** | `Shift+Alt+A` | Add/remove `/* */` comment |

### Clipboard

| Action | Shortcut | Description |
|--------|----------|-------------|
| **Copy** | `Ctrl+C` | Copy selection or current line |
| **Cut** | `Ctrl+X` | Cut selection or current line |
| **Paste** | `Ctrl+V` | Paste from clipboard |
| **Paste and Match Style** | `Ctrl+Shift+V` | Paste without formatting |

---

## Context-Specific Shortcuts

### Quick Open Dialog (Ctrl+P)

| Action | Shortcut | Description |
|--------|----------|-------------|
| **Open Quick Open** | `Ctrl+P` | Open Quick Open dialog |
| **Filter by Type** | Type `@` | Show type filters (@table, @view, @sp) |
| **Navigate Results** | `Up/Down` | Navigate search results |
| **Select Item** | `Enter` | Open selected item |
| **Cancel** | `Esc` | Close Quick Open |

**Quick Open Type Filters**:
- `@table` - Show only tables
- `@view` - Show only views
- `@sp` or `@procedure` - Show only stored procedures
- `@fn` or `@function` - Show only functions

**Examples**:
- `Ctrl+P` → Type "Customer" → Shows all objects containing "Customer"
- `Ctrl+P` → Type "@table Customer" → Shows only tables containing "Customer"

### Object Browser

| Action | Shortcut | Description |
|--------|----------|-------------|
| **Toggle Object Browser** | `Ctrl+B` | Show/hide Object Browser |
| **Double-Click Object** | Mouse | Open object definition in new tab |
| **Right-Click Object** | Mouse | Show context menu |
| **Expand/Collapse** | `Space` or Click | Expand/collapse tree node |
| **Search in Browser** | Start typing | Filter objects (if implemented) |

### Results Grid

| Action | Shortcut | Description |
|--------|----------|-------------|
| **Copy Cell** | `Ctrl+C` | Copy selected cell value |
| **Copy Row** | Select row + `Ctrl+C` | Copy entire row (tab-delimited) |
| **Copy All** | Click "Copy" button | Copy all results (tab-delimited) |
| **Export CSV** | Click "CSV" button | Export results to CSV file |
| **Export JSON** | Click "JSON" button | Export results to JSON file |

---

## Monaco Editor (VSCode) Shortcuts

The code editor is powered by Monaco Editor (same engine as VSCode). Here are additional advanced shortcuts:

### IntelliSense

| Action | Shortcut | Description |
|--------|----------|-------------|
| **Trigger IntelliSense** | `Ctrl+Space` | Show autocomplete suggestions |
| **Parameter Hints** | `Ctrl+Shift+Space` | Show function parameter hints |
| **Quick Info** | `Ctrl+K Ctrl+I` | Show hover information |

### Refactoring

| Action | Shortcut | Description |
|--------|----------|-------------|
| **Rename Symbol** | `F2` | Rename variable/object (all occurrences) |
| **Format Document** | `Shift+Alt+F` | Format entire document |
| **Format Selection** | `Ctrl+K Ctrl+F` | Format selected code |

### Editor Split

| Action | Shortcut | Description |
|--------|----------|-------------|
| **Split Editor** | `Ctrl+\` | Split editor into two panels |
| **Focus Next Panel** | `Ctrl+K Ctrl+Right` | Move focus to next panel |
| **Focus Previous Panel** | `Ctrl+K Ctrl+Left` | Move focus to previous panel |

---

## Customizing Shortcuts

Currently, keyboard shortcuts are not customizable. This is planned for a future release.

**Planned Features**:
- Custom keyboard shortcut mapping
- Import/export keybindings
- Preset keybinding schemes (VSCode, SSMS, Sublime Text)

---

## Platform-Specific Notes

### Windows

- All shortcuts use `Ctrl` as the modifier key
- Right-click for context menus
- `Alt+F4` closes the entire browser tab/window

### Mac

- Replace `Ctrl` with `Cmd` (⌘) for most shortcuts
- Replace `Alt` with `Option` (⌥)
- `Cmd+Q` quits the browser application

### Linux

- Similar to Windows (uses `Ctrl`)
- Some shortcuts may conflict with desktop environment
- Check your desktop environment's shortcut settings if conflicts occur

---

## Tips & Tricks

### Productivity Hacks

1. **Quick Open is Your Friend**: Use `Ctrl+P` constantly to navigate without mouse
2. **Multi-Cursor Magic**: Use `Ctrl+D` to select next occurrence and edit all at once
3. **Format Before Running**: Press `Shift+Alt+F` before executing to format messy SQL
4. **Save Often**: Use `Ctrl+S` frequently (or enable auto-save)
5. **Close Results Before Running**: `Ctrl+Shift+R` to clear old results

### Workflow Examples

#### Renaming a Column in Multiple Queries

1. Select column name (e.g., `CustomerId`)
2. Press `Ctrl+D` repeatedly to select all occurrences
3. Type new name (e.g., `CustomerID`)
4. All occurrences updated simultaneously

#### Quickly Commenting Out Debug Code

1. Select lines to comment
2. Press `Ctrl+/`
3. Lines are commented with `--`
4. Press `Ctrl+/` again to uncomment

#### Navigating Large Scripts

1. Press `Ctrl+G`
2. Enter line number (e.g., `250`)
3. Editor jumps to that line
4. Use `Ctrl+Home` / `Ctrl+End` to jump to top/bottom

---

## Troubleshooting

### Shortcuts Not Working

**Symptoms**: Keyboard shortcuts don't respond.

**Possible Causes**:
- Browser extension conflict
- Browser itself captured the shortcut
- Editor doesn't have focus

**Solutions**:
1. Click in the editor to ensure it has focus
2. Check for browser extension conflicts (try disabling)
3. Try a different browser
4. Use mouse click as alternative

### Ctrl+S Triggers Browser Save Dialog

**Symptoms**: `Ctrl+S` opens "Save Web Page" dialog instead of saving script.

**Solution**: This is the expected behavior in some browsers. The script is still saved internally. Close the browser dialog.

**Workaround**: Enable auto-save in Configuration to avoid relying on manual saves.

---

## Reference Card (Printable)

### Most Common Shortcuts

```
ESSENTIAL
=========
Ctrl+S       Save Script
Ctrl+Enter   Run Query
Ctrl+P       Quick Open
Ctrl+F       Find
Ctrl+Z       Undo

EDITING
=======
Ctrl+D       Duplicate Line
Alt+Up/Down  Move Line
Ctrl+/       Toggle Comment
Shift+Alt+F  Format Code

NAVIGATION
==========
Ctrl+G       Go to Line
F12          Go to Definition
F8           Next Error
Ctrl+Tab     Next Tab
```

---

## Support

For questions or issues:
- **Documentation**: See full user guide
- **Configuration**: Press `Ctrl+,` or navigate to Configuration page
- **Report Issues**: GitHub Issues tracker
- **Request Features**: Submit feature requests to development team

---

**Version**: 1.0
**Last Updated**: 2025-11-02
**Prepared By**: SQL Monitor Development Team
