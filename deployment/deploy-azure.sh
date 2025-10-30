#!/bin/bash
# =====================================================
# SQL Monitor - Azure Container Instances Deployment
# =====================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/deployment-config.yaml}"

# Load configuration (requires yq or python)
if command -v yq &> /dev/null; then
    RESOURCE_GROUP=$(yq eval '.azure.container_instances.resource_group' "$CONFIG_FILE")
    CONTAINER_NAME=$(yq eval '.azure.container_instances.container_name' "$CONFIG_FILE")
    LOCATION=$(yq eval '.azure.container_instances.location' "$CONFIG_FILE")
    ACR_NAME=$(yq eval '.registry.acr.registry_name' "$CONFIG_FILE")
    ACR_REPO=$(yq eval '.registry.acr.repository' "$CONFIG_FILE")
    CPU=$(yq eval '.azure.container_instances.cpu' "$CONFIG_FILE")
    MEMORY=$(yq eval '.azure.container_instances.memory' "$CONFIG_FILE")
    DNS_LABEL=$(yq eval '.azure.container_instances.dns_label' "$CONFIG_FILE")
else
    echo "ERROR: yq required. Install with: brew install yq (or apt/yum)"
    exit 1
fi

IMAGE="${ACR_NAME}.azurecr.io/${ACR_REPO}:latest"

echo "==================================================================="
echo "SQL Monitor - Azure Container Instances Deployment"
echo "==================================================================="
echo "Resource Group: $RESOURCE_GROUP"
echo "Container Name: $CONTAINER_NAME"
echo "Location: $LOCATION"
echo "Image: $IMAGE"
echo "==================================================================="

# =====================================================
# Build and Push Docker Image
# =====================================================

echo "Building Docker image..."
cd "$SCRIPT_DIR/.."
docker build -f deployment/Dockerfile.grafana -t sql-monitor-grafana:latest .

echo "Tagging image for ACR..."
docker tag sql-monitor-grafana:latest "$IMAGE"

echo "Logging in to ACR..."
az acr login --name "$ACR_NAME"

echo "Pushing image to ACR..."
docker push "$IMAGE"

# =====================================================
# Get Secrets from Key Vault
# =====================================================

echo "Retrieving secrets..."
KEY_VAULT=$(yq eval '.azure.secrets.key_vault_name' "$CONFIG_FILE")
MONITORINGDB_PASSWORD=$(az keyvault secret show \
    --vault-name "$KEY_VAULT" \
    --name "$(yq eval '.azure.secrets.monitoringdb_password_secret' "$CONFIG_FILE")" \
    --query value -o tsv)
GRAFANA_PASSWORD=$(az keyvault secret show \
    --vault-name "$KEY_VAULT" \
    --name "$(yq eval '.azure.secrets.grafana_password_secret' "$CONFIG_FILE")" \
    --query value -o tsv)

# Get ACR credentials
ACR_CREDS=$(az acr credential show --name "$ACR_NAME" -o json)
ACR_USERNAME=$(echo "$ACR_CREDS" | jq -r '.username')
ACR_PASSWORD=$(echo "$ACR_CREDS" | jq -r '.passwords[0].value')

# =====================================================
# Deploy Container Instance
# =====================================================

echo "Deploying container instance..."

az container create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CONTAINER_NAME" \
    --image "$IMAGE" \
    --registry-login-server "${ACR_NAME}.azurecr.io" \
    --registry-username "$ACR_USERNAME" \
    --registry-password "$ACR_PASSWORD" \
    --os-type Linux \
    --dns-name-label "$DNS_LABEL" \
    --ports 3000 \
    --cpu "$CPU" \
    --memory "$MEMORY" \
    --environment-variables \
        MONITORINGDB_SERVER="$(yq eval '.monitoringdb.server' "$CONFIG_FILE")" \
        MONITORINGDB_PORT="$(yq eval '.monitoringdb.port' "$CONFIG_FILE")" \
        MONITORINGDB_DATABASE="$(yq eval '.monitoringdb.database' "$CONFIG_FILE")" \
        MONITORINGDB_USER="$(yq eval '.monitoringdb.username' "$CONFIG_FILE")" \
        DASHBOARD_DOWNLOAD="$(yq eval '.grafana.dashboards.download_from_github' "$CONFIG_FILE")" \
        GITHUB_REPO="$(yq eval '.grafana.dashboards.github_repo' "$CONFIG_FILE")" \
    --secure-environment-variables \
        MONITORINGDB_PASSWORD="$MONITORINGDB_PASSWORD" \
        GF_SECURITY_ADMIN_PASSWORD="$GRAFANA_PASSWORD" \
    --location "$LOCATION"

# Get FQDN
FQDN=$(az container show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CONTAINER_NAME" \
    --query ipAddress.fqdn \
    --output tsv)

echo "==================================================================="
echo "Deployment Complete!"
echo "==================================================================="
echo "Access URL: http://${FQDN}:3000"
echo ""
echo "Check status:"
echo "  az container show --resource-group $RESOURCE_GROUP --name $CONTAINER_NAME"
echo ""
echo "View logs:"
echo "  az container logs --resource-group $RESOURCE_GROUP --name $CONTAINER_NAME"
echo ""
echo "SSH into container:"
echo "  az container exec --resource-group $RESOURCE_GROUP --name $CONTAINER_NAME --exec-command /bin/bash"
echo "==================================================================="
