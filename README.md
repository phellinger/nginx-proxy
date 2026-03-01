# Nginx Proxy + Let's Encrypt

Single nginx-proxy + Let's Encrypt companion for multiple domains. Other projects run on the same host and join the `app_network` with `VIRTUAL_HOST` / `LETSENCRYPT_HOST` to get HTTPS.

## Architecture

- **nginx-proxy**: one container on 80/443, routes by hostname to containers on `app_network`
- **letsencrypt-companion**: issues and renews certs for containers that set `LETSENCRYPT_HOST`
- **app_network**: external Docker network; create it here, other stacks use `external: true`

## Setup

1. Create network and start proxy:

   ```bash
   chmod +x setup-prod.sh
   ./setup-prod.sh
   ```

2. Deploy other projects that use `app_network` and set `VIRTUAL_HOST` / `VIRTUAL_PORT` / `LETSENCRYPT_HOST` on their services.

## Deploy to server

1. Create `.env.target` (from `.env.target.template`):

   ```bash
   TARGET_HOST=user@your-server
   TARGET_PATH=/path/on/server/nginx-proxy
   ```

2. Deploy and start:
   ```bash
   make deploy
   ```

Requires Docker on the server. First time on server: create `app_network` and nginx dirs (done by `setup-prod.sh`).

## Adding a new backend (from another repo)

Each service must:

- Use network `app_network` with `external: true`
- Set on the container:
  - `VIRTUAL_HOST=your-domain.com`
  - `VIRTUAL_PORT=<internal port>`
  - `LETSENCRYPT_HOST=your-domain.com`

Example (in the other project’s docker-compose):

```yaml
services:
  frontend:
    environment:
      - VIRTUAL_HOST=${FRONTEND_DOMAIN}
      - VIRTUAL_PORT=3123
      - LETSENCRYPT_HOST=${FRONTEND_DOMAIN}
    networks:
      - app_network

networks:
  app_network:
    external: true
```

No restart of nginx-proxy needed when adding or removing backends.

## Commands

- Start: `./setup-prod.sh` or `docker-compose up -d`
- Logs: `docker logs nginx-proxy`, `docker logs letsencrypt-companion`
- Certificates: `docker exec nginx-proxy ls -la /etc/nginx/certs/`
- Config: `docker exec nginx-proxy cat /etc/nginx/conf.d/default.conf`

## Optional: host-mounted Let's Encrypt

Compose mounts `/etc/letsencrypt/live` and `/etc/letsencrypt/archive` read-only so certs obtained on the host (e.g. certbot) can be used. The companion normally writes into the `nginx_certs` volume; use one or the other.
