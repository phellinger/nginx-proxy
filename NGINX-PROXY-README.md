# Nginx Proxy Setup for Multiple Domains

This setup allows you to serve multiple domains using a single nginx-proxy container. The nginx-proxy automatically detects containers with the appropriate environment variables and routes traffic to them based on the requested domain. **No nginx-proxy restarts are needed** when adding new services.

## Architecture Overview

- **Single nginx-proxy container** handles all domains (ports 80/443)
- **letsencrypt-companion** issues and renews Let's Encrypt certs for containers that set `LETSENCRYPT_HOST`
- **Each service** runs on internal Docker network ports
- **Automatic SSL** with Let's Encrypt certificates (no manual certbot for proxy-routed services)
- **Zero downtime** when adding new services
- **No port conflicts** - all services use internal networking

## Initial Setup

### 1. Create the nginx-proxy infrastructure

This repo provides `docker-compose.yml`:

```yaml
version: '3'

services:
  nginx-proxy:
    image: jwilder/nginx-proxy:alpine
    container_name: nginx-proxy
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/tmp/docker.sock:ro
      - ./nginx/vhost.d:/etc/nginx/vhost.d
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./nginx/html:/usr/share/nginx/html
      - /etc/letsencrypt/live:/etc/letsencrypt/live:ro
      - /etc/letsencrypt/archive:/etc/letsencrypt/archive:ro
      - nginx_certs:/etc/nginx/certs:rw
    environment:
      - ENABLE_IPV6=true
    restart: always
    networks:
      - app_network
    healthcheck:
      test: ["CMD-SHELL", "nginx -t && wget -q --spider http://localhost/ || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  letsencrypt-companion:
    image: jrcs/letsencrypt-nginx-proxy-companion:latest
    container_name: letsencrypt-companion
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - nginx_certs:/etc/nginx/certs:rw
    environment:
      - NGINX_PROXY_CONTAINER=nginx-proxy
    restart: always
    networks:
      - app_network
    depends_on:
      - nginx-proxy

volumes:
  nginx_certs:

networks:
  app_network:
    external: true
```

### 2. Create setup script

The repo provides `setup-prod.sh`:

```bash
#!/bin/bash
set -e

# Create Docker network if it doesn't exist
docker network create app_network || true

# Create nginx directories
mkdir -p nginx/vhost.d
mkdir -p nginx/conf.d
mkdir -p nginx/html

# Start nginx-proxy and Let's Encrypt companion
docker-compose up -d

echo "Nginx-proxy and Let's Encrypt companion are running!"
echo "SSL certificates will be automatically generated for services that join app_network with VIRTUAL_HOST and LETSENCRYPT_HOST."
echo "Check logs: docker logs letsencrypt-companion"
```

### 3. Start the nginx-proxy

```bash
chmod +x setup-prod.sh
./setup-prod.sh
```

## Adding New Services (No Restart Required)

### Template for any new service

Create a new `docker-compose.your-service.yml`:

```yaml
version: '3.8'

services:
  your-service:
    image: your-service-image
    container_name: your_service_container
    restart: unless-stopped
    environment:
      - VIRTUAL_HOST=${YOUR_DOMAIN}
      - VIRTUAL_PORT=3542 # Port your service listens on internally
      - LETSENCRYPT_HOST=${YOUR_DOMAIN}
    labels:
      # Optional: Custom nginx config for static files
      - "com.github.jrcs.letsencrypt_nginx_proxy_companion.nginx_proxy.custom_nginx_server_config=location ~ ^/favicon\\.(ico|svg|png)$ { proxy_pass http://your-service:3542; access_log off; log_not_found off; expires max; }"
    networks:
      - app_network
    # Add any volumes, depends_on, etc. as needed

networks:
  app_network:
    external: true
```

### Environment file template

Create `.env.your-service`:

```bash
YOUR_DOMAIN=your-domain.com
# Add any other environment variables your service needs
```

### Start your service

```bash
# Load environment variables (if using .env)
export $(cat .env.your-service | grep -v '^#' | xargs)

# Start your service (SSL is obtained automatically by letsencrypt-companion)
docker-compose -f docker-compose.your-service.yml up -d
```

## Complete Example: Multiple Simple Sites

Here's how to run multiple simple sites on the same machine:

### Service 1: Portfolio Site

`docker-compose.portfolio.yml`:

```yaml
version: '3.8'

services:
  portfolio:
    image: nginx:alpine
    container_name: portfolio_site
    restart: unless-stopped
    environment:
      - VIRTUAL_HOST=portfolio.example.com
      - VIRTUAL_PORT=3542
      - LETSENCRYPT_HOST=portfolio.example.com
    volumes:
      - ./portfolio:/usr/share/nginx/html
    networks:
      - app_network

networks:
  app_network:
    external: true
```

### Service 2: Documentation Site

`docker-compose.docs.yml`:

