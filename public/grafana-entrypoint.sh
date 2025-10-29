#!/bin/bash
# Grafana Entrypoint with GitHub Dashboard Download
# Simplified version with extensive debugging

# Enable debug mode and exit on any error
set -x
set -e

echo "=========================================="
echo "GRAFANA ENTRYPOINT - DEBUG MODE"
echo "=========================================="
date
echo ""

# Configuration
GITHUB_REPO="${GITHUB_REPO:-https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/public}"
DASHBOARDS_DIR="/var/lib/grafana/dashboards"
PROVISIONING_DIR="/etc/grafana/provisioning"

echo "Configuration:"
echo "  GitHub Repo: $GITHUB_REPO"
echo "  Dashboards Dir: $DASHBOARDS_DIR"
echo "  Provisioning Dir: $PROVISIONING_DIR"
echo "  MonitoringDB Server: ${MONITORINGDB_SERVER:-NOT_SET}"
echo "  MonitoringDB Port: ${MONITORINGDB_PORT:-NOT_SET}"
echo "  MonitoringDB Database: ${MONITORINGDB_DATABASE:-NOT_SET}"
echo "  MonitoringDB User: ${MONITORINGDB_USER:-NOT_SET}"
echo ""

# Check environment variables
if [ -z "$MONITORINGDB_SERVER" ] || [ -z "$MONITORINGDB_PASSWORD" ]; then
    echo "ERROR: Required environment variables not set!"
    echo "  MONITORINGDB_SERVER: ${MONITORINGDB_SERVER:-NOT_SET}"
    echo "  MONITORINGDB_PASSWORD: ${MONITORINGDB_PASSWORD:-NOT_SET}"
    exit 1
fi

# Step 1: Create directories
echo "Step 1: Creating directories..."
mkdir -p "$DASHBOARDS_DIR"
mkdir -p "$PROVISIONING_DIR/dashboards"
mkdir -p "$PROVISIONING_DIR/datasources"
echo "  Directories created successfully"
ls -la "$DASHBOARDS_DIR" || true
ls -la "$PROVISIONING_DIR" || true
echo ""

# Step 2: Generate datasource configuration
echo "Step 2: Generating datasource configuration..."
cat > "$PROVISIONING_DIR/datasources/monitoringdb.yaml" <<EOF
apiVersion: 1

datasources:
  - name: MonitoringDB
    type: mssql
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

echo "  Datasource config generated"
echo "  Validating YAML syntax..."
cat "$PROVISIONING_DIR/datasources/monitoringdb.yaml"
echo ""

# Step 3: Download dashboard provider config
echo "Step 3: Downloading dashboard provider config..."
wget -q -O "$PROVISIONING_DIR/dashboards/dashboards.yaml" \
    "$GITHUB_REPO/provisioning/dashboards/dashboards.yaml" || {
    echo "  ERROR: Dashboard provider config download failed"
    exit 1
}
echo "  Dashboard provider config downloaded"
cat "$PROVISIONING_DIR/dashboards/dashboards.yaml"
echo ""

# Step 4: Download dashboard JSON files
echo "Step 4: Downloading dashboard JSON files..."
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

DOWNLOAD_COUNT=0
FAILED_COUNT=0

for dashboard in "${DASHBOARDS[@]}"; do
    echo "  Downloading $dashboard..."
    if wget -q -O "$DASHBOARDS_DIR/$dashboard" "$GITHUB_REPO/dashboards/$dashboard"; then
        DOWNLOAD_COUNT=$((DOWNLOAD_COUNT + 1))
        echo "    ✓ Success"
    else
        FAILED_COUNT=$((FAILED_COUNT + 1))
        echo "    ✗ Failed"
    fi
done

echo "  Downloaded: $DOWNLOAD_COUNT dashboards"
echo "  Failed: $FAILED_COUNT dashboards"
echo ""

# Step 5: Set permissions
echo "Step 5: Setting permissions (Grafana runs as UID 472)..."
chown -R 472:472 "$DASHBOARDS_DIR" || echo "  Warning: chown dashboards failed"
chown -R 472:472 "$PROVISIONING_DIR" || echo "  Warning: chown provisioning failed"
echo "  Permissions set"
ls -la "$DASHBOARDS_DIR" | head -5
echo ""

# Step 6: Start Grafana (simplified - run as root for now)
echo "Step 6: Starting Grafana..."
echo "  Command: /run.sh"
echo "  Running as root (user switching removed for debugging)"
echo ""
echo "=========================================="
echo "HANDING OFF TO GRAFANA"
echo "=========================================="

# Execute Grafana - simplified without user switching
exec /run.sh
