#!/bin/bash
# =============================================
# File: generate-html-report.sh
# Purpose: Generate HTML health report and serve/email it
# Created: 2025-10-27
# Updated: 2025-10-27 - Use PowerShell for reliable export
# =============================================

set -e

# Configuration
SERVER="${1:-sqltest.schoolvision.net,14333}"
USER="${2:-sv}"
PASS="${3:-Gv51076!}"
OUTPUT_DIR="./reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="$OUTPUT_DIR/health_report_${TIMESTAMP}.html"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

echo "=========================================="
echo "SQL Server Health Report Generator"
echo "=========================================="
echo ""
echo "Server: $SERVER"
echo "Output: $REPORT_FILE"
echo ""

# Check if PowerShell is available
if command -v pwsh >/dev/null 2>&1; then
    echo "Generating HTML report using PowerShell..."
    echo ""

    # Use PowerShell script for reliable export
    pwsh -File "$(dirname "$0")/Export-HealthReportHTML.ps1" \
        -Server "$SERVER" \
        -User "$USER" \
        -Password "$PASS" \
        -OutputPath "$REPORT_FILE" <<< "N"

    # PowerShell script creates the file directly
else
    echo "⚠️  PowerShell not found. Using fallback method..."
    echo "Note: sqlcmd may truncate large output. Install PowerShell for best results."
    echo ""

    # Fallback to sqlcmd (may truncate)
    sqlcmd -S "$SERVER" -U "$USER" -P "$PASS" -C -d DBATools -y 0 -Q "
    SET NOCOUNT ON
    EXEC DBATools.dbo.DBA_DailyHealthOverview_HTML
        @TopSlowQueries = 20,
        @TopMissingIndexes = 20,
        @HoursBackForIssues = 48
    " -o "$REPORT_FILE" 2>&1
fi

# Check if report was generated
if [ ! -f "$REPORT_FILE" ]; then
    echo "ERROR: Failed to generate report"
    exit 1
fi

# Get file size
FILE_SIZE=$(du -h "$REPORT_FILE" | cut -f1)
CHAR_COUNT=$(wc -c < "$REPORT_FILE")

echo ""
if [ "$CHAR_COUNT" -gt 60000 ]; then
    echo "✅ Report generated successfully"
else
    echo "⚠️  Report may be incomplete (sqlcmd truncation)"
    echo "   Install PowerShell Core for full export: https://aka.ms/install-powershell"
fi
echo "   File: $REPORT_FILE"
echo "   Size: $FILE_SIZE ($CHAR_COUNT characters)"
echo ""

# Offer options
echo "What would you like to do with the report?"
echo ""
echo "1) Serve via HTTP server (default port 8000)"
echo "2) Send via email"
echo "3) Just view file path"
echo "4) Open in browser (WSL only)"
echo ""
read -p "Enter choice (1-4) [default: 3]: " CHOICE
CHOICE=${CHOICE:-3}

case $CHOICE in
    1)
        echo ""
        echo "Starting Python HTTP server..."
        echo "Report will be available at: http://localhost:8000/$(basename $REPORT_FILE)"
        echo ""
        echo "Press Ctrl+C to stop server"
        echo ""
        cd "$OUTPUT_DIR"
        python3 -m http.server 8000
        ;;

    2)
        echo ""
        read -p "Enter recipient email address: " EMAIL_TO
        read -p "Enter subject [default: SQL Server Health Report]: " EMAIL_SUBJECT
        EMAIL_SUBJECT=${EMAIL_SUBJECT:-"SQL Server Health Report"}

        # Check if mail command is available
        if ! command -v mail &> /dev/null; then
            echo ""
            echo "WARNING: 'mail' command not found. Installing mailutils..."
            echo ""
            sudo apt-get update && sudo apt-get install -y mailutils
        fi

        # Send email with HTML attachment
        echo "Sending email to $EMAIL_TO..."
        cat "$REPORT_FILE" | mail -s "$(echo -e "$EMAIL_SUBJECT\nContent-Type: text/html")" "$EMAIL_TO"

        echo ""
        echo "✅ Email sent to $EMAIL_TO"
        ;;

    3)
        echo ""
        echo "Report saved to: $REPORT_FILE"
        echo ""
        echo "To view:"
        echo "  - Open file in web browser"
        echo "  - Or serve via: python3 -m http.server 8000 (in $OUTPUT_DIR)"
        ;;

    4)
        echo ""
        echo "Opening in default browser..."

        # Convert WSL path to Windows path
        WINDOWS_PATH=$(wslpath -w "$REPORT_FILE")
        cmd.exe /c start "$WINDOWS_PATH"

        echo "✅ Report opened in browser"
        ;;

    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "Done"
echo "=========================================="
