# SQL Monitor - AWS Deployment Guide

Complete step-by-step guide for deploying SQL Monitor to AWS using ECS Fargate.

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

This guide deploys SQL Monitor to AWS using:
- **ECS Fargate**: Serverless container orchestration
- **ECR**: Container image registry
- **Secrets Manager**: Secure credential storage
- **CloudWatch**: Logging and monitoring
- **ALB** (optional): Load balancer for high availability
- **VPC**: Network isolation

**Deployment Time**: 30-45 minutes
**Monthly Cost**: $15-25 (single instance) or $40-60 (HA with ALB)

## Prerequisites

### Required Tools

```bash
# Install AWS CLI (macOS)
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /

# Install AWS CLI (Linux)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

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

### AWS Account Setup

```bash
# Configure AWS credentials
aws configure
# AWS Access Key ID: [Your access key]
# AWS Secret Access Key: [Your secret key]
# Default region name: us-east-1
# Default output format: json

# Verify authentication
aws sts get-caller-identity
```

### Required Permissions

Your AWS IAM user/role needs these permissions:
- ECS: Create/manage clusters, services, task definitions
- ECR: Create repositories, push images
- Secrets Manager: Create/read secrets
- CloudWatch: Create log groups, write logs
- IAM: Create execution roles for ECS tasks
- VPC: Describe VPCs, subnets, security groups
- (Optional) ALB: Create/configure load balancers

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                           AWS Account                            │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                       VPC (10.0.0.0/16)                     │ │
│  │                                                             │ │
│  │  ┌──────────────────┐      ┌──────────────────┐           │ │
│  │  │ Public Subnet A  │      │ Public Subnet B  │           │ │
│  │  │   10.0.1.0/24    │      │   10.0.2.0/24    │           │ │
│  │  │                  │      │                  │           │ │
│  │  │  ┌───────────┐   │      │  ┌───────────┐   │           │ │
│  │  │  │    ALB    │   │      │  │    ALB    │   │           │ │
│  │  │  │ (Optional)│   │      │  │ (Optional)│   │           │ │
│  │  │  └─────┬─────┘   │      │  └─────┬─────┘   │           │ │
│  │  │        │         │      │        │         │           │ │
│  │  │  ┌─────▼─────┐   │      │  ┌─────▼─────┐   │           │ │
│  │  │  │ECS Fargate│   │      │  │ECS Fargate│   │           │ │
│  │  │  │  Grafana  │   │      │  │  Grafana  │   │           │ │
│  │  │  │ Port 3000 │   │      │  │ Port 3000 │   │           │ │
│  │  │  └───────────┘   │      │  └───────────┘   │           │ │
│  │  └──────────────────┘      └──────────────────┘           │ │
│  │                                                             │ │
│  │  Internet Gateway                                           │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────┐  │
│  │   ECR Registry   │  │ Secrets Manager  │  │  CloudWatch  │  │
│  │  (Docker Images) │  │  (Passwords)     │  │    (Logs)    │  │
│  └──────────────────┘  └──────────────────┘  └──────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                            │
                            │ SQL connection (port 1433 or 14333)
                            ▼
                ┌────────────────────────┐
                │   SQL Server (On-Prem  │
                │   or AWS RDS/EC2)      │
                │   MonitoringDB         │
                └────────────────────────┘
```

## Cost Estimate

### Monthly Costs (us-east-1, as of 2025)

**Single Instance (Non-HA)**:
| Service | Configuration | Monthly Cost |
|---------|--------------|--------------|
| ECS Fargate | 1 vCPU, 2 GB RAM, 24/7 | $14.60 |
| ECR Storage | 5 GB images | $0.50 |
| Data Transfer | 10 GB outbound | $0.90 |
| CloudWatch Logs | 5 GB ingestion, 30 day retention | $2.50 |
| Secrets Manager | 2 secrets | $0.80 |
| **Total** | | **~$19.30/month** |

