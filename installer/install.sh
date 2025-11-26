#!/bin/bash
# ============================================================================
# SQL Server Monitor - Universal Installer
# ============================================================================
# One-command deployment for AWS, Azure, GCP, or On-Premises
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/installer/install.sh | bash
#   OR
#   ./install.sh [--interactive] [--config config.json]
#
# Supports:
#   - Interactive wizard mode (default)
#   - Non-interactive with config file
#   - AWS EC2, Azure VM, GCP Compute, On-Premises
#   - Docker Compose or Kubernetes deployment
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Version
INSTALLER_VERSION="1.0.0"
REPO_URL="https://github.com/dbbuilder/sql-monitor"
REPO_RAW="https://raw.githubusercontent.com/dbbuilder/sql-monitor/main"

# Default values
INSTALL_DIR="/opt/sql-monitor"
CONFIG_FILE=""
INTERACTIVE=true
SKIP_PREREQS=false
DEPLOYMENT_TYPE="docker"  # docker, kubernetes, manual

# ============================================================================
# Helper Functions
# ============================================================================

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                                                                  ║"
    echo "║   ${BOLD}SQL Server Monitor${NC}${CYAN} - Enterprise Monitoring Solution          ║"
    echo "║                                                                  ║"
    echo "║   Self-hosted, open-source SQL Server monitoring                 ║"
    echo "║   with Grafana dashboards and real-time alerting                 ║"
    echo "║                                                                  ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}Step $1: $2${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

prompt() {
    local prompt_text="$1"
    local default_value="$2"
    local var_name="$3"

    if [ -n "$default_value" ]; then
        read -p "$(echo -e "${BOLD}$prompt_text${NC} [$default_value]: ")" input
        eval "$var_name=\"${input:-$default_value}\""
    else
        read -p "$(echo -e "${BOLD}$prompt_text${NC}: ")" input
        eval "$var_name=\"$input\""
    fi
}

prompt_password() {
    local prompt_text="$1"
    local var_name="$2"

    read -s -p "$(echo -e "${BOLD}$prompt_text${NC}: ")" input
    echo ""
    eval "$var_name=\"$input\""
}

prompt_yes_no() {
    local prompt_text="$1"
    local default="$2"

    if [ "$default" = "y" ]; then
        read -p "$(echo -e "${BOLD}$prompt_text${NC} [Y/n]: ")" input
        input="${input:-y}"
    else
        read -p "$(echo -e "${BOLD}$prompt_text${NC} [y/N]: ")" input
        input="${input:-n}"
    fi

    [[ "$input" =~ ^[Yy] ]]
}

generate_password() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -dc 'a-zA-Z0-9' | head -c "$length"
}

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# ============================================================================
# Pre-flight Checks
# ============================================================================

