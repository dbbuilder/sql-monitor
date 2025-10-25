# SQL Server Monitor - Requirements Specification

## Executive Summary

This document consolidates requirements from multiple sources to define a comprehensive SQL Server monitoring solution that surpasses AWS RDS Performance Insights and commercial solutions. The system provides deep visibility for developers and DBAs across **any environment** (on-premises data centers, private clouds, public clouds).

### Key Drivers

- **Limitations of Commercial Solutions**: AWS RDS Performance Insights, SolarWinds, Redgate lack stored procedure introspection, customization, and long-term retention
- **Developer-Centric**: Code-level performance analysis, regressions, and optimization opportunities
- **Cost Efficiency**: Eliminate $30k-40k/year in licensing fees (20 server fleet)
- **Full Control**: Data collection, retention, historical analysis, DevOps integration
- **Deployment Flexibility**: Works on-prem, in any cloud (Azure/AWS/GCP), or hybrid - never requires internet access
- **Security-First**: 100% air-gapped deployment option (no external connections required)

## 1. Architectural Requirements

### AR-1: Platform Support
- **AR-1.1**: Microsoft SQL Server 2016+ with SQL Server 2025 compatibility
- **AR-1.2**: Support for SQL Server on **any infrastructure**:
  - On-premises data centers (Windows/Linux)
  - Cloud VMs (Azure VM, AWS EC2, GCP Compute Engine, any cloud provider)
  - Managed instances (Azure SQL MI, AWS RDS SQL Server, etc.)
  - Containers (SQL Server on Docker/Kubernetes)
- **AR-1.3**: MonitoringDB runs on **internal SQL Server** (no external database services)
- **AR-1.4**: Modular design: deploy per-instance or centralized for multiple instances
- **AR-1.5**: No dependency on proprietary SaaS agents or external services

### AR-2: Security (Air-Gap Compatible)
- **AR-2.1**: Encryption at rest (TDE) and in transit (TLS 1.2+)
- **AR-2.2**: Secure credential storage options (in priority order):
  - Docker secrets (recommended for Kubernetes/Swarm)
  - Environment variables with restricted file permissions
  - Encrypted configuration files (local filesystem)
  - Optional external: HashiCorp Vault, Azure Key Vault, AWS Secrets Manager (only if infrastructure exists)
- **AR-2.3**: Principle of least privilege: Collectors use VIEW SERVER STATE, VIEW DATABASE STATE only
- **AR-2.4**: No sysadmin or db_owner rights required on monitored instances
- **AR-2.5**: **Zero external network dependencies** (works completely offline/air-gapped)

### AR-3: Scalability
- **AR-3.1**: Support 20-100 SQL Server instances from single deployment
- **AR-3.2**: Central data warehouse scales to 100TB+ (time-series data)
- **AR-3.3**: Horizontal scaling via multiple MonitoringDB instances (sharding by region/environment)
- **AR-3.4**: Lightweight container deployment (1-2 containers: API + Grafana)

### AR-4: Self-Hosted Architecture (CRITICAL - Firewall-Safe)
- **AR-4.1**: MonitoringDB resides on one of the existing monitored SQL Servers (zero additional database cost)
- **AR-4.2**: Collection via SQL Agent jobs calling stored procedures over linked servers (no external agents)
- **AR-4.3**: API and UI run in 1-2 Docker containers with local storage (Docker volumes, persistent volumes in K8s)
- **AR-4.4**: **Zero mandatory cloud services** (no Azure, AWS, GCP dependencies)
- **AR-4.5**: **Works behind firewall** (no inbound/outbound internet requirements)
- **AR-4.6**: Storage: Local filesystem, NFS, SMB, or cloud block storage (EBS, Azure Disk) - never blob/object storage
- **AR-4.7**: Total infrastructure cost: $0-$1,500/year (vs. $27k-$37k for commercial solutions)
- **AR-4.8**: 100% open-source technology stack (Apache 2.0, MIT licenses only)

## 2. Data Collection Requirements

### DC-1: Extended Events Integration
- **DC-1.1**: Custom event sessions for:
  - Query execution (`query_post_execution_showplan`)
  - Stored procedure performance (`rpc_completed`)
  - Blocking and deadlocks (`blocked_process_report`, `deadlock_graph`)
  - Parameter sniffing detection (`query_execution` with parameter values)
  - Wait information (`wait_info`)
