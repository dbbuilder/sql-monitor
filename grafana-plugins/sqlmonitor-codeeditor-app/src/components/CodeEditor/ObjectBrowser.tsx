/**
 * ObjectBrowser
 *
 * Hierarchical tree view of database objects:
 * - Servers
 *   - Databases
 *     - Tables
 *     - Views
 *     - Stored Procedures
 *     - Functions
 *
 * Features:
 * - Expand/collapse nodes
 * - Context menu (Open, Open in New Tab, Refresh, Copy Name)
 * - Double-click to open object
 * - Drag-and-drop object name into editor
 * - Refresh button to reload metadata
 * - Search/filter objects
 */

import React, { useState, useCallback, useRef, useEffect } from 'react';
import { css } from '@emotion/css';
import { GrafanaTheme2 } from '@grafana/data';
import { useStyles2, Icon, IconButton, Input } from '@grafana/ui';

/**
 * Tree node types
 */
export type NodeType = 'server' | 'database' | 'folder' | 'table' | 'view' | 'procedure' | 'function';

/**
 * Tree node interface
 */
export interface TreeNode {
  id: string;
  type: NodeType;
  label: string;
  serverId?: number;
  serverName?: string;
  databaseName?: string;
  schemaName?: string;
  objectName?: string;
  objectType?: 'table' | 'view' | 'procedure' | 'function';
  children?: TreeNode[];
  isExpanded?: boolean;
  isLoading?: boolean;
}

/**
 * Props interface
 */
interface ObjectBrowserProps {
  onObjectOpen: (node: TreeNode) => void;
  onObjectOpenInNewTab?: (node: TreeNode) => void;
}

/**
 * Context menu state
 */
interface ContextMenuState {
  visible: boolean;
  x: number;
  y: number;
  node: TreeNode | null;
}

/**
 * Cache entry interface
 * Code Optimization: Add caching for object metadata
 */
interface CacheEntry {
  data: TreeNode[];
  timestamp: number;
}

/**
 * Object metadata cache (5 minute TTL)
 * Code Optimization: Prevents repeated API calls for same data
 */
const objectMetadataCache = new Map<string, CacheEntry>();
const CACHE_DURATION_MS = 300000; // 5 minutes

/**
 * Generate cache key for a node
 */
function getCacheKey(node: TreeNode): string {
  if (node.type === 'server') {
    return `server-${node.serverId}`;
  } else if (node.type === 'database') {
    return `database-${node.serverId}-${node.databaseName}`;
  } else if (node.type === 'folder') {
    return `folder-${node.serverId}-${node.databaseName}-${node.label}`;
  }
  return node.id;
}

/**
 * Check if cache entry is still valid
 */
function isCacheValid(entry: CacheEntry): boolean {
  return Date.now() - entry.timestamp < CACHE_DURATION_MS;
}

/**
 * Get cached data if available and valid
 */
function getCachedData(cacheKey: string): TreeNode[] | null {
  const entry = objectMetadataCache.get(cacheKey);
  if (entry && isCacheValid(entry)) {
    console.log(`[ObjectBrowser] Cache hit: ${cacheKey}`);
    return entry.data;
  }
  if (entry) {
    // Cache expired, remove it
    console.log(`[ObjectBrowser] Cache expired: ${cacheKey}`);
    objectMetadataCache.delete(cacheKey);
  }
  return null;
}

/**
 * Set cached data
 */
function setCachedData(cacheKey: string, data: TreeNode[]): void {
  console.log(`[ObjectBrowser] Caching data: ${cacheKey} (${data.length} items)`);
  objectMetadataCache.set(cacheKey, {
    data,
    timestamp: Date.now(),
  });
}

/**
 * Clear all cache
 */
function clearCache(): void {
  console.log(`[ObjectBrowser] Clearing cache (${objectMetadataCache.size} entries)`);
  objectMetadataCache.clear();
}

/**
 * Clear cache for specific node
 */
function clearCacheForNode(node: TreeNode): void {
  const cacheKey = getCacheKey(node);
  console.log(`[ObjectBrowser] Clearing cache for node: ${cacheKey}`);
  objectMetadataCache.delete(cacheKey);
}

/**
 * ObjectBrowser component
 */
