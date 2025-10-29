#!/bin/bash

SERVER="svweb"
PORT="14333"
USER="sv"
PASSWORD="Gv51076!"
DATABASE="DBATools"

echo "=========================================="
echo "Complete Collector Test (P0/P1/P2/P3)"
echo "=========================================="
echo ""

# Create test snapshot run
echo "Creating test PerfSnapshotRunID..."
TEST_RUN_ID=$(sqlcmd -S $SERVER,$PORT -U $USER -P $PASSWORD -C -d $DATABASE -h -1 -Q "SET NOCOUNT ON; DECLARE @ID BIGINT; INSERT INTO PerfSnapshotRun (SnapshotUTC, ServerName, SqlVersion) VALUES (SYSUTCDATETIME(), @@SERVERNAME, CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(200))); SET @ID = SCOPE_IDENTITY(); SELECT @ID" 2>&1 | tr -d '[:space:]')

if [ -z "$TEST_RUN_ID" ] || [ "$TEST_RUN_ID" = "0" ]; then
    echo "ERROR: Failed to create test run"
    exit 1
fi

echo "Test PerfSnapshotRunID: $TEST_RUN_ID"
echo ""

# Function to test a collector
test_collector() {
    local collector_name=$1
    local priority=$2
    local start_time=$(date +%s%3N)

    timeout 15 sqlcmd -S $SERVER,$PORT -U $USER -P $PASSWORD -C -d $DATABASE -Q "EXEC $collector_name $TEST_RUN_ID, 0" > /tmp/collector_${collector_name}.log 2>&1
    local exit_code=$?
    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))

    if [ $exit_code -eq 124 ]; then
        echo "[$priority] [TIMEOUT] $collector_name: >15000 ms (HUNG)"
    elif [ $exit_code -eq 0 ]; then
        echo "[$priority] [OK] $collector_name: ${duration} ms"
    else
        echo "[$priority] [ERROR] $collector_name: Exit code $exit_code (${duration} ms)"
        cat /tmp/collector_${collector_name}.log | head -5
    fi
}

echo "Testing P0 collectors..."
test_collector "DBA_Collect_P0_QueryStats" "P0"
test_collector "DBA_Collect_P0_IOStats" "P0"
test_collector "DBA_Collect_P0_Memory" "P0"
test_collector "DBA_Collect_P0_BackupHistory" "P0"

echo ""
echo "Testing P1 collectors..."
test_collector "DBA_Collect_P1_IndexUsage" "P1"
test_collector "DBA_Collect_P1_MissingIndexes" "P1"
test_collector "DBA_Collect_P1_WaitStats" "P1"
test_collector "DBA_Collect_P1_TempDBContention" "P1"
test_collector "DBA_Collect_P1_QueryPlans" "P1"

echo ""
echo "Testing P2 collectors..."
test_collector "DBA_Collect_P2_ServerConfig" "P2"
test_collector "DBA_Collect_P2_VLFCounts" "P2"
test_collector "DBA_Collect_P2_DeadlockDetails" "P2"
test_collector "DBA_Collect_P2_SchedulerHealth" "P2"
test_collector "DBA_Collect_P2_PerfCounters" "P2"
test_collector "DBA_Collect_P2_AutogrowthEvents" "P2"

echo ""
echo "Testing P3 collectors..."
test_collector "DBA_Collect_P3_LatchStats" "P3"
test_collector "DBA_Collect_P3_JobHistory" "P3"
test_collector "DBA_Collect_P3_SpinlockStats" "P3"

echo ""
echo "=========================================="
echo "Verification - Checking Data Collection"
echo "=========================================="

