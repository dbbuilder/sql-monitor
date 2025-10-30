# SSL Proxy for Azure Grafana

Nginx reverse proxy with automatic Let's Encrypt SSL certificates.

## Cost: ~$3/month

Azure Container Instance (1 CPU, 1GB RAM) with automatic SSL renewal.

## Quick Setup

### Option 1: Cloudflare (FREE - RECOMMENDED)

1. Sign up at [cloudflare.com](https://cloudflare.com) (free tier)
2. Add your domain to Cloudflare
3. Update nameservers at your domain registrar
4. Add DNS A record: `monitor` → `4.156.212.48`
5. Go to SSL/TLS → Overview → Set to "Full"
6. Done! Access via `https://monitor.yourdomain.com`

**Pros:**
- ✅ $0/month
- ✅ 5-minute setup
- ✅ Auto-renewing SSL
- ✅ DDoS protection included
- ✅ Global CDN

**Cons:**
- Cloudflare→Container connection still HTTP (but encrypted to client)

### Option 2: Nginx SSL Proxy (~$3/month)

Deploy this container for true end-to-end HTTPS.

**Prerequisites:**
- Domain name (e.g., monitor.schoolvision.net)
- Email for Let's Encrypt notifications

**Deploy:**

```bash
cd /mnt/d/dev2/sql-monitor/ssl-proxy

# Set your domain and email
export DOMAIN="monitor.schoolvision.net"
export CERTBOT_EMAIL="admin@schoolvision.net"

# Deploy
./deploy-ssl-proxy.sh
```

**After Deployment:**

1. Get public IP from output
2. Point DNS A record: `monitor.schoolvision.net` → `PUBLIC_IP`
3. Wait 5-10 minutes for SSL certificate
4. Access: `https://monitor.schoolvision.net`

## How It Works

```
Client (HTTPS) → Nginx SSL Proxy (HTTPS) → Grafana Container (HTTP)
                 ↑
                 Let's Encrypt SSL
                 (Auto-renews every 60 days)
```

## Files

- `Dockerfile` - Nginx + Certbot image
- `nginx.conf` - Reverse proxy configuration
- `entrypoint.sh` - SSL certificate automation
- `deploy-ssl-proxy.sh` - Azure deployment script

## Production Notes

**First deployment uses Let's Encrypt STAGING certificates** (for testing).

For production certificates, edit `entrypoint.sh` and remove `--staging`:

```bash
# Before (staging):
certbot certonly --webroot ... --staging

# After (production):
certbot certonly --webroot ...
```

Then redeploy:

```bash
az container delete --resource-group rg-sqlmonitor-schoolvision --name ssl-proxy-grafana --yes
./deploy-ssl-proxy.sh
```

## SSL Features

- ✅ Auto-renewal (checks twice daily)
- ✅ TLS 1.2 + 1.3 only
- ✅ Strong cipher suites
- ✅ HSTS enabled
- ✅ Security headers
- ✅ Rate limiting (10 req/sec)
- ✅ WebSocket support (Grafana Live)

## Cost Breakdown

| Component | Cost |
|-----------|------|
| Azure Container Instance (1 CPU, 1GB) | ~$3/month |
| Let's Encrypt SSL | $0 |
| Data transfer (minimal) | ~$0.50/month |
| **Total** | **~$3.50/month** |

## Troubleshooting

**DNS not resolving:**
```bash
nslookup monitor.yourdomain.com
# Should return the container's public IP
```

**SSL certificate failed:**
```bash
# Check container logs
az container logs --resource-group rg-sqlmonitor-schoolvision --name ssl-proxy-grafana

# Common issues:
# - DNS not pointing to container yet (wait 5-10 min)
# - Port 80 blocked (check Azure NSG)
# - Invalid email address
```

**Force SSL renewal:**
```bash
az container exec \
  --resource-group rg-sqlmonitor-schoolvision \
  --name ssl-proxy-grafana \
  --exec-command "certbot renew --force-renewal && nginx -s reload"
```

## Recommendation

**Use Cloudflare (Option 1)** unless you specifically need end-to-end encryption or want to avoid third-party services.

Cloudflare is:
- Free
- Faster to set up
- More reliable (global network)
- Includes DDoS protection
- Easier to manage
