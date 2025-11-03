/**
 * ResultsGrid
 *
 * Display query results using ag-Grid:
 * - Multiple result sets (tabbed interface)
 * - Column resizing, sorting, filtering
 * - Export to CSV, JSON, Excel
 * - Row count and execution time display
 * - Error messages display
 * - Messages panel (PRINT statements, row counts)
 *
 * Week 3 Day 11 implementation
 */

import React, { useState, useMemo, useCallback } from 'react';
import { css } from '@emotion/css';
import { GrafanaTheme2 } from '@grafana/data';
import { useStyles2, Button, Icon, TabsBar, Tab, TabContent } from '@grafana/ui';
import { AgGridReact } from 'ag-grid-react';
import type { ColDef } from 'ag-grid-community';
import 'ag-grid-community/styles/ag-grid.css';
import 'ag-grid-community/styles/ag-theme-alpine.css';
import type { QueryExecutionResult, ResultSet } from '../../types/query';

/**
 * Props interface
 */
interface ResultsGridProps {
  result: QueryExecutionResult | null;
  onExport?: (format: 'csv' | 'json' | 'excel') => void;
}

/**
 * ResultsGrid component
 */
export const ResultsGrid: React.FC<ResultsGridProps> = ({ result, onExport }) => {
  const styles = useStyles2(getStyles);
  const [activeTab, setActiveTab] = useState<'results' | 'messages' | number>('results');

  /**
   * Generate ag-Grid column definitions from result set
   */
  const getColumnDefs = useCallback((resultSet: ResultSet): ColDef[] => {
    return resultSet.columns.map((col) => ({
      field: col.name,
      headerName: col.name,
      sortable: true,
      filter: true,
      resizable: true,
      minWidth: 100,
      flex: 1,
      // Format based on data type
      valueFormatter: (params: any) => {
        if (params.value === null || params.value === undefined) {
          return 'NULL';
        }

        // Format dates
        if (col.dataType.toLowerCase().includes('date') || col.dataType.toLowerCase().includes('time')) {
          if (params.value instanceof Date) {
            return params.value.toISOString();
          }
          return String(params.value);
        }

        // Format numbers
        if (col.dataType.toLowerCase().includes('int') || col.dataType.toLowerCase().includes('decimal') || col.dataType.toLowerCase().includes('float')) {
          if (typeof params.value === 'number') {
            return params.value.toLocaleString();
          }
        }

        return String(params.value);
      },
    }));
  }, []);

  /**
   * Export data to CSV
   */
  const exportToCsv = useCallback((resultSet: ResultSet) => {
    const headers = resultSet.columns.map((col) => col.name);
    const rows = resultSet.rows.map((row) =>
      resultSet.columns.map((col) => {
        const value = row[col.name];
        if (value === null || value === undefined) return 'NULL';
        if (typeof value === 'string' && value.includes(',')) return `"${value}"`;
        return String(value);
      })
    );

    const csvContent = [headers.join(','), ...rows.map((r) => r.join(','))].join('\n');

    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = `query_results_${Date.now()}.csv`;
    link.click();

    console.log('[ResultsGrid] Exported to CSV');
  }, []);

  /**
   * Export data to JSON
   */
  const exportToJson = useCallback((resultSet: ResultSet) => {
    const jsonContent = JSON.stringify(resultSet.rows, null, 2);

    const blob = new Blob([jsonContent], { type: 'application/json;charset=utf-8;' });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = `query_results_${Date.now()}.json`;
    link.click();

    console.log('[ResultsGrid] Exported to JSON');
  }, []);

  /**
   * Copy to clipboard
   */
  const copyToClipboard = useCallback((resultSet: ResultSet) => {
    const headers = resultSet.columns.map((col) => col.name);
    const rows = resultSet.rows.map((row) =>
      resultSet.columns.map((col) => {
        const value = row[col.name];
        return value === null || value === undefined ? 'NULL' : String(value);
      })
    );

    const textContent = [headers.join('\t'), ...rows.map((r) => r.join('\t'))].join('\n');

    navigator.clipboard.writeText(textContent);
    console.log('[ResultsGrid] Copied to clipboard');
  }, []);

  /**
   * Render empty state
   */
  if (!result) {
    return (
      <div className={styles.container}>
        <div className={styles.emptyState}>
          <Icon name="table" size="xl" />
          <p>No query results</p>
          <p className={styles.hint}>Run a query to see results here</p>
        </div>
      </div>
    );
  }

  /**
   * Render error state
   */
  if (!result.success && result.errors && result.errors.length > 0) {
    return (
      <div className={styles.container}>
        <div className={styles.errorContainer}>
          <div className={styles.errorHeader}>
            <Icon name="exclamation-triangle" className={styles.errorIcon} />
            <h3>Query Execution Failed</h3>
          </div>
          <div className={styles.errorList}>
            {result.errors.map((error, index) => (
              <div key={index} className={styles.errorItem}>
                <div className={styles.errorMessage}>{error.message}</div>
                {error.lineNumber && (
                  <div className={styles.errorLocation}>
                    Line {error.lineNumber} • Severity: {error.severity}
                  </div>
                )}
              </div>
            ))}
          </div>
          <div className={styles.executionInfo}>
            <span>Execution Time: {result.executionTimeMs}ms</span>
            <span>Server: {result.serverName}</span>
            <span>Database: {result.databaseName}</span>
          </div>
        </div>
      </div>
    );
  }

  /**
   * Render success state with results
   */
  const hasResults = result.resultSets && result.resultSets.length > 0;
  const hasMessages = result.messages && result.messages.length > 0;

  return (
    <div className={styles.container}>
      {/* Header with tabs and actions */}
      <div className={styles.header}>
        <TabsBar>
          {hasResults && (
            <>
              {result.resultSets!.length === 1 ? (
                <Tab
                  label={`Results (${result.resultSets![0].rowCount} rows)`}
                  active={activeTab === 'results'}
                  onChangeTab={() => setActiveTab('results')}
                />
              ) : (
                result.resultSets!.map((rs, index) => (
                  <Tab
                    key={index}
                    label={`Result Set ${index + 1} (${rs.rowCount} rows)`}
                    active={activeTab === index}
                    onChangeTab={() => setActiveTab(index)}
                  />
                ))
              )}
            </>
          )}
          {hasMessages && (
            <Tab
              label={`Messages (${result.messages!.length})`}
              active={activeTab === 'messages'}
              onChangeTab={() => setActiveTab('messages')}
            />
          )}
        </TabsBar>

        <div className={styles.actions}>
          {hasResults && activeTab !== 'messages' && (
            <>
              <Button
                icon="copy"
                variant="secondary"
                size="sm"
                onClick={() => {
                  const resultSet = typeof activeTab === 'number' ? result.resultSets![activeTab] : result.resultSets![0];
                  copyToClipboard(resultSet);
                }}
                tooltip="Copy to clipboard"
              >
                Copy
              </Button>
              <Button
                icon="download-alt"
                variant="secondary"
                size="sm"
                onClick={() => {
                  const resultSet = typeof activeTab === 'number' ? result.resultSets![activeTab] : result.resultSets![0];
                  exportToCsv(resultSet);
                }}
                tooltip="Export to CSV"
              >
                CSV
              </Button>
              <Button
                icon="file-alt"
                variant="secondary"
                size="sm"
                onClick={() => {
                  const resultSet = typeof activeTab === 'number' ? result.resultSets![activeTab] : result.resultSets![0];
                  exportToJson(resultSet);
                }}
                tooltip="Export to JSON"
              >
                JSON
              </Button>
            </>
          )}
        </div>
      </div>

      {/* Content area */}
      <div className={styles.content}>
        {/* Results tab */}
        {hasResults && activeTab !== 'messages' && (
          <TabContent>
            {(() => {
              const resultSet = typeof activeTab === 'number' ? result.resultSets![activeTab] : result.resultSets![0];
              const columnDefs = getColumnDefs(resultSet);

              return (
                <div className="ag-theme-alpine" style={{ height: '100%', width: '100%' }}>
                  <AgGridReact
                    rowData={resultSet.rows}
                    columnDefs={columnDefs}
                    defaultColDef={{
                      sortable: true,
                      filter: true,
                      resizable: true,
                    }}
                    pagination={true}
                    paginationPageSize={50}
                    paginationPageSizeSelector={[10, 25, 50, 100, 500]}
                    domLayout="normal"
                    animateRows={true}
                    enableCellTextSelection={true}
                    ensureDomOrder={true}
                  />
                </div>
              );
            })()}
          </TabContent>
        )}

        {/* Messages tab */}
        {hasMessages && activeTab === 'messages' && (
          <TabContent>
            <div className={styles.messagesPanel}>
              {result.messages!.map((message, index) => (
                <div key={index} className={styles.messageItem}>
                  <Icon name="info-circle" className={styles.messageIcon} />
                  <span>{message}</span>
                </div>
              ))}
            </div>
          </TabContent>
        )}

        {/* No results */}
        {!hasResults && !hasMessages && (
          <div className={styles.emptyState}>
            <Icon name="check-circle" size="xl" />
            <p>Query executed successfully</p>
            <p className={styles.hint}>No rows returned</p>
          </div>
        )}
      </div>

      {/* Footer with execution info */}
      <div className={styles.footer}>
        <span className={styles.footerItem}>
          <Icon name="clock-nine" />
          Execution Time: {result.executionTimeMs}ms
        </span>
        {result.rowsAffected > 0 && (
          <span className={styles.footerItem}>
            <Icon name="database" />
            Rows Affected: {result.rowsAffected}
          </span>
        )}
        {hasResults && (
          <span className={styles.footerItem}>
            <Icon name="table" />
            Total Rows: {result.resultSets!.reduce((sum, rs) => sum + rs.rowCount, 0)}
          </span>
        )}
        <span className={styles.footerItem}>
          <Icon name="server" />
          {result.serverName} / {result.databaseName}
        </span>
        <span className={styles.footerItem}>
          <Icon name="calendar" />
          {new Date(result.executedAt).toLocaleString()}
        </span>
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
    background-color: ${theme.colors.background.primary};
  `,

  header: css`
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: ${theme.spacing(1, 2)};
    border-bottom: 1px solid ${theme.colors.border.weak};
    background-color: ${theme.colors.background.secondary};
  `,

  actions: css`
    display: flex;
    gap: ${theme.spacing(1)};
  `,

  content: css`
    flex: 1;
    overflow: hidden;
    position: relative;
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
      margin: ${theme.spacing(1, 0)};
    }
  `,

  hint: css`
    font-size: ${theme.typography.bodySmall.fontSize};
    color: ${theme.colors.text.disabled};
  `,

  errorContainer: css`
    padding: ${theme.spacing(3)};
    height: 100%;
    overflow-y: auto;
  `,

  errorHeader: css`
    display: flex;
    align-items: center;
    gap: ${theme.spacing(1)};
    margin-bottom: ${theme.spacing(2)};
    color: ${theme.colors.error.text};

    h3 {
      margin: 0;
      font-size: ${theme.typography.h4.fontSize};
    }
  `,

  errorIcon: css`
    color: ${theme.colors.error.text};
    font-size: ${theme.typography.h4.fontSize};
  `,

  errorList: css`
    display: flex;
    flex-direction: column;
    gap: ${theme.spacing(1)};
    margin-bottom: ${theme.spacing(2)};
  `,

  errorItem: css`
    padding: ${theme.spacing(2)};
    background-color: ${theme.colors.error.transparent};
    border-left: 3px solid ${theme.colors.error.border};
    border-radius: ${theme.shape.borderRadius()};
  `,

  errorMessage: css`
    font-size: ${theme.typography.body.fontSize};
    color: ${theme.colors.error.text};
    margin-bottom: ${theme.spacing(0.5)};
    font-family: ${theme.typography.fontFamilyMonospace};
  `,

  errorLocation: css`
    font-size: ${theme.typography.bodySmall.fontSize};
    color: ${theme.colors.error.text};
    opacity: 0.8;
  `,

  messagesPanel: css`
    padding: ${theme.spacing(2)};
    height: 100%;
    overflow-y: auto;
  `,

  messageItem: css`
    display: flex;
    align-items: flex-start;
    gap: ${theme.spacing(1)};
    padding: ${theme.spacing(1, 0)};
    font-family: ${theme.typography.fontFamilyMonospace};
    font-size: ${theme.typography.bodySmall.fontSize};
    color: ${theme.colors.text.primary};
  `,

  messageIcon: css`
    color: ${theme.colors.info.text};
    margin-top: ${theme.spacing(0.25)};
  `,

  executionInfo: css`
    display: flex;
    gap: ${theme.spacing(2)};
    padding: ${theme.spacing(2)};
    background-color: ${theme.colors.background.secondary};
    border-radius: ${theme.shape.borderRadius()};
    font-size: ${theme.typography.bodySmall.fontSize};
    color: ${theme.colors.text.secondary};
  `,

  footer: css`
    display: flex;
    gap: ${theme.spacing(2)};
    padding: ${theme.spacing(1, 2)};
    border-top: 1px solid ${theme.colors.border.weak};
    background-color: ${theme.colors.background.secondary};
    font-size: ${theme.typography.bodySmall.fontSize};
    color: ${theme.colors.text.secondary};
  `,

  footerItem: css`
    display: flex;
    align-items: center;
    gap: ${theme.spacing(0.5)};
  `,
});
