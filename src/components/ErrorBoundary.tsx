import React, { Component, ErrorInfo, ReactNode } from 'react';
import { Alert, Button } from '@grafana/ui';

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
  onError?: (error: Error, errorInfo: ErrorInfo) => void;
}

interface State {
  hasError: boolean;
  error: Error | null;
  errorInfo: ErrorInfo | null;
}

/**
 * ErrorBoundary component to catch and handle React component errors.
 *
 * Prevents entire plugin from crashing when a component throws an error.
 * Displays a user-friendly error message with recovery options.
 *
 * @example
 * <ErrorBoundary>
 *   <CodeEditorPage />
 * </ErrorBoundary>
 */
export class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = {
      hasError: false,
      error: null,
      errorInfo: null,
    };
  }

  static getDerivedStateFromError(error: Error): Partial<State> {
    // Update state so the next render will show the fallback UI
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    // Log error details to console for debugging
    console.error('[ErrorBoundary] Component error caught:', {
      error: error.message,
      stack: error.stack,
      componentStack: errorInfo.componentStack,
      timestamp: new Date().toISOString(),
    });

    // Store error info in state for display
    this.setState({ errorInfo });

    // Call optional error handler callback
    if (this.props.onError) {
      this.props.onError(error, errorInfo);
    }

    // TODO: Log to monitoring service (Sentry, LogRocket, etc.)
    // Example:
    // if (window.Sentry) {
    //   window.Sentry.captureException(error, {
    //     contexts: {
    //       react: {
    //         componentStack: errorInfo.componentStack,
    //       },
    //     },
    //   });
    // }
  }

  handleReset = () => {
    // Reset error state to try rendering again
    this.setState({
      hasError: false,
      error: null,
      errorInfo: null,
    });
  };

  handleReload = () => {
    // Reload the entire page
    window.location.reload();
  };

  render() {
    if (this.state.hasError) {
      // Use custom fallback if provided
      if (this.props.fallback) {
        return this.props.fallback;
      }

      // Default error UI
      return (
        <div style={{ padding: '20px', maxWidth: '800px', margin: '0 auto' }}>
          <Alert title="Something went wrong" severity="error">
            <p style={{ marginBottom: '12px' }}>
              {this.state.error?.message || 'An unexpected error occurred in the application.'}
            </p>

            {process.env.NODE_ENV === 'development' && this.state.errorInfo && (
              <details style={{ marginBottom: '12px' }}>
                <summary style={{ cursor: 'pointer', marginBottom: '8px' }}>
                  <strong>Error Details (Development Mode)</strong>
                </summary>
                <pre
                  style={{
                    fontSize: '12px',
                    backgroundColor: '#f5f5f5',
                    padding: '12px',
                    borderRadius: '4px',
                    overflow: 'auto',
                    maxHeight: '300px',
                  }}
                >
                  {this.state.error?.stack}
                  {'\n\n'}
                  {this.state.errorInfo.componentStack}
                </pre>
              </details>
            )}

            <div style={{ display: 'flex', gap: '8px' }}>
              <Button onClick={this.handleReset} variant="secondary">
                Try Again
              </Button>
              <Button onClick={this.handleReload} variant="primary">
                Reload Page
              </Button>
            </div>
          </Alert>
        </div>
      );
    }

    // No error, render children normally
    return this.props.children;
  }
}