check_prerequisites() {
    log_step "1" "Checking Prerequisites"

    local prereqs_ok=true

    # Check OS
    log_info "Detecting operating system..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            DISTRO=$ID
            log_success "Linux detected: $PRETTY_NAME"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        log_success "macOS detected"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        OS="windows"
        log_success "Windows (WSL/Git Bash) detected"
    else
        log_warn "Unknown OS: $OSTYPE - proceeding with caution"
        OS="unknown"
    fi

    # Check Docker
    log_info "Checking Docker..."
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        log_success "Docker $DOCKER_VERSION found"

        # Check if Docker is running
        if docker info &> /dev/null; then
            log_success "Docker daemon is running"
        else
            log_error "Docker daemon is not running"
            log_info "Please start Docker and try again"
            prereqs_ok=false
        fi
    else
        log_error "Docker not found"
        log_info "Please install Docker: https://docs.docker.com/get-docker/"
        prereqs_ok=false
    fi

    # Check Docker Compose
    log_info "Checking Docker Compose..."
    if command -v docker-compose &> /dev/null; then
        COMPOSE_VERSION=$(docker-compose --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        log_success "Docker Compose $COMPOSE_VERSION found"
    elif docker compose version &> /dev/null; then
        COMPOSE_VERSION=$(docker compose version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        log_success "Docker Compose (plugin) $COMPOSE_VERSION found"
        COMPOSE_CMD="docker compose"
    else
        log_error "Docker Compose not found"
        prereqs_ok=false
    fi

    # Check curl
    log_info "Checking curl..."
    if command -v curl &> /dev/null; then
        log_success "curl found"
    else
        log_error "curl not found - required for downloads"
        prereqs_ok=false
    fi

    # Check available disk space
    log_info "Checking available disk space..."
    if [ "$OS" = "linux" ] || [ "$OS" = "macos" ]; then
        AVAILABLE_GB=$(df -BG "${INSTALL_DIR%/*}" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
        if [ -z "$AVAILABLE_GB" ]; then
            AVAILABLE_GB=$(df -BG / | tail -1 | awk '{print $4}' | tr -d 'G')
        fi

        if [ "$AVAILABLE_GB" -ge 10 ]; then
            log_success "${AVAILABLE_GB}GB available (10GB required)"
        else
            log_warn "Only ${AVAILABLE_GB}GB available (10GB recommended)"
        fi
    fi

    # Check memory
    log_info "Checking available memory..."
    if [ "$OS" = "linux" ]; then
        TOTAL_MEM_GB=$(free -g | awk '/^Mem:/{print $2}')
        if [ "$TOTAL_MEM_GB" -ge 4 ]; then
            log_success "${TOTAL_MEM_GB}GB RAM available (4GB required)"
        else
            log_warn "Only ${TOTAL_MEM_GB}GB RAM available (4GB recommended)"
        fi
    fi

    # Check sqlcmd (optional, for direct database deployment)
    log_info "Checking sqlcmd (optional)..."
    if command -v sqlcmd &> /dev/null; then
        log_success "sqlcmd found - can deploy database directly"
        HAS_SQLCMD=true
    else
        log_info "sqlcmd not found - will use container for database deployment"
        HAS_SQLCMD=false
    fi

    if [ "$prereqs_ok" = false ]; then
        echo ""
        log_error "Prerequisites check failed. Please install missing components."
        exit 1
    fi

    log_success "All prerequisites satisfied!"
}

# ============================================================================
# Configuration Wizard
# ============================================================================

run_wizard() {
    log_step "2" "Configuration Wizard"

    echo ""
    echo "This wizard will help you configure SQL Server Monitor."
    echo "Press Enter to accept default values shown in [brackets]."
    echo ""

    # Installation directory
    prompt "Installation directory" "$INSTALL_DIR" "INSTALL_DIR"

    # Deployment type
    echo ""
    echo "Deployment options:"
    echo "  1) Docker Compose (recommended for single-server)"
    echo "  2) Kubernetes (for cluster deployments)"
    echo "  3) Manual (download files only)"
    echo ""
    prompt "Select deployment type" "1" "DEPLOY_CHOICE"

    case "$DEPLOY_CHOICE" in
        1) DEPLOYMENT_TYPE="docker" ;;
        2) DEPLOYMENT_TYPE="kubernetes" ;;
        3) DEPLOYMENT_TYPE="manual" ;;
        *) DEPLOYMENT_TYPE="docker" ;;
    esac

    echo ""
    echo -e "${BOLD}SQL Server Configuration${NC}"
    echo "Configure the SQL Server that will host MonitoringDB."
    echo ""

    prompt "SQL Server hostname or IP" "localhost" "SQL_SERVER"
    prompt "SQL Server port" "1433" "SQL_PORT"
    prompt "SQL Server username (needs sysadmin for setup)" "sa" "SQL_USER"
    prompt_password "SQL Server password" "SQL_PASSWORD"

    # Test SQL Server connection
    echo ""
    log_info "Testing SQL Server connection..."

    if test_sql_connection "$SQL_SERVER" "$SQL_PORT" "$SQL_USER" "$SQL_PASSWORD"; then
        log_success "SQL Server connection successful!"
    else
        log_warn "Could not connect to SQL Server"
        if prompt_yes_no "Continue anyway?" "n"; then
            log_info "Proceeding without connection verification"
        else
            log_error "Please check SQL Server settings and try again"
            exit 1
        fi
    fi

    echo ""
    echo -e "${BOLD}Application Credentials${NC}"
    echo "These credentials will be used by the monitoring system."
    echo ""

    # Generate secure defaults
    DEFAULT_API_PASSWORD=$(generate_password 24)
    DEFAULT_GRAFANA_PASSWORD=$(generate_password 16)
    DEFAULT_JWT_SECRET=$(generate_password 48)

    prompt "API database user" "monitor_api" "API_USER"
    prompt "API database password (auto-generated)" "$DEFAULT_API_PASSWORD" "API_PASSWORD"
    prompt "Grafana admin password" "$DEFAULT_GRAFANA_PASSWORD" "GRAFANA_PASSWORD"
    prompt "JWT secret key (48+ chars)" "$DEFAULT_JWT_SECRET" "JWT_SECRET"

    echo ""
    echo -e "${BOLD}Network Configuration${NC}"
    echo ""

    prompt "API port" "9000" "API_PORT"
    prompt "Grafana port" "9001" "GRAFANA_PORT"

    # SSL/TLS
    echo ""
    if prompt_yes_no "Enable SSL/TLS (HTTPS)?" "n"; then
        ENABLE_SSL=true
        prompt "SSL certificate path" "/etc/ssl/certs/server.crt" "SSL_CERT"
        prompt "SSL key path" "/etc/ssl/private/server.key" "SSL_KEY"
    else
        ENABLE_SSL=false
    fi

    # Monitored servers
    echo ""
    echo -e "${BOLD}Monitored SQL Servers${NC}"
    echo "You can add servers to monitor now, or later via the UI."
    echo ""

    MONITORED_SERVERS=()
    if prompt_yes_no "Add the setup SQL Server as a monitored server?" "y"; then
        MONITORED_SERVERS+=("$SQL_SERVER:$SQL_PORT")
    fi

    while prompt_yes_no "Add another SQL Server to monitor?" "n"; do
        prompt "Server hostname:port" "" "NEW_SERVER"
        if [ -n "$NEW_SERVER" ]; then
            MONITORED_SERVERS+=("$NEW_SERVER")
        fi
    done

    # Data retention
    echo ""
    echo -e "${BOLD}Data Retention${NC}"
    echo ""
    prompt "Data retention (days)" "90" "RETENTION_DAYS"

    # Show summary
    show_config_summary
}

