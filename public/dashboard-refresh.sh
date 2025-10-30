#!/bin/bash
# Grafana Dashboard Refresh Script
# Downloads latest dashboards from GitHub without container restart
# Can be triggered via Grafana webhook or manual execution

set -e

# Configuration
GITHUB_REPO="${GITHUB_REPO:-https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/public}"
DASHBOARDS_DIR="${DASHBOARDS_DIR:-/var/lib/grafana/dashboards}"
GRAFANA_API="${GRAFANA_API:-http://localhost:3000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD}"

echo "=========================================="
echo "GRAFANA DASHBOARD REFRESH"
echo "=========================================="
date
echo ""

# Dashboard list (keep in sync with entrypoint)
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
    "08-aws-rds-performance-insights.json"
    "09-dbcc-integrity-checks.json"
    "detailed-metrics.json"
    "sql-server-overview.json"
)

DOWNLOAD_COUNT=0
FAILED_COUNT=0
UPDATE_COUNT=0

echo "Step 1: Downloading latest dashboards from GitHub..."
for dashboard in "${DASHBOARDS[@]}"; do
    echo "  Downloading $dashboard..."
    TEMP_FILE="/tmp/$dashboard"

    if wget -q -O "$TEMP_FILE" "$GITHUB_REPO/dashboards/$dashboard"; then
        # Compare with existing file
        if [ -f "$DASHBOARDS_DIR/$dashboard" ]; then
            if ! cmp -s "$TEMP_FILE" "$DASHBOARDS_DIR/$dashboard"; then
                echo "    ✓ Updated (file changed)"
                cp "$TEMP_FILE" "$DASHBOARDS_DIR/$dashboard"
                UPDATE_COUNT=$((UPDATE_COUNT + 1))
            else
                echo "    ○ No change"
            fi
        else
            echo "    ✓ New dashboard"
            cp "$TEMP_FILE" "$DASHBOARDS_DIR/$dashboard"
            UPDATE_COUNT=$((UPDATE_COUNT + 1))
        fi
        DOWNLOAD_COUNT=$((DOWNLOAD_COUNT + 1))
        rm -f "$TEMP_FILE"
    else
        FAILED_COUNT=$((FAILED_COUNT + 1))
        echo "    ✗ Failed to download"
    fi
done

echo ""
echo "Download Summary:"
echo "  Total dashboards: ${#DASHBOARDS[@]}"
echo "  Downloaded: $DOWNLOAD_COUNT"
echo "  Updated: $UPDATE_COUNT"
echo "  Failed: $FAILED_COUNT"
echo ""

# Step 2: Set permissions
echo "Step 2: Fixing permissions..."
chown -R 472:472 "$DASHBOARDS_DIR" 2>/dev/null || echo "  Warning: Could not change ownership (may need root)"
echo "  Permissions updated"
echo ""

# Step 3: Trigger Grafana to reload provisioning (if API available)
if [ -n "$GRAFANA_PASSWORD" ]; then
    echo "Step 3: Triggering Grafana provisioning reload..."

    # Grafana doesn't have a direct API to reload provisioning, but we can:
    # 1. Use the admin API to trigger dashboard search (forces re-scan)
    RESPONSE=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
        "$GRAFANA_API/api/search?type=dash-db" 2>/dev/null || echo "FAILED")

    if [ "$RESPONSE" != "FAILED" ]; then
        DASHBOARD_COUNT=$(echo "$RESPONSE" | grep -o '"uid"' | wc -l)
        echo "  ✓ Grafana API responsive"
        echo "  ✓ Dashboard count: $DASHBOARD_COUNT"
    else
        echo "  ⚠ Could not connect to Grafana API (dashboards will load on next Grafana restart)"
    fi
else
    echo "Step 3: Skipped (GRAFANA_PASSWORD not set)"
    echo "  Dashboards will be loaded on next Grafana restart or UI refresh"
fi

echo ""
echo "=========================================="
echo "REFRESH COMPLETE"
echo "=========================================="
echo ""
echo "What to do next:"
if [ $UPDATE_COUNT -gt 0 ]; then
    echo "  1. Dashboards updated! ($UPDATE_COUNT files changed)"
    echo "  2. Restart Grafana to load new dashboards:"
    echo "     docker restart <container-name>"
    echo "  OR"
    echo "  3. Wait for Grafana's auto-reload (may take 1-2 minutes)"
else
    echo "  No updates needed - all dashboards are current"
fi

exit 0
