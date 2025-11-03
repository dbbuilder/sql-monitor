/**
 * KeyboardShortcutsHelp
 *
 * Modal dialog showing all available keyboard shortcuts.
 * Activated with Ctrl+K Ctrl+H or via toolbar button.
 */

import React from 'react';
import { css } from '@emotion/css';
import { GrafanaTheme2 } from '@grafana/data';
import { useStyles2, Modal, Icon } from '@grafana/ui';

/**
 * Keyboard shortcut definition
 */
interface KeyboardShortcut {
  category: string;
  shortcuts: Array<{
    keys: string;
    description: string;
  }>;
}

/**
 * All keyboard shortcuts organized by category
 */
const KEYBOARD_SHORTCUTS: KeyboardShortcut[] = [
  {
    category: 'General',
    shortcuts: [
      { keys: 'Ctrl+S', description: 'Save script' },
      { keys: 'Ctrl+N', description: 'New script' },
      { keys: 'Ctrl+P', description: 'Quick open script' },
      { keys: 'Ctrl+Shift+P', description: 'Command palette' },
      { keys: 'Ctrl+K Ctrl+H', description: 'Show keyboard shortcuts' },
    ],
  },
  {
    category: 'Query Execution',
    shortcuts: [
      { keys: 'Ctrl+Enter', description: 'Run query (or selected text)' },
      { keys: 'F5', description: 'Run query (alternative)' },
      { keys: 'Ctrl+Shift+Enter', description: 'Run query and show execution plan' },
      { keys: 'Esc', description: 'Cancel query execution' },
    ],
  },
  {
    category: 'Editing',
    shortcuts: [
      { keys: 'Ctrl+/', description: 'Toggle line comment' },
      { keys: 'Ctrl+Shift+/', description: 'Toggle block comment' },
      { keys: 'Ctrl+K Ctrl+C', description: 'Add line comment' },
      { keys: 'Ctrl+K Ctrl+U', description: 'Remove line comment' },
      { keys: 'Ctrl+D', description: 'Duplicate line' },
      { keys: 'Ctrl+Shift+K', description: 'Delete line' },
      { keys: 'Alt+Up', description: 'Move line up' },
      { keys: 'Alt+Down', description: 'Move line down' },
      { keys: 'Ctrl+]', description: 'Indent line' },
      { keys: 'Ctrl+[', description: 'Outdent line' },
    ],
  },
  {
    category: 'Formatting',
    shortcuts: [
      { keys: 'Ctrl+Shift+F', description: 'Format document' },
      { keys: 'Ctrl+K Ctrl+F', description: 'Format selection' },
      { keys: 'Shift+Alt+F', description: 'Format document (alternative)' },
    ],
  },
  {
    category: 'Search and Replace',
    shortcuts: [
      { keys: 'Ctrl+F', description: 'Find' },
      { keys: 'Ctrl+H', description: 'Replace' },
      { keys: 'F3', description: 'Find next' },
      { keys: 'Shift+F3', description: 'Find previous' },
      { keys: 'Ctrl+Shift+L', description: 'Select all occurrences' },
      { keys: 'Ctrl+F2', description: 'Change all occurrences' },
    ],
  },
  {
    category: 'Navigation',
    shortcuts: [
      { keys: 'Ctrl+G', description: 'Go to line' },
      { keys: 'F8', description: 'Go to next error/warning' },
      { keys: 'Shift+F8', description: 'Go to previous error/warning' },
      { keys: 'Ctrl+Shift+O', description: 'Go to symbol' },
      { keys: 'Ctrl+T', description: 'Go to object (table/view/SP)' },
    ],
  },
  {
    category: 'Multi-Cursor and Selection',
    shortcuts: [
      { keys: 'Alt+Click', description: 'Add cursor' },
      { keys: 'Ctrl+Alt+Up', description: 'Add cursor above' },
      { keys: 'Ctrl+Alt+Down', description: 'Add cursor below' },
      { keys: 'Ctrl+U', description: 'Undo last cursor operation' },
      { keys: 'Shift+Alt+Drag', description: 'Column (box) selection' },
    ],
  },
  {
    category: 'Code Analysis',
    shortcuts: [
      { keys: 'Alt+A', description: 'Run code analysis' },
      { keys: 'Alt+F', description: 'Apply quick fix' },
      { keys: 'F12', description: 'Go to definition (IntelliSense)' },
      { keys: 'Alt+F12', description: 'Peek definition' },
      { keys: 'Shift+F12', description: 'Find all references' },
    ],
  },
];

/**
 * KeyboardShortcutsHelp props
 */
interface KeyboardShortcutsHelpProps {
  /** Whether the dialog is open */
  isOpen: boolean;

  /** Callback when dialog is closed */
  onClose: () => void;
}

/**
 * KeyboardShortcutsHelp component
 */
