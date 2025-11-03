/**
 * EditorPanel
 *
 * Monaco Editor wrapper component for T-SQL editing.
 * Features:
 * - SQL syntax highlighting
 * - Line numbers, minimap, code folding
 * - Find & replace, multi-cursor editing
 * - Dark mode support (respects Grafana theme)
 * - Keyboard shortcuts integration
 *
 * Week 5 Day 18: Integrated with SettingsService for editor preferences
 */

import React, { useRef, useEffect } from 'react';
import { css } from '@emotion/css';
import { GrafanaTheme2 } from '@grafana/data';
import { useTheme2 } from '@grafana/ui';
import Editor, { Monaco, OnMount } from '@monaco-editor/react';
import type * as monacoEditor from 'monaco-editor';
import { formatSql } from '../../utils/formatters';
import { monacoIntelliSenseService } from '../../services/monacoIntelliSenseService';
import { settingsService } from '../../services/settingsService';

/**
 * EditorPanel props
 */
interface EditorPanelProps {
  /** Current code content */
  value: string;

  /** Callback when code changes */
  onChange: (value: string) => void;

  /** Whether the editor is read-only */
  readOnly?: boolean;

  /** Language mode (default: 'sql') */
  language?: string;

  /** Height of the editor (default: '100%') */
  height?: string | number;

  /** Callback when editor is ready */
  onEditorReady?: (editor: monacoEditor.editor.IStandaloneCodeEditor) => void;

  /** Callback for custom keyboard shortcuts */
  onKeyboardShortcut?: (action: string) => void;
}

/**
 * EditorPanel component
 */
