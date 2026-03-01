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
