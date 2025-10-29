#!/bin/bash

# P2 Collector Testing Script
# Tests each P2 collector with 10-second timeout

SERVER="svweb"
PORT="14333"
USER="sv"
PASSWORD="Gv51076!"
DATABASE="DBATools"

echo "=========================================="
echo "P2 Collector Performance Test"
echo "Testing each collector with 10s timeout"
echo "=========================================="
echo ""

# Create test snapshot run
echo "Creating test PerfSnapshotRunID..."
TEST_RUN_ID=$(sqlcmd -S $SERVER,$PORT -U $USER -P "$PASSWORD" -C -d $DATABASE -h -1 -Q "SET NOCOUNT ON; DECLARE @ID BIGINT; INSERT INTO PerfSnapshotRun (SnapshotUTC, ServerName, SqlVersion) VALUES (SYSUTCDATETIME(), @@SERVERNAME, CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(200))); SET @ID = SCOPE_IDENTITY(); SELECT @ID" 2>&1 | tr -d '[:space:]')

if [ -z "$TEST_RUN_ID" ] || [ "$TEST_RUN_ID" = "0" ]; then
    echo "ERROR: Failed to create test run"
    exit 1
fi

echo "Test PerfSnapshotRunID: $TEST_RUN_ID"
echo ""
echo "Starting P2 collector tests..."
echo "----------------------------------------"

# Function to test a collector
test_collector() {
    local collector_name=$1
    local start_time=$(date +%s%3N)

    timeout 10 sqlcmd -S $SERVER,$PORT -U $USER -P "$PASSWORD" -C -d $DATABASE -Q "EXEC $collector_name $TEST_RUN_ID, 0" > /tmp/collector_${collector_name}.log 2>&1
    local exit_code=$?
    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))

    if [ $exit_code -eq 124 ]; then
        echo "[TIMEOUT] $collector_name: >10000 ms (HUNG)"
    elif [ $exit_code -eq 0 ]; then
        echo "[OK] $collector_name: ${duration} ms"
    else
        echo "[ERROR] $collector_name: Exit code $exit_code (${duration} ms)"
        cat /tmp/collector_${collector_name}.log
    fi
}

# Test P2 collectors
test_collector "DBA_Collect_P2_ServerConfig"
test_collector "DBA_Collect_P2_VLFCounts"
test_collector "DBA_Collect_P2_DeadlockDetails"
test_collector "DBA_Collect_P2_SchedulerHealth"
test_collector "DBA_Collect_P2_PerfCounters"
test_collector "DBA_Collect_P2_AutogrowthEvents"

echo ""
echo "----------------------------------------"
echo "All P2 tests complete!"
echo ""

# Cleanup
echo "Cleaning up test data..."
sqlcmd -S $SERVER,$PORT -U $USER -P "$PASSWORD" -C -d $DATABASE -Q "
DELETE FROM dbo.PerfSnapshotServerConfig WHERE PerfSnapshotRunID = $TEST_RUN_ID;
DELETE FROM dbo.PerfSnapshotVLFCounts WHERE PerfSnapshotRunID = $TEST_RUN_ID;
DELETE FROM dbo.PerfSnapshotDeadlockDetails WHERE PerfSnapshotRunID = $TEST_RUN_ID;
DELETE FROM dbo.PerfSnapshotSchedulerHealth WHERE PerfSnapshotRunID = $TEST_RUN_ID;
DELETE FROM dbo.PerfSnapshotPerfCounters WHERE PerfSnapshotRunID = $TEST_RUN_ID;
DELETE FROM dbo.PerfSnapshotAutogrowthEvents WHERE PerfSnapshotRunID = $TEST_RUN_ID;
DELETE FROM dbo.PerfSnapshotRun WHERE PerfSnapshotRunID = $TEST_RUN_ID;
" > /dev/null 2>&1

echo "Test data cleaned up."
echo "=========================================="

# Cleanup temp files
rm -f /tmp/collector_*.log
