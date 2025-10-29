#!/bin/bash
# =============================================
# SQL Monitor - Deploy MonitoringDB and Configure Monitored Servers
# Purpose: Deploys MonitoringDB database and configures data collection
# Part 2 of two-part deployment (Part 1: deploy-grafana.sh)
# =============================================

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================
# Configuration
# =============================================

# Central MonitoringDB server (where monitoring database will be created)
CENTRAL_SERVER="${CENTRAL_SERVER}"
CENTRAL_PORT="${CENTRAL_PORT:-1433}"
CENTRAL_USER="${CENTRAL_USER}"
CENTRAL_PASSWORD="${CENTRAL_PASSWORD}"
CENTRAL_DATABASE="${CENTRAL_DATABASE:-MonitoringDB}"

# Monitored servers (comma-separated list of servers to monitor)
# Example: "sql-prod-01,sql-prod-02,sql-prod-03"
MONITORED_SERVERS="${MONITORED_SERVERS}"

# SQL authentication for monitored servers
MONITORED_USER="${MONITORED_USER}"
MONITORED_PASSWORD="${MONITORED_PASSWORD}"
MONITORED_PORT="${MONITORED_PORT:-1433}"

# Collection frequency (minutes)
COLLECTION_INTERVAL="${COLLECTION_INTERVAL:-5}"

# Client identification
CLIENT_NAME="${CLIENT_NAME:-Client1}"

# Should central server monitor itself?
MONITOR_CENTRAL_SERVER="${MONITOR_CENTRAL_SERVER:-true}"

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

    if [ -z "$CENTRAL_SERVER" ]; then
        print_error "CENTRAL_SERVER is required"
        valid=false
    fi

    if [ -z "$CENTRAL_USER" ]; then
        print_error "CENTRAL_USER is required"
        valid=false
    fi

    if [ -z "$CENTRAL_PASSWORD" ]; then
        print_error "CENTRAL_PASSWORD is required"
        valid=false
    fi

    if [ -z "$MONITORED_SERVERS" ]; then
        print_error "MONITORED_SERVERS is required (comma-separated list)"
        valid=false
    fi

    if [ -z "$MONITORED_USER" ]; then
        print_error "MONITORED_USER is required"
        valid=false
    fi

    if [ -z "$MONITORED_PASSWORD" ]; then
        print_error "MONITORED_PASSWORD is required"
        valid=false
    fi

    # Check if sqlcmd is available
    if ! command -v sqlcmd &> /dev/null; then
        print_error "sqlcmd not found. Install SQL Server command-line tools."
        print_info "Linux: https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-setup-tools"
        print_info "Windows: Install SQL Server Management Studio or command-line tools"
        valid=false
    fi

    if [ "$valid" = false ]; then
        exit 1
    fi

    print_success "Configuration valid"
}

# =============================================
# Database Deployment
# =============================================

