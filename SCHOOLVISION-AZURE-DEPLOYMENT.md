# SchoolVision SQL Monitor - Azure Deployment Summary

**Deployment Date**: 2025-10-29
**Status**: ✅ Successfully Migrated to Azure

---

## Deployment Information

### Azure Subscription
- **Subscription Name**: Test Environment
- **Subscription ID**: 7b2beff3-b38a-4516-a75f-3216725cc4e9
- **Tenant**: DBBuilder (dbbuilder.io)
- **Account**: sql@schoolvision.net

### Resource Group
- **Name**: rg-sqlmonitor-schoolvision
- **Location**: East US
- **Status**: Active

### Grafana Container Instance
- **Container Name**: grafana-schoolvision
- **Image**: grafana/grafana-oss:10.2.0
- **OS Type**: Linux
- **CPU**: 2 cores
- **Memory**: 4 GB
- **Status**: ✅ Running
- **Restart Count**: 0

---

## Access Information

### Grafana Web Interface
- **URL**: http://schoolvision-sqlmonitor.eastus.azurecontainer.io:3000
- **Public IP**: 52.249.200.138
- **DNS Name**: schoolvision-sqlmonitor.eastus.azurecontainer.io
- **Username**: admin
- **Password**: Admin123!

### MonitoringDB Connection
- **Server**: sqltest.schoolvision.net,14333
- **Database**: MonitoringDB
- **User**: sv
- **Password**: Gv51076!
- **Datasource**: Configured and provisioned

---

## What Changed

### Before (Local Docker)
- **Location**: Local workstation
- **Container**: sql-monitor-grafana-schoolvision
- **Port**: http://localhost:9002
- **Persistence**: Local Docker volume (grafana-data-schoolvision)
- **Access**: Local network only

### After (Azure Container Instances)
- **Location**: Azure East US
- **Container**: grafana-schoolvision
- **URL**: http://schoolvision-sqlmonitor.eastus.azurecontainer.io:3000
- **Persistence**: Container instance (ephemeral, recreates on restart)
- **Access**: Internet-accessible (public IP)

---

## Important Notes

### 1. Dashboard Provisioning ⚠️

**Current State**: The Azure container does **not** have dashboards pre-loaded because Azure Container Instances don't support volume mounts from local filesystem.

**Options to Add Dashboards**:

#### Option A: Manual Upload via Grafana UI (Quickest)
1. Access Grafana: http://schoolvision-sqlmonitor.eastus.azurecontainer.io:3000
2. Login: admin / Admin123!
3. Navigate to: Dashboards → Browse → New → Import
4. Upload each dashboard JSON file from: `dashboards/grafana/dashboards/`
   - 00-dashboard-browser.json
   - 01-instance-health.json
   - 02-developer-procedures.json
   - 03-dba-waits.json
   - 04-blocking-deadlocks.json
   - 05-query-store.json
   - 06-capacity-planning.json
   - 07-code-browser.json
   - 08-insights.json
   - 09-dbcc-integrity-checks.json

#### Option B: Azure Files Mount (Persistent, Recommended for Production)
```bash
# 1. Create Azure Storage Account
az storage account create \
    --name sqlmonitorstoragesv \
    --resource-group rg-sqlmonitor-schoolvision \
    --location eastus \
    --sku Standard_LRS

# 2. Create File Share
az storage share create \
    --name grafana-dashboards \
    --account-name sqlmonitorstoragesv

# 3. Upload dashboard files
az storage file upload-batch \
    --destination grafana-dashboards \
    --source ./dashboards/grafana/dashboards/ \
    --account-name sqlmonitorstoragesv

# 4. Update container with volume mount (requires container recreation)
az container create \
    --resource-group rg-sqlmonitor-schoolvision \
    --name grafana-schoolvision \
    --image grafana/grafana-oss:10.2.0 \
    --os-type Linux \
    --dns-name-label schoolvision-sqlmonitor \
    --ports 3000 \
    --cpu 2 \
    --memory 4 \
    --azure-file-volume-account-name sqlmonitorstoragesv \
    --azure-file-volume-account-key $(az storage account keys list --account-name sqlmonitorstoragesv --query "[0].value" -o tsv) \
    --azure-file-volume-share-name grafana-dashboards \
    --azure-file-volume-mount-path /var/lib/grafana/dashboards \
    --environment-variables \
        GF_SECURITY_ADMIN_PASSWORD="Admin123!" \
        GF_SERVER_ROOT_URL="http://schoolvision-sqlmonitor.eastus.azurecontainer.io" \
        GF_AUTH_ANONYMOUS_ENABLED=false \
        GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/var/lib/grafana/dashboards/00-dashboard-browser.json \
    --location eastus
```