**High Availability (with ALB)**:
| Service | Configuration | Monthly Cost |
|---------|--------------|--------------|
| ECS Fargate | 2 tasks, 1 vCPU, 2 GB RAM each | $29.20 |
| ALB | 1 load balancer | $16.20 |
| ECR Storage | 5 GB images | $0.50 |
| Data Transfer | 20 GB outbound | $1.80 |
| CloudWatch Logs | 10 GB ingestion | $5.00 |
| Secrets Manager | 2 secrets | $0.80 |
| **Total** | | **~$53.50/month** |

**Cost Optimization Tips**:
- Use Fargate Spot (70% savings, but may be interrupted)
- Reduce log retention (7 days instead of 30)
- Use compression for data transfer
- Schedule tasks to stop during non-business hours (dev/test)

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
  region: us-east-1  # Change to your preferred region

# MonitoringDB connection
monitoringdb:
  server: your-sql-server.example.com  # Your SQL Server hostname
  port: 1433  # Or 14333 if using custom port
  database: MonitoringDB
  username: monitor_api  # SQL Server login with read access
  password_env: MONITORINGDB_PASSWORD  # Secret name in AWS Secrets Manager

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

# Container registry (AWS ECR)
registry:
  type: ecr
  ecr:
    account_id: "123456789012"  # Your AWS account ID
    region: us-east-1
    repository: sql-monitor-grafana

# Grafana configuration
grafana:
  admin_password_env: GRAFANA_ADMIN_PASSWORD
  root_url: http://your-grafana-url.com  # Will update after deployment

  dashboards:
    download_from_github: true
    github_repo: https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/public/dashboards

# AWS-specific configuration
aws:
  ecs:
    cluster_name: sql-monitor-cluster
    service_name: sql-monitor-grafana
    cpu: 1024  # 1 vCPU (256, 512, 1024, 2048, 4096)
    memory: 2048  # 2 GB (512, 1024, 2048, 4096, 8192)

    # Networking
    vpc_id: vpc-xxxxxxxxx  # Your VPC ID (or leave empty to use default)
    subnets:  # Public subnets with internet gateway
      - subnet-xxxxxxxxx
      - subnet-yyyyyyyyy
    security_groups:  # Will create default if not specified
      - sg-xxxxxxxxx

    # Load Balancer (optional, for HA)
    load_balancer:
      enabled: false  # Set to true for HA setup
      target_group_arn: ""  # Leave empty to create new

    # Secrets
    secrets:
      monitoringdb_password_arn: arn:aws:secretsmanager:us-east-1:123456789012:secret:sql-monitor/monitoringdb-password
      grafana_password_arn: arn:aws:secretsmanager:us-east-1:123456789012:secret:sql-monitor/grafana-admin-password
```

### Step 2: Set Up Database (MonitoringDB)

**Option A: Existing SQL Server (On-Premise or EC2)**

```bash
# Connect to SQL Server
sqlcmd -S your-sql-server.example.com -U sa -P YourPassword -C

# Run deployment scripts (from repository root)
:r database/01-create-database.sql
:r database/02-create-tables.sql
:r database/03-create-partitions.sql
:r database/04-create-procedures.sql
:r database/05-create-rds-equivalent-procedures.sql
# ... (run all scripts in order)

# Or use deployment script
sqlcmd -S your-sql-server.example.com -U sa -P YourPassword -C -i database/deploy-all.sql

# Create dedicated login for API
CREATE LOGIN monitor_api WITH PASSWORD = 'SecurePassword123!';
USE MonitoringDB;
CREATE USER monitor_api FOR LOGIN monitor_api;
ALTER ROLE db_datareader ADD MEMBER monitor_api;
ALTER ROLE db_datawriter ADD MEMBER monitor_api;
GRANT EXECUTE TO monitor_api;
GO
```

**Option B: AWS RDS for SQL Server**

```bash
# Create RDS instance (if not exists)
aws rds create-db-instance \
    --db-instance-identifier sql-monitor-db \
    --db-instance-class db.t3.small \
    --engine sqlserver-ex \
    --master-username admin \
    --master-user-password YourStrongPassword123! \
    --allocated-storage 20 \
    --vpc-security-group-ids sg-xxxxxxxxx \
    --db-subnet-group-name default \
    --publicly-accessible \
    --backup-retention-period 7