- **DC-1.2**: Time-bound event support (SQL Server 2025 feature)
- **DC-1.3**: Dual targets: Ring buffer (real-time) + Event file (historical)
- **DC-1.4**: Configurable event retention (local): 24-48 hours before bulk load

### DC-2: Query Store Utilization
- **DC-2.1**: Automatic plan capture and regression detection
- **DC-2.2**: Wait stats aggregation at query and procedure level
- **DC-2.3**: Configuration: 90+ days retention, AUTO capture mode
- **DC-2.4**: Plan forcing detection and alerting
- **DC-2.5**: Integration with `sys.query_store_query_text` for procedure correlation

### DC-3: DMV Snapshot Collection
**Frequency**: Every 5-15 minutes (configurable per instance)

**Required DMVs**:
- `sys.dm_exec_query_stats` - Query performance
- `sys.dm_exec_procedure_stats` - Stored procedure metrics
- `sys.dm_os_wait_stats` - Wait statistics
- `sys.dm_io_virtual_file_stats` - I/O latency and throughput
- `sys.dm_db_index_usage_stats` - Index usage patterns
- `sys.dm_os_performance_counters` - SQL Server counters
- `sys.dm_os_memory_clerks` - Memory allocation by component
- `sys.dm_db_missing_index_details` - Missing index recommendations
- `sys.dm_os_sys_memory` - System memory information
- `sys.dm_os_schedulers` - CPU scheduler details

**DC-3.1**: Delta calculations: Store deltas for cumulative counters (wait times, executions)
**DC-3.2**: Automatic server metadata capture (version, edition, hardware specs)

### DC-4: Custom Health Metrics
- **DC-4.1**: SQL Agent job status and latency
- **DC-4.2**: Backup completion status and age
- **DC-4.3**: Database autogrowth events
- **DC-4.4**: CPU saturation events
- **DC-4.5**: Virtual Log File (VLF) counts
- **DC-4.6**: Transaction log backup age

## 3. Stored Procedure and Code Introspection

### SP-1: Procedure-Level Metrics
- **SP-1.1**: Track per stored procedure:
  - Execution count
  - Total/average worker time (CPU)
  - Total/average elapsed time
  - Logical reads/writes
  - Physical reads
  - Average/max/min duration
- **SP-1.2**: Correlation with blocking and deadlock incidents
- **SP-1.3**: Parameter sniffing pattern detection (variance analysis)
- **SP-1.4**: Plan hash tracking for plan change detection

### SP-2: Code Change Analysis
- **SP-2.1**: Baseline fingerprinting: Hash of procedure definition (`OBJECT_DEFINITION()`)
- **SP-2.2**: Automatic detection of procedure modifications
- **SP-2.3**: Before/after performance comparison for deployments
- **SP-2.4**: Schema change correlation with performance shifts
- **SP-2.5**: Integration with version control (Git commit hash tagging)

### SP-3: Performance Regression Detection
- **SP-3.1**: Automatic flagging of procedures with ≥25% duration increase
- **SP-3.2**: Plan regression detection via Query Store
- **SP-3.3**: Forced plan interventions and tracking
- **SP-3.4**: Execution context tracking (application name, host, user)

## 4. Developer-Focused Features

### DEV-1: Developer Dashboard
- **DEV-1.1**: Top stored procedures by resource usage (CPU, duration, I/O)
- **DEV-1.2**: Query execution plan visualization (graphical rendering)
- **DEV-1.3**: Plan history and comparison
- **DEV-1.4**: Parameter performance variance analysis
- **DEV-1.5**: Real-time blocking chain visualization
- **DEV-1.6**: Personalized alert subscriptions (procedure regressions, blocking)

### DEV-2: Code Deployment Tracker
- **DEV-2.1**: Pre- and post-deployment performance comparison
- **DEV-2.2**: Git commit/release ID tagging of metrics
- **DEV-2.3**: Impact analysis report (affected procedures, performance delta)
- **DEV-2.4**: Automated regression testing integration

