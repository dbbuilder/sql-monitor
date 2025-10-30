# DNS Configuration Complete - sqlmonitor.servicevision.io

**Date**: October 30, 2025
**Domain**: sqlmonitor.servicevision.io
**Target**: Azure Container Instance (SchoolVision Grafana)

## ✅ Configuration Summary

### DNS Record Created

```
Type:     CNAME
Host:     sqlmonitor
Domain:   servicevision.io
FQDN:     sqlmonitor.servicevision.io
Target:   schoolvision-sqlmonitor.eastus.azurecontainer.io
TTL:      300 seconds (5 minutes)
Record ID: 270970894
```

### Target Service

- **Azure Container Instance**: schoolvision-sqlmonitor
- **Resource Group**: (SchoolVision deployment)
- **Location**: East US
- **IP Address**: 4.156.212.48
- **Service**: Grafana OSS 10.2.0
- **Port**: 3000

## ✅ Verification Results

### DNS Propagation

```bash
# Google DNS (8.8.8.8)
$ dig @8.8.8.8 sqlmonitor.servicevision.io +short
schoolvision-sqlmonitor.eastus.azurecontainer.io.
4.156.212.48

# Cloudflare DNS (1.1.1.1)
$ dig @1.1.1.1 sqlmonitor.servicevision.io +short
schoolvision-sqlmonitor.eastus.azurecontainer.io.
4.156.212.48

# CNAME Record
$ dig sqlmonitor.servicevision.io CNAME +short
schoolvision-sqlmonitor.eastus.azurecontainer.io.
```

**Status**: ✅ DNS propagated successfully to all major DNS servers

### HTTP Connectivity

```bash
# Health Check Endpoint
$ curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://sqlmonitor.servicevision.io:3000/api/health
HTTP Status: 200

# Login Page
$ curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://sqlmonitor.servicevision.io:3000/login
HTTP Status: 200

# Health Check Response
$ curl -s http://sqlmonitor.servicevision.io:3000/api/health
{
  "commit": "895fbafb7a",
  "database": "ok",
  "version": "10.2.0"
}
```

**Status**: ✅ Service accessible and responding correctly

## 🌐 Access Information

### Grafana Dashboard

**URL**: http://sqlmonitor.servicevision.io:3000

**Credentials**:
- Username: `admin`
- Password: (stored in Azure Key Vault / environment variables)

### Available Dashboards

Once logged in, access these dashboards:

1. **SQL Monitor - Home**: http://sqlmonitor.servicevision.io:3000/d/sql-monitor-home/sql-monitor-home
2. **Dashboard Browser**: http://sqlmonitor.servicevision.io:3000/d/dashboard-browser/dashboard-browser
3. **Performance Analysis**: http://sqlmonitor.servicevision.io:3000/d/performance-analysis/performance-analysis
4. **Query Store Analysis**: http://sqlmonitor.servicevision.io:3000/d/query-store-analysis/query-store-performance-analysis
5. **Table Browser**: http://sqlmonitor.servicevision.io:3000/d/sql-monitor-table-browser/sql-monitor-table-browser
6. **Code Browser**: http://sqlmonitor.servicevision.io:3000/d/sql-monitor-code-browser/sql-monitor-code-browser
7. **Insights (24h Priorities)**: http://sqlmonitor.servicevision.io:3000/d/insights-24h/insights-24h-priorities

## 📋 What Was Done

### Step 1: API Authentication
- Verified Name.com API access with TEDTHERRIAULT account
- Confirmed servicevision.io domain ownership

### Step 2: Existing Record Cleanup
- Found existing A record (ID: 270970889) pointing to 24.18.95.234
- Deleted conflicting A record to allow CNAME creation

### Step 3: CNAME Record Creation
- Created CNAME record via Name.com API v4
- Record Type: CNAME (not A record)
- Target: Azure Container Instance FQDN
- TTL: 300 seconds (5 minutes)

### Step 4: DNS Propagation Verification
- Verified propagation to Google DNS (8.8.8.8)
- Verified propagation to Cloudflare DNS (1.1.1.1)
- Confirmed CNAME chain resolution

### Step 5: Service Connectivity Testing
- HTTP health check: 200 OK
- HTTP login page: 200 OK
- Grafana version: 10.2.0 confirmed

## 🔒 Security Considerations

### Current State: HTTP Only

⚠️ **Important**: The service is currently accessible via HTTP only (port 3000), not HTTPS.

**Implications**:
- Data transmitted in clear text
- No encryption for login credentials
- No SSL/TLS certificate

### Recommended: Add SSL/TLS

To enable HTTPS access, choose one of these options:

#### Option 1: Azure Application Gateway (Recommended for Production)

```bash
# Create Application Gateway with SSL termination
az network application-gateway create \
    --name sqlmonitor-appgw \
    --resource-group rg-schoolvision-monitor \
    --location eastus \
    --sku Standard_v2 \
    --public-ip-address appgw-public-ip \
    --frontend-port 443 \
    --http-settings-port 3000 \
    --http-settings-protocol Http \
    --ssl-certificate-data @certificate.pfx \
    --ssl-certificate-password "YourPassword"

# Update DNS to point to Application Gateway IP
# Type: A
# Host: sqlmonitor
# Value: <Application Gateway Public IP>
```

**Cost**: ~$150-200/month
**Benefits**: WAF, DDoS protection, auto-scaling, Azure-managed SSL

#### Option 2: Let's Encrypt with NGINX Reverse Proxy

Deploy an SSL proxy container in front of Grafana:

