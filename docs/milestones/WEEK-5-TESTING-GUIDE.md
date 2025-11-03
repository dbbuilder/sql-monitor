# Week 5 Testing Guide - Settings Integration

**Feature**: Phase 3 Feature #7 - T-SQL Code Editor & Analyzer
**Week**: Week 5 (Day 18)
**Date**: 2025-11-02
**Status**: Settings Integration Complete - Ready for Testing

---

## Overview

Week 5 focused on integrating the SettingsService across all components to provide a unified configuration system. This testing guide provides comprehensive procedures to validate all settings functionality.

---

## Table of Contents

1. [Test Environment Setup](#test-environment-setup)
2. [Settings Service Tests](#settings-service-tests)
3. [Configuration Page Tests](#configuration-page-tests)
4. [Code Editor Integration Tests](#code-editor-integration-tests)
5. [Monaco Editor Settings Tests](#monaco-editor-settings-tests)
6. [Analysis Engine Integration Tests](#analysis-engine-integration-tests)
7. [Auto-Save Integration Tests](#auto-save-integration-tests)
8. [End-to-End User Scenarios](#end-to-end-user-scenarios)
9. [Known Issues and Limitations](#known-issues-and-limitations)

---

## Test Environment Setup

### Prerequisites

1. **Grafana Instance**: Running locally or in development environment
2. **Plugin Installed**: SQL Monitor Code Editor plugin installed and enabled
3. **Browser**: Chrome/Firefox with developer console access
4. **Test Data**: At least 2 SQL scripts saved for testing

### Setup Steps

1. Navigate to Grafana
2. Open SQL Monitor Code Editor plugin
3. Open browser developer console (F12) to monitor console logs
4. Clear localStorage (optional, for clean state):
   ```javascript
   localStorage.clear();
   location.reload();
   ```

---

## Settings Service Tests

### Test 1.1: Default Settings Loading

**Objective**: Verify that default settings are loaded when no saved settings exist.

**Steps**:
1. Clear localStorage
2. Reload the plugin
3. Navigate to Configuration page
4. Verify default values:
   - Font Size: 14
   - Tab Size: 4
   - Line Numbers: ON
   - Minimap: ON
   - Word Wrap: OFF
   - Auto-Save Enabled: ON
   - Auto-Save Delay: 5000ms
   - Query Timeout: 60 seconds
   - Max Rows Per Page: 50
   - Analysis Auto-Run: ON
   - Show Object Browser: ON
   - Show Analysis Panel: ON
   - Disabled Rules: 0 rules

**Expected Result**: All settings show default values.

### Test 1.2: Settings Persistence

**Objective**: Verify that settings persist across page reloads.

**Steps**:
1. Navigate to Configuration page
2. Change Font Size to 18
3. Change Tab Size to 2
4. Disable Auto-Save
5. Click "Save"
6. Reload the page
7. Navigate to Configuration page

**Expected Result**: All changed settings retain their values after reload.

### Test 1.3: Settings Export

**Objective**: Verify that settings can be exported to JSON.

**Steps**:
1. Navigate to Configuration page
2. Make several settings changes
3. Click "Save"
4. Click "Export Settings"
5. Open the downloaded JSON file

**Expected Result**:
- File name: `sqlmonitor-settings-{timestamp}.json`
- JSON structure contains:
  - `settings` object with all configuration values
  - `exportedAt` timestamp
  - `version` field

### Test 1.4: Settings Import

**Objective**: Verify that settings can be imported from JSON.

**Steps**:
1. Export settings (Test 1.3)
2. Change several settings to different values
3. Click "Import Settings"
4. Select the previously exported JSON file
5. Verify settings are restored

**Expected Result**: All settings match the imported file values.

---

## Configuration Page Tests

### Test 2.1: Editor Settings Section

**Objective**: Verify all editor settings controls function correctly.

**Steps**:
1. Navigate to Configuration page
2. Test each control:
   - Font Size slider (10-24)
   - Tab Size input (2-8)
   - Line Numbers toggle
   - Minimap toggle
   - Word Wrap toggle
3. Change each setting
4. Click "Save"
5. Verify success message

**Expected Result**: All controls are functional and settings save successfully.

### Test 2.2: Auto-Save Settings Section

**Objective**: Verify auto-save settings controls.

**Steps**:
1. Toggle "Auto-Save Enabled"
2. Adjust "Auto-Save Delay" slider (1000-30000ms)
3. Click "Save"
4. Open Code Editor
5. Type in editor
6. Wait for auto-save delay
7. Check console for auto-save message

**Expected Result**: Auto-save respects the configured delay.

### Test 2.3: Query Execution Settings

**Objective**: Verify query execution settings.

**Steps**:
1. Set Query Timeout to 30 seconds
2. Set Max Rows Per Page to 25
3. Click "Save"
4. Navigate to Code Editor
5. Run a SELECT query
6. Check Results Grid pagination

**Expected Result**: Pagination shows 25 rows per page options.

### Test 2.4: Analysis Rules Configuration

**Objective**: Verify analysis rules can be enabled/disabled.

**Steps**:
1. Navigate to Configuration > Code Analysis Settings
2. Disable all Performance rules (click "Disable All")
3. Click "Save"
4. Navigate to Code Editor
5. Write code that triggers a Performance rule (e.g., `SELECT *`)
6. Click "Analyze"
7. Verify no Performance warnings appear

**Expected Result**: Disabled rules do not trigger warnings.

### Test 2.5: Individual Rule Toggle

**Objective**: Verify individual rules can be toggled.

**Steps**:
1. Navigate to Configuration > Code Analysis Settings
2. Find rule P001 (SELECT *)
3. Disable only P001
4. Click "Save"
5. Navigate to Code Editor
6. Write `SELECT * FROM Customers`
7. Click "Analyze"
8. Verify no P001 warning appears
9. Write code for P002 (Missing WHERE clause)
10. Click "Analyze"
11. Verify P002 warning DOES appear

**Expected Result**: Only disabled rules are suppressed.

### Test 2.6: Enable/Disable All in Category

**Objective**: Verify batch enable/disable for rule categories.

**Steps**:
1. Click "Disable All" for Security category
2. Verify all 5 Security rules are disabled
3. Click "Enable All" for Security category
4. Verify all 5 Security rules are enabled

**Expected Result**: Batch operations work correctly.

### Test 2.7: Reset to Defaults

**Objective**: Verify reset functionality.

**Steps**:
1. Make extensive changes to settings
2. Click "Save"
3. Click "Reset to Defaults"
4. Confirm the dialog
5. Verify all settings return to defaults

**Expected Result**: All settings reset to default values, confirmation message shown.

---

## Code Editor Integration Tests

### Test 3.1: Object Browser Default Visibility

**Objective**: Verify object browser respects default visibility setting.

**Steps**:
1. Navigate to Configuration
2. Set "Show Object Browser by Default" to OFF
3. Click "Save"
4. Navigate to Code Editor
5. Verify object browser is hidden
6. Toggle object browser button
7. Verify object browser appears

**Expected Result**: Object browser respects the default visibility setting.

### Test 3.2: Query Timeout Integration

**Objective**: Verify query execution uses configured timeout.

**Steps**:
1. Navigate to Configuration
2. Set Query Timeout to 15 seconds
3. Click "Save"
4. Navigate to Code Editor
5. Open browser console
6. Run a query
7. Check console log for timeout value

**Expected Result**: Console shows "Query timeout: 15 seconds".

### Test 3.3: Settings Live Update

**Objective**: Verify settings update without page reload.

**Steps**:
1. Open Code Editor in one browser tab
2. Open Configuration in another tab
3. In Configuration tab, change "Show Object Browser" to OFF
4. Click "Save"
5. Switch to Code Editor tab
6. Verify object browser automatically hides (no reload needed)

**Expected Result**: Code Editor updates immediately when settings change.

---

## Monaco Editor Settings Tests

### Test 4.1: Font Size Change

**Objective**: Verify font size changes apply to Monaco editor.

**Steps**:
1. Navigate to Configuration
2. Set Font Size to 20
3. Click "Save"
4. Navigate to Code Editor
5. Inspect editor text
6. Verify font size is 20px

**Expected Result**: Editor text displays at 20px font size.

### Test 4.2: Tab Size Change

**Objective**: Verify tab size changes apply to Monaco editor.

**Steps**:
1. Navigate to Configuration
2. Set Tab Size to 2
3. Click "Save"
4. Navigate to Code Editor
5. Type code with indentation
6. Press Tab key
7. Verify indentation is 2 spaces

**Expected Result**: Tab key inserts 2 spaces.

### Test 4.3: Line Numbers Toggle

**Objective**: Verify line numbers can be hidden/shown.

**Steps**:
1. Navigate to Configuration
2. Set Line Numbers to OFF
3. Click "Save"
4. Navigate to Code Editor
5. Verify line numbers are hidden
6. Go back to Configuration
7. Set Line Numbers to ON
8. Click "Save"
9. Return to Code Editor
10. Verify line numbers are visible

**Expected Result**: Line numbers toggle correctly.

### Test 4.4: Minimap Toggle

**Objective**: Verify minimap can be hidden/shown.

**Steps**:
1. Navigate to Configuration
2. Set Minimap to OFF
3. Click "Save"
4. Navigate to Code Editor
5. Verify minimap (right-side code overview) is hidden

**Expected Result**: Minimap is not visible when disabled.

### Test 4.5: Word Wrap Toggle

**Objective**: Verify word wrap can be enabled/disabled.

**Steps**:
1. Navigate to Configuration
2. Set Word Wrap to ON
3. Click "Save"
4. Navigate to Code Editor
5. Write a very long line of code (200+ characters)
6. Verify line wraps to next line (no horizontal scroll)

**Expected Result**: Long lines wrap when word wrap is enabled.

### Test 4.6: Live Editor Settings Update

**Objective**: Verify editor settings update without closing/reopening editor.

**Steps**:
1. Open Code Editor
2. Note current font size (e.g., 14px)
3. Without closing editor, navigate to Configuration (in sidebar or new tab)
4. Change Font Size to 22
5. Click "Save"
6. Return to Code Editor (do not reload)
7. Verify font size changed to 22px

**Expected Result**: Editor settings update in real-time via settings subscription.

---

## Analysis Engine Integration Tests

### Test 5.1: Disabled Rules Not Executed

**Objective**: Verify disabled rules are not executed during analysis.

**Steps**:
1. Navigate to Configuration
2. Disable rule P001 (SELECT *)
3. Click "Save"
4. Navigate to Code Editor
5. Write: `SELECT * FROM Customers`
6. Click "Analyze"
7. Check console for analysis log

**Expected Result**: Console shows "X rules executed (1 disabled by settings)" and P001 warning does not appear.

### Test 5.2: Analysis Auto-Run Setting

**Objective**: Verify analysis auto-run can be disabled.

**Steps**:
1. Navigate to Configuration
2. Set "Auto-Run Analysis" to OFF
3. Click "Save"
4. Navigate to Code Editor
5. Type code with an issue
6. Wait 2 seconds
7. Verify analysis panel does not update automatically
8. Click "Analyze" button manually
9. Verify analysis panel updates

**Expected Result**: Analysis only runs when manually triggered.

### Test 5.3: Category-Level Rule Disabling

**Objective**: Verify disabling entire category suppresses all rules in that category.

**Steps**:
1. Navigate to Configuration
2. Disable all "Performance" rules (10 rules)
3. Click "Save"
4. Navigate to Code Editor
5. Write code that violates multiple Performance rules:
   ```sql
   SELECT * FROM Customers WHERE 1=1
   ```
6. Click "Analyze"
7. Verify no Performance warnings appear (P001, P002, etc.)

**Expected Result**: All Performance rules are suppressed.

---

## Auto-Save Integration Tests

### Test 6.1: Auto-Save Enabled/Disabled

**Objective**: Verify auto-save respects enabled setting.

**Steps**:
1. Navigate to Configuration
2. Set Auto-Save to OFF
3. Click "Save"
4. Navigate to Code Editor
5. Type content
6. Wait 10 seconds
7. Check localStorage for `sqlmonitor-current-script`
8. Verify no auto-save occurred
9. Go back to Configuration
10. Set Auto-Save to ON
11. Click "Save"
12. Type more content
13. Wait 10 seconds
14. Check localStorage again
15. Verify auto-save occurred

**Expected Result**: Auto-save only functions when enabled.

### Test 6.2: Auto-Save Delay Configuration

**Objective**: Verify auto-save delay is configurable.

**Steps**:
1. Navigate to Configuration
2. Set Auto-Save Delay to 10000ms (10 seconds)
3. Click "Save"
4. Navigate to Code Editor
5. Open console
6. Type content
7. Monitor console logs
8. Verify auto-save triggers after 10 seconds

**Expected Result**: Auto-save waits for configured delay.

### Test 6.3: Dynamic Auto-Save Delay Update

**Objective**: Verify changing auto-save delay recreates debounced function.

**Steps**:
1. Set Auto-Save Delay to 5000ms
2. Start typing in editor
3. While typing, change delay to 2000ms
4. Continue typing
5. Verify auto-save now triggers after 2 seconds

**Expected Result**: Delay change takes effect immediately.

---

## End-to-End User Scenarios

### Scenario 1: New User First-Time Setup

**Objective**: Simulate a new user configuring the plugin for first use.

**Steps**:
1. Clear localStorage (fresh start)
2. Open plugin
3. Navigate to Configuration
4. Customize settings:
   - Font Size: 16
   - Tab Size: 2
   - Disable SELECT * rule
   - Enable all Security rules
5. Click "Save"
6. Navigate to Code Editor
7. Verify all customizations applied
8. Write and run a query
9. Save a script
10. Reload page
11. Verify settings persisted

**Expected Result**: User experience is smooth, all settings work as configured.

### Scenario 2: Power User with Custom Configuration

**Objective**: Simulate advanced user with extensive customizations.

**Steps**:
1. Configure extensive rule customizations (disable 20 rules)
2. Set custom editor preferences (large font, no minimap, word wrap)
3. Disable auto-save
4. Set query timeout to 120 seconds
5. Export settings
6. Clear localStorage
7. Import settings
8. Verify all customizations restored
9. Work in editor for 10 minutes
10. Verify all settings remain consistent

**Expected Result**: Power user workflow is fully supported.

### Scenario 3: Team Configuration Sharing

**Objective**: Simulate team members sharing a standard configuration.

**Steps**:
1. User A creates custom configuration
2. User A exports settings to file
3. User A shares file with User B (via email/Slack)
4. User B imports settings
5. Verify both users have identical settings

**Expected Result**: Configuration sharing works seamlessly.

### Scenario 4: Settings Update During Active Editing

**Objective**: Verify settings can be updated mid-workflow without disruption.

**Steps**:
1. Open Code Editor with active script
2. Start editing (make 50+ changes)
3. Without saving script, open Configuration in new tab
4. Change multiple settings
5. Click "Save" in Configuration
6. Return to Code Editor
7. Verify:
   - Editor settings updated (font size, etc.)
   - Script content not lost
   - Cursor position maintained
   - Undo history preserved

**Expected Result**: Settings update without disrupting editing session.

---

## Known Issues and Limitations

### Issue 1: Settings Service Initialization Timing

**Description**: If SettingsService methods are called before the service initializes, default settings may be used.

**Workaround**: Service initializes on first getInstance() call, so this is typically not an issue.

**Severity**: Low

---

### Issue 2: Auto-Save Delay Change Requires Active Typing

**Description**: Changing auto-save delay doesn't cancel pending auto-save from previous delay.

**Workaround**: Type additional content to trigger new debounced function.

**Severity**: Low

---

### Issue 3: Monaco Editor Minimap Flicker on Setting Change

**Description**: Toggling minimap while editor is open may cause brief visual flicker.

**Workaround**: Acceptable UX trade-off for live setting updates.

**Severity**: Cosmetic

---

### Issue 4: Browser LocalStorage Quota

**Description**: Extensive script saving may exceed browser localStorage quota (5-10MB).

**Workaround**: Clean up old scripts periodically.

**Severity**: Low (unlikely to occur in normal usage)

---

## Testing Checklist Summary

### Settings Service
- [ ] Default settings load correctly
- [ ] Settings persist across reloads
- [ ] Settings export/import works
- [ ] Settings change listeners fire correctly

### Configuration Page
- [ ] All editor settings controls functional
- [ ] Auto-save settings apply correctly
- [ ] Query execution settings apply correctly
- [ ] Analysis rules can be toggled individually
- [ ] Analysis rules can be batch enabled/disabled
- [ ] Reset to defaults works
- [ ] Success/error messages display

### Code Editor Integration
- [ ] Object browser default visibility works
- [ ] Query timeout uses configured value
- [ ] Settings update without page reload

### Monaco Editor Integration
- [ ] Font size changes apply
- [ ] Tab size changes apply
- [ ] Line numbers toggle works
- [ ] Minimap toggle works
- [ ] Word wrap toggle works
- [ ] Live settings updates work (no reload needed)

### Analysis Engine Integration
- [ ] Disabled rules not executed
- [ ] Analysis auto-run setting works
- [ ] Category-level disabling works
- [ ] Console logs show disabled rule count

### Auto-Save Integration
- [ ] Auto-save enabled/disabled works
- [ ] Auto-save delay configuration works
- [ ] Dynamic delay update works

### End-to-End Scenarios
- [ ] New user first-time setup
- [ ] Power user with extensive customizations
- [ ] Team configuration sharing
- [ ] Settings update during active editing

---

## Test Execution Tracking

| Test ID | Test Name | Status | Date | Tester | Notes |
|---------|-----------|--------|------|--------|-------|
| 1.1 | Default Settings Loading | ⬜ Not Run | | | |
| 1.2 | Settings Persistence | ⬜ Not Run | | | |
| 1.3 | Settings Export | ⬜ Not Run | | | |
| 1.4 | Settings Import | ⬜ Not Run | | | |
| 2.1 | Editor Settings Section | ⬜ Not Run | | | |
| 2.2 | Auto-Save Settings | ⬜ Not Run | | | |
| 2.3 | Query Execution Settings | ⬜ Not Run | | | |
| 2.4 | Analysis Rules Config | ⬜ Not Run | | | |
| 2.5 | Individual Rule Toggle | ⬜ Not Run | | | |
| 2.6 | Enable/Disable Category | ⬜ Not Run | | | |
| 2.7 | Reset to Defaults | ⬜ Not Run | | | |
| 3.1 | Object Browser Visibility | ⬜ Not Run | | | |
| 3.2 | Query Timeout Integration | ⬜ Not Run | | | |
| 3.3 | Settings Live Update | ⬜ Not Run | | | |
| 4.1 | Font Size Change | ⬜ Not Run | | | |
| 4.2 | Tab Size Change | ⬜ Not Run | | | |
| 4.3 | Line Numbers Toggle | ⬜ Not Run | | | |
| 4.4 | Minimap Toggle | ⬜ Not Run | | | |
| 4.5 | Word Wrap Toggle | ⬜ Not Run | | | |
| 4.6 | Live Editor Settings | ⬜ Not Run | | | |
| 5.1 | Disabled Rules Not Executed | ⬜ Not Run | | | |
| 5.2 | Analysis Auto-Run | ⬜ Not Run | | | |
| 5.3 | Category-Level Disabling | ⬜ Not Run | | | |
| 6.1 | Auto-Save Enabled/Disabled | ⬜ Not Run | | | |
| 6.2 | Auto-Save Delay Config | ⬜ Not Run | | | |
| 6.3 | Dynamic Delay Update | ⬜ Not Run | | | |

**Legend**: ⬜ Not Run | ✅ Pass | ❌ Fail | ⚠️ Pass with Issues

---

## Regression Testing

When making future changes to settings functionality, re-run this entire test suite to ensure no regressions are introduced.

**Estimated Testing Time**: 3-4 hours for comprehensive execution

---

## Conclusion

This testing guide provides comprehensive coverage of the Week 5 settings integration. All tests should pass before considering the feature production-ready.

**Next Steps After Testing**:
1. Document any bugs found during testing
2. Create bug fix tickets for critical issues
3. Update user documentation with configuration examples
4. Proceed to Week 6 implementation (API integration, if planned)

---

**Prepared By**: Claude Code Assistant
**Date**: 2025-11-02
**Version**: 1.0
