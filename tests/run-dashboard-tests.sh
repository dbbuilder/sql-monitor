#!/bin/bash
# Comprehensive dashboard test runner
# Generates multiple report formats and provides detailed analysis

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          SQL Monitor Dashboard Validation Tests           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Activate virtual environment
if [ ! -d "venv" ]; then
    echo -e "${YELLOW}Creating virtual environment...${NC}"
    python3 -m venv venv
fi

echo -e "${GREEN}Activating virtual environment...${NC}"
source venv/bin/activate

# Install dependencies
if [ ! -f "venv/installed.marker" ]; then
    echo -e "${YELLOW}Installing dependencies...${NC}"
    pip install -r requirements.txt --quiet
    touch venv/installed.marker
fi

# Create reports directory
REPORTS_DIR="$SCRIPT_DIR/reports"
mkdir -p "$REPORTS_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HTML_REPORT="$REPORTS_DIR/dashboard-tests-$TIMESTAMP.html"
JSON_REPORT="$REPORTS_DIR/dashboard-tests-$TIMESTAMP.json"

echo -e "${GREEN}Running tests...${NC}"
echo ""

# Run pytest with multiple report formats
pytest test_dashboards.py \
    -v \
    --html="$HTML_REPORT" \
    --self-contained-html \
    --json-report \
    --json-report-file="$JSON_REPORT" \
    --tb=short \
    --color=yes \
    | tee "$REPORTS_DIR/test-output-$TIMESTAMP.log"

# Check test results
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                 ALL TESTS PASSED ✅                        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
else
    echo ""
    echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                 SOME TESTS FAILED ❌                       ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
fi

echo ""
echo -e "${BLUE}Reports generated:${NC}"
echo -e "  📄 HTML: ${HTML_REPORT}"
echo -e "  📊 JSON: ${JSON_REPORT}"
echo -e "  📝 Log:  $REPORTS_DIR/test-output-$TIMESTAMP.log"
echo ""

# Generate summary
echo -e "${BLUE}Generating summary report...${NC}"
python3 << 'EOF'
import json
import sys
from pathlib import Path
from collections import defaultdict

# Load JSON report
reports_dir = Path("reports")
json_files = sorted(reports_dir.glob("dashboard-tests-*.json"))

if not json_files:
    print("No test reports found")
    sys.exit(0)

latest_report = json_files[-1]

with open(latest_report) as f:
    data = json.load(f)

# Analyze results
summary = data.get('summary', {})
tests = data.get('tests', [])

total = summary.get('total', 0)
passed = summary.get('passed', 0)
failed = summary.get('failed', 0)

print(f"\n📊 Test Summary:")
print(f"   Total Tests: {total}")
print(f"   Passed: {passed} ({passed/total*100:.1f}%)")
print(f"   Failed: {failed} ({failed/total*100:.1f}%)")
print()

# Group failures by dashboard
if failed > 0:
    failures_by_dashboard = defaultdict(list)

    for test in tests:
        if test.get('outcome') == 'failed':
            # Extract dashboard name from test nodeid
            nodeid = test.get('nodeid', '')
            if '::' in nodeid:
                parts = nodeid.split('::')
                dashboard_info = parts[-1] if len(parts) > 1 else 'Unknown'
                dashboard_name = dashboard_info.split('::')[0] if '::' in dashboard_info else dashboard_info
                failures_by_dashboard[dashboard_name].append(test)

    print("❌ Failures by Dashboard:")
    for dashboard, failed_tests in sorted(failures_by_dashboard.items(), key=lambda x: len(x[1]), reverse=True):
        print(f"   - {dashboard}: {len(failed_tests)} failed")

EOF

echo ""
echo -e "${GREEN}Test run complete!${NC}"
echo ""
