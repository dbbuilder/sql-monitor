#!/bin/bash
# =============================================
# SQL Monitor - Idempotent Deployment Script (Bash)
# Purpose: Provisions SQL Monitor from scratch or resumes from any checkpoint
# Safe to run multiple times - only applies missing components
# =============================================

set -e  # Exit on error
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKPOINT_FILE="$SCRIPT_DIR/.deploy-checkpoint.json"

# Default configuration
SQL_SERVER="${SQL_SERVER:-localhost,1433}"
SQL_USER="${SQL_USER:-sa}"
SQL_PASSWORD="${SQL_PASSWORD}"
DATABASE_NAME="${DATABASE_NAME:-MonitoringDB}"
GRAFANA_PORT="${GRAFANA_PORT:-9002}"
API_PORT="${API_PORT:-9000}"
ENVIRONMENT="${ENVIRONMENT:-Development}"
SKIP_DOCKER="${SKIP_DOCKER:-false}"
BATCH_SIZE="${BATCH_SIZE:-10}"  # Process databases in batches of 10

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

print_warning() {
    echo "  ⚠  $1"
}

print_info() {
    echo "  ℹ  $1"
}

print_error() {
    echo "  ✗ $1" >&2
}

get_checkpoint() {
    if [ -f "$CHECKPOINT_FILE" ]; then
        cat "$CHECKPOINT_FILE"
    else
        echo '{"steps":[],"lastUpdated":null,"sqlServer":null,"databaseName":null,"environment":null,"processedDatabases":[]}'
    fi
}

save_checkpoint() {
    local step_name="$1"
    local checkpoint=$(get_checkpoint)

    # Add step if not already present
    checkpoint=$(echo "$checkpoint" | jq --arg step "$step_name" \
        'if (.steps | contains([$step])) then . else .steps += [$step] end')

    # Update metadata
    checkpoint=$(echo "$checkpoint" | jq \
        --arg timestamp "$(date '+%Y-%m-%d %H:%M:%S')" \
        --arg server "$SQL_SERVER" \
        --arg db "$DATABASE_NAME" \
        --arg env "$ENVIRONMENT" \
        '.lastUpdated = $timestamp | .sqlServer = $server | .databaseName = $db | .environment = $env')

    echo "$checkpoint" > "$CHECKPOINT_FILE"
    print_success "Checkpoint saved: $step_name"
}

save_processed_database() {
    local db_name="$1"
    local checkpoint=$(get_checkpoint)

    checkpoint=$(echo "$checkpoint" | jq --arg db "$db_name" \
        'if (.processedDatabases | contains([$db])) then . else .processedDatabases += [$db] end')

    echo "$checkpoint" > "$CHECKPOINT_FILE"
}

test_step_completed() {
    local step_name="$1"
    local checkpoint=$(get_checkpoint)
    echo "$checkpoint" | jq -e --arg step "$step_name" '.steps | contains([$step])' > /dev/null 2>&1
}

test_database_processed() {
    local db_name="$1"
    local checkpoint=$(get_checkpoint)
    echo "$checkpoint" | jq -e --arg db "$db_name" '.processedDatabases | contains([$db])' > /dev/null 2>&1
}

show_status() {
    print_header "Deployment Status"

    if [ ! -f "$CHECKPOINT_FILE" ]; then
        print_warning "No deployment checkpoint found. Run ./deploy.sh to start."
        return
    fi

    local checkpoint=$(get_checkpoint)
    print_info "Last Updated: $(echo "$checkpoint" | jq -r '.lastUpdated')"
    print_info "SQL Server: $(echo "$checkpoint" | jq -r '.sqlServer')"
    print_info "Database: $(echo "$checkpoint" | jq -r '.databaseName')"
    print_info "Environment: $(echo "$checkpoint" | jq -r '.environment')"
    echo ""
    echo "Completed Steps:"

    local all_steps=("Prerequisites" "DatabaseCreated" "TablesCreated" "ProceduresCreated" "ServerRegistered" "MetadataInitialized" "DockerConfigured" "GrafanaStarted")

    for step in "${all_steps[@]}"; do
        if echo "$checkpoint" | jq -e --arg step "$step" '.steps | contains([$step])' > /dev/null 2>&1; then
            echo "  [X] $step"
        else
            echo "  [ ] $step"
        fi
    done

    echo ""
    local db_count=$(echo "$checkpoint" | jq '.processedDatabases | length')
    print_info "Databases processed for metadata: $db_count"
}

