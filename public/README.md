# SQL Monitor - Public Deployment Assets

This directory contains publicly accessible files used for deploying SQL Monitor Grafana instances to any container platform (Azure, AWS, on-prem, etc.).

## Contents

```
public/
├── dashboards/               # All Grafana dashboard JSON files (13 dashboards)
│   ├── 00-dashboard-browser.json  # Home page with blog articles
│   ├── 00-landing-page.json
│   ├── 00-sql-server-monitoring.json
│   ├── 01-table-browser.json
│   ├── 02-table-details.json
│   ├── 03-code-browser.json
│   ├── 05-performance-analysis.json
│   ├── 06-query-store.json
│   ├── 07-audit-logging.json
│   ├── 08-insights.json
│   ├── 09-dbcc-integrity-checks.json
│   ├── detailed-metrics.json
│   └── sql-server-overview.json
├── provisioning/
│   ├── dashboards/
│   │   └── dashboards.yaml        # Dashboard provider configuration
│   └── datasources/
│       └── monitoringdb.yaml      # MonitoringDB datasource template
└── grafana-entrypoint.sh          # Startup script for container deployment

```

## How It Works

### Automated Dashboard Download

The `grafana-entrypoint.sh` script is executed when a Grafana container starts. It:

1. **Downloads** all dashboard files from this GitHub repo
2. **Configures** Grafana provisioning (datasources and dashboards)
3. **Starts** Grafana with all dashboards available immediately

### Usage

#### Azure Container Instances

```bash
az container create \
    --resource-group rg-sqlmonitor \
    --name grafana-sqlmonitor \
    --image grafana/grafana-oss:10.2.0 \
    --os-type Linux \
    --dns-name-label client-sqlmonitor \
    --ports 3000 \
    --cpu 2 \
    --memory 4 \
    --environment-variables \
        GF_SECURITY_ADMIN_PASSWORD="YourPassword" \
        GF_SERVER_ROOT_URL="http://client-sqlmonitor.eastus.azurecontainer.io" \
        GITHUB_REPO="https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/public" \
    --command-line "/bin/sh -c 'apk add --no-cache wget && wget -O /tmp/entrypoint.sh https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/public/grafana-entrypoint.sh && chmod +x /tmp/entrypoint.sh && /tmp/entrypoint.sh'" \
    --location eastus
```

#### AWS ECS Fargate

```json
{
  "family": "grafana-sqlmonitor",
  "containerDefinitions": [{
    "name": "grafana",
    "image": "grafana/grafana-oss:10.2.0",
    "portMappings": [{"containerPort": 3000}],
    "environment": [
      {"name": "GF_SECURITY_ADMIN_PASSWORD", "value": "YourPassword"},
      {"name": "GITHUB_REPO", "value": "https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/public"}
    ],
    "entryPoint": ["/bin/sh", "-c"],
    "command": ["apk add --no-cache wget && wget -O /tmp/entrypoint.sh https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/public/grafana-entrypoint.sh && chmod +x /tmp/entrypoint.sh && /tmp/entrypoint.sh"]
  }]
}
```

#### Local Docker / Docker Compose

```yaml
version: '3.8'
services:
  grafana:
    image: grafana/grafana-oss:10.2.0
    ports:
      - "9002:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=Admin123!
      - GITHUB_REPO=https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/public
    command: >
      /bin/sh -c "
      apk add --no-cache wget &&
      wget -O /tmp/entrypoint.sh https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/public/grafana-entrypoint.sh &&
      chmod +x /tmp/entrypoint.sh &&
      /tmp/entrypoint.sh
      "
```

