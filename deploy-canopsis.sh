#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# deploy-canopsis.sh — Déploiement Canopsis Community sur Ubuntu (Docker Compose + Hardening)
# Usage: sudo bash deploy-canopsis.sh [--domain <FQDN>] [--install-dir <path>]
###############################################################################

CANOPSIS_VERSION="24.04.0"
INSTALL_DIR="/opt/canopsis"
DOMAIN="$(hostname -f)"
EXPOSE_PORT=8443

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="$2"; shift 2 ;;
    --install-dir) INSTALL_DIR="$2"; shift 2 ;;
    --port) EXPOSE_PORT="$2"; shift 2 ;;
    *) echo "Option inconnue: $1"; exit 1 ;;
  esac
done

# --- Couleurs ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

###############################################################################
# Phase 1 : Pré-requis système
###############################################################################
info "Phase 1 — Vérification des pré-requis"

[[ $EUID -eq 0 ]] || error "Ce script doit être exécuté en tant que root (sudo)"

source /etc/os-release 2>/dev/null || error "Impossible de lire /etc/os-release"
[[ "$ID" == "ubuntu" ]] || error "Ce script est conçu pour Ubuntu (détecté: $ID)"
[[ "$VERSION_ID" == "22.04" || "$VERSION_ID" == "24.04" ]] || warn "Version Ubuntu $VERSION_ID non testée (22.04/24.04 recommandées)"

TOTAL_RAM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
[[ $TOTAL_RAM_MB -ge 3800 ]] || error "RAM insuffisante: ${TOTAL_RAM_MB} Mo (minimum 4 Go)"

AVAIL_DISK_GB=$(df -BG --output=avail "${INSTALL_DIR%/*}" 2>/dev/null | tail -1 | tr -d ' G')
[[ ${AVAIL_DISK_GB:-0} -ge 20 ]] || error "Espace disque insuffisant: ${AVAIL_DISK_GB:-?} Go (minimum 20 Go)"

info "Ubuntu $VERSION_ID — RAM: ${TOTAL_RAM_MB} Mo — Disque libre: ${AVAIL_DISK_GB} Go"

# Docker
if ! command -v docker &>/dev/null; then
  info "Installation de Docker CE..."
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable --now docker
fi

docker compose version &>/dev/null || error "Docker Compose plugin non disponible"
info "Docker $(docker --version | awk '{print $3}') + Compose $(docker compose version --short)"

# Sysctl
info "Configuration sysctl pour MongoDB et performances..."
cat > /etc/sysctl.d/99-canopsis.conf <<'SYSCTL'
vm.max_map_count = 262144
fs.file-max = 65536
net.core.somaxconn = 65535
SYSCTL
sysctl --system --quiet

# Transparent Huge Pages
if [[ -f /sys/kernel/mm/transparent_hugepage/enabled ]]; then
  echo never > /sys/kernel/mm/transparent_hugepage/enabled
  echo never > /sys/kernel/mm/transparent_hugepage/defrag
  cat > /etc/systemd/system/disable-thp.service <<'THP'
[Unit]
Description=Disable Transparent Huge Pages
DefaultDependencies=no
After=sysinit.target local-fs.target
Before=mongod.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled && echo never > /sys/kernel/mm/transparent_hugepage/defrag'

[Install]
WantedBy=basic.target
THP
  systemctl daemon-reload
  systemctl enable disable-thp.service
fi

###############################################################################
# Phase 2 : Génération des secrets
###############################################################################
info "Phase 2 — Génération des secrets"

gen_password() { openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32; }

mkdir -p "$INSTALL_DIR"
chmod 750 "$INSTALL_DIR"

# Mots de passe sans caractères spéciaux pour éviter les problèmes d'URL-encoding
CPS_MONGO_PASSWORD=$(gen_password)
CPS_RABBITMQ_PASSWORD=$(gen_password)
CPS_POSTGRES_PASSWORD=$(gen_password)
CPS_REDIS_PASSWORD=$(gen_password)
MONGO_KEYFILE_KEY=$(openssl rand -base64 756)

