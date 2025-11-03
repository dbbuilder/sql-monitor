/**
 * NavigationBar
 *
 * Main navigation bar for the SQL Monitor Code Editor plugin.
 * Provides navigation between Code Editor, Saved Scripts, and Configuration pages.
 *
 * Week 4 Day 17 implementation
 */

import React from 'react';
import { css } from '@emotion/css';
import { GrafanaTheme2 } from '@grafana/data';
import { useStyles2, TabsBar, Tab, Icon } from '@grafana/ui';
import { useNavigate, useLocation } from 'react-router-dom';

/**
 * NavigationBar component
 */
export const NavigationBar: React.FC = () => {
  const styles = useStyles2(getStyles);
  const navigate = useNavigate();
  const location = useLocation();

  // Determine active tab based on current route
  const getActiveTab = (): string => {
    if (location.pathname.startsWith('/editor')) {
      return 'editor';
    } else if (location.pathname.startsWith('/scripts')) {
      return 'scripts';
    } else if (location.pathname.startsWith('/config')) {
      return 'config';
    }
    return 'editor';
  };

  const activeTab = getActiveTab();

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <div className={styles.title}>
          <Icon name="code-branch" size="lg" />
          <h2>SQL Monitor Code Editor</h2>
        </div>
        <div className={styles.navigation}>
          <TabsBar>
            <Tab
              label="Code Editor"
              icon="edit"
              active={activeTab === 'editor'}
              onChangeTab={() => navigate('/editor')}
            />
            <Tab
              label="Saved Scripts"
              icon="save"
              active={activeTab === 'scripts'}
              onChangeTab={() => navigate('/scripts')}
            />
            <Tab
              label="Configuration"
              icon="cog"
              active={activeTab === 'config'}
              onChangeTab={() => navigate('/config')}
            />
          </TabsBar>
        </div>
      </div>
    </div>
  );
};

/**
 * Component styles
 */
const getStyles = (theme: GrafanaTheme2) => ({
  container: css`
    width: 100%;
    background-color: ${theme.colors.background.primary};
    border-bottom: 1px solid ${theme.colors.border.weak};
  `,

  header: css`
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: ${theme.spacing(2)};
    gap: ${theme.spacing(2)};
  `,

  title: css`
    display: flex;
    align-items: center;
    gap: ${theme.spacing(1)};
    color: ${theme.colors.text.primary};

    h2 {
      margin: 0;
      font-size: ${theme.typography.h3.fontSize};
      font-weight: ${theme.typography.h3.fontWeight};
    }
  `,

  navigation: css`
    flex: 1;
    display: flex;
    justify-content: center;
  `,
});
