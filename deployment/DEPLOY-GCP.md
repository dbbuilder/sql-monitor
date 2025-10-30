# SQL Monitor - Google Cloud Platform Deployment Guide

Complete step-by-step guide for deploying SQL Monitor to GCP using Cloud Run.

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Architecture](#architecture)
- [Cost Estimate](#cost-estimate)
- [Step-by-Step Deployment](#step-by-step-deployment)
- [Verification](#verification)
- [Maintenance](#maintenance)
- [Troubleshooting](#troubleshooting)

## Overview

This guide deploys SQL Monitor to GCP using:
- **Cloud Run**: Fully managed serverless container platform
- **Artifact Registry**: Container image storage
- **Secret Manager**: Secure credential management
- **Cloud Load Balancing** (optional): Global load balancer with SSL
- **VPC Connector**: Private network access to SQL Server

**Deployment Time**: 15-25 minutes
**Monthly Cost**: $10-20 (single instance) or $50-80 (with load balancer)

## Prerequisites

### Install Tools

```bash
# Install gcloud CLI (macOS)
curl https://sdk.cloud.google.com | bash
exec -l $SHELL

# Install gcloud CLI (Linux)
curl https://sdk.cloud.google.com | bash
exec -l $SHELL

# Install Docker
# macOS: Download Docker Desktop
# Linux: sudo apt-get install docker.io

# Install yq and jq
brew install yq jq  # macOS
sudo apt-get install yq jq  # Linux
```

### GCP Account Setup

```bash
# Login
gcloud auth login

# List projects
gcloud projects list

# Set active project
gcloud config set project YOUR_PROJECT_ID

# Enable required APIs
gcloud services enable run.googleapis.com \
    artifactregistry.googleapis.com \
    secretmanager.googleapis.com \
    vpcaccess.googleapis.com \
    compute.googleapis.com
```

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│                    GCP Project                             │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐ │
│  │         Cloud Load Balancer (Optional)                │ │
│  │         Global HTTPS, SSL termination                 │ │
│  └────────────────────┬─────────────────────────────────┘ │
│                       │                                    │
│  ┌────────────────────▼─────────────────────────────────┐ │
│  │              Cloud Run Service                        │ │
│  │              sql-monitor-grafana                      │ │
│  │              Auto-scales 0-10 instances               │ │
│  │              Port 3000                                │ │
│  └────────────────────┬─────────────────────────────────┘ │
│                       │                                    │
│  ┌────────────────────▼─────────────────────────────────┐ │
│  │         VPC Serverless Connector (Optional)          │ │
│  │         Private access to SQL Server                  │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                            │
│  ┌──────────────────┐  ┌──────────────────┐  ┌─────────┐ │
│  │ Artifact Registry│  │ Secret Manager   │  │ Logging │ │
│  │ (Container Images)│  │ (Passwords)     │  │         │ │
│  └──────────────────┘  └──────────────────┘  └─────────┘ │
└────────────────────────────────────────────────────────────┘
                            │
                            │ SQL connection
                            ▼
                ┌────────────────────────┐
                │   SQL Server (On-Prem  │
                │   or Cloud SQL)        │
                │   MonitoringDB         │
                └────────────────────────┘
```

## Cost Estimate

### Monthly Costs (us-central1, as of 2025)

**Single Cloud Run Instance**:
| Service | Configuration | Monthly Cost |
|---------|--------------|--------------|
| Cloud Run | 1 vCPU, 2 GB RAM, 730 hrs | $12.70 |
| Cloud Run Requests | 1M requests/month | $0.40 |
| Artifact Registry | 10 GB storage | $1.00 |
| Secret Manager | 2 secrets, 10K accesses | $0.12 |
| Cloud Logging | 5 GB | $2.50 |
| Egress | 10 GB | $1.20 |
| **Total** | | **~$17.92/month** |

**With Cloud Load Balancer**:
| Service | Configuration | Monthly Cost |
|---------|--------------|--------------|
| Cloud Run (scaled) | 2-10 instances | $25.40 |
| Load Balancer | Global HTTPS | $18.00 |
| SSL Certificate | Managed | $0.00 |
| Artifact Registry | 10 GB | $1.00 |
| Secret Manager | 2 secrets | $0.12 |
| Cloud Logging | 10 GB | $5.00 |
| **Total** | | **~$49.52/month** |

**Cost Optimization**:
- Scale to zero (pay only when used)
- Use minimum instances: 0 (cold start) or 1 (warm)
- Reduce log retention (7 days instead of 30)
- Use VPC connector only if needed

## Step-by-Step Deployment

### Step 1: Set Environment Variables

```bash
# Set your configuration
export PROJECT_ID="your-gcp-project"
export REGION="us-central1"
export SERVICE_NAME="sql-monitor-grafana"
export ARTIFACT_REPO="sql-monitor"

# SQL Server connection
export MONITORINGDB_SERVER="your-sql-server.example.com"
export MONITORINGDB_PORT="1433"
export MONITORINGDB_DATABASE="MonitoringDB"
export MONITORINGDB_USER="monitor_api"
export MONITORINGDB_PASSWORD="SecurePassword123!"
export GRAFANA_PASSWORD="Admin123!Secure"

# Verify
gcloud config set project $PROJECT_ID
gcloud config get-value project
```

### Step 2: Set Up Database

**Same as AWS/Azure guides - run deployment scripts on SQL Server**

```bash
# Connect to SQL Server
sqlcmd -S $MONITORINGDB_SERVER -U sa -P YourPassword -C

# Run deployment scripts
:r database/deploy-all.sql

# Create API login
CREATE LOGIN monitor_api WITH PASSWORD = 'SecurePassword123!';
USE MonitoringDB;
CREATE USER monitor_api FOR LOGIN monitor_api;
ALTER ROLE db_datareader ADD MEMBER monitor_api;
ALTER ROLE db_datawriter ADD MEMBER monitor_api;
GRANT EXECUTE TO monitor_api;
GO
```

### Step 3: Create Secret Manager Secrets

```bash
# Create secrets
echo -n "$MONITORINGDB_PASSWORD" | gcloud secrets create monitoringdb-password --data-file=-
echo -n "$GRAFANA_PASSWORD" | gcloud secrets create grafana-admin-password --data-file=-

# Grant Cloud Run access to secrets
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

gcloud secrets add-iam-policy-binding monitoringdb-password \
    --member="serviceAccount:${COMPUTE_SA}" \
    --role="roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding grafana-admin-password \
    --member="serviceAccount:${COMPUTE_SA}" \
    --role="roles/secretmanager.secretAccessor"

# Verify
gcloud secrets list
```

### Step 4: Create Artifact Registry Repository

```bash
# Create repository
gcloud artifacts repositories create $ARTIFACT_REPO \
    --repository-format=docker \
    --location=$REGION \
    --description="SQL Monitor container images"

# Configure Docker authentication
gcloud auth configure-docker ${REGION}-docker.pkg.dev

# Verify
gcloud artifacts repositories list --location=$REGION
```

### Step 5: Build and Push Container Image

```bash
# Navigate to project root
cd /path/to/sql-monitor

# Build image
docker build -f deployment/Dockerfile.grafana -t sql-monitor-grafana:latest .

# Tag for Artifact Registry
IMAGE_URL="${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REPO}/sql-monitor-grafana"
docker tag sql-monitor-grafana:latest ${IMAGE_URL}:latest
docker tag sql-monitor-grafana:latest ${IMAGE_URL}:$(date +%Y%m%d-%H%M%S)

# Push image
docker push ${IMAGE_URL}:latest
docker push ${IMAGE_URL}:$(date +%Y%m%d-%H%M%S)

# Verify
gcloud artifacts docker images list ${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REPO}
```

### Step 6: Deploy to Cloud Run

**Option A: Public Access (No VPC)**

```bash
# Deploy service
gcloud run deploy $SERVICE_NAME \
    --image ${IMAGE_URL}:latest \
    --platform managed \
    --region $REGION \
    --allow-unauthenticated \
    --port 3000 \
    --cpu 1 \
    --memory 2Gi \
    --min-instances 1 \
    --max-instances 10 \
    --timeout 300 \
    --set-env-vars "MONITORINGDB_SERVER=${MONITORINGDB_SERVER},MONITORINGDB_PORT=${MONITORINGDB_PORT},MONITORINGDB_DATABASE=${MONITORINGDB_DATABASE},MONITORINGDB_USER=${MONITORINGDB_USER},DASHBOARD_DOWNLOAD=true,GITHUB_REPO=https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/public/dashboards" \
    --set-secrets "MONITORINGDB_PASSWORD=monitoringdb-password:latest,GF_SECURITY_ADMIN_PASSWORD=grafana-admin-password:latest"

# Get service URL
SERVICE_URL=$(gcloud run services describe $SERVICE_NAME \
    --platform managed \
    --region $REGION \
    --format 'value(status.url)')

echo ""
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo "Grafana URL: $SERVICE_URL"
echo "Username: admin"
echo "Password: (from Secret Manager)"
echo "========================================="
```

**Option B: With VPC Connector (Private SQL Server)**

```bash
# Create VPC connector
gcloud compute networks vpc-access connectors create sql-monitor-connector \
    --region=$REGION \
    --subnet=default \
    --subnet-project=$PROJECT_ID \
    --min-instances=2 \
    --max-instances=10 \
    --machine-type=e2-micro

# Deploy with VPC connector
gcloud run deploy $SERVICE_NAME \
    --image ${IMAGE_URL}:latest \
    --platform managed \
    --region $REGION \
    --allow-unauthenticated \
    --port 3000 \
    --cpu 1 \
    --memory 2Gi \
    --min-instances 1 \
    --max-instances 10 \
    --vpc-connector sql-monitor-connector \
    --vpc-egress all-traffic \
    --set-env-vars "MONITORINGDB_SERVER=${MONITORINGDB_SERVER},MONITORINGDB_PORT=${MONITORINGDB_PORT},MONITORINGDB_DATABASE=${MONITORINGDB_DATABASE},MONITORINGDB_USER=${MONITORINGDB_USER},DASHBOARD_DOWNLOAD=true,GITHUB_REPO=https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/public/dashboards" \
    --set-secrets "MONITORINGDB_PASSWORD=monitoringdb-password:latest,GF_SECURITY_ADMIN_PASSWORD=grafana-admin-password:latest"
```

### Step 7: Configure Custom Domain and SSL (Optional)

**Option A: Automated Setup with Name.com API (Recommended)**

```bash
# Navigate to deployment directory
cd /path/to/sql-monitor/deployment

# Run automated DNS configuration script
# Auto-detects GCP Cloud Run deployment and configures DNS
./configure-dns-namecom.sh

# Script will:
# 1. Detect Cloud Run service URL
# 2. Create CNAME record: sqlmonitor.servicevision.io → ghs.googlehosted.com
# 3. Create GCP domain mapping
# 4. Provision SSL certificate automatically (5-30 minutes)
# 5. Verify DNS propagation
# 6. Test HTTPS connectivity

# Expected output:
# ✅ DNS record created successfully!
# ✅ GCP domain mapping configured
# ✅ DNS propagated successfully!
# Grafana URL: https://sqlmonitor.servicevision.io
```

**Option B: Manual DNS Configuration**

```bash
# Map custom domain
gcloud run domain-mappings create --service=$SERVICE_NAME --domain=sqlmonitor.servicevision.io --region=$REGION

# Get DNS records to add to your DNS provider
gcloud run domain-mappings describe --domain=sqlmonitor.servicevision.io --region=$REGION

# Add DNS records (from output above)
# Type: CNAME, Name: sqlmonitor, Value: ghs.googlehosted.com
# SSL certificate will be provisioned automatically (5-30 minutes)

# Verify certificate status
gcloud run domain-mappings describe --domain=sqlmonitor.servicevision.io --region=$REGION --format='value(status.certificate.status)'
```

**Complete DNS Guide:** See [CONFIGURE-DNS-NAMECOM.md](CONFIGURE-DNS-NAMECOM.md) for detailed instructions

## Verification

### Check Service Status

```bash
# Get service details
gcloud run services describe $SERVICE_NAME --region=$REGION

# Check revisions
gcloud run revisions list --service=$SERVICE_NAME --region=$REGION

# Get service URL
gcloud run services describe $SERVICE_NAME \
    --region=$REGION \
    --format='value(status.url)'
```

### View Logs

```bash
# Stream logs
gcloud run services logs tail $SERVICE_NAME --region=$REGION --follow

# Get recent logs
gcloud run services logs read $SERVICE_NAME --region=$REGION --limit=100

# Filter logs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=$SERVICE_NAME" --limit 50
```

### Test Access

```bash
# Health check
curl ${SERVICE_URL}/api/health

# Login page
curl -I ${SERVICE_URL}/login

# Test authentication
curl -X POST ${SERVICE_URL}/api/login \
    -H "Content-Type: application/json" \
    -d "{\"user\":\"admin\",\"password\":\"${GRAFANA_PASSWORD}\"}"
```

## Maintenance

### Update Container Image

```bash
# Build new image
docker build -f deployment/Dockerfile.grafana -t sql-monitor-grafana:latest .

# Tag and push
docker tag sql-monitor-grafana:latest ${IMAGE_URL}:latest
docker push ${IMAGE_URL}:latest

# Deploy new revision
gcloud run deploy $SERVICE_NAME \
    --image ${IMAGE_URL}:latest \
    --region $REGION

# Cloud Run automatically routes traffic to new revision
```

### Update Secrets

```bash
# Update secret
echo -n "NewPassword123!" | gcloud secrets versions add monitoringdb-password --data-file=-

# Redeploy service to pick up new secret version
gcloud run services update $SERVICE_NAME --region=$REGION
```

### Scale Service

```bash
# Update scaling
gcloud run services update $SERVICE_NAME \
    --region $REGION \
    --min-instances 2 \
    --max-instances 20

# Auto-scale to zero (cold start, lowest cost)
gcloud run services update $SERVICE_NAME \
    --region $REGION \
    --min-instances 0
```

### Backup

```bash
# Export service configuration
gcloud run services describe $SERVICE_NAME \
    --region=$REGION \
    --format=yaml > service-backup.yaml

# Backup Grafana dashboards
curl -u admin:${GRAFANA_PASSWORD} ${SERVICE_URL}/api/search?type=dash-db | \
    jq -r '.[] | .uid' | \
    while read uid; do
        curl -u admin:${GRAFANA_PASSWORD} ${SERVICE_URL}/api/dashboards/uid/$uid > dashboard-$uid.json
    done
```

## Troubleshooting

### Service Won't Deploy

```bash
# Check deployment logs
gcloud run services logs tail $SERVICE_NAME --region=$REGION

# Describe service status
gcloud run services describe $SERVICE_NAME --region=$REGION

# Common issues:
# - Image not found: Verify image URL and permissions
# - Secret access denied: Check IAM bindings
# - CPU/memory limits: Increase resources
```

### Database Connection Failures

```bash
# Test from local machine (if SQL Server is public)
sqlcmd -S $MONITORINGDB_SERVER -U $MONITORINGDB_USER -P $MONITORINGDB_PASSWORD -C

# If using VPC connector, verify:
gcloud compute networks vpc-access connectors describe sql-monitor-connector --region=$REGION

# Check firewall rules
gcloud compute firewall-rules list
```

### Cold Start Issues

```bash
# Increase minimum instances to keep service warm
gcloud run services update $SERVICE_NAME \
    --region $REGION \
    --min-instances 1

# Increase CPU during startup
gcloud run services update $SERVICE_NAME \
    --region $REGION \
    --cpu-boost
```

## Cost Optimization

### Reduce Costs

```bash
# Scale to zero when not in use (dev/test)
gcloud run services update $SERVICE_NAME \
    --region $REGION \
    --min-instances 0

# Reduce memory (if sufficient)
gcloud run services update $SERVICE_NAME \
    --region $REGION \
    --memory 1Gi

# Reduce log retention
gcloud logging sinks create delete-old-logs \
    storage.googleapis.com/sql-monitor-logs \
    --log-filter='resource.type="cloud_run_revision"' \
    --retention-days=7
```

### Monitor Costs

```bash
# View cost breakdown
gcloud billing accounts list
gcloud billing projects link $PROJECT_ID --billing-account=<BILLING_ACCOUNT_ID>

# Set budget alerts
# Go to: https://console.cloud.google.com/billing/budgets
```

## Security Best Practices

1. **Require Authentication**: Remove `--allow-unauthenticated` flag
2. **Use Service Accounts**: Create dedicated service account with minimum permissions
3. **Enable Binary Authorization**: Ensure only signed images can be deployed
4. **Use VPC Connector**: Keep SQL Server private
5. **Rotate Secrets**: Regularly update passwords in Secret Manager
6. **Enable Cloud Armor**: DDoS protection and WAF rules

## Next Steps

1. **Configure Monitoring**: Set up alerting for service health
2. **Enable Cloud Armor**: Add DDoS protection
3. **Set Up CI/CD**: Automate deployments with Cloud Build
4. **Configure Backup**: Schedule MonitoringDB backups
5. **Review Security**: Implement IAM best practices

## Support

- **GCP Documentation**: https://cloud.google.com/run/docs
- **GitHub Issues**: https://github.com/dbbuilder/sql-monitor/issues
- **Discussions**: https://github.com/dbbuilder/sql-monitor/discussions