cat > "$INSTALL_DIR/.env" <<ENV
# Canopsis Community — Secrets générés le $(date -Iseconds)
CPS_MONGO_PASSWORD=${CPS_MONGO_PASSWORD}
CPS_RABBITMQ_PASSWORD=${CPS_RABBITMQ_PASSWORD}
CPS_POSTGRES_PASSWORD=${CPS_POSTGRES_PASSWORD}
CPS_REDIS_PASSWORD=${CPS_REDIS_PASSWORD}
CANOPSIS_VERSION=${CANOPSIS_VERSION}
DOMAIN=${DOMAIN}
EXPOSE_PORT=${EXPOSE_PORT}
ENV
chmod 600 "$INSTALL_DIR/.env"

# MongoDB keyfile
echo "$MONGO_KEYFILE_KEY" > "$INSTALL_DIR/mongo-keyfile"
chmod 400 "$INSTALL_DIR/mongo-keyfile"
chown 999:999 "$INSTALL_DIR/mongo-keyfile"

###############################################################################
# Phase 3 : Certificat TLS auto-signé
###############################################################################
info "Phase 3 — Génération du certificat TLS auto-signé"

mkdir -p "$INSTALL_DIR/certs"
if [[ ! -f "$INSTALL_DIR/certs/server.crt" ]]; then
  openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
    -keyout "$INSTALL_DIR/certs/server.key" \
    -out "$INSTALL_DIR/certs/server.crt" \
    -subj "/CN=${DOMAIN}" \
    -addext "subjectAltName=DNS:${DOMAIN},DNS:localhost,IP:127.0.0.1" \
    2>/dev/null
  info "Certificat TLS généré pour ${DOMAIN}"
else
  info "Certificat TLS existant conservé"
fi

###############################################################################
# Phase 4 : Configuration Nginx
###############################################################################
info "Phase 4 — Configuration Nginx"

cat > "$INSTALL_DIR/nginx.conf" <<'NGINX'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;
    client_max_body_size 50m;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    upstream canopsis_api {
        server api:8082;
    }

    server {
        listen 443 ssl;
        server_name _;

        ssl_certificate     /etc/nginx/certs/server.crt;
        ssl_certificate_key /etc/nginx/certs/server.key;
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_ciphers         HIGH:!aNULL:!MD5;
        ssl_prefer_server_ciphers on;

        location / {
            proxy_pass http://canopsis_api;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
        }
    }
}
NGINX

###############################################################################
# Phase 5 : MongoDB init script
###############################################################################
cat > "$INSTALL_DIR/mongo-init.js" <<MONGOINIT
rs.initiate({
  _id: "rs0",
  members: [{ _id: 0, host: "mongodb:27017" }]
});

var attempts = 0;
while (!rs.isMaster().ismaster && attempts < 30) {
  sleep(1000);
  attempts++;
}

db.getSiblingDB("admin").createUser({
  user: "cpsmongo",
  pwd: "${CPS_MONGO_PASSWORD}",
  roles: [{ role: "root", db: "admin" }]
});

db.getSiblingDB("canopsis").createUser({
  user: "cpsmongo",
  pwd: "${CPS_MONGO_PASSWORD}",
  roles: [{ role: "dbOwner", db: "canopsis" }]
});
MONGOINIT
chmod 600 "$INSTALL_DIR/mongo-init.js"

###############################################################################
# Phase 6 : PostgreSQL init script
###############################################################################
cat > "$INSTALL_DIR/pg-init.sh" <<PGINIT
#!/bin/bash
set -e
psql -v ON_ERROR_STOP=1 --username "\$POSTGRES_USER" --dbname "\$POSTGRES_DB" <<-EOSQL
  CREATE EXTENSION IF NOT EXISTS timescaledb;
EOSQL
PGINIT
chmod 755 "$INSTALL_DIR/pg-init.sh"

###############################################################################
# Phase 7 : docker-compose.yml
###############################################################################
info "Phase 5 — Génération du docker-compose.yml"

cat > "$INSTALL_DIR/docker-compose.yml" <<COMPOSE
version: "3.8"

x-canopsis-env: &canopsis-env
  CPS_AMQP_URL: "amqp://cpsrabbit:${CPS_RABBITMQ_PASSWORD}@rabbitmq:5672/canopsis"
  CPS_MONGO_URL: "mongodb://cpsmongo:${CPS_MONGO_PASSWORD}@mongodb:27017/canopsis?replicaSet=rs0&authSource=admin"
  CPS_POSTGRES_URL: "postgresql://cpspostgres:${CPS_POSTGRES_PASSWORD}@timescaledb:5432/canopsis"
  CPS_REDIS_URL: "redis://default:${CPS_REDIS_PASSWORD}@redis:6379/0"
  CPS_EDITION: "community"
  CPS_MAX_RETRY: "30"
  CPS_MAX_DELAY: "10"
  CPS_WAIT_FIRST_ATTEMPT: "15"