export const KeyboardShortcutsHelp: React.FC<KeyboardShortcutsHelpProps> = ({ isOpen, onClose }) => {
  const styles = useStyles2(getStyles);

  if (!isOpen) {
    return null;
  }

  return (
    <Modal title="Keyboard Shortcuts" isOpen={isOpen} onDismiss={onClose} className={styles.modal}>
      <div className={styles.container}>
        <div className={styles.header}>
          <Icon name="keyboard" size="xl" className={styles.headerIcon} />
          <p className={styles.headerText}>
            Learn keyboard shortcuts to work faster. You can customize these shortcuts in the Configuration page.
          </p>
        </div>

        <div className={styles.categoriesGrid}>
          {KEYBOARD_SHORTCUTS.map((category) => (
            <div key={category.category} className={styles.category}>
              <h3 className={styles.categoryTitle}>{category.category}</h3>
              <div className={styles.shortcutsList}>
                {category.shortcuts.map((shortcut, index) => (
                  <div key={index} className={styles.shortcutRow}>
                    <div className={styles.shortcutKeys}>
                      {shortcut.keys.split(' ').map((key, keyIndex) => (
                        <React.Fragment key={keyIndex}>
                          {keyIndex > 0 && <span className={styles.keySeparator}>then</span>}
                          <kbd className={styles.key}>{key}</kbd>
                        </React.Fragment>
                      ))}
                    </div>
                    <div className={styles.shortcutDescription}>{shortcut.description}</div>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>

        <div className={styles.footer}>
          <p className={styles.footerHint}>
            <Icon name="info-circle" /> Tip: Press <kbd className={styles.key}>Ctrl+K</kbd> then{' '}
            <kbd className={styles.key}>Ctrl+H</kbd> to show this dialog anytime.
          </p>
        </div>
      </div>
    </Modal>
  );
};

/**
 * Component styles
 */
const getStyles = (theme: GrafanaTheme2) => ({
  modal: css`
    width: 90%;
    max-width: 1200px;
  `,

  container: css`
    display: flex;
    flex-direction: column;
    gap: ${theme.spacing(3)};
  `,

  header: css`
    display: flex;
    align-items: flex-start;
    gap: ${theme.spacing(2)};
    padding: ${theme.spacing(2)};
    background-color: ${theme.colors.background.secondary};
    border-radius: ${theme.shape.borderRadius()};
  `,

  headerIcon: css`
    color: ${theme.colors.primary.main};
    flex-shrink: 0;
    margin-top: ${theme.spacing(0.5)};
  `,

  headerText: css`
    margin: 0;
    color: ${theme.colors.text.secondary};
    font-size: ${theme.typography.body.fontSize};
  `,

  categoriesGrid: css`
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
    gap: ${theme.spacing(3)};
  `,

  category: css`
    display: flex;
    flex-direction: column;
    gap: ${theme.spacing(1.5)};
  `,

  categoryTitle: css`
    margin: 0;
    font-size: ${theme.typography.h5.fontSize};
    font-weight: ${theme.typography.h5.fontWeight};
    color: ${theme.colors.text.primary};
    padding-bottom: ${theme.spacing(1)};
    border-bottom: 2px solid ${theme.colors.border.medium};
  `,

  shortcutsList: css`
    display: flex;
    flex-direction: column;
    gap: ${theme.spacing(1)};
  `,

  shortcutRow: css`
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: ${theme.spacing(2)};
    padding: ${theme.spacing(0.75, 1)};
    border-radius: ${theme.shape.borderRadius()};
    transition: background-color 0.2s;

    &:hover {
      background-color: ${theme.colors.emphasize(theme.colors.background.primary, 0.03)};
    }
  `,

  shortcutKeys: css`
    display: flex;
    align-items: center;
    gap: ${theme.spacing(0.5)};
    flex-shrink: 0;
  `,

  key: css`
    display: inline-block;
    padding: ${theme.spacing(0.5, 1)};
    font-family: ${theme.typography.fontFamilyMonospace};
    font-size: ${theme.typography.bodySmall.fontSize};
    font-weight: ${theme.typography.fontWeightMedium};
    color: ${theme.colors.text.primary};
    background-color: ${theme.colors.background.secondary};
    border: 1px solid ${theme.colors.border.medium};
    border-radius: ${theme.shape.borderRadius(1)};
    box-shadow: 0 2px 0 ${theme.colors.border.weak};
    white-space: nowrap;
  `,

  keySeparator: css`
    font-size: ${theme.typography.bodySmall.fontSize};
    color: ${theme.colors.text.disabled};
    font-style: italic;
    padding: 0 ${theme.spacing(0.5)};
  `,

  shortcutDescription: css`
    flex: 1;
    color: ${theme.colors.text.secondary};
    font-size: ${theme.typography.body.fontSize};
  `,

  footer: css`
    padding: ${theme.spacing(2)};
    background-color: ${theme.colors.background.secondary};
    border-radius: ${theme.shape.borderRadius()};
    margin-top: ${theme.spacing(1)};
  `,

  footerHint: css`
    margin: 0;
    display: flex;
    align-items: center;
    gap: ${theme.spacing(1)};
    color: ${theme.colors.text.secondary};
    font-size: ${theme.typography.bodySmall.fontSize};

    svg {
      color: ${theme.colors.info.main};
    }
  `,
});