test_sql_connection() {
    local server="$1"
    local port="$2"
    local user="$3"
    local password="$4"

    # Try with sqlcmd if available
    if [ "$HAS_SQLCMD" = true ]; then
        if sqlcmd -S "$server,$port" -U "$user" -P "$password" -Q "SELECT 1" -C -l 10 &> /dev/null; then
            return 0
        fi
    fi

    # Try with Docker SQL Server container
    if docker run --rm mcr.microsoft.com/mssql-tools \
        /opt/mssql-tools/bin/sqlcmd -S "$server,$port" -U "$user" -P "$password" \
        -Q "SELECT 1" -C -l 10 &> /dev/null 2>&1; then
        return 0
    fi

    # Try basic TCP connection
    if timeout 5 bash -c "echo > /dev/tcp/$server/$port" 2>/dev/null; then
        log_info "TCP connection successful, but SQL authentication not verified"
        return 0
    fi

    return 1
}

show_config_summary() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}Configuration Summary${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  Installation Directory:  $INSTALL_DIR"
    echo "  Deployment Type:         $DEPLOYMENT_TYPE"
    echo ""
    echo "  SQL Server:              $SQL_SERVER:$SQL_PORT"
    echo "  SQL Username:            $SQL_USER"
    echo "  API Database User:       $API_USER"
    echo ""
    echo "  API Port:                $API_PORT"
    echo "  Grafana Port:            $GRAFANA_PORT"
    echo "  SSL Enabled:             $ENABLE_SSL"
    echo ""
    echo "  Data Retention:          $RETENTION_DAYS days"
    echo "  Monitored Servers:       ${#MONITORED_SERVERS[@]}"
    echo ""

    if ! prompt_yes_no "Proceed with installation?" "y"; then
        log_info "Installation cancelled"
        exit 0
    fi
}

# ============================================================================
# Installation Steps
# ============================================================================

