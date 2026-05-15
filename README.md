# Canopsis Community — Automated Deployment Script

One-command deployment of [Canopsis Community Edition](https://www.canopsis.net/) on a fresh Ubuntu server using Docker Compose with production-grade hardening.

## Features

- **Zero-config deployment** — Run one command, get a fully working Canopsis instance
- **Production hardening** — Strong passwords, TLS, minimal port exposure, resource limits
- **Auto-generated secrets** — 32-character random passwords, no defaults
- **TLS out of the box** — Self-signed certificate generated automatically (Let's Encrypt instructions included)
- **Health monitoring** — Healthchecks on all services with dependency ordering
- **Backup included** — Companion script for MongoDB + PostgreSQL dumps with retention policy
- **Log rotation** — JSON log driver with size and file count limits

## Requirements

| Requirement | Minimum |
|---|---|
| OS | Ubuntu 22.04 or 24.04 (x86_64) |
| RAM | 4 GB |
| Disk | 20 GB free |
| Network | Internet access (to pull Docker images) |
| Privileges | Root / sudo |

Docker CE and Docker Compose plugin are **installed automatically** if not present.

## Quick Start

```bash
# Download
git clone <this-repo> && cd canopsis-deploy

# Deploy (as root or with sudo)
sudo bash deploy-canopsis.sh
```

That's it. The script handles everything: prerequisites, Docker, secrets, TLS, configuration, and startup.

## Usage

```bash
sudo bash deploy-canopsis.sh [OPTIONS]

Options:
  --domain <FQDN>       Set the server domain name (default: hostname -f)
  --install-dir <path>  Installation directory (default: /opt/canopsis)
  --port <port>         HTTPS port to expose (default: 8443)
```

### Examples

```bash
# Default deployment on port 8443
sudo bash deploy-canopsis.sh

# Custom domain and standard HTTPS port
sudo bash deploy-canopsis.sh --domain canopsis.example.com --port 443

# Custom install directory
sudo bash deploy-canopsis.sh --install-dir /srv/canopsis
```

## What Gets Deployed

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Ubuntu Host                              │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                Docker Compose Stack                        │   │
│  │                                                           │   │
│  │  ┌─────────┐    ┌──────────────────────────────────┐     │   │
│  │  │  nginx  │───▶│          Canopsis API             │     │   │
│  │  │ :8443   │    │          (port 8082)              │     │   │
│  │  └─────────┘    └──────────────────────────────────┘     │   │
│  │       │                       │                           │   │
│  │       │         ┌─────────────┼─────────────┐             │   │
│  │       │         ▼             ▼             ▼             │   │
│  │       │    ┌─────────┐  ┌─────────┐  ┌──────────┐       │   │
│  │       │    │engine-  │  │engine-  │  │engine-   │       │   │
│  │       │    │  fifo   │  │  che    │  │  axe     │       │   │
│  │       │    └─────────┘  └─────────┘  └──────────┘       │   │
│  │       │    ┌─────────┐  ┌─────────┐  ┌──────────┐       │   │
│  │       │    │engine-  │  │engine-  │  │engine-   │       │   │
│  │       │    │ action  │  │ service │  │pbehavior │       │   │
│  │       │    └─────────┘  └─────────┘  └──────────┘       │   │
│  │       │                                                   │   │
│  │       │    ┌─────────┐  ┌─────────┐  ┌──────────┐       │   │
│  │       └───▶│ MongoDB │  │RabbitMQ │  │  Redis   │       │   │
│  │            │  :27017 │  │  :5672  │  │  :6379   │       │   │
│  │            └─────────┘  └─────────┘  └──────────┘       │   │
│  │                         ┌──────────────┐                  │   │
│  │                         │ TimescaleDB  │                  │   │
│  │                         │    :5432     │                  │   │
│  │                         └──────────────┘                  │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  Exposed: only port 8443 (nginx TLS)                            │
└─────────────────────────────────────────────────────────────────┘
```

### Services

| Service | Image | Purpose |
|---|---|---|
| mongodb | mongo:7.0 | Primary database (replica set) |
| rabbitmq | rabbitmq:3.13-management | AMQP message broker |
| redis | redis:7-alpine | Cache & session store |
| timescaledb | timescale/timescaledb:2.14.2-pg16 | Time-series database |
| reconfigure | canopsis/reconfigure | One-shot DB migrations |
| engine-fifo | canopsis/engine-fifo | Event queue processing |
| engine-che | canopsis/engine-che | Event enrichment |
| engine-axe | canopsis/engine-axe | Alarm management |
| engine-action | canopsis/engine-action | Automated actions |
| engine-service | canopsis/engine-service | Service trees |
| engine-pbehavior | canopsis/engine-pbehavior | Periodic behaviors |
| api | canopsis/api | REST API + Web UI |
| nginx | nginx:1.26-alpine | TLS reverse proxy |

## Security Hardening

| Measure | Details |
|---|---|
| **Passwords** | 32-char random alphanumeric, generated at install time |
| **TLS** | Self-signed RSA-4096 cert; TLS 1.2/1.3 only |
| **Network isolation** | Only nginx (port 8443) exposed; all other services on internal bridge |
| **File permissions** | `.env`: 600, MongoDB keyfile: 400 |
| **Resource limits** | `mem_limit` on every container |
| **Restart policy** | `unless-stopped` on all persistent services |
| **Log rotation** | max 50MB × 5 files per service |
| **Security headers** | X-Frame-Options, X-Content-Type-Options, X-XSS-Protection, Referrer-Policy |
| **MongoDB auth** | Keyfile + user/password authentication enforced |
| **Redis auth** | Password required, maxmemory with eviction policy |

## Post-Deployment

### Access the Web UI

```
https://<server-ip>:8443
```

> Your browser will show a certificate warning (self-signed). This is expected.

### Useful Commands

```bash
cd /opt/canopsis

# Status
docker compose ps

# Logs (follow)
docker compose logs -f

# Logs for specific service
docker compose logs -f engine-axe

# Stop all services
docker compose down

# Restart
docker compose up -d

# Update to new version (edit .env first)
docker compose pull && docker compose up -d
```

### Backup & Restore

```bash
# Run backup (keeps 7 days by default)
/opt/canopsis/backup-canopsis.sh

# Run backup with 30-day retention
/opt/canopsis/backup-canopsis.sh 30

# Schedule daily backup via cron
echo "0 2 * * * root /opt/canopsis/backup-canopsis.sh" > /etc/cron.d/canopsis-backup
```

Backups are stored in `/opt/canopsis/backups/<date>/` and include:
- MongoDB archive (gzipped)
- PostgreSQL custom dump
- Configuration files (.env, docker-compose.yml, nginx.conf)

### TLS with Let's Encrypt

```bash
# Install certbot
apt install -y certbot

# Get certificate (stop nginx first or use DNS challenge)
docker compose stop nginx
certbot certonly --standalone -d your-domain.com
docker compose start nginx

# Replace self-signed cert
cp /etc/letsencrypt/live/your-domain.com/fullchain.pem /opt/canopsis/certs/server.crt
cp /etc/letsencrypt/live/your-domain.com/privkey.pem /opt/canopsis/certs/server.key
docker compose restart nginx
```

## File Structure

```
/opt/canopsis/
├── docker-compose.yml    # Main compose file
├── .env                  # Secrets (chmod 600)
├── nginx.conf            # Nginx configuration
├── mongo-keyfile         # MongoDB replica set auth (chmod 400)
├── mongo-init.js         # MongoDB initialization
├── pg-init.sh            # TimescaleDB extension setup
├── certs/
│   ├── server.crt        # TLS certificate
│   └── server.key        # TLS private key
├── backup-canopsis.sh    # Backup script
└── backups/              # Backup storage
    └── 20260515-020000/
        ├── mongodb.archive.gz
        ├── postgresql.dump
        └── *.bak
```

## Troubleshooting

### Services not starting

```bash
# Check which services are unhealthy
docker compose ps

# Check logs for a specific service
docker compose logs reconfigure
docker compose logs mongodb
```

### MongoDB replica set issues

```bash
# Verify replica set status
docker exec canopsis-mongodb mongosh -u cpsmongo -p "$(grep CPS_MONGO_PASSWORD /opt/canopsis/.env | cut -d= -f2)" --authenticationDatabase admin --eval "rs.status()"
```

### Port already in use

```bash
# Change port
sudo bash deploy-canopsis.sh --port 9443
# Or edit .env and restart
```

### Insufficient resources

The script requires minimum 4 GB RAM. For better performance:
- **8 GB RAM** recommended for production workloads
- **SSD storage** strongly recommended for MongoDB and TimescaleDB
- **4+ CPU cores** for handling multiple engines concurrently

## Upgrading

1. Edit `.env` and change `CANOPSIS_VERSION` to the new version
2. Pull new images: `docker compose pull`
3. Restart: `docker compose up -d`
4. The `reconfigure` service handles migrations automatically

## Uninstall

```bash
cd /opt/canopsis
docker compose down -v   # Stop and remove volumes (DATA LOSS!)
rm -rf /opt/canopsis     # Remove configuration
```

## License

This deployment script is provided as-is under the MIT License.
Canopsis Community Edition is licensed under the [AGPLv3](https://www.gnu.org/licenses/agpl-3.0.html).

## References

- [Canopsis Official Documentation](https://doc.canopsis.net/)
- [Canopsis Community Repository](https://git.canopsis.net/canopsis/canopsis-community)
- [Docker Compose Installation Guide](https://doc.canopsis.net/24.04/guide-administration/installation/installation-conteneurs/)