# Wait for instance to be available (5-10 minutes)
aws rds wait db-instance-available --db-instance-identifier sql-monitor-db

# Get endpoint
aws rds describe-db-instances \
    --db-instance-identifier sql-monitor-db \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text

# Connect and deploy schema
sqlcmd -S your-rds-endpoint.rds.amazonaws.com -U admin -P YourStrongPassword123! -C -i database/deploy-all.sql
```

### Step 3: Store Secrets in AWS Secrets Manager

```bash
# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $AWS_ACCOUNT_ID"

# Create MonitoringDB password secret
aws secretsmanager create-secret \
    --name sql-monitor/monitoringdb-password \
    --description "SQL Monitor MonitoringDB password" \
    --secret-string "SecurePassword123!" \
    --region us-east-1

# Create Grafana admin password secret
aws secretsmanager create-secret \
    --name sql-monitor/grafana-admin-password \
    --description "SQL Monitor Grafana admin password" \
    --secret-string "Admin123!Secure" \
    --region us-east-1

# Verify secrets created
aws secretsmanager list-secrets --region us-east-1 | grep sql-monitor

# Get secret ARNs (needed for configuration)
aws secretsmanager describe-secret \
    --secret-id sql-monitor/monitoringdb-password \
    --region us-east-1 \
    --query ARN \
    --output text

aws secretsmanager describe-secret \
    --secret-id sql-monitor/grafana-admin-password \
    --region us-east-1 \
    --query ARN \
    --output text

# Copy ARNs to deployment-config.yaml under aws.ecs.secrets
```

### Step 4: Create VPC and Networking (if needed)

**Option A: Use Existing VPC**

```bash
# List VPCs
aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,CidrBlock,Tags[?Key==`Name`].Value|[0]]' --output table

# List subnets
aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=vpc-xxxxxxxxx" \
    --query 'Subnets[*].[SubnetId,CidrBlock,AvailabilityZone,MapPublicIpOnLaunch]' \
    --output table

# List security groups
aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=vpc-xxxxxxxxx" \
    --query 'SecurityGroups[*].[GroupId,GroupName,Description]' \
    --output table
```

**Option B: Create New VPC**

```bash
# Create VPC
VPC_ID=$(aws ec2 create-vpc \
    --cidr-block 10.0.0.0/16 \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=sql-monitor-vpc}]' \
    --query Vpc.VpcId \
    --output text)

echo "VPC ID: $VPC_ID"

# Create Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway \
    --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=sql-monitor-igw}]' \
    --query InternetGateway.InternetGatewayId \
    --output text)

aws ec2 attach-internet-gateway \
    --vpc-id $VPC_ID \
    --internet-gateway-id $IGW_ID

# Create public subnets (2 for HA)
SUBNET_1=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.1.0/24 \
    --availability-zone us-east-1a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=sql-monitor-subnet-1}]' \
    --query Subnet.SubnetId \
    --output text)

SUBNET_2=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.2.0/24 \
    --availability-zone us-east-1b \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=sql-monitor-subnet-2}]' \
    --query Subnet.SubnetId \
    --output text)

echo "Subnet 1: $SUBNET_1"
echo "Subnet 2: $SUBNET_2"

# Enable auto-assign public IP
aws ec2 modify-subnet-attribute \
    --subnet-id $SUBNET_1 \
    --map-public-ip-on-launch

aws ec2 modify-subnet-attribute \
    --subnet-id $SUBNET_2 \
    --map-public-ip-on-launch

# Create route table
ROUTE_TABLE_ID=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=sql-monitor-rt}]' \
    --query RouteTable.RouteTableId \
    --output text)

# Add route to internet gateway
aws ec2 create-route \
    --route-table-id $ROUTE_TABLE_ID \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id $IGW_ID

# Associate route table with subnets
aws ec2 associate-route-table \
    --subnet-id $SUBNET_1 \
    --route-table-id $ROUTE_TABLE_ID

aws ec2 associate-route-table \
    --subnet-id $SUBNET_2 \
    --route-table-id $ROUTE_TABLE_ID

# Create security group
SG_ID=$(aws ec2 create-security-group \
    --group-name sql-monitor-sg \
    --description "SQL Monitor security group" \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=sql-monitor-sg}]' \
    --query GroupId \
    --output text)

