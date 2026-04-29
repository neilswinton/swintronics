# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Is

Infrastructure-as-Code for a self-hosted server cluster. Primary server is a Dell XPS13 (`swintronics.com`). Cloud targets are Hetzner (DR) and Oracle Cloud OCI (`cactus-cantina.com`, experimental). All servers run Docker Compose services with Tailscale networking, Traefik reverse proxy, Infisical secrets, and Uptime Kuma / Beszel monitoring.

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

## New Deployment Checklist

### Prerequisites (external accounts/services)

- **Cloudflare** — zone for your domain, API token with DNS edit permissions, zone ID
- **Tailscale** — tailnet with an OAuth client (scopes: `auth_keys`, `devices:core`, `dns:read`, `oauth_keys`); a `container` tag must exist and be assigned to `devices:core`
- **Infisical** — account + project; a Machine Identity with `admin` role for Terraform, and a separate Machine Identity (`docker_deploy`) created by Terraform for Ansible
- **healthchecks.io** — account for backup monitoring (optional but referenced in `backup.env`)
- **Telegram bot** — for Kuma notifications (token + chat ID stored in Infisical under `/server`)

### Required gitignored files

These files must be created manually — they are never committed.

#### `terraform/.auto.tfvars`

```hcl
infisical_client_id     = ""   # Terraform Machine Identity client ID
infisical_client_secret = ""   # Terraform Machine Identity client secret
infisical_project_id    = ""   # Infisical project UUID (from Project Settings → General)
admin_user              = ""   # OS username to create on provisioned servers
timezone                = "America/New_York"
domain_name             = "example.com"
cloud_provider          = "oci"  # "hetzner", "oci", or omit for local-only

# Hetzner — only needed if cloud_provider = "hetzner". All fields have defaults.
# hetzner = {
#   server_type    = "CPX11"
#   volume_size_gb = 40
# }

# OCI — only needed if cloud_provider = "oci". All fields have defaults.
# oci = {
#   region              = "us-ashburn-1"
#   ocpus               = 1
#   memory_in_gbs       = 6
#   boot_volume_size_gb = 50
#   data_volume_size_gb = 60
# }
```

#### `ansible/.env`

Copy from `ansible/.env.example` and fill in values. The Machine Identity here is the `docker_deploy` identity created by `terraform apply` — its credentials are output after apply.

```bash
export INFISICAL_CLIENT_ID=
export INFISICAL_CLIENT_SECRET=
export INFISICAL_PROJECT_ID=   # Runtime project ID (different from the Terraform project)
```

#### `ansible/inventory/host_vars/localhost.yml`

```yaml
git_user_name: ""
git_user_email: ""

data_disk_mountpoint: /docker-data   # Must be a btrfs filesystem
immich_data_location: "{{ data_disk_mountpoint }}/volumes/immich"

tailscale_tag: "server"
tailscale_authkey_secret: "TS_XPS13_AUTH_KEY"   # Name of secret in Infisical runtime project
tailscale_subnet: "192.168.X.0/24"
tailscale_exit_node: true

dns_hostname: "myhostname"   # Used as CNAME target: <dns_hostname>.<domain>
cert_resolver: "staging"     # Use "staging" until everything works, then "production"

docker_gid: "984"   # Check with: getent group docker | cut -d: -f3

hardware_watchdog_module: "iTCO_wdt"   # Intel: iTCO_wdt, AMD: sp5100_tco; omit on unknown hardware

# Set after first Beszel deploy (see Beszel Agent Bootstrap below):
# beszel_agent_key: ""
# beszel_agent_token: ""
```

#### `docker-services/backup.env`

Sourced by `backup.sh` and `cluster.sh`. All `RESTIC_*` vars are passed to `restic` via `sudo -E`.

```bash
DATA_MOUNTPOINT=/docker-data

# Restic repository (e.g. Backblaze B2, S3, local path)
RESTIC_REPOSITORY=
RESTIC_PASSWORD=
# Add any provider-specific env vars (B2_ACCOUNT_ID, AWS_ACCESS_KEY_ID, etc.)

# healthchecks.io — for pausing/resuming the Kuma heartbeat monitor during backup
HEARTBEAT_HEALTHCHECK_API_KEY=
HEARTBEAT_HEALTHCHECK_PAUSE_URL=
HEARTBEAT_HEALTHCHECK_RESUME_URL=

# Kuma push URLs — created in Kuma UI as push monitors, one per service (optional)
KUMA_PHOTO_PUSH_URL=
KUMA_PAPERLESS_PUSH_URL=
KUMA_LINKWARDEN_PUSH_URL=
KUMA_KUMA_PUSH_URL=
```