### DEV-3: Ad-Hoc Profiling
- **DEV-3.1**: On-demand Extended Event session creation from dashboard
- **DEV-3.2**: Deep dive into specific query execution
- **DEV-3.3**: Parameter value capture for troubleshooting

## 5. DBA-Focused Features

### DBA-1: Operational Dashboard
- **DBA-1.1**: Instance health summary:
  - CPU utilization and trends
  - Memory usage (buffer pool, plan cache)
  - I/O latency and throughput
  - Wait statistics breakdown
  - Page Life Expectancy
  - Log growth rate
- **DBA-1.2**: Top N resource consumers (procedures, queries, sessions)
- **DBA-1.3**: Blocking and deadlock history with root cause analytics
- **DBA-1.4**: Configuration drift tracking across environments

### DBA-2: Capacity Planning
- **DBA-2.1**: Database size trends (data and log files)
- **DBA-2.2**: Growth projections (linear and polynomial regression)
- **DBA-2.3**: VLF count tracking and alerting
- **DBA-2.4**: Index fragmentation trends

### DBA-3: Maintenance Automation
- **DBA-3.1**: Index maintenance recommendations (rebuild vs. reorganize)
- **DBA-3.2**: Missing index identification with impact scoring
- **DBA-3.3**: Unused index detection
- **DBA-3.4**: Statistics age analysis and update recommendations
- **DBA-3.5**: Automated backup integrity check status

### DBA-4: Custom Analysis Procedures
- **DBA-4.1**: `sp_WhoIsActive` equivalent with historical storage
- **DBA-4.2**: Plan regression detection procedures
- **DBA-4.3**: Resource utilization trending views
- **DBA-4.4**: Deadlock graph parsing and analysis

## 6. Historical Data Warehouse

### HDW-1: Data Retention
- **HDW-1.1**: Detailed metrics: 30-90 days (configurable)
- **HDW-1.2**: Aggregated metrics: 1+ year
- **HDW-1.3**: Rollup tiers:
  - Raw: 5-minute intervals for 30 days
  - Hourly aggregates: 90 days
  - Daily aggregates: 1 year
  - Weekly/Monthly aggregates: 3+ years
- **HDW-1.4**: Configurable retention policies per metric category

### HDW-2: Storage Optimization
- **HDW-2.1**: Partitioning: Monthly partitions on `CollectionTime`
- **HDW-2.2**: Columnstore indexes on large fact tables
- **HDW-2.3**: PAGE compression on historical partitions
- **HDW-2.4**: Sliding window partition management (automatic SWITCH)

### HDW-3: Data Archival
- **HDW-3.1**: Automatic archival to configurable storage:
  - Local filesystem (mounted volumes)
  - Network file share (NFS, SMB/CIFS)
  - Optional cloud storage (Azure Blob, AWS S3, GCP Storage) only if already in use
- **HDW-3.2**: Purge jobs for data beyond retention window
- **HDW-3.3**: Archived data retrieval mechanism (for compliance/audit)
- **HDW-3.4**: Archive format: SQL backup (.bak) or compressed CSV (no proprietary formats)

## 7. Alerting and Automation

### ALERT-1: Alert Rules
- **ALERT-1.1**: Configurable thresholds for:
  - Procedure duration regression (≥25% increase)
  - CPU utilization (≥80% for 5+ minutes)
  - Memory pressure (Page Life Expectancy <300 seconds)
  - I/O latency (≥20ms average for 5+ minutes)
  - Blocking (≥30 seconds)
  - Parameter sniffing variance (≥3x standard deviation)
  - Missing index impact (≥1M improvement score)
  - VLF count (≥500)
  - Deadlock occurrences
- **ALERT-1.2**: Multi-level severity: Information, Warning, Critical
- **ALERT-1.3**: Alert suppression: Prevent duplicate alerts within configurable time window
- **ALERT-1.4**: Maintenance window integration (suppress alerts during planned downtime)