export const EditorPanel: React.FC<EditorPanelProps> = ({
  value,
  onChange,
  readOnly = false,
  language = 'sql',
  height = '100%',
  onEditorReady,
  onKeyboardShortcut,
}) => {
  const theme = useTheme2();
  const editorRef = useRef<monacoEditor.editor.IStandaloneCodeEditor | null>(null);
  const monacoRef = useRef<Monaco | null>(null);

  /**
   * Determine Monaco theme based on Grafana theme
   */
  const monacoTheme = theme.isDark ? 'vs-dark' : 'vs';

  /**
   * Apply editor settings from SettingsService (Week 5 Day 18)
   */
  const applyEditorSettings = (editor: monacoEditor.editor.IStandaloneCodeEditor) => {
    const settings = settingsService.getSettings();

    editor.updateOptions({
      fontSize: settings.editorFontSize,
      tabSize: settings.editorTabSize,
      lineNumbers: settings.editorLineNumbers ? 'on' : 'off',
      minimap: {
        enabled: settings.editorMinimap,
        scale: 1,
        showSlider: 'mouseover',
        renderCharacters: false,
      },
      wordWrap: settings.editorWordWrap ? 'on' : 'off',
    });

    console.log('[EditorPanel] Applied editor settings:', {
      fontSize: settings.editorFontSize,
      tabSize: settings.editorTabSize,
      lineNumbers: settings.editorLineNumbers,
      minimap: settings.editorMinimap,
      wordWrap: settings.editorWordWrap,
    });
  };

  /**
   * Handle editor mount
   */
  const handleEditorMount: OnMount = (editor, monaco) => {
    editorRef.current = editor;
    monacoRef.current = monaco;

    // Load settings from service and configure editor options (Week 5 Day 18)
    const settings = settingsService.getSettings();

    editor.updateOptions({
      fontSize: settings.editorFontSize,
      fontFamily: "'Courier New', 'Consolas', monospace",
      lineHeight: settings.editorFontSize + 6, // Dynamic line height based on font size
      letterSpacing: 0.5,
      tabSize: settings.editorTabSize,
      insertSpaces: true,
      detectIndentation: true,
      folding: true,
      foldingStrategy: 'indentation',
      showFoldingControls: 'always',
      minimap: {
        enabled: settings.editorMinimap,
        scale: 1,
        showSlider: 'mouseover',
        renderCharacters: false,
      },
      lineNumbers: settings.editorLineNumbers ? 'on' : 'off',
      renderLineHighlight: 'all',
      scrollBeyondLastLine: false,
      wordWrap: settings.editorWordWrap ? 'on' : 'off',
      wrappingStrategy: 'advanced',
      smoothScrolling: true,
      cursorBlinking: 'smooth',
      cursorSmoothCaretAnimation: 'on',
      formatOnPaste: true,
      formatOnType: false,
      autoClosingBrackets: 'always',
      autoClosingQuotes: 'always',
      autoSurround: 'languageDefined',
      bracketPairColorization: {
        enabled: true,
      },
      guides: {
        bracketPairs: true,
        bracketPairsHorizontal: true,
        highlightActiveBracketPair: true,
        indentation: true,
      },
      suggest: {
        showWords: true,
        showSnippets: true,
      },
      quickSuggestions: {
        other: true,
        comments: false,
        strings: false,
      },
      parameterHints: {
        enabled: true,
      },
      acceptSuggestionOnCommitCharacter: true,
      acceptSuggestionOnEnter: 'on',
      snippetSuggestions: 'top',
    });

    // Register custom keyboard shortcuts
    registerKeyboardShortcuts(editor, monaco, onKeyboardShortcut);

    // Configure SQL language features
    configureSqlLanguage(monaco);

    // Notify parent component
    if (onEditorReady) {
      onEditorReady(editor);
    }
  };

  /**
   * Handle editor content change
   */
  const handleEditorChange = (value: string | undefined) => {
    onChange(value || '');
  };

  /**
   * Focus the editor
   */
  useEffect(() => {
    if (editorRef.current) {
      editorRef.current.focus();
    }
  }, []);

  /**
   * Subscribe to settings changes (Week 5 Day 18)
   */
  useEffect(() => {
    const unsubscribe = settingsService.subscribe((updatedSettings) => {
      if (editorRef.current) {
        console.log('[EditorPanel] Settings changed, updating editor options');
        applyEditorSettings(editorRef.current);
      }
    });

    return unsubscribe;
  }, []);

  /**
   * Cleanup Monaco editor instance on unmount to prevent memory leaks
   * Code Optimization: Fix memory leak identified in code review
   */
  useEffect(() => {
    return () => {
      // Dispose editor instance
      if (editorRef.current) {
        console.log('[EditorPanel] Disposing Monaco editor instance');
        editorRef.current.dispose();
        editorRef.current = null;
      }

      // Clear Monaco reference
      if (monacoRef.current) {
        monacoRef.current = null;
      }
    };
  }, []);

  return (
    <div className={css(getStyles(theme))}>
      <Editor
        height={height}
        defaultLanguage={language}
        language={language}
        value={value}
        onChange={handleEditorChange}
        onMount={handleEditorMount}
        theme={monacoTheme}
        options={{
          readOnly,
        }}
        loading={
          <div className={css(getLoadingStyles(theme))}>
            <div className="spinner" />
            <p>Loading editor...</p>
          </div>
        }
      />
    </div>
  );
};

/**
 * Register custom keyboard shortcuts
 */
