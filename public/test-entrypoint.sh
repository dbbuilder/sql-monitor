#!/bin/bash
# Minimal test entrypoint - no dashboard downloads
echo "=========================================="
echo "MINIMAL TEST ENTRYPOINT"
echo "=========================================="
date
echo "Environment variables present: $(env | grep -c MONITORINGDB || echo 0)"
echo "Starting Grafana directly..."
exec /run.sh