export const ObjectBrowser: React.FC<ObjectBrowserProps> = ({ onObjectOpen, onObjectOpenInNewTab }) => {
  const styles = useStyles2(getStyles);
  const [treeData, setTreeData] = useState<TreeNode[]>([]);
  const [searchText, setSearchText] = useState('');
  const [contextMenu, setContextMenu] = useState<ContextMenuState>({ visible: false, x: 0, y: 0, node: null });
  const contextMenuRef = useRef<HTMLDivElement>(null);

  /**
   * Load initial tree data (mock servers for now)
   * TODO: Week 3 - Fetch from SqlMonitorApiClient.getServers()
   */
  useEffect(() => {
    const mockServers: TreeNode[] = [
      {
        id: 'server-1',
        type: 'server',
        label: 'SQL-PROD-01 (localhost)',
        serverId: 1,
        serverName: 'SQL-PROD-01',
        isExpanded: false,
        children: [],
      },
      {
        id: 'server-2',
        type: 'server',
        label: 'SQL-DEV-01 (172.31.208.1)',
        serverId: 2,
        serverName: 'SQL-DEV-01',
        isExpanded: false,
        children: [],
      },
    ];

    setTreeData(mockServers);
  }, []);

  /**
   * Close context menu when clicking outside
   */
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (contextMenuRef.current && !contextMenuRef.current.contains(e.target as Node)) {
        setContextMenu({ visible: false, x: 0, y: 0, node: null });
      }
    };

    if (contextMenu.visible) {
      document.addEventListener('mousedown', handleClickOutside);
      return () => document.removeEventListener('mousedown', handleClickOutside);
    }
  }, [contextMenu.visible]);

  /**
   * Toggle node expansion
   */
  const toggleNode = useCallback((nodeId: string) => {
    setTreeData((prev) => {
      const updateNode = (nodes: TreeNode[]): TreeNode[] => {
        return nodes.map((node) => {
          if (node.id === nodeId) {
            const isExpanding = !node.isExpanded;

            // If expanding and no children, load them
            if (isExpanding && (!node.children || node.children.length === 0)) {
              return { ...node, isExpanded: true, isLoading: true, children: loadChildren(node) };
            }

            return { ...node, isExpanded: isExpanding };
          }

          if (node.children) {
            return { ...node, children: updateNode(node.children) };
          }

          return node;
        });
      };

      return updateNode(prev);
    });
  }, []);

  /**
   * Load children for a node (with caching)
   * Code Optimization: Cache results to prevent repeated API calls
   * TODO: Week 3 - Fetch from SqlMonitorApiClient
   */
  const loadChildren = useCallback((node: TreeNode): TreeNode[] => {
    // Check cache first
    const cacheKey = getCacheKey(node);
    const cachedData = getCachedData(cacheKey);

    if (cachedData) {
      return cachedData;
    }

    // Cache miss - load data
    console.log(`[ObjectBrowser] Cache miss: ${cacheKey}, loading data...`);
    let children: TreeNode[] = [];

    if (node.type === 'server') {
      // Load databases for server
      children = [
        {
          id: `${node.id}-db-1`,
          type: 'database',
          label: 'master',
          serverId: node.serverId,
          serverName: node.serverName,
          databaseName: 'master',
          isExpanded: false,
          children: [],
        },
        {
          id: `${node.id}-db-2`,
          type: 'database',
          label: 'SalesDB',
          serverId: node.serverId,
          serverName: node.serverName,
          databaseName: 'SalesDB',
          isExpanded: false,
          children: [],
        },
        {
          id: `${node.id}-db-3`,
          type: 'database',
          label: 'InventoryDB',
          serverId: node.serverId,
          serverName: node.serverName,
          databaseName: 'InventoryDB',
          isExpanded: false,
          children: [],
        },
      ];
    } else if (node.type === 'database') {
      // Load folders for database
      children = [
        {
          id: `${node.id}-folder-tables`,
          type: 'folder',
          label: 'Tables',
          serverId: node.serverId,
          serverName: node.serverName,
          databaseName: node.databaseName,
          isExpanded: false,
          children: [],
        },
        {
          id: `${node.id}-folder-views`,
          type: 'folder',
          label: 'Views',
          serverId: node.serverId,
          serverName: node.serverName,
          databaseName: node.databaseName,
          isExpanded: false,
          children: [],
        },
        {
          id: `${node.id}-folder-procedures`,
          type: 'folder',
          label: 'Stored Procedures',
          serverId: node.serverId,
          serverName: node.serverName,
          databaseName: node.databaseName,
          isExpanded: false,
          children: [],
        },
        {
          id: `${node.id}-folder-functions`,
          type: 'folder',
          label: 'Functions',
          serverId: node.serverId,
          serverName: node.serverName,
          databaseName: node.databaseName,
          isExpanded: false,
          children: [],
        },
      ];
    } else if (node.type === 'folder') {
      // Load objects for folder
      const folderType = node.label.toLowerCase();

      if (folderType.includes('table')) {
        children = [
          {
            id: `${node.id}-obj-1`,
            type: 'table',
            label: 'dbo.Customers',
            serverId: node.serverId,
            serverName: node.serverName,
            databaseName: node.databaseName,
            schemaName: 'dbo',
            objectName: 'Customers',
            objectType: 'table',
          },
          {
            id: `${node.id}-obj-2`,
            type: 'table',
            label: 'dbo.Orders',
            serverId: node.serverId,
            serverName: node.serverName,
            databaseName: node.databaseName,
            schemaName: 'dbo',
            objectName: 'Orders',
            objectType: 'table',
          },
          {
            id: `${node.id}-obj-3`,
            type: 'table',
            label: 'dbo.Products',
            serverId: node.serverId,
            serverName: node.serverName,
            databaseName: node.databaseName,
            schemaName: 'dbo',
            objectName: 'Products',
            objectType: 'table',
          },
        ];
      } else if (folderType.includes('view')) {
        children = [
          {
            id: `${node.id}-obj-1`,
            type: 'view',
            label: 'dbo.vw_ActiveOrders',
            serverId: node.serverId,
            serverName: node.serverName,
            databaseName: node.databaseName,
            schemaName: 'dbo',
            objectName: 'vw_ActiveOrders',
            objectType: 'view',
          },
        ];
      } else if (folderType.includes('procedure')) {
        children = [
          {
            id: `${node.id}-obj-1`,
            type: 'procedure',
            label: 'dbo.usp_GetCustomers',
            serverId: node.serverId,
            serverName: node.serverName,
            databaseName: node.databaseName,
            schemaName: 'dbo',
            objectName: 'usp_GetCustomers',
            objectType: 'procedure',
          },
          {
            id: `${node.id}-obj-2`,
            type: 'procedure',
            label: 'dbo.usp_GetOrders',
            serverId: node.serverId,
            serverName: node.serverName,
            databaseName: node.databaseName,
            schemaName: 'dbo',
            objectName: 'usp_GetOrders',
            objectType: 'procedure',
          },
        ];
      } else if (folderType.includes('function')) {
        children = [
          {
            id: `${node.id}-obj-1`,
            type: 'function',
            label: 'dbo.fn_CalculateDiscount',
            serverId: node.serverId,
            serverName: node.serverName,
            databaseName: node.databaseName,
            schemaName: 'dbo',
            objectName: 'fn_CalculateDiscount',
            objectType: 'function',
          },
        ];
      }
    }

    // Cache the data before returning
    setCachedData(cacheKey, children);
    return children;
  }, []);

  /**
   * Handle node double-click (open object)
   */
  const handleNodeDoubleClick = useCallback(
    (node: TreeNode) => {
      if (node.type === 'table' || node.type === 'view' || node.type === 'procedure' || node.type === 'function') {
        onObjectOpen(node);
      }
    },
    [onObjectOpen]
  );

  /**
   * Handle node right-click (context menu)
   */
  const handleNodeRightClick = useCallback((e: React.MouseEvent, node: TreeNode) => {
    e.preventDefault();
    setContextMenu({
      visible: true,
      x: e.clientX,
      y: e.clientY,
      node,
    });
  }, []);

  /**
   * Handle context menu action
   */
  const handleContextMenuAction = useCallback(
    (action: string, node: TreeNode | null) => {
      if (!node) return;

      switch (action) {
        case 'open':
          onObjectOpen(node);
          break;
        case 'openInNewTab':
          onObjectOpenInNewTab?.(node);
          break;
        case 'refresh':
          // Clear cache for this node (Code Optimization)
          clearCacheForNode(node);

          // Clear children to force reload
          setTreeData((prev) => {
            const updateNode = (nodes: TreeNode[]): TreeNode[] => {
              return nodes.map((n) => {
                if (n.id === node.id) {
                  return { ...n, children: [], isExpanded: false };
                }
                if (n.children) {
                  return { ...n, children: updateNode(n.children) };
                }
                return n;
              });
            };
            return updateNode(prev);
          });
          break;
        case 'copyName':
          const fullName =
            node.type === 'server'
              ? node.serverName
              : node.type === 'database'
              ? node.databaseName
              : node.schemaName && node.objectName
              ? `${node.schemaName}.${node.objectName}`
              : node.objectName;
          if (fullName) {
            navigator.clipboard.writeText(fullName);
            console.log('[ObjectBrowser] Copied to clipboard:', fullName);
          }
          break;
      }

      setContextMenu({ visible: false, x: 0, y: 0, node: null });
    },
    [onObjectOpen, onObjectOpenInNewTab]
  );

  /**
   * Filter tree by search text
   */
  const filterTree = useCallback(
    (nodes: TreeNode[]): TreeNode[] => {
      if (!searchText.trim()) return nodes;

      const query = searchText.toLowerCase();

      return nodes
        .map((node) => {
          const matches = node.label.toLowerCase().includes(query);
          const filteredChildren = node.children ? filterTree(node.children) : [];

          if (matches || filteredChildren.length > 0) {
            return {
              ...node,
              children: filteredChildren,
              isExpanded: filteredChildren.length > 0, // Auto-expand if has matching children
            };
          }

          return null;
        })
        .filter((node): node is TreeNode => node !== null);
    },
    [searchText]
  );

  const filteredTree = filterTree(treeData);

  return (
    <div className={styles.container}>
      {/* Header */}
      <div className={styles.header}>
        <h3>Object Browser</h3>
        <IconButton
          name="sync"
          tooltip="Refresh"
          onClick={() => {
            console.log('[ObjectBrowser] Refresh clicked');
            // TODO: Reload tree data from API
          }}
        />
      </div>

      {/* Search */}
      <div className={styles.searchContainer}>
        <Input
          prefix={<Icon name="search" />}
          placeholder="Filter objects..."
          value={searchText}
          onChange={(e) => setSearchText(e.currentTarget.value)}
        />
      </div>

      {/* Tree */}
      <div className={styles.tree}>
        {filteredTree.length === 0 ? (
          <div className={styles.emptyState}>
            <Icon name="database" size="xl" />
            <p>No objects found</p>
          </div>
        ) : (
          <TreeView
            nodes={filteredTree}
            onToggle={toggleNode}
            onDoubleClick={handleNodeDoubleClick}
            onRightClick={handleNodeRightClick}
          />
        )}
      </div>

      {/* Context Menu */}
      {contextMenu.visible && contextMenu.node && (
        <div
          ref={contextMenuRef}
          className={styles.contextMenu}
          style={{ left: contextMenu.x, top: contextMenu.y }}
        >
          {(contextMenu.node.type === 'table' ||
            contextMenu.node.type === 'view' ||
            contextMenu.node.type === 'procedure' ||
            contextMenu.node.type === 'function') && (
            <>
              <div className={styles.menuItem} onClick={() => handleContextMenuAction('open', contextMenu.node)}>
                <Icon name="file-alt" />
                <span>Open</span>
              </div>
              <div
                className={styles.menuItem}
                onClick={() => handleContextMenuAction('openInNewTab', contextMenu.node)}
              >
                <Icon name="file-copy-alt" />
                <span>Open in New Tab</span>
              </div>
              <div className={styles.menuDivider} />
            </>
          )}
          <div className={styles.menuItem} onClick={() => handleContextMenuAction('refresh', contextMenu.node)}>
            <Icon name="sync" />
            <span>Refresh</span>
          </div>
          <div className={styles.menuItem} onClick={() => handleContextMenuAction('copyName', contextMenu.node)}>
            <Icon name="copy" />
            <span>Copy Name</span>
          </div>
        </div>
      )}
    </div>
  );
};

