#!/bin/bash
# =============================================
# Grafana Data Setup - Quick Start Script
# Purpose: Initialize metadata collection and set landing page as home
# Created: 2025-10-28
# =============================================

set -e  # Exit on error

echo "========================================="
echo "Grafana Dashboard Data Setup"
echo "========================================="
echo ""

# Configuration (adjust these for your environment)
SQL_SERVER="${SQL_SERVER:-172.31.208.1,14333}"
SQL_USER="${SQL_USER:-sv}"
SQL_PASSWORD="${SQL_PASSWORD:-Gv51076!}"
SQL_DATABASE="MonitoringDB"

echo "Configuration:"
echo "  SQL Server: $SQL_SERVER"
echo "  User: $SQL_USER"
echo "  Database: $SQL_DATABASE"
echo ""

# =============================================
# Step 1: Check prerequisites
# =============================================

echo "Step 1: Checking prerequisites..."

# Check if sqlcmd is available
if ! command -v sqlcmd &> /dev/null; then
    echo "❌ ERROR: sqlcmd not found"
    echo ""
    echo "Install sqlcmd:"
    echo "  Ubuntu/Debian: sudo apt-get install mssql-tools"
    echo "  Or use SSMS / Azure Data Studio to run scripts manually"
    exit 1
fi

# Check if database scripts exist
if [ ! -f "database/29-initialize-metadata-collection.sql" ]; then
    echo "❌ ERROR: Initialization script not found"
    echo "  Expected: database/29-initialize-metadata-collection.sql"
    echo "  Run from project root directory"
    exit 1
fi

echo "  ✓ sqlcmd found"
echo "  ✓ Initialization script found"
echo ""

# =============================================
# Step 2: Test database connection
# =============================================

echo "Step 2: Testing database connection..."

if sqlcmd -S "$SQL_SERVER" -U "$SQL_USER" -P "$SQL_PASSWORD" -d "$SQL_DATABASE" -C -Q "SELECT @@VERSION" > /dev/null 2>&1; then
    echo "  ✓ Database connection successful"
else
    echo "❌ ERROR: Cannot connect to database"
    echo ""
    echo "Check connection details:"
    echo "  Server: $SQL_SERVER"
    echo "  User: $SQL_USER"
    echo "  Database: $SQL_DATABASE"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Verify SQL Server is running"
    echo "  2. Check username and password"
    echo "  3. Ensure SQL Server allows remote connections"
    echo "  4. Check firewall settings"
    exit 1
fi
echo ""

# =============================================
# Step 3: Initialize metadata collection
# =============================================

echo "Step 3: Initializing metadata collection..."
echo ""
echo "This will:"
echo "  - Register local server in Servers table"
echo "  - Auto-discover all user databases"
echo "  - Collect metadata for tables, procedures, functions"
echo "  - May take 1-5 minutes per database"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted by user"
    exit 1
fi

echo "Running initialization script..."
echo ""

# Run initialization script
if sqlcmd -S "$SQL_SERVER" -U "$SQL_USER" -P "$SQL_PASSWORD" -d "$SQL_DATABASE" -C \
    -i database/29-initialize-metadata-collection.sql -o /tmp/grafana-init.log; then
    echo ""
    echo "✓ Initialization complete"
    echo ""
    echo "Full output saved to: /tmp/grafana-init.log"
else
    echo ""
    echo "❌ ERROR: Initialization failed"
    echo "Check output above for errors"
    echo "Full log: /tmp/grafana-init.log"
    exit 1
fi
echo ""

# =============================================
# Step 4: Verify data collected
# =============================================

echo "Step 4: Verifying data collection..."
echo ""

# Check database count
DB_COUNT=$(sqlcmd -S "$SQL_SERVER" -U "$SQL_USER" -P "$SQL_PASSWORD" -d "$SQL_DATABASE" -C \
    -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.DatabaseMetadataCache;" -h -1 | tr -d '[:space:]')

# Check table count
TABLE_COUNT=$(sqlcmd -S "$SQL_SERVER" -U "$SQL_USER" -P "$SQL_PASSWORD" -d "$SQL_DATABASE" -C \
    -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.TableMetadata;" -h -1 | tr -d '[:space:]')

# Check code object count
CODE_COUNT=$(sqlcmd -S "$SQL_SERVER" -U "$SQL_USER" -P "$SQL_PASSWORD" -d "$SQL_DATABASE" -C \
    -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.CodeObjectMetadata;" -h -1 | tr -d '[:space:]')

echo "Results:"
echo "  Databases registered: $DB_COUNT"
echo "  Tables cached: $TABLE_COUNT"
echo "  Code objects cached: $CODE_COUNT"
echo ""

if [ "$DB_COUNT" -eq 0 ] || [ "$TABLE_COUNT" -eq 0 ]; then
    echo "⚠️  WARNING: No data collected"
    echo ""
    echo "Possible causes:"
    echo "  - No user databases on server (only system databases)"
    echo "  - Permission issues (grant db_datareader to monitoring user)"
    echo "  - Collection script errors (check /tmp/grafana-init.log)"
else
    echo "✓ Data collection verified"
fi
echo ""

# =============================================
# Step 5: Restart Grafana
# =============================================

echo "Step 5: Restarting Grafana..."
echo ""

# Check if docker-compose is available
if ! command -v docker &> /dev/null; then
    echo "⚠️  WARNING: Docker not found"
    echo "Manually restart Grafana container to apply changes"
    echo ""
else
    # Check if in project root
    if [ ! -f "docker-compose.yml" ]; then
        echo "⚠️  WARNING: docker-compose.yml not found"
        echo "Run from project root directory, or manually restart Grafana"
        echo ""
    else
        echo "Restarting Grafana container..."
        if docker compose restart grafana; then
            echo "  ✓ Grafana restarted"
        else
            echo "❌ ERROR: Failed to restart Grafana"
            echo "Manually restart: docker compose restart grafana"
        fi
    fi
fi
echo ""

# =============================================
# Step 6: Instructions for setting home page
# =============================================

echo "Step 6: Set Landing Page as Grafana Home"
echo ""
echo "Option 1: Via Grafana UI (Easiest)"
echo "  1. Open http://localhost:9002"
echo "  2. Login: admin / Admin123!"
echo "  3. Click gear icon (⚙️) → Preferences"
echo "  4. Home Dashboard: Select 'SQL Monitor - Home'"
echo "  5. Click Save"
echo ""
echo "Option 2: Already configured in docker-compose.yml"
echo "  - Environment variable set"
echo "  - Should work after Grafana restart"
echo "  - If not, use Option 1"
echo ""

# =============================================
# Summary
# =============================================

echo "========================================="
echo "Setup Complete!"
echo "========================================="
echo ""
echo "Next Steps:"
echo ""
echo "1. Open Grafana: http://localhost:9002"
echo "   - Should show arcTrade branded landing page"
echo ""
echo "2. Navigate to Table Browser dashboard"
echo "   - Database dropdown should show $DB_COUNT database(s)"
echo "   - Select a database to view tables"
echo ""
echo "3. Navigate to Code Browser dashboard"
echo "   - Should show procedures, functions, views"
echo "   - Total objects: $CODE_COUNT"
echo ""
echo "4. If landing page not showing:"
echo "   - Preferences → Home Dashboard → SQL Monitor - Home"
echo ""
echo "Troubleshooting:"
echo "  - Full log: /tmp/grafana-init.log"
echo "  - Setup guide: GRAFANA-DATA-SETUP.md"
echo ""
