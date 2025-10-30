# SQL Monitor - Name.com DNS Configuration Guide

Complete guide for configuring DNS for `sqlmonitor.servicevision.io` using the Name.com API.

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [DNS Record Types by Platform](#dns-record-types-by-platform)
- [Configuration Steps](#configuration-steps)
- [Automated Setup Script](#automated-setup-script)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)

## Overview

This guide shows how to configure DNS for your SQL Monitor deployment using Name.com's API. The DNS configuration varies depending on your deployment platform:

- **AWS ECS**: CNAME to Application Load Balancer DNS name
- **Azure Container Instances**: CNAME to Azure-provided FQDN
- **GCP Cloud Run**: CNAME to ghs.googlehosted.com (with domain mapping)
- **On-Premise**: A record to your public IP address

## Prerequisites

### Name.com Account Setup

1. **Name.com API Token** (from account settings):
   - Username: `TEDTHERRIAULT`
   - API Token: `4790fea6e456f7fe9cf4f61a30f025acd63ecd1c`

2. **Domain Ownership**:
   - Verify `servicevision.io` domain is in your Name.com account
   - Confirm you have DNS management permissions

3. **Deployment Target**:
   - AWS: Application Load Balancer DNS name
   - Azure: Container Instance FQDN
   - GCP: Cloud Run service URL or load balancer IP
   - On-Premise: Public IP address and open port 443

### Install Tools

```bash
# Install jq for JSON parsing
brew install jq  # macOS
sudo apt-get install jq  # Linux

# Install curl (usually pre-installed)
curl --version
```

## DNS Record Types by Platform

### AWS ECS Fargate

**DNS Record**: CNAME record pointing to Application Load Balancer

```bash
# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --names sql-monitor-alb \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

echo "ALB DNS: $ALB_DNS"
# Example: sql-monitor-alb-1234567890.us-east-1.elb.amazonaws.com

# Required DNS Record:
# Type: CNAME
# Name: sqlmonitor
# Value: sql-monitor-alb-1234567890.us-east-1.elb.amazonaws.com
# TTL: 300
```

### Azure Container Instances

**DNS Record**: CNAME record pointing to Azure-provided FQDN

```bash
# Get Azure Container Instance FQDN
AZURE_FQDN=$(az container show \
    --resource-group sql-monitor-rg \
    --name sql-monitor-grafana \
    --query 'ipAddress.fqdn' \
    --output tsv)

echo "Azure FQDN: $AZURE_FQDN"
# Example: sqlmonitor.westus2.azurecontainer.io

# Required DNS Record:
# Type: CNAME
# Name: sqlmonitor
# Value: sqlmonitor.westus2.azurecontainer.io
# TTL: 300
```

### GCP Cloud Run

**DNS Record**: CNAME record to ghs.googlehosted.com (Google-managed)

```bash
# Get Cloud Run service URL
SERVICE_URL=$(gcloud run services describe sql-monitor-grafana \
    --region us-central1 \
    --format 'value(status.url)')

echo "Cloud Run URL: $SERVICE_URL"
# Example: https://sql-monitor-grafana-abc123-uc.a.run.app

# Required DNS Records (2 records):
# 1. CNAME for www subdomain:
#    Type: CNAME
#    Name: sqlmonitor
#    Value: ghs.googlehosted.com
#    TTL: 300
#
# 2. Configure domain mapping in GCP:
gcloud run domain-mappings create \
    --service sql-monitor-grafana \
    --domain sqlmonitor.servicevision.io \
    --region us-central1
```

### On-Premise Deployment

**DNS Record**: A record pointing to your public IP address

```bash
# Get your public IP
PUBLIC_IP=$(curl -s ifconfig.me)
echo "Public IP: $PUBLIC_IP"

# Required DNS Record:
# Type: A
# Name: sqlmonitor
# Value: 203.0.113.45 (your public IP)
# TTL: 300

# IMPORTANT: Ensure firewall allows HTTPS (port 443)
sudo ufw allow 443/tcp
```

## Configuration Steps

### Step 1: Set Environment Variables

```bash
# Name.com API credentials
export NAMECOM_USERNAME="TEDTHERRIAULT"
export NAMECOM_TOKEN="4790fea6e456f7fe9cf4f61a30f025acd63ecd1c"
export NAMECOM_DOMAIN="servicevision.io"
export SUBDOMAIN="sqlmonitor"

# Deployment target (choose one):
# For AWS:
export TARGET_TYPE="CNAME"
export TARGET_VALUE="sql-monitor-alb-1234567890.us-east-1.elb.amazonaws.com"

# For Azure:
export TARGET_TYPE="CNAME"
export TARGET_VALUE="sqlmonitor.westus2.azurecontainer.io"

# For GCP:
export TARGET_TYPE="CNAME"
export TARGET_VALUE="ghs.googlehosted.com"

# For On-Premise:
export TARGET_TYPE="A"
export TARGET_VALUE="203.0.113.45"  # Your public IP

export TTL=300  # 5 minutes (use 3600 for production)
```

### Step 2: Test Name.com API Access

```bash
# List all domains in your account
curl -u "${NAMECOM_USERNAME}:${NAMECOM_TOKEN}" \
    https://api.name.com/v4/domains | jq '.'

# Verify servicevision.io is present
curl -u "${NAMECOM_USERNAME}:${NAMECOM_TOKEN}" \
    https://api.name.com/v4/domains/servicevision.io | jq '.'
```

### Step 3: Check Existing DNS Records

```bash
# List current DNS records for servicevision.io
curl -u "${NAMECOM_USERNAME}:${NAMECOM_TOKEN}" \
    https://api.name.com/v4/domains/servicevision.io/records | jq '.'

# Check if sqlmonitor subdomain already exists
curl -u "${NAMECOM_USERNAME}:${NAMECOM_TOKEN}" \
    https://api.name.com/v4/domains/servicevision.io/records \
    | jq '.records[] | select(.host=="sqlmonitor")'
```

### Step 4: Create DNS Record

**Option A: Using curl (Manual)**

```bash
# Create CNAME record (for AWS/Azure/GCP)
curl -u "${NAMECOM_USERNAME}:${NAMECOM_TOKEN}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{
        \"host\": \"${SUBDOMAIN}\",
        \"type\": \"${TARGET_TYPE}\",
        \"answer\": \"${TARGET_VALUE}\",
        \"ttl\": ${TTL}
    }" \
    https://api.name.com/v4/domains/${NAMECOM_DOMAIN}/records

# Create A record (for On-Premise)
curl -u "${NAMECOM_USERNAME}:${NAMECOM_TOKEN}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{
        \"host\": \"${SUBDOMAIN}\",
        \"type\": \"A\",
        \"answer\": \"${TARGET_VALUE}\",
        \"ttl\": ${TTL}
    }" \
    https://api.name.com/v4/domains/${NAMECOM_DOMAIN}/records
```

**Option B: Using Automated Script (Recommended)**

See [Automated Setup Script](#automated-setup-script) section below.

### Step 5: Verify DNS Record Creation

```bash
# List records and find sqlmonitor
curl -u "${NAMECOM_USERNAME}:${NAMECOM_TOKEN}" \
    https://api.name.com/v4/domains/servicevision.io/records \
    | jq '.records[] | select(.host=="sqlmonitor")'

# Expected output:
# {
#   "id": 123456789,
#   "domainName": "servicevision.io",
#   "host": "sqlmonitor",
#   "fqdn": "sqlmonitor.servicevision.io",
#   "type": "CNAME",
#   "answer": "sql-monitor-alb-1234567890.us-east-1.elb.amazonaws.com",
#   "ttl": 300
# }
```

### Step 6: Wait for DNS Propagation

```bash
# DNS propagation can take 5 minutes to 48 hours
# Typical: 5-15 minutes with TTL=300

# Check DNS propagation (run every minute)
watch -n 60 "dig sqlmonitor.servicevision.io +short"

# Check from multiple DNS servers
dig @8.8.8.8 sqlmonitor.servicevision.io +short        # Google DNS
dig @1.1.1.1 sqlmonitor.servicevision.io +short        # Cloudflare DNS
dig @208.67.222.222 sqlmonitor.servicevision.io +short # OpenDNS

# Check DNS propagation globally
curl "https://www.whatsmydns.net/#CNAME/sqlmonitor.servicevision.io"
```

## Automated Setup Script

Complete script to configure DNS for any deployment platform:

```bash
#!/bin/bash
# File: configure-dns-namecom.sh
# Purpose: Automated DNS configuration for SQL Monitor on Name.com

set -e  # Exit on error

# ============================================
# Configuration
# ============================================

NAMECOM_USERNAME="TEDTHERRIAULT"
NAMECOM_TOKEN="4790fea6e456f7fe9cf4f61a30f025acd63ecd1c"
NAMECOM_DOMAIN="servicevision.io"
SUBDOMAIN="sqlmonitor"
FQDN="${SUBDOMAIN}.${NAMECOM_DOMAIN}"

# ============================================
# Function: Detect Deployment Platform
# ============================================

detect_platform() {
    echo "Detecting deployment platform..."

    # Check for AWS
    if command -v aws &> /dev/null; then
        ALB_DNS=$(aws elbv2 describe-load-balancers \
            --names sql-monitor-alb \
            --query 'LoadBalancers[0].DNSName' \
            --output text 2>/dev/null || echo "")

        if [ -n "$ALB_DNS" ] && [ "$ALB_DNS" != "None" ]; then
            echo "✅ Detected AWS ECS deployment"
            TARGET_TYPE="CNAME"
            TARGET_VALUE="$ALB_DNS"
            PLATFORM="AWS"
            return 0
        fi
    fi

    # Check for Azure
    if command -v az &> /dev/null; then
        AZURE_FQDN=$(az container show \
            --resource-group sql-monitor-rg \
            --name sql-monitor-grafana \
            --query 'ipAddress.fqdn' \
            --output tsv 2>/dev/null || echo "")

        if [ -n "$AZURE_FQDN" ] && [ "$AZURE_FQDN" != "None" ]; then
            echo "✅ Detected Azure Container Instances deployment"
            TARGET_TYPE="CNAME"
            TARGET_VALUE="$AZURE_FQDN"
            PLATFORM="Azure"
            return 0
        fi
    fi

    # Check for GCP
    if command -v gcloud &> /dev/null; then
        SERVICE_URL=$(gcloud run services describe sql-monitor-grafana \
            --region us-central1 \
            --format 'value(status.url)' 2>/dev/null || echo "")

        if [ -n "$SERVICE_URL" ]; then
            echo "✅ Detected GCP Cloud Run deployment"
            TARGET_TYPE="CNAME"
            TARGET_VALUE="ghs.googlehosted.com"
            PLATFORM="GCP"
            GCP_SERVICE_URL="$SERVICE_URL"
            return 0
        fi
    fi

    # Default to On-Premise (manual IP entry)
    echo "⚠️  No cloud deployment detected. Using On-Premise mode."
    echo "Enter your public IP address:"
    read -r PUBLIC_IP
    TARGET_TYPE="A"
    TARGET_VALUE="$PUBLIC_IP"
    PLATFORM="On-Premise"
}

# ============================================
# Function: Check Existing DNS Record
# ============================================

check_existing_record() {
    echo ""
    echo "Checking for existing DNS record..."

    EXISTING_RECORD=$(curl -s -u "${NAMECOM_USERNAME}:${NAMECOM_TOKEN}" \
        https://api.name.com/v4/domains/${NAMECOM_DOMAIN}/records \
        | jq -r ".records[] | select(.host==\"${SUBDOMAIN}\")")

    if [ -n "$EXISTING_RECORD" ]; then
        echo "⚠️  Existing DNS record found:"
        echo "$EXISTING_RECORD" | jq '.'

        RECORD_ID=$(echo "$EXISTING_RECORD" | jq -r '.id')

        echo ""
        echo "Do you want to delete and recreate? (y/n)"
        read -r CONFIRM

        if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
            echo "Deleting existing record..."
            curl -s -u "${NAMECOM_USERNAME}:${NAMECOM_TOKEN}" \
                -X DELETE \
                https://api.name.com/v4/domains/${NAMECOM_DOMAIN}/records/${RECORD_ID}
            echo "✅ Deleted existing record"
        else
            echo "❌ Aborted. Existing record unchanged."
            exit 1
        fi
    else
        echo "✅ No existing record found. Proceeding with creation."
    fi
}

# ============================================
# Function: Create DNS Record
# ============================================

create_dns_record() {
    echo ""
    echo "Creating DNS record..."
    echo "  Domain: ${NAMECOM_DOMAIN}"
    echo "  Subdomain: ${SUBDOMAIN}"
    echo "  FQDN: ${FQDN}"
    echo "  Type: ${TARGET_TYPE}"
    echo "  Value: ${TARGET_VALUE}"
    echo "  TTL: 300"
    echo ""

    RESPONSE=$(curl -s -u "${NAMECOM_USERNAME}:${NAMECOM_TOKEN}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{
            \"host\": \"${SUBDOMAIN}\",
            \"type\": \"${TARGET_TYPE}\",
            \"answer\": \"${TARGET_VALUE}\",
            \"ttl\": 300
        }" \
        https://api.name.com/v4/domains/${NAMECOM_DOMAIN}/records)

    # Check for errors
    if echo "$RESPONSE" | jq -e '.message' > /dev/null 2>&1; then
        ERROR_MSG=$(echo "$RESPONSE" | jq -r '.message')
        echo "❌ Error creating DNS record: $ERROR_MSG"
        exit 1
    fi

    echo "✅ DNS record created successfully!"
    echo ""
    echo "$RESPONSE" | jq '.'
}

# ============================================
# Function: Configure GCP Domain Mapping
# ============================================

configure_gcp_domain_mapping() {
    if [ "$PLATFORM" = "GCP" ]; then
        echo ""
        echo "Configuring GCP Cloud Run domain mapping..."

        gcloud run domain-mappings create \
            --service sql-monitor-grafana \
            --domain "${FQDN}" \
            --region us-central1

        echo "✅ GCP domain mapping configured"
        echo "Note: SSL certificate will be provisioned automatically (5-30 minutes)"
    fi
}

# ============================================
# Function: Verify DNS Propagation
# ============================================

verify_dns() {
    echo ""
    echo "Verifying DNS propagation..."
    echo "This may take 5-15 minutes. Checking every 30 seconds..."
    echo ""

    for i in {1..30}; do
        RESULT=$(dig +short "${FQDN}" @8.8.8.8 | head -n 1)

        if [ -n "$RESULT" ]; then
            echo "✅ DNS propagated successfully!"
            echo "   ${FQDN} → ${RESULT}"

            # Test HTTPS connection
            echo ""
            echo "Testing HTTPS connection..."
            sleep 5  # Wait for service to be ready

            HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://${FQDN}/api/health" || echo "000")

            if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
                echo "✅ HTTPS connection successful!"
                echo ""
                echo "========================================="
                echo "DNS Configuration Complete!"
                echo "========================================="
                echo "Grafana URL: https://${FQDN}"
                echo "Username: admin"
                echo "Password: (from secrets/environment)"
                echo "========================================="
            else
                echo "⚠️  DNS propagated but HTTPS connection failed (HTTP $HTTP_CODE)"
                echo "Check firewall rules and SSL certificate status"
            fi

            return 0
        fi

        echo "Attempt $i/30: Waiting for DNS propagation..."
        sleep 30
    done

    echo "⚠️  DNS propagation taking longer than expected"
    echo "Check status at: https://www.whatsmydns.net/#${TARGET_TYPE}/${FQDN}"
}

# ============================================
# Main Execution
# ============================================

echo "========================================="
echo "SQL Monitor - Name.com DNS Configuration"
echo "========================================="
echo ""

# Step 1: Detect platform
detect_platform

# Step 2: Check for existing record
check_existing_record

# Step 3: Create DNS record
create_dns_record

# Step 4: Configure GCP domain mapping (if GCP)
configure_gcp_domain_mapping

# Step 5: Verify DNS propagation
verify_dns

echo ""
echo "✅ DNS configuration complete!"
```

### Running the Script

```bash
# Make script executable
chmod +x configure-dns-namecom.sh

# Run script (auto-detects deployment platform)
./configure-dns-namecom.sh

# Manual mode (specify target)
export TARGET_TYPE="CNAME"
export TARGET_VALUE="your-alb-dns.us-east-1.elb.amazonaws.com"
./configure-dns-namecom.sh
```

## Verification

### Check DNS Resolution

```bash
# Basic DNS lookup
nslookup sqlmonitor.servicevision.io

# Detailed DNS query
dig sqlmonitor.servicevision.io

# Check CNAME chain
dig sqlmonitor.servicevision.io CNAME

# Check A record (for on-premise)
dig sqlmonitor.servicevision.io A

# Test from multiple locations
curl "https://www.whatsmydns.net/#CNAME/sqlmonitor.servicevision.io"
```

### Test HTTPS Access

```bash
# Health check
curl -I https://sqlmonitor.servicevision.io/api/health

# Grafana login page
curl -I https://sqlmonitor.servicevision.io/login

# Full test
curl https://sqlmonitor.servicevision.io/api/health | jq '.'

# Expected response:
# {
#   "status": "Healthy",
#   "database": "Connected",
#   "lastCollection": "2025-10-30T10:30:00Z",
#   "serversMonitored": 20
# }
```

### Verify SSL Certificate

```bash
# Check SSL certificate
openssl s_client -connect sqlmonitor.servicevision.io:443 -servername sqlmonitor.servicevision.io

# Check certificate expiration
echo | openssl s_client -connect sqlmonitor.servicevision.io:443 -servername sqlmonitor.servicevision.io 2>/dev/null | openssl x509 -noout -dates

# Expected:
# notBefore=Oct 30 00:00:00 2025 GMT
# notAfter=Oct 30 23:59:59 2026 GMT
```

## Troubleshooting

### DNS Record Not Resolving

```bash
# Check Name.com API for record
curl -u "${NAMECOM_USERNAME}:${NAMECOM_TOKEN}" \
    https://api.name.com/v4/domains/servicevision.io/records \
    | jq '.records[] | select(.host=="sqlmonitor")'

# If record exists but not resolving:
# 1. Wait 15 minutes for propagation
# 2. Flush local DNS cache:
#    macOS: sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
#    Linux: sudo systemd-resolve --flush-caches
#    Windows: ipconfig /flushdns

# 3. Test with Google DNS directly
dig @8.8.8.8 sqlmonitor.servicevision.io +short
```

### HTTPS Connection Refused

```bash
# Check if port 443 is open
nc -zv sqlmonitor.servicevision.io 443

# For AWS: Check security group
aws ec2 describe-security-groups \
    --group-ids sg-xxxxx \
    --query 'SecurityGroups[0].IpPermissions[?ToPort==`443`]'

# For Azure: Check network security group
az network nsg rule list \
    --resource-group sql-monitor-rg \
    --nsg-name sql-monitor-nsg \
    --query "[?destinationPortRange=='443']"

# For GCP: Check firewall rules
gcloud compute firewall-rules list \
    --filter="allowed[].ports:443"

# For On-Premise: Check firewall
sudo ufw status | grep 443
sudo iptables -L -n | grep 443
```

### SSL Certificate Issues

**Problem**: SSL certificate not provisioned

**AWS Solution**:
```bash
# Request ACM certificate
aws acm request-certificate \
    --domain-name sqlmonitor.servicevision.io \
    --validation-method DNS \
    --region us-east-1

# Get validation CNAME records
aws acm describe-certificate \
    --certificate-arn arn:aws:acm:us-east-1:xxxx:certificate/yyyy \
    --region us-east-1

# Add validation CNAME to Name.com
curl -u "${NAMECOM_USERNAME}:${NAMECOM_TOKEN}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{
        \"host\": \"_validation.sqlmonitor\",
        \"type\": \"CNAME\",
        \"answer\": \"_validation.acm.amazonaws.com\",
        \"ttl\": 300
    }" \
    https://api.name.com/v4/domains/servicevision.io/records
```

**GCP Solution**:
```bash
# Check domain mapping status
gcloud run domain-mappings describe sqlmonitor.servicevision.io \
    --region us-central1

# Certificate status should show "ACTIVE" after 5-30 minutes
# If stuck, delete and recreate:
gcloud run domain-mappings delete sqlmonitor.servicevision.io --region us-central1
gcloud run domain-mappings create --service sql-monitor-grafana --domain sqlmonitor.servicevision.io --region us-central1
```

**Azure Solution**:
```bash
# Azure Container Instances doesn't support custom SSL
# Use Azure Application Gateway with SSL termination
az network application-gateway create \
    --name sql-monitor-appgw \
    --resource-group sql-monitor-rg \
    --location westus2 \
    --sku Standard_v2 \
    --public-ip-address appgw-public-ip \
    --frontend-port 443 \
    --ssl-certificate-data @/path/to/certificate.pfx \
    --ssl-certificate-password "password"
```

**On-Premise Solution (Let's Encrypt)**:
```bash
# Install certbot
sudo apt-get install certbot python3-certbot-nginx

# Request certificate
sudo certbot --nginx -d sqlmonitor.servicevision.io

# Auto-renewal (cron job)
sudo certbot renew --dry-run
```

### Name.com API Errors

**Error**: `401 Unauthorized`
```bash
# Verify credentials
echo "${NAMECOM_USERNAME}:${NAMECOM_TOKEN}"

# Test authentication
curl -u "${NAMECOM_USERNAME}:${NAMECOM_TOKEN}" \
    https://api.name.com/v4/hello

# Expected: {"username":"TEDTHERRIAULT"}
```

**Error**: `403 Forbidden - Domain not found`
```bash
# List all domains in account
curl -u "${NAMECOM_USERNAME}:${NAMECOM_TOKEN}" \
    https://api.name.com/v4/domains | jq '.domains[].domainName'

# Verify servicevision.io is present
```

**Error**: `422 Unprocessable Entity - Invalid DNS record`
```bash
# Common issues:
# 1. CNAME value must end with dot (.)
#    Correct: "sql-monitor-alb-123.elb.amazonaws.com."
#    Wrong: "sql-monitor-alb-123.elb.amazonaws.com"

# 2. A record must be valid IP
#    Correct: "203.0.113.45"
#    Wrong: "203.0.113.45."

# 3. TTL must be >= 300
#    Correct: 300, 3600, 86400
#    Wrong: 60, 120
```

## DNS Record Management

### Update Existing Record

```bash
# Get record ID
RECORD_ID=$(curl -s -u "${NAMECOM_USERNAME}:${NAMECOM_TOKEN}" \
    https://api.name.com/v4/domains/servicevision.io/records \
    | jq -r ".records[] | select(.host==\"sqlmonitor\") | .id")

# Update record
curl -u "${NAMECOM_USERNAME}:${NAMECOM_TOKEN}" \
    -X PUT \
    -H "Content-Type: application/json" \
    -d "{
        \"host\": \"sqlmonitor\",
        \"type\": \"CNAME\",
        \"answer\": \"new-target.example.com\",
        \"ttl\": 300
    }" \
    https://api.name.com/v4/domains/servicevision.io/records/${RECORD_ID}
```

### Delete DNS Record

```bash
# Get record ID
RECORD_ID=$(curl -s -u "${NAMECOM_USERNAME}:${NAMECOM_TOKEN}" \
    https://api.name.com/v4/domains/servicevision.io/records \
    | jq -r ".records[] | select(.host==\"sqlmonitor\") | .id")

# Delete record
curl -u "${NAMECOM_USERNAME}:${NAMECOM_TOKEN}" \
    -X DELETE \
    https://api.name.com/v4/domains/servicevision.io/records/${RECORD_ID}
```

### List All DNS Records

```bash
# List all records
curl -u "${NAMECOM_USERNAME}:${NAMECOM_TOKEN}" \
    https://api.name.com/v4/domains/servicevision.io/records \
    | jq '.records[] | {host: .host, type: .type, answer: .answer, ttl: .ttl}'

# Export to CSV
curl -s -u "${NAMECOM_USERNAME}:${NAMECOM_TOKEN}" \
    https://api.name.com/v4/domains/servicevision.io/records \
    | jq -r '.records[] | [.host, .type, .answer, .ttl] | @csv' \
    > dns-records.csv
```

## Security Best Practices

1. **API Token Security**:
   - Never commit API token to source control
   - Use environment variables or secrets manager
   - Rotate token every 90 days

2. **DNS Security**:
   - Enable DNSSEC on servicevision.io domain
   - Use CAA records to restrict certificate issuance
   - Monitor DNS changes with alerts

3. **SSL/TLS**:
   - Use TLS 1.2 or higher only
   - Enable HSTS (HTTP Strict Transport Security)
   - Configure strong cipher suites

## Next Steps

1. **Configure SSL Certificate** (see platform-specific guides)
2. **Set Up Monitoring** (DNS health checks, SSL expiration alerts)
3. **Enable DNSSEC** (Name.com dashboard → Security settings)
4. **Configure CDN** (optional: CloudFlare, Fastly for global acceleration)
5. **Set Up Backup DNS** (Route 53, CloudFlare as secondary)

## Support

- **Name.com API Documentation**: https://www.name.com/api-docs
- **Name.com Support**: https://www.name.com/support
- **SQL Monitor Issues**: https://github.com/dbbuilder/sql-monitor/issues
