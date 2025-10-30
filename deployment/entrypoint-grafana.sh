#!/bin/bash
set -e

echo "==================================================================="
echo "SQL Monitor - Grafana Container Starting"
echo "==================================================================="

# =========================================
# Configuration from Environment Variables
# =========================================

# MonitoringDB Connection
MONITORINGDB_SERVER="${MONITORINGDB_SERVER:-localhost}"
MONITORINGDB_PORT="${MONITORINGDB_PORT:-1433}"
MONITORINGDB_DATABASE="${MONITORINGDB_DATABASE:-MonitoringDB}"
MONITORINGDB_USER="${MONITORINGDB_USER:-sa}"
MONITORINGDB_PASSWORD="${MONITORINGDB_PASSWORD}"

# Grafana Configuration
GF_SERVER_ROOT_URL="${GF_SERVER_ROOT_URL:-http://localhost:3000}"
GF_SECURITY_ADMIN_PASSWORD="${GF_SECURITY_ADMIN_PASSWORD:-admin}"

# Dashboard Download (optional - for GitHub integration)
GITHUB_REPO="${GITHUB_REPO:-}"
DASHBOARD_DOWNLOAD="${DASHBOARD_DOWNLOAD:-false}"

echo "Configuration:"
echo "  MonitoringDB: ${MONITORINGDB_SERVER}:${MONITORINGDB_PORT}/${MONITORINGDB_DATABASE}"
echo "  Grafana Root URL: ${GF_SERVER_ROOT_URL}"
echo "  Dashboard Download: ${DASHBOARD_DOWNLOAD}"

# =========================================
# Create Datasource Configuration
# =========================================

echo "Creating datasource configuration..."

mkdir -p /etc/grafana/provisioning/datasources

cat > /etc/grafana/provisioning/datasources/monitoringdb.yaml <<EOF
apiVersion: 1

datasources:
  - name: MonitoringDB
    type: mssql
    uid: PACBEEDECF159CDCA
    access: proxy
    url: ${MONITORINGDB_SERVER}:${MONITORINGDB_PORT}
    database: ${MONITORINGDB_DATABASE}
    user: ${MONITORINGDB_USER}
    secureJsonData:
      password: ${MONITORINGDB_PASSWORD}
    jsonData:
      maxOpenConns: 10
      maxIdleConns: 2
      connMaxLifetime: 14400
      encrypt: 'true'
      tlsSkipVerify: true
    editable: false
    isDefault: true
EOF

echo "✓ Datasource configuration created"

# =========================================
# Download Dashboards (Optional)
# =========================================

if [ "$DASHBOARD_DOWNLOAD" = "true" ] && [ -n "$GITHUB_REPO" ]; then
    echo "Downloading dashboards from GitHub..."
    mkdir -p /var/lib/grafana/dashboards

    DASHBOARDS=(
        "00-dashboard-browser.json"
        "00-landing-page.json"
        "00-sql-server-monitoring.json"
        "01-table-browser.json"
        "02-table-details.json"
        "03-code-browser.json"
        "05-performance-analysis.json"
        "06-query-store.json"
        "07-audit-logging.json"
        "08-insights.json"
        "09-dbcc-integrity-checks.json"
        "detailed-metrics.json"
        "sql-server-overview.json"
    )

    for dashboard in "${DASHBOARDS[@]}"; do
        echo "  Downloading $dashboard..."
        curl -sSL "${GITHUB_REPO}/${dashboard}" -o "/var/lib/grafana/dashboards/${dashboard}" 2>/dev/null || true
    done

    echo "✓ Dashboards downloaded"
fi

# =========================================
# Start Grafana
# =========================================

echo "Starting Grafana..."
echo "==================================================================="

exec /run.sh