# Allow inbound HTTP (port 3000 for Grafana)
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 3000 \
    --cidr 0.0.0.0/0

# Allow outbound (all traffic)
aws ec2 authorize-security-group-egress \
    --group-id $SG_ID \
    --protocol -1 \
    --cidr 0.0.0.0/0

echo "Security Group ID: $SG_ID"

# Update deployment-config.yaml with these values
echo ""
echo "Update deployment-config.yaml:"
echo "  vpc_id: $VPC_ID"
echo "  subnets: [$SUBNET_1, $SUBNET_2]"
echo "  security_groups: [$SG_ID]"
```

### Step 5: Create ECR Repository

```bash
# Create ECR repository
aws ecr create-repository \
    --repository-name sql-monitor-grafana \
    --region us-east-1 \
    --image-scanning-configuration scanOnPush=true \
    --tags Key=Project,Value=sql-monitor

# Get repository URI
REPOSITORY_URI=$(aws ecr describe-repositories \
    --repository-names sql-monitor-grafana \
    --region us-east-1 \
    --query 'repositories[0].repositoryUri' \
    --output text)

echo "ECR Repository URI: $REPOSITORY_URI"
```

### Step 6: Build and Push Docker Image

```bash
# Navigate to project root
cd /path/to/sql-monitor

# Login to ECR
aws ecr get-login-password --region us-east-1 | \
    docker login --username AWS --password-stdin $REPOSITORY_URI

# Build image
docker build -f deployment/Dockerfile.grafana -t sql-monitor-grafana:latest .

# Tag image
docker tag sql-monitor-grafana:latest $REPOSITORY_URI:latest
docker tag sql-monitor-grafana:latest $REPOSITORY_URI:$(date +%Y%m%d-%H%M%S)

# Push image
docker push $REPOSITORY_URI:latest
docker push $REPOSITORY_URI:$(date +%Y%m%d-%H%M%S)

# Verify image pushed
aws ecr list-images \
    --repository-name sql-monitor-grafana \
    --region us-east-1
```

### Step 7: Create ECS Cluster

```bash
# Create ECS cluster
aws ecs create-cluster \
    --cluster-name sql-monitor-cluster \
    --region us-east-1 \
    --tags key=Project,value=sql-monitor

# Verify cluster created
aws ecs describe-clusters \
    --clusters sql-monitor-cluster \
    --region us-east-1
```

### Step 8: Create IAM Roles

```bash
# Create task execution role (allows ECS to pull images and secrets)
cat > task-execution-role-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
    --role-name sql-monitor-task-execution-role \
    --assume-role-policy-document file://task-execution-role-trust-policy.json

# Attach managed policies
aws iam attach-role-policy \
    --role-name sql-monitor-task-execution-role \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

# Create policy for Secrets Manager access
cat > secrets-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "arn:aws:secretsmanager:us-east-1:$AWS_ACCOUNT_ID:secret:sql-monitor/*"
      ]
    }
  ]
}
EOF

aws iam create-policy \
    --policy-name sql-monitor-secrets-policy \
    --policy-document file://secrets-policy.json

aws iam attach-role-policy \
    --role-name sql-monitor-task-execution-role \
    --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/sql-monitor-secrets-policy

# Get role ARN (needed for task definition)
TASK_EXECUTION_ROLE_ARN=$(aws iam get-role \
    --role-name sql-monitor-task-execution-role \
    --query Role.Arn \
    --output text)

echo "Task Execution Role ARN: $TASK_EXECUTION_ROLE_ARN"
```

### Step 9: Create ECS Task Definition

```bash
# Read configuration values
MONITORINGDB_SERVER=$(yq eval '.monitoringdb.server' deployment-config.yaml)
MONITORINGDB_PORT=$(yq eval '.monitoringdb.port' deployment-config.yaml)
MONITORINGDB_DATABASE=$(yq eval '.monitoringdb.database' deployment-config.yaml)
MONITORINGDB_USER=$(yq eval '.monitoringdb.username' deployment-config.yaml)
MONITORINGDB_PASSWORD_ARN=$(yq eval '.aws.ecs.secrets.monitoringdb_password_arn' deployment-config.yaml)
GRAFANA_PASSWORD_ARN=$(yq eval '.aws.ecs.secrets.grafana_password_arn' deployment-config.yaml)
DASHBOARD_DOWNLOAD=$(yq eval '.grafana.dashboards.download_from_github' deployment-config.yaml)
GITHUB_REPO=$(yq eval '.grafana.dashboards.github_repo' deployment-config.yaml)