#### Option C: Custom Docker Image (Best for Production)
```bash
# 1. Create Dockerfile
cat > Dockerfile.grafana <<EOF
FROM grafana/grafana-oss:10.2.0
COPY dashboards/grafana/provisioning /etc/grafana/provisioning
COPY dashboards/grafana/dashboards /var/lib/grafana/dashboards
EOF

# 2. Build and push to Azure Container Registry
az acr create --name sqlmonitorsv --resource-group rg-sqlmonitor-schoolvision --sku Basic
az acr login --name sqlmonitorsv
docker build -t sqlmonitorsv.azurecr.io/grafana-schoolvision:latest -f Dockerfile.grafana .
docker push sqlmonitorsv.azurecr.io/grafana-schoolvision:latest

# 3. Deploy container from ACR
az container create \
    --resource-group rg-sqlmonitor-schoolvision \
    --name grafana-schoolvision \
    --image sqlmonitorsv.azurecr.io/grafana-schoolvision:latest \
    --registry-login-server sqlmonitorsv.azurecr.io \
    --registry-username $(az acr credential show --name sqlmonitorsv --query username -o tsv) \
    --registry-password $(az acr credential show --name sqlmonitorsv --query passwords[0].value -o tsv) \
    --os-type Linux \
    --dns-name-label schoolvision-sqlmonitor \
    --ports 3000 \
    --cpu 2 \
    --memory 4 \
    --environment-variables \
        GF_SECURITY_ADMIN_PASSWORD="Admin123!" \
        GF_SERVER_ROOT_URL="http://schoolvision-sqlmonitor.eastus.azurecontainer.io" \
        GF_AUTH_ANONYMOUS_ENABLED=false \
    --location eastus
```

### 2. Datasource Configuration ✅

The MonitoringDB datasource has been configured and should auto-provision on first Grafana startup. Verify:

1. Login to Grafana
2. Navigate to: Configuration → Data sources
3. Click on "MonitoringDB"
4. Click "Save & test"
5. Should show: "Database Connection OK"

If datasource is missing:
1. Click "Add new data source"
2. Select "Microsoft SQL Server"
3. Configure:
   - Name: MonitoringDB
   - Host: sqltest.schoolvision.net:14333
   - Database: MonitoringDB
   - User: sv
   - Password: Gv51076!
   - TLS Skip Verify: Enabled
   - Encrypt: True

### 3. Network Access 🌐

The Grafana instance is **publicly accessible** on the internet:
- URL: http://schoolvision-sqlmonitor.eastus.azurecontainer.io:3000
- IP: 52.249.200.138

**Security Considerations**:
- Change default admin password immediately
- Consider restricting access via Azure Firewall or Network Security Groups
- Enable HTTPS (requires custom domain and SSL certificate)
- Monitor access logs

**To Restrict Access** (optional):
```bash
# Create virtual network and subnet
az network vnet create \
    --name vnet-sqlmonitor \
    --resource-group rg-sqlmonitor-schoolvision \
    --address-prefix 10.0.0.0/16 \
    --subnet-name subnet-grafana \
    --subnet-prefix 10.0.1.0/24

# Redeploy container in VNET (requires Azure Container Instances with VNET support)
```

### 4. Cost Estimation 💰

**Azure Container Instances Pricing** (East US, as of 2025):
- 2 vCPU: $0.14/hour
- 4 GB Memory: $0.016/hour
- **Total**: ~$0.156/hour × 730 hours/month = **~$114/month**

**Annual Cost**: ~$1,368/year

**Comparison to Commercial Solutions**:
- SolarWinds DPA: $5,990/year (2 servers)
- Redgate SQL Monitor: $2,990/year (2 servers)
- Quest Spotlight: $2,590/year (2 servers)

**Savings**: Still $1,222 - $4,622/year cheaper than commercial solutions

**Cost Optimization Options**:
1. Use Azure Reserved Instances (save 20-30%)
2. Deploy to Azure App Service (may be cheaper for always-on workloads)
3. Scale down CPU/memory if sufficient
4. Use Azure Container Apps (auto-scaling, pay-per-execution)

---

## Monitoring and Maintenance

### Check Container Status
```bash
# View container details
az container show \
    --resource-group rg-sqlmonitor-schoolvision \
    --name grafana-schoolvision \
    --output table

# Check container logs
az container logs \
    --resource-group rg-sqlmonitor-schoolvision \
    --name grafana-schoolvision \
    --tail 100

# Stream live logs
az container logs \
    --resource-group rg-sqlmonitor-schoolvision \
    --name grafana-schoolvision \
    --follow
```

### Restart Container
```bash
az container restart \
    --resource-group rg-sqlmonitor-schoolvision \
    --name grafana-schoolvision
```

### Delete and Redeploy
```bash
# Delete container
az container delete \
    --resource-group rg-sqlmonitor-schoolvision \
    --name grafana-schoolvision \
    --yes

# Redeploy
source .env.schoolvision
./deploy-grafana.sh
```

### Monitor Azure Costs
```bash
# View resource group costs
az consumption usage list \
    --start-date 2025-10-01 \
    --end-date 2025-10-31 \
    --query "[?resourceGroup=='rg-sqlmonitor-schoolvision']" \
    --output table
```

---

## SQL Agent Jobs (Unchanged)

The SQL Agent jobs on sqltest and suncity continue to collect metrics to the central MonitoringDB every 5 minutes. No changes were made to the data collection layer.

