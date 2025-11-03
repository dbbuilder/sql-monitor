/**
 * TabBar
 *
 * Tab management UI for the code editor.
 * Features:
 * - Visual tab display with icons
 * - Close, pin, drag-and-drop
 * - Context menu actions
 * - Unsaved changes indicator
 */

import React, { useState, useCallback } from 'react';
import { css } from '@emotion/css';
import { GrafanaTheme2 } from '@grafana/data';
import { useStyles2, Icon, Tooltip, ContextMenu, MenuItem } from '@grafana/ui';
import type { TabState } from '../../services/tabStateService';

/**
 * TabBar props
 */
interface TabBarProps {
  /** All open tabs */
  tabs: TabState[];

  /** Index of active tab */
  activeTabIndex: number;

  /** Callback when tab is clicked */
  onTabClick: (tabId: string) => void;

  /** Callback when tab is closed */
  onTabClose: (tabId: string) => void;

  /** Callback when new tab is created */
  onNewTab: () => void;

  /** Callback when tab context menu action is triggered */
  onTabContextAction: (tabId: string, action: string) => void;

  /** Callback when tab is dragged */
  onTabReorder?: (fromIndex: number, toIndex: number) => void;
}

/**
 * Get icon for tab type
 */
function getTabIcon(tab: TabState): string {
  if (tab.type === 'untitled') {
    return 'file-blank';
  }

  if (tab.type === 'script') {
    return 'save';
  }

  // Database object
  switch (tab.objectType) {
    case 'table':
      return 'table';
    case 'view':
      return 'eye';
    case 'procedure':
      return 'cog';
    case 'function':
      return 'brackets-curly';
    default:
      return 'file-code-o';
  }
}

/**
 * TabBar component
 * Code Optimization: Wrapped with React.memo to prevent unnecessary re-renders
 */
export const TabBar = React.memo<TabBarProps>(({
  tabs,
  activeTabIndex,
  onTabClick,
  onTabClose,
  onNewTab,
  onTabContextAction,
  onTabReorder,
}) => {
  const styles = useStyles2(getStyles);
  const [draggedIndex, setDraggedIndex] = useState<number | null>(null);
  const [contextMenuTab, setContextMenuTab] = useState<TabState | null>(null);
  const [contextMenuPosition, setContextMenuPosition] = useState<{ x: number; y: number } | null>(null);

  /**
   * Handle tab click
   */
  const handleTabClick = useCallback(
    (tabId: string, event: React.MouseEvent) => {
      // Middle click closes tab
      if (event.button === 1) {
        event.preventDefault();
        onTabClose(tabId);
        return;
      }

      // Left click activates tab
      if (event.button === 0) {
        onTabClick(tabId);
      }
    },
    [onTabClick, onTabClose]
  );

  /**
   * Handle tab close button click
   */
  const handleTabCloseClick = useCallback(
    (tabId: string, event: React.MouseEvent) => {
      event.stopPropagation();
      onTabClose(tabId);
    },
    [onTabClose]
  );

  /**
   * Handle tab context menu
   */
  const handleTabContextMenu = useCallback((tab: TabState, event: React.MouseEvent) => {
    event.preventDefault();
    setContextMenuTab(tab);
    setContextMenuPosition({ x: event.clientX, y: event.clientY });
  }, []);

  /**
   * Handle context menu item click
   */
  const handleContextMenuAction = useCallback(
    (action: string) => {
      if (contextMenuTab) {
        onTabContextAction(contextMenuTab.id, action);
      }
      setContextMenuTab(null);
      setContextMenuPosition(null);
    },
    [contextMenuTab, onTabContextAction]
  );

  /**
   * Handle drag start
   */
  const handleDragStart = useCallback((index: number, event: React.DragEvent) => {
    setDraggedIndex(index);
    event.dataTransfer.effectAllowed = 'move';
  }, []);

  /**
   * Handle drag over
   */
  const handleDragOver = useCallback(
    (index: number, event: React.DragEvent) => {
      event.preventDefault();
      event.dataTransfer.dropEffect = 'move';

      if (draggedIndex !== null && draggedIndex !== index && onTabReorder) {
        onTabReorder(draggedIndex, index);
        setDraggedIndex(index);
      }
    },
    [draggedIndex, onTabReorder]
  );

  /**
   * Handle drag end
   */
  const handleDragEnd = useCallback(() => {
    setDraggedIndex(null);
  }, []);

  return (
    <div className={styles.tabBar}>
      <div className={styles.tabList}>
        {tabs.map((tab, index) => {
          const isActive = index === activeTabIndex;
          const icon = getTabIcon(tab);

          return (
            <div
              key={tab.id}
              className={`${styles.tab} ${isActive ? styles.tabActive : ''} ${draggedIndex === index ? styles.tabDragging : ''}`}
              onClick={(e) => handleTabClick(tab.id, e)}
              onMouseDown={(e) => handleTabClick(tab.id, e)}
              onContextMenu={(e) => handleTabContextMenu(tab, e)}
              draggable
              onDragStart={(e) => handleDragStart(index, e)}
              onDragOver={(e) => handleDragOver(index, e)}
              onDragEnd={handleDragEnd}
            >
              {/* Pin indicator */}
              {tab.isPinned && (
                <Tooltip content="Pinned">
                  <Icon name="gf-pin" size="sm" className={styles.pinIcon} />
                </Tooltip>
              )}

              {/* Tab icon */}
              <Icon name={icon} size="sm" className={styles.tabIcon} />

              {/* Tab title */}
              <span className={styles.tabTitle}>
                {tab.isModified && <span className={styles.modifiedIndicator}>●</span>}
                {tab.title}
              </span>

              {/* Subtitle (server/database for objects) */}
              {tab.type === 'object' && tab.serverName && (
                <Tooltip content={`${tab.serverName} / ${tab.databaseName}`}>
                  <span className={styles.tabSubtitle}>
                    {tab.serverName.split('.')[0]} / {tab.databaseName}
                  </span>
                </Tooltip>
              )}

              {/* Close button */}
              {!tab.isPinned && (
                <button
                  className={styles.closeButton}
                  onClick={(e) => handleTabCloseClick(tab.id, e)}
                  aria-label="Close tab"
                >
                  <Icon name="times" size="sm" />
                </button>
              )}
            </div>
          );
        })}

        {/* New tab button */}
        <button className={styles.newTabButton} onClick={onNewTab} aria-label="New tab">
          <Icon name="plus" size="sm" />
        </button>
      </div>

      {/* Context menu */}
      {contextMenuTab && contextMenuPosition && (
        <ContextMenu
          x={contextMenuPosition.x}
          y={contextMenuPosition.y}
          onClose={() => {
            setContextMenuTab(null);
            setContextMenuPosition(null);
          }}
          renderMenuItems={() => (
            <>
              <MenuItem
                label="Close"
                icon="times"
                onClick={() => handleContextMenuAction('close')}
              />
              <MenuItem
                label="Close Others"
                onClick={() => handleContextMenuAction('closeOthers')}
              />
              <MenuItem
                label="Close All"
                onClick={() => handleContextMenuAction('closeAll')}
              />
              <MenuItem
                label="Close to the Right"
                onClick={() => handleContextMenuAction('closeToRight')}
              />
              <MenuItem
                label={contextMenuTab.isPinned ? 'Unpin Tab' : 'Pin Tab'}
                icon={contextMenuTab.isPinned ? 'gf-pin' : 'gf-pin'}
                onClick={() => handleContextMenuAction('togglePin')}
              />
              {contextMenuTab.type === 'object' && (
                <>
                  <MenuItem label="-" />
                  <MenuItem
                    label="Copy Path"
                    icon="copy"
                    onClick={() => handleContextMenuAction('copyPath')}
                  />
                  <MenuItem
                    label="Reveal in Object Browser"
                    icon="folder-open"
                    onClick={() => handleContextMenuAction('revealInBrowser')}
                  />
                  <MenuItem
                    label="Split Right"
                    icon="columns"
                    onClick={() => handleContextMenuAction('splitRight')}
                  />
                </>
              )}
            </>
          )}
        />
      )}
    </div>
  );
}); // React.memo closing