# Create task definition JSON
cat > task-definition.json <<EOF
{
  "family": "sql-monitor-grafana",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "1024",
  "memory": "2048",
  "executionRoleArn": "$TASK_EXECUTION_ROLE_ARN",
  "containerDefinitions": [
    {
      "name": "grafana",
      "image": "$REPOSITORY_URI:latest",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 3000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "MONITORINGDB_SERVER",
          "value": "$MONITORINGDB_SERVER"
        },
        {
          "name": "MONITORINGDB_PORT",
          "value": "$MONITORINGDB_PORT"
        },
        {
          "name": "MONITORINGDB_DATABASE",
          "value": "$MONITORINGDB_DATABASE"
        },
        {
          "name": "MONITORINGDB_USER",
          "value": "$MONITORINGDB_USER"
        },
        {
          "name": "DASHBOARD_DOWNLOAD",
          "value": "$DASHBOARD_DOWNLOAD"
        },
        {
          "name": "GITHUB_REPO",
          "value": "$GITHUB_REPO"
        }
      ],
      "secrets": [
        {
          "name": "MONITORINGDB_PASSWORD",
          "valueFrom": "$MONITORINGDB_PASSWORD_ARN"
        },
        {
          "name": "GF_SECURITY_ADMIN_PASSWORD",
          "valueFrom": "$GRAFANA_PASSWORD_ARN"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/sql-monitor-grafana",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:3000/api/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
EOF

# Create CloudWatch log group
aws logs create-log-group \
    --log-group-name /ecs/sql-monitor-grafana \
    --region us-east-1 || true

aws logs put-retention-policy \
    --log-group-name /ecs/sql-monitor-grafana \
    --retention-in-days 30 \
    --region us-east-1

# Register task definition
aws ecs register-task-definition \
    --cli-input-json file://task-definition.json \
    --region us-east-1
```

### Step 10: Create ECS Service

**Option A: Public IP (No Load Balancer)**

```bash
# Get subnet and security group from config
SUBNET_1=$(yq eval '.aws.ecs.subnets[0]' deployment-config.yaml)
SUBNET_2=$(yq eval '.aws.ecs.subnets[1]' deployment-config.yaml)
SG_ID=$(yq eval '.aws.ecs.security_groups[0]' deployment-config.yaml)

# Create service
aws ecs create-service \
    --cluster sql-monitor-cluster \
    --service-name sql-monitor-grafana \
    --task-definition sql-monitor-grafana \
    --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_1,$SUBNET_2],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
    --region us-east-1

# Wait for service to stabilize (2-3 minutes)
aws ecs wait services-stable \
    --cluster sql-monitor-cluster \
    --services sql-monitor-grafana \
    --region us-east-1

# Get public IP
TASK_ARN=$(aws ecs list-tasks \
    --cluster sql-monitor-cluster \
    --service-name sql-monitor-grafana \
    --region us-east-1 \
    --query 'taskArns[0]' \
    --output text)

ENI_ID=$(aws ecs describe-tasks \
    --cluster sql-monitor-cluster \
    --tasks $TASK_ARN \
    --region us-east-1 \
    --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' \
    --output text)

PUBLIC_IP=$(aws ec2 describe-network-interfaces \
    --network-interface-ids $ENI_ID \
    --region us-east-1 \
    --query 'NetworkInterfaces[0].Association.PublicIp' \
    --output text)

echo ""
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo "Grafana URL: http://$PUBLIC_IP:3000"
echo "Username: admin"
echo "Password: (from Secrets Manager)"
echo "========================================="
```

**Option B: With Application Load Balancer (HA)**

```bash
# Create ALB
ALB_ARN=$(aws elbv2 create-load-balancer \
    --name sql-monitor-alb \
    --subnets $SUBNET_1 $SUBNET_2 \
    --security-groups $SG_ID \
    --region us-east-1 \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text)

# Create target group
TG_ARN=$(aws elbv2 create-target-group \
    --name sql-monitor-tg \
    --protocol HTTP \
    --port 3000 \
    --vpc-id $VPC_ID \
    --target-type ip \
    --health-check-path /api/health \
    --health-check-interval-seconds 30 \
    --health-check-timeout-seconds 5 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 3 \
    --region us-east-1 \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

# Create listener
aws elbv2 create-listener \
    --load-balancer-arn $ALB_ARN \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn=$TG_ARN \
    --region us-east-1

# Create ECS service with ALB
aws ecs create-service \
    --cluster sql-monitor-cluster \
    --service-name sql-monitor-grafana \
    --task-definition sql-monitor-grafana \
    --desired-count 2 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_1,$SUBNET_2],securityGroups=[$SG_ID]}" \
    --load-balancers "targetGroupArn=$TG_ARN,containerName=grafana,containerPort=3000" \
    --health-check-grace-period-seconds 60 \
    --region us-east-1

# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns $ALB_ARN \
    --region us-east-1 \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

echo ""
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo "Grafana URL: http://$ALB_DNS"
echo "Username: admin"
echo "Password: (from Secrets Manager)"
echo "========================================="
```

## Configuration

### DNS Setup (Optional)

```bash
# If you have Route 53 hosted zone
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
    --query 'HostedZones[?Name==`example.com.`].Id' \
    --output text | cut -d'/' -f3)

# Create CNAME record pointing to ALB
cat > change-batch.json <<EOF
{
  "Changes": [
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "grafana.example.com",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [
          {
            "Value": "$ALB_DNS"
          }
        ]
      }
    }
  ]
}
EOF

