/**
 * QuickOpenDialog
 *
 * VSCode-like Quick Open dialog (Ctrl+P) for:
 * - Fuzzy search across database objects
 * - Recent files
 * - Saved scripts
 * - Type filters (@table, @sp, @view, @function, @script)
 *
 * Features:
 * - Fuzzy matching with highlighted matches
 * - Keyboard navigation (arrow keys, Enter)
 * - Type-ahead filtering
 * - Icon badges for object types
 * - Recent files at top (last 10 accessed)
 */

import React, { useState, useEffect, useRef, useCallback } from 'react';
import { css } from '@emotion/css';
import { GrafanaTheme2 } from '@grafana/data';
import { useStyles2, Icon, IconName } from '@grafana/ui';
import { TabStateService } from '../../services/tabStateService';
import { AutoSaveService } from '../../services/autoSaveService';

/**
 * Quick Open item types
 */
export type QuickOpenItemType = 'table' | 'view' | 'procedure' | 'function' | 'script' | 'recent';

/**
 * Quick Open item interface
 */
export interface QuickOpenItem {
  id: string;
  type: QuickOpenItemType;
  label: string;          // Display name
  description?: string;   // Server / Database / Schema
  detail?: string;        // Additional info (row count, last modified, etc.)
  serverId?: number;
  serverName?: string;
  databaseName?: string;
  schemaName?: string;
  objectName?: string;
  scriptId?: string;
}

/**
 * Props interface
 */
interface QuickOpenDialogProps {
  isOpen: boolean;
  onClose: () => void;
  onSelect: (item: QuickOpenItem) => void;
}

/**
 * Icon mapping for object types
 */
const ICON_MAP: Record<QuickOpenItemType, IconName> = {
  table: 'table',
  view: 'eye',
  procedure: 'cube',
  function: 'calculator-alt',
  script: 'file-alt',
  recent: 'history',
};

/**
 * QuickOpenDialog component
 */