### ALERT-2: Notification Delivery (Air-Gap Compatible)
- **ALERT-2.1**: Email via internal SMTP server (no cloud email services required)
- **ALERT-2.2**: Webhooks to internal systems (Slack, Teams, Mattermost, or self-hosted chat)
- **ALERT-2.3**: Custom webhook integration (for ITSM systems like ServiceNow, PagerDuty, JIRA)
- **ALERT-2.4**: Database Mail (SQL Server built-in, no external dependencies)
- **ALERT-2.5**: SMS via internal SMS gateway (optional, Twilio/other only if already in use)

### ALERT-3: Automated Responses
- **ALERT-3.1**: Read-only automation:
  - Capture `sp_whoisactive` snapshot on blocking alert
  - Export deadlock graph on deadlock event
  - Capture query plan on regression alert
- **ALERT-3.2**: Alert enrichment: Include diagnostic data in notification
- **ALERT-3.3**: Integration with CI/CD pipelines (fail build on critical regression)

### ALERT-4: Baseline and Anomaly Detection
- **ALERT-4.1**: Automated baseline calculation (7-day and 30-day averages)
- **ALERT-4.2**: Anomaly detection: Flag metrics exceeding ±3 standard deviations
- **ALERT-4.3**: Scheduled baseline recalculation (weekly)
- **ALERT-4.4**: Machine learning-based anomaly detection (Phase 2)

## 8. Visualization and Reporting

### VIZ-1: Dashboards
- **VIZ-1.1**: Real-time operational dashboard (Grafana):
  - System health overview
  - Top resource consumers
  - Active blocking chains
  - Wait statistics breakdown
  - Auto-refresh: 30 seconds
- **VIZ-1.2**: Developer dashboard (Grafana):
  - Stored procedure performance grid
  - Query plan visualizations
  - Parameter variance analysis
  - Code deployment impact reports
- **VIZ-1.3**: DBA dashboard (Grafana/Power BI):
  - Capacity planning trends
  - Index maintenance recommendations
  - Configuration drift reports
  - Backup status overview

### VIZ-2: Historical Analysis
- **VIZ-2.1**: Time-series charts with drill-down:
  - Instance → Database → Procedure → Query
- **VIZ-2.2**: Date range selection (custom, 1h, 24h, 7d, 30d, 90d)
- **VIZ-2.3**: Comparison views: Compare two time periods side-by-side
- **VIZ-2.4**: Correlation analysis: Overlay multiple metrics

### VIZ-3: Reporting
- **VIZ-3.1**: Exportable data formats: CSV, Excel, JSON
- **VIZ-3.2**: Scheduled reports (daily/weekly/monthly)
- **VIZ-3.3**: Power BI templates for executive reporting
- **VIZ-3.4**: Cost-of-query reporting (resource utilization × hardware cost)

### VIZ-4: Query Plan Visualization
- **VIZ-4.1**: Graphical plan rendering (SSMS XML import or web UI)
- **VIZ-4.2**: Plan comparison (before/after deployment)
- **VIZ-4.3**: Plan forcing status indicators

## 9. Security and Access Control

### SEC-1: Authentication (Flexible, No Cloud Required)
- **SEC-1.1**: Internal authentication options (in priority order):
  - Active Directory / LDAP (on-prem or cloud-hosted)
  - SQL authentication (works everywhere)
  - API key authentication (for programmatic access)
  - Optional: Azure AD / Entra ID (only if infrastructure exists)
- **SEC-1.2**: Grafana built-in authentication (local users, no SSO required)
- **SEC-1.3**: No mandatory SSO or cloud identity provider

### SEC-2: Authorization (RBAC)
- **SEC-2.1**: Roles:
  - **DBA Role**: Full access (read/write, configuration, alerts)
  - **Developer Role**: Limited to performance views, own alert subscriptions
  - **Auditor Role**: Read-only access, export capabilities
  - **Service Account**: Collector agents, write-only to staging tables
- **SEC-2.2**: Row-level security: Developers see only their application's procedures
- **SEC-2.3**: Server-level access control: Restrict visibility by environment/platform

### SEC-3: Audit and Compliance
- **SEC-3.1**: Audit logging:
  - All authentication attempts
  - Configuration changes
  - Alert rule modifications
  - Data access (export operations)
- **SEC-3.2**: Retention: 1+ year for audit logs
- **SEC-3.3**: Immutable audit trail (append-only table with ledger)
- **SEC-3.4**: Compliance reporting: SOX, HIPAA, FERPA support