sqlcmd -S $SERVER,$PORT -U $USER -P "$PASSWORD" -C -d $DATABASE -Q "
SELECT 'P0_QueryStats' AS TableName, COUNT(*) AS Cnt FROM dbo.PerfSnapshotQueryStats WHERE PerfSnapshotRunID = $TEST_RUN_ID
UNION ALL SELECT 'P0_IOStats', COUNT(*) FROM dbo.PerfSnapshotIOStats WHERE PerfSnapshotRunID = $TEST_RUN_ID
UNION ALL SELECT 'P0_Memory', COUNT(*) FROM dbo.PerfSnapshotMemory WHERE PerfSnapshotRunID = $TEST_RUN_ID
UNION ALL SELECT 'P0_BackupHistory', COUNT(*) FROM dbo.PerfSnapshotBackupHistory WHERE PerfSnapshotRunID = $TEST_RUN_ID
UNION ALL SELECT 'P1_IndexUsage', COUNT(*) FROM dbo.PerfSnapshotIndexUsage WHERE PerfSnapshotRunID = $TEST_RUN_ID
UNION ALL SELECT 'P1_MissingIndexes', COUNT(*) FROM dbo.PerfSnapshotMissingIndexes WHERE PerfSnapshotRunID = $TEST_RUN_ID
UNION ALL SELECT 'P1_WaitStats', COUNT(*) FROM dbo.PerfSnapshotWaitStats WHERE PerfSnapshotRunID = $TEST_RUN_ID
UNION ALL SELECT 'P1_TempDBContention', COUNT(*) FROM dbo.PerfSnapshotTempDBContention WHERE PerfSnapshotRunID = $TEST_RUN_ID
UNION ALL SELECT 'P1_QueryPlans', COUNT(*) FROM dbo.PerfSnapshotQueryPlans WHERE PerfSnapshotRunID = $TEST_RUN_ID
UNION ALL SELECT 'P2_Config', COUNT(*) FROM dbo.PerfSnapshotConfig WHERE PerfSnapshotRunID = $TEST_RUN_ID
UNION ALL SELECT 'P2_Deadlocks', COUNT(*) FROM dbo.PerfSnapshotDeadlocks WHERE PerfSnapshotRunID = $TEST_RUN_ID
UNION ALL SELECT 'P2_Schedulers', COUNT(*) FROM dbo.PerfSnapshotSchedulers WHERE PerfSnapshotRunID = $TEST_RUN_ID
UNION ALL SELECT 'P2_Counters', COUNT(*) FROM dbo.PerfSnapshotCounters WHERE PerfSnapshotRunID = $TEST_RUN_ID
UNION ALL SELECT 'P2_AutogrowthEvents', COUNT(*) FROM dbo.PerfSnapshotAutogrowthEvents WHERE PerfSnapshotRunID = $TEST_RUN_ID
UNION ALL SELECT 'P3_LatchStats', COUNT(*) FROM dbo.PerfSnapshotLatchStats WHERE PerfSnapshotRunID = $TEST_RUN_ID
UNION ALL SELECT 'P3_JobHistory', COUNT(*) FROM dbo.PerfSnapshotJobHistory WHERE PerfSnapshotRunID = $TEST_RUN_ID
UNION ALL SELECT 'P3_SpinlockStats', COUNT(*) FROM dbo.PerfSnapshotSpinlockStats WHERE PerfSnapshotRunID = $TEST_RUN_ID
ORDER BY TableName
"

# Check VLFCount in PerfSnapshotDB
echo ""
echo "Checking VLFCount updates in PerfSnapshotDB..."
sqlcmd -S $SERVER,$PORT -U $USER -P "$PASSWORD" -C -d $DATABASE -Q "
SELECT TOP 5 DatabaseName, VLFCount 
FROM dbo.PerfSnapshotDB 
WHERE PerfSnapshotRunID = $TEST_RUN_ID AND VLFCount IS NOT NULL
ORDER BY VLFCount DESC
"

echo ""
echo "=========================================="
echo "Test complete! Run ID: $TEST_RUN_ID"
echo "=========================================="

# Cleanup temp files
rm -f /tmp/collector_*.log
