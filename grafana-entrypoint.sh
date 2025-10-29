#!/bin/bash
# Grafana Entrypoint with GitHub Dashboard Download
# This script downloads dashboards and provisioning configs from GitHub
# and starts Grafana - works on any container platform

set -e

GITHUB_REPO="${GITHUB_REPO:-https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/public}"
DASHBOARDS_DIR="/var/lib/grafana/dashboards"
PROVISIONING_DIR="/etc/grafana/provisioning"

echo "=== Grafana Startup with GitHub Dashboard Download ==="
echo "GitHub Repo: $GITHUB_REPO"
echo "Dashboards Dir: $DASHBOARDS_DIR"
echo "Provisioning Dir: $PROVISIONING_DIR"

# Create directories if they don't exist
mkdir -p "$DASHBOARDS_DIR"
mkdir -p "$PROVISIONING_DIR/dashboards"
mkdir -p "$PROVISIONING_DIR/datasources"

# Download provisioning configurations
echo "Downloading provisioning configs..."
wget -q -O "$PROVISIONING_DIR/datasources/monitoringdb.yaml" \
    "$GITHUB_REPO/provisioning/datasources/monitoringdb.yaml" || echo "Datasource config download failed (will configure manually)"

wget -q -O "$PROVISIONING_DIR/dashboards/dashboards.yaml" \
    "$GITHUB_REPO/provisioning/dashboards/dashboards.yaml" || echo "Dashboard provider config download failed"

# Download all dashboard JSON files
echo "Downloading dashboards..."
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
    wget -q -O "$DASHBOARDS_DIR/$dashboard" \
        "$GITHUB_REPO/dashboards/$dashboard" || echo "  Warning: $dashboard download failed"
done

echo "Dashboard download complete!"
echo "Starting Grafana..."

# Start Grafana with original entrypoint
exec /run.sh