### SEC-4: Data Protection
- **SEC-4.1**: Sensitive data masking in query text (passwords, credit cards, PII)
- **SEC-4.2**: GDPR compliance: Right to erasure support
- **SEC-4.3**: Encryption at rest: TDE (Transparent Data Encryption) on SQL Server
- **SEC-4.4**: Encryption in transit: TLS 1.2+ for all connections (SQL, API, Grafana)
- **SEC-4.5**: No data ever leaves the customer network (air-gap deployment supported)

## 10. Integration and Extensibility

### INT-1: RESTful API (Internal Network Only)
- **INT-1.1**: OpenAPI 3.0 specification (Swagger UI available at `/swagger`)
- **INT-1.2**: Endpoints (all internal, no internet exposure required):
  - `GET /api/servers` - Server inventory management
  - `GET /api/metrics/{serverId}` - Retrieve metrics and history
  - `GET /api/alerts` - Alert history and active alerts
  - `POST /api/alerts/rules` - Create/update alert rules
  - `GET /api/recommendations/{serverId}` - Retrieve performance recommendations
  - `GET /health` - Health check endpoint
- **INT-1.3**: Authentication: API keys, SQL auth, or LDAP (no cloud IdP required)
- **INT-1.4**: Rate limiting: 1000 requests/minute per client (configurable)
- **INT-1.5**: API accessible only within customer network (no public internet exposure)

### INT-2: CI/CD Integration
- **INT-2.1**: Webhook notifications to build pipelines
- **INT-2.2**: API endpoint for pre/post-deployment tagging
- **INT-2.3**: Automated regression checks (fail build on critical regression)
- **INT-2.4**: PowerShell/Python SDK for scripting

### INT-3: External Tool Integration (All Internal)
- **INT-3.1**: Grafana OSS as primary UI (Apache 2.0 license, runs in Docker)
- **INT-3.2**: Compatibility with SQL monitoring tools:
  - SQLWATCH (dashboard pattern inspiration)
  - DBA Dash (alerting pattern inspiration)
  - sp_WhoIsActive (query pattern integration)
- **INT-3.3**: Export to internal systems only:
  - Internal logging servers (syslog, Graylog, ELK stack)
  - Internal metrics systems (Prometheus, InfluxDB, self-hosted)
  - ITSM systems (ServiceNow, JIRA, self-hosted)
- **INT-3.4**: Cloud integration completely optional (never required)

### INT-4: Infrastructure as Code
- **INT-4.1**: Docker Compose for container deployment (primary method)
- **INT-4.2**: SQL scripts for database deployment (T-SQL)
- **INT-4.3**: Configuration as code: JSON for Grafana dashboards, SQL for alert rules
- **INT-4.4**: Version control for all deployment artifacts (Git repository)
- **INT-4.5**: Optional advanced deployment:
  - Kubernetes Helm charts (for enterprise scale 50+ servers)
  - Terraform for multi-cloud infrastructure
  - PowerShell DSC for Windows Server automation

## 11. Monitoring Operations and Maintenance

### OPS-1: Instance Discovery (Internal Network Only)
- **OPS-1.1**: Automatic discovery via:
  - Active Directory / LDAP queries (on-prem or self-hosted)
  - SQL Server Central Management Server (CMS)
  - Network scanning (configurable IP ranges)
  - Manual registration (CSV import or API)
- **OPS-1.2**: Central inventory table with automatic registration
- **OPS-1.3**: Collection job heartbeat monitoring (detect stale servers)

### OPS-2: Self-Monitoring (Internal Only)
- **OPS-2.1**: Health checks for monitoring infrastructure:
  - SQL Agent job status (collection jobs)
  - API endpoint availability (internal HTTP check)
  - MonitoringDB health (connection, disk space, fragmentation)
  - Docker container health (via HEALTHCHECK)
- **OPS-2.2**: Self-diagnosis and alerting:
  - Failed collection jobs (via SQL Agent alerts)
  - API errors (logged to SQL table or local file)
  - Database connection failures
- **OPS-2.3**: Internal telemetry options:
  - SQL Server Extended Events (self-monitoring)
  - Local log files (structured logging via Serilog)
  - Optional: Internal Prometheus/Grafana (monitoring the monitor)