x-canopsis-base: &canopsis-base
  restart: unless-stopped
  networks:
    - canopsis-net
  environment:
    <<: *canopsis-env
  logging:
    driver: json-file
    options:
      max-size: "50m"
      max-file: "5"

networks:
  canopsis-net:
    driver: bridge

volumes:
  mongodbdata:
  rabbitmqdata:
  timescaledata:
  redisdata:
  uploadfiles:
  uploadicons:

services:
  # ── Infrastructure ──────────────────────────────────────────────────────────

  mongodb:
    image: mongo:7.0
    container_name: canopsis-mongodb
    restart: unless-stopped
    command: ["--replSet", "rs0", "--bind_ip_all", "--keyFile", "/data/keyfile"]
    environment:
      MONGO_INITDB_ROOT_USERNAME: cpsmongo
      MONGO_INITDB_ROOT_PASSWORD: "${CPS_MONGO_PASSWORD}"
    volumes:
      - mongodbdata:/data/db
      - ${INSTALL_DIR}/mongo-keyfile:/data/keyfile:ro
    networks:
      - canopsis-net
    mem_limit: 2g
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')", "-u", "cpsmongo", "-p", "${CPS_MONGO_PASSWORD}", "--authenticationDatabase", "admin", "--quiet"]
      interval: 15s
      timeout: 10s
      retries: 10
      start_period: 30s
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "5"

  mongodb-init:
    image: mongo:7.0
    container_name: canopsis-mongodb-init
    restart: "no"
    depends_on:
      mongodb:
        condition: service_started
    volumes:
      - ${INSTALL_DIR}/mongo-init.js:/docker-entrypoint-initdb.d/init.js:ro
      - ${INSTALL_DIR}/mongo-keyfile:/data/keyfile:ro
    entrypoint: >
      bash -c '
        sleep 10 &&
        mongosh --host mongodb:27017 --eval "
          try { rs.status() } catch(e) { rs.initiate({_id: \"rs0\", members: [{_id: 0, host: \"mongodb:27017\"}]}) }
        " &&
        sleep 5 &&
        mongosh --host mongodb:27017/admin --eval "
          var attempts = 0;
          while (!rs.isMaster().ismaster && attempts < 30) { sleep(1000); attempts++; }
          try {
            db.createUser({user: \"cpsmongo\", pwd: \"${CPS_MONGO_PASSWORD}\", roles: [{role: \"root\", db: \"admin\"}]});
          } catch(e) {
            if (e.codeName !== \"DuplicateKey\") throw e;
          }
          db.getSiblingDB(\"canopsis\");
        "
      '
    networks:
      - canopsis-net

  rabbitmq:
    image: rabbitmq:3.13-management
    container_name: canopsis-rabbitmq
    restart: unless-stopped
    environment:
      RABBITMQ_DEFAULT_USER: cpsrabbit
      RABBITMQ_DEFAULT_PASS: "${CPS_RABBITMQ_PASSWORD}"
      RABBITMQ_DEFAULT_VHOST: canopsis
    volumes:
      - rabbitmqdata:/var/lib/rabbitmq
    networks:
      - canopsis-net
    mem_limit: 1g
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "-q", "ping"]
      interval: 15s
      timeout: 10s
      retries: 10
      start_period: 30s
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "5"

  redis:
    image: redis:7-alpine
    container_name: canopsis-redis
    restart: unless-stopped
    command: ["redis-server", "--requirepass", "${CPS_REDIS_PASSWORD}", "--appendonly", "yes", "--maxmemory", "512mb", "--maxmemory-policy", "allkeys-lru"]
    volumes:
      - redisdata:/data
    networks:
      - canopsis-net
    mem_limit: 768m
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${CPS_REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s
    logging:
      driver: json-file
      options:
        max-size: "20m"
        max-file: "3"

  timescaledb:
    image: timescale/timescaledb:2.14.2-pg16
    container_name: canopsis-timescaledb
    restart: unless-stopped
    environment:
      POSTGRES_USER: cpspostgres
      POSTGRES_PASSWORD: "${CPS_POSTGRES_PASSWORD}"
      POSTGRES_DB: canopsis
    volumes:
      - timescaledata:/var/lib/postgresql/data
      - ${INSTALL_DIR}/pg-init.sh:/docker-entrypoint-initdb.d/init-timescaledb.sh:ro
    networks:
      - canopsis-net
    mem_limit: 1g
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U cpspostgres -d canopsis"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 15s
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "5"

  # ── Canopsis Engines ────────────────────────────────────────────────────────

  reconfigure:
    image: docker.canopsis.net/docker/community/reconfigure:${CANOPSIS_VERSION}
    container_name: canopsis-reconfigure
    restart: "no"
    depends_on:
      mongodb:
        condition: service_healthy
      rabbitmq:
        condition: service_healthy
      redis:
        condition: service_healthy
      timescaledb:
        condition: service_healthy
    environment:
      <<: *canopsis-env
      CPS_EDITION: community
    command: ["-migrate-postgres=true", "-migrate-mongo=true"]
    networks:
      - canopsis-net

  engine-fifo:
    <<: *canopsis-base
    image: docker.canopsis.net/docker/community/engine-fifo:${CANOPSIS_VERSION}
    container_name: canopsis-engine-fifo
    mem_limit: 512m
    depends_on:
      reconfigure:
        condition: service_completed_successfully

  engine-che:
    <<: *canopsis-base
    image: docker.canopsis.net/docker/community/engine-che:${CANOPSIS_VERSION}
    container_name: canopsis-engine-che
    mem_limit: 512m
    depends_on:
      reconfigure:
        condition: service_completed_successfully

  engine-axe:
    <<: *canopsis-base
    image: docker.canopsis.net/docker/community/engine-axe:${CANOPSIS_VERSION}
    container_name: canopsis-engine-axe
    mem_limit: 512m
    depends_on:
      reconfigure:
        condition: service_completed_successfully

  engine-action:
    <<: *canopsis-base
    image: docker.canopsis.net/docker/community/engine-action:${CANOPSIS_VERSION}
    container_name: canopsis-engine-action
    mem_limit: 512m
    depends_on:
      reconfigure:
        condition: service_completed_successfully

  engine-service:
    <<: *canopsis-base
    image: docker.canopsis.net/docker/community/engine-service:${CANOPSIS_VERSION}
    container_name: canopsis-engine-service
    mem_limit: 512m
    depends_on:
      reconfigure:
        condition: service_completed_successfully

  engine-pbehavior:
    <<: *canopsis-base
    image: docker.canopsis.net/docker/community/engine-pbehavior:${CANOPSIS_VERSION}
    container_name: canopsis-engine-pbehavior
    mem_limit: 512m
    depends_on:
      reconfigure:
        condition: service_completed_successfully

  api:
    <<: *canopsis-base
    image: docker.canopsis.net/docker/community/api:${CANOPSIS_VERSION}
    container_name: canopsis-api
    mem_limit: 1g
    volumes:
      - uploadfiles:/opt/canopsis/share/uploads
      - uploadicons:/opt/canopsis/share/icons
    depends_on:
      reconfigure:
        condition: service_completed_successfully
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:8082/api/v4/heartbeat || exit 1"]
      interval: 15s
      timeout: 10s
      retries: 10
      start_period: 60s

  # ── Reverse Proxy ───────────────────────────────────────────────────────────

  nginx:
    image: nginx:1.26-alpine
    container_name: canopsis-nginx
    restart: unless-stopped
    ports:
      - "${EXPOSE_PORT}:443"
    volumes:
      - ${INSTALL_DIR}/nginx.conf:/etc/nginx/nginx.conf:ro
      - ${INSTALL_DIR}/certs/server.crt:/etc/nginx/certs/server.crt:ro
      - ${INSTALL_DIR}/certs/server.key:/etc/nginx/certs/server.key:ro
    networks:
      - canopsis-net
    mem_limit: 256m
    depends_on:
      api:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "curl -kf https://localhost:443/ || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 10s
    logging:
      driver: json-file
      options:
        max-size: "20m"
        max-file: "5"
COMPOSE

###############################################################################
# Phase 8 : Script de backup
###############################################################################
info "Phase 6 — Génération du script de backup"

cat > "$INSTALL_DIR/backup-canopsis.sh" <<'BACKUP'
#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="${INSTALL_DIR}/backups/$(date +%Y%m%d-%H%M%S)"
RETENTION_DAYS="${1:-7}"

source "$INSTALL_DIR/.env"

mkdir -p "$BACKUP_DIR"

echo "[$(date -Iseconds)] Backup MongoDB..."
docker exec canopsis-mongodb mongodump \
  --uri="mongodb://cpsmongo:${CPS_MONGO_PASSWORD}@localhost:27017/canopsis?authSource=admin&replicaSet=rs0" \
  --archive --gzip > "$BACKUP_DIR/mongodb.archive.gz"

echo "[$(date -Iseconds)] Backup PostgreSQL..."
docker exec canopsis-timescaledb pg_dump \
  -U cpspostgres -d canopsis --format=custom \
  > "$BACKUP_DIR/postgresql.dump"

echo "[$(date -Iseconds)] Sauvegarde .env et configs..."
cp "$INSTALL_DIR/.env" "$BACKUP_DIR/env.bak"
cp "$INSTALL_DIR/docker-compose.yml" "$BACKUP_DIR/docker-compose.yml.bak"
cp "$INSTALL_DIR/nginx.conf" "$BACKUP_DIR/nginx.conf.bak"

echo "[$(date -Iseconds)] Nettoyage des backups > ${RETENTION_DAYS} jours..."
find "${INSTALL_DIR}/backups" -maxdepth 1 -type d -mtime +${RETENTION_DAYS} -exec rm -rf {} +

TOTAL=$(du -sh "$BACKUP_DIR" | awk '{print $1}')
echo "[$(date -Iseconds)] Backup terminé: $BACKUP_DIR ($TOTAL)"
BACKUP
chmod 750 "$INSTALL_DIR/backup-canopsis.sh"

###############################################################################
# Phase 9 : Démarrage
###############################################################################
info "Phase 7 — Démarrage de Canopsis"

cd "$INSTALL_DIR"
docker compose pull 2>&1 | tail -5
docker compose up -d

info "Attente du démarrage des services (timeout 5 min)..."
TIMEOUT=300
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
  HEALTHY=$(docker compose ps --format json 2>/dev/null | grep -c '"healthy"' || true)
  TOTAL=$(docker compose ps --format json 2>/dev/null | wc -l || true)
  RUNNING=$(docker compose ps --status running --format json 2>/dev/null | wc -l || true)

  if docker compose ps 2>/dev/null | grep -q "canopsis-nginx" && \
     docker inspect --format='{{.State.Health.Status}}' canopsis-nginx 2>/dev/null | grep -q "healthy"; then
    break
  fi

  sleep 10
  ELAPSED=$((ELAPSED + 10))
  echo -ne "\r  ⏳ ${ELAPSED}s / ${TIMEOUT}s — Services running: ${RUNNING}"
done
echo ""

if [[ $ELAPSED -ge $TIMEOUT ]]; then
  warn "Timeout atteint — certains services peuvent ne pas être prêts"
  docker compose ps
  echo ""
  warn "Consultez les logs: cd $INSTALL_DIR && docker compose logs"
else
  info "Tous les services sont opérationnels"
fi

###############################################################################
# Récapitulatif
###############################################################################
LOCAL_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║           CANOPSIS COMMUNITY — DÉPLOIEMENT TERMINÉ             ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║                                                                ║"
echo "║  Web UI:  https://${LOCAL_IP}:${EXPOSE_PORT}"
echo "║  API:     https://${LOCAL_IP}:${EXPOSE_PORT}/api/v4/"
echo "║                                                                ║"
echo "║  Répertoire:  ${INSTALL_DIR}"
echo "║  Secrets:     ${INSTALL_DIR}/.env"
echo "║  Backup:      ${INSTALL_DIR}/backup-canopsis.sh"
echo "║                                                                ║"
echo "║  Commandes utiles:                                             ║"
echo "║    cd ${INSTALL_DIR}"
echo "║    docker compose ps          # État des services              ║"
echo "║    docker compose logs -f     # Logs en temps réel             ║"
echo "║    docker compose down        # Arrêter                        ║"
echo "║    docker compose up -d       # Redémarrer                     ║"
echo "║    ./backup-canopsis.sh       # Backup (rétention 7j)          ║"
echo "║    ./backup-canopsis.sh 30    # Backup (rétention 30j)         ║"
echo "║                                                                ║"
echo "║  ⚠ Certificat TLS auto-signé. Pour Let's Encrypt:             ║"
echo "║    apt install certbot                                         ║"
echo "║    certbot certonly --standalone -d ${DOMAIN}"
echo "║                                                                ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

docker compose ps
