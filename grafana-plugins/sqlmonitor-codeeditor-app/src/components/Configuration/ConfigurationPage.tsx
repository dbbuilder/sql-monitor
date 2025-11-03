/**
 * ConfigurationPage
 *
 * Plugin configuration and settings:
 * - Editor preferences (font size, theme, tab size)
 * - Analysis rules configuration (enable/disable rules)
 * - Auto-save settings
 * - Query execution defaults (timeout, max rows)
 * - Export/import settings
 *
 * Week 4 Day 17 implementation
 * Week 5 Day 18: Integrated with SettingsService
 */

import React, { useState, useEffect, useCallback } from 'react';
import { css } from '@emotion/css';
import { GrafanaTheme2 } from '@grafana/data';
import { useStyles2, Button, Input, Switch, Select, Field, FieldSet, Icon } from '@grafana/ui';
import { allRulesArray, ruleStats } from '../../services/rules';
import { settingsService, PluginSettings } from '../../services/settingsService';

/**
 * ConfigurationPage component
 */
export const ConfigurationPage: React.FC = () => {
  const styles = useStyles2(getStyles);
  const [settings, setSettings] = useState<PluginSettings>(settingsService.getSettings());
  const [hasChanges, setHasChanges] = useState(false);

  /**
   * Load settings on mount and subscribe to changes
   */
  useEffect(() => {
    // Load current settings
    setSettings(settingsService.getSettings());
    console.log('[Configuration] Loaded settings from service');

    // Subscribe to settings changes from other components
    const unsubscribe = settingsService.subscribe((updatedSettings) => {
      console.log('[Configuration] Settings updated by another component');
      setSettings(updatedSettings);
      setHasChanges(false);
    });

    return unsubscribe;
  }, []);

  /**
   * Save settings
   */
  const handleSave = useCallback(() => {
    settingsService.updateSettings(settings);
    setHasChanges(false);
    alert('Settings saved successfully');
    console.log('[Configuration] Settings saved via service');
  }, [settings]);

  /**
   * Reset to defaults
   */
  const handleReset = useCallback(() => {
    if (confirm('Reset all settings to defaults?')) {
      settingsService.resetToDefaults();
      setSettings(settingsService.getSettings());
      setHasChanges(false);
      alert('Settings reset to defaults');
      console.log('[Configuration] Settings reset to defaults via service');
    }
  }, []);

  /**
   * Update setting helper
   */
  const updateSetting = useCallback(<K extends keyof PluginSettings>(key: K, value: PluginSettings[K]) => {
    setSettings((prev) => ({ ...prev, [key]: value }));
    setHasChanges(true);
  }, []);

  /**
   * Toggle rule enabled/disabled
   */
  const toggleRule = useCallback(
    (ruleId: string) => {
      setSettings((prev) => {
        const disabledRules = prev.disabledRules.includes(ruleId)
          ? prev.disabledRules.filter((id) => id !== ruleId)
          : [...prev.disabledRules, ruleId];
        return { ...prev, disabledRules };
      });
      setHasChanges(true);
    },
    []
  );

  /**
   * Enable all rules in category
   */
  const enableAllInCategory = useCallback((category: string) => {
    const rulesInCategory = allRulesArray
      .filter((rule) => rule.category.toLowerCase() === category.toLowerCase())
      .map((rule) => rule.ruleId);

    setSettings((prev) => ({
      ...prev,
      disabledRules: prev.disabledRules.filter((id) => !rulesInCategory.includes(id)),
    }));
    setHasChanges(true);
  }, []);

  /**
   * Disable all rules in category
   */
  const disableAllInCategory = useCallback((category: string) => {
    const rulesInCategory = allRulesArray
      .filter((rule) => rule.category.toLowerCase() === category.toLowerCase())
      .map((rule) => rule.ruleId);

    setSettings((prev) => ({
      ...prev,
      disabledRules: [...new Set([...prev.disabledRules, ...rulesInCategory])],
    }));
    setHasChanges(true);
  }, []);

  /**
   * Export settings
   */
  const handleExport = useCallback(() => {
    const exportData = {
      settings: settingsService.getSettings(),
      exportedAt: new Date().toISOString(),
      version: '1.0',
    };

    const blob = new Blob([JSON.stringify(exportData, null, 2)], { type: 'application/json' });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = `sqlmonitor-settings-${Date.now()}.json`;
    link.click();

    console.log('[Configuration] Settings exported via service');
  }, []);

  /**
   * Import settings
   */
  const handleImport = useCallback(() => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = 'application/json';

    input.onchange = (e) => {
      const file = (e.target as HTMLInputElement).files?.[0];
      if (!file) return;

      const reader = new FileReader();
      reader.onload = (event) => {
        try {
          const data = JSON.parse(event.target?.result as string);
          if (data.settings) {
            // Import via service (validates and saves)
            settingsService.importSettings(JSON.stringify(data.settings));
            setSettings(settingsService.getSettings());
            setHasChanges(false);
            alert('Settings imported successfully');
            console.log('[Configuration] Settings imported via service');
          } else {
            alert('Invalid settings file format');
          }
        } catch (error) {
          console.error('[Configuration] Import failed:', error);
          alert(`Import failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
        }
      };
      reader.readAsText(file);
    };

    input.click();
  }, []);

  // Group rules by category
  const rulesByCategory = allRulesArray.reduce((acc, rule) => {
    if (!acc[rule.category]) {
      acc[rule.category] = [];
    }
    acc[rule.category].push(rule);
    return acc;
  }, {} as Record<string, typeof allRulesArray>);

  return (
    <div className={styles.container}>
      {/* Header */}
      <div className={styles.header}>
        <div>
          <h1>Configuration</h1>
          <p className={styles.subtitle}>Customize your SQL Code Editor experience</p>
        </div>
        <div className={styles.headerActions}>
          <Button icon="import" variant="secondary" onClick={handleImport}>
            Import Settings
          </Button>
          <Button icon="download-alt" variant="secondary" onClick={handleExport}>
            Export Settings
          </Button>
          <Button variant="secondary" onClick={handleReset}>
            Reset to Defaults
          </Button>
          <Button variant="primary" onClick={handleSave} disabled={!hasChanges}>
            {hasChanges ? 'Save Changes' : 'No Changes'}
          </Button>
        </div>
      </div>

      {/* Settings Content */}
      <div className={styles.content}>
        {/* Editor Settings */}
        <FieldSet label="Editor Settings">
          <Field label="Font Size" description="Editor font size in pixels">
            <Input
              type="number"
              value={settings.editorFontSize}
              onChange={(e) => updateSetting('editorFontSize', parseInt(e.currentTarget.value) || 14)}
              min={10}
              max={24}
              width={20}
            />
          </Field>

          <Field label="Tab Size" description="Number of spaces per tab">
            <Input
              type="number"
              value={settings.editorTabSize}
              onChange={(e) => updateSetting('editorTabSize', parseInt(e.currentTarget.value) || 4)}
              min={2}
              max={8}
              width={20}
            />
          </Field>

          <Field label="Show Line Numbers">
            <Switch
              value={settings.editorLineNumbers}
              onChange={(e) => updateSetting('editorLineNumbers', e.currentTarget.checked)}
            />
          </Field>

          <Field label="Show Minimap">
            <Switch
              value={settings.editorMinimap}
              onChange={(e) => updateSetting('editorMinimap', e.currentTarget.checked)}
            />
          </Field>

          <Field label="Word Wrap">
            <Switch
              value={settings.editorWordWrap}
              onChange={(e) => updateSetting('editorWordWrap', e.currentTarget.checked)}
            />
          </Field>
        </FieldSet>

        {/* Auto-Save Settings */}
        <FieldSet label="Auto-Save Settings">
          <Field label="Enable Auto-Save" description="Automatically save scripts while typing">
            <Switch
              value={settings.autoSaveEnabled}
              onChange={(e) => updateSetting('autoSaveEnabled', e.currentTarget.checked)}
            />
          </Field>

          <Field label="Auto-Save Delay (ms)" description="Delay before auto-saving after typing stops">
            <Input
              type="number"
              value={settings.autoSaveDelayMs}
              onChange={(e) => updateSetting('autoSaveDelayMs', parseInt(e.currentTarget.value) || 2000)}
              min={500}
              max={10000}
              step={500}
              width={20}
              disabled={!settings.autoSaveEnabled}
            />
          </Field>
        </FieldSet>

        {/* Query Execution Settings */}
        <FieldSet label="Query Execution Settings">
          <Field label="Query Timeout (seconds)" description="Maximum execution time for queries">
            <Input
              type="number"
              value={settings.queryTimeoutSeconds}
              onChange={(e) => updateSetting('queryTimeoutSeconds', parseInt(e.currentTarget.value) || 60)}
              min={10}
              max={300}
              width={20}
            />
          </Field>

          <Field label="Max Rows Per Page" description="Default pagination size for result grids">
            <Select
              options={[
                { label: '10 rows', value: 10 },
                { label: '25 rows', value: 25 },
                { label: '50 rows', value: 50 },
                { label: '100 rows', value: 100 },
                { label: '500 rows', value: 500 },
              ]}
              value={settings.maxRowsPerPage}
              onChange={(option) => updateSetting('maxRowsPerPage', option.value!)}
              width={20}
            />
          </Field>
        </FieldSet>

        {/* Analysis Settings */}
        <FieldSet label="Code Analysis Settings">
          <Field label="Auto-Run Analysis" description="Automatically run analysis when opening a script">
            <Switch
              value={settings.analysisAutoRun}
              onChange={(e) => updateSetting('analysisAutoRun', e.currentTarget.checked)}
            />
          </Field>

          <div className={styles.rulesSection}>
            <div className={styles.rulesSectionHeader}>
              <h3>Analysis Rules</h3>
              <span className={styles.rulesCount}>
                {allRulesArray.length - settings.disabledRules.length} of {allRulesArray.length} rules enabled
              </span>
            </div>

            {Object.entries(rulesByCategory).map(([category, rules]) => (
              <div key={category} className={styles.ruleCategory}>
                <div className={styles.ruleCategoryHeader}>
                  <h4>
                    {category} ({rules.filter((r) => !settings.disabledRules.includes(r.ruleId)).length} /{' '}
                    {rules.length})
                  </h4>
                  <div className={styles.categoryActions}>
                    <Button size="sm" variant="secondary" onClick={() => enableAllInCategory(category)}>
                      Enable All
                    </Button>
                    <Button size="sm" variant="secondary" onClick={() => disableAllInCategory(category)}>
                      Disable All
                    </Button>
                  </div>
                </div>

                <div className={styles.rulesList}>
                  {rules.map((rule) => (
                    <div key={rule.ruleId} className={styles.ruleItem}>
                      <Switch
                        value={!settings.disabledRules.includes(rule.ruleId)}
                        onChange={() => toggleRule(rule.ruleId)}
                      />
                      <div className={styles.ruleInfo}>
                        <div className={styles.ruleHeader}>
                          <span className={styles.ruleId}>{rule.ruleId}</span>
                          <span className={`${styles.severity} ${styles[`severity${rule.severity}`]}`}>
                            {rule.severity}
                          </span>
                        </div>
                        <div className={styles.ruleMessage}>{rule.message}</div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </FieldSet>

        {/* UI Settings */}
        <FieldSet label="UI Settings">
          <Field label="Show Object Browser by Default">
            <Switch
              value={settings.showObjectBrowserByDefault}
              onChange={(e) => updateSetting('showObjectBrowserByDefault', e.currentTarget.checked)}
            />
          </Field>

          <Field label="Show Analysis Panel by Default">
            <Switch
              value={settings.showAnalysisPanelByDefault}
              onChange={(e) => updateSetting('showAnalysisPanelByDefault', e.currentTarget.checked)}
            />
          </Field>
        </FieldSet>
      </div>
    </div>
  );
};

/**
 * Component styles
 */
const getStyles = (theme: GrafanaTheme2) => ({
  container: css`
    display: flex;
    flex-direction: column;
    height: 100%;
    padding: ${theme.spacing(3)};
    background-color: ${theme.colors.background.primary};
  `,

  header: css`
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    margin-bottom: ${theme.spacing(3)};

    h1 {
      margin: 0 0 ${theme.spacing(0.5)} 0;
      font-size: ${theme.typography.h2.fontSize};
      font-weight: ${theme.typography.h2.fontWeight};
    }
  `,

  subtitle: css`
    margin: 0;
    color: ${theme.colors.text.secondary};
    font-size: ${theme.typography.body.fontSize};
  `,

  headerActions: css`
    display: flex;
    gap: ${theme.spacing(1)};
  `,

  content: css`
    flex: 1;
    overflow-y: auto;
    display: flex;
    flex-direction: column;
    gap: ${theme.spacing(3)};
  `,

  rulesSection: css`
    margin-top: ${theme.spacing(2)};
  `,

  rulesSectionHeader: css`
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: ${theme.spacing(2)};

    h3 {
      margin: 0;
      font-size: ${theme.typography.h4.fontSize};
    }
  `,

  rulesCount: css`
    font-size: ${theme.typography.bodySmall.fontSize};
    color: ${theme.colors.text.secondary};
    padding: ${theme.spacing(0.5, 1)};
    background-color: ${theme.colors.background.canvas};
    border-radius: ${theme.shape.borderRadius()};
  `,

  ruleCategory: css`
    margin-bottom: ${theme.spacing(3)};
    padding: ${theme.spacing(2)};
    background-color: ${theme.colors.background.secondary};
    border: 1px solid ${theme.colors.border.weak};
    border-radius: ${theme.shape.borderRadius()};
  `,

  ruleCategoryHeader: css`
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: ${theme.spacing(2)};

    h4 {
      margin: 0;
      font-size: ${theme.typography.h5.fontSize};
      color: ${theme.colors.text.primary};
    }
  `,

  categoryActions: css`
    display: flex;
    gap: ${theme.spacing(1)};
  `,

  rulesList: css`
    display: flex;
    flex-direction: column;
    gap: ${theme.spacing(1)};
  `,

  ruleItem: css`
    display: flex;
    align-items: flex-start;
    gap: ${theme.spacing(1.5)};
    padding: ${theme.spacing(1.5)};
    background-color: ${theme.colors.background.primary};
    border-radius: ${theme.shape.borderRadius()};
  `,

  ruleInfo: css`
    flex: 1;
  `,

  ruleHeader: css`
    display: flex;
    align-items: center;
    gap: ${theme.spacing(1)};
    margin-bottom: ${theme.spacing(0.5)};
  `,

  ruleId: css`
    font-family: ${theme.typography.fontFamilyMonospace};
    font-size: ${theme.typography.bodySmall.fontSize};
    color: ${theme.colors.text.secondary};
    font-weight: ${theme.typography.fontWeightMedium};
  `,

  severity: css`
    font-size: ${theme.typography.bodySmall.fontSize};
    font-weight: ${theme.typography.fontWeightMedium};
    padding: ${theme.spacing(0.25, 0.75)};
    border-radius: ${theme.shape.borderRadius()};
    text-transform: uppercase;
  `,

  severityError: css`
    background-color: ${theme.colors.error.transparent};
    color: ${theme.colors.error.text};
  `,

  severityWarning: css`
    background-color: ${theme.colors.warning.transparent};
    color: ${theme.colors.warning.text};
  `,

  severityInfo: css`
    background-color: ${theme.colors.info.transparent};
    color: ${theme.colors.info.text};
  `,

  ruleMessage: css`
    font-size: ${theme.typography.body.fontSize};
    color: ${theme.colors.text.primary};
  `,
});