### OPS-3: Documentation
- **OPS-3.1**: Inline documentation: Every stored procedure and job documented
- **OPS-3.2**: Runbooks:
  - Onboarding new SQL Server
  - Troubleshooting failed collector
  - Responding to critical alerts
- **OPS-3.3**: Architecture diagrams (component, data flow, network)
- **OPS-3.4**: Video tutorials (optional, for training)

### OPS-4: Configuration Management
- **OPS-4.1**: Configuration snapshots (daily):
  - Server-level settings (MaxDOP, CTFP, trace flags)
  - Database-level settings (recovery model, compatibility level)
- **OPS-4.2**: Drift detection: Alert on configuration changes
- **OPS-4.3**: Change approval workflow (for critical configuration)

## 12. Non-Functional Requirements

### NFR-1: Performance
- **NFR-1.1**: Collection overhead: ≤3% CPU on monitored instances
- **NFR-1.2**: API response time: <500ms for dashboard queries
- **NFR-1.3**: Dashboard load time: <2 seconds (real-time view)
- **NFR-1.4**: Data ingestion latency:
  - Critical alerts: ≤60 seconds
  - Dashboard metrics: ≤10 minutes
  - Historical data: ≤30 minutes

### NFR-2: Availability
- **NFR-2.1**: Monitoring service uptime: 99.9% (8.76 hours/year downtime)
- **NFR-2.2**: Graceful degradation: Collectors cache locally if API unavailable
- **NFR-2.3**: Failover: Secondary warehouse replica for HA
- **NFR-2.4**: RTO/RPO:
  - RTO ≤4 hours (restore monitoring service)
  - RPO ≤1 hour (maximum data loss)

### NFR-3: Scalability
- **NFR-3.1**: Concurrent users: 1000+ on dashboard
- **NFR-3.2**: Monitored instances: 20-100 from single deployment
- **NFR-3.3**: Metrics ingestion rate: 100,000+ metrics/minute
- **NFR-3.4**: Historical data: 100TB+ warehouse capacity

### NFR-4: Usability
- **NFR-4.1**: Intuitive UI: Low learning curve (<1 hour for basic usage)
- **NFR-4.2**: Mobile-responsive dashboards
- **NFR-4.3**: Contextual help and tooltips
- **NFR-4.4**: Search and filter capabilities on all grids

### NFR-5: Maintainability
- **NFR-5.1**: Code documentation: All modules documented
- **NFR-5.2**: Unit test coverage: ≥80% for business logic
- **NFR-5.3**: Automated deployment: Zero-downtime updates
- **NFR-5.4**: Version control: Git repository for all artifacts

## 13. Future Enhancements (Phase 2+)

### FUT-1: Advanced Analytics
- **FUT-1.1**: Machine learning-based anomaly detection (Python + Azure ML)
- **FUT-1.2**: Automated performance tuning suggestions (index creation, parameter sniffing fixes)
- **FUT-1.3**: Predictive capacity planning (ML regression models)

### FUT-2: Cloud-Native Expansion
- **FUT-2.1**: Azure SQL Database support (serverless, Hyperscale)
- **FUT-2.2**: AWS RDS SQL Server integration
- **FUT-2.3**: Cross-cloud aggregated insights dashboard

### FUT-3: Containerization
- **FUT-3.1**: Kubernetes deployment for collector fleet
- **FUT-3.2**: Helm charts for collector and API
- **FUT-3.3**: Service mesh integration (Istio) for collector network

### FUT-4: Advanced Visualizations
- **FUT-4.1**: 3D query plan visualizations
- **FUT-4.2**: Real-time blocking chain animations
- **FUT-4.3**: Heatmaps for resource utilization

## 14. Technology Stack Requirements

### TECH-1: Mandatory Technology Stack
- **TECH-1.1**: Database: SQL Server 2016+ (existing infrastructure, any edition)
- **TECH-1.2**: API: ASP.NET Core 8.0 LTS (MIT license)
- **TECH-1.3**: Data Access: Dapper 2.x (Apache 2.0 license)
- **TECH-1.4**: UI: Grafana OSS 10.x (Apache 2.0 license)
- **TECH-1.5**: Containers: Docker + Docker Compose (Apache 2.0 license)
- **TECH-1.6**: Collection: SQL Server Agent + Linked Servers (built-in, no cost)