test_prerequisite() {
    local command=$1
    local name=$2
    local install_instructions=$3

    if command -v "$command" &> /dev/null; then
        print_success "$name found"
        return 0
    else
        print_error "$name not found"
        print_info "Install: $install_instructions"
        return 1
    fi
}

sql_query() {
    local query="$1"
    local database="${2:-master}"

    sqlcmd -S "$SQL_SERVER" -U "$SQL_USER" -P "$SQL_PASSWORD" -d "$database" -C -Q "$query" -h -1 2>&1 | grep -v "^$" | tail -n +2
}

test_database_exists() {
    local db_name="$1"
    local result=$(sql_query "SELECT COUNT(*) FROM sys.databases WHERE name = '$db_name'" "master" 2>/dev/null || echo "0")
    [ "$result" -gt 0 ]
}

test_table_exists() {
    local table_name="$1"
    local result=$(sql_query "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = '$table_name'" "$DATABASE_NAME" 2>/dev/null || echo "0")
    [ "$result" -gt 0 ]
}

# =============================================
# Parse Arguments
# =============================================

SHOW_STATUS=false
RESUME=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --sql-server)
            SQL_SERVER="$2"
            shift 2
            ;;
        --sql-user)
            SQL_USER="$2"
            shift 2
            ;;
        --sql-password)
            SQL_PASSWORD="$2"
            shift 2
            ;;
        --database)
            DATABASE_NAME="$2"
            shift 2
            ;;
        --grafana-port)
            GRAFANA_PORT="$2"
            shift 2
            ;;
        --api-port)
            API_PORT="$2"
            shift 2
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --skip-docker)
            SKIP_DOCKER=true
            shift
            ;;
        --batch-size)
            BATCH_SIZE="$2"
            shift 2
            ;;
        --status)
            SHOW_STATUS=true
            shift
            ;;
        --resume)
            RESUME=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --sql-server SERVER       SQL Server instance (default: localhost,1433)"
            echo "  --sql-user USER           SQL Server username"
            echo "  --sql-password PASS       SQL Server password"
            echo "  --database NAME           Database name (default: MonitoringDB)"
            echo "  --grafana-port PORT       Grafana port (default: 9002)"
            echo "  --api-port PORT           API port (default: 9000)"
            echo "  --environment ENV         Environment (Development|Staging|Production)"
            echo "  --skip-docker             Skip Docker container setup"
            echo "  --batch-size N            Process databases in batches of N (default: 10)"
            echo "  --status                  Show deployment status"
            echo "  --resume                  Resume from last checkpoint"
            echo "  --help                    Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --sql-server localhost,14333 --sql-user sa --sql-password 'Pass@123'"
            echo "  $0 --status"
            echo "  $0 --resume --batch-size 5"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

# =============================================
# Main Deployment Logic
# =============================================

if [ "$SHOW_STATUS" = true ]; then
    show_status
    exit 0
fi

print_header "SQL Monitor - Idempotent Deployment"

# Load configuration from checkpoint if resuming
if [ "$RESUME" = true ]; then
    if [ -f "$CHECKPOINT_FILE" ]; then
        checkpoint=$(get_checkpoint)
        SQL_SERVER=$(echo "$checkpoint" | jq -r '.sqlServer')
        DATABASE_NAME=$(echo "$checkpoint" | jq -r '.databaseName')
        ENVIRONMENT=$(echo "$checkpoint" | jq -r '.environment')
        print_info "Resuming from checkpoint..."
    else
        print_warning "No checkpoint found. Starting fresh deployment."
        RESUME=false
    fi
fi

# Prompt for password if not provided
if [ -z "$SQL_PASSWORD" ]; then
    read -sp "SQL Server Password: " SQL_PASSWORD
    echo ""
fi

# =============================================
# Step 1: Check Prerequisites
# =============================================

