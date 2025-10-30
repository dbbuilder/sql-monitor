# SQL Monitor - Azure Deployment Guide

Complete step-by-step guide for deploying SQL Monitor to Azure using Container Instances.

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Architecture](#architecture)
- [Cost Estimate](#cost-estimate)
- [Step-by-Step Deployment](#step-by-step-deployment)
- [Configuration](#configuration)
- [Verification](#verification)
- [Maintenance](#maintenance)
- [Troubleshooting](#troubleshooting)
- [Scaling](#scaling)
- [Security](#security)

## Overview

This guide deploys SQL Monitor to Azure using:
- **Azure Container Instances (ACI)**: Serverless container hosting
- **Azure Container Registry (ACR)**: Private container image registry
- **Azure Key Vault**: Secure credential storage
- **Azure Monitor**: Logging and metrics
- **Azure Application Gateway** (optional): Load balancer and SSL termination
- **Azure Virtual Network**: Network isolation

**Deployment Time**: 20-35 minutes
**Monthly Cost**: $20-30 (single instance) or $150-200 (HA with App Gateway)

## Prerequisites

### Required Tools

```bash
# Install Azure CLI (macOS)
brew install azure-cli

# Install Azure CLI (Linux)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Install Azure CLI (Windows via PowerShell)
Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi
Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'

# Install Docker
# macOS: Download Docker Desktop
# Linux: sudo apt-get install docker.io

# Install yq (YAML processor)
brew install yq  # macOS
sudo apt-get install yq  # Linux

# Install jq (JSON processor)
brew install jq  # macOS
sudo apt-get install jq  # Linux
```

### Azure Account Setup

```bash
# Login to Azure
az login

# If you have multiple subscriptions, set the active one
az account list --output table
az account set --subscription "<SUBSCRIPTION_ID>"

# Verify authentication
az account show
```

### Required Permissions

Your Azure account needs:
- Contributor role on resource group (or Subscription)
- Key Vault Administrator (for Key Vault operations)
- ACR Push/Pull permissions

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                      Azure Subscription                          │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                  Resource Group: rg-sqlmonitor             │ │
│  │                                                            │ │
│  │  ┌─────────────────────────────────────────────────────┐  │ │
│  │  │      Virtual Network (Optional)                      │  │ │
│  │  │      10.0.0.0/16                                     │  │ │
│  │  │                                                      │  │ │
│  │  │  ┌────────────────┐                                 │  │ │
│  │  │  │   App Gateway  │  (Optional, for HA + SSL)       │  │ │
│  │  │  │   Public IP    │                                 │  │ │
│  │  │  └────────┬───────┘                                 │  │ │
│  │  │           │                                          │  │ │
│  │  │  ┌────────▼────────────────┐                        │  │ │
│  │  │  │ Container Instance      │                        │  │ │
│  │  │  │  grafana-sqlmonitor     │                        │  │ │
│  │  │  │  2 vCPU, 4 GB RAM       │                        │  │ │
│  │  │  │  Port 3000              │                        │  │ │
│  │  │  │  Public IP (if no VNet) │                        │  │ │
│  │  │  └─────────────────────────┘                        │  │ │
│  │  └─────────────────────────────────────────────────────┘  │ │
│  │                                                            │ │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌─────────┐ │ │
│  │  │ Container Registry│  │   Key Vault      │  │ Monitor │ │ │
│  │  │  (ACR)            │  │  (Secrets)       │  │ (Logs)  │ │ │
│  │  │  sqlmonitoracr    │  │  kv-sqlmonitor   │  │         │ │ │
│  │  └──────────────────┘  └──────────────────┘  └─────────┘ │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
                            │
                            │ SQL connection (port 1433 or 14333)
                            ▼
                ┌────────────────────────┐
                │   SQL Server (On-Prem  │
                │   or Azure SQL)        │
                │   MonitoringDB         │
                └────────────────────────┘
```

## Cost Estimate

### Monthly Costs (East US, as of 2025)

**Single Container Instance**:
| Service | Configuration | Monthly Cost |
|---------|--------------|--------------|
| Container Instances | 2 vCPU, 4 GB RAM, 730 hrs | $100.74 |
| ACR (Basic) | 10 GB storage | $5.00 |
| Key Vault | 2 secrets, 1000 ops/month | $0.15 |
| Public IP | 1 static IP | $3.65 |
| Data Transfer | 10 GB outbound | $0.87 |
| Azure Monitor | 5 GB logs | $2.50 |
| **Total** | | **~$112.91/month** |

**Cost Optimization Options**:
| Option | Monthly Cost | Notes |
|--------|--------------|-------|
| Reduce to 1 vCPU, 2 GB | $50.37 | Sufficient for <20 servers |
| Stop during off-hours (12h/day) | $56.46 | Good for dev/test |
| Use VNET injection only | -$3.65 | Remove public IP |
| Reduce log retention (7 days) | -$1.00 | Less historical data |

**With Application Gateway (HA + SSL)**:
| Service | Configuration | Monthly Cost |
|---------|--------------|--------------|
| Container Instances (2x) | 2 vCPU, 4 GB each | $201.48 |
| Application Gateway V2 | 2 capacity units | $140.00 |
| ACR (Basic) | 10 GB storage | $5.00 |
| Key Vault | 3 secrets | $0.15 |
| VNet | Standard | $0.00 |
| Azure Monitor | 10 GB logs | $5.00 |
| **Total** | | **~$351.63/month** |

## Step-by-Step Deployment

### Step 1: Prepare Configuration

```bash
# Clone repository
git clone https://github.com/dbbuilder/sql-monitor.git
cd sql-monitor/deployment

# Copy configuration template
cp config-template.yaml deployment-config.yaml

# Edit configuration
nano deployment-config.yaml
```

**Edit `deployment-config.yaml`**:

```yaml
project:
  name: sql-monitor
  environment: production
  region: eastus  # Or: westus, westeurope, etc.

# MonitoringDB connection
monitoringdb:
  server: your-sql-server.example.com
  port: 1433
  database: MonitoringDB
  username: monitor_api
  password_env: MONITORINGDB_PASSWORD

# Servers to monitor
monitored_servers:
  - name: prod-sql-01.example.com,1433
    environment: Production
    collect_interval_minutes: 5
    linked_server_name: PRODSQL01

  - name: prod-sql-02.example.com,1433
    environment: Production
    collect_interval_minutes: 5
    linked_server_name: PRODSQL02

# Container registry (Azure ACR)
registry:
  type: acr
  acr:
    registry_name: sqlmonitoracr  # Must be globally unique
    resource_group: rg-sqlmonitor
    sku: Basic  # Basic, Standard, or Premium
    repository: sql-monitor-grafana

# Grafana configuration
grafana:
  admin_password_env: GRAFANA_ADMIN_PASSWORD
  root_url: http://your-grafana-url.com

  dashboards:
    download_from_github: true
    github_repo: https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/public/dashboards

# Azure-specific configuration
azure:
  container_instances:
    resource_group: rg-sqlmonitor
    container_name: grafana-sqlmonitor
    location: eastus
    cpu: 2  # 1, 2, 4
    memory: 4  # 1, 2, 4, 8, 16 (in GB)

    # Public DNS label (creates: <label>.<region>.azurecontainer.io)
    dns_label: sqlmonitor-grafana  # Must be globally unique

    # VNET integration (optional, for private networking)
    vnet:
      enabled: false
      name: vnet-sqlmonitor
      address_prefix: 10.0.0.0/16
      subnet_name: subnet-containers
      subnet_prefix: 10.0.1.0/24

  # Key Vault for secrets
  key_vault:
    name: kv-sqlmonitor  # Must be globally unique, 3-24 chars
    resource_group: rg-sqlmonitor
    location: eastus
    sku: standard
```

### Step 2: Create Resource Group

```bash
# Set variables from config
LOCATION=$(yq eval '.azure.container_instances.location' deployment-config.yaml)
RESOURCE_GROUP=$(yq eval '.azure.container_instances.resource_group' deployment-config.yaml)

# Create resource group
az group create \
    --name $RESOURCE_GROUP \
    --location $LOCATION

# Verify
az group show --name $RESOURCE_GROUP
```

### Step 3: Set Up Database (MonitoringDB)

**Option A: Existing SQL Server (On-Premise or Azure VM)**

```bash
# Connect to SQL Server (Windows Authentication or SQL Auth)
sqlcmd -S your-sql-server.example.com -U sa -P YourPassword -C

# Run deployment scripts (from repository root)
:r database/deploy-all.sql

# Create dedicated login for API
CREATE LOGIN monitor_api WITH PASSWORD = 'SecurePassword123!';
USE MonitoringDB;
CREATE USER monitor_api FOR LOGIN monitor_api;
ALTER ROLE db_datareader ADD MEMBER monitor_api;
ALTER ROLE db_datawriter ADD MEMBER monitor_api;
GRANT EXECUTE TO monitor_api;
GO
```

**Option B: Azure SQL Database**

```bash
# Create Azure SQL Server
SQL_SERVER_NAME="sqlserver-sqlmonitor"
SQL_ADMIN="sqladmin"
SQL_PASSWORD="SecurePassword123!@#"

az sql server create \
    --name $SQL_SERVER_NAME \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --admin-user $SQL_ADMIN \
    --admin-password $SQL_PASSWORD

# Create firewall rule (allow Azure services)
az sql server firewall-rule create \
    --resource-group $RESOURCE_GROUP \
    --server $SQL_SERVER_NAME \
    --name AllowAzureServices \
    --start-ip-address 0.0.0.0 \
    --end-ip-address 0.0.0.0

# Add your client IP
MY_IP=$(curl -s ifconfig.me)
az sql server firewall-rule create \
    --resource-group $RESOURCE_GROUP \
    --server $SQL_SERVER_NAME \
    --name AllowMyIP \
    --start-ip-address $MY_IP \
    --end-ip-address $MY_IP

# Create database
az sql db create \
    --resource-group $RESOURCE_GROUP \
    --server $SQL_SERVER_NAME \
    --name MonitoringDB \
    --service-objective S1 \
    --backup-storage-redundancy Local

# Get connection string
SQL_FQDN=$(az sql server show \
    --name $SQL_SERVER_NAME \
    --resource-group $RESOURCE_GROUP \
    --query fullyQualifiedDomainName \
    --output tsv)

echo "SQL Server FQDN: $SQL_FQDN"

# Connect and deploy schema
sqlcmd -S $SQL_FQDN -U $SQL_ADMIN -P $SQL_PASSWORD -C -i database/deploy-all.sql

# Create API user
sqlcmd -S $SQL_FQDN -U $SQL_ADMIN -P $SQL_PASSWORD -C -Q "
CREATE USER monitor_api WITH PASSWORD = 'ApiPassword123!';
ALTER ROLE db_datareader ADD MEMBER monitor_api;
ALTER ROLE db_datawriter ADD MEMBER monitor_api;
GRANT EXECUTE TO monitor_api;
"
```

### Step 4: Create Key Vault and Store Secrets

```bash
# Get Key Vault name from config
KEY_VAULT_NAME=$(yq eval '.azure.key_vault.name' deployment-config.yaml)

# Create Key Vault
az keyvault create \
    --name $KEY_VAULT_NAME \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --sku standard \
    --enable-rbac-authorization false

# Set secrets
az keyvault secret set \
    --vault-name $KEY_VAULT_NAME \
    --name monitoringdb-password \
    --value "SecurePassword123!"

az keyvault secret set \
    --vault-name $KEY_VAULT_NAME \
    --name grafana-admin-password \
    --value "Admin123!Secure"

# Verify secrets
az keyvault secret list \
    --vault-name $KEY_VAULT_NAME \
    --query "[].name" \
    --output table

# Get Key Vault ID (needed for container identity)
KEY_VAULT_ID=$(az keyvault show \
    --name $KEY_VAULT_NAME \
    --resource-group $RESOURCE_GROUP \
    --query id \
    --output tsv)

echo "Key Vault ID: $KEY_VAULT_ID"
```

### Step 5: Create Container Registry (ACR)

```bash
# Get ACR name from config
ACR_NAME=$(yq eval '.registry.acr.registry_name' deployment-config.yaml)

# Create ACR
az acr create \
    --name $ACR_NAME \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --sku Basic \
    --admin-enabled true

# Get ACR credentials
ACR_USERNAME=$(az acr credential show \
    --name $ACR_NAME \
    --query username \
    --output tsv)

ACR_PASSWORD=$(az acr credential show \
    --name $ACR_NAME \
    --query passwords[0].value \
    --output tsv)

ACR_LOGIN_SERVER=$(az acr show \
    --name $ACR_NAME \
    --resource-group $RESOURCE_GROUP \
    --query loginServer \
    --output tsv)

echo "ACR Login Server: $ACR_LOGIN_SERVER"
echo "ACR Username: $ACR_USERNAME"
```

### Step 6: Build and Push Docker Image

```bash
# Navigate to project root
cd /path/to/sql-monitor

# Login to ACR
az acr login --name $ACR_NAME

# Alternative: Docker login
echo $ACR_PASSWORD | docker login $ACR_LOGIN_SERVER \
    --username $ACR_USERNAME \
    --password-stdin

# Build image
docker build -f deployment/Dockerfile.grafana -t sql-monitor-grafana:latest .

# Tag image
docker tag sql-monitor-grafana:latest $ACR_LOGIN_SERVER/sql-monitor-grafana:latest
docker tag sql-monitor-grafana:latest $ACR_LOGIN_SERVER/sql-monitor-grafana:$(date +%Y%m%d-%H%M%S)

# Push image
docker push $ACR_LOGIN_SERVER/sql-monitor-grafana:latest
docker push $ACR_LOGIN_SERVER/sql-monitor-grafana:$(date +%Y%m%d-%H%M%S)

# Verify image
az acr repository list --name $ACR_NAME --output table
az acr repository show-tags --name $ACR_NAME --repository sql-monitor-grafana --output table
```

### Step 7: Create Virtual Network (Optional)

**Skip this step if using public IP without VNET**

```bash
# Get VNET settings from config
VNET_ENABLED=$(yq eval '.azure.container_instances.vnet.enabled' deployment-config.yaml)

if [ "$VNET_ENABLED" = "true" ]; then
    VNET_NAME=$(yq eval '.azure.container_instances.vnet.name' deployment-config.yaml)
    VNET_PREFIX=$(yq eval '.azure.container_instances.vnet.address_prefix' deployment-config.yaml)
    SUBNET_NAME=$(yq eval '.azure.container_instances.vnet.subnet_name' deployment-config.yaml)
    SUBNET_PREFIX=$(yq eval '.azure.container_instances.vnet.subnet_prefix' deployment-config.yaml)

    # Create VNET
    az network vnet create \
        --resource-group $RESOURCE_GROUP \
        --name $VNET_NAME \
        --address-prefix $VNET_PREFIX \
        --subnet-name $SUBNET_NAME \
        --subnet-prefix $SUBNET_PREFIX

    # Delegate subnet to Container Instances
    az network vnet subnet update \
        --resource-group $RESOURCE_GROUP \
        --vnet-name $VNET_NAME \
        --name $SUBNET_NAME \
        --delegations Microsoft.ContainerInstance/containerGroups

    # Get subnet ID
    SUBNET_ID=$(az network vnet subnet show \
        --resource-group $RESOURCE_GROUP \
        --vnet-name $VNET_NAME \
        --name $SUBNET_NAME \
        --query id \
        --output tsv)

    echo "Subnet ID: $SUBNET_ID"
fi
```

### Step 8: Deploy Container Instance

**Option A: Public IP (No VNET)**

```bash
# Get configuration values
CONTAINER_NAME=$(yq eval '.azure.container_instances.container_name' deployment-config.yaml)
DNS_LABEL=$(yq eval '.azure.container_instances.dns_label' deployment-config.yaml)
CPU=$(yq eval '.azure.container_instances.cpu' deployment-config.yaml)
MEMORY=$(yq eval '.azure.container_instances.memory' deployment-config.yaml)

MONITORINGDB_SERVER=$(yq eval '.monitoringdb.server' deployment-config.yaml)
MONITORINGDB_PORT=$(yq eval '.monitoringdb.port' deployment-config.yaml)
MONITORINGDB_DATABASE=$(yq eval '.monitoringdb.database' deployment-config.yaml)
MONITORINGDB_USER=$(yq eval '.monitoringdb.username' deployment-config.yaml)

DASHBOARD_DOWNLOAD=$(yq eval '.grafana.dashboards.download_from_github' deployment-config.yaml)
GITHUB_REPO=$(yq eval '.grafana.dashboards.github_repo' deployment-config.yaml)

# Get secrets from Key Vault
MONITORINGDB_PASSWORD=$(az keyvault secret show \
    --vault-name $KEY_VAULT_NAME \
    --name monitoringdb-password \
    --query value \
    --output tsv)

GRAFANA_PASSWORD=$(az keyvault secret show \
    --vault-name $KEY_VAULT_NAME \
    --name grafana-admin-password \
    --query value \
    --output tsv)

# Deploy container
az container create \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_NAME \
    --image $ACR_LOGIN_SERVER/sql-monitor-grafana:latest \
    --registry-login-server $ACR_LOGIN_SERVER \
    --registry-username $ACR_USERNAME \
    --registry-password $ACR_PASSWORD \
    --dns-name-label $DNS_LABEL \
    --ports 3000 \
    --cpu $CPU \
    --memory $MEMORY \
    --os-type Linux \
    --restart-policy Always \
    --environment-variables \
        MONITORINGDB_SERVER=$MONITORINGDB_SERVER \
        MONITORINGDB_PORT=$MONITORINGDB_PORT \
        MONITORINGDB_DATABASE=$MONITORINGDB_DATABASE \
        MONITORINGDB_USER=$MONITORINGDB_USER \
        DASHBOARD_DOWNLOAD=$DASHBOARD_DOWNLOAD \
        GITHUB_REPO=$GITHUB_REPO \
    --secure-environment-variables \
        MONITORINGDB_PASSWORD=$MONITORINGDB_PASSWORD \
        GF_SECURITY_ADMIN_PASSWORD=$GRAFANA_PASSWORD

# Wait for container to start (30-60 seconds)
az container show \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_NAME \
    --query instanceView.state

# Get FQDN
FQDN=$(az container show \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_NAME \
    --query ipAddress.fqdn \
    --output tsv)

echo ""
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo "Grafana URL: http://$FQDN:3000"
echo "Username: admin"
echo "Password: (from Key Vault)"
echo "========================================="
```

**Option B: With VNET Integration (Private Networking)**

```bash
# Deploy container to VNET
az container create \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_NAME \
    --image $ACR_LOGIN_SERVER/sql-monitor-grafana:latest \
    --registry-login-server $ACR_LOGIN_SERVER \
    --registry-username $ACR_USERNAME \
    --registry-password $ACR_PASSWORD \
    --vnet $VNET_NAME \
    --subnet $SUBNET_NAME \
    --ports 3000 \
    --cpu $CPU \
    --memory $MEMORY \
    --os-type Linux \
    --restart-policy Always \
    --environment-variables \
        MONITORINGDB_SERVER=$MONITORINGDB_SERVER \
        MONITORINGDB_PORT=$MONITORINGDB_PORT \
        MONITORINGDB_DATABASE=$MONITORINGDB_DATABASE \
        MONITORINGDB_USER=$MONITORINGDB_USER \
        DASHBOARD_DOWNLOAD=$DASHBOARD_DOWNLOAD \
        GITHUB_REPO=$GITHUB_REPO \
    --secure-environment-variables \
        MONITORINGDB_PASSWORD=$MONITORINGDB_PASSWORD \
        GF_SECURITY_ADMIN_PASSWORD=$GRAFANA_PASSWORD

# Get private IP
PRIVATE_IP=$(az container show \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_NAME \
    --query ipAddress.ip \
    --output tsv)

echo "Private IP: $PRIVATE_IP"
echo "Access via VNET: http://$PRIVATE_IP:3000"
```

### Step 9: Configure Managed Identity (Optional, for Key Vault access)

```bash
# Enable system-assigned managed identity
az container update \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_NAME \
    --assign-identity [system]

# Get identity principal ID
IDENTITY_ID=$(az container show \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_NAME \
    --query identity.principalId \
    --output tsv)

# Grant Key Vault access
az keyvault set-policy \
    --name $KEY_VAULT_NAME \
    --object-id $IDENTITY_ID \
    --secret-permissions get list

echo "Managed identity configured for Key Vault access"
```

## Configuration

### DNS Setup (Custom Domain)

**Option 1: Azure DNS Zone**

```bash
# Create DNS zone (if not exists)
az network dns zone create \
    --resource-group $RESOURCE_GROUP \
    --name example.com

# Create CNAME record
az network dns record-set cname set-record \
    --resource-group $RESOURCE_GROUP \
    --zone-name example.com \
    --record-set-name grafana \
    --cname $FQDN

# Verify
az network dns record-set cname show \
    --resource-group $RESOURCE_GROUP \
    --zone-name example.com \
    --name grafana
```

**Option 2: External DNS Provider**

Add CNAME record pointing to `$FQDN`:
```
grafana.example.com  CNAME  sqlmonitor-grafana.eastus.azurecontainer.io
```

### SSL/TLS Setup

**Option 1: Application Gateway + Azure Certificate**

See "Application Gateway Deployment" section below.

**Option 2: Cloudflare (Free SSL)**

1. Add domain to Cloudflare
2. Create DNS record: `grafana.example.com` → `<FQDN>:3000`
3. Enable SSL/TLS → Full
4. Done! Cloudflare provides free SSL

**Option 3: Let's Encrypt (via sidecar container)**

Deploy SSL proxy sidecar - see `ssl-proxy/` directory in repository.

### Application Gateway Deployment (HA + SSL)

```bash
# Create public IP for App Gateway
az network public-ip create \
    --resource-group $RESOURCE_GROUP \
    --name pip-appgw-sqlmonitor \
    --allocation-method Static \
    --sku Standard

# Create Application Gateway
az network application-gateway create \
    --resource-group $RESOURCE_GROUP \
    --name appgw-sqlmonitor \
    --location $LOCATION \
    --vnet-name $VNET_NAME \
    --subnet subnet-appgw \
    --public-ip-address pip-appgw-sqlmonitor \
    --http-settings-port 3000 \
    --http-settings-protocol Http \
    --frontend-port 80 \
    --sku Standard_v2 \
    --capacity 2

# Add backend pool with container private IP
az network application-gateway address-pool create \
    --resource-group $RESOURCE_GROUP \
    --gateway-name appgw-sqlmonitor \
    --name backend-sqlmonitor \
    --servers $PRIVATE_IP

# Configure health probe
az network application-gateway probe create \
    --resource-group $RESOURCE_GROUP \
    --gateway-name appgw-sqlmonitor \
    --name health-probe \
    --protocol Http \
    --path /api/health \
    --interval 30 \
    --timeout 30 \
    --threshold 3

# Get App Gateway public IP
APPGW_PUBLIC_IP=$(az network public-ip show \
    --resource-group $RESOURCE_GROUP \
    --name pip-appgw-sqlmonitor \
    --query ipAddress \
    --output tsv)

echo "Application Gateway Public IP: $APPGW_PUBLIC_IP"
```

## Verification

### Check Container Status

```bash
# Get container status
az container show \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_NAME \
    --query "[name,provisioningState,instanceView.state]" \
    --output table

# Get detailed status
az container show \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_NAME

# Check events
az container show \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_NAME \
    --query instanceView.events
```

### View Logs

```bash
# Stream logs in real-time
az container logs \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_NAME \
    --follow

# Get recent logs
az container logs \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_NAME \
    --tail 100

# Attach to container (interactive)
az container attach \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_NAME
```

### Test Grafana Access

```bash
# Health check
curl http://$FQDN:3000/api/health

# Login page
curl -I http://$FQDN:3000/login

# Test authentication
curl -X POST http://$FQDN:3000/api/login \
    -H "Content-Type: application/json" \
    -d "{\"user\":\"admin\",\"password\":\"$GRAFANA_PASSWORD\"}"
```

### SSH into Container

```bash
# Execute command in container
az container exec \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_NAME \
    --exec-command "/bin/sh"

# Inside container:
ps aux
netstat -tulpn
env | grep MONITORING
```

## Maintenance

### Update Container Image

```bash
# Build new image
cd /path/to/sql-monitor
docker build -f deployment/Dockerfile.grafana -t sql-monitor-grafana:latest .

# Tag and push
docker tag sql-monitor-grafana:latest $ACR_LOGIN_SERVER/sql-monitor-grafana:latest
docker tag sql-monitor-grafana:latest $ACR_LOGIN_SERVER/sql-monitor-grafana:v$(date +%Y%m%d)
docker push $ACR_LOGIN_SERVER/sql-monitor-grafana:latest
docker push $ACR_LOGIN_SERVER/sql-monitor-grafana:v$(date +%Y%m%d)

# Delete and recreate container (Container Instances doesn't support in-place updates)
az container delete \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_NAME \
    --yes

# Recreate (use same command from Step 8)
az container create ...
```

### Update Secrets

```bash
# Update MonitoringDB password in Key Vault
az keyvault secret set \
    --vault-name $KEY_VAULT_NAME \
    --name monitoringdb-password \
    --value "NewPassword123!"

# Restart container to pick up new secret
az container restart \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_NAME
```

### Start/Stop Container

```bash
# Stop container (stops billing for CPU/memory)
az container stop \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_NAME

# Start container
az container start \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_NAME

# Schedule auto-stop/start (using Azure Automation)
# See: https://docs.microsoft.com/en-us/azure/automation/
```

### Backup and Restore

```bash
# Export container configuration
az container export \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_NAME \
    --file container-backup.yaml

# Backup Grafana dashboards (via API)
curl -u admin:$GRAFANA_PASSWORD http://$FQDN:3000/api/search?type=dash-db | \
    jq -r '.[] | .uid' | \
    while read uid; do
        curl -u admin:$GRAFANA_PASSWORD http://$FQDN:3000/api/dashboards/uid/$uid > dashboard-$uid.json
    done

# Backup MonitoringDB
sqlcmd -S $MONITORINGDB_SERVER -U monitor_api -P $MONITORINGDB_PASSWORD -C -Q \
    "BACKUP DATABASE MonitoringDB TO DISK = '/backups/MonitoringDB.bak' WITH COMPRESSION;"
```

## Troubleshooting

### Container Won't Start

```bash
# Check provisioning state
az container show \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_NAME \
    --query "[provisioningState,instanceView.state]"

# View events
az container show \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_NAME \
    --query instanceView.events

# Check logs for errors
az container logs \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_NAME | grep -i error
```

### Database Connection Issues

```bash
# Test from container
az container exec \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_NAME \
    --exec-command "/bin/sh"

# Inside container, test connection
apk add --no-cache mysql-client
mysql -h $MONITORINGDB_SERVER -P $MONITORINGDB_PORT -u $MONITORINGDB_USER -p

# Check NSG rules (if using VNET)
az network nsg rule list \
    --resource-group $RESOURCE_GROUP \
    --nsg-name <NSG_NAME> \
    --output table
```

### Image Pull Errors

```bash
# Verify ACR credentials
az acr credential show --name $ACR_NAME

# Test ACR login
docker login $ACR_LOGIN_SERVER \
    --username $ACR_USERNAME \
    --password $ACR_PASSWORD

# Check ACR access from container
az container show \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_NAME \
    --query imageRegistryCredentials
```

### High Costs

```bash
# Check container metrics
az monitor metrics list \
    --resource $(az container show --resource-group $RESOURCE_GROUP --name $CONTAINER_NAME --query id -o tsv) \
    --metric CPUUsage \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ)

# Consider:
# - Reduce CPU/memory if underutilized
# - Stop during off-hours (dev/test)
# - Use Azure Spot instances (preview)
```

## Scaling

### Vertical Scaling (Increase Resources)

```bash
# Delete container
az container delete \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_NAME \
    --yes

# Recreate with more resources
az container create \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_NAME \
    ... \
    --cpu 4 \
    --memory 8
```

### Horizontal Scaling (Multiple Containers)

Azure Container Instances doesn't support native scaling. Options:

1. **Azure Kubernetes Service (AKS)**: For true horizontal scaling
2. **Multiple Container Groups**: Deploy multiple separate containers behind App Gateway
3. **Azure Container Apps**: Serverless container service with auto-scaling

**Deploy multiple containers:**

```bash
# Create container group 1
az container create --name grafana-sqlmonitor-01 ...

# Create container group 2
az container create --name grafana-sqlmonitor-02 ...

# Add both to App Gateway backend pool
az network application-gateway address-pool update \
    --gateway-name appgw-sqlmonitor \
    --name backend-sqlmonitor \
    --servers $PRIVATE_IP_01 $PRIVATE_IP_02
```

## Security

### Network Security

```bash
# Create NSG (if using VNET)
az network nsg create \
    --resource-group $RESOURCE_GROUP \
    --name nsg-sqlmonitor

# Allow HTTP from specific IPs only
az network nsg rule create \
    --resource-group $RESOURCE_GROUP \
    --nsg-name nsg-sqlmonitor \
    --name AllowHTTP \
    --priority 100 \
    --source-address-prefixes 203.0.113.0/24 \
    --destination-port-ranges 3000 \
    --access Allow

# Associate NSG with subnet
az network vnet subnet update \
    --resource-group $RESOURCE_GROUP \
    --vnet-name $VNET_NAME \
    --name $SUBNET_NAME \
    --network-security-group nsg-sqlmonitor
```

### Key Vault Security

```bash
# Enable Key Vault firewall
az keyvault update \
    --name $KEY_VAULT_NAME \
    --default-action Deny

# Allow specific IP
az keyvault network-rule add \
    --name $KEY_VAULT_NAME \
    --ip-address $MY_IP

# Allow Azure services
az keyvault update \
    --name $KEY_VAULT_NAME \
    --bypass AzureServices
```

### ACR Security

```bash
# Disable admin account (use managed identity instead)
az acr update \
    --name $ACR_NAME \
    --admin-enabled false

# Use container managed identity to pull images
# (requires Azure Container Registry Tasks or AKS)
```

## Next Steps

1. **Configure Custom Domain**: Point DNS to container FQDN
2. **Enable SSL**: Use App Gateway with ACM certificate
3. **Set Up Monitoring**: Azure Monitor alerts for container health
4. **Configure Backups**: Automate MonitoringDB and Grafana backups
5. **Review Costs**: Use Azure Cost Management
6. **Consider AKS**: For production HA and auto-scaling

## Support

- **Azure Documentation**: https://docs.microsoft.com/en-us/azure/container-instances/
- **GitHub Issues**: https://github.com/dbbuilder/sql-monitor/issues
- **Discussions**: https://github.com/dbbuilder/sql-monitor/discussions