```bash
# Deploy ssl-proxy container
cd /mnt/d/dev2/sql-monitor/ssl-proxy
./deploy-azure.sh

# Update DNS to point to ssl-proxy IP
# Type: A
# Host: sqlmonitor
# Value: <SSL Proxy Public IP>
```

**Cost**: ~$10-20/month (additional container)
**Benefits**: Free SSL certificate, automatic renewal

#### Option 3: Cloudflare Free SSL (Easiest)

1. Add servicevision.io to Cloudflare (free plan)
2. Change DNS to Cloudflare nameservers
3. Enable SSL/TLS → Full mode
4. Cloudflare provides free SSL termination

**Cost**: $0/month
**Benefits**: Free SSL, DDoS protection, CDN, automatic certificate renewal

## 📊 Name.com API Details

### API Endpoint Used

```
POST https://api.name.com/v4/domains/servicevision.io/records
```

### Request Body

```json
{
  "host": "sqlmonitor",
  "type": "CNAME",
  "answer": "schoolvision-sqlmonitor.eastus.azurecontainer.io",
  "ttl": 300
}
```

### Response

```json
{
  "id": 270970894,
  "domainName": "servicevision.io",
  "host": "sqlmonitor",
  "fqdn": "sqlmonitor.servicevision.io.",
  "type": "CNAME",
  "answer": "schoolvision-sqlmonitor.eastus.azurecontainer.io",
  "ttl": 300
}
```

## 🔧 Management Operations

### View Current DNS Record

```bash
curl -s -u "TEDTHERRIAULT:4790fea6e456f7fe9cf4f61a30f025acd63ecd1c" \
  https://api.name.com/v4/domains/servicevision.io/records \
  | jq '.records[] | select(.host=="sqlmonitor")'
```

### Update DNS Record

```bash
# Update target or TTL
curl -u "TEDTHERRIAULT:4790fea6e456f7fe9cf4f61a30f025acd63ecd1c" \
  -X PUT \
  -H "Content-Type: application/json" \
  -d '{
    "host": "sqlmonitor",
    "type": "CNAME",
    "answer": "new-target.azurecontainer.io",
    "ttl": 300
  }' \
  https://api.name.com/v4/domains/servicevision.io/records/270970894
```

### Delete DNS Record

```bash
curl -u "TEDTHERRIAULT:4790fea6e456f7fe9cf4f61a30f025acd63ecd1c" \
  -X DELETE \
  https://api.name.com/v4/domains/servicevision.io/records/270970894
```

## 📈 Monitoring

### DNS Health Check

```bash
# Check DNS resolution
dig sqlmonitor.servicevision.io

# Check from multiple DNS servers
dig @8.8.8.8 sqlmonitor.servicevision.io +short
dig @1.1.1.1 sqlmonitor.servicevision.io +short
dig @208.67.222.222 sqlmonitor.servicevision.io +short  # OpenDNS

# Check global propagation
# Visit: https://www.whatsmydns.net/#CNAME/sqlmonitor.servicevision.io
```

### Service Health Check

```bash
# Test HTTP connectivity
curl -s http://sqlmonitor.servicevision.io:3000/api/health | jq '.'

# Expected response:
{
  "commit": "895fbafb7a",
  "database": "ok",
  "version": "10.2.0"
}

# Test login page
curl -I http://sqlmonitor.servicevision.io:3000/login
```

### Azure Container Health

```bash
# Check container status
az container show \
  --resource-group rg-schoolvision-monitor \
  --name schoolvision-sqlmonitor \
  --query 'instanceView.state' \
  --output tsv

# View logs
az container logs \
  --resource-group rg-schoolvision-monitor \
  --name schoolvision-sqlmonitor
```

## 🎯 Next Steps

### Immediate (Optional)

1. **Add SSL/TLS**: Choose one of the SSL options above
2. **Set Up Monitoring**: Configure uptime monitoring (e.g., UptimeRobot, Pingdom)
3. **Configure Alerts**: Set up alerts for service downtime

### Medium-Term

1. **Custom Domain for Direct HTTPS**:
   - Deploy Application Gateway or SSL proxy
   - Update DNS to point to gateway/proxy
   - Access via https://sqlmonitor.servicevision.io

2. **Backup DNS**: Configure secondary DNS provider (Cloudflare, Route 53)

3. **CDN**: Add Cloudflare or Azure CDN for global acceleration

### Long-Term

1. **High Availability**: Deploy multiple Grafana instances with load balancer
2. **Disaster Recovery**: Set up automated backups and failover
3. **Security Hardening**: Implement WAF, IP allowlisting, MFA

## 📚 Related Documentation

- **Name.com API Guide**: [deployment/CONFIGURE-DNS-NAMECOM.md](deployment/CONFIGURE-DNS-NAMECOM.md)
- **Azure Deployment Guide**: [deployment/DEPLOY-AZURE.md](deployment/DEPLOY-AZURE.md)
- **SchoolVision Deployment**: [SCHOOLVISION-AZURE-DEPLOYMENT.md](SCHOOLVISION-AZURE-DEPLOYMENT.md)
- **SSL Proxy Setup**: [ssl-proxy/README.md](ssl-proxy/README.md)

## ✅ Summary

**DNS Configuration**: ✅ Complete
**DNS Propagation**: ✅ Confirmed (< 5 minutes)
**Service Accessibility**: ✅ HTTP working (port 3000)
**HTTPS**: ⚠️ Not configured (optional next step)

**Access URL**: http://sqlmonitor.servicevision.io:3000

The DNS is now live and the service is accessible via the custom domain!
