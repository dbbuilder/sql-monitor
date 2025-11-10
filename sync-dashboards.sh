#!/bin/bash
# Sync dashboards from source to public folder
# This ensures GitHub-hosted dashboards match the provisioned ones

set -e

echo "=========================================="
echo "DASHBOARD SYNC SCRIPT"
echo "=========================================="
echo ""

SOURCE_DIR="dashboards/grafana/dashboards"
TARGET_DIR="public/dashboards"
BUILD_TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

echo "Source: $SOURCE_DIR"
echo "Target: $TARGET_DIR"
echo "Build Timestamp: $BUILD_TIMESTAMP"
echo ""

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "ERROR: Source directory not found: $SOURCE_DIR"
    exit 1
fi

# Create target directory if it doesn't exist
mkdir -p "$TARGET_DIR"

# Copy all dashboard JSON files
echo "Copying dashboards..."
COPIED_COUNT=0

for dashboard in "$SOURCE_DIR"/*.json; do
    if [ -f "$dashboard" ]; then
        filename=$(basename "$dashboard")
        echo "  - $filename"

        # Add build timestamp to dashboard title
        if command -v jq &> /dev/null; then
            jq --arg bt "$BUILD_TIMESTAMP" \
                'if .title then .title = (.title | gsub(" \\(Build: [^)]+\\)$"; "")) + " (Build: " + $bt + ")" else . end' \
                "$dashboard" > "$TARGET_DIR/$filename"
        else
            # Fallback: just copy without timestamp if jq not available
            cp "$dashboard" "$TARGET_DIR/$filename"
        fi

        COPIED_COUNT=$((COPIED_COUNT + 1))
    fi
done

echo ""
echo "=========================================="
echo "SYNC COMPLETE"
echo "=========================================="
echo "Copied: $COPIED_COUNT dashboards"
echo "Build Timestamp: $BUILD_TIMESTAMP"
echo ""
echo "Next steps:"
echo "  1. git add public/dashboards/"
echo "  2. git commit -m \"Update dashboards (Build: $BUILD_TIMESTAMP)\""
echo "  3. git push origin main"
echo ""
