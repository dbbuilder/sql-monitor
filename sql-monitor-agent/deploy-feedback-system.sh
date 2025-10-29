#!/bin/bash
# =============================================
# File: deploy-feedback-system.sh
# Purpose: Deploy feedback system with identity seed pattern
# Created: 2025-10-27
# =============================================

set -e  # Exit on error

SERVERS=("sqltest.schoolvision.net,14333" "svweb,14333" "suncity.schoolvision.net,14333")
USER="sv"
PASS="Gv51076!"
DB="DBATools"

echo "=========================================="
echo "Deploying Feedback System with Identity Seed Pattern"
echo "=========================================="
echo ""
echo "Pattern:"
echo "  - System-seeded data: IDs 1 - 999,999,999"
echo "  - User-created data:  IDs 1,000,000,000+"
echo ""
echo "This ensures safe reseeding without affecting user customizations."
echo "=========================================="
echo ""

for SERVER in "${SERVERS[@]}"; do
    echo "=== Deploying to $SERVER ==="
    echo ""

    echo "Step 1: Creating infrastructure (tables, function)..."
    sleep 3
    sqlcmd -S "$SERVER" -U "$USER" -P "$PASS" -C -d "$DB" \
        -i /mnt/e/Downloads/sql_monitor/13_create_feedback_system.sql \
        2>&1 | tail -20

    echo ""
    echo "Step 2: Seeding/reseeding data (preserves user data >= 1B)..."
    sleep 3
    sqlcmd -S "$SERVER" -U "$USER" -P "$PASS" -C -d "$DB" \
        -i /mnt/e/Downloads/sql_monitor/13b_seed_feedback_rules.sql \
        2>&1 | tail -30

    echo ""
    echo "Step 3: Enhancing DBA_DailyHealthOverview procedure..."
    sleep 3
    sqlcmd -S "$SERVER" -U "$USER" -P "$PASS" -C -d "$DB" \
        -i /mnt/e/Downloads/sql_monitor/14_enhance_daily_overview_with_feedback.sql \
        2>&1 | tail -20

    echo ""
    echo "✅ $SERVER deployment complete"
    echo "=========================================="
    echo ""
    sleep 2
done

echo ""
echo "=========================================="
echo "Deployment Summary"
echo "=========================================="
echo ""

for SERVER in "${SERVERS[@]}"; do
    echo "=== $SERVER ==="
    sqlcmd -S "$SERVER" -U "$USER" -P "$PASS" -C -d "$DB" -h -1 -Q "
        SELECT
            'Metadata: ' + CAST(COUNT(*) AS VARCHAR(10)) + ' records (' +
            CAST(SUM(CASE WHEN MetadataID < 1000000000 THEN 1 ELSE 0 END) AS VARCHAR(10)) + ' system, ' +
            CAST(SUM(CASE WHEN MetadataID >= 1000000000 THEN 1 ELSE 0 END) AS VARCHAR(10)) + ' user)'
        FROM DBATools.dbo.FeedbackMetadata
        UNION ALL
        SELECT
            'Rules: ' + CAST(COUNT(*) AS VARCHAR(10)) + ' records (' +
            CAST(SUM(CASE WHEN FeedbackRuleID < 1000000000 THEN 1 ELSE 0 END) AS VARCHAR(10)) + ' system, ' +
            CAST(SUM(CASE WHEN FeedbackRuleID >= 1000000000 THEN 1 ELSE 0 END) AS VARCHAR(10)) + ' user)'
        FROM DBATools.dbo.FeedbackRule
    " 2>&1
    echo ""
done

echo "=========================================="
echo "✅ All servers deployed successfully"
echo "=========================================="
echo ""
echo "Usage:"
echo "  EXEC DBA_DailyHealthOverview @TopSlowQueries = 20, @TopMissingIndexes = 20"
echo ""
echo "To customize feedback (creates user data with ID >= 1B):"
echo "  INSERT INTO DBATools.dbo.FeedbackRule (...) VALUES (...)"
echo "  -- Identity will auto-assign ID >= 1,000,000,000"
echo ""