aws route53 change-resource-record-sets \
    --hosted-zone-id $HOSTED_ZONE_ID \
    --change-batch file://change-batch.json
```

### SSL/TLS Setup

**Option 1: AWS Certificate Manager (ACM) + ALB**

```bash
# Request certificate
CERT_ARN=$(aws acm request-certificate \
    --domain-name grafana.example.com \
    --validation-method DNS \
    --region us-east-1 \
    --query CertificateArn \
    --output text)

# Get validation records
aws acm describe-certificate \
    --certificate-arn $CERT_ARN \
    --region us-east-1 \
    --query 'Certificate.DomainValidationOptions[0].ResourceRecord'

# Add CNAME record to Route 53 (from output above)
# Wait for validation (5-30 minutes)

# Add HTTPS listener to ALB
aws elbv2 create-listener \
    --load-balancer-arn $ALB_ARN \
    --protocol HTTPS \
    --port 443 \
    --certificates CertificateArn=$CERT_ARN \
    --default-actions Type=forward,TargetGroupArn=$TG_ARN \
    --region us-east-1

# Redirect HTTP to HTTPS
aws elbv2 modify-listener \
    --listener-arn <HTTP_LISTENER_ARN> \
    --default-actions Type=redirect,RedirectConfig={Protocol=HTTPS,Port=443,StatusCode=HTTP_301}
```

**Option 2: Cloudflare (Free SSL)**

See main deployment guide for Cloudflare setup instructions.

## Verification

### Check Service Status

```bash
# Check service status
aws ecs describe-services \
    --cluster sql-monitor-cluster \
    --services sql-monitor-grafana \
    --region us-east-1 \
    --query 'services[0].[serviceName,status,runningCount,desiredCount]' \
    --output table

# Check tasks
aws ecs list-tasks \
    --cluster sql-monitor-cluster \
    --service-name sql-monitor-grafana \
    --region us-east-1

# Check task health
aws ecs describe-tasks \
    --cluster sql-monitor-cluster \
    --tasks <TASK_ARN> \
    --region us-east-1 \
    --query 'tasks[0].[lastStatus,healthStatus,containers[0].lastStatus]' \
    --output table
```

### View Logs

```bash
# Stream logs in real-time
aws logs tail /ecs/sql-monitor-grafana --follow --region us-east-1

