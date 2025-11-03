/**
 * App
 *
 * Main application component with React Router.
 * Handles routing between different pages of the plugin.
 *
 * Week 4 Day 17: Added SavedScripts and Configuration pages with NavigationBar
 */

import React from 'react';
import { css } from '@emotion/css';
import { Routes, Route, Navigate } from 'react-router-dom';
import { useStyles2 } from '@grafana/ui';
import { GrafanaTheme2 } from '@grafana/data';
import { CodeEditorPage } from '../CodeEditor/CodeEditorPage';
import { SavedScriptsPage } from '../SavedScripts/SavedScriptsPage';
import { ConfigurationPage } from '../Configuration/ConfigurationPage';
import { NavigationBar } from '../Navigation/NavigationBar';

/**
 * App component
 */
export const App: React.FC = () => {
  const styles = useStyles2(getStyles);

  return (
    <div className={styles.container}>
      <NavigationBar />
      <div className={styles.content}>
        <Routes>
          {/* Default route - redirect to editor */}
          <Route path="/" element={<Navigate to="/editor" replace />} />

          {/* Code Editor page */}
          <Route path="/editor" element={<CodeEditorPage />} />

          {/* Saved Scripts page (Week 4 Day 16) */}
          <Route path="/scripts" element={<SavedScriptsPage />} />

          {/* Configuration page (Week 4 Day 17) */}
          <Route path="/config" element={<ConfigurationPage />} />

          {/* 404 - redirect to editor */}
          <Route path="*" element={<Navigate to="/editor" replace />} />
        </Routes>
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
    height: 100vh;
    width: 100%;
    background-color: ${theme.colors.background.primary};
  `,

  content: css`
    flex: 1;
    overflow: hidden;
    position: relative;
  `,
});
