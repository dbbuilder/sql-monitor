#!/bin/bash
# =====================================================
# SQL Monitor - Google Cloud Run Deployment Script
# =====================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/deployment-config.yaml}"

# Load configuration (requires yq or python)
if command -v yq &> /dev/null; then
    PROJECT_ID=$(yq eval '.registry.gcr.project_id' "$CONFIG_FILE")
    SERVICE_NAME=$(yq eval '.gcp.cloud_run.service_name' "$CONFIG_FILE")
    REGION=$(yq eval '.gcp.cloud_run.region' "$CONFIG_FILE")
    GCR_REPO=$(yq eval '.registry.gcr.repository' "$CONFIG_FILE")
    CPU=$(yq eval '.gcp.cloud_run.cpu' "$CONFIG_FILE")
    MEMORY=$(yq eval '.gcp.cloud_run.memory' "$CONFIG_FILE")
    MIN_INSTANCES=$(yq eval '.gcp.cloud_run.min_instances' "$CONFIG_FILE")
    MAX_INSTANCES=$(yq eval '.gcp.cloud_run.max_instances' "$CONFIG_FILE")
else
    echo "ERROR: yq required. Install with: brew install yq (or apt/yum)"
    exit 1
fi

IMAGE="gcr.io/${PROJECT_ID}/${GCR_REPO}:latest"

echo "==================================================================="
echo "SQL Monitor - Google Cloud Run Deployment"
echo "==================================================================="
echo "Project: $PROJECT_ID"
echo "Service: $SERVICE_NAME"
echo "Region: $REGION"
echo "Image: $IMAGE"
echo "==================================================================="

# =====================================================
# Build and Push Docker Image
# =====================================================

echo "Building Docker image..."
cd "$SCRIPT_DIR/.."
docker build -f deployment/Dockerfile.grafana -t sql-monitor-grafana:latest .

echo "Tagging image for GCR..."
docker tag sql-monitor-grafana:latest "$IMAGE"

echo "Configuring Docker for GCR..."
gcloud auth configure-docker

echo "Pushing image to GCR..."
docker push "$IMAGE"

# =====================================================
# Get Secrets from Secret Manager
# =====================================================

echo "Retrieving secrets..."
SECRET_PROJECT=$(yq eval '.gcp.secrets.project_id' "$CONFIG_FILE")
MONITORINGDB_PASSWORD_SECRET=$(yq eval '.gcp.secrets.monitoringdb_password_secret' "$CONFIG_FILE")
GRAFANA_PASSWORD_SECRET=$(yq eval '.gcp.secrets.grafana_password_secret' "$CONFIG_FILE")

# =====================================================
# Deploy to Cloud Run
# =====================================================

echo "Deploying to Cloud Run..."

gcloud run deploy "$SERVICE_NAME" \
    --image "$IMAGE" \
    --platform managed \
    --region "$REGION" \
    --project "$PROJECT_ID" \
    --cpu "$CPU" \
    --memory "$MEMORY" \
    --min-instances "$MIN_INSTANCES" \
    --max-instances "$MAX_INSTANCES" \
    --port 3000 \
    --allow-unauthenticated \
    --set-env-vars "\
MONITORINGDB_SERVER=$(yq eval '.monitoringdb.server' "$CONFIG_FILE"),\
MONITORINGDB_PORT=$(yq eval '.monitoringdb.port' "$CONFIG_FILE"),\
MONITORINGDB_DATABASE=$(yq eval '.monitoringdb.database' "$CONFIG_FILE"),\
MONITORINGDB_USER=$(yq eval '.monitoringdb.username' "$CONFIG_FILE"),\
DASHBOARD_DOWNLOAD=$(yq eval '.grafana.dashboards.download_from_github' "$CONFIG_FILE"),\
GITHUB_REPO=$(yq eval '.grafana.dashboards.github_repo' "$CONFIG_FILE")" \
    --set-secrets "\
MONITORINGDB_PASSWORD=${MONITORINGDB_PASSWORD_SECRET}:latest,\
GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD_SECRET}:latest"

# Get service URL
SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
    --platform managed \
    --region "$REGION" \
    --project "$PROJECT_ID" \
    --format="value(status.url)")

echo "==================================================================="
echo "Deployment Complete!"
echo "==================================================================="
echo "Service URL: $SERVICE_URL"
echo ""
echo "Check status:"
echo "  gcloud run services describe $SERVICE_NAME --region $REGION"
echo ""
echo "View logs:"
echo "  gcloud logging read \"resource.type=cloud_run_revision AND resource.labels.service_name=$SERVICE_NAME\" --limit 50"
echo "==================================================================="