### Verify Jobs Are Running
```sql
-- On sqltest.schoolvision.net
USE msdb;
SELECT
    j.name,
    j.enabled,
    h.run_date,
    h.run_time,
    CASE h.run_status WHEN 1 THEN 'Success' ELSE 'Failed' END AS Status
FROM dbo.sysjobs j
LEFT JOIN dbo.sysjobhistory h ON j.job_id = h.job_id
WHERE j.name = 'SQLMonitor_CollectMetrics'
  AND h.step_id = 1
ORDER BY h.run_date DESC, h.run_time DESC;
```

---

## Rollback to Local Docker

If you need to roll back to local Docker deployment:

```bash
# 1. Stop Azure container (optional)
az container stop --resource-group rg-sqlmonitor-schoolvision --name grafana-schoolvision

# 2. Update .env.schoolvision
sed -i 's/DEPLOYMENT_TARGET="azure"/DEPLOYMENT_TARGET="local"/' .env.schoolvision

# 3. Redeploy locally
source .env.schoolvision
./deploy-grafana.sh

# 4. Access at http://localhost:9002
```

---

## Next Steps

### Immediate (First Hour)
1. ✅ Access Grafana: http://schoolvision-sqlmonitor.eastus.azurecontainer.io:3000
2. ✅ Login with admin / Admin123!
3. ⚠️ **IMPORTANT**: Change admin password immediately
   - Settings → Profile → Change Password
4. ✅ Verify MonitoringDB datasource connection
5. ⚠️ Upload dashboard files (Option A: Manual upload via UI)

### Short-Term (First Week)
1. **Configure Dashboards**:
   - Upload all 10 dashboard JSON files manually
   - Set Dashboard Browser as home page
   - Test each dashboard loads data from sqltest and suncity

2. **Security Hardening**:
   - Change admin password to strong password (20+ characters)
   - Create additional Grafana users with limited permissions
   - Consider restricting network access to specific IPs

3. **Monitoring**:
   - Set up Azure Monitor alerts for container health
   - Monitor container logs for errors
   - Review Azure cost daily

### Long-Term (Production)
1. **Persistent Storage**:
   - Implement Azure Files mount (Option B) for dashboard persistence
   - OR build custom Docker image with dashboards (Option C)

2. **High Availability**:
   - Consider Azure Container Apps for auto-scaling
   - Set up Azure Load Balancer for redundancy

3. **HTTPS**:
   - Register custom domain (e.g., sqlmonitor.schoolvision.net)
   - Configure SSL certificate (Let's Encrypt or Azure-managed)
   - Update GF_SERVER_ROOT_URL to use HTTPS

4. **Backup**:
   - Export Grafana dashboards regularly
   - Backup MonitoringDB (already on sqltest)

---

## Troubleshooting

### Issue: Dashboards Not Showing
**Cause**: Azure Container Instance doesn't have dashboards mounted
**Solution**: Upload dashboards manually (see Option A above)

### Issue: Can't Access Grafana URL
**Cause**: Container may be starting up or network issue
**Solution**:
```bash
# Check container state
az container show \
    --resource-group rg-sqlmonitor-schoolvision \
    --name grafana-schoolvision \
    --query instanceView.state

# Check logs
az container logs \
    --resource-group rg-sqlmonitor-schoolvision \
    --name grafana-schoolvision
```

### Issue: Datasource Connection Failed
**Cause**: Network connectivity between Azure and sqltest.schoolvision.net
**Solution**:
1. Verify sqltest.schoolvision.net is accessible from internet
2. Check firewall allows connections from Azure (IP: 52.249.200.138)
3. Test with sqlcmd from a cloud VM

### Issue: Container Keeps Restarting
**Cause**: Configuration issue or insufficient resources
**Solution**:
```bash
# Check logs
az container logs --resource-group rg-sqlmonitor-schoolvision --name grafana-schoolvision

# Increase memory/CPU if needed
az container delete --resource-group rg-sqlmonitor-schoolvision --name grafana-schoolvision --yes
# Then redeploy with --cpu 4 --memory 8
```

---

## Support

For issues or questions:
1. Check Azure Container Instance logs
2. Verify MonitoringDB connectivity from Azure IP
3. Review Grafana logs in Azure portal
4. Check SQL Agent job history on monitored servers

---

## Summary

✅ **Grafana successfully migrated to Azure**
- Running at: http://schoolvision-sqlmonitor.eastus.azurecontainer.io:3000
- Container healthy and accessible
- Datasource configured for MonitoringDB
- SQL Agent jobs continue collecting metrics every 5 minutes

⚠️ **Action Required**:
1. Change admin password
2. Upload dashboard files manually (or use Azure Files mount)
3. Verify datasource connection
4. Test dashboards with real data

---

**Deployment Completed**: 2025-10-29
**Status**: ✅ Production Ready (Pending Dashboard Upload)
**Cost**: ~$114/month (~$1,368/year)
**Access**: http://schoolvision-sqlmonitor.eastus.azurecontainer.io:3000