#### Kubernetes

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana-sqlmonitor
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      containers:
      - name: grafana
        image: grafana/grafana-oss:10.2.0
        ports:
        - containerPort: 3000
        env:
        - name: GF_SECURITY_ADMIN_PASSWORD
          value: "YourPassword"
        - name: GITHUB_REPO
          value: "https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/public"
        command: ["/bin/sh", "-c"]
        args:
        - |
          apk add --no-cache wget &&
          wget -O /tmp/entrypoint.sh https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/public/grafana-entrypoint.sh &&
          chmod +x /tmp/entrypoint.sh &&
          /tmp/entrypoint.sh
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GITHUB_REPO` | No | `https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/public` | Base URL for downloading dashboards |
| `GF_SECURITY_ADMIN_PASSWORD` | Yes | - | Grafana admin password |
| `GF_SERVER_ROOT_URL` | No | - | Public URL where Grafana will be accessed |

## Customization

### Using a Fork or Private Repo

If you fork this repo or want to use a private repo:

1. Update `GITHUB_REPO` environment variable to point to your repo:
   ```
   GITHUB_REPO="https://raw.githubusercontent.com/dbbuilder/sql-monitor/main/public"
   ```

2. For private repos, you'll need to provide authentication:
   ```
   GITHUB_TOKEN="ghp_your_token_here"
   ```

   Update entrypoint script to use token:
   ```bash
   wget --header="Authorization: token $GITHUB_TOKEN" -O file.json URL
   ```

### Adding Custom Dashboards

1. Add your dashboard JSON to `public/dashboards/`
2. Update `grafana-entrypoint.sh` DASHBOARDS array
3. Commit and push to GitHub
4. Redeploy containers - they'll automatically download new dashboards

### Modifying Datasource Configuration

Edit `public/provisioning/datasources/monitoringdb.yaml` to change:
- Connection string format
- Security settings
- Pool sizes
- Encryption settings

## Security Considerations

### Why Public Repo?

- Dashboard JSON files contain no secrets (only queries and visualizations)
- Datasource credentials are passed via environment variables at runtime
- Blog content is educational and can be public
- Makes deployment simpler (no authentication required)

### Best Practices

1. **Never commit**:
   - Database passwords
   - Grafana admin passwords
   - API keys or tokens
   - Connection strings with credentials

2. **Use environment variables** for all sensitive data

3. **Review dashboards** before making repo public to ensure no sensitive data embedded

## Troubleshooting

### Dashboards Not Showing

**Check container logs**:
```bash
# Azure
az container logs --resource-group rg-sqlmonitor --name grafana-sqlmonitor

# Docker
docker logs grafana-sqlmonitor

# Kubernetes
kubectl logs deployment/grafana-sqlmonitor
```

**Common issues**:
- wget not installed (add `apk add --no-cache wget` to command)
- GitHub rate limiting (use GITHUB_TOKEN for private repos)
- Network connectivity (check firewall allows HTTPS to github.com)
- Wrong GITHUB_REPO URL (verify raw.githubusercontent.com format)

### Datasource Not Configured

The datasource template in `public/provisioning/datasources/monitoringdb.yaml` is a template only. You need to customize it at deployment time with your actual MonitoringDB connection details.

**Solution**: Pass environment variables or use deployment scripts that generate the datasource config dynamically.

## Deployment Scripts

This repo includes automated deployment scripts that handle everything:

- `deploy-grafana.sh` - Deploys Grafana to local/Azure/AWS with GitHub integration
- `deploy-monitoring.sh` - Deploys MonitoringDB and configures data collection

**See main README.md for usage.**

## Blog Articles

The Dashboard Browser (`00-dashboard-browser.json`) includes 12 embedded SQL Server optimization articles:

1. How to Add Indexes Based on Statistics
2. Temp Tables vs Table Variables
3. When CTE is NOT the Best Idea
4. Error Handling and Logging
5. Cross-Database Queries and Message Hubs
6. The Value of INCLUDE and Index Options
7. Branchable Logic in WHERE Clauses
8. When Table-Valued Functions Are Best
9. How to Optimize UPSERT Operations
10. Partitioning Large Tables
11. Managing Mammoth Tables
12. When to Rebuild Indexes

These are automatically included when dashboards are downloaded from GitHub.

## Contributing

To add new dashboards or update existing ones:

1. Test dashboard locally in Grafana
2. Export dashboard JSON (Settings → JSON Model → Copy)
3. Save to `public/dashboards/`
4. Update `grafana-entrypoint.sh` DASHBOARDS array if needed
5. Commit and push
6. Redeploy containers to pull latest

---

**Last Updated**: 2025-10-29
**Version**: 1.0
**License**: MIT (dashboards and scripts)