### Infisical secret structure

Terraform reads from the **Terraform project** (existing, pre-created):

| Path | Key | Description |
|------|-----|-------------|
| `/` | `CF_API_EMAIL` | Cloudflare account email |
| `/` | `CF_DNS_API_TOKEN` | Cloudflare DNS token (copied to runtime project by Terraform) |
| `/` | `CF_ZONE_ID` | Cloudflare zone ID |
| `/terraform` | `TS_MS_PROVIDER_OAUTH_CLIENT_ID` | Tailscale OAuth client ID |
| `/terraform` | `TS_MS_PROVIDER_OAUTH_CLIENT_SECRET` | Tailscale OAuth client secret |
| `/terraform` | `HETZNER_TOKEN` | Hetzner API token (only if `cloud_provider = "hetzner"`) |
| `/terraform` | `OCI_TENANCY_OCID` | OCI tenancy OCID (only if `cloud_provider = "oci"`) |
| `/terraform` | `OCI_USER_OCID` | OCI user OCID |
| `/terraform` | `OCI_FINGERPRINT` | OCI API key fingerprint |
| `/terraform` | `OCI_PRIVATE_KEY` | OCI API signing key (PEM) |
| `/terraform` | `OCI_REGION` | OCI region identifier |
| `/server` | `TELEGRAM_BOT_TOKEN` | Telegram bot token for Kuma notifications |
| `/server` | `TELEGRAM_CHAT_ID` | Telegram chat ID |

Terraform creates the **Runtime project** and populates it with generated secrets (DB passwords, encryption keys, auth keys). Ansible reads from the Runtime project.

### First deploy sequence

1. Create Infisical Terraform project and populate `/terraform` secrets above
2. `cd terraform && terraform init && terraform apply` — creates Runtime project, Tailscale node, Cloudflare DNS, generates all service secrets; **run twice** (first apply creates the Runtime project; second populates it)
3. Set up the server: ensure btrfs data disk is mounted at `data_disk_mountpoint`
4. `cd ansible && source .env`
5. `ansible-galaxy collection install -r requirements.yml && pip install infisicalsdk`
6. `ansible-playbook playbooks/bootstrap.yml` — installs system packages, configures SSH, sudo
7. `ansible-playbook playbooks/docker.yml` — installs Docker
8. `ansible-playbook playbooks/tailscale.yml` — joins Tailscale network
9. `ansible-playbook playbooks/setup-storage.yml` — creates btrfs subvolumes for stateful services
10. `ansible-playbook playbooks/deploy-versions.yml` — deploys and starts all services
11. `ansible-playbook playbooks/install-backup.yml` — installs backup cron job
12. Complete manual setup: Kuma (see below), Beszel (see below), `backup.env` on server

### Restore / Disaster Recovery

The restore procedure is not yet automated. Manual steps:

1. Complete steps 1–11 above on the new server (services start with empty data)
2. Stop services that own the data to be restored: `docker compose stop <service>`
3. Initialize the restic repo and restore the snapshot:
   ```bash
   sudo -E restic snapshots   # list available snapshots
   sudo -E restic restore latest --tag <service> --target /
   ```
4. Fix ownership if needed (`chown -R <user> <data dir>`)
5. Restart services: `docker compose start <service>`
6. Verify data integrity in the UI before re-enabling backup cron

`backup.env` must be present and `RESTIC_*` vars exported before running `restic` commands.

## Architecture

### Provisioning Flow

1. **Terraform** creates cloud server + networking, injects `cloud-init.yml`
2. **Cloud-init** creates the admin user with SSH key and `mkdir`s the data disk mountpoint
3. **Ansible** runs sequentially: `bootstrap.yml` → `docker.yml` → `tailscale.yml` → `setup-storage.yml` (formats + mounts disk, creates directory structure) → `deploy-versions.yml`

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
| autoheal       | autoheal       | services/autoheal/compose.yml.j2    |

### Networking