# Get last 100 lines
aws logs tail /ecs/sql-monitor-grafana --since 10m --region us-east-1

# Search for errors
aws logs filter-log-events \
    --log-group-name /ecs/sql-monitor-grafana \
    --filter-pattern "ERROR" \
    --region us-east-1
```

### Test Grafana Access

```bash
# Health check
curl http://$PUBLIC_IP:3000/api/health

# Login page
curl -I http://$PUBLIC_IP:3000/login

# Test authentication
curl -X POST http://$PUBLIC_IP:3000/api/login \
    -H "Content-Type: application/json" \
    -d '{"user":"admin","password":"<YOUR_PASSWORD>"}'
```

## Maintenance

### Update Container Image

```bash
# Build new image
docker build -f deployment/Dockerfile.grafana -t sql-monitor-grafana:latest .

# Tag and push
docker tag sql-monitor-grafana:latest $REPOSITORY_URI:latest
docker tag sql-monitor-grafana:latest $REPOSITORY_URI:v$(date +%Y%m%d-%H%M%S)
docker push $REPOSITORY_URI:latest
docker push $REPOSITORY_URI:v$(date +%Y%m%d-%H%M%S)

# Force new deployment
aws ecs update-service \
    --cluster sql-monitor-cluster \
    --service sql-monitor-grafana \
    --force-new-deployment \
    --region us-east-1

# Wait for deployment
aws ecs wait services-stable \
    --cluster sql-monitor-cluster \
    --services sql-monitor-grafana \
    --region us-east-1
```

### Update Secrets

```bash
# Update MonitoringDB password
aws secretsmanager update-secret \
    --secret-id sql-monitor/monitoringdb-password \
    --secret-string "NewPassword123!" \
    --region us-east-1

# Restart service to pick up new secret
aws ecs update-service \
    --cluster sql-monitor-cluster \
    --service sql-monitor-grafana \
    --force-new-deployment \
    --region us-east-1
```

### Scale Service

```bash
# Scale to 3 tasks
aws ecs update-service \
    --cluster sql-monitor-cluster \
    --service sql-monitor-grafana \
    --desired-count 3 \
    --region us-east-1

# Enable auto-scaling (requires Application Auto Scaling)
aws application-autoscaling register-scalable-target \
    --service-namespace ecs \
    --resource-id service/sql-monitor-cluster/sql-monitor-grafana \
    --scalable-dimension ecs:service:DesiredCount \
    --min-capacity 2 \
    --max-capacity 10 \
    --region us-east-1

# CPU-based auto-scaling policy
aws application-autoscaling put-scaling-policy \
    --policy-name sql-monitor-cpu-scaling \
    --service-namespace ecs \
    --resource-id service/sql-monitor-cluster/sql-monitor-grafana \
    --scalable-dimension ecs:service:DesiredCount \
    --policy-type TargetTrackingScaling \
    --target-tracking-scaling-policy-configuration '{
        "TargetValue": 70.0,
        "PredefinedMetricSpecification": {
            "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
        },
        "ScaleInCooldown": 300,
        "ScaleOutCooldown": 60
    }' \
    --region us-east-1
```

### Backup and Restore

```bash
# Backup Grafana dashboards (via API)
curl -u admin:<PASSWORD> http://$PUBLIC_IP:3000/api/search?type=dash-db | \
    jq -r '.[] | .uid' | \
    while read uid; do
        curl -u admin:<PASSWORD> http://$PUBLIC_IP:3000/api/dashboards/uid/$uid > dashboard-$uid.json
    done

# Export task definition
aws ecs describe-task-definition \
    --task-definition sql-monitor-grafana \
    --region us-east-1 > task-definition-backup.json

# Backup MonitoringDB (from SQL Server)
sqlcmd -S $MONITORINGDB_SERVER -U monitor_api -P <PASSWORD> -C -Q "BACKUP DATABASE MonitoringDB TO DISK = '/backups/MonitoringDB.bak' WITH COMPRESSION;"
```

## Troubleshooting

### Service Won't Start

```bash
# Check service events
aws ecs describe-services \
    --cluster sql-monitor-cluster \
    --services sql-monitor-grafana \
    --region us-east-1 \
    --query 'services[0].events[:5]' \
    --output table