deploy_monitoringdb() {
    print_header "Deploying MonitoringDB Schema"

    print_step "Connecting to central server: ${CENTRAL_SERVER},${CENTRAL_PORT}"

    # Find all numbered SQL scripts in database/ directory
    local scripts=($(ls -1 "$SCRIPT_DIR/database/"*.sql 2>/dev/null | sort -V))

    if [ ${#scripts[@]} -eq 0 ]; then
        print_error "No SQL scripts found in database/ directory"
        exit 1
    fi

    print_info "Found ${#scripts[@]} database scripts to execute"

    # Execute each script in order
    for script in "${scripts[@]}"; do
        local script_name=$(basename "$script")
        print_step "Executing: $script_name"

        # Execute script with sqlcmd
        sqlcmd -S "${CENTRAL_SERVER},${CENTRAL_PORT}" \
               -U "$CENTRAL_USER" \
               -P "$CENTRAL_PASSWORD" \
               -d "$CENTRAL_DATABASE" \
               -C \
               -i "$script" \
               -b  # Abort on error

        if [ $? -eq 0 ]; then
            print_success "$script_name executed successfully"
        else
            print_error "$script_name failed"
            exit 1
        fi
    done

    print_success "MonitoringDB schema deployed"
}

# =============================================
# Server Registration
# =============================================

register_monitored_servers() {
    print_header "Registering Monitored Servers"

    # Split comma-separated server list into array
    IFS=',' read -ra SERVER_ARRAY <<< "$MONITORED_SERVERS"

    # Add central server to monitored list if requested
    if [ "$MONITOR_CENTRAL_SERVER" = "true" ]; then
        SERVER_ARRAY+=("$CENTRAL_SERVER")
        print_info "Central server will monitor itself"
    fi

    # Register each server in MonitoringDB
    for server in "${SERVER_ARRAY[@]}"; do
        server=$(echo "$server" | xargs)  # Trim whitespace
        print_step "Registering server: $server"

        # Create SQL script to register server
        cat > /tmp/register_server.sql <<EOF
-- Register server in Servers table
IF NOT EXISTS (SELECT 1 FROM dbo.Servers WHERE ServerName = '$server')
BEGIN
    INSERT INTO dbo.Servers (
        ServerName,
        ServerDescription,
        Environment,
        IsActive,
        MonitoringEnabled,
        CollectionIntervalMinutes,
        CreatedDate
    )
    VALUES (
        '$server',
        'Auto-registered by deploy-monitoring.sh',
        'Production',
        1,
        1,
        $COLLECTION_INTERVAL,
        GETUTCDATE()
    );
    PRINT 'Server registered: $server';
END
ELSE
BEGIN
    UPDATE dbo.Servers
    SET IsActive = 1,
        MonitoringEnabled = 1,
        CollectionIntervalMinutes = $COLLECTION_INTERVAL,
        ModifiedDate = GETUTCDATE()
    WHERE ServerName = '$server';
    PRINT 'Server updated: $server';
END
GO
EOF

        # Execute registration
        sqlcmd -S "${CENTRAL_SERVER},${CENTRAL_PORT}" \
               -U "$CENTRAL_USER" \
               -P "$CENTRAL_PASSWORD" \
               -d "$CENTRAL_DATABASE" \
               -C \
               -i /tmp/register_server.sql

        if [ $? -eq 0 ]; then
            print_success "Server registered: $server"
        else
            print_error "Failed to register server: $server"
        fi
    done

    rm -f /tmp/register_server.sql
}

# =============================================
# Linked Server Configuration
# =============================================

configure_linked_servers() {
    print_header "Configuring Linked Servers"

    # Split comma-separated server list into array
    IFS=',' read -ra SERVER_ARRAY <<< "$MONITORED_SERVERS"

    # Add central server if monitoring itself
    if [ "$MONITOR_CENTRAL_SERVER" = "true" ]; then
        SERVER_ARRAY+=("$CENTRAL_SERVER")
    fi

    # Create linked server from central server to each monitored server
    for server in "${SERVER_ARRAY[@]}"; do
        server=$(echo "$server" | xargs)  # Trim whitespace

        # Skip creating linked server to itself
        if [ "$server" = "$CENTRAL_SERVER" ]; then
            print_info "Skipping linked server to self: $server"
            continue
        fi

        print_step "Creating linked server: $server"

        # Create SQL script for linked server
        cat > /tmp/create_linked_server.sql <<EOF
-- Drop existing linked server if exists
IF EXISTS (SELECT 1 FROM sys.servers WHERE name = '${server}')
BEGIN
    EXEC sp_dropserver @server = '${server}', @droplogins = 'droplogins';
    PRINT 'Dropped existing linked server: ${server}';
END
GO

-- Create linked server
EXEC sp_addlinkedserver
    @server = '${server}',
    @srvproduct = '',
    @provider = 'SQLNCLI',
    @datasrc = '${server},${MONITORED_PORT}';

PRINT 'Created linked server: ${server}';
GO

-- Configure linked server login mapping
EXEC sp_addlinkedsrvlogin
    @rmtsrvname = '${server}',
    @useself = 'FALSE',
    @locallogin = NULL,
    @rmtuser = '${MONITORED_USER}',
    @rmtpassword = '${MONITORED_PASSWORD}';

PRINT 'Configured linked server login: ${server}';
GO

-- Test linked server connection
BEGIN TRY
    DECLARE @ServerName NVARCHAR(128);
    SELECT @ServerName = * FROM OPENQUERY([${server}], 'SELECT @@SERVERNAME');
    PRINT 'Linked server test successful: ' + @ServerName;
END TRY
BEGIN CATCH
    PRINT 'WARNING: Linked server test failed: ' + ERROR_MESSAGE();
END CATCH
GO
EOF

        # Execute linked server creation
        sqlcmd -S "${CENTRAL_SERVER},${CENTRAL_PORT}" \
               -U "$CENTRAL_USER" \
               -P "$CENTRAL_PASSWORD" \
               -d master \
               -C \
               -i /tmp/create_linked_server.sql

        if [ $? -eq 0 ]; then
            print_success "Linked server configured: $server"
        else
            print_error "Failed to configure linked server: $server"
        fi
    done

    rm -f /tmp/create_linked_server.sql
}

# =============================================
# SQL Agent Job Configuration
# =============================================

configure_sql_agent_jobs() {
    print_header "Configuring SQL Agent Jobs"

    # Split comma-separated server list into array
    IFS=',' read -ra SERVER_ARRAY <<< "$MONITORED_SERVERS"

    # Add central server if monitoring itself
    if [ "$MONITOR_CENTRAL_SERVER" = "true" ]; then
        SERVER_ARRAY+=("$CENTRAL_SERVER")
    fi

    # Create SQL Agent job on each monitored server
    for server in "${SERVER_ARRAY[@]}"; do
        server=$(echo "$server" | xargs)  # Trim whitespace
        print_step "Creating SQL Agent job on: $server"

        # Determine if this is the central server
        local is_central="false"
        if [ "$server" = "$CENTRAL_SERVER" ]; then
            is_central="true"
        fi

        # Create SQL script for SQL Agent job
        cat > /tmp/create_sql_agent_job.sql <<EOF
USE msdb;
GO

-- Drop existing job if exists
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = 'SQLMonitor_CollectMetrics')
BEGIN
    EXEC sp_delete_job @job_name = 'SQLMonitor_CollectMetrics';
    PRINT 'Dropped existing job: SQLMonitor_CollectMetrics';
END
GO

-- Create SQL Agent job
DECLARE @jobId BINARY(16);
DECLARE @schedule_id INT;
DECLARE @LinkedServerName NVARCHAR(128) = '${CENTRAL_SERVER}';
DECLARE @IsCentralServer BIT = $([ "$is_central" = "true" ] && echo "1" || echo "0");

-- If this IS the central server, use local procedure calls
DECLARE @JobCommand NVARCHAR(MAX);

IF @IsCentralServer = 1
BEGIN
    -- Local execution (central server monitoring itself)
    SET @JobCommand = N'
USE [${CENTRAL_DATABASE}];
GO

DECLARE @ServerName NVARCHAR(128) = @@SERVERNAME;

-- Collect metrics
EXEC dbo.usp_CollectMetrics_RemoteServer @ServerName = @ServerName;

PRINT ''Metrics collected for: '' + @ServerName;
';
END
ELSE
BEGIN
    -- Remote execution (monitored server calling central MonitoringDB)
    SET @JobCommand = N'
DECLARE @ServerName NVARCHAR(128) = @@SERVERNAME;
DECLARE @SQL NVARCHAR(MAX);

-- Call stored procedure on central MonitoringDB via linked server
SET @SQL = N''EXEC [' + @LinkedServerName + '].[${CENTRAL_DATABASE}].dbo.usp_CollectMetrics_RemoteServer @ServerName = '''''' + @ServerName + '''''';'';

EXEC sp_executesql @SQL;

PRINT ''Metrics sent to central server for: '' + @ServerName;
';
END

-- Create job
EXEC dbo.sp_add_job
    @job_name = N'SQLMonitor_CollectMetrics',
    @enabled = 1,
    @description = N'Collects SQL Server performance metrics for SQL Monitor (Client: ${CLIENT_NAME})',
    @job_id = @jobId OUTPUT;

-- Add job step
EXEC dbo.sp_add_jobstep
    @job_id = @jobId,
    @step_name = N'Collect Metrics',
    @subsystem = N'TSQL',
    @command = @JobCommand,
    @database_name = N'master',
    @on_success_action = 1,  -- Quit with success
    @on_fail_action = 2;     -- Quit with failure

-- Create schedule (every ${COLLECTION_INTERVAL} minutes)
EXEC dbo.sp_add_schedule
    @schedule_name = N'Every_${COLLECTION_INTERVAL}_Minutes',
    @freq_type = 4,  -- Daily
    @freq_interval = 1,
    @freq_subday_type = 4,  -- Minutes
    @freq_subday_interval = ${COLLECTION_INTERVAL},
    @active_start_time = 0,
    @schedule_id = @schedule_id OUTPUT;

-- Attach schedule to job
EXEC dbo.sp_attach_schedule
    @job_id = @jobId,
    @schedule_id = @schedule_id;

-- Add job to local server
EXEC dbo.sp_add_jobserver
    @job_id = @jobId,
    @server_name = N'(local)';

PRINT 'SQL Agent job created: SQLMonitor_CollectMetrics';
PRINT 'Collection interval: ${COLLECTION_INTERVAL} minutes';
GO
EOF

        # Execute job creation on monitored server
        sqlcmd -S "${server},${MONITORED_PORT}" \
               -U "$MONITORED_USER" \
               -P "$MONITORED_PASSWORD" \
               -d msdb \
               -C \
               -i /tmp/create_sql_agent_job.sql

        if [ $? -eq 0 ]; then
            print_success "SQL Agent job created on: $server"
        else
            print_error "Failed to create SQL Agent job on: $server"
        fi
    done

    rm -f /tmp/create_sql_agent_job.sql
}

# =============================================
# Initial Metadata Collection
# =============================================

collect_initial_metadata() {
    print_header "Collecting Initial Metadata"

    # Split comma-separated server list into array
    IFS=',' read -ra SERVER_ARRAY <<< "$MONITORED_SERVERS"

    # Add central server if monitoring itself
    if [ "$MONITOR_CENTRAL_SERVER" = "true" ]; then
        SERVER_ARRAY+=("$CENTRAL_SERVER")
    fi

    # Trigger initial collection for each server
    for server in "${SERVER_ARRAY[@]}"; do
        server=$(echo "$server" | xargs)  # Trim whitespace
        print_step "Triggering initial collection for: $server"

        # Create SQL script for initial collection
        cat > /tmp/initial_collection.sql <<EOF
-- Trigger initial metadata collection
EXEC dbo.usp_CollectMetrics_RemoteServer @ServerName = '${server}';
PRINT 'Initial metrics collected for: ${server}';
GO

-- Collect schema metadata (if procedure exists)
IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_CollectSchemaMetadata')
BEGIN
    EXEC dbo.usp_CollectSchemaMetadata @ServerName = '${server}';
    PRINT 'Schema metadata collected for: ${server}';
END
GO
EOF

        # Execute initial collection
        sqlcmd -S "${CENTRAL_SERVER},${CENTRAL_PORT}" \
               -U "$CENTRAL_USER" \
               -P "$CENTRAL_PASSWORD" \
               -d "$CENTRAL_DATABASE" \
               -C \
               -i /tmp/initial_collection.sql

        if [ $? -eq 0 ]; then
            print_success "Initial data collected: $server"
        else
            print_error "Failed initial collection: $server"
        fi
    done

    rm -f /tmp/initial_collection.sql
}

# =============================================
# Verification
# =============================================

verify_deployment() {
    print_header "Verifying Deployment"

    print_step "Checking registered servers..."

    # Query registered servers
    cat > /tmp/verify_servers.sql <<EOF
SELECT
    ServerID,
    ServerName,
    Environment,
    IsActive,
    MonitoringEnabled,
    CollectionIntervalMinutes,
    LastCollectionTime
FROM dbo.Servers
WHERE IsActive = 1
ORDER BY ServerName;
GO
EOF

    sqlcmd -S "${CENTRAL_SERVER},${CENTRAL_PORT}" \
           -U "$CENTRAL_USER" \
           -P "$CENTRAL_PASSWORD" \
           -d "$CENTRAL_DATABASE" \
           -C \
           -i /tmp/verify_servers.sql

    rm -f /tmp/verify_servers.sql

    print_step "Checking recent metrics..."

    # Query recent metrics
    cat > /tmp/verify_metrics.sql <<EOF
SELECT TOP 10
    s.ServerName,
    pm.CollectionTime,
    pm.MetricCategory,
    COUNT(*) AS MetricCount
FROM dbo.PerformanceMetrics pm
INNER JOIN dbo.Servers s ON pm.ServerID = s.ServerID
WHERE pm.CollectionTime >= DATEADD(HOUR, -1, GETUTCDATE())
GROUP BY s.ServerName, pm.CollectionTime, pm.MetricCategory
ORDER BY pm.CollectionTime DESC;
GO
EOF

    sqlcmd -S "${CENTRAL_SERVER},${CENTRAL_PORT}" \
           -U "$CENTRAL_USER" \
           -P "$CENTRAL_PASSWORD" \
           -d "$CENTRAL_DATABASE" \
           -C \
           -i /tmp/verify_metrics.sql

    rm -f /tmp/verify_metrics.sql

    print_success "Verification complete"
}

# =============================================
# Main Deployment Logic
# =============================================

print_header "SQL Monitor - Deploy MonitoringDB and Monitored Servers"
print_info "Client: ${CLIENT_NAME}"
print_info "Central Server: ${CENTRAL_SERVER}:${CENTRAL_PORT}"
print_info "Central Database: ${CENTRAL_DATABASE}"
print_info "Monitored Servers: ${MONITORED_SERVERS}"
print_info "Collection Interval: ${COLLECTION_INTERVAL} minutes"
print_info "Monitor Central Server: ${MONITOR_CENTRAL_SERVER}"

# Validate configuration
validate_config

# Deploy MonitoringDB schema
deploy_monitoringdb

# Register monitored servers
register_monitored_servers

# Configure linked servers (for remote collection)
configure_linked_servers

# Configure SQL Agent jobs on each monitored server
configure_sql_agent_jobs

# Collect initial metadata
collect_initial_metadata

# Verify deployment
verify_deployment

print_header "Deployment Complete!"

print_info "Next steps:"
print_info "1. Verify SQL Agent jobs are running on all monitored servers"
print_info "2. Check SQL Agent job history: SSMS → SQL Server Agent → Jobs → SQLMonitor_CollectMetrics"
print_info "3. Deploy Grafana using deploy-grafana.sh:"
print_info "   DEPLOYMENT_TARGET=local \\"
print_info "   MONITORINGDB_SERVER=${CENTRAL_SERVER} \\"
print_info "   MONITORINGDB_PORT=${CENTRAL_PORT} \\"
print_info "   MONITORINGDB_USER=${CENTRAL_USER} \\"
print_info "   MONITORINGDB_PASSWORD=${CENTRAL_PASSWORD} \\"
print_info "   CLIENT_NAME=${CLIENT_NAME} \\"
print_info "   ./deploy-grafana.sh"
print_info ""
print_info "4. Access Grafana at http://localhost:9002 (or configured port)"
print_info "5. Verify dashboards load with data from all monitored servers"
