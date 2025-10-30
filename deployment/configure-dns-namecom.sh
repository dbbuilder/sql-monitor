#!/bin/bash
# File: configure-dns-namecom.sh
# Purpose: Automated DNS configuration for SQL Monitor on Name.com
# Usage: ./configure-dns-namecom.sh [--platform aws|azure|gcp|onprem] [--target value]

set -e  # Exit on error

# ============================================
# Configuration
# ============================================

NAMECOM_USERNAME="TEDTHERRIAULT"
NAMECOM_TOKEN="4790fea6e456f7fe9cf4f61a30f025acd63ecd1c"
NAMECOM_DOMAIN="servicevision.io"
SUBDOMAIN="sqlmonitor"
FQDN="${SUBDOMAIN}.${NAMECOM_DOMAIN}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================
# Function: Print colored output
# ============================================

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# ============================================
# Function: Check prerequisites
# ============================================

check_prerequisites() {
    print_info "Checking prerequisites..."

    # Check jq
    if ! command -v jq &> /dev/null; then
        print_error "jq is not installed. Install with:"
        echo "  macOS: brew install jq"
        echo "  Linux: sudo apt-get install jq"
        exit 1
    fi

    # Check curl
    if ! command -v curl &> /dev/null; then
        print_error "curl is not installed"
        exit 1
    fi

    # Check dig
    if ! command -v dig &> /dev/null; then
        print_error "dig is not installed. Install with:"
        echo "  macOS: brew install bind"
        echo "  Linux: sudo apt-get install dnsutils"
        exit 1
    fi

    print_success "All prerequisites satisfied"
}

# ============================================
# Function: Parse command line arguments
# ============================================

parse_arguments() {
    FORCE_PLATFORM=""
    FORCE_TARGET=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --platform)
                FORCE_PLATFORM="$2"
                shift 2
                ;;
            --target)
                FORCE_TARGET="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  --platform <aws|azure|gcp|onprem>  Force specific platform"
                echo "  --target <value>                    Force specific target value"
                echo "  --help                              Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0  # Auto-detect platform"
                echo "  $0 --platform aws --target my-alb.us-east-1.elb.amazonaws.com"
                echo "  $0 --platform onprem --target 203.0.113.45"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# ============================================
# Function: Test Name.com API access
# ============================================

