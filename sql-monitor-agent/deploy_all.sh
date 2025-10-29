#!/bin/bash

# =============================================
# Complete SQL Server Monitoring System Deployment
# Deploys all components in correct order
# =============================================

SERVER="svweb"
PORT="14333"
USER="sv"
PASSWORD="Gv51076!"
DATABASE="DBATools"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "SQL Server Monitoring System Deployment"
echo "=========================================="
echo "Server: $SERVER,$PORT"
echo "Database: $DATABASE"
echo ""

# Function to execute SQL file
execute_sql() {
    local step_num=$1
    local description=$2
    local sql_file=$3
    local database=${4:-"master"}  # Default to master for database creation

    echo -e "${BLUE}[$step_num]${NC} $description"
    echo "  File: $sql_file"
    echo -n "  Executing... "

    if [ "$database" = "master" ]; then
        sqlcmd -S $SERVER,$PORT -U $USER -P $PASSWORD -C -i "$sql_file" > /tmp/deploy_${step_num}.log 2>&1
    else
        sqlcmd -S $SERVER,$PORT -U $USER -P $PASSWORD -C -d "$database" -i "$sql_file" > /tmp/deploy_${step_num}.log 2>&1
    fi

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}SUCCESS${NC}"
        return 0
    else
        echo -e "${RED}FAILED${NC}"
        echo ""
        echo "  Error output:"
        tail -20 /tmp/deploy_${step_num}.log | sed 's/^/    /'
        echo ""
        return 1
    fi
}

# Function to verify step
verify_step() {
    local step_num=$1
    local description=$2
    local verification_sql=$3

    echo -n "  Verifying... "

    result=$(sqlcmd -S $SERVER,$PORT -U $USER -P $PASSWORD -C -d $DATABASE -h -1 -Q "SET NOCOUNT ON; $verification_sql" 2>&1 | tr -d '[:space:]')

    if [ ! -z "$result" ] && [ "$result" != "0" ]; then
        echo -e "${GREEN}OK${NC} ($result)"
        return 0
    else
        echo -e "${YELLOW}WARNING${NC} (no results or zero count)"
        return 1
    fi
}

# Check prerequisites
echo "Checking prerequisites..."
echo -n "  Network connectivity: "
if ping -c 1 -W 2 $SERVER > /dev/null 2>&1; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    echo "Cannot reach server $SERVER"
    exit 1
fi

echo -n "  SQL Server reachable: "
if sqlcmd -S $SERVER,$PORT -U $USER -P $PASSWORD -C -Q "SELECT 1" > /dev/null 2>&1; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    echo "Cannot connect to SQL Server"
    exit 1
fi

echo ""
echo "Starting deployment..."
echo "----------------------------------------"
echo ""

# Step 1: Create database and base tables
execute_sql "01" "Create DBATools database and base tables" \
    "01_create_DBATools_and_tables.sql" "master" || exit 1
verify_step "01" "Tables created" \
    "SELECT COUNT(*) FROM sys.tables WHERE name IN ('LogEntry','PerfSnapshotRun','PerfSnapshotDB','PerfSnapshotWorkload','PerfSnapshotErrorLog')"
echo ""

# Step 2: Create logging infrastructure
execute_sql "02" "Create logging infrastructure" \
    "02_create_DBA_LogEntry_Insert.sql" "$DATABASE" || exit 1
verify_step "02" "Logging procedure created" \
    "SELECT COUNT(*) FROM sys.procedures WHERE name = 'DBA_LogEntry_Insert'"
echo ""

# Step 3: Create config system
execute_sql "03" "Create configuration system" \
    "13_create_config_table_and_functions.sql" "$DATABASE" || exit 1
verify_step "03" "Config created" \
    "SELECT COUNT(*) FROM dbo.MonitoringConfig"
echo ""

# Step 4: Create database filter view
execute_sql "04" "Create database filter view" \
    "13b_create_database_filter_view.sql" "$DATABASE" || exit 1