download_files() {
    log_step "3" "Downloading SQL Server Monitor"

    # Create installation directory
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    log_info "Downloading from $REPO_URL..."

    # Clone or download
    if command -v git &> /dev/null; then
        if [ -d ".git" ]; then
            log_info "Updating existing installation..."
            git pull origin main
        else
            git clone --depth 1 "$REPO_URL.git" .
        fi
    else
        # Download as zip
        curl -sSL "$REPO_URL/archive/refs/heads/main.zip" -o sql-monitor.zip
        unzip -q sql-monitor.zip
        mv sql-monitor-main/* .
        rm -rf sql-monitor-main sql-monitor.zip
    fi

    log_success "Files downloaded to $INSTALL_DIR"
}

create_env_file() {
    log_step "4" "Creating Configuration Files"

    log_info "Generating .env file..."

    cat > "$INSTALL_DIR/.env" << EOF
# ============================================================================
# SQL Server Monitor Configuration
# Generated: $(date -Iseconds)
# ============================================================================

# Database Connection (MonitoringDB)
DB_CONNECTION_STRING=Server=${SQL_SERVER},${SQL_PORT};Database=MonitoringDB;User Id=${API_USER};Password=${API_PASSWORD};Encrypt=True;TrustServerCertificate=True;Connection Timeout=30

# SQL Server Admin (for initial setup only)
SQL_ADMIN_SERVER=${SQL_SERVER},${SQL_PORT}
SQL_ADMIN_USER=${SQL_USER}
SQL_ADMIN_PASSWORD=${SQL_PASSWORD}

# API Configuration
API_PORT=${API_PORT}
ASPNETCORE_ENVIRONMENT=Production
ASPNETCORE_URLS=http://+:${API_PORT}

# JWT Authentication
JWT_SECRET_KEY=${JWT_SECRET}
JWT_ISSUER=SqlMonitor.Api
JWT_AUDIENCE=SqlMonitor.Client
JWT_EXPIRATION_HOURS=8

# Grafana Configuration
GRAFANA_PORT=${GRAFANA_PORT}
GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
GF_SERVER_HTTP_PORT=${GRAFANA_PORT}
GF_DATABASE_TYPE=mssql
GF_DATABASE_HOST=${SQL_SERVER}
GF_DATABASE_NAME=MonitoringDB
GF_DATABASE_USER=${API_USER}
GF_DATABASE_PASSWORD=${API_PASSWORD}

# Monitoring Settings
MONITORINGDB_SERVER=${SQL_SERVER}
MONITORINGDB_USER=${API_USER}
MONITORINGDB_PASSWORD=${API_PASSWORD}
DATA_RETENTION_DAYS=${RETENTION_DAYS}
COLLECTION_INTERVAL_MINUTES=5

# SSL Configuration
ENABLE_SSL=${ENABLE_SSL}
SSL_CERT_PATH=${SSL_CERT:-}
SSL_KEY_PATH=${SSL_KEY:-}

# Advanced Settings
ENABLE_DEBUG_LOGGING=false
CONNECTION_TIMEOUT_SECONDS=30
EOF

    chmod 600 "$INSTALL_DIR/.env"
    log_success "Configuration file created: $INSTALL_DIR/.env"
}

deploy_database() {
    log_step "5" "Deploying Database Schema"

    log_info "This will create the MonitoringDB database and all required objects..."

    cd "$INSTALL_DIR"

    # Create database deployment script
    cat > "/tmp/deploy-monitoring-db.sql" << 'EOSQL'
-- Pre-flight check
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'MonitoringDB')
BEGIN
    PRINT 'MonitoringDB already exists - will update schema';
END
ELSE
BEGIN
    PRINT 'Creating MonitoringDB...';
    CREATE DATABASE MonitoringDB;
END
GO

USE MonitoringDB;
GO

PRINT 'Database ready for schema deployment';
GO
EOSQL

    # Run database deployment
    if [ "$HAS_SQLCMD" = true ]; then
        log_info "Deploying with sqlcmd..."

        # Create database
        sqlcmd -S "$SQL_SERVER,$SQL_PORT" -U "$SQL_USER" -P "$SQL_PASSWORD" \
            -i "/tmp/deploy-monitoring-db.sql" -C

        # Deploy schema
        sqlcmd -S "$SQL_SERVER,$SQL_PORT" -U "$SQL_USER" -P "$SQL_PASSWORD" \
            -d MonitoringDB -i "$INSTALL_DIR/database/deploy-all.sql" -C

    else
        log_info "Deploying with Docker SQL tools container..."

        docker run --rm \
            -v "$INSTALL_DIR/database:/database:ro" \
            -v "/tmp/deploy-monitoring-db.sql:/tmp/deploy.sql:ro" \
            mcr.microsoft.com/mssql-tools \
            /bin/bash -c "
                /opt/mssql-tools/bin/sqlcmd -S $SQL_SERVER,$SQL_PORT -U $SQL_USER -P '$SQL_PASSWORD' \
                    -i /tmp/deploy.sql -C && \
                /opt/mssql-tools/bin/sqlcmd -S $SQL_SERVER,$SQL_PORT -U $SQL_USER -P '$SQL_PASSWORD' \
                    -d MonitoringDB -i /database/deploy-all.sql -C
            "
    fi

    # Create application database user
    log_info "Creating application database user..."

    cat > "/tmp/create-app-user.sql" << EOSQL
USE MonitoringDB;
GO

-- Create API user if not exists
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = '${API_USER}')
BEGIN
    CREATE LOGIN [${API_USER}] WITH PASSWORD = '${API_PASSWORD}';
    PRINT 'Created login: ${API_USER}';
END

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '${API_USER}')
BEGIN
    CREATE USER [${API_USER}] FOR LOGIN [${API_USER}];
    PRINT 'Created user: ${API_USER}';
END

-- Grant permissions
GRANT EXECUTE TO [${API_USER}];
GRANT SELECT ON SCHEMA::dbo TO [${API_USER}];
GRANT INSERT ON SCHEMA::dbo TO [${API_USER}];
GRANT UPDATE ON SCHEMA::dbo TO [${API_USER}];
GRANT DELETE ON SCHEMA::dbo TO [${API_USER}];
PRINT 'Permissions granted to ${API_USER}';
GO
EOSQL

    if [ "$HAS_SQLCMD" = true ]; then
        sqlcmd -S "$SQL_SERVER,$SQL_PORT" -U "$SQL_USER" -P "$SQL_PASSWORD" \
            -i "/tmp/create-app-user.sql" -C
    else
        docker run --rm \
            -v "/tmp/create-app-user.sql:/tmp/create-user.sql:ro" \
            mcr.microsoft.com/mssql-tools \
            /opt/mssql-tools/bin/sqlcmd -S "$SQL_SERVER,$SQL_PORT" -U "$SQL_USER" -P "$SQL_PASSWORD" \
                -i /tmp/create-user.sql -C
    fi

    log_success "Database schema deployed successfully!"
}

deploy_containers() {
    log_step "6" "Deploying Containers"

    cd "$INSTALL_DIR"

    log_info "Building and starting containers..."

    # Use docker compose (v2) or docker-compose (v1)
    COMPOSE_CMD="${COMPOSE_CMD:-docker-compose}"

    # Build custom images
    log_info "Building API image..."
    $COMPOSE_CMD build api

    # Start services
    log_info "Starting services..."
    $COMPOSE_CMD up -d

    # Wait for services to be healthy
    log_info "Waiting for services to start..."
    local max_wait=60
    local waited=0

    while [ $waited -lt $max_wait ]; do
        if curl -s "http://localhost:$API_PORT/health" > /dev/null 2>&1; then
            break
        fi
        sleep 2
        waited=$((waited + 2))
        echo -n "."
    done
    echo ""

    if [ $waited -ge $max_wait ]; then
        log_warn "Services may still be starting..."
    else
        log_success "Services are running!"
    fi

    # Show status
    $COMPOSE_CMD ps
}

register_servers() {
    log_step "7" "Registering Monitored Servers"

    if [ ${#MONITORED_SERVERS[@]} -eq 0 ]; then
        log_info "No servers to register. You can add servers later via the API or UI."
        return
    fi

    for server in "${MONITORED_SERVERS[@]}"; do
        log_info "Registering server: $server"

        # Parse server:port
        local srv_host="${server%:*}"
        local srv_port="${server##*:}"
        [ "$srv_port" = "$srv_host" ] && srv_port="1433"

        # Register via stored procedure
        local register_sql="EXEC dbo.usp_AddServer @ServerName = '$srv_host,$srv_port', @Description = 'Auto-registered during setup', @IsActive = 1;"

        if [ "$HAS_SQLCMD" = true ]; then
            sqlcmd -S "$SQL_SERVER,$SQL_PORT" -U "$SQL_USER" -P "$SQL_PASSWORD" \
                -d MonitoringDB -Q "$register_sql" -C
        else
            docker run --rm mcr.microsoft.com/mssql-tools \
                /opt/mssql-tools/bin/sqlcmd -S "$SQL_SERVER,$SQL_PORT" -U "$SQL_USER" -P "$SQL_PASSWORD" \
                -d MonitoringDB -Q "$register_sql" -C
        fi

        log_success "Registered: $server"
    done
}

run_verification() {
    log_step "8" "Verifying Installation"

    local all_ok=true

    # Check API health
    log_info "Checking API health..."
    if curl -s "http://localhost:$API_PORT/health" | grep -q "Healthy"; then
        log_success "API is healthy"
    else
        log_error "API health check failed"
        all_ok=false
    fi

    # Check Grafana
    log_info "Checking Grafana..."
    if curl -s "http://localhost:$GRAFANA_PORT/api/health" | grep -q "ok"; then
        log_success "Grafana is healthy"
    else
        log_warn "Grafana may still be starting..."
    fi

    # Check database connectivity
    log_info "Checking database connectivity..."
    local db_check="SELECT COUNT(*) FROM dbo.Servers;"

    if [ "$HAS_SQLCMD" = true ]; then
        if sqlcmd -S "$SQL_SERVER,$SQL_PORT" -U "$API_USER" -P "$API_PASSWORD" \
            -d MonitoringDB -Q "$db_check" -C -h -1 &> /dev/null; then
            log_success "Database connection verified"
        else
            log_error "Database connection failed"
            all_ok=false
        fi
    fi

    # Check dashboards
    log_info "Checking Grafana dashboards..."
    local dashboard_count=$(curl -s "http://admin:$GRAFANA_PASSWORD@localhost:$GRAFANA_PORT/api/search" 2>/dev/null | grep -o '"uid"' | wc -l)
    if [ "$dashboard_count" -gt 0 ]; then
        log_success "$dashboard_count dashboards loaded"
    else
        log_warn "No dashboards found - they may still be loading"
    fi

    echo ""
    if [ "$all_ok" = true ]; then
        log_success "Installation verified successfully!"
    else
        log_warn "Some checks failed - please review the logs above"
    fi
}

show_completion_message() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                                  ║${NC}"
    echo -e "${GREEN}║   ${BOLD}Installation Complete!${NC}${GREEN}                                      ║${NC}"
    echo -e "${GREEN}║                                                                  ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}Access your SQL Server Monitor:${NC}"
    echo ""
    echo "  Grafana Dashboard:  http://localhost:$GRAFANA_PORT"
    echo "  API Endpoint:       http://localhost:$API_PORT"
    echo "  API Documentation:  http://localhost:$API_PORT/swagger"
    echo ""
    echo -e "${BOLD}Credentials:${NC}"
    echo ""
    echo "  Grafana Admin:      admin / $GRAFANA_PASSWORD"
    echo ""
    echo -e "${BOLD}Configuration:${NC}"
    echo ""
    echo "  Installation Dir:   $INSTALL_DIR"
    echo "  Config File:        $INSTALL_DIR/.env"
    echo ""
    echo -e "${BOLD}Next Steps:${NC}"
    echo ""
    echo "  1. Open Grafana at http://localhost:$GRAFANA_PORT"
    echo "  2. Navigate to 'SQL Server Monitoring' dashboard"
    echo "  3. Add more servers via API: POST /api/servers"
    echo "  4. Configure alerts in Grafana"
    echo ""
    echo -e "${BOLD}Useful Commands:${NC}"
    echo ""
    echo "  View logs:          cd $INSTALL_DIR && docker-compose logs -f"
    echo "  Restart services:   cd $INSTALL_DIR && docker-compose restart"
    echo "  Stop services:      cd $INSTALL_DIR && docker-compose down"
    echo "  Update:             cd $INSTALL_DIR && git pull && docker-compose up -d --build"
    echo ""
    echo -e "${CYAN}Documentation: https://github.com/dbbuilder/sql-monitor/docs${NC}"
    echo ""
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    print_banner

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --non-interactive|-n)
                INTERACTIVE=false
                shift
                ;;
            --config|-c)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --install-dir|-d)
                INSTALL_DIR="$2"
                shift 2
                ;;
            --skip-prereqs)
                SKIP_PREREQS=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  -n, --non-interactive    Run without prompts (requires --config)"
                echo "  -c, --config FILE        Use configuration file"
                echo "  -d, --install-dir DIR    Installation directory (default: /opt/sql-monitor)"
                echo "  --skip-prereqs           Skip prerequisite checks"
                echo "  -h, --help               Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Run installation steps
    if [ "$SKIP_PREREQS" = false ]; then
        check_prerequisites
    fi

    if [ "$INTERACTIVE" = true ]; then
        run_wizard
    else
        if [ -z "$CONFIG_FILE" ]; then
            log_error "Non-interactive mode requires --config FILE"
            exit 1
        fi
        # Load config file
        source "$CONFIG_FILE"
    fi

    download_files
    create_env_file
    deploy_database

    if [ "$DEPLOYMENT_TYPE" = "docker" ]; then
        deploy_containers
    fi

    register_servers
    run_verification
    show_completion_message
}

# Run main function
main "$@"