- All services share an external Docker network named `proxy`
- Traefik handles TLS termination and reverse proxy (defined in `docker-services/networking/`)
- Tailscale provides VPN access; Ansible connects via `ts.swintronics.com`
- Cloudflare manages public DNS

### Backup

Restic-based backup scripts in `server-scripts/` are installed as cron jobs (`neil.crontab`). Each stateful service (Immich, Paperless, Uptime Kuma) has its own backup script with healthchecks.io pings.

### Uptime Kuma Setup

Kuma configuration is manual (no API automation). Use SQLite (the default) — no external DB needed.

**First-time setup on a new machine:**
1. Run `deploy-versions.yml` — Kuma starts with a fresh SQLite database
2. Log into the admin UI at `https://status-admin.<server_domain>`
3. Create an account (first user becomes admin)
4. Add a **Telegram** notification channel: Settings → Notifications → Add → Telegram
   - Bot token and chat ID are in Infisical
   - Test before saving
5. Add **HTTP monitors** for each service — interval: 5 minutes, retries: 3:
   - `https://photos.<domain>` — Immich
   - `https://paperless.<domain>` — Paperless
   - `https://linkwarden.<domain>` — Linkwarden
   - `https://stirling-pdf.<domain>` — Stirling PDF
   - `https://logs.<domain>` — Dozzle
   - `https://beszel.<domain>` — Beszel
   - `https://status-admin.<domain>` — Kuma itself
   - healthchecks.io ping URL (from Infisical as `HC_KUMA_PING_URL`) — confirms Kuma is alive

**Subsequent deploys:** Kuma data persists in `/docker-data/volumes/uptime-kuma/data` (SQLite file).

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

### Context

All services run on the Dell XPS13 (`localhost`), using `swintronics.com` as the domain. Hetzner has been decommissioned. The next goal is to deploy to cloud providers and establish a DR path.

### Goal: Multi-cloud deployment + disaster recovery

**DR path:** If the XPS13 fails, spin up a Hetzner server, run Ansible, restore from Restic backups, flip DNS — back online. Hetzner is the DR target because it has a proper btrfs data disk matching the XPS13 layout.

**OCI:** Oracle Cloud (free tier, ARM A1.Flex, `us-ashburn-1`) is for experimentation. It runs the same services with a btrfs data disk (60 GiB by default; free tier allows 200 GiB total block storage). Not the DR target.

**Domain:** New deployments use `cactus-cantina.com`. XPS13 continues on `swintronics.com` for now.

**Naming convention:** `swintronics` stays in infrastructure code (script names, service names, system paths). Per-deployment variables (`server_domain`, `dns_hostname`) are set in `host_vars` and can be cantina-branded.

### Phase 1 — Codebase cleanup (do first, no new infra needed)

- [ ] Slim `terraform/scripts/cloud-init.yml`: remove Docker install, Infisical CLI install, package list, git clone, Tailscale. Keep only user creation and data disk formatting. Make disk formatting conditional (`format_data_disk` bool) so OCI can skip it.
- [ ] Split laptop-specific tasks out of `ansible/playbooks/bootstrap.yml` into a new `ansible/playbooks/laptop.yml` (sleep/suspend masking, lid-close handling).
- [ ] Rename Ansible inventory group `[swintronics]` → `[servers]` and update all playbook defaults accordingly.
- [ ] Rename `ansible/inventory/group_vars/swintronics.yml` → `servers.yml`; change `docker_services_path` to use `{{ cluster_name }}` variable instead of hardcoded `swintronics`; change `data_disk_mountpoint` to `/docker-data`.
- [ ] Update `setup-storage.yml` to support `use_btrfs: false` hosts — skip btrfs check and subvolume creation, create plain directories instead.

### Phase 2 — Terraform module extraction

Restructure flat `terraform/` into reusable modules:

```
terraform/
├── main.tf           # renders cloud-init, calls modules, wires DNS + Tailscale
├── variables.tf      # cloud_provider, shared vars
├── providers.tf
├── cloudflare.tf     # iterates active servers → DNS CNAMEs
├── tailscale.tf      # one auth key per active server
├── secrets.tf        # Infisical (root-level)
├── ssh.tf
├── outputs.tf
└── modules/
    ├── hetzner/      # server + btrfs volume + network + firewall + ssh_key
    └── oci/          # instance (A1.Flex) + VCN + IGW + route table +
                      #   security list + block volume + attachment
```

