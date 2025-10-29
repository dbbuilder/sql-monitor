#!/bin/bash
# =============================================
# SQL Monitor - Example Deployment for ArcTrade Client
# Purpose: Complete example showing both deployment scripts
# =============================================

set -e
set -o pipefail

echo ""
echo "=========================================="
echo "SQL Monitor - Example Deployment"
echo "Client: ArcTrade"
echo "=========================================="
echo ""

# =============================================
# PART 1: Deploy MonitoringDB and Data Collection
# =============================================

echo "PART 1: Deploying MonitoringDB and configuring data collection..."
echo ""

# Configuration for MonitoringDB deployment
export CENTRAL_SERVER="sql-prod-01"
export CENTRAL_PORT="1433"
export CENTRAL_USER="sa"
export CENTRAL_PASSWORD="YourSecurePassword123"
export CENTRAL_DATABASE="MonitoringDB"

# Monitored servers (comma-separated)
export MONITORED_SERVERS="sql-prod-02,sql-prod-03,sql-prod-04,sql-prod-05"

# SQL authentication for monitored servers
export MONITORED_USER="monitor_collector"
export MONITORED_PASSWORD="MonitorCollectorPass456"
export MONITORED_PORT="1433"

# Collection frequency
export COLLECTION_INTERVAL="5"

# Client identification
export CLIENT_NAME="ArcTrade"

# Monitor central server itself
export MONITOR_CENTRAL_SERVER="true"

echo "Configuration:"
echo "  Central Server: ${CENTRAL_SERVER}:${CENTRAL_PORT}"
echo "  Monitored Servers: ${MONITORED_SERVERS}"
echo "  Collection Interval: ${COLLECTION_INTERVAL} minutes"
echo "  Monitor Central Server: ${MONITOR_CENTRAL_SERVER}"
echo ""

# Uncomment to actually run deployment
# ./deploy-monitoring.sh

echo "✓ Part 1 configuration ready"
echo ""

# =============================================
# PART 2: Deploy Grafana Visualization
# =============================================

echo "PART 2: Deploying Grafana visualization layer..."
echo ""

# Deployment target (local, azure, aws)
export DEPLOYMENT_TARGET="local"

# Grafana configuration
export GRAFANA_PORT="9002"
export GRAFANA_ADMIN_PASSWORD="Admin123!"

# MonitoringDB connection (from Part 1)
export MONITORINGDB_SERVER="${CENTRAL_SERVER}"
export MONITORINGDB_PORT="${CENTRAL_PORT}"
export MONITORINGDB_DATABASE="${CENTRAL_DATABASE}"
export MONITORINGDB_USER="monitor_api"
export MONITORINGDB_PASSWORD="MonitorAPIPass789"

# Client identification
export CLIENT_NAME="ArcTrade"
export CLIENT_ORG="ArcTrade"

echo "Configuration:"
echo "  Deployment Target: ${DEPLOYMENT_TARGET}"
echo "  Grafana Port: ${GRAFANA_PORT}"
echo "  MonitoringDB Server: ${MONITORINGDB_SERVER}:${MONITORINGDB_PORT}"
echo "  Client: ${CLIENT_NAME}"
echo ""

# Uncomment to actually run deployment
# ./deploy-grafana.sh

echo "✓ Part 2 configuration ready"
echo ""

# =============================================
# Summary
# =============================================

echo "=========================================="
echo "Deployment Configuration Complete"
echo "=========================================="
echo ""
echo "To execute deployment:"
echo ""
echo "1. Review configuration variables above"
echo "2. Update passwords and server names"
echo "3. Uncomment the deployment script calls:"
echo "   - Line 68: ./deploy-monitoring.sh"
echo "   - Line 99: ./deploy-grafana.sh"
echo "4. Run: ./example-deployment.sh"
echo ""
echo "OR run scripts individually:"
echo ""
echo "# Part 1: MonitoringDB"
echo "source .env.monitoring"
echo "./deploy-monitoring.sh"
echo ""
echo "# Part 2: Grafana"
echo "source .env.grafana"
echo "./deploy-grafana.sh"
echo ""
echo "Access Grafana at: http://localhost:${GRAFANA_PORT}"
echo "Login: admin / ${GRAFANA_ADMIN_PASSWORD}"
echo ""