# Check task stopped reason
aws ecs describe-tasks \
    --cluster sql-monitor-cluster \
    --tasks <TASK_ARN> \
    --region us-east-1 \
    --query 'tasks[0].[stoppedReason,containers[0].reason]'
```

### Database Connection Issues

```bash
# Test from container
aws ecs execute-command \
    --cluster sql-monitor-cluster \
    --task <TASK_ARN> \
    --container grafana \
    --interactive \
    --command "/bin/sh"

# Inside container:
apk add --no-cache mysql-client
mysql -h $MONITORINGDB_SERVER -P $MONITORINGDB_PORT -u $MONITORINGDB_USER -p

# Check security group rules
aws ec2 describe-security-groups \
    --group-ids $SG_ID \
    --query 'SecurityGroups[0].IpPermissionsEgress'
```

### High Costs

```bash
# Check resource utilization
aws ecs describe-tasks \
    --cluster sql-monitor-cluster \
    --tasks <TASK_ARN> \
    --include TAGS \
    --region us-east-1 \
    --query 'tasks[0].[cpu,memory,containers[0].cpuUtilization,containers[0].memoryUtilization]'

# Consider:
# - Reduce CPU/memory if underutilized
# - Use Fargate Spot (70% savings)
# - Stop service during non-business hours (dev/test)
# - Reduce log retention period
```

### Dashboard Not Loading

```bash
# Check dashboard download
aws logs filter-log-events \
    --log-group-name /ecs/sql-monitor-grafana \
    --filter-pattern "dashboard" \
    --region us-east-1

# Verify datasource
curl -u admin:<PASSWORD> http://$PUBLIC_IP:3000/api/datasources
```

## Scaling

### Vertical Scaling (Increase Resources)

```bash
# Update task definition with more CPU/memory
# Edit task-definition.json: "cpu": "2048", "memory": "4096"

# Register new version
aws ecs register-task-definition --cli-input-json file://task-definition.json

# Update service
aws ecs update-service \
    --cluster sql-monitor-cluster \
    --service sql-monitor-grafana \
    --task-definition sql-monitor-grafana:<NEW_REVISION> \
    --force-new-deployment \
    --region us-east-1
```

### Horizontal Scaling (More Tasks)

See "Scale Service" section under Maintenance.

## Security

### Network Security

```bash
# Restrict security group to specific IPs
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 3000 \
    --cidr 203.0.113.0/24  # Your office IP range

# Remove open access
aws ec2 revoke-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 3000 \
    --cidr 0.0.0.0/0
```

### IAM Least Privilege

```bash
# Create read-only SQL Server login
CREATE LOGIN monitor_readonly WITH PASSWORD = 'SecurePassword123!';
USE MonitoringDB;
CREATE USER monitor_readonly FOR LOGIN monitor_readonly;
ALTER ROLE db_datareader ADD MEMBER monitor_readonly;
GRANT EXECUTE ON SCHEMA::dbo TO monitor_readonly;  -- Only execute SPs
GO
```

### Secrets Rotation

```bash
# Enable automatic rotation (30 days)
aws secretsmanager rotate-secret \
    --secret-id sql-monitor/monitoringdb-password \
    --rotation-lambda-arn <LAMBDA_ARN> \
    --rotation-rules AutomaticallyAfterDays=30 \
    --region us-east-1
```

## Next Steps

1. **Configure DNS**: Point custom domain to ALB
2. **Enable SSL**: Use ACM certificate for HTTPS
3. **Set Up Monitoring**: CloudWatch alarms for task health
4. **Configure Backups**: Automate MonitoringDB backups
5. **Enable Auto-Scaling**: Scale based on CPU/memory
6. **Review Costs**: Use AWS Cost Explorer

## Support

- **AWS Documentation**: https://docs.aws.amazon.com/ecs/
- **GitHub Issues**: https://github.com/dbbuilder/sql-monitor/issues
- **Discussions**: https://github.com/dbbuilder/sql-monitor/discussions
