# Canopsis Community — Automated Deployment Script

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Canopsis](https://img.shields.io/badge/Canopsis-Community%20Edition-blue)](https://www.canopsis.net/)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-orange)](https://ubuntu.com/)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED)](https://docs.docker.com/compose/)

One-command deployment of [Canopsis Community Edition](https://www.canopsis.net/) on a fresh Ubuntu server using Docker Compose with production-grade hardening.

---

## Table of Contents

- [About Canopsis](#about-canopsis)
- [Features](#features)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Architecture](#architecture)
- [Canopsis Core Concepts](#canopsis-core-concepts)
- [Event Format](#event-format)
- [API Documentation](#api-documentation)
- [Web UI](#web-ui)
- [Connectors & Integrations](#connectors--integrations)
- [User Management & Authentication](#user-management--authentication)
- [Configuration Reference](#configuration-reference)
- [Security Hardening](#security-hardening)
- [Backup & Restore](#backup--restore)
- [TLS with Let's Encrypt](#tls-with-lets-encrypt)
- [Upgrading](#upgrading)
- [Troubleshooting](#troubleshooting)
- [Community vs Pro Edition](#community-vs-pro-edition)
- [File Structure](#file-structure)
- [Uninstall](#uninstall)
- [References](#references)
- [License](#license)

---

## About Canopsis

[Canopsis](https://www.canopsis.net/) is an open-source **IT hypervision platform** developed by [Capensis](https://www.capensis.fr/). It aggregates events from multiple monitoring sources (Zabbix, Nagios, Centreon, Prometheus, SNMP, etc.) into a single unified platform for centralized alarm management, event correlation, and business-oriented dashboards.

### What Canopsis Does

- **Event Aggregation** — Collects and normalizes events from heterogeneous monitoring tools
- **Alarm Management** — Unified alarm console with acknowledgement, ticketing, and escalation
- **Event Correlation** — Links related events to reduce alert fatigue and identify root causes
- **Service Modeling** — Maps technical components to business services with dependency trees
- **SLA/SLI Monitoring** — Tracks service availability and compliance (Pro edition)
- **Automated Remediation** — Triggers actions based on alarm conditions (Pro edition)
- **Real-time Dashboards** — Customizable views with widgets for operational and business KPIs

### Use Cases

| Use Case | Description |
|----------|-------------|
| **Multi-tool consolidation** | Aggregate Zabbix + Nagios + Centreon into one alarm console |
| **NOC operations** | Real-time service weather for network operations centers |
| **Incident management** | Alarm lifecycle with ack, ticket, and resolution tracking |
| **Business monitoring** | Map infrastructure events to business service impact |
| **Compliance reporting** | SLA calculations with maintenance window exclusions |
| **Alert reduction** | Correlate events to reduce noise by up to 90% |

---

## Features

- **Zero-config deployment** — Run one command on a fresh Ubuntu, get a fully working Canopsis
- **Production hardening** — Strong passwords, TLS, minimal port exposure, resource limits
- **Auto-generated secrets** — 32-character random passwords, no defaults
- **TLS out of the box** — Self-signed certificate generated automatically
- **Health monitoring** — Healthchecks on all services with dependency ordering
- **Backup included** — Companion script for MongoDB + PostgreSQL dumps with retention
- **Log rotation** — JSON log driver with size and file count limits

---

## Requirements

| Requirement | Minimum | Recommended |
|---|---|---|
| **OS** | Ubuntu 22.04 or 24.04 (x86_64) | Ubuntu 24.04 LTS |
| **RAM** | 4 GB | 8 GB |
| **CPU** | 2 cores | 4+ cores |
| **Disk** | 20 GB free | 50 GB SSD |
| **Network** | Internet access (pull images) | Static IP |
| **Privileges** | Root / sudo | — |

> Docker CE and Docker Compose plugin are **installed automatically** if not present.

---

## Quick Start

```bash
# Clone the repository
git clone https://github.com/HicusDanielle/canopsis-deploy.git
cd canopsis-deploy

# Deploy (as root or with sudo)
sudo bash deploy-canopsis.sh
```

The script handles everything: system checks, Docker installation, secrets generation, TLS certificate, service configuration, and startup.

After ~5 minutes, access the Web UI at: `https://<your-server-ip>:8443`

---

## Usage

```bash
sudo bash deploy-canopsis.sh [OPTIONS]

Options:
  --domain <FQDN>       Server domain name for TLS certificate (default: hostname -f)
  --install-dir <path>  Installation directory (default: /opt/canopsis)
  --port <port>         HTTPS port to expose (default: 8443)
```

### Examples

```bash
# Default deployment
sudo bash deploy-canopsis.sh

# Custom domain and standard HTTPS port
sudo bash deploy-canopsis.sh --domain canopsis.example.com --port 443

# Custom install directory
sudo bash deploy-canopsis.sh --install-dir /srv/canopsis
```

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                           Ubuntu Host                                  │
│                                                                        │
│  ┌────────────────────────────────────────────────────────────────┐   │
│  │                    Docker Compose Stack                          │   │
│  │                                                                  │   │
│  │  ┌───────────┐         ┌────────────────────────────────────┐   │   │
│  │  │   nginx   │────────▶│           Canopsis API              │   │   │
│  │  │  :8443    │  TLS    │           (port 8082)               │   │   │
│  │  │  (only    │         │  ┌─────────────────────────────┐   │   │   │
│  │  │  exposed  │         │  │        Web UI (SPA)          │   │   │   │
│  │  │  port)    │         │  └─────────────────────────────┘   │   │   │
│  │  └───────────┘         └────────────────────────────────────┘   │   │
│  │                                      │                           │   │
│  │          ┌───────────────────────────┼───────────────────┐      │   │
│  │          │        Event Processing Pipeline              │      │   │
│  │          │                                               │      │   │
│  │          │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────────┐ │      │   │
│  │          │  │ FIFO │─▶│ CHE  │─▶│ AXE  │─▶│  ACTION  │ │      │   │
│  │          │  └──────┘  └──────┘  └──────┘  └──────────┘ │      │   │
│  │          │  ┌──────────┐  ┌───────────┐                  │      │   │
│  │          │  │ SERVICE  │  │ PBEHAVIOR │                  │      │   │
│  │          │  └──────────┘  └───────────┘                  │      │   │
│  │          └───────────────────────────────────────────────┘      │   │
│  │                         │         │         │                    │   │
│  │          ┌──────────────┼─────────┼─────────┼──────────────┐    │   │
│  │          │         Infrastructure Services                  │    │   │
│  │          │                                                  │    │   │
│  │          │  ┌─────────┐  ┌──────────┐  ┌───────────────┐  │    │   │
│  │          │  │MongoDB  │  │ RabbitMQ │  │ TimescaleDB   │  │    │   │
│  │          │  │ 7.0     │  │  3.13    │  │ 2.14/PG16    │  │    │   │
│  │          │  │(replica)│  │  (AMQP)  │  │ (time-series)│  │    │   │
│  │          │  └─────────┘  └──────────┘  └───────────────┘  │    │   │
│  │          │  ┌─────────┐                                    │    │   │
│  │          │  │  Redis  │  All on internal bridge network    │    │   │
│  │          │  │   7     │  (not exposed to host)             │    │   │
│  │          │  └─────────┘                                    │    │   │
│  │          └─────────────────────────────────────────────────┘    │   │
│  └────────────────────────────────────────────────────────────────┘   │
│                                                                        │
│  Only port 8443 exposed to the network (nginx TLS termination)        │
└──────────────────────────────────────────────────────────────────────┘
```

### Services Deployed

| Service | Image | Role | Memory Limit |
|---|---|---|---|
| mongodb | `mongo:7.0` | Primary database (replica set mode) | 2 GB |
| rabbitmq | `rabbitmq:3.13-management` | AMQP message broker | 1 GB |
| redis | `redis:7-alpine` | Cache & session store | 768 MB |
| timescaledb | `timescale/timescaledb:2.14.2-pg16` | Time-series database | 1 GB |
| reconfigure | `canopsis/reconfigure` | DB migrations (one-shot) | — |
| engine-fifo | `canopsis/engine-fifo` | Event queue ingestion | 512 MB |
| engine-che | `canopsis/engine-che` | Context-graph & enrichment | 512 MB |
| engine-axe | `canopsis/engine-axe` | Alarm engine | 512 MB |
| engine-action | `canopsis/engine-action` | Action execution | 512 MB |
| engine-service | `canopsis/engine-service` | Service dependency trees | 512 MB |
| engine-pbehavior | `canopsis/engine-pbehavior` | Maintenance windows | 512 MB |
| api | `canopsis/api` | REST API + Web UI | 1 GB |
| nginx | `nginx:1.26-alpine` | TLS reverse proxy | 256 MB |

---

## Canopsis Core Concepts

### Entities

Entities represent monitored objects in the IT infrastructure. Each entity has:
- **Component** — The system or application (e.g., `webserver-01`, `database-prod`)
- **Resource** — A specific metric or service on that component (e.g., `cpu_load`, `disk_usage`)
- **Connector** — The source that reports events (e.g., `zabbix`, `nagios`, `snmp`)

Entity types: `connector`, `component`, `resource`, `service`

### Alarms

An alarm is created when an entity transitions to a non-OK state. Alarm lifecycle:

```
Event received → Alarm created (state > 0)
                       │
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
   Acknowledged    Ticketed      Auto-resolved
        │              │              │
        └──────────────┼──────────────┘
                       ▼
                   Resolved
                       │
                       ▼
                   Closed/Archived
```

Alarm states:
| State | Value | Meaning |
|---|---|---|
| OK | 0 | Service operating normally |
| Minor | 1 | Warning condition |
| Major | 2 | Critical condition |
| Critical | 3 | Unknown/unreachable |

### Event Processing Pipeline

Events flow through Canopsis engines in sequence:

1. **FIFO** — Receives events from RabbitMQ, orders them chronologically
2. **CHE** (Context-graph Handler Engine) — Enriches events, manages entity context
3. **AXE** (Alarm eXecution Engine) — Creates/updates/resolves alarms
4. **ACTION** — Executes automated actions (webhooks, scripts)
5. **SERVICE** — Updates service dependency trees
6. **PBEHAVIOR** — Applies maintenance windows and periodic behaviors

### PBehaviors (Periodic Behaviors)

PBehaviors define time periods when monitoring behavior changes:
- **Maintenance** — Suppress alarms during planned work
- **Pause** — Temporarily stop monitoring
- **Active/Inactive** — Business hours scheduling

PBehaviors exclude their time windows from SLA calculations.

### Watchers & Services

- **Watchers** monitor groups of entities and aggregate their states
- **Services** model business services as dependency trees of entities
- State propagation: worst-state-wins (a critical child = critical service)

---

## Event Format

Canopsis processes events as JSON messages. Events are submitted via AMQP (RabbitMQ) or HTTP API.

### Event Structure

```json
{
  "event_type": "check",
  "source_type": "resource",
  "connector": "monitoring-tool",
  "connector_name": "instance-name",
  "component": "server-hostname",
  "resource": "service-or-metric",
  "state": 2,
  "output": "CPU usage at 95%",
  "long_output": "Process 'java' consuming 90% CPU for 15 minutes",
  "timestamp": 1715731200
}
```

### Field Reference

| Field | Type | Required | Description |
|---|---|---|---|
| `event_type` | string | Yes | Event category: `check`, `ack`, `cancel`, `comment`, `changestate` |
| `source_type` | string | Yes | `"component"` or `"resource"` |
| `connector` | string | Yes | Connector type (e.g., `zabbix`, `nagios`, `prometheus`) |
| `connector_name` | string | Yes | Connector instance identifier |
| `component` | string | Yes | Component/host name |
| `resource` | string | Conditional | Resource name (required if source_type = "resource") |
| `state` | int | Yes | Severity: 0=OK, 1=Minor, 2=Major, 3=Critical |
| `output` | string | No | Short description of the event |
| `long_output` | string | No | Extended diagnostic information |
| `timestamp` | int | No | Unix epoch (defaults to current time) |
| `author` | string | No | User who triggered the action |

### Event Types

| Type | Purpose | Example |
|---|---|---|
| `check` | State change report | Monitoring check result |
| `ack` | Acknowledge alarm | Operator acknowledged an issue |
| `ackremove` | Remove acknowledgement | Cancel previous ack |
| `cancel` | Cancel alarm | False positive |
| `uncancel` | Restore cancelled alarm | Undo cancel |
| `comment` | Add comment to alarm | Operator note |
| `changestate` | Force state change | Manual override |
| `resolve` | Force resolve alarm | Manual resolution |

### AMQP Routing

Events published to RabbitMQ use topic exchange routing:

- **Exchange:** `canopsis.events` (type: topic, durable)
- **Vhost:** `canopsis`
- **Routing key pattern:** `<connector>.<connector_name>.<event_type>.<source_type>.<component>[.<resource>]`

Example: `zabbix.zabbix-prod.check.resource.webserver01.cpu_load`

### Submitting Events via API

```bash
# Using curl
curl -k -X POST https://localhost:8443/api/v4/event \
  -H "x-canopsis-authkey: YOUR_AUTH_KEY" \
  -H "Content-Type: application/json" \
  -d '[{
    "event_type": "check",
    "source_type": "resource",
    "connector": "custom",
    "connector_name": "my-script",
    "component": "app-server-01",
    "resource": "api_health",
    "state": 0,
    "output": "API responding in 150ms"
  }]'
```

---

## API Documentation

Canopsis provides a REST API (v4) for programmatic access to all platform features.

### Base URL

```
https://<canopsis-host>:<port>/api/v4/
```

### Authentication

All API calls require authentication via the `x-canopsis-authkey` header:

```bash
curl -k -H "x-canopsis-authkey: <your-auth-key>" https://localhost:8443/api/v4/alarms
```

To obtain an auth key: Log into the Web UI → Administration → Rights → Select user → Copy API key.

### Swagger / OpenAPI

Interactive API documentation is available at:
- **Community:** `https://<host>:<port>/swagger/index.html`

### Key Endpoints

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/api/v4/alarms` | List alarms with filters |
| `GET` | `/api/v4/alarms/:id` | Get specific alarm details |
| `PUT` | `/api/v4/alarms/:id/ack` | Acknowledge an alarm |
| `PUT` | `/api/v4/alarms/:id/cancel` | Cancel an alarm |
| `PUT` | `/api/v4/alarms/:id/changestate` | Change alarm state |
| `POST` | `/api/v4/event` | Submit events (array of events) |
| `GET` | `/api/v4/entities` | List entities |
| `GET` | `/api/v4/entityservices` | List service entities |
| `GET` | `/api/v4/pbehaviors` | List PBehaviors |
| `POST` | `/api/v4/pbehaviors` | Create PBehavior |
| `GET` | `/api/v4/heartbeat` | API health check |
| `GET` | `/api/v4/views` | List views/dashboards |
| `GET` | `/api/v4/roles` | List roles |

### Alarm Filtering

```bash
# Get all active critical alarms
curl -k -H "x-canopsis-authkey: KEY" \
  "https://localhost:8443/api/v4/alarms?search=%7B%22v.state.val%22:3%7D"

# Get alarms for a specific component
curl -k -H "x-canopsis-authkey: KEY" \
  "https://localhost:8443/api/v4/alarms?search=%7B%22v.component%22:%22webserver-01%22%7D"
```

---

## Web UI

Canopsis Web UI is a single-page application served by the API service.

### Available Widgets

| Widget | Description |
|---|---|
| **Alarm List** | Real-time alarm table with filters, ack, and bulk actions |
| **Service Weather** | Color-coded grid showing service health at a glance |
| **Context Explorer** | Browse and search monitored entities |
| **Statistics** | Charts and counters for alarm metrics |
| **Text** | Static or dynamic text/markdown content |
| **Counter** | Numeric alarm counters with thresholds |
| **Map** | Geographic or logical topology maps |

### Key UI Features

- **Custom Views** — Create personalized dashboards with drag-and-drop widgets
- **Alarm Filters** — Column-level rapid filtering with boolean AND/OR logic
- **Bulk Operations** — Acknowledge, ticket, or resolve multiple alarms at once
- **PBehavior Calendar** — Visual calendar for scheduling maintenance windows
- **Entity Explorer** — Browse entity context, metadata, and relationships
- **Alarm Timeline** — Full history of alarm state changes and operator actions
- **Role-based Views** — Different dashboards for different user roles

### Default Login

After deployment, the default admin credentials are configured during the `reconfigure` phase. Check the Canopsis documentation for the initial setup wizard.

---

## Connectors & Integrations

Canopsis connects to existing monitoring tools via connectors that translate native events into Canopsis format.

### Official Connectors

| Source | Method | Direction | Edition |
|---|---|---|---|
| **Zabbix** | Webhook (Media Type) | Zabbix → Canopsis | Community |
| **Nagios / Icinga** | NEB module (neb2canopsis) | Nagios → Canopsis | Community |
| **Centreon** | Stream Connector (Lua) | Centreon → Canopsis | Community |
| **SNMP Traps** | Native engine (UDP 162) | Devices → Canopsis | **Pro only** |
| **Prometheus** | AlertManager webhook | Prometheus → Canopsis | Community |
| **LibreNMS** | HTTP Transport | LibreNMS → Canopsis | Community |
| **Grafana** | Notification channel (webhook) | Grafana → Canopsis | Community |
| **Email (outbound)** | SMTP via webhooks | Canopsis → Email | Community |
| **Custom / Generic** | HTTP POST to /api/v4/event | Any → Canopsis | Community |

### Zabbix Integration

1. Import the webhook media type (XML for Zabbix 5.x, YAML for 6.x–7.x)
2. Configure parameters:
   - `canopsis_url`: `https://canopsis-server:8443`
   - `canopsis_user`: API user
   - `canopsis_password`: API password or auth key
   - `connector_name`: Unique identifier (e.g., `zabbix-prod`)
3. Create an alert action using the Canopsis media type
4. Map Zabbix severities to Canopsis states

### Nagios / Icinga Integration

1. Install the `neb2canopsis` broker module
2. Configure AMQP connection to Canopsis RabbitMQ
3. Events are sent directly via AMQP (low latency)

### Centreon Integration

1. Install the Canopsis Stream Connector (Lua script)
2. Configure the output in Centreon Broker:
   - HTTP URL: `https://canopsis-server:8443/api/v4/event`
   - Authentication: auth key header
3. Filter which hosts/services to forward

### Prometheus / AlertManager Integration

1. Add Canopsis as a webhook receiver in AlertManager config:
   ```yaml
   receivers:
     - name: canopsis
       webhook_configs:
         - url: 'https://canopsis-server:8443/api/v4/event'
           http_config:
             headers:
               x-canopsis-authkey: YOUR_KEY
   ```
2. Map AlertManager labels to Canopsis event fields

### Custom Integration (Any Source)

Any system that can make HTTP POST requests can send events:

```bash
curl -k -X POST https://canopsis:8443/api/v4/event \
  -H "x-canopsis-authkey: KEY" \
  -H "Content-Type: application/json" \
  -d '[{
    "event_type": "check",
    "source_type": "resource",
    "connector": "custom",
    "connector_name": "my-app",
    "component": "payment-service",
    "resource": "transaction_rate",
    "state": 1,
    "output": "Transaction rate below threshold: 50/min (expected: 200/min)"
  }]'
```

---

## User Management & Authentication

### Authentication Methods

| Method | Description | Configuration |
|---|---|---|
| **Local** | Username/password in Canopsis DB | Default, built-in |
| **API Key** | Persistent token per user | Administration → Users → API key |
| **LDAP** | Directory service authentication | `canopsis.toml` [ldap] section |
| **SSO / OIDC** | External identity provider | `canopsis.toml` [auth] section |
| **SAML** | Enterprise SSO federation | Available in some versions |

### Role-Based Access Control (RBAC)

Canopsis uses RBAC to control access:

- **Roles** define permission sets (admin, operator, viewer, etc.)
- **Permissions** are granular (per-API, per-view, per-action)
- **Users** are assigned one or more roles
- **Views** can be restricted to specific roles

### Managing Users

Via Web UI: Administration → Users
Via API:
```bash
# List users
curl -k -H "x-canopsis-authkey: KEY" https://localhost:8443/api/v4/users

# Create user
curl -k -X POST -H "x-canopsis-authkey: KEY" \
  -H "Content-Type: application/json" \
  https://localhost:8443/api/v4/users \
  -d '{"_id": "operator1", "name": "Operator One", "role": "operator", "password": "<CHANGE_ME_STRONG_PASSWORD>"}'
```

---

## Configuration Reference

### Environment Variables

| Variable | Purpose | Default |
|---|---|---|
| `CPS_AMQP_URL` | RabbitMQ connection URI | — |
| `CPS_MONGO_URL` | MongoDB connection URI (with replicaSet) | — |
| `CPS_POSTGRES_URL` | PostgreSQL/TimescaleDB URI | — |
| `CPS_REDIS_URL` | Redis connection URI | — |
| `CPS_EDITION` | Edition: `community` or `pro` | `community` |
| `CPS_MAX_RETRY` | Max connection retry attempts | `10` |
| `CPS_MAX_DELAY` | Max delay between retries (seconds) | `30` |
| `CPS_WAIT_FIRST_ATTEMPT` | Wait before first connection (seconds) | `10` |
| `CPS_LOGGING_LEVEL` | Log verbosity: `debug`, `info`, `warning` | `info` |
| `HTTP_PROXY` | HTTP proxy URL | — |
| `HTTPS_PROXY` | HTTPS proxy URL | — |

### Configuration Files

| File | Purpose |
|---|---|
| `canopsis.toml` | Main application configuration |
| `canopsis-override.toml` | Custom overrides (survives updates) |
| `go-engines-vars.conf` | Engine environment variables (package install) |
| `compose.env` / `.env` | Docker Compose environment |

### Key canopsis.toml Sections

```toml
[api]
  host = "0.0.0.0"
  port = 8082

[auth]
  # Authentication configuration (local, LDAP, SSO)

[engines.event_filter]
  # Event processing rules

[engines.remediation]
  # Automated action configuration

[storage]
  # Data retention policies
```

---

## Security Hardening

This deployment script applies the following security measures:

| Measure | Implementation |
|---|---|
| **Strong passwords** | 32-char alphanumeric random generation (no special chars to avoid URL-encoding issues) |
| **TLS termination** | RSA-4096 self-signed certificate; TLS 1.2/1.3 only; strong ciphers |
| **Network isolation** | Only nginx port exposed; all services on internal Docker bridge |
| **File permissions** | `.env`: 600 (root only), MongoDB keyfile: 400 |
| **MongoDB auth** | Keyfile replica set authentication + user/password |
| **Redis auth** | Password required; maxmemory with eviction policy |
| **Resource limits** | `mem_limit` on every container prevents runaway consumption |
| **Restart policy** | `unless-stopped` ensures services recover from crashes |
| **Log rotation** | JSON driver: max 50 MB × 5 files per service |
| **Security headers** | X-Frame-Options, X-Content-Type-Options, X-XSS-Protection, Referrer-Policy |
| **No default creds** | All passwords generated at install time, never reused |
| **Healthchecks** | Every service monitored; unhealthy containers auto-restart |

### Additional Recommendations

- [ ] Replace self-signed cert with Let's Encrypt (see below)
- [ ] Set up a firewall (ufw) allowing only port 8443 and SSH
- [ ] Enable Docker content trust: `export DOCKER_CONTENT_TRUST=1`
- [ ] Schedule regular backups via cron
- [ ] Monitor disk usage (MongoDB and TimescaleDB grow over time)
- [ ] Set up log forwarding to a SIEM

---

## Backup & Restore

### Run Backup

```bash
# Default: 7-day retention
/opt/canopsis/backup-canopsis.sh

# Custom retention (30 days)
/opt/canopsis/backup-canopsis.sh 30
```

### Schedule Automated Backups

```bash
# Daily at 2 AM
echo "0 2 * * * root /opt/canopsis/backup-canopsis.sh" > /etc/cron.d/canopsis-backup
chmod 644 /etc/cron.d/canopsis-backup
```

### Backup Contents

Each backup creates a timestamped directory:
```
/opt/canopsis/backups/20260515-020000/
├── mongodb.archive.gz     # Full MongoDB dump (gzipped)
├── postgresql.dump        # PostgreSQL custom format dump
├── env.bak               # .env configuration
├── docker-compose.yml.bak # Compose file
└── nginx.conf.bak        # Nginx configuration
```

### Restore

```bash
# Stop services
cd /opt/canopsis && docker compose down

# Restore MongoDB
docker run --rm -v canopsis_mongodbdata:/data/db \
  -v /opt/canopsis/backups/20260515-020000:/backup \
  mongo:7.0 mongorestore --archive=/backup/mongodb.archive.gz --gzip

# Restore PostgreSQL
docker run --rm -v canopsis_timescaledata:/var/lib/postgresql/data \
  -v /opt/canopsis/backups/20260515-020000:/backup \
  timescale/timescaledb:2.14.2-pg16 pg_restore -U cpspostgres -d canopsis /backup/postgresql.dump

# Restart
docker compose up -d
```

---

## TLS with Let's Encrypt

Replace the self-signed certificate with a trusted Let's Encrypt certificate:

```bash
# Install certbot
apt install -y certbot

# Stop nginx temporarily
cd /opt/canopsis && docker compose stop nginx

# Obtain certificate (requires port 80 or DNS validation)
certbot certonly --standalone -d your-domain.com

# Copy certificates
cp /etc/letsencrypt/live/your-domain.com/fullchain.pem /opt/canopsis/certs/server.crt
cp /etc/letsencrypt/live/your-domain.com/privkey.pem /opt/canopsis/certs/server.key

# Restart nginx
docker compose start nginx
```

### Auto-Renewal

```bash
# Add to crontab
echo "0 3 * * * root certbot renew --quiet --deploy-hook 'cd /opt/canopsis && docker compose restart nginx'" \
  > /etc/cron.d/certbot-canopsis
```

---

## Upgrading

1. **Backup first:**
   ```bash
   /opt/canopsis/backup-canopsis.sh
   ```

2. **Update version in .env:**
   ```bash
   sed -i 's/CANOPSIS_VERSION=.*/CANOPSIS_VERSION=25.04.0/' /opt/canopsis/.env
   ```

3. **Pull and restart:**
   ```bash
   cd /opt/canopsis
   docker compose pull
   docker compose up -d
   ```

The `reconfigure` service automatically handles database migrations on startup.

> Always check the [Canopsis release notes](https://doc.canopsis.net/notes-de-version/) before upgrading for breaking changes.

---

## Troubleshooting

### Services Not Starting

```bash
# Check service status
cd /opt/canopsis && docker compose ps

# View logs for failing service
docker compose logs reconfigure
docker compose logs mongodb
docker compose logs engine-axe
```

### MongoDB Replica Set Issues

```bash
# Check replica set status
docker exec canopsis-mongodb mongosh \
  -u cpsmongo -p "$(grep CPS_MONGO_PASSWORD /opt/canopsis/.env | cut -d= -f2)" \
  --authenticationDatabase admin \
  --eval "rs.status()"
```

### RabbitMQ Queue Backlog

```bash
# Check queue sizes
docker exec canopsis-rabbitmq rabbitmqctl list_queues -p canopsis
```

### API Not Responding

```bash
# Direct API health check (bypassing nginx)
docker exec canopsis-api curl -sf http://localhost:8082/api/v4/heartbeat

# Check API logs
docker compose logs api --tail 100
```

### Port Already in Use

```bash
# Find what's using the port
ss -tlnp | grep 8443

# Deploy on different port
sudo bash deploy-canopsis.sh --port 9443
```

### Insufficient Resources

```bash
# Monitor resource usage
docker stats --no-stream

# Increase memory limits in docker-compose.yml if needed
```

### Common Error Messages

| Error | Cause | Fix |
|---|---|---|
| `connection refused` on MongoDB | Replica set not initialized | Wait for `mongodb-init` to complete |
| `UNAUTHORIZED` on API calls | Invalid or missing auth key | Regenerate key in Admin UI |
| `no space left on device` | Disk full | Clean old backups, Docker prune |
| `OOM killed` | Container exceeded mem_limit | Increase `mem_limit` in compose |
| `dial tcp: lookup mongodb` | DNS resolution failure | Ensure services are on same network |

---

## Community vs Pro Edition

| Feature | Community | Pro |
|---|---|---|
| Event aggregation & normalization | ✅ | ✅ |
| Alarm management (ack, cancel, resolve) | ✅ | ✅ |
| Event filters & enrichment | ✅ | ✅ |
| PBehaviors / Maintenance windows | ✅ | ✅ |
| Custom dashboards & widgets | ✅ | ✅ |
| Service weather | ✅ | ✅ |
| Dependency tree visualization | ✅ | ✅ |
| REST API (v4) | ✅ | ✅ |
| RBAC (role-based access) | ✅ | ✅ |
| **Event correlation / Meta-alarms** | ❌ | ✅ |
| **SNMP Trap connector** | ❌ | ✅ |
| **Automatic remediation** | ❌ | ✅ |
| **Ticketing integration (ITSM)** | ❌ | ✅ |
| **SLA/SLI calculations** | ❌ | ✅ |
| **Advanced statistics & KPIs** | ❌ | ✅ |
| **High availability** | ❌ | ✅ |
| **Multi-node deployment** | ❌ | ✅ |
| **Professional support** | ❌ | ✅ (contract) |

> This script deploys the **Community Edition**. To upgrade to Pro, contact [Capensis](https://www.capensis.fr/) for licensing, then change `CPS_EDITION=pro` in `.env` and authenticate to the private Docker registry.

---

## File Structure

```
/opt/canopsis/
├── docker-compose.yml      # Main Compose orchestration file
├── .env                    # Secrets & configuration (chmod 600)
├── nginx.conf              # Nginx reverse proxy config
├── mongo-keyfile           # MongoDB replica set auth key (chmod 400)
├── mongo-init.js           # MongoDB user initialization
├── pg-init.sh              # TimescaleDB extension activation
├── certs/
│   ├── server.crt          # TLS certificate (RSA-4096)
│   └── server.key          # TLS private key
├── backup-canopsis.sh      # Backup script (chmod 750)
└── backups/                # Backup storage directory
    └── YYYYMMDD-HHMMSS/
        ├── mongodb.archive.gz
        ├── postgresql.dump
        └── *.bak
```

---

## Uninstall

```bash
cd /opt/canopsis

# Stop and remove containers (preserves data volumes)
docker compose down

# Full removal including data (IRREVERSIBLE)
docker compose down -v
rm -rf /opt/canopsis

# Remove Docker images
docker image prune -a

# Remove system configurations
rm -f /etc/sysctl.d/99-canopsis.conf
rm -f /etc/systemd/system/disable-thp.service
systemctl daemon-reload
```

---

## References

### Official Documentation
- [Canopsis Documentation Portal](https://doc.canopsis.net/)
- [Installation Guide (Docker)](https://doc.canopsis.net/24.04/guide-administration/installation/installation-conteneurs/)
- [Installation Guide (Packages)](https://doc.canopsis.net/24.04/guide-administration/installation/installation-paquets/)
- [Environment Variables](https://doc.canopsis.net/24.04/guide-administration/administration-avancee/variables-environnement/)
- [Network Ports Matrix](https://doc.canopsis.net/24.04/guide-administration/matrice-des-flux-reseau/)
- [Release Notes](https://doc.canopsis.net/notes-de-version/)

### Connector Documentation
- [Zabbix Connector](https://doc.canopsis.net/24.10/interconnexions/Supervision/Zabbix/)
- [Nagios/Icinga Connector](https://doc.canopsis.net/24.04/interconnexions/Supervision/Nagios-et-Icinga/)
- [Centreon Stream Connector](https://doc.canopsis.net/interconnexions/Supervision/Centreon-stream-connector/)
- [SNMP Trap Connector](https://doc.canopsis.net/interconnexions/Supervision/SNMPtrap/)

### Community Resources
- [Canopsis GitHub](https://github.com/capensis/canopsis)
- [Canopsis GitLab (Official)](https://git.canopsis.net/canopsis/canopsis-community)
- [Canopsis Website](https://www.canopsis.net/)
- [Capensis (Company)](https://www.capensis.fr/)

---

## License

This deployment script is provided under the [MIT License](LICENSE).

Canopsis Community Edition is licensed under the [AGPLv3](https://www.gnu.org/licenses/agpl-3.0.html).