if ! test_step_completed "Prerequisites"; then
    print_header "Step 1: Checking Prerequisites"

    all_found=true
    test_prerequisite "sqlcmd" "SQL Server Command Line Tools" "https://learn.microsoft.com/en-us/sql/tools/sqlcmd" || all_found=false
    test_prerequisite "jq" "jq (JSON processor)" "sudo apt-get install jq (Ubuntu) or brew install jq (macOS)" || all_found=false

    if [ "$SKIP_DOCKER" != true ]; then
        test_prerequisite "docker" "Docker" "https://docs.docker.com/get-docker/" || all_found=false
    fi

    if [ "$all_found" != true ]; then
        print_error "Prerequisites not met. Install missing tools and try again."
        exit 1
    fi

    save_checkpoint "Prerequisites"
else
    print_warning "Prerequisites already checked"
fi

# =============================================
# Step 2: Create Database
# =============================================

if ! test_step_completed "DatabaseCreated"; then
    print_header "Step 2: Creating Database"

    if test_database_exists "$DATABASE_NAME"; then
        print_warning "Database '$DATABASE_NAME' already exists"
    else
        print_step "Creating database '$DATABASE_NAME'..."
        sqlcmd -S "$SQL_SERVER" -U "$SQL_USER" -P "$SQL_PASSWORD" -d master -C -Q "
            CREATE DATABASE [$DATABASE_NAME];
            ALTER DATABASE [$DATABASE_NAME] SET RECOVERY SIMPLE;
            ALTER DATABASE [$DATABASE_NAME] SET PAGE_VERIFY CHECKSUM;
        "
        print_success "Database created"
    fi

    save_checkpoint "DatabaseCreated"
else
    print_warning "Database creation already completed"
fi

# =============================================
# Step 3: Deploy Schema (Tables)
# =============================================

