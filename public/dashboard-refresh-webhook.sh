#!/bin/bash
# Grafana Dashboard Refresh Webhook Server
# Provides an HTTP endpoint to trigger dashboard refresh from Grafana

# Install netcat if needed: apk add --no-cache busybox-extras

PORT="${REFRESH_PORT:-8888}"
REFRESH_SCRIPT="/dashboard-refresh.sh"

echo "Starting Dashboard Refresh Webhook Server on port $PORT..."

while true; do
    # Simple HTTP server using netcat
    echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nRefreshing dashboards..." | nc -l -p $PORT -q 1

    # Trigger refresh in background
    echo "$(date): Refresh triggered via webhook"
    bash $REFRESH_SCRIPT > /var/log/dashboard-refresh.log 2>&1 &

    # Small delay to prevent rapid-fire requests
    sleep 1
done
