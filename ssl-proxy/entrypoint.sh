#!/bin/sh
set -e

DOMAIN="${DOMAIN:-monitor.example.com}"
EMAIL="${CERTBOT_EMAIL:-admin@example.com}"
BACKEND_IP="${BACKEND_IP:-4.156.212.48}"

echo "==> Setting up SSL proxy for $DOMAIN"
echo "==> Backend: $BACKEND_IP:3000"
echo "==> Email: $EMAIL"

# Replace placeholders in nginx config
sed -i "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" /etc/nginx/nginx.conf
sed -i "s/BACKEND_IP/$BACKEND_IP/g" /etc/nginx/nginx.conf

# Create webroot directory for certbot
mkdir -p /var/www/certbot

# Check if certificates already exist
if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    echo "==> Certificates not found. Starting nginx temporarily for certbot..."

    # Start nginx in background for HTTP-01 challenge
    nginx -g 'daemon off;' &
    NGINX_PID=$!

    sleep 5

    echo "==> Requesting SSL certificate from Let's Encrypt..."
    certbot certonly --webroot \
        -w /var/www/certbot \
        -d "$DOMAIN" \
        --email "$EMAIL" \
        --agree-tos \
        --non-interactive \
        --staging  # Remove --staging for production

    # Stop temporary nginx
    kill $NGINX_PID
    wait $NGINX_PID 2>/dev/null || true

    echo "==> SSL certificate obtained!"
else
    echo "==> SSL certificates already exist"
fi

# Setup auto-renewal cron (runs twice daily)
echo "0 0,12 * * * certbot renew --quiet && nginx -s reload" | crontab -

# Start nginx in foreground
echo "==> Starting nginx with SSL..."
exec nginx -g 'daemon off;'
