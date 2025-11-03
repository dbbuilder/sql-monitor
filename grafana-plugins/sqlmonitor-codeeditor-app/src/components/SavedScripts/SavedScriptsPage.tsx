/**
 * SavedScriptsPage
 *
 * Manage saved SQL scripts:
 * - List all saved scripts with search/filter
 * - Sort by name, modified date, server
 * - Open script in Code Editor
 * - Delete scripts
 * - Rename scripts
 * - Export scripts
 * - Import scripts
 *
 * Week 4 Day 16 implementation
 */

import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { css } from '@emotion/css';
import { GrafanaTheme2 } from '@grafana/data';
import { useStyles2, Button, Input, Icon, ConfirmModal, IconButton, Tooltip } from '@grafana/ui';
import { useNavigate } from 'react-router-dom';
import { AutoSaveService } from '../../services/autoSaveService';
import type { SavedScript } from '../../types/savedScript';

/**
 * Sort options
 */
type SortField = 'name' | 'lastModified' | 'serverId' | 'databaseName';
type SortDirection = 'asc' | 'desc';

/**
 * SavedScriptsPage component
 */
export const SavedScriptsPage: React.FC = () => {
  const styles = useStyles2(getStyles);
  const navigate = useNavigate();

  // State
  const [scripts, setScripts] = useState<SavedScript[]>([]);
  const [searchText, setSearchText] = useState('');
  const [sortField, setSortField] = useState<SortField>('lastModified');
  const [sortDirection, setSortDirection] = useState<SortDirection>('desc');
  const [selectedScripts, setSelectedScripts] = useState<Set<string>>(new Set());
  const [deleteModalOpen, setDeleteModalOpen] = useState(false);
  const [scriptToDelete, setScriptToDelete] = useState<SavedScript | null>(null);
  const [renameModalOpen, setRenameModalOpen] = useState(false);
  const [scriptToRename, setScriptToRename] = useState<SavedScript | null>(null);
  const [newScriptName, setNewScriptName] = useState('');

  /**
   * Load scripts on mount
   */
  useEffect(() => {
    loadScripts();
  }, []);

  /**
   * Load scripts from AutoSaveService
   */
  const loadScripts = useCallback(() => {
    const allScripts = AutoSaveService.getAllScripts();
    // Filter out auto-saved scripts (only show manually saved)
    const savedScripts = allScripts.filter((s) => !s.autoSaved);
    setScripts(savedScripts);
    console.log('[SavedScripts] Loaded scripts:', savedScripts.length);
  }, []);

  /**
   * Filter and sort scripts
   */
  const filteredScripts = useMemo(() => {
    let filtered = scripts;

    // Apply search filter
    if (searchText.trim()) {
      const query = searchText.toLowerCase();
      filtered = filtered.filter(
        (script) =>
          script.name.toLowerCase().includes(query) ||
          script.content.toLowerCase().includes(query) ||
          script.databaseName?.toLowerCase().includes(query)
      );
    }

    // Apply sorting
    filtered = [...filtered].sort((a, b) => {
      let comparison = 0;

      switch (sortField) {
        case 'name':
          comparison = a.name.localeCompare(b.name);
          break;
        case 'lastModified':
          comparison = new Date(a.lastModified).getTime() - new Date(b.lastModified).getTime();
          break;
        case 'serverId':
          comparison = (a.serverId || 0) - (b.serverId || 0);
          break;
        case 'databaseName':
          comparison = (a.databaseName || '').localeCompare(b.databaseName || '');
          break;
      }

      return sortDirection === 'asc' ? comparison : -comparison;
    });

    return filtered;
  }, [scripts, searchText, sortField, sortDirection]);

  /**
   * Handle sort column click
   */
  const handleSort = useCallback(
    (field: SortField) => {
      if (sortField === field) {
        // Toggle direction if clicking same field
        setSortDirection((prev) => (prev === 'asc' ? 'desc' : 'asc'));
      } else {
        // Set new field with default direction
        setSortField(field);
        setSortDirection(field === 'lastModified' ? 'desc' : 'asc');
      }
    },
    [sortField]
  );

  /**
   * Handle script open
   */
  const handleOpenScript = useCallback(
    (script: SavedScript) => {
      // Navigate to editor with script parameter
      navigate(`/a/sqlmonitor-codeeditor-app/editor?script=${script.id}`);
    },
    [navigate]
  );

  /**
   * Handle script delete
   */
  const handleDeleteScript = useCallback((script: SavedScript) => {
    setScriptToDelete(script);
    setDeleteModalOpen(true);
  }, []);

  /**
   * Confirm delete
   */
  const confirmDelete = useCallback(() => {
    if (scriptToDelete) {
      AutoSaveService.deleteScript(scriptToDelete.id);
      loadScripts();
      setDeleteModalOpen(false);
      setScriptToDelete(null);
      console.log('[SavedScripts] Deleted script:', scriptToDelete.name);
    }
  }, [scriptToDelete, loadScripts]);

  /**
   * Handle script rename
   */
  const handleRenameScript = useCallback((script: SavedScript) => {
    setScriptToRename(script);
    setNewScriptName(script.name);
    setRenameModalOpen(true);
  }, []);

  /**
   * Confirm rename
   */
  const confirmRename = useCallback(() => {
    if (scriptToRename && newScriptName.trim()) {
      const updatedScript: SavedScript = {
        ...scriptToRename,
        name: newScriptName.trim(),
        lastModified: new Date().toISOString(),
      };

      AutoSaveService.manualSave(updatedScript);
      loadScripts();
      setRenameModalOpen(false);
      setScriptToRename(null);
      setNewScriptName('');
      console.log('[SavedScripts] Renamed script:', scriptToRename.name, '→', newScriptName);
    }
  }, [scriptToRename, newScriptName, loadScripts]);

  /**
   * Handle export script
   */
  const handleExportScript = useCallback((script: SavedScript) => {
    const exportData = {
      name: script.name,
      content: script.content,
      serverId: script.serverId,
      databaseName: script.databaseName,
      exportedAt: new Date().toISOString(),
    };

    const blob = new Blob([JSON.stringify(exportData, null, 2)], { type: 'application/json' });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = `${script.name.replace(/[^a-z0-9]/gi, '_')}.json`;
    link.click();

    console.log('[SavedScripts] Exported script:', script.name);
  }, []);

  /**
   * Handle export all scripts
   */
  const handleExportAll = useCallback(() => {
    const exportData = {
      scripts: scripts.map((s) => ({
        name: s.name,
        content: s.content,
        serverId: s.serverId,
        databaseName: s.databaseName,
      })),
      exportedAt: new Date().toISOString(),
      count: scripts.length,
    };

    const blob = new Blob([JSON.stringify(exportData, null, 2)], { type: 'application/json' });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = `sql_scripts_${Date.now()}.json`;
    link.click();

    console.log('[SavedScripts] Exported all scripts:', scripts.length);
  }, [scripts]);

  /**
   * Handle import scripts
   */
  const handleImportScripts = useCallback(() => {
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

          // Handle single script export
          if (data.name && data.content) {
            const script: SavedScript = {
              id: AutoSaveService.generateScriptId(),
              name: data.name,
              content: data.content,
              serverId: data.serverId,
              databaseName: data.databaseName,
              autoSaved: false,
              lastModified: new Date().toISOString(),
            };

            AutoSaveService.manualSave(script);
            loadScripts();
            alert(`Imported script: ${script.name}`);
          }
          // Handle batch export
          else if (data.scripts && Array.isArray(data.scripts)) {
            let importedCount = 0;

            data.scripts.forEach((s: any) => {
              if (s.name && s.content) {
                const script: SavedScript = {
                  id: AutoSaveService.generateScriptId(),
                  name: s.name,
                  content: s.content,
                  serverId: s.serverId,
                  databaseName: s.databaseName,
                  autoSaved: false,
                  lastModified: new Date().toISOString(),
                };

                AutoSaveService.manualSave(script);
                importedCount++;
              }
            });

            loadScripts();
            alert(`Imported ${importedCount} scripts`);
          } else {
            alert('Invalid import file format');
          }

          console.log('[SavedScripts] Import completed');
        } catch (error) {
          console.error('[SavedScripts] Import failed:', error);
          alert(`Import failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
        }
      };

      reader.readAsText(file);
    };

    input.click();
  }, [loadScripts]);

  /**
   * Handle new script
   */
  const handleNewScript = useCallback(() => {
    navigate('/a/sqlmonitor-codeeditor-app/editor');
  }, [navigate]);

  return (
    <div className={styles.container}>
      {/* Header */}
      <div className={styles.header}>
        <div className={styles.headerLeft}>
          <h1>Saved Scripts</h1>
          <span className={styles.scriptCount}>
            {filteredScripts.length} {filteredScripts.length === 1 ? 'script' : 'scripts'}
          </span>
        </div>
        <div className={styles.headerRight}>
          <Button icon="plus" variant="primary" onClick={handleNewScript}>
            New Script
          </Button>
          <Button icon="import" variant="secondary" onClick={handleImportScripts}>
            Import
          </Button>
          <Button icon="download-alt" variant="secondary" onClick={handleExportAll} disabled={scripts.length === 0}>
            Export All
          </Button>
        </div>
      </div>

      {/* Toolbar */}
      <div className={styles.toolbar}>
        <Input
          prefix={<Icon name="search" />}
          placeholder="Search scripts..."
          value={searchText}
          onChange={(e) => setSearchText(e.currentTarget.value)}
          width={40}
        />
      </div>

      {/* Scripts Table */}
      <div className={styles.tableContainer}>
        {filteredScripts.length === 0 ? (
          <div className={styles.emptyState}>
            <Icon name="file-alt" size="xxxl" />
            <h2>No saved scripts</h2>
            {searchText ? (
              <p>No scripts match your search criteria</p>
            ) : (
              <>
                <p>Create your first script to get started</p>
                <Button icon="plus" variant="primary" onClick={handleNewScript}>
                  New Script
                </Button>
              </>
            )}
          </div>
        ) : (
          <table className={styles.table}>
            <thead>
              <tr>
                <th onClick={() => handleSort('name')} className={styles.sortableHeader}>
                  <div className={styles.headerContent}>
                    <span>Name</span>
                    {sortField === 'name' && <Icon name={sortDirection === 'asc' ? 'arrow-up' : 'arrow-down'} />}
                  </div>
                </th>
                <th onClick={() => handleSort('databaseName')} className={styles.sortableHeader}>
                  <div className={styles.headerContent}>
                    <span>Server / Database</span>
                    {sortField === 'databaseName' && <Icon name={sortDirection === 'asc' ? 'arrow-up' : 'arrow-down'} />}
                  </div>
                </th>
                <th onClick={() => handleSort('lastModified')} className={styles.sortableHeader}>
                  <div className={styles.headerContent}>
                    <span>Last Modified</span>
                    {sortField === 'lastModified' && (
                      <Icon name={sortDirection === 'asc' ? 'arrow-up' : 'arrow-down'} />
                    )}
                  </div>
                </th>
                <th className={styles.actionsHeader}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {filteredScripts.map((script) => (
                <tr key={script.id} className={styles.tableRow}>
                  <td className={styles.nameCell}>
                    <div className={styles.scriptName} onClick={() => handleOpenScript(script)}>
                      <Icon name="file-alt" />
                      <span>{script.name}</span>
                    </div>
                  </td>
                  <td className={styles.serverCell}>
                    {script.serverId && script.databaseName ? (
                      <div className={styles.serverInfo}>
                        <Icon name="server" />
                        <span>
                          Server{script.serverId} / {script.databaseName}
                        </span>
                      </div>
                    ) : (
                      <span className={styles.noServer}>—</span>
                    )}
                  </td>
                  <td className={styles.dateCell}>{new Date(script.lastModified).toLocaleString()}</td>
                  <td className={styles.actionsCell}>
                    <Tooltip content="Open script">
                      <IconButton name="folder-open" onClick={() => handleOpenScript(script)} />
                    </Tooltip>
                    <Tooltip content="Rename">
                      <IconButton name="edit" onClick={() => handleRenameScript(script)} />
                    </Tooltip>
                    <Tooltip content="Export">
                      <IconButton name="download-alt" onClick={() => handleExportScript(script)} />
                    </Tooltip>
                    <Tooltip content="Delete">
                      <IconButton name="trash-alt" onClick={() => handleDeleteScript(script)} />
                    </Tooltip>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* Delete Confirmation Modal */}
      <ConfirmModal
        isOpen={deleteModalOpen}
        title="Delete Script"
        body={
          scriptToDelete ? (
            <>
              <p>Are you sure you want to delete "{scriptToDelete.name}"?</p>
              <p>This action cannot be undone.</p>
            </>
          ) : null
        }
        confirmText="Delete"
        onConfirm={confirmDelete}
        onDismiss={() => {
          setDeleteModalOpen(false);
          setScriptToDelete(null);
        }}
      />

      {/* Rename Modal */}
      {renameModalOpen && (
        <div className={styles.modalBackdrop} onClick={() => setRenameModalOpen(false)}>
          <div className={styles.modal} onClick={(e) => e.stopPropagation()}>
            <div className={styles.modalHeader}>
              <h3>Rename Script</h3>
              <IconButton name="times" onClick={() => setRenameModalOpen(false)} />
            </div>
            <div className={styles.modalBody}>
              <Input
                label="Script Name"
                value={newScriptName}
                onChange={(e) => setNewScriptName(e.currentTarget.value)}
                autoFocus
                onKeyDown={(e) => {
                  if (e.key === 'Enter') {
                    confirmRename();
                  }
                }}
              />
            </div>
            <div className={styles.modalFooter}>
              <Button variant="secondary" onClick={() => setRenameModalOpen(false)}>
                Cancel
              </Button>
              <Button variant="primary" onClick={confirmRename} disabled={!newScriptName.trim()}>
                Rename
              </Button>
            </div>
          </div>
        </div>
      )}
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
    align-items: center;
    margin-bottom: ${theme.spacing(3)};
  `,

  headerLeft: css`
    display: flex;
    align-items: baseline;
    gap: ${theme.spacing(2)};

    h1 {
      margin: 0;
      font-size: ${theme.typography.h2.fontSize};
      font-weight: ${theme.typography.h2.fontWeight};
    }
  `,

  scriptCount: css`
    font-size: ${theme.typography.body.fontSize};
    color: ${theme.colors.text.secondary};
  `,

  headerRight: css`
    display: flex;
    gap: ${theme.spacing(1)};
  `,

  toolbar: css`
    display: flex;
    gap: ${theme.spacing(2)};
    margin-bottom: ${theme.spacing(2)};
  `,

  tableContainer: css`
    flex: 1;
    overflow: auto;
    background-color: ${theme.colors.background.secondary};
    border: 1px solid ${theme.colors.border.weak};
    border-radius: ${theme.shape.borderRadius()};
  `,

  table: css`
    width: 100%;
    border-collapse: collapse;

    th,
    td {
      padding: ${theme.spacing(1.5, 2)};
      text-align: left;
      border-bottom: 1px solid ${theme.colors.border.weak};
    }

    thead th {
      background-color: ${theme.colors.background.canvas};
      font-weight: ${theme.typography.fontWeightMedium};
      color: ${theme.colors.text.secondary};
      position: sticky;
      top: 0;
      z-index: 1;
    }

    tbody tr:hover {
      background-color: ${theme.colors.emphasize(theme.colors.background.secondary, 0.03)};
    }
  `,

  sortableHeader: css`
    cursor: pointer;
    user-select: none;

    &:hover {
      background-color: ${theme.colors.emphasize(theme.colors.background.canvas, 0.03)} !important;
    }
  `,

  headerContent: css`
    display: flex;
    align-items: center;
    gap: ${theme.spacing(0.5)};
  `,

  actionsHeader: css`
    width: 160px;
  `,

  tableRow: css`
    cursor: pointer;
  `,

  nameCell: css`
    font-weight: ${theme.typography.fontWeightMedium};
  `,

  scriptName: css`
    display: flex;
    align-items: center;
    gap: ${theme.spacing(1)};
    color: ${theme.colors.text.link};

    &:hover {
      text-decoration: underline;
    }
  `,

  serverCell: css`
    color: ${theme.colors.text.secondary};
  `,

  serverInfo: css`
    display: flex;
    align-items: center;
    gap: ${theme.spacing(0.5)};
  `,

  noServer: css`
    color: ${theme.colors.text.disabled};
  `,

  dateCell: css`
    color: ${theme.colors.text.secondary};
    font-size: ${theme.typography.bodySmall.fontSize};
  `,

  actionsCell: css`
    display: flex;
    gap: ${theme.spacing(0.5)};
  `,

  emptyState: css`
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: ${theme.spacing(8)};
    color: ${theme.colors.text.secondary};
    text-align: center;

    h2 {
      margin-top: ${theme.spacing(2)};
      font-size: ${theme.typography.h3.fontSize};
    }

    p {
      margin: ${theme.spacing(1, 0, 2)};
      color: ${theme.colors.text.disabled};
    }
  `,

  modalBackdrop: css`
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background-color: rgba(0, 0, 0, 0.5);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 9999;
  `,

  modal: css`
    background-color: ${theme.colors.background.primary};
    border: 1px solid ${theme.colors.border.medium};
    border-radius: ${theme.shape.borderRadius(2)};
    width: 500px;
    max-width: 90%;
    box-shadow: ${theme.shadows.z3};
  `,

  modalHeader: css`
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: ${theme.spacing(2, 3)};
    border-bottom: 1px solid ${theme.colors.border.weak};

    h3 {
      margin: 0;
      font-size: ${theme.typography.h4.fontSize};
    }
  `,

  modalBody: css`
    padding: ${theme.spacing(3)};
  `,

  modalFooter: css`
    display: flex;
    justify-content: flex-end;
    gap: ${theme.spacing(1)};
    padding: ${theme.spacing(2, 3)};
    border-top: 1px solid ${theme.colors.border.weak};
  `,
});
