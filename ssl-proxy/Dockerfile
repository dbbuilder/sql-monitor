FROM nginx:alpine

# Install certbot for Let's Encrypt
RUN apk add --no-cache certbot certbot-nginx

# Copy nginx config
COPY nginx.conf /etc/nginx/nginx.conf
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 80 443

ENTRYPOINT ["/entrypoint.sh"]