if ! test_step_completed "TablesCreated"; then
    print_header "Step 3: Creating Tables"

    for script in "$SCRIPT_DIR"/database/*-create-*tables*.sql; do
        if [ -f "$script" ]; then
            print_step "Executing: $(basename "$script")"
            sqlcmd -S "$SQL_SERVER" -U "$SQL_USER" -P "$SQL_PASSWORD" -d "$DATABASE_NAME" -C -i "$script" -b
        fi
    done

    print_success "Tables created"
    save_checkpoint "TablesCreated"
else
    print_warning "Tables already created"
fi

# =============================================
# Step 4: Deploy Procedures/Functions
# =============================================

if ! test_step_completed "ProceduresCreated"; then
    print_header "Step 4: Creating Procedures and Functions"

    for script in "$SCRIPT_DIR"/database/*-create-*procedure*.sql; do
        if [ -f "$script" ]; then
            print_step "Executing: $(basename "$script")"
            sqlcmd -S "$SQL_SERVER" -U "$SQL_USER" -P "$SQL_PASSWORD" -d "$DATABASE_NAME" -C -i "$script" || print_warning "May already exist"
        fi
    done

    print_success "Procedures created"
    save_checkpoint "ProceduresCreated"
else
    print_warning "Procedures already created"
fi

# =============================================
# Step 5: Register Server
# =============================================

if ! test_step_completed "ServerRegistered"; then
    print_header "Step 5: Registering Server"

    server_count=$(sql_query "SELECT COUNT(*) FROM dbo.Servers" "$DATABASE_NAME" 2>/dev/null || echo "0")

    if [ "$server_count" -eq 0 ]; then
        print_step "Registering local server..."
        sql_query "INSERT INTO dbo.Servers (ServerName, Environment, IsActive) VALUES (@@SERVERNAME, '$ENVIRONMENT', 1)" "$DATABASE_NAME"
        print_success "Server registered"
    else
        print_warning "Server already registered"
    fi

    save_checkpoint "ServerRegistered"
else
    print_warning "Server registration already completed"
fi

# =============================================
# Step 6: Initialize Metadata Collection (Batched)
# =============================================

if ! test_step_completed "MetadataInitialized"; then
    print_header "Step 6: Initializing Metadata Collection (Batch Size: $BATCH_SIZE)"

    # Get list of user databases
    databases=$(sql_query "
        SELECT name
        FROM sys.databases
        WHERE database_id > 4
          AND name NOT IN ('ReportServer', 'ReportServerTempDB')
          AND state = 0
        ORDER BY name
    " "master" | tr -d ' ')

    total_dbs=$(echo "$databases" | wc -l)
    processed=0
    skipped=0

    print_info "Found $total_dbs user databases"

    # Process in batches
    batch=()
    for db in $databases; do
        # Skip if already processed
        if test_database_processed "$db"; then
            print_warning "Skipped: $db (already processed)"
            ((skipped++))
            continue
        fi

        batch+=("$db")

        # Process batch when it reaches BATCH_SIZE
        if [ ${#batch[@]} -eq $BATCH_SIZE ]; then
            print_step "Processing batch of ${#batch[@]} databases..."

            for batch_db in "${batch[@]}"; do
                print_step "  Processing: $batch_db"

                # Call metadata collection for single database
                sqlcmd -S "$SQL_SERVER" -U "$SQL_USER" -P "$SQL_PASSWORD" -d "$DATABASE_NAME" -C -Q "
                    SET NOCOUNT ON;
                    EXEC dbo.usp_RefreshMetadataCache @ServerID = 1, @DatabaseName = '$batch_db', @ForceRefresh = 0;
                " -t 300 || print_warning "    Timeout or error processing $batch_db"

                save_processed_database "$batch_db"
                ((processed++))
                print_success "    Completed: $batch_db ($processed/$total_dbs)"
            done

            batch=()
        fi
    done

    # Process remaining databases
    if [ ${#batch[@]} -gt 0 ]; then
        print_step "Processing final batch of ${#batch[@]} databases..."

        for batch_db in "${batch[@]}"; do
            print_step "  Processing: $batch_db"

            sqlcmd -S "$SQL_SERVER" -U "$SQL_USER" -P "$SQL_PASSWORD" -d "$DATABASE_NAME" -C -Q "
                SET NOCOUNT ON;
                EXEC dbo.usp_RefreshMetadataCache @ServerID = 1, @DatabaseName = '$batch_db', @ForceRefresh = 0;
            " -t 300 || print_warning "    Timeout or error processing $batch_db"

            save_processed_database "$batch_db"
            ((processed++))
            print_success "    Completed: $batch_db ($processed/$total_dbs)"
        done
    fi

    print_success "Metadata collection initialized: $processed processed, $skipped skipped"
    save_checkpoint "MetadataInitialized"
else
    print_warning "Metadata initialization already completed"
fi

# =============================================
# Step 7: Configure Docker
# =============================================

if [ "$SKIP_DOCKER" != true ] && ! test_step_completed "DockerConfigured"; then
    print_header "Step 7: Configuring Docker"

    # Create .env file
    jwt_secret=$(openssl rand -base64 32 | tr -d '\n')
    cat > "$SCRIPT_DIR/.env" <<EOF
DB_CONNECTION_STRING=Server=$SQL_SERVER;Database=$DATABASE_NAME;User Id=$SQL_USER;Password=$SQL_PASSWORD;Encrypt=True;TrustServerCertificate=True;Connection Timeout=30
JWT_SECRET_KEY=$jwt_secret
GRAFANA_PASSWORD=Admin123!
ASPNETCORE_ENVIRONMENT=$ENVIRONMENT
GF_SERVER_HTTP_PORT=$GRAFANA_PORT
EOF
    print_success ".env file created"

    save_checkpoint "DockerConfigured"
elif [ "$SKIP_DOCKER" = true ]; then
    print_warning "Docker setup skipped"
else
    print_warning "Docker already configured"
fi

# =============================================
# Step 8: Start Docker Containers
# =============================================

if [ "$SKIP_DOCKER" != true ] && ! test_step_completed "GrafanaStarted"; then
    print_header "Step 8: Starting Docker Containers"

    print_step "Starting containers..."
    docker compose up -d

    print_success "Containers started"
    print_info "Grafana: http://localhost:$GRAFANA_PORT (admin/Admin123!)"
    print_info "API: http://localhost:$API_PORT"

    save_checkpoint "GrafanaStarted"
elif [ "$SKIP_DOCKER" = true ]; then
    print_warning "Docker startup skipped"
else
    print_warning "Containers already started"
fi

# =============================================
# Deployment Complete
# =============================================

print_header "Deployment Complete!"

echo "Next Steps:"
echo "  1. Open Grafana: http://localhost:$GRAFANA_PORT"
echo "  2. Login: admin / Admin123!"
echo "  3. Explore dashboards (landing page should be home)"
echo ""
echo "Run './deploy.sh --status' to check deployment status"
echo ""