/**
 * TreeView recursive component
 */
interface TreeViewProps {
  nodes: TreeNode[];
  level?: number;
  onToggle: (nodeId: string) => void;
  onDoubleClick: (node: TreeNode) => void;
  onRightClick: (e: React.MouseEvent, node: TreeNode) => void;
}

const TreeView: React.FC<TreeViewProps> = ({ nodes, level = 0, onToggle, onDoubleClick, onRightClick }) => {
  const styles = useStyles2(getStyles);

  return (
    <>
      {nodes.map((node) => (
        <div key={node.id}>
          <div
            className={styles.treeNode}
            style={{ paddingLeft: `${level * 20 + 8}px` }}
            onClick={() => onToggle(node.id)}
            onDoubleClick={() => onDoubleClick(node)}
            onContextMenu={(e) => onRightClick(e, node)}
          >
            {/* Expand/collapse icon */}
            {(node.type === 'server' || node.type === 'database' || node.type === 'folder') && (
              <Icon
                name={node.isExpanded ? 'angle-down' : 'angle-right'}
                className={styles.expandIcon}
              />
            )}

            {/* Node icon */}
            <Icon name={getNodeIcon(node.type)} className={styles.nodeIcon} />

            {/* Node label */}
            <span className={styles.nodeLabel}>{node.label}</span>

            {/* Loading indicator */}
            {node.isLoading && <Icon name="fa fa-spinner" className={styles.loadingIcon} />}
          </div>

          {/* Children */}
          {node.isExpanded && node.children && node.children.length > 0 && (
            <TreeView
              nodes={node.children}
              level={level + 1}
              onToggle={onToggle}
              onDoubleClick={onDoubleClick}
              onRightClick={onRightClick}
            />
          )}
        </div>
      ))}
    </>
  );
};

