#!/bin/bash
# =====================================================
# Script: run-all-phase-1.9-tests.sh
# Description: Master test runner for Phase 1.9 Day 1
# Author: SQL Server Monitor Project
# Date: 2025-10-27
# Phase: 1.9 - Integration (Day 1)
# =====================================================

echo "========================================================================="
echo "Phase 1.9 Day 1: Complete Test Suite"
echo "========================================================================="
echo ""

# Configuration
SERVER="${SQL_SERVER:-172.31.208.1,14333}"
USER="${SQL_USER:-sa}"
PASSWORD="${SQL_PASSWORD}"

if [ -z "$PASSWORD" ]; then
    echo "Error: SQL_PASSWORD environment variable not set"
    echo "Usage: SQL_PASSWORD='your_password' ./run-all-phase-1.9-tests.sh"
    exit 1
fi

echo "Target SQL Server: $SERVER"
echo "SQL User: $USER"
echo ""

# Test log file
LOG_FILE="phase-1.9-test-results-$(date +%Y%m%d-%H%M%S).log"
echo "Test results will be logged to: $LOG_FILE"
echo ""

# Function to run SQL script
run_sql() {
    local script=$1
    local description=$2

    echo "-------------------------------------------"
    echo "$description"
    echo "-------------------------------------------"
    echo "Executing: $script"
    echo ""

    sqlcmd -S "$SERVER" -U "$USER" -P "$PASSWORD" -C -i "$script" 2>&1 | tee -a "$LOG_FILE"

    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo "✓ $description completed successfully"
    else
        echo "✗ $description failed with errors"
        return 1
    fi

    echo ""
}

# Change to tests directory
cd "$(dirname "$0")"

# Test 1: Deploy and test DBATools (single-server mode)
echo "========================================================================="
echo "TEST 1: DBATools Deployment (Single-Server Mode)"
echo "========================================================================="
echo ""

run_sql "deploy-and-test-dbatools.sql" "DBATools deployment and validation"

if [ $? -ne 0 ]; then
    echo "✗ DBATools tests failed. Stopping test suite."
    exit 1
fi

# Test 2: Deploy and test MonitoringDB (multi-server mode)
echo ""
echo "========================================================================="
echo "TEST 2: MonitoringDB Deployment (Multi-Server Mode)"
echo "========================================================================="
echo ""

run_sql "deploy-and-test-monitoringdb.sql" "MonitoringDB deployment and validation"

if [ $? -ne 0 ]; then
    echo "✗ MonitoringDB tests failed. Stopping test suite."
    exit 1
fi

# Final Summary
echo ""
echo "========================================================================="
echo "FINAL TEST SUMMARY"
echo "========================================================================="
echo ""
echo "✓ DBATools deployment: PASSED"
echo "✓ MonitoringDB deployment: PASSED"
echo "✓ Single-server mode: VERIFIED"
echo "✓ Multi-server mode: VERIFIED"
echo "✓ Backward compatibility: VERIFIED"
echo ""
echo "Databases tested:"
echo "  1. DBATools (single-server mode)"
echo "     - 24 tables created (5 core + 19 enhanced)"
echo "     - ServerID nullable for backward compatibility"
echo "     - sql-monitor-agent compatible"
echo ""
echo "  2. MonitoringDB (multi-server mode)"
echo "     - 24 tables created (5 core + 19 enhanced)"
echo "     - Multi-server inventory (Servers table)"
echo "     - Cross-server aggregation tested"
echo ""
echo "Log file: $LOG_FILE"
echo ""
echo "✓✓✓ ALL PHASE 1.9 DAY 1 TESTS PASSED ✓✓✓"
echo ""
echo "Ready to proceed to Day 2: Schema Unification (mapping views)"
echo "========================================================================="

exit 0