verify_step "04" "Filter view created" \
    "SELECT COUNT(*) FROM dbo.vw_MonitoredDatabases"
echo ""

# Step 5: Create enhanced tables
execute_sql "05" "Create enhanced snapshot tables (P0/P1/P2/P3)" \
    "05_create_enhanced_tables.sql" "$DATABASE" || exit 1
verify_step "05" "Enhanced tables created" \
    "SELECT COUNT(*) FROM sys.tables WHERE name LIKE 'PerfSnapshot%'"
echo ""

# Step 6: Create P0 collectors
execute_sql "06" "Create P0 (Critical) collectors" \
    "06_create_modular_collectors_P0_FIXED.sql" "$DATABASE" || exit 1
verify_step "06" "P0 collectors created" \
    "SELECT COUNT(*) FROM sys.procedures WHERE name LIKE 'DBA_Collect_P0%'"
echo ""

# Step 7: Create P1 collectors
execute_sql "07" "Create P1 (Performance) collectors" \
    "07_create_modular_collectors_P1_FIXED.sql" "$DATABASE" || exit 1
verify_step "07" "P1 collectors created" \
    "SELECT COUNT(*) FROM sys.procedures WHERE name LIKE 'DBA_Collect_P1%'"
echo ""

# Step 8: Create P2/P3 collectors
execute_sql "08" "Create P2/P3 (Medium/Low) collectors" \
    "08_create_modular_collectors_P2_P3_FIXED.sql" "$DATABASE" || exit 1
verify_step "08" "P2 collectors created" \
    "SELECT COUNT(*) FROM sys.procedures WHERE name LIKE 'DBA_Collect_P2%'"
echo ""

# Step 9: Create master orchestrator
execute_sql "09" "Create master orchestrator" \
    "10_create_master_orchestrator_FIXED.sql" "$DATABASE" || exit 1
verify_step "09" "Orchestrator created" \
    "SELECT COUNT(*) FROM sys.procedures WHERE name = 'DBA_CollectPerformanceSnapshot'"
echo ""

# Step 10: Create reporting procedures
execute_sql "10" "Create reporting procedures" \
    "14_create_reporting_procedures.sql" "$DATABASE" || exit 1
verify_step "10" "Reporting procedures created" \
    "SELECT COUNT(*) FROM sys.procedures WHERE name LIKE 'DBA_%' AND name NOT LIKE 'DBA_Collect%' AND name NOT LIKE 'DBA_LogEntry%'"
echo ""

# Step 11: Create retention policy
execute_sql "11" "Create retention policy procedure" \
    "create_retention_policy.sql" "$DATABASE" || exit 1
verify_step "11" "Retention procedure created" \
    "SELECT COUNT(*) FROM sys.procedures WHERE name = 'DBA_PurgeOldSnapshots'"
echo ""

# Step 12: Create SQL Agent job for collection
execute_sql "12" "Create SQL Agent collection job" \
    "create_agent_job.sql" "msdb" || exit 1
verify_step "12" "Collection job created" \
    "SELECT COUNT(*) FROM msdb.dbo.sysjobs WHERE name = 'DBA Collect Perf Snapshot'"
echo ""

# Step 13: Create SQL Agent job for retention
execute_sql "13" "Create SQL Agent retention job" \
    "create_retention_job.sql" "msdb" || exit 1
verify_step "13" "Retention job created" \
    "SELECT COUNT(*) FROM msdb.dbo.sysjobs WHERE name = 'DBA Purge Old Snapshots'"
echo ""

echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""

# Test collection
echo "Running test collection (P0+P1+P2)..."
echo -n "  Executing... "
start_time=$(date +%s%3N)
sqlcmd -S $SERVER,$PORT -U $USER -P $PASSWORD -C -d $DATABASE -Q "EXEC DBA_CollectPerformanceSnapshot @IncludeP0=1, @IncludeP1=1, @IncludeP2=1, @IncludeP3=0, @Debug=1" -t 60 > /tmp/test_collection.log 2>&1
exit_code=$?
end_time=$(date +%s%3N)
duration=$((end_time - start_time))