export const QuickOpenDialog: React.FC<QuickOpenDialogProps> = ({ isOpen, onClose, onSelect }) => {
  const styles = useStyles2(getStyles);
  const [searchText, setSearchText] = useState('');
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [items, setItems] = useState<QuickOpenItem[]>([]);
  const [filteredItems, setFilteredItems] = useState<QuickOpenItem[]>([]);
  const inputRef = useRef<HTMLInputElement>(null);
  const listRef = useRef<HTMLDivElement>(null);

  /**
   * Load items (recent files, scripts, database objects)
   */
  useEffect(() => {
    if (!isOpen) return;

    const allItems: QuickOpenItem[] = [];

    // 1. Recent files from TabStateService (last 10 accessed)
    const recentFiles = TabStateService.getRecentFiles();
    recentFiles.forEach((tab) => {
      if (tab.type === 'object') {
        allItems.push({
          id: `recent-${tab.id}`,
          type: 'recent',
          label: `${tab.schemaName}.${tab.objectName}`,
          description: `${tab.serverName} / ${tab.databaseName}`,
          detail: 'Recently opened',
          serverId: tab.serverId,
          serverName: tab.serverName,
          databaseName: tab.databaseName,
          schemaName: tab.schemaName,
          objectName: tab.objectName,
        });
      } else if (tab.type === 'script') {
        allItems.push({
          id: `recent-${tab.id}`,
          type: 'recent',
          label: tab.title,
          description: 'Saved Script',
          detail: 'Recently opened',
          scriptId: tab.scriptId,
        });
      }
    });

    // 2. Saved scripts from AutoSaveService
    const savedScripts = AutoSaveService.getAllScripts();
    savedScripts
      .filter((script) => !script.autoSaved) // Only manually saved scripts
      .forEach((script) => {
        allItems.push({
          id: `script-${script.id}`,
          type: 'script',
          label: script.name,
          description: script.databaseName
            ? `Server ${script.serverId} / ${script.databaseName}`
            : `Server ${script.serverId}`,
          detail: new Date(script.lastModified).toLocaleString(),
          serverId: script.serverId,
          databaseName: script.databaseName,
          scriptId: script.id,
        });
      });

    // 3. Database objects (mock data for now - will fetch from API in Week 3)
    // TODO: Week 3 - Fetch from SqlMonitorApiClient.getObjectMetadata()
    const mockDatabaseObjects: QuickOpenItem[] = [
      {
        id: 'obj-1',
        type: 'procedure',
        label: 'dbo.usp_GetCustomers',
        description: 'Server1 / SalesDB',
        detail: 'Stored Procedure',
        serverId: 1,
        serverName: 'Server1',
        databaseName: 'SalesDB',
        schemaName: 'dbo',
        objectName: 'usp_GetCustomers',
      },
      {
        id: 'obj-2',
        type: 'procedure',
        label: 'dbo.usp_GetOrders',
        description: 'Server1 / SalesDB',
        detail: 'Stored Procedure',
        serverId: 1,
        serverName: 'Server1',
        databaseName: 'SalesDB',
        schemaName: 'dbo',
        objectName: 'usp_GetOrders',
      },
      {
        id: 'obj-3',
        type: 'table',
        label: 'dbo.Customers',
        description: 'Server1 / SalesDB',
        detail: 'Table (15,342 rows)',
        serverId: 1,
        serverName: 'Server1',
        databaseName: 'SalesDB',
        schemaName: 'dbo',
        objectName: 'Customers',
      },
      {
        id: 'obj-4',
        type: 'view',
        label: 'dbo.vw_ActiveOrders',
        description: 'Server1 / SalesDB',
        detail: 'View',
        serverId: 1,
        serverName: 'Server1',
        databaseName: 'SalesDB',
        schemaName: 'dbo',
        objectName: 'vw_ActiveOrders',
      },
      {
        id: 'obj-5',
        type: 'function',
        label: 'dbo.fn_CalculateDiscount',
        description: 'Server1 / SalesDB',
        detail: 'Scalar Function',
        serverId: 1,
        serverName: 'Server1',
        databaseName: 'SalesDB',
        schemaName: 'dbo',
        objectName: 'fn_CalculateDiscount',
      },
    ];

    allItems.push(...mockDatabaseObjects);

    setItems(allItems);
    setFilteredItems(allItems);
    setSelectedIndex(0);
  }, [isOpen]);

  /**
   * Filter items based on search text
   */
  useEffect(() => {
    if (!searchText.trim()) {
      setFilteredItems(items);
      setSelectedIndex(0);
      return;
    }

    // Parse type filter (e.g., "@table query")
    let typeFilter: QuickOpenItemType | null = null;
    let query = searchText.toLowerCase();

    if (query.startsWith('@')) {
      const spaceIndex = query.indexOf(' ');
      if (spaceIndex > 0) {
        const typeStr = query.substring(1, spaceIndex);
        query = query.substring(spaceIndex + 1);

        // Map type aliases
        if (typeStr === 'sp') typeFilter = 'procedure';
        else if (['table', 'view', 'procedure', 'function', 'script'].includes(typeStr)) {
          typeFilter = typeStr as QuickOpenItemType;
        }
      }
    }

    // Fuzzy match algorithm
    const filtered = items
      .filter((item) => {
        // Apply type filter
        if (typeFilter && item.type !== typeFilter) {
          return false;
        }

        // Fuzzy match on label
        return fuzzyMatch(item.label.toLowerCase(), query);
      })
      .sort((a, b) => {
        // Sort by match quality (recent files first)
        if (a.type === 'recent' && b.type !== 'recent') return -1;
        if (a.type !== 'recent' && b.type === 'recent') return 1;
        return 0;
      });

    setFilteredItems(filtered);
    setSelectedIndex(0);
  }, [searchText, items]);

  /**
   * Focus input when dialog opens
   */
  useEffect(() => {
    if (isOpen && inputRef.current) {
      inputRef.current.focus();
      setSearchText('');
    }
  }, [isOpen]);

  /**
   * Scroll selected item into view
   */
  useEffect(() => {
    if (listRef.current) {
      const selectedElement = listRef.current.children[selectedIndex] as HTMLElement;
      if (selectedElement) {
        selectedElement.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
      }
    }
  }, [selectedIndex]);

  /**
   * Handle keyboard navigation
   */
  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      switch (e.key) {
        case 'ArrowDown':
          e.preventDefault();
          setSelectedIndex((prev) => Math.min(prev + 1, filteredItems.length - 1));
          break;
        case 'ArrowUp':
          e.preventDefault();
          setSelectedIndex((prev) => Math.max(prev - 1, 0));
          break;
        case 'Enter':
          e.preventDefault();
          if (filteredItems[selectedIndex]) {
            onSelect(filteredItems[selectedIndex]);
            onClose();
          }
          break;
        case 'Escape':
          e.preventDefault();
          onClose();
          break;
      }
    },
    [selectedIndex, filteredItems, onSelect, onClose]
  );

  /**
   * Handle item click
   */
  const handleItemClick = useCallback(
    (item: QuickOpenItem) => {
      onSelect(item);
      onClose();
    },
    [onSelect, onClose]
  );

  if (!isOpen) return null;

  return (
    <>
      {/* Backdrop */}
      <div className={styles.backdrop} onClick={onClose} />

      {/* Dialog */}
      <div className={styles.dialog}>
        {/* Search Input */}
        <div className={styles.searchContainer}>
          <Icon name="search" className={styles.searchIcon} />
          <input
            ref={inputRef}
            type="text"
            className={styles.searchInput}
            placeholder="Search database objects, scripts, recent files... (try @table, @sp, @view)"
            value={searchText}
            onChange={(e) => setSearchText(e.target.value)}
            onKeyDown={handleKeyDown}
          />
          {searchText && (
            <button className={styles.clearButton} onClick={() => setSearchText('')}>
              <Icon name="times" />
            </button>
          )}
        </div>

        {/* Results List */}
        <div className={styles.resultsList} ref={listRef}>
          {filteredItems.length === 0 ? (
            <div className={styles.emptyState}>
              <Icon name="search" size="xl" />
              <p>No results found</p>
              <p className={styles.hint}>Try different keywords or use type filters (@table, @sp, @view)</p>
            </div>
          ) : (
            filteredItems.map((item, index) => (
              <div
                key={item.id}
                className={`${styles.resultItem} ${index === selectedIndex ? styles.resultItemSelected : ''}`}
                onClick={() => handleItemClick(item)}
                onMouseEnter={() => setSelectedIndex(index)}
              >
                <Icon name={ICON_MAP[item.type]} className={styles.itemIcon} />
                <div className={styles.itemContent}>
                  <div className={styles.itemLabel}>
                    {highlightMatches(item.label, searchText)}
                    {item.type === 'recent' && <span className={styles.recentBadge}>Recent</span>}
                  </div>
                  {item.description && <div className={styles.itemDescription}>{item.description}</div>}
                </div>
                {item.detail && <div className={styles.itemDetail}>{item.detail}</div>}
              </div>
            ))
          )}
        </div>

        {/* Footer with hints */}
        <div className={styles.footer}>
          <span className={styles.footerHint}>
            <kbd>↑↓</kbd> Navigate
          </span>
          <span className={styles.footerHint}>
            <kbd>Enter</kbd> Select
          </span>
          <span className={styles.footerHint}>
            <kbd>Esc</kbd> Close
          </span>
        </div>
      </div>
    </>
  );
};

