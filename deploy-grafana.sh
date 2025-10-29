#!/bin/bash
# =============================================
# SQL Monitor - Deploy Central Grafana Server
# Purpose: Deploys only the Grafana container (visualization layer)
# Can be deployed to: Local server, Azure, AWS, or any Docker host
# =============================================

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================
# Configuration
# =============================================

# Deployment target (local, azure, aws)
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-local}"

# Grafana configuration
GRAFANA_PORT="${GRAFANA_PORT:-9002}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-Admin123!}"

# MonitoringDB connection (the database this Grafana will query)
MONITORINGDB_SERVER="${MONITORINGDB_SERVER}"
MONITORINGDB_PORT="${MONITORINGDB_PORT:-1433}"
MONITORINGDB_DATABASE="${MONITORINGDB_DATABASE:-MonitoringDB}"
MONITORINGDB_USER="${MONITORINGDB_USER}"
MONITORINGDB_PASSWORD="${MONITORINGDB_PASSWORD}"

# Client identification
CLIENT_NAME="${CLIENT_NAME:-Client1}"
CLIENT_ORG="${CLIENT_ORG:-ArcTrade}"

# Azure-specific (if DEPLOYMENT_TARGET=azure)
AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP}"
AZURE_CONTAINER_NAME="${AZURE_CONTAINER_NAME:-grafana-${CLIENT_NAME,,}}"
AZURE_LOCATION="${AZURE_LOCATION:-eastus}"
AZURE_DNS_LABEL="${AZURE_DNS_LABEL:-${CLIENT_NAME,,}-monitor}"

# AWS-specific (if DEPLOYMENT_TARGET=aws)
AWS_CLUSTER="${AWS_CLUSTER}"
AWS_TASK_DEFINITION="${AWS_TASK_DEFINITION:-grafana-${CLIENT_NAME,,}}"
AWS_SERVICE_NAME="${AWS_SERVICE_NAME:-grafana-${CLIENT_NAME,,}}"

# =============================================
# Helper Functions
# =============================================

print_header() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
    echo ""
}

print_step() {
    echo "  $1"
}

print_success() {
    echo "  ✓ $1"
}

print_error() {
    echo "  ✗ $1" >&2
}

print_info() {
    echo "  ℹ  $1"
}

# =============================================
# Validation
# =============================================

validate_config() {
    print_header "Validating Configuration"

    local valid=true

    if [ -z "$MONITORINGDB_SERVER" ]; then
        print_error "MONITORINGDB_SERVER is required"
        valid=false
    fi

    if [ -z "$MONITORINGDB_USER" ]; then
        print_error "MONITORINGDB_USER is required"
        valid=false
    fi

    if [ -z "$MONITORINGDB_PASSWORD" ]; then
        print_error "MONITORINGDB_PASSWORD is required"
        valid=false
    fi

    if [ "$DEPLOYMENT_TARGET" = "azure" ]; then
        if [ -z "$AZURE_RESOURCE_GROUP" ]; then
            print_error "AZURE_RESOURCE_GROUP is required for Azure deployment"
            valid=false
        fi
    fi

    if [ "$DEPLOYMENT_TARGET" = "aws" ]; then
        if [ -z "$AWS_CLUSTER" ]; then
            print_error "AWS_CLUSTER is required for AWS deployment"
            valid=false
        fi
    fi

    if [ "$valid" = false ]; then
        exit 1
    fi

    print_success "Configuration valid"
}

# =============================================
# Datasource Configuration
# =============================================

create_datasource_config() {
    print_header "Creating Datasource Configuration"

    local datasource_file="$SCRIPT_DIR/dashboards/grafana/provisioning/datasources/monitoringdb.yaml"

    cat > "$datasource_file" <<EOF
apiVersion: 1

datasources:
  - name: MonitoringDB
    type: mssql
    access: proxy
    url: ${MONITORINGDB_SERVER}:${MONITORINGDB_PORT}
    database: ${MONITORINGDB_DATABASE}
    user: ${MONITORINGDB_USER}
    secureJsonData:
      password: ${MONITORINGDB_PASSWORD}
    jsonData:
      maxOpenConns: 10
      maxIdleConns: 2
      connMaxLifetime: 14400
      encrypt: 'true'
      tlsSkipVerify: true
    editable: false
    isDefault: true
EOF

    print_success "Datasource configuration created"
}