### TECH-2: Prohibited Dependencies (Air-Gap Compliance)
- **TECH-2.1**: NO commercial software licenses required (beyond existing SQL Server)
- **TECH-2.2**: NO mandatory cloud services (Azure, AWS, GCP) - works 100% offline
- **TECH-2.3**: NO external agent software (PowerShell-based agents, third-party collectors)
- **TECH-2.4**: NO heavy ORMs (Entity Framework Core for data access - use Dapper instead)
- **TECH-2.5**: NO proprietary UI frameworks (use Grafana OSS, not custom Vue/React)
- **TECH-2.6**: NO internet connectivity required (can deploy completely air-gapped)
- **TECH-2.7**: NO cloud blob/object storage (Azure Blob, AWS S3) - use local/block storage only

### TECH-3: Optional Enhancements (Only If Infrastructure Exists)
- **TECH-3.1**: Cloud secrets management (Azure Key Vault, AWS Secrets Manager, HashiCorp Vault)
- **TECH-3.2**: Kubernetes for enterprise scale (50+ servers, but Docker Compose works for most)
- **TECH-3.3**: Cloud monitoring integration (Application Insights, CloudWatch) - purely optional
- **TECH-3.4**: PostgreSQL with TimescaleDB (alternative to SQL Server for MonitoringDB)

### TECH-4: Development Tooling
- **TECH-4.1**: Testing: xUnit (API), tSQLt (database), Grafana built-in query tester (UI)
- **TECH-4.2**: IDE: Visual Studio Code or Visual Studio 2022
- **TECH-4.3**: Version Control: Git (GitHub, GitLab, Azure DevOps, or self-hosted)
- **TECH-4.4**: CI/CD: GitHub Actions, Azure DevOps Pipelines, Jenkins, or GitLab CI

## Success Criteria

### SC-1: Performance Metrics
- ✅ Dashboard loads in <2 seconds
- ✅ Real-time metrics updated every 30 seconds
- ✅ Zero data loss during collection (99.9% delivery rate)
- ✅ Collection overhead <3% CPU on monitored servers

### SC-2: Business Impact
- ✅ Reduce mean time to detect (MTTD) performance issues by 80%
- ✅ Reduce mean time to resolve (MTTR) performance issues by 50%
- ✅ 90% user satisfaction rating (developers and DBAs)
- ✅ ROI: Cost savings >$20k/year for 20 server fleet

### SC-3: Reliability
- ✅ 99.9% uptime measured over 30 days
- ✅ <1% failed metric collections due to application errors
- ✅ Zero critical security vulnerabilities (OWASP Top 10)

### SC-4: Adoption
- ✅ 100% of production servers monitored within 6 months
- ✅ 50% of developers actively using dashboards weekly
- ✅ 90% of performance incidents diagnosed using monitoring data

## Out of Scope (Initial Release)

- ❌ SQL Server Agent job monitoring (Phase 2)
- ❌ Database backup monitoring (Phase 2)
- ❌ High Availability (Always On AG) monitoring (Phase 2)
- ❌ Mobile native applications (responsive Grafana dashboards only)
- ❌ Machine learning anomaly detection (Phase 2)
- ❌ Automated remediation actions (read-only automation only)
- ❌ Multi-tenancy support (single organization only)
- ❌ Custom web frontend (Grafana OSS provides all UI needs)

## Appendix: Glossary

- **DMV**: Dynamic Management View (SQL Server system views)
- **Extended Events**: SQL Server event capture framework
- **Query Store**: Built-in query performance tracking (SQL 2016+)
- **PLE**: Page Life Expectancy (memory pressure indicator)
- **VLF**: Virtual Log File (transaction log segment)
- **CTFP**: Cost Threshold for Parallelism (SQL configuration)
- **MaxDOP**: Max Degree of Parallelism (SQL configuration)
- **TDE**: Transparent Data Encryption
- **MTTD**: Mean Time to Detect
- **MTTR**: Mean Time to Resolve