```yaml
version: '3.8'

services:
  docs:
    image: nginx:alpine
    container_name: docs_site
    restart: unless-stopped
    environment:
      - VIRTUAL_HOST=docs.example.com
      - VIRTUAL_PORT=7777
      - LETSENCRYPT_HOST=docs.example.com
    volumes:
      - ./docs:/usr/share/nginx/html
    networks:
      - app_network

networks:
  app_network:
    external: true
```

### Service 3: Landing Page

`docker-compose.landing.yml`:

```yaml
version: '3.8'

services:
  landing:
    image: nginx:alpine
    container_name: landing_site
    restart: unless-stopped
    environment:
      - VIRTUAL_HOST=landing.example.com
      - VIRTUAL_PORT=9999
      - LETSENCRYPT_HOST=landing.example.com
    volumes:
      - ./landing:/usr/share/nginx/html
    networks:
      - app_network

networks:
  app_network:
    external: true
```

### Service 4: Simple API

`docker-compose.api.yml`:

```yaml
version: '3.8'

services:
  api:
    image: node:alpine
    container_name: simple_api
    restart: unless-stopped
    environment:
      - VIRTUAL_HOST=api.example.com
      - VIRTUAL_PORT=3542
      - LETSENCRYPT_HOST=api.example.com
    volumes:
      - ./api:/app
    working_dir: /app
    command: node server.js
    networks:
      - app_network

networks:
  app_network:
    external: true
```

## Advanced Configuration

### Custom nginx configuration per service

```yaml
labels:
  # Custom server block configuration
  - 'com.github.jrcs.letsencrypt_nginx_proxy_companion.nginx_proxy.custom_nginx_server_config=location /api/ { proxy_pass http://your-service:3542/; }'

  # Custom location block configuration
  - "com.github.jrcs.letsencrypt_nginx_proxy_companion.nginx_proxy.custom_nginx_location_config=location ~* \\.(ico|css|js|gif|jpe?g|png|svg|woff|woff2|ttf|eot)$ { proxy_pass http://your-service:3542; expires max; add_header Cache-Control 'public, max-age=31536000'; }"
```

### Multiple domains for one service

```yaml
environment:
  - VIRTUAL_HOST=example.com,www.example.com
  - VIRTUAL_PORT=3542
  - LETSENCRYPT_HOST=example.com,www.example.com
```

### WebSocket support

```yaml
labels:
  - "com.github.jrcs.letsencrypt_nginx_proxy_companion.nginx_proxy.custom_nginx_server_config=proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection 'upgrade'; proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto $scheme;"
```

## Management Commands

### Start nginx-proxy (one-time setup)

```bash
./setup-prod.sh
```

Or directly:

```bash
docker-compose up -d
```

### Add a new service

```bash
# 1. Create your docker-compose file (in the other project)
# 2. Create your .env file (if needed)
# 3. Start your service — SSL is obtained automatically by letsencrypt-companion
docker-compose -f docker-compose.your-service.yml up -d
```

### Stop a service

```bash
docker-compose -f docker-compose.your-service.yml down
```

### View all running services

```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

### Check nginx-proxy logs

```bash
docker logs nginx-proxy
```

### Check letsencrypt-companion logs

```bash
docker logs letsencrypt-companion
```

## Key Benefits

1. **No port conflicts** - All services use internal Docker networking
2. **No nginx restarts** - Adding services is seamless
3. **Automatic SSL** - Let's Encrypt certificates handled automatically
4. **Scalable** - Add unlimited services on the same machine
5. **Isolated** - Each service can have its own docker-compose file
6. **Zero downtime** - Services can be updated independently

## Troubleshooting

### Check if nginx-proxy is running

```bash
docker ps | grep nginx-proxy
```

### Check nginx configuration

```bash
docker exec nginx-proxy nginx -t
```

### View nginx configuration for a domain

```bash
docker exec nginx-proxy cat /etc/nginx/conf.d/default.conf
```

### Check SSL certificates

```bash
docker exec nginx-proxy ls -la /etc/nginx/certs/
```

Optional: if using host-mounted certs (e.g. certbot), also check:

```bash
sudo ls -la /etc/letsencrypt/live/
```

### Common issues

1. **Service not accessible**: Check that `VIRTUAL_HOST` matches your domain
2. **SSL not working**: Verify certificate exists and nginx-proxy has access
3. **Static files not served**: Check custom nginx configuration labels
4. **Service not starting**: Check internal port matches `VIRTUAL_PORT`

## Best Practices

1. **Use descriptive container names** - Makes debugging easier
2. **Keep services isolated** - One docker-compose file per service
3. **Use environment files** - Keep configuration separate
4. **Monitor logs** - Set up log rotation for nginx-proxy
5. **Backup certificates** - Keep SSL certificates backed up
6. **Use health checks** - Add health checks to your services
