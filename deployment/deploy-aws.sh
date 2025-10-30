#!/bin/bash
# =====================================================
# SQL Monitor - AWS ECS Deployment Script
# =====================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/deployment-config.yaml}"

# =====================================================
# Load Configuration
# =====================================================

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    echo "Copy config-template.yaml to deployment-config.yaml and customize"
    exit 1
fi

# Parse YAML (requires yq or python)
if command -v yq &> /dev/null; then
    CLUSTER_NAME=$(yq eval '.aws.ecs.cluster_name' "$CONFIG_FILE")
    SERVICE_NAME=$(yq eval '.aws.ecs.service_name' "$CONFIG_FILE")
    TASK_FAMILY=$(yq eval '.aws.ecs.task_family' "$CONFIG_FILE")
    CPU=$(yq eval '.aws.ecs.cpu' "$CONFIG_FILE")
    MEMORY=$(yq eval '.aws.ecs.memory' "$CONFIG_FILE")
    REGION=$(yq eval '.project.region' "$CONFIG_FILE")
    ECR_ACCOUNT=$(yq eval '.registry.ecr.account_id' "$CONFIG_FILE")
    ECR_REGION=$(yq eval '.registry.ecr.region' "$CONFIG_FILE")
    ECR_REPO=$(yq eval '.registry.ecr.repository' "$CONFIG_FILE")
elif command -v python3 &> /dev/null; then
    # Fallback to Python YAML parsing
    CLUSTER_NAME=$(python3 -c "import yaml; print(yaml.safe_load(open('$CONFIG_FILE'))['aws']['ecs']['cluster_name'])")
    SERVICE_NAME=$(python3 -c "import yaml; print(yaml.safe_load(open('$CONFIG_FILE'))['aws']['ecs']['service_name'])")
    # ... etc
else
    echo "ERROR: yq or python3 required to parse configuration"
    exit 1
fi

ECR_URL="${ECR_ACCOUNT}.dkr.ecr.${ECR_REGION}.amazonaws.com"
IMAGE="${ECR_URL}/${ECR_REPO}:latest"

echo "==================================================================="
echo "SQL Monitor - AWS ECS Deployment"
echo "==================================================================="
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo "Image: $IMAGE"
echo "==================================================================="

# =====================================================
# Build and Push Docker Image
# =====================================================

echo "Building Docker image..."
cd "$SCRIPT_DIR/.."
docker build -f deployment/Dockerfile.grafana -t sql-monitor-grafana:latest .

echo "Tagging image for ECR..."
docker tag sql-monitor-grafana:latest "$IMAGE"

echo "Logging in to ECR..."
aws ecr get-login-password --region "$ECR_REGION" | \
    docker login --username AWS --password-stdin "$ECR_URL"

echo "Pushing image to ECR..."
docker push "$IMAGE"

# =====================================================
# Create ECS Task Definition
# =====================================================

echo "Creating ECS task definition..."

cat > /tmp/task-definition.json <<EOF
{
  "family": "${TASK_FAMILY}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "${CPU}",
  "memory": "${MEMORY}",
  "containerDefinitions": [
    {
      "name": "grafana",
      "image": "${IMAGE}",
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
          "value": "$(yq eval '.monitoringdb.server' "$CONFIG_FILE")"
        },
        {
          "name": "MONITORINGDB_PORT",
          "value": "$(yq eval '.monitoringdb.port' "$CONFIG_FILE")"
        },
        {
          "name": "MONITORINGDB_DATABASE",
          "value": "$(yq eval '.monitoringdb.database' "$CONFIG_FILE")"
        },
        {
          "name": "MONITORINGDB_USER",
          "value": "$(yq eval '.monitoringdb.username' "$CONFIG_FILE")"
        },
        {
          "name": "GF_SERVER_ROOT_URL",
          "value": "$(yq eval '.grafana.root_url' "$CONFIG_FILE")"
        },
        {
          "name": "DASHBOARD_DOWNLOAD",
          "value": "$(yq eval '.grafana.dashboards.download_from_github' "$CONFIG_FILE")"
        },
        {
          "name": "GITHUB_REPO",
          "value": "$(yq eval '.grafana.dashboards.github_repo' "$CONFIG_FILE")"
        }
      ],
      "secrets": [
        {
          "name": "MONITORINGDB_PASSWORD",
          "valueFrom": "$(yq eval '.aws.secrets.monitoringdb_password_arn' "$CONFIG_FILE")"
        },
        {
          "name": "GF_SECURITY_ADMIN_PASSWORD",
          "valueFrom": "$(yq eval '.aws.secrets.grafana_password_arn' "$CONFIG_FILE")"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/${TASK_FAMILY}",
          "awslogs-region": "${REGION}",
          "awslogs-stream-prefix": "grafana"
        }
      },
      "healthCheck": {
        "command": [
          "CMD-SHELL",
          "curl -f http://localhost:3000/api/health || exit 1"
        ],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
EOF

echo "Registering task definition..."
aws ecs register-task-definition \
    --cli-input-json file:///tmp/task-definition.json \
    --region "$REGION"

# =====================================================
# Create or Update ECS Service
# =====================================================

echo "Checking if service exists..."
if aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$REGION" \
    --query 'services[0].status' \
    --output text | grep -q ACTIVE; then

    echo "Updating existing service..."
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --task-definition "$TASK_FAMILY" \
        --force-new-deployment \
        --region "$REGION"
else
    echo "Creating new service..."

    VPC_SUBNETS=$(yq eval '.aws.ecs.subnets | join(",")' "$CONFIG_FILE")
    SECURITY_GROUPS=$(yq eval '.aws.ecs.security_groups | join(",")' "$CONFIG_FILE")

    aws ecs create-service \
        --cluster "$CLUSTER_NAME" \
        --service-name "$SERVICE_NAME" \
        --task-definition "$TASK_FAMILY" \
        --desired-count 1 \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[$VPC_SUBNETS],securityGroups=[$SECURITY_GROUPS],assignPublicIp=ENABLED}" \
        --region "$REGION"
fi

echo "==================================================================="
echo "Deployment Complete!"
echo "==================================================================="
echo "Service: $SERVICE_NAME"
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo ""
echo "Check status:"
echo "  aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $REGION"
echo ""
echo "View logs:"
echo "  aws logs tail /ecs/$TASK_FAMILY --follow --region $REGION"
echo "==================================================================="