function registerKeyboardShortcuts(
  editor: monacoEditor.editor.IStandaloneCodeEditor,
  monaco: Monaco,
  onKeyboardShortcut?: (action: string) => void
) {
  if (!onKeyboardShortcut) {
    return;
  }

  // Ctrl+S: Save
  editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, () => {
    onKeyboardShortcut('save');
  });

  // Ctrl+Enter: Run Query
  editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.Enter, () => {
    onKeyboardShortcut('run');
  });

  // F5: Run Query (alternative)
  editor.addCommand(monaco.KeyCode.F5, () => {
    onKeyboardShortcut('run');
  });

  // Ctrl+Shift+F: Format Code
  editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyMod.Shift | monaco.KeyCode.KeyF, () => {
    onKeyboardShortcut('format');
  });

  // Ctrl+/: Toggle Line Comment
  editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.Slash, () => {
    editor.trigger('keyboard', 'editor.action.commentLine', {});
  });

  // Ctrl+Shift+/: Toggle Block Comment
  editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyMod.Shift | monaco.KeyCode.Slash, () => {
    editor.trigger('keyboard', 'editor.action.blockComment', {});
  });

  // Ctrl+D: Duplicate Line
  editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyD, () => {
    editor.trigger('keyboard', 'editor.action.copyLinesDownAction', {});
  });

  // Alt+Up/Down: Move Line Up/Down
  editor.addCommand(monaco.KeyMod.Alt | monaco.KeyCode.UpArrow, () => {
    editor.trigger('keyboard', 'editor.action.moveLinesUpAction', {});
  });
  editor.addCommand(monaco.KeyMod.Alt | monaco.KeyCode.DownArrow, () => {
    editor.trigger('keyboard', 'editor.action.moveLinesDownAction', {});
  });

  // Ctrl+Shift+K: Delete Line
  editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyMod.Shift | monaco.KeyCode.KeyK, () => {
    editor.trigger('keyboard', 'editor.action.deleteLines', {});
  });

  // Ctrl+]: Indent
  editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.BracketRight, () => {
    editor.trigger('keyboard', 'editor.action.indentLines', {});
  });

  // Ctrl+[: Outdent
  editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.BracketLeft, () => {
    editor.trigger('keyboard', 'editor.action.outdentLines', {});
  });

  // Ctrl+K Ctrl+C: Comment Selection
  editor.addCommand(monaco.KeyMod.chord(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyK, monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyC), () => {
    editor.trigger('keyboard', 'editor.action.addCommentLine', {});
  });

  // Ctrl+K Ctrl+U: Uncomment Selection
  editor.addCommand(monaco.KeyMod.chord(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyK, monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyU), () => {
    editor.trigger('keyboard', 'editor.action.removeCommentLine', {});
  });

  // Ctrl+K Ctrl+F: Format Selection
  editor.addCommand(monaco.KeyMod.chord(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyK, monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyF), () => {
    editor.trigger('keyboard', 'editor.action.formatSelection', {});
  });

  // Ctrl+Shift+L: Select All Occurrences
  editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyMod.Shift | monaco.KeyCode.KeyL, () => {
    editor.trigger('keyboard', 'editor.action.selectHighlights', {});
  });

  // Ctrl+F2: Change All Occurrences
  editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.F2, () => {
    editor.trigger('keyboard', 'editor.action.changeAll', {});
  });

  // F8: Go to Next Error
  editor.addCommand(monaco.KeyCode.F8, () => {
    editor.trigger('keyboard', 'editor.action.marker.next', {});
  });

  // Shift+F8: Go to Previous Error
  editor.addCommand(monaco.KeyMod.Shift | monaco.KeyCode.F8, () => {
    editor.trigger('keyboard', 'editor.action.marker.prev', {});
  });

  // Ctrl+G: Go to Line
  editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyG, () => {
    editor.trigger('keyboard', 'editor.action.gotoLine', {});
  });

  // Ctrl+P: Quick Open (File Picker)
  editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyP, () => {
    onKeyboardShortcut('quickOpen');
  });

  // Ctrl+Shift+P: Command Palette
  editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyMod.Shift | monaco.KeyCode.KeyP, () => {
    editor.trigger('keyboard', 'editor.action.quickCommand', {});
  });

  // Ctrl+K Ctrl+H: Keyboard Shortcuts Help
  editor.addCommand(monaco.KeyMod.chord(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyK, monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyH), () => {
    onKeyboardShortcut('showKeyboardShortcuts');
  });
}

/**
 * Configure SQL language features
 */
