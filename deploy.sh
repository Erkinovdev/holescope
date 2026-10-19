#!/usr/bin/env bash
# Деплой на сервер: ./deploy.sh root@95.217.220.168
# Ставит Docker (если нет), копирует проект и данные, создаёт .env с секретами, поднимает контейнеры (админка+API на порту 80).
set -euo pipefail
HOST="${1:?укажите user@host}"
ssh "$HOST" 'command -v docker >/dev/null || (curl -fsSL https://get.docker.com | sh); mkdir -p /opt/holescope'
tar --exclude=node_modules --exclude=.venv --exclude=.git --exclude=app --exclude=__pycache__ --exclude=releases --exclude=admin-web/dist --exclude=backend/data/uzbekistan.osm.pbf -czf - . | ssh "$HOST" 'tar -xzf - -C /opt/holescope'
ssh "$HOST" 'cd /opt/holescope/backend && [ -f .env ] || cat > .env <<ENV
DJANGO_DEBUG=0
DJANGO_SECRET_KEY=$(openssl rand -hex 32)
PG_PASSWORD=$(openssl rand -hex 16)
WEB_PORT=8000
ADMIN_PORT=80
ENV
docker compose up -d --build && docker compose ps'