test_api_access() {
    print_info "Testing Name.com API access..."

    RESPONSE=$(curl -s -u "${NAMECOM_USERNAME}:${NAMECOM_TOKEN}" \
        https://api.name.com/v4/hello)

    USERNAME=$(echo "$RESPONSE" | jq -r '.username' 2>/dev/null || echo "")

    if [ "$USERNAME" = "$NAMECOM_USERNAME" ]; then
        print_success "API authentication successful"
    else
        print_error "API authentication failed"
        echo "Response: $RESPONSE"
        exit 1
    fi

    # Verify domain exists
    DOMAIN_CHECK=$(curl -s -u "${NAMECOM_USERNAME}:${NAMECOM_TOKEN}" \
        https://api.name.com/v4/domains/${NAMECOM_DOMAIN})

    if echo "$DOMAIN_CHECK" | jq -e '.domainName' > /dev/null 2>&1; then
        print_success "Domain ${NAMECOM_DOMAIN} found in account"
    else
        print_error "Domain ${NAMECOM_DOMAIN} not found in account"
        exit 1
    fi
}

# ============================================
# Function: Detect Deployment Platform
# ============================================

detect_platform() {
    if [ -n "$FORCE_PLATFORM" ]; then
        print_info "Using forced platform: $FORCE_PLATFORM"
        PLATFORM="$FORCE_PLATFORM"

        if [ -n "$FORCE_TARGET" ]; then
            if [ "$PLATFORM" = "onprem" ]; then
                TARGET_TYPE="A"
            else
                TARGET_TYPE="CNAME"
            fi
            TARGET_VALUE="$FORCE_TARGET"
            return 0
        else
            print_error "When using --platform, you must also specify --target"
            exit 1
        fi
    fi

    print_info "Auto-detecting deployment platform..."

    # Check for AWS
    if command -v aws &> /dev/null; then
        print_info "Checking for AWS ECS deployment..."
        ALB_DNS=$(aws elbv2 describe-load-balancers \
            --names sql-monitor-alb \
            --query 'LoadBalancers[0].DNSName' \
            --output text 2>/dev/null || echo "")

        if [ -n "$ALB_DNS" ] && [ "$ALB_DNS" != "None" ]; then
            print_success "Detected AWS ECS deployment"
            TARGET_TYPE="CNAME"
            TARGET_VALUE="$ALB_DNS"
            PLATFORM="AWS"
            return 0
        fi
    fi

    # Check for Azure
    if command -v az &> /dev/null; then
        print_info "Checking for Azure Container Instances deployment..."
        AZURE_FQDN=$(az container show \
            --resource-group sql-monitor-rg \
            --name sql-monitor-grafana \
            --query 'ipAddress.fqdn' \
            --output tsv 2>/dev/null || echo "")

        if [ -n "$AZURE_FQDN" ] && [ "$AZURE_FQDN" != "None" ]; then
            print_success "Detected Azure Container Instances deployment"
            TARGET_TYPE="CNAME"
            TARGET_VALUE="$AZURE_FQDN"
            PLATFORM="Azure"
            return 0
        fi
    fi

    # Check for GCP
    if command -v gcloud &> /dev/null; then
        print_info "Checking for GCP Cloud Run deployment..."
        SERVICE_URL=$(gcloud run services describe sql-monitor-grafana \
            --region us-central1 \
            --format 'value(status.url)' 2>/dev/null || echo "")

        if [ -n "$SERVICE_URL" ]; then
            print_success "Detected GCP Cloud Run deployment"
            TARGET_TYPE="CNAME"
            TARGET_VALUE="ghs.googlehosted.com"
            PLATFORM="GCP"
            GCP_SERVICE_URL="$SERVICE_URL"
            return 0
        fi
    fi

    # Default to On-Premise (manual IP entry)
    print_warning "No cloud deployment detected"
    print_info "Switching to On-Premise mode"
    echo ""
    echo "Enter your public IP address (or press Enter to detect automatically):"
    read -r PUBLIC_IP

    if [ -z "$PUBLIC_IP" ]; then
        print_info "Detecting public IP..."
        PUBLIC_IP=$(curl -s ifconfig.me)
        print_info "Detected IP: $PUBLIC_IP"
        echo "Use this IP? (y/n)"
        read -r CONFIRM
        if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
            print_error "Aborted by user"
            exit 1
        fi
    fi

    TARGET_TYPE="A"
    TARGET_VALUE="$PUBLIC_IP"
    PLATFORM="On-Premise"
}

# ============================================
# Function: Display configuration summary
# ============================================

display_summary() {
    echo ""
    echo "========================================="
    echo "DNS Configuration Summary"
    echo "========================================="
    echo "Domain:       ${NAMECOM_DOMAIN}"
    echo "Subdomain:    ${SUBDOMAIN}"
    echo "FQDN:         ${FQDN}"
    echo "Platform:     ${PLATFORM}"
    echo "Record Type:  ${TARGET_TYPE}"
    echo "Target Value: ${TARGET_VALUE}"
    echo "TTL:          300 seconds (5 minutes)"
    echo "========================================="
    echo ""
    echo "Proceed with DNS record creation? (y/n)"
    read -r CONFIRM

    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        print_error "Aborted by user"
        exit 1
    fi
}

# ============================================
# Function: Check Existing DNS Record
# ============================================

check_existing_record() {
    print_info "Checking for existing DNS record..."

    EXISTING_RECORD=$(curl -s -u "${NAMECOM_USERNAME}:${NAMECOM_TOKEN}" \
        https://api.name.com/v4/domains/${NAMECOM_DOMAIN}/records \
        | jq -r ".records[] | select(.host==\"${SUBDOMAIN}\")")

    if [ -n "$EXISTING_RECORD" ]; then
        print_warning "Existing DNS record found:"
        echo ""
        echo "$EXISTING_RECORD" | jq '.'
        echo ""

        RECORD_ID=$(echo "$EXISTING_RECORD" | jq -r '.id')
        EXISTING_TYPE=$(echo "$EXISTING_RECORD" | jq -r '.type')
        EXISTING_ANSWER=$(echo "$EXISTING_RECORD" | jq -r '.answer')

        # Check if record is already correct
        if [ "$EXISTING_TYPE" = "$TARGET_TYPE" ] && [ "$EXISTING_ANSWER" = "$TARGET_VALUE" ]; then
            print_success "DNS record already configured correctly!"
            echo ""
            echo "No changes needed. Skipping to verification."
            return 1  # Signal to skip creation
        fi

        echo "Do you want to delete and recreate? (y/n)"
        read -r CONFIRM

        if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
            print_info "Deleting existing record..."
            DELETE_RESPONSE=$(curl -s -u "${NAMECOM_USERNAME}:${NAMECOM_TOKEN}" \
                -X DELETE \
                https://api.name.com/v4/domains/${NAMECOM_DOMAIN}/records/${RECORD_ID})

            print_success "Deleted existing record"
        else
            print_error "Aborted. Existing record unchanged."
            exit 1
        fi
    else
        print_success "No existing record found. Proceeding with creation."
    fi

    return 0  # Signal to proceed with creation
}

# ============================================
# Function: Create DNS Record
# ============================================

create_dns_record() {
    print_info "Creating DNS record..."

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
        print_error "Error creating DNS record: $ERROR_MSG"
        echo ""
        echo "Full response:"
        echo "$RESPONSE" | jq '.'
        exit 1
    fi

    print_success "DNS record created successfully!"
    echo ""
    echo "$RESPONSE" | jq '.'
}

# ============================================
# Function: Configure GCP Domain Mapping
# ============================================

configure_gcp_domain_mapping() {
    if [ "$PLATFORM" = "GCP" ]; then
        echo ""
        print_info "Configuring GCP Cloud Run domain mapping..."

        # Check if domain mapping already exists
        EXISTING_MAPPING=$(gcloud run domain-mappings describe "${FQDN}" \
            --region us-central1 \
            --format json 2>/dev/null || echo "")

        if [ -n "$EXISTING_MAPPING" ]; then
            print_warning "Domain mapping already exists"
            echo "Delete and recreate? (y/n)"
            read -r CONFIRM

            if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
                gcloud run domain-mappings delete "${FQDN}" \
                    --region us-central1 \
                    --quiet
            else
                print_info "Keeping existing domain mapping"
                return 0
            fi
        fi

        gcloud run domain-mappings create \
            --service sql-monitor-grafana \
            --domain "${FQDN}" \
            --region us-central1

        print_success "GCP domain mapping configured"
        print_info "SSL certificate will be provisioned automatically (5-30 minutes)"
    fi
}

# ============================================
# Function: Verify DNS Propagation
# ============================================

verify_dns() {
    echo ""
    print_info "Verifying DNS propagation..."
    print_info "This may take 5-15 minutes. Checking every 30 seconds..."
    echo ""

    for i in {1..30}; do
        # Query Google DNS (8.8.8.8)
        RESULT=$(dig +short "${FQDN}" @8.8.8.8 | grep -v "^;" | head -n 1)

        if [ -n "$RESULT" ]; then
            print_success "DNS propagated successfully!"
            echo "   ${FQDN} → ${RESULT}"
            echo ""

            # Verify record type matches
            if [ "$TARGET_TYPE" = "CNAME" ]; then
                ACTUAL_TYPE=$(dig +short "${FQDN}" CNAME @8.8.8.8 | grep -v "^;")
                if [ -n "$ACTUAL_TYPE" ]; then
                    print_success "CNAME record verified: ${ACTUAL_TYPE}"
                fi
            elif [ "$TARGET_TYPE" = "A" ]; then
                ACTUAL_IP=$(dig +short "${FQDN}" A @8.8.8.8 | grep -v "^;")
                if [ "$ACTUAL_IP" = "$TARGET_VALUE" ]; then
                    print_success "A record verified: ${ACTUAL_IP}"
                fi
            fi

            return 0
        fi

        echo -ne "\rAttempt $i/30: Waiting for DNS propagation..."
        sleep 30
    done

    echo ""
    print_warning "DNS propagation taking longer than expected"
    echo "Check status at: https://www.whatsmydns.net/#${TARGET_TYPE}/${FQDN}"
}

# ============================================
# Function: Test HTTPS Connection
# ============================================

test_https() {
    echo ""
    print_info "Testing HTTPS connection..."
    print_info "Waiting 10 seconds for service to be ready..."
    sleep 10

    # Try health endpoint
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://${FQDN}/api/health" 2>/dev/null || echo "000")

    if [ "$HTTP_CODE" = "200" ]; then
        print_success "HTTPS connection successful! (HTTP $HTTP_CODE)"

        # Try to get health data
        HEALTH_DATA=$(curl -s "https://${FQDN}/api/health" 2>/dev/null || echo "")
        if [ -n "$HEALTH_DATA" ]; then
            echo ""
            echo "Health Check Response:"
            echo "$HEALTH_DATA" | jq '.' 2>/dev/null || echo "$HEALTH_DATA"
        fi

        return 0
    elif [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        print_warning "Received redirect (HTTP $HTTP_CODE)"
        print_info "Service is likely running but redirecting to login page"
        return 0
    elif [ "$HTTP_CODE" = "000" ]; then
        print_warning "HTTPS connection failed (connection refused or timeout)"
        print_info "Possible causes:"
        echo "  1. SSL certificate not yet provisioned (wait 5-30 minutes for GCP/AWS)"
        echo "  2. Firewall blocking port 443"
        echo "  3. Service not running"
        echo "  4. DNS CNAME not fully propagated"
    else
        print_warning "HTTPS connection returned HTTP $HTTP_CODE"
        print_info "Service may be starting up or experiencing issues"
    fi

    # Try HTTP fallback (for on-premise without SSL)
    if [ "$PLATFORM" = "On-Premise" ]; then
        print_info "Trying HTTP connection (port 80)..."
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${FQDN}/api/health" 2>/dev/null || echo "000")

        if [ "$HTTP_CODE" = "200" ]; then
            print_success "HTTP connection successful!"
            print_warning "SSL not configured. Configure Let's Encrypt for HTTPS:"
            echo "  sudo certbot --nginx -d ${FQDN}"
        fi
    fi
}

# ============================================
# Function: Display completion summary
# ============================================

display_completion() {
    echo ""
    echo "========================================="
    echo "DNS Configuration Complete!"
    echo "========================================="
    echo "FQDN:     https://${FQDN}"
    echo "Platform: ${PLATFORM}"
    echo "Status:   DNS propagated"
    echo "========================================="
    echo ""
    echo "Next Steps:"
    echo "  1. Access Grafana: https://${FQDN}"
    echo "  2. Login with credentials from deployment"
    echo "  3. Verify dashboards are loading"
    echo ""

    if [ "$PLATFORM" = "GCP" ]; then
        echo "GCP-Specific:"
        echo "  - SSL certificate provisioning: 5-30 minutes"
        echo "  - Check status: gcloud run domain-mappings describe ${FQDN} --region us-central1"
        echo ""
    fi

    if [ "$PLATFORM" = "On-Premise" ]; then
        echo "On-Premise-Specific:"
        echo "  - Configure SSL with Let's Encrypt:"
        echo "    sudo certbot --nginx -d ${FQDN}"
        echo "  - Ensure port 443 is open in firewall"
        echo ""
    fi

    echo "Troubleshooting:"
    echo "  - Check DNS: dig ${FQDN}"
    echo "  - Check global propagation: https://www.whatsmydns.net/#${TARGET_TYPE}/${FQDN}"
    echo "  - View logs: See platform-specific deployment guide"
    echo "========================================="
}

# ============================================
# Main Execution
# ============================================

echo "========================================="
echo "SQL Monitor - Name.com DNS Configuration"
echo "========================================="
echo ""

# Parse command line arguments
parse_arguments "$@"

# Step 1: Check prerequisites
check_prerequisites

# Step 2: Test API access
test_api_access

# Step 3: Detect platform
detect_platform

# Step 4: Display summary and confirm
display_summary

# Step 5: Check for existing record
if check_existing_record; then
    # Step 6: Create DNS record (only if not already correct)
    create_dns_record
fi

# Step 7: Configure GCP domain mapping (if GCP)
configure_gcp_domain_mapping

# Step 8: Verify DNS propagation
verify_dns

# Step 9: Test HTTPS connection
test_https

# Step 10: Display completion summary
display_completion

print_success "All done!"