/**
 * Fuzzy match algorithm (simple character sequence matching)
 */
function fuzzyMatch(text: string, query: string): boolean {
  let queryIndex = 0;
  for (let i = 0; i < text.length && queryIndex < query.length; i++) {
    if (text[i] === query[queryIndex]) {
      queryIndex++;
    }
  }
  return queryIndex === query.length;
}

/**
 * Highlight matching characters in label
 */
function highlightMatches(label: string, query: string): React.ReactNode {
  if (!query.trim()) return label;

  // Remove type filter from query
  const cleanQuery = query.startsWith('@') ? query.substring(query.indexOf(' ') + 1) : query;
  if (!cleanQuery.trim()) return label;

  const lowerLabel = label.toLowerCase();
  const lowerQuery = cleanQuery.toLowerCase();

  const parts: React.ReactNode[] = [];
  let lastIndex = 0;
  let queryIndex = 0;

  for (let i = 0; i < lowerLabel.length && queryIndex < lowerQuery.length; i++) {
    if (lowerLabel[i] === lowerQuery[queryIndex]) {
      // Add non-matching part
      if (i > lastIndex) {
        parts.push(<span key={`text-${lastIndex}`}>{label.substring(lastIndex, i)}</span>);
      }
      // Add matching character (highlighted)
      parts.push(
        <span key={`match-${i}`} style={{ fontWeight: 'bold', color: '#4299e1' }}>
          {label[i]}
        </span>
      );
      lastIndex = i + 1;
      queryIndex++;
    }
  }

  // Add remaining text
  if (lastIndex < label.length) {
    parts.push(<span key={`text-${lastIndex}`}>{label.substring(lastIndex)}</span>);
  }

  return <>{parts}</>;
}

