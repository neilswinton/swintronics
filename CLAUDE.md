# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Is

Infrastructure-as-Code for a self-hosted home server cluster on Hetzner Cloud. It provisions a single Ubuntu server running Docker Compose services, with networking via Tailscale and Traefik, secrets management via Infisical, and monitoring via Uptime Kuma / Prometheus / Grafana.

## Repository Structure

- **`terraform/`** — Provisions the Hetzner Cloud server, Cloudflare DNS, Tailscale node, firewall, SSH keys, and Cloudflare R2 backend for Terraform state
- **`ansible/`** — Manages rolling updates to Docker services from your local machine; connects via Tailscale
- **`docker-services/`** — Docker Compose configurations for all services running on the server
- **`server-scripts/`** — Backup scripts (Restic) and cron definitions that live on the server

## Key Commands

### Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply   # Run twice on first deploy (per README)
```

### Ansible

Run from the `ansible/` directory. Requires Infisical CLI installed locally with `~/.infisical.json` credentials.

```bash
# Install collections (first time)
ansible-galaxy collection install -r requirements.yml

# Test connectivity
ansible swintronics -m ping

# Update a service
ansible-playbook playbooks/update-service.yml \
  -e "service_name=immich" \
  -e "new_version=v1.117.0"

# Dry run
ansible-playbook playbooks/update-service.yml \
  -e "service_name=immich" -e "new_version=v1.117.0" --check

# Debug
ansible-playbook playbooks/update-service.yml \
  -e "service_name=immich" -e "new_version=v1.117.0" -vvv
```

### Docker Cluster (run on the server in `/home/neil/swintronics/docker-services/`)

```bash
./cluster.sh --up        # Start all services
./cluster.sh --down      # Stop all services
./cluster.sh --upgrade   # Pull new images and restart
./cluster.sh --pull      # Pull images without restarting
./cluster.sh --debug     # Enable bash -x tracing
```

`cluster.sh` reads `backup.env` for healthchecks.io API keys and coordinates startup/shutdown order: networking first/last, Uptime Kuma last up / first down.

## Architecture

### Provisioning Flow

1. **Terraform** creates Hetzner server + networking, injects `cloud-init.yml`
2. **Cloud-init** installs Docker and Infisical CLI, clones this repo to `/home/neil/swintronics/`
3. **Manual steps** remain: copy `.env` files and run `cluster.sh --up`

### Secrets

All runtime secrets are stored in **Infisical** (project: "Swintronics Runtime", environment: "dev"). Neither `.env` files nor `.tfvars` files are committed to git.

- Terraform accesses Infisical via machine identity in `.auto.tfvars`
- Ansible fetches secrets at playbook runtime using `infisical export` (delegated to localhost)
- `cluster.sh` reads local `backup.env` on the server for healthchecks.io keys

### Service Update Workflow (Ansible)

The `playbooks/update-service.yml` playbook:
1. Fetches secrets from Infisical (runs locally)
2. Pauses healthchecks.io monitoring
3. Stops Uptime Kuma (skipped if updating Kuma itself)
4. Backs up the service's `.env` file with a timestamp
5. Updates the `SERVICE_VERSION=` line in `.env` using `lineinfile`
6. Pulls new image via `community.docker.docker_compose`
7. Restarts the container
8. Waits for container to report `Running`
9. Restarts Uptime Kuma and waits for port 3001
10. Resumes healthchecks.io monitoring

### Service Name Mapping

The playbook maps `service_name` → directory → env var name:

| service_name   | directory      | env var                  |
|----------------|----------------|--------------------------|
| immich         | immich-app     | IMMICH_VERSION           |
| paperless      | paperless      | PAPERLESS_VERSION        |
| kuma           | uptime-kuma    | KUMA_VERSION             |
| stirling-pdf   | sterling-pdf   | STIRLING_PDF_VERSION     |
| linkwarden     | linkwarden     | LINKWARDEN_VERSION       |
| dozzle         | dozzle         | DOZZLE_VERSION           |
| traefik        | networking     | TRAEFIK_VERSION          |

Version strings for all services are tracked in `docker-services/versions.txt`.

### Networking

- All services share an external Docker network named `proxy`
- Traefik handles TLS termination and reverse proxy (defined in `docker-services/networking/`)
- Tailscale provides VPN access; Ansible connects via `ts.swintronics.com`
- Cloudflare manages public DNS

### Backup

Restic-based backup scripts in `server-scripts/` are installed as cron jobs (`neil.crontab`). Each stateful service (Immich, Paperless, Grafana, Uptime Kuma) has its own backup script with healthchecks.io pings.