Both modules accept: `project_name`, `admin_user`, `admin_public_key`, `user_data`, `region`.
Hetzner also accepts: `server_type`, `volume_size_gb`.
Both output: `server_ip`, `server_name`.

`format_data_disk = true` for Hetzner, `false` for OCI.

### Phase 3 — Ansible inventory expansion

```
inventory/
├── hosts
│   [local]              localhost
│   [hetzner]            (future DR server)
│   [oci]                oci-main ansible_host=<tailscale hostname>
│   [servers:children]   hetzner, oci
├── group_vars/
│   ├── all.yml          # shared vars
│   └── servers.yml      # remote server defaults
└── host_vars/
    ├── localhost.yml           # XPS13: swintronics.com, use_btrfs=true
    └── oci-main.yml            # OCI: cactus-cantina.com, use_btrfs=true
```

### Phase 4 — OCI deployment prerequisites (user actions)

1. Sign up at oracle.com/cloud/free — select **US East (Ashburn)** as home region (cannot change later)
2. **Immediately upgrade to a paid account** — OCI reclaims "idle" free-tier instances after 7 days of inactivity. Upgrading to Pay As You Go keeps Always Free resources permanently and prevents surprise termination. You are not charged for Always Free resources.
3. Generate OCI API signing key; collect: tenancy OCID, user OCID, fingerprint, private key, region
4. Store in Infisical (cantina project): `OCI_TENANCY_OCID`, `OCI_USER_OCID`, `OCI_FINGERPRINT`, `OCI_PRIVATE_KEY`, `OCI_REGION`
5. Add `cactus-cantina.com` to Cloudflare; confirm existing `CF_DNS_API_TOKEN` covers it (or create a new token)
6. Provide XPS13 `host_vars/localhost.yml` as reference for new host_vars files

### Two distinct server deployment scenarios

#### Scenario A: Standing up a new server (primary flow)

A fresh server with no prior data. The normal case for OCI experimentation or adding a new node.

```bash
terraform apply -var='cloud_provider=oci'
# wait ~2 min for cloud-init (user creation only)
ansible-playbook playbooks/bootstrap.yml -e target=oci-main
ansible-playbook playbooks/docker.yml -e target=oci-main
ansible-playbook playbooks/tailscale.yml -e target=oci-main
# subsequent connections via Tailscale SSH
ansible-playbook playbooks/setup-storage.yml -e target=oci-main
ansible-playbook playbooks/deploy-versions.yml -e target=oci-main
ansible-playbook playbooks/configure-unattended-upgrades.yml -e target=oci-main
ansible-playbook playbooks/install-backup.yml -e target=oci-main
# manual: Uptime Kuma setup, Beszel agent bootstrap
```

Each new deployment has its own Infisical project with its own secrets. Services start fresh with no data.

#### Scenario B: Failover from XPS13 to Hetzner (DR)

A different flow — documented here for reference, not the current focus. Requires:
- Shared Restic repository credentials between XPS13 and the recovery server
- Matching volume layout (`/docker-data/volumes/` structure)

```bash
terraform apply -var='cloud_provider=hetzner'
# run Scenario A deployment steps with target=hetzner-main
# then restore data before starting services:
restic restore latest --target /docker-data/volumes/
ansible-playbook playbooks/deploy-versions.yml -e target=hetzner-main
# flip DNS: point domain A record at Hetzner IP
```

This scenario requires additional planning around Restic repo sharing and is deferred.

### Backlog

- Update Kuma monitors on XPS13: add all services, Telegram notifications, healthchecks.io ping
- Consider Renovate bot for automatic Docker image version PRs
- Add nginx autoindex service to serve `data_disk_mountpoint/logs` over HTTPS
- Automate restore procedure
- Long-term: phone-friendly server management — expose remaining service UIs, document mobile access patterns

### Upstream Compose File Convention
Services adapted from upstream compose files keep a reference copy at `ansible/services/<service>/upstream.yml`. Diff with `diff ansible/services/<service>/upstream.yml ansible/services/<service>/compose.yml.j2` to see local changes. Currently tracked: immich, paperless, linkwarden, uptime-kuma, beszel. Not tracked: networking/traefik (fully custom), dozzle, dockhand (single-container, written from scratch), stirling-pdf (upstream repo only has build-from-source compose files, no runtime compose)