/**
 * Component styles
 */
const getStyles = (theme: GrafanaTheme2) => ({
  backdrop: css`
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background-color: rgba(0, 0, 0, 0.5);
    z-index: 9998;
  `,

  dialog: css`
    position: fixed;
    top: 15%;
    left: 50%;
    transform: translateX(-50%);
    width: 600px;
    max-width: 90%;
    background-color: ${theme.colors.background.primary};
    border: 1px solid ${theme.colors.border.medium};
    border-radius: ${theme.shape.borderRadius(2)};
    box-shadow: ${theme.shadows.z3};
    z-index: 9999;
    display: flex;
    flex-direction: column;
    max-height: 70vh;
  `,

  searchContainer: css`
    display: flex;
    align-items: center;
    padding: ${theme.spacing(2)};
    border-bottom: 1px solid ${theme.colors.border.weak};
    gap: ${theme.spacing(1)};
  `,

  searchIcon: css`
    color: ${theme.colors.text.secondary};
  `,

  searchInput: css`
    flex: 1;
    border: none;
    background: transparent;
    outline: none;
    font-size: ${theme.typography.body.fontSize};
    color: ${theme.colors.text.primary};

    &::placeholder {
      color: ${theme.colors.text.disabled};
    }
  `,

  clearButton: css`
    background: none;
    border: none;
    color: ${theme.colors.text.secondary};
    cursor: pointer;
    padding: ${theme.spacing(0.5)};
    display: flex;
    align-items: center;

    &:hover {
      color: ${theme.colors.text.primary};
    }
  `,

  resultsList: css`
    flex: 1;
    overflow-y: auto;
    max-height: 50vh;
  `,

  emptyState: css`
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: ${theme.spacing(4)};
    color: ${theme.colors.text.secondary};
    text-align: center;

    p {
      margin: ${theme.spacing(1, 0)};
    }
  `,

  hint: css`
    font-size: ${theme.typography.bodySmall.fontSize};
    color: ${theme.colors.text.disabled};
  `,

  resultItem: css`
    display: flex;
    align-items: center;
    padding: ${theme.spacing(1.5, 2)};
    cursor: pointer;
    gap: ${theme.spacing(1.5)};
    border-left: 3px solid transparent;

    &:hover {
      background-color: ${theme.colors.emphasize(theme.colors.background.primary, 0.03)};
    }
  `,

  resultItemSelected: css`
    background-color: ${theme.colors.emphasize(theme.colors.background.primary, 0.05)};
    border-left-color: ${theme.colors.primary.main};
  `,

  itemIcon: css`
    color: ${theme.colors.text.secondary};
  `,

  itemContent: css`
    flex: 1;
    min-width: 0;
  `,

  itemLabel: css`
    font-size: ${theme.typography.body.fontSize};
    color: ${theme.colors.text.primary};
    display: flex;
    align-items: center;
    gap: ${theme.spacing(1)};
  `,

  recentBadge: css`
    font-size: ${theme.typography.bodySmall.fontSize};
    color: ${theme.colors.info.text};
    background-color: ${theme.colors.info.transparent};
    padding: ${theme.spacing(0.25, 0.75)};
    border-radius: ${theme.shape.borderRadius()};
  `,

  itemDescription: css`
    font-size: ${theme.typography.bodySmall.fontSize};
    color: ${theme.colors.text.secondary};
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  `,

  itemDetail: css`
    font-size: ${theme.typography.bodySmall.fontSize};
    color: ${theme.colors.text.disabled};
    white-space: nowrap;
  `,

  footer: css`
    display: flex;
    gap: ${theme.spacing(2)};
    padding: ${theme.spacing(1, 2)};
    border-top: 1px solid ${theme.colors.border.weak};
    background-color: ${theme.colors.background.secondary};
  `,

  footerHint: css`
    font-size: ${theme.typography.bodySmall.fontSize};
    color: ${theme.colors.text.secondary};
    display: flex;
    align-items: center;
    gap: ${theme.spacing(0.5)};

    kbd {
      background-color: ${theme.colors.background.canvas};
      border: 1px solid ${theme.colors.border.medium};
      border-radius: ${theme.shape.borderRadius()};
      padding: ${theme.spacing(0.25, 0.5)};
      font-family: ${theme.typography.fontFamilyMonospace};
      font-size: ${theme.typography.bodySmall.fontSize};
    }
  `,
});
