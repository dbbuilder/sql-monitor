# SQL Monitor - Multi-Cloud Deployment Guide

Complete deployment solution for AWS, GCP, and Azure with multi-server monitoring support.

## 📋 Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Cloud Providers](#cloud-providers)
  - [AWS ECS](#aws-ecs-fargate)
  - [Google Cloud Run](#google-cloud-run)
  - [Azure Container Instances](#azure-container-instances)
- [Multi-Server Setup](#multi-server-setup)
- [SSL/TLS Configuration](#ssltls-configuration)
- [Monitoring & Logging](#monitoring--logging)
- [Cost Optimization](#cost-optimization)
- [Troubleshooting](#troubleshooting)

## Overview

This deployment system provides:

✅ **Multi-Cloud Support**: AWS ECS, GCP Cloud Run, Azure Container Instances
✅ **Configuration-Driven**: Single YAML file for all settings
✅ **Multi-Server Monitoring**: Monitor unlimited SQL Server instances
✅ **Automatic Secrets Management**: AWS Secrets Manager, GCP Secret Manager, Azure Key Vault
✅ **Auto-Scaling**: Configurable min/max instances
✅ **Health Checks**: Built-in Grafana /api/health endpoint
✅ **Dashboard Sync**: Auto-download from GitHub
✅ **Cost Effective**: $10-30/month depending on cloud provider

## Quick Start

### Prerequisites

```bash
# Install required tools
brew install yq jq docker

# Cloud CLI tools
# AWS
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /

# GCP
curl https://sdk.cloud.google.com | bash

# Azure
brew install azure-cli
```

### 1. Copy Configuration Template

```bash
cd /mnt/d/dev2/sql-monitor/deployment
cp config-template.yaml deployment-config.yaml
```

### 2. Edit Configuration

```yaml
# deployment-config.yaml
project:
  name: sql-monitor
  environment: production

# MonitoringDB connection
monitoringdb:
  server: sqltest.schoolvision.net
  port: 14333
  database: MonitoringDB
  username: sv

# Monitored servers (auto-registered on deployment)
monitored_servers:
  - name: sqltest.schoolvision.net,14333
    environment: Test
  - name: suncity.schoolvision.net,14333
    environment: Production
  - name: svweb,14333
    environment: Production

# Choose cloud provider
registry:
  type: acr  # or ecr, gcr, dockerhub
```

### 3. Set Secrets

**AWS:**
```bash
aws secretsmanager create-secret \
    --name sql-monitor/monitoringdb-password \
    --secret-string "your-password"

aws secretsmanager create-secret \
    --name sql-monitor/grafana-admin-password \
    --secret-string "Admin123!"
```

**GCP:**
```bash
echo -n "your-password" | gcloud secrets create monitoringdb-password --data-file=-
echo -n "Admin123!" | gcloud secrets create grafana-admin-password --data-file=-
```

**Azure:**
```bash
az keyvault create --name kv-sqlmonitor --resource-group rg-sqlmonitor --location eastus
az keyvault secret set --vault-name kv-sqlmonitor --name monitoringdb-password --value "your-password"
az keyvault secret set --vault-name kv-sqlmonitor --name grafana-admin-password --value "Admin123!"
```

### 4. Deploy

**AWS:**
```bash
./deploy-aws.sh
```

**GCP:**
```bash
./deploy-gcp.sh
```

**Azure:**
```bash
./deploy-azure.sh
```

## Configuration

### Full Configuration Reference

```yaml
# deployment-config.yaml

project:
  name: sql-monitor
  environment: production  # development, staging, production
  region: us-east-1       # Cloud region

# Container registry selection
registry:
  type: acr  # Options: dockerhub, ecr, gcr, acr

  # AWS ECR
  ecr:
    account_id: "123456789012"
    region: us-east-1
    repository: sql-monitor-grafana

  # Google GCR
  gcr:
    project_id: your-project-id
    repository: sql-monitor-grafana

  # Azure ACR
  acr:
    registry_name: sqlmonitoracr
    repository: sql-monitor-grafana

# MonitoringDB (central monitoring database)
monitoringdb:
  server: sqltest.schoolvision.net
  port: 14333
  database: MonitoringDB
  username: sv
  password_env: MONITORINGDB_PASSWORD  # Secret name

# SQL Servers to monitor
monitored_servers:
  - name: sqltest.schoolvision.net,14333
    environment: Test
    collect_interval_minutes: 5
    linked_server_name: SQLTEST

  - name: prod-sql-01.mycompany.com,1433
    environment: Production
    collect_interval_minutes: 5
    linked_server_name: PRODSQL01

# Grafana configuration
grafana:
  admin_password_env: GRAFANA_ADMIN_PASSWORD
  root_url: https://monitor.mycompany.com

  # Dashboard source
  dashboards:
    download_from_github: true
    github_repo: https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/public/dashboards
```

## Cloud Providers

### AWS ECS (Fargate)

**Cost:** ~$15-20/month

**Architecture:**
```
Internet → ALB → ECS Service (Fargate) → RDS/SQL Server
                    ↓
              CloudWatch Logs
                    ↓
            Secrets Manager
```

**Configuration:**

```yaml
aws:
  ecs:
    cluster_name: sql-monitor-cluster
    service_name: sql-monitor-grafana
    cpu: 1024        # 1 vCPU
    memory: 2048     # 2 GB

    # Networking
    vpc_id: vpc-xxxxx
    subnets: [subnet-xxxxx, subnet-yyyyy]
    security_groups: [sg-xxxxx]

    # Load Balancer (optional)
    load_balancer:
      enabled: true
      target_group_arn: arn:aws:elasticloadbalancing:...
```

**Deploy:**
```bash
./deploy-aws.sh

# View logs
aws logs tail /ecs/sql-monitor-grafana --follow

# Update service
./deploy-aws.sh  # Automatically detects and updates
```

**Features:**
- ✅ Auto-scaling (1-10 tasks)
- ✅ ALB integration
- ✅ VPC networking
- ✅ Secrets Manager integration
- ✅ CloudWatch Logs

### Google Cloud Run

**Cost:** ~$10-15/month

**Architecture:**
```
Internet → Cloud Load Balancer → Cloud Run Service → Cloud SQL
                    ↓
              Cloud Logging
                    ↓
            Secret Manager
```

**Configuration:**

```yaml
gcp:
  cloud_run:
    service_name: sql-monitor-grafana
    region: us-central1
    cpu: 1
    memory: 2Gi

    # Scaling
    min_instances: 1
    max_instances: 3

    # Networking
    vpc_connector: projects/PROJECT/locations/REGION/connectors/CONNECTOR
    ingress: all  # all, internal, internal-and-cloud-load-balancing
```

**Deploy:**
```bash
./deploy-gcp.sh

# View logs
gcloud logging read "resource.type=cloud_run_revision" --limit 50

# Access service
gcloud run services describe sql-monitor-grafana --region us-central1
```

**Features:**
- ✅ Serverless (pay-per-request)
- ✅ Auto-scaling (0-1000 instances)
- ✅ Custom domains
- ✅ Secret Manager integration
- ✅ VPC connector support

### Azure Container Instances

**Cost:** ~$20-30/month

**Architecture:**
```
Internet → App Gateway → Container Instance → Azure SQL
                    ↓
              Azure Monitor
                    ↓
            Key Vault
```

**Configuration:**

```yaml
azure:
  container_instances:
    resource_group: rg-sqlmonitor
    container_name: grafana-sqlmonitor
    location: eastus
    cpu: 2
    memory: 4

    # Networking
    dns_label: sqlmonitor-grafana
    vnet:
      enabled: false
      name: vnet-sqlmonitor
```

**Deploy:**
```bash
./deploy-azure.sh

# View logs
az container logs --resource-group rg-sqlmonitor --name grafana-sqlmonitor

# SSH into container
az container exec --resource-group rg-sqlmonitor --name grafana-sqlmonitor --exec-command /bin/bash
```

**Features:**
- ✅ Simple deployment
- ✅ VNET integration
- ✅ Key Vault integration
- ✅ Azure Monitor
- ✅ SSH access

## Multi-Server Setup

### Automatic Server Registration

Configure monitored servers in `deployment-config.yaml`:

```yaml
monitored_servers:
  - name: prod-sql-01.company.com,1433
    environment: Production
    collect_interval_minutes: 5
    linked_server_name: PRODSQL01

  - name: prod-sql-02.company.com,1433
    environment: Production
    collect_interval_minutes: 5
    linked_server_name: PRODSQL02

  - name: dev-sql-01.company.com,1433
    environment: Development
    collect_interval_minutes: 15
    linked_server_name: DEVSQL01
```

### How It Works

1. **Deployment Script Reads Config**
   - Parses `monitored_servers` array

2. **Servers Registered in MonitoringDB**
   ```sql
   INSERT INTO dbo.Servers (ServerName, Environment, IsActive)
   VALUES ('prod-sql-01.company.com,1433', 'Production', 1);
   ```

3. **Linked Servers Created**
   ```sql
   EXEC sp_addlinkedserver @server = 'PRODSQL01', @datasrc = 'prod-sql-01.company.com,1433';
   ```

4. **SQL Agent Jobs Deployed**
   - Collect metrics every N minutes
   - Sync DBATools data
   - Run alert rules

5. **Grafana Dashboards Show All Servers**
   - Server dropdown variable
   - Multi-server charts

### Manual Server Addition

```bash
# SSH into container (Azure example)
az container exec --resource-group rg-sqlmonitor --name grafana-sqlmonitor --exec-command /bin/bash

# Inside container, run SQL
sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P "$MONITORINGDB_PASSWORD" -C -d MonitoringDB -Q "
EXEC dbo.usp_AddServer
    @ServerName = 'new-sql-server.company.com,1433',
    @Environment = 'Production';
"
```

## SSL/TLS Configuration

### Option 1: Cloudflare (FREE, Recommended)

```yaml
ssl:
  provider: cloudflare

  cloudflare:
    enabled: true
    zone_id: your-zone-id
```

**Steps:**
1. Add domain to Cloudflare
2. Point DNS: `monitor.company.com` → Container IP
3. SSL/TLS → Full (automatic)
4. Done! ✅

**Pros:**
- $0/month
- 5-minute setup
- DDoS protection
- Global CDN

### Option 2: Let's Encrypt (via SSL Proxy)

```yaml
ssl:
  provider: letsencrypt

  letsencrypt:
    enabled: true
    email: admin@company.com
    domain: monitor.company.com
```

Deploy SSL proxy container:
```bash
cd ../ssl-proxy
./deploy-ssl-proxy.sh
```

**Cost:** ~$3/month (additional container)

### Option 3: Bring Your Own Certificate

```yaml
ssl:
  provider: custom_cert

  custom_cert:
    enabled: true
    cert_path: /secrets/cert.pem
    key_path: /secrets/key.pem
```

Mount certificate as volume or secret.

## Monitoring & Logging

### Health Checks

All deployments include health checks:

```bash
# HTTP health check endpoint
curl http://your-grafana-url/api/health

# Response:
{
  "commit": "895fbafb7a",
  "database": "ok",
  "version": "10.2.0"
}
```

### Logging

**AWS CloudWatch:**
```bash
aws logs tail /ecs/sql-monitor-grafana --follow
```

**GCP Cloud Logging:**
```bash
gcloud logging read "resource.type=cloud_run_revision" --limit 50
```

**Azure Monitor:**
```bash
az container logs --resource-group rg-sqlmonitor --name grafana-sqlmonitor
```

### Metrics

Monitor container metrics:
- CPU usage
- Memory usage
- Request count
- Error rate
- Response time

## Cost Optimization

### Development/Staging Auto-Shutdown

```yaml
cost:
  auto_shutdown:
    enabled: true
    schedule: "0 18 * * 1-5"  # Weekdays at 6 PM
    timezone: America/New_York
```

### Spot Instances (AWS)

```yaml
aws:
  ecs:
    launch_type: FARGATE_SPOT

cost:
  spot_instances:
    enabled: true
    max_price: "0.05"
```

**Savings:** 70-90% vs on-demand

### Right-Sizing

| Environment | CPU | Memory | Cost/Month |
|-------------|-----|--------|------------|
| Dev/Test    | 0.5 | 1 GB   | $5-10      |
| Staging     | 1   | 2 GB   | $10-15     |
| Production  | 2   | 4 GB   | $20-30     |

## Troubleshooting

### Container Won't Start

**Check logs:**
```bash
# AWS
aws ecs describe-tasks --cluster sql-monitor-cluster --tasks TASK_ID

# GCP
gcloud run services logs read sql-monitor-grafana --limit 100

# Azure
az container logs --resource-group rg-sqlmonitor --name grafana-sqlmonitor
```

**Common issues:**
- Database connection refused → Check network/firewall
- Secret not found → Verify secret name in Key Vault/Secrets Manager
- Image pull error → Verify registry credentials

### Database Connection Failed

```bash
# Test from container
az container exec --resource-group rg-sqlmonitor --name grafana-sqlmonitor \
  --exec-command "sqlcmd -S sqltest.schoolvision.net,14333 -U sv -P \$MONITORINGDB_PASSWORD -C -Q 'SELECT @@VERSION'"
```

**Check:**
- ✅ Server allows remote connections
- ✅ Port 14333 open in firewall
- ✅ SQL Server TCP/IP enabled
- ✅ Container has network access

### Dashboards Not Loading

**Check datasource:**
```bash
curl -u admin:YourPassword http://your-grafana-url/api/datasources
```

**Verify UID matches:** Should be `PACBEEDECF159CDCA`

**Re-download dashboards:**
```bash
# Set environment variable
DASHBOARD_DOWNLOAD=true
GITHUB_REPO=https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/public/dashboards

# Restart container
az container restart --resource-group rg-sqlmonitor --name grafana-sqlmonitor
```

### Performance Issues

**Increase resources:**
```yaml
# deployment-config.yaml
azure:
  container_instances:
    cpu: 4      # Increase from 2
    memory: 8   # Increase from 4
```

Redeploy:
```bash
./deploy-azure.sh
```

## Migration Between Clouds

### AWS → GCP

1. Export Grafana configuration
2. Update `deployment-config.yaml`:
   ```yaml
   registry:
     type: gcr  # Change from ecr
   ```
3. Deploy to GCP:
   ```bash
   ./deploy-gcp.sh
   ```
4. Update DNS to new Cloud Run URL
5. Decommission AWS resources

### Multi-Cloud Active-Active

Run containers in multiple clouds simultaneously:

```yaml
# AWS MonitoringDB → AWS Grafana
aws:
  ecs:
    service_name: sql-monitor-grafana-aws

# GCP MonitoringDB → GCP Grafana
gcp:
  cloud_run:
    service_name: sql-monitor-grafana-gcp
```

Use DNS load balancing or GeoDNS for failover.

## Support

- **Documentation**: https://github.com/dbbuilder/sql-monitor
- **Issues**: https://github.com/dbbuilder/sql-monitor/issues
- **Discussions**: https://github.com/dbbuilder/sql-monitor/discussions

## License

Apache 2.0 - See [LICENSE](../LICENSE)
