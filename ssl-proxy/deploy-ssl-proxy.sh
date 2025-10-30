#!/bin/bash
# =============================================
# Deploy SSL Proxy for Grafana
# =============================================

set -e

RESOURCE_GROUP="rg-sqlmonitor-schoolvision"
CONTAINER_NAME="ssl-proxy-grafana"
LOCATION="eastus"
ACR_NAME="sqlmonitoracr"

# Configuration - EDIT THESE
DOMAIN="${DOMAIN:-monitor.schoolvision.net}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-admin@schoolvision.net}"
GRAFANA_BACKEND_IP="4.156.212.48"

echo "========================================"
echo "Deploying SSL Proxy for Grafana"
echo "========================================"
echo "Domain: $DOMAIN"
echo "Email: $CERTBOT_EMAIL"
echo "Backend: $GRAFANA_BACKEND_IP:3000"
echo ""

# Build and push Docker image
echo "Building SSL proxy image..."
docker build -t $ACR_NAME.azurecr.io/ssl-proxy:latest .

echo "Pushing to Azure Container Registry..."
az acr login --name $ACR_NAME
docker push $ACR_NAME.azurecr.io/ssl-proxy:latest

# Get ACR credentials
ACR_CREDS=$(az acr credential show --name $ACR_NAME -o json)
ACR_USERNAME=$(echo "$ACR_CREDS" | jq -r '.username')
ACR_PASSWORD=$(echo "$ACR_CREDS" | jq -r '.passwords[0].value')

# Deploy container
echo "Deploying SSL proxy container..."
az container create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CONTAINER_NAME" \
    --image "$ACR_NAME.azurecr.io/ssl-proxy:latest" \
    --registry-login-server "$ACR_NAME.azurecr.io" \
    --registry-username "$ACR_USERNAME" \
    --registry-password "$ACR_PASSWORD" \
    --os-type Linux \
    --dns-name-label "sqlmonitor-ssl" \
    --ports 80 443 \
    --cpu 1 \
    --memory 1 \
    --environment-variables \
        DOMAIN="$DOMAIN" \
        CERTBOT_EMAIL="$CERTBOT_EMAIL" \
        BACKEND_IP="$GRAFANA_BACKEND_IP" \
    --location "$LOCATION"

# Get public IP
PUBLIC_IP=$(az container show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CONTAINER_NAME" \
    --query ipAddress.ip \
    --output tsv)

echo ""
echo "========================================"
echo "SSL Proxy Deployed!"
echo "========================================"
echo "Public IP: $PUBLIC_IP"
echo ""
echo "Next steps:"
echo "1. Point DNS A record: $DOMAIN → $PUBLIC_IP"
echo "2. Wait 5-10 minutes for Let's Encrypt SSL"
echo "3. Access: https://$DOMAIN"
echo ""
echo "Note: First deployment uses Let's Encrypt STAGING."
echo "      Remove --staging flag in entrypoint.sh for production certs."
echo ""