/**
 * Component styles
 */
const getStyles = (theme: GrafanaTheme2) => ({
  tabBar: css`
    display: flex;
    align-items: center;
    background-color: ${theme.colors.background.secondary};
    border-bottom: 1px solid ${theme.colors.border.weak};
    height: 40px;
    overflow-x: auto;
    overflow-y: hidden;

    /* Hide scrollbar */
    &::-webkit-scrollbar {
      height: 4px;
    }

    &::-webkit-scrollbar-thumb {
      background-color: ${theme.colors.border.medium};
      border-radius: 2px;
    }
  `,

  tabList: css`
    display: flex;
    align-items: center;
    gap: 0;
    flex: 1;
    min-width: 0;
  `,

  tab: css`
    display: flex;
    align-items: center;
    gap: ${theme.spacing(0.5)};
    padding: ${theme.spacing(1, 1.5)};
    background-color: ${theme.colors.background.secondary};
    border-right: 1px solid ${theme.colors.border.weak};
    cursor: pointer;
    user-select: none;
    min-width: 100px;
    max-width: 250px;
    transition: background-color 0.2s;

    &:hover {
      background-color: ${theme.colors.emphasize(theme.colors.background.secondary, 0.03)};
    }
  `,

  tabActive: css`
    background-color: ${theme.colors.background.primary};
    border-bottom: 2px solid ${theme.colors.primary.main};

    &:hover {
      background-color: ${theme.colors.background.primary};
    }
  `,

  tabDragging: css`
    opacity: 0.5;
  `,

  pinIcon: css`
    color: ${theme.colors.warning.main};
    flex-shrink: 0;
  `,

  tabIcon: css`
    color: ${theme.colors.text.secondary};
    flex-shrink: 0;
  `,

  tabTitle: css`
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: ${theme.typography.bodySmall.fontSize};
    color: ${theme.colors.text.primary};
  `,

  modifiedIndicator: css`
    color: ${theme.colors.warning.main};
    margin-right: ${theme.spacing(0.5)};
    font-weight: ${theme.typography.fontWeightBold};
  `,

  tabSubtitle: css`
    flex-shrink: 0;
    font-size: ${theme.typography.bodySmall.fontSize};
    color: ${theme.colors.text.disabled};
    margin-left: ${theme.spacing(0.5)};
  `,

  closeButton: css`
    display: flex;
    align-items: center;
    justify-content: center;
    background: none;
    border: none;
    padding: ${theme.spacing(0.5)};
    cursor: pointer;
    color: ${theme.colors.text.secondary};
    flex-shrink: 0;
    border-radius: ${theme.shape.borderRadius(1)};
    transition: all 0.2s;

    &:hover {
      background-color: ${theme.colors.action.hover};
      color: ${theme.colors.text.primary};
    }
  `,

  newTabButton: css`
    display: flex;
    align-items: center;
    justify-content: center;
    background: none;
    border: none;
    padding: ${theme.spacing(1)};
    cursor: pointer;
    color: ${theme.colors.text.secondary};
    transition: all 0.2s;

    &:hover {
      background-color: ${theme.colors.action.hover};
      color: ${theme.colors.text.primary};
    }
  `,
});