function configureSqlLanguage(monaco: Monaco) {
  // SQL keywords (T-SQL specific)
  const sqlKeywords = [
    'SELECT', 'FROM', 'WHERE', 'JOIN', 'INNER', 'LEFT', 'RIGHT', 'FULL', 'OUTER', 'CROSS',
    'ON', 'AND', 'OR', 'NOT', 'IN', 'EXISTS', 'BETWEEN', 'LIKE', 'IS', 'NULL',
    'INSERT', 'INTO', 'VALUES', 'UPDATE', 'SET', 'DELETE', 'TRUNCATE',
    'CREATE', 'ALTER', 'DROP', 'TABLE', 'VIEW', 'INDEX', 'PROCEDURE', 'FUNCTION',
    'DATABASE', 'SCHEMA', 'CONSTRAINT', 'PRIMARY', 'FOREIGN', 'KEY', 'UNIQUE',
    'DEFAULT', 'CHECK', 'REFERENCES', 'CASCADE', 'NO', 'ACTION',
    'AS', 'DISTINCT', 'TOP', 'ORDER', 'BY', 'GROUP', 'HAVING', 'UNION', 'ALL',
    'CASE', 'WHEN', 'THEN', 'ELSE', 'END', 'IF', 'BEGIN', 'END',
    'DECLARE', 'SET', 'EXEC', 'EXECUTE', 'RETURN', 'PRINT', 'RAISERROR',
    'TRY', 'CATCH', 'THROW', 'TRANSACTION', 'COMMIT', 'ROLLBACK', 'SAVE',
    'GRANT', 'REVOKE', 'DENY', 'WITH', 'NOLOCK', 'ROWLOCK', 'UPDLOCK',
    'INT', 'BIGINT', 'SMALLINT', 'TINYINT', 'DECIMAL', 'NUMERIC', 'FLOAT', 'REAL',
    'VARCHAR', 'NVARCHAR', 'CHAR', 'NCHAR', 'TEXT', 'NTEXT',
    'DATE', 'DATETIME', 'DATETIME2', 'TIME', 'TIMESTAMP', 'SMALLDATETIME',
    'BIT', 'BINARY', 'VARBINARY', 'IMAGE', 'UNIQUEIDENTIFIER', 'XML', 'JSON',
    'COUNT', 'SUM', 'AVG', 'MIN', 'MAX', 'STDEV', 'VAR',
    'ROW_NUMBER', 'RANK', 'DENSE_RANK', 'NTILE', 'LAG', 'LEAD',
    'OVER', 'PARTITION', 'ROWS', 'RANGE', 'UNBOUNDED', 'PRECEDING', 'FOLLOWING', 'CURRENT',
    'CAST', 'CONVERT', 'COALESCE', 'ISNULL', 'NULLIF',
    'SUBSTRING', 'LEN', 'CHARINDEX', 'PATINDEX', 'REPLACE', 'UPPER', 'LOWER', 'LTRIM', 'RTRIM',
    'DATEADD', 'DATEDIFF', 'GETDATE', 'GETUTCDATE', 'SYSDATETIME', 'YEAR', 'MONTH', 'DAY',
  ];

  // SQL operators
  const sqlOperators = [
    '=', '!=', '<>', '<', '>', '<=', '>=',
    '+', '-', '*', '/', '%',
    '(', ')', ',', ';', '.',
  ];

  // Register SQL language configuration
  monaco.languages.setLanguageConfiguration('sql', {
    comments: {
      lineComment: '--',
      blockComment: ['/*', '*/'],
    },
    brackets: [
      ['(', ')'],
      ['[', ']'],
    ],
    autoClosingPairs: [
      { open: '(', close: ')' },
      { open: '[', close: ']' },
      { open: "'", close: "'", notIn: ['string', 'comment'] },
      { open: '"', close: '"', notIn: ['string', 'comment'] },
    ],
    surroundingPairs: [
      { open: '(', close: ')' },
      { open: '[', close: ']' },
      { open: "'", close: "'" },
      { open: '"', close: '"' },
    ],
    folding: {
      markers: {
        start: new RegExp('^\\s*--\\s*#region\\b'),
        end: new RegExp('^\\s*--\\s*#endregion\\b'),
      },
    },
  });

  // Register SQL token provider for syntax highlighting
  monaco.languages.setMonarchTokensProvider('sql', {
    defaultToken: '',
    tokenPostfix: '.sql',
    ignoreCase: true,

    keywords: sqlKeywords,
    operators: sqlOperators,

    tokenizer: {
      root: [
        // Line comments
        [/--.*$/, 'comment'],

        // Block comments
        [/\/\*/, 'comment', '@comment'],

        // Strings
        [/'/, 'string', '@string'],
        [/"/, 'string.double', '@stringDouble'],

        // Numbers
        [/\b\d+(\.\d+)?\b/, 'number'],

        // Keywords
        [/\b(SELECT|FROM|WHERE|JOIN|INNER|LEFT|RIGHT|FULL|OUTER|CROSS|ON|AND|OR|NOT|IN|EXISTS|BETWEEN|LIKE|IS|NULL)\b/i, 'keyword'],
        [/\b(INSERT|INTO|VALUES|UPDATE|SET|DELETE|TRUNCATE)\b/i, 'keyword'],
        [/\b(CREATE|ALTER|DROP|TABLE|VIEW|INDEX|PROCEDURE|FUNCTION|DATABASE|SCHEMA)\b/i, 'keyword'],
        [/\b(AS|DISTINCT|TOP|ORDER|BY|GROUP|HAVING|UNION|ALL)\b/i, 'keyword'],
        [/\b(CASE|WHEN|THEN|ELSE|END|IF|BEGIN)\b/i, 'keyword'],
        [/\b(DECLARE|SET|EXEC|EXECUTE|RETURN|PRINT|RAISERROR)\b/i, 'keyword'],
        [/\b(TRY|CATCH|THROW|TRANSACTION|COMMIT|ROLLBACK|SAVE)\b/i, 'keyword'],

        // Data types
        [/\b(INT|BIGINT|SMALLINT|TINYINT|DECIMAL|NUMERIC|FLOAT|REAL|VARCHAR|NVARCHAR|CHAR|NCHAR|TEXT|NTEXT|DATE|DATETIME|DATETIME2|TIME|TIMESTAMP|BIT|BINARY|VARBINARY|IMAGE|UNIQUEIDENTIFIER|XML|JSON)\b/i, 'type'],

        // Functions
        [/\b(COUNT|SUM|AVG|MIN|MAX|STDEV|VAR|ROW_NUMBER|RANK|DENSE_RANK|NTILE|LAG|LEAD|CAST|CONVERT|COALESCE|ISNULL|NULLIF|SUBSTRING|LEN|CHARINDEX|PATINDEX|REPLACE|UPPER|LOWER|LTRIM|RTRIM|DATEADD|DATEDIFF|GETDATE|GETUTCDATE|SYSDATETIME|YEAR|MONTH|DAY)\b/i, 'predefined'],

        // Operators
        [/[=!<>]+/, 'operator'],
        [/[+\-*/%]/, 'operator'],

        // Variables
        [/@\w+/, 'variable'],

        // Identifiers
        [/[a-zA-Z_][\w]*/, 'identifier'],

        // Delimiters
        [/[()[\]]/, '@brackets'],
        [/[,;.]/, 'delimiter'],
      ],

      comment: [
        [/[^/*]+/, 'comment'],
        [/\*\//, 'comment', '@pop'],
        [/[/*]/, 'comment'],
      ],

      string: [
        [/[^']+/, 'string'],
        [/''/, 'string'],
        [/'/, 'string', '@pop'],
      ],

      stringDouble: [
        [/[^"]+/, 'string.double'],
        [/""/, 'string.double'],
        [/"/, 'string.double', '@pop'],
      ],
    },
  });

  // Initialize IntelliSense service (Week 2 Day 8)
  // This provides schema-aware autocomplete, Go to Definition (F12), and hover tooltips
  monacoIntelliSenseService.initialize();
  console.log('[EditorPanel] Monaco IntelliSense service initialized');

  // Register document formatting provider (using sql-formatter)
  monaco.languages.registerDocumentFormattingEditProvider('sql', {
    provideDocumentFormattingEdits: (model) => {
      const code = model.getValue();
      const formatted = formatSql(code);

      return [
        {
          range: model.getFullModelRange(),
          text: formatted,
        },
      ];
    },
  });

  // Register document range formatting provider (for format selection)
  monaco.languages.registerDocumentRangeFormattingEditProvider('sql', {
    provideDocumentRangeFormattingEdits: (model, range) => {
      const code = model.getValueInRange(range);
      const formatted = formatSql(code);

      return [
        {
          range,
          text: formatted,
        },
      ];
    },
  });
}

/**
 * Component styles
 */
const getStyles = (theme: GrafanaTheme2) => css`
  width: 100%;
  height: 100%;
  overflow: hidden;

  .monaco-editor {
    padding: 0;
  }

  .monaco-editor .margin {
    background-color: ${theme.colors.background.secondary};
  }

  .monaco-editor .line-numbers {
    color: ${theme.colors.text.disabled};
  }
`;

/**
 * Loading state styles
 */
const getLoadingStyles = (theme: GrafanaTheme2) => css`
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  height: 100%;
  color: ${theme.colors.text.secondary};

  .spinner {
    width: 40px;
    height: 40px;
    border: 3px solid ${theme.colors.border.weak};
    border-top-color: ${theme.colors.primary.main};
    border-radius: 50%;
    animation: spin 1s linear infinite;
    margin-bottom: ${theme.spacing(2)};
  }

  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }

  p {
    margin: 0;
    font-size: ${theme.typography.body.fontSize};
  }
`;
