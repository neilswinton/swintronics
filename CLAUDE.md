# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Is

Infrastructure-as-Code for a self-hosted home server cluster on Hetzner Cloud. It provisions a single Ubuntu server running Docker Compose services, with networking via Tailscale and Traefik, secrets management via Infisical, and monitoring via Uptime Kuma / Prometheus / Grafana.

## Repository Structure

- **`terraform/`** — Provisions the Hetzner Cloud server, Cloudflare DNS, Tailscale node, firewall, SSH keys, and Cloudflare R2 backend for Terraform state
- **`ansible/`** — Manages rolling updates to Docker services from your local machine; connects via Tailscale
  - `versions.yml` — single file tracking all service versions; edit and run `deploy-versions.yml` to update
  - `services/` — Docker Compose files as Jinja2 templates; Ansible renders and deploys these to the server
- **`docker-services/`** — Non-versioned service config (cluster.sh, networks.yml, env files, traefik config); compose files are deployed here by Ansible
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

Run from the `ansible/` directory. Source `ansible/.env` first (see `ansible/.env.example`).

```bash
# Install collections (first time)
ansible-galaxy collection install -r requirements.yml
pip install infisicalsdk

# Load credentials
source ansible/.env

# Test connectivity
ansible swintronics -m ping

# Update versions: edit ansible/versions.yml, then:
ansible-playbook playbooks/deploy-versions.yml

# Dry run (shows what would change)
ansible-playbook playbooks/deploy-versions.yml --check

# Update a single service manually
ansible-playbook playbooks/update-service.yml \
  -e "service_name=immich" \
  -e "new_version=v1.117.0"
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
- Ansible authenticates to Infisical using Universal Auth (Machine Identity); credentials in `ansible/.env`
- `cluster.sh` reads local `backup.env` on the server for healthchecks.io keys

### Service Update Workflow (Ansible)

**Preferred:** Edit `ansible/versions.yml` and run `deploy-versions.yml`. The playbook:
1. Renders Jinja2 compose templates from `ansible/services/` to the server
2. Detects which service files actually changed
3. If anything changed: pauses healthchecks.io, stops Kuma, pulls+restarts changed services, starts Kuma, resumes healthchecks.io
4. If nothing changed: exits cleanly with no restarts

**Single-service update:** `update-service.yml -e service_name=X -e new_version=Y` (same orchestration flow for one service).

### Service Name Mapping

| service_name   | directory      | template                            |
|----------------|----------------|-------------------------------------|
| immich         | immich-app     | services/immich-app/compose.yml.j2  |
| paperless      | paperless      | services/paperless/compose.yml.j2   |
| kuma           | uptime-kuma    | services/uptime-kuma/compose.yml.j2 |
| stirling-pdf   | stirling-pdf   | services/stirling-pdf/compose.yml.j2|
| linkwarden     | linkwarden     | services/linkwarden/compose.yml.j2  |
| dozzle         | dozzle         | services/dozzle/compose.yml.j2      |
| traefik        | networking     | services/networking/traefik.yml.j2  |

### Networking

- All services share an external Docker network named `proxy`
- Traefik handles TLS termination and reverse proxy (defined in `docker-services/networking/`)
- Tailscale provides VPN access; Ansible connects via `ts.swintronics.com`
- Cloudflare manages public DNS

### Backup

Restic-based backup scripts in `server-scripts/` are installed as cron jobs (`neil.crontab`). Each stateful service (Immich, Paperless, Grafana, Uptime Kuma) has its own backup script with healthchecks.io pings.

### Beszel Agent Bootstrap

Beszel hub and agent communicate over a Unix socket. The agent requires the hub's public key (`KEY`) to authenticate. This key is only available after the hub is running and a system has been added in the UI.

**First-time setup on a new machine:**
1. Run `deploy-versions.yml` — hub starts, agent is absent (key not set yet)
2. Log into the Beszel UI at `https://beszel.<server_domain>`
3. Add a system — copy the public key shown
4. Add `beszel_agent_key: "<key>"` to `ansible/inventory/host_vars/localhost.yml`
5. Run `deploy-versions.yml` again — agent service is now rendered and started

**Subsequent deploys:** key is already in `localhost.yml`, agent deploys normally.

## Current Work In Progress

### Context: Migration from Hetzner to XPS13

The Hetzner Cloud swintronics server is being decommissioned (too expensive). All Docker workloads are being migrated to the Dell XPS13 (`localhost`). When migration is complete, the XPS13 will become the permanent "swintronics" server. The `swintronics` group in Ansible inventory still points to the Hetzner server but is being retired.

`deploy-versions.yml` defaults to target `swintronics` (Hetzner). During migration, run it with `-e target=localhost` to deploy to the XPS13 instead.

`localhost.yml` has `dns_hostname: xps13` — this will change to `swintronics` once migration is complete and the Hetzner server is shut down.

### Branch: `feature/migrate-services`

#### Done
- Added 1Password desktop + CLI to `ansible/playbooks/apps.yml`
- Added linkwarden service
- DNS redesign: `dns_names` in `_service_config` is now the single source of truth; `deploy-versions.yml` ensures Cloudflare CNAMEs on every run; Traefik Host labels in compose templates reference `_service_config` instead of hardcoded subdomains
- Removed monitoring stack (Prometheus/Grafana/cAdvisor) in favour of Beszel
- Beszel agent gated on `beszel_agent_key` in `localhost.yml` — see bootstrap steps above
- Switched to production cert resolver

#### What's Next
- Complete Beszel bootstrap: log into hub, get agent key, add to `localhost.yml`, re-deploy
- Continue migrating remaining services from Hetzner (immich, paperless, kuma)