if [ $exit_code -eq 0 ]; then
    echo -e "${GREEN}SUCCESS${NC} (${duration} ms)"

    # Get run ID
    run_id=$(sqlcmd -S $SERVER,$PORT -U $USER -P $PASSWORD -C -d $DATABASE -h -1 -Q "SET NOCOUNT ON; SELECT TOP 1 PerfSnapshotRunID FROM dbo.PerfSnapshotRun ORDER BY PerfSnapshotRunID DESC" 2>&1 | tr -d '[:space:]')

    if [ ! -z "$run_id" ]; then
        echo "  Run ID: $run_id"

        # Check data collected
        echo ""
        echo "Verifying data collection..."

        tables=("PerfSnapshotQueryStats" "PerfSnapshotIOStats" "PerfSnapshotMemory" "PerfSnapshotBackupHistory"
                "PerfSnapshotIndexUsage" "PerfSnapshotMissingIndexes" "PerfSnapshotWaitStats"
                "PerfSnapshotConfig" "PerfSnapshotCounters" "PerfSnapshotSchedulers")

        for table in "${tables[@]}"; do
            count=$(sqlcmd -S $SERVER,$PORT -U $USER -P $PASSWORD -C -d $DATABASE -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.$table WHERE PerfSnapshotRunID = $run_id" 2>&1 | tr -d '[:space:]')

            if [ ! -z "$count" ] && [ "$count" != "0" ]; then
                echo -e "  $table: ${GREEN}$count rows${NC}"
            else
                echo -e "  $table: ${YELLOW}0 rows${NC}"
            fi
        done
    fi
else
    echo -e "${RED}FAILED${NC}"
    echo ""
    echo "  Error output:"
    tail -20 /tmp/test_collection.log | sed 's/^/    /'
fi

echo ""
echo "=========================================="
echo "Deployment Summary"
echo "=========================================="
echo "Database: $DATABASE"
echo "Tables: $(sqlcmd -S $SERVER,$PORT -U $USER -P $PASSWORD -C -d $DATABASE -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.tables" 2>&1 | tr -d '[:space:]')"
echo "Procedures: $(sqlcmd -S $SERVER,$PORT -U $USER -P $PASSWORD -C -d $DATABASE -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.procedures" 2>&1 | tr -d '[:space:]')"
echo "Functions: $(sqlcmd -S $SERVER,$PORT -U $USER -P $PASSWORD -C -d $DATABASE -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.objects WHERE type IN ('FN','IF','TF')" 2>&1 | tr -d '[:space:]')"
echo "Views: $(sqlcmd -S $SERVER,$PORT -U $USER -P $PASSWORD -C -d $DATABASE -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.views" 2>&1 | tr -d '[:space:]')"
echo "SQL Agent Jobs: $(sqlcmd -S $SERVER,$PORT -U $USER -P $PASSWORD -C -d msdb -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.sysjobs WHERE name LIKE 'DBA %'" 2>&1 | tr -d '[:space:]')"
echo ""
echo "Collection Schedule: Every 5 minutes (P0+P1+P2)"
echo "Retention Policy: 14 days (purged daily at 2 AM)"
echo "Expected Performance: <20 seconds per collection"
echo ""
echo "Next Steps:"
echo "  1. Review test collection results above"
echo "  2. Monitor job execution: EXEC msdb.dbo.sp_help_jobhistory @job_name='DBA Collect Perf Snapshot'"
echo "  3. View system health: EXEC DBATools.dbo.DBA_CheckSystemHealth"
echo "  4. Check backup status: EXEC DBATools.dbo.DBA_ShowBackupStatus"
echo "=========================================="

# Cleanup temp files
rm -f /tmp/deploy_*.log /tmp/test_collection.log

echo ""
echo "Deployment logs cleaned up."
echo "Deployment complete!"