# =============================================
# Deployment Functions
# =============================================

deploy_local() {
    print_header "Deploying Grafana Locally (Docker Compose)"

    # Create docker-compose-grafana.yml
    cat > "$SCRIPT_DIR/docker-compose-grafana.yml" <<EOF
version: '3.8'

services:
  grafana:
    image: grafana/grafana-oss:10.2.0
    container_name: sql-monitor-grafana-${CLIENT_NAME,,}
    ports:
      - "${GRAFANA_PORT}:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
      - GF_SERVER_ROOT_URL=http://localhost:${GRAFANA_PORT}
      - GF_AUTH_ANONYMOUS_ENABLED=false
      - GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/var/lib/grafana/dashboards/00-dashboard-browser.json
      - GF_SERVER_DOMAIN=localhost
      - GF_INSTALL_PLUGINS=
      # Client branding
      - GF_USERS_DEFAULT_THEME=dark
      - GF_ANALYTICS_REPORTING_ENABLED=false
      - GF_ANALYTICS_CHECK_FOR_UPDATES=false
    volumes:
      - grafana-data-${CLIENT_NAME,,}:/var/lib/grafana
      - ./dashboards/grafana/provisioning/datasources:/etc/grafana/provisioning/datasources:ro
      - ./dashboards/grafana/provisioning/dashboards:/etc/grafana/provisioning/dashboards:ro
      - ./dashboards/grafana/dashboards:/var/lib/grafana/dashboards:ro
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:3000/api/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  grafana-data-${CLIENT_NAME,,}:
    driver: local
EOF

    print_step "Starting Grafana container..."
    docker compose -f docker-compose-grafana.yml up -d

    print_success "Grafana deployed locally on port ${GRAFANA_PORT}"
    print_info "Access at: http://localhost:${GRAFANA_PORT}"
    print_info "Username: admin"
    print_info "Password: ${GRAFANA_ADMIN_PASSWORD}"
}

deploy_azure() {
    print_header "Deploying Grafana to Azure Container Instances"

    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI not found. Install from: https://docs.microsoft.com/cli/azure/install-azure-cli"
        exit 1
    fi

    # Check if logged in
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Run: az login"
        exit 1
    fi

    print_step "Creating Azure Container Instance..."

    # Create connection string for environment variable
    local connection_string="Server=${MONITORINGDB_SERVER},${MONITORINGDB_PORT};Database=${MONITORINGDB_DATABASE};User Id=${MONITORINGDB_USER};Password=${MONITORINGDB_PASSWORD};Encrypt=True;TrustServerCertificate=True;"

    # GitHub repo URL for dashboard downloads
    local github_repo="${GITHUB_REPO:-https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/public}"
    local entrypoint_url="${github_repo}/grafana-entrypoint.sh"

    print_step "Using GitHub repo: $github_repo"
    print_step "Entrypoint script: $entrypoint_url"

    # Deploy container instance with GitHub-based dashboard download
    az container create \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "$AZURE_CONTAINER_NAME" \
        --image grafana/grafana-oss:10.2.0 \
        --os-type Linux \
        --dns-name-label "$AZURE_DNS_LABEL" \
        --ports 3000 \
        --cpu 2 \
        --memory 4 \
        --environment-variables \
            GF_SECURITY_ADMIN_PASSWORD="$GRAFANA_ADMIN_PASSWORD" \
            GF_SERVER_ROOT_URL="http://${AZURE_DNS_LABEL}.${AZURE_LOCATION}.azurecontainer.io" \
            GF_AUTH_ANONYMOUS_ENABLED=false \
            GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/var/lib/grafana/dashboards/00-dashboard-browser.json \
            GITHUB_REPO="$github_repo" \
            MONITORINGDB_SERVER="$MONITORINGDB_SERVER" \
            MONITORINGDB_PORT="$MONITORINGDB_PORT" \
            MONITORINGDB_DATABASE="$MONITORINGDB_DATABASE" \
            MONITORINGDB_USER="$MONITORINGDB_USER" \
            MONITORINGDB_PASSWORD="$MONITORINGDB_PASSWORD" \
        --command-line "/bin/sh -c 'apk add --no-cache wget && wget -O /tmp/entrypoint.sh ${entrypoint_url} && chmod +x /tmp/entrypoint.sh && /tmp/entrypoint.sh'" \
        --location "$AZURE_LOCATION"

    # Get FQDN
    local fqdn=$(az container show \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "$AZURE_CONTAINER_NAME" \
        --query ipAddress.fqdn \
        --output tsv)

    print_success "Grafana deployed to Azure Container Instances with GitHub dashboard integration"
    print_info "Access at: http://${fqdn}:3000"
    print_info "Username: admin"
    print_info "Password: ${GRAFANA_ADMIN_PASSWORD}"

    print_info ""
    print_info "Dashboards are being downloaded from GitHub: $github_repo"
    print_info "Wait 30-60 seconds for container startup and dashboard download"
    print_info "All 13 dashboards including blog articles will be available automatically"
}

