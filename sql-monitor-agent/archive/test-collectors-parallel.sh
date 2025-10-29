#!/bin/bash

# Parallel Collector Testing Script
# Tests each collector with 15-second timeout to identify slow ones

SERVER="svweb"
PORT="14333"
USER="sv"
PASSWORD="Gv51076!"
DATABASE="DBATools"

echo "=========================================="
echo "Parallel Collector Performance Test"
echo "Testing each collector with 15s timeout"
echo "=========================================="
echo ""

# Create test snapshot run
echo "Creating test PerfSnapshotRunID..."
TEST_RUN_ID=$(sqlcmd -S $SERVER,$PORT -U $USER -P "$PASSWORD" -C -d $DATABASE -h -1 -Q "SET NOCOUNT ON; DECLARE @ID BIGINT; INSERT INTO PerfSnapshotRun (SnapshotUTC, ServerName) VALUES (SYSUTCDATETIME(), @@SERVERNAME); SET @ID = SCOPE_IDENTITY(); SELECT @ID" 2>&1 | tr -d '[:space:]')

if [ -z "$TEST_RUN_ID" ] || [ "$TEST_RUN_ID" = "0" ]; then
    echo "ERROR: Failed to create test run"
    exit 1
fi

echo "Test PerfSnapshotRunID: $TEST_RUN_ID"
echo ""
echo "Starting parallel collector tests..."
echo "----------------------------------------"

# Array to hold background process IDs
declare -A PIDS
declare -A START_TIMES

# Function to test a collector
test_collector() {
    local collector_name=$1
    local start_time=$(date +%s%3N)

    timeout 15 sqlcmd -S $SERVER,$PORT -U $USER -P "$PASSWORD" -C -d $DATABASE -Q "EXEC $collector_name $TEST_RUN_ID, 0" > /tmp/collector_${collector_name}.log 2>&1
    local exit_code=$?
    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))

    if [ $exit_code -eq 124 ]; then
        echo "[TIMEOUT] $collector_name: >15000 ms (HUNG)"
    elif [ $exit_code -eq 0 ]; then
        echo "[OK] $collector_name: ${duration} ms"
    else
        echo "[ERROR] $collector_name: Exit code $exit_code (${duration} ms)"
        cat /tmp/collector_${collector_name}.log
    fi
}

# Launch all collectors in parallel
echo "Launching collectors in background..."

test_collector "DBA_Collect_P0_QueryStats" &
PIDS[P0_QueryStats]=$!

test_collector "DBA_Collect_P0_IOStats" &
PIDS[P0_IOStats]=$!

test_collector "DBA_Collect_P0_Memory" &
PIDS[P0_Memory]=$!

test_collector "DBA_Collect_P0_BackupHistory" &
PIDS[P0_BackupHistory]=$!

test_collector "DBA_Collect_P1_IndexUsage" &
PIDS[P1_IndexUsage]=$!

test_collector "DBA_Collect_P1_MissingIndexes" &
PIDS[P1_MissingIndexes]=$!

test_collector "DBA_Collect_P1_WaitStats" &
PIDS[P1_WaitStats]=$!

test_collector "DBA_Collect_P1_TempDBContention" &
PIDS[P1_TempDBContention]=$!

test_collector "DBA_Collect_P1_QueryPlans" &
PIDS[P1_QueryPlans]=$!

# Wait for all background jobs to complete
echo ""
echo "Waiting for all collectors to complete (max 15 seconds)..."
wait

echo ""
echo "----------------------------------------"
echo "All tests complete!"
echo ""

# Cleanup
echo "Cleaning up test data..."
sqlcmd -S $SERVER,$PORT -U $USER -P "$PASSWORD" -C -d $DATABASE -Q "
DELETE FROM dbo.PerfSnapshotQueryStats WHERE PerfSnapshotRunID = $TEST_RUN_ID;
DELETE FROM dbo.PerfSnapshotIOStats WHERE PerfSnapshotRunID = $TEST_RUN_ID;
DELETE FROM dbo.PerfSnapshotMemory WHERE PerfSnapshotRunID = $TEST_RUN_ID;
DELETE FROM dbo.PerfSnapshotBackupHistory WHERE PerfSnapshotRunID = $TEST_RUN_ID;
DELETE FROM dbo.PerfSnapshotIndexUsage WHERE PerfSnapshotRunID = $TEST_RUN_ID;
DELETE FROM dbo.PerfSnapshotMissingIndexes WHERE PerfSnapshotRunID = $TEST_RUN_ID;
DELETE FROM dbo.PerfSnapshotWaitStats WHERE PerfSnapshotRunID = $TEST_RUN_ID;
DELETE FROM dbo.PerfSnapshotTempDBContention WHERE PerfSnapshotRunID = $TEST_RUN_ID;
DELETE FROM dbo.PerfSnapshotQueryPlans WHERE PerfSnapshotRunID = $TEST_RUN_ID;
DELETE FROM dbo.PerfSnapshotRun WHERE PerfSnapshotRunID = $TEST_RUN_ID;
" > /dev/null 2>&1

echo "Test data cleaned up."
echo "=========================================="

# Cleanup temp files
rm -f /tmp/collector_*.log