/**
 * Get icon for node type
 */
function getNodeIcon(type: NodeType): string {
  switch (type) {
    case 'server':
      return 'server';
    case 'database':
      return 'database';
    case 'folder':
      return 'folder';
    case 'table':
      return 'table';
    case 'view':
      return 'eye';
    case 'procedure':
      return 'cube';
    case 'function':
      return 'calculator-alt';
    default:
      return 'file-alt';
  }
}

/**
 * Component styles
 */
const getStyles = (theme: GrafanaTheme2) => ({
  container: css`
    display: flex;
    flex-direction: column;
    height: 100%;
    background-color: ${theme.colors.background.secondary};
  `,

  header: css`
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: ${theme.spacing(2)};
    border-bottom: 1px solid ${theme.colors.border.weak};

    h3 {
      margin: 0;
      font-size: ${theme.typography.h5.fontSize};
      font-weight: ${theme.typography.h5.fontWeight};
    }
  `,

  searchContainer: css`
    padding: ${theme.spacing(1, 2)};
    border-bottom: 1px solid ${theme.colors.border.weak};
  `,

  tree: css`
    flex: 1;
    overflow-y: auto;
    padding: ${theme.spacing(1, 0)};
  `,

  emptyState: css`
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    height: 100%;
    color: ${theme.colors.text.secondary};
    text-align: center;

    p {
      margin-top: ${theme.spacing(1)};
    }
  `,

  treeNode: css`
    display: flex;
    align-items: center;
    padding: ${theme.spacing(0.75, 1)};
    cursor: pointer;
    gap: ${theme.spacing(0.5)};
    user-select: none;

    &:hover {
      background-color: ${theme.colors.emphasize(theme.colors.background.secondary, 0.03)};
    }
  `,

  expandIcon: css`
    color: ${theme.colors.text.secondary};
    flex-shrink: 0;
  `,

  nodeIcon: css`
    color: ${theme.colors.text.secondary};
    flex-shrink: 0;
  `,

  nodeLabel: css`
    flex: 1;
    font-size: ${theme.typography.body.fontSize};
    color: ${theme.colors.text.primary};
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  `,

  loadingIcon: css`
    color: ${theme.colors.text.disabled};
    animation: spin 1s linear infinite;

    @keyframes spin {
      from {
        transform: rotate(0deg);
      }
      to {
        transform: rotate(360deg);
      }
    }
  `,

  contextMenu: css`
    position: fixed;
    background-color: ${theme.colors.background.primary};
    border: 1px solid ${theme.colors.border.medium};
    border-radius: ${theme.shape.borderRadius()};
    box-shadow: ${theme.shadows.z3};
    padding: ${theme.spacing(0.5)};
    min-width: 200px;
    z-index: 10000;
  `,

  menuItem: css`
    display: flex;
    align-items: center;
    gap: ${theme.spacing(1)};
    padding: ${theme.spacing(1, 1.5)};
    cursor: pointer;
    border-radius: ${theme.shape.borderRadius()};
    font-size: ${theme.typography.body.fontSize};
    color: ${theme.colors.text.primary};

    &:hover {
      background-color: ${theme.colors.action.hover};
    }
  `,

  menuDivider: css`
    height: 1px;
    background-color: ${theme.colors.border.weak};
    margin: ${theme.spacing(0.5, 0)};
  `,
});