deploy_aws() {
    print_header "Deploying Grafana to AWS ECS Fargate"

    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI not found. Install from: https://aws.amazon.com/cli/"
        exit 1
    fi

    print_step "Creating ECS Task Definition..."

    # Create task definition JSON
    cat > /tmp/grafana-task-def.json <<EOF
{
  "family": "${AWS_TASK_DEFINITION}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "1024",
  "memory": "2048",
  "containerDefinitions": [
    {
      "name": "grafana",
      "image": "grafana/grafana-oss:10.2.0",
      "portMappings": [
        {
          "containerPort": 3000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {"name": "GF_SECURITY_ADMIN_PASSWORD", "value": "${GRAFANA_ADMIN_PASSWORD}"},
        {"name": "GF_AUTH_ANONYMOUS_ENABLED", "value": "false"},
        {"name": "GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH", "value": "/var/lib/grafana/dashboards/00-dashboard-browser.json"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/grafana-${CLIENT_NAME,,}",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "grafana"
        }
      }
    }
  ]
}
EOF

    # Register task definition
    aws ecs register-task-definition --cli-input-json file:///tmp/grafana-task-def.json

    print_step "Creating ECS Service..."

    # Note: User needs to provide VPC/Subnet/Security Group
    print_info "Task definition created: ${AWS_TASK_DEFINITION}"
    print_info ""
    print_info "To complete deployment, run:"
    print_info "aws ecs create-service \\"
    print_info "  --cluster ${AWS_CLUSTER} \\"
    print_info "  --service-name ${AWS_SERVICE_NAME} \\"
    print_info "  --task-definition ${AWS_TASK_DEFINITION} \\"
    print_info "  --desired-count 1 \\"
    print_info "  --launch-type FARGATE \\"
    print_info "  --network-configuration 'awsvpcConfiguration={subnets=[subnet-xxx],securityGroups=[sg-xxx],assignPublicIp=ENABLED}'"

    print_success "Task definition registered"
}

# =============================================
# Main Deployment Logic
# =============================================

print_header "SQL Monitor - Deploy Central Grafana Server"
print_info "Client: ${CLIENT_NAME}"
print_info "Target: ${DEPLOYMENT_TARGET}"
print_info "MonitoringDB: ${MONITORINGDB_SERVER}:${MONITORINGDB_PORT}/${MONITORINGDB_DATABASE}"

# Validate configuration
validate_config

# Create datasource configuration
create_datasource_config

# Deploy based on target
case "$DEPLOYMENT_TARGET" in
    local)
        deploy_local
        ;;
    azure)
        deploy_azure
        ;;
    aws)
        deploy_aws
        ;;
    *)
        print_error "Unknown deployment target: $DEPLOYMENT_TARGET"
        print_info "Valid targets: local, azure, aws"
        exit 1
        ;;
esac

print_header "Deployment Complete!"

print_info "Next steps:"
print_info "1. Access Grafana at the URL shown above"
print_info "2. Login with admin / ${GRAFANA_ADMIN_PASSWORD}"
print_info "3. Verify MonitoringDB datasource connection"
print_info "4. Open Dashboard Browser (should be home page)"
print_info "5. Verify all 9 dashboards load correctly"
