# Deploying a New Server

This is a living runbook. Steps are added and refined as each phase is tested.
Status markers: ✅ validated | 🚧 in progress | 📋 planned

---

## What You'll End Up With

A cloud server (OCI or Hetzner) running Docker Compose services behind Traefik, connected
to your Tailscale network, with secrets from Infisical and monitoring via Uptime Kuma and
Beszel. Services are managed by Ansible from your local machine.

---

## Accounts and Services Required

Before starting, you need accounts with:

| Service | Purpose | Notes |
|---------|---------|-------|
| [Oracle Cloud (OCI)](https://oracle.com/cloud/free) | Server (free tier) | See Step 1 |
| [Cloudflare](https://cloudflare.com) | DNS + TLS certs | Must manage your domain |
| [Infisical](https://infisical.com) | Secrets management | Create a project per deployment |
| [Tailscale](https://tailscale.com) | VPN / Ansible connectivity | Free for personal use |
| [Healthchecks.io](https://healthchecks.io) | Backup monitoring pings | Free tier sufficient |

---

## Local Tools Required

```bash
# Terraform
brew install terraform       # macOS
# or: https://developer.hashicorp.com/terraform/downloads

# Ansible
pip install ansible infisicalsdk
ansible-galaxy collection install -r ansible/requirements.yml

# Tailscale (for connecting to server after initial setup)
# https://tailscale.com/download
```

---

## Step 1 — OCI Account Setup 📋

1. Sign up at [oracle.com/cloud/free](https://oracle.com/cloud/free)
   - Select **US East (Ashburn)** as your home region — this cannot be changed later
   - Always Free A1.Flex instances are only available in your home region

2. **Immediately upgrade to Pay As You Go**
   - OCI reclaims "idle" free-tier instances after approximately 7 days of low activity
   - Upgrading to PAYG keeps Always Free resources permanently; you are not charged for them
   - Billing → Upgrade → Pay As You Go

3. Generate an API signing key
   - Profile (top right) → My Profile → API Keys → Add API Key
   - Download the private key; note the fingerprint shown after adding

4. Collect the following values (all visible in the OCI console):
   - **Tenancy OCID** — Profile → Tenancy
   - **User OCID** — Profile → My Profile
   - **Fingerprint** — shown after adding API key
   - **Private key** — the PEM file you downloaded
   - **Region** — `us-ashburn-1`

---

## Step 2 — Infisical Project Setup 📋

Create a new Infisical project for this deployment (do not reuse another project's secrets).

Add the following secrets to the project (environment: `dev`):

### OCI credentials
| Secret name | Value |
|-------------|-------|
| `OCI_TENANCY_OCID` | from Step 1 |
| `OCI_USER_OCID` | from Step 1 |
| `OCI_FINGERPRINT` | from Step 1 |
| `OCI_PRIVATE_KEY` | full PEM contents |
| `OCI_REGION` | `us-ashburn-1` |

### Cloudflare
| Secret name | Value |
|-------------|-------|
| `CF_DNS_API_TOKEN` | Cloudflare API token with DNS edit on your domain |
| `CF_ZONE_ID` | Zone ID for your domain (from Cloudflare dashboard) |

### Tailscale
| Secret name | Value |
|-------------|-------|
| `TS_SERVER_AUTH_KEY` | Reusable auth key from Tailscale admin → Settings → Keys |

### Server credentials
| Secret name | Value |
|-------------|-------|
| `username` | OS user to create on the server (e.g. `neil`) |

### Service secrets
_TODO: document per-service secrets as services are deployed and tested_

### Healthchecks.io
| Secret name | Value |
|-------------|-------|
| `HEALTHCHECKS_API_KEY` | from healthchecks.io account |
| `HEALTHCHECKS_KUMA_CHECK_UUID` | UUID of the Uptime Kuma heartbeat check |

---

## Step 3 — Cloudflare Domain Setup 📋

1. Add your domain to Cloudflare and point nameservers as instructed
2. Note the Zone ID (Cloudflare dashboard → your domain → Overview, right sidebar)
3. Create an API token: My Profile → API Tokens → Create Token
   - Template: **Edit zone DNS**
   - Scope: your domain's zone
4. Store both in Infisical (see Step 2)

---

## Step 4 — Tailscale Auth Key 📋

1. Tailscale admin console → Settings → Keys → Generate auth key
2. Check **Reusable** (so Ansible can use it for initial join)
3. Set an appropriate expiry
4. Store in Infisical as `TS_SERVER_AUTH_KEY`

---

## Step 5 — Configure Ansible Credentials 📋

Copy the Ansible env file and fill in your Infisical credentials:

```bash
cp ansible/.env.example ansible/.env
# edit ansible/.env:
#   INFISICAL_CLIENT_ID     — Machine Identity client ID from Infisical
#   INFISICAL_CLIENT_SECRET — Machine Identity client secret
#   INFISICAL_PROJECT_ID    — Project ID from Infisical project settings
```

Create a Machine Identity in Infisical (project settings → Access Control → Machine Identities)
and grant it read access to the project.

---

## Step 6 — Create host_vars for the New Server 📋

Copy the example and fill in values:

```bash
cp ansible/inventory/host_vars/localhost.yml.example \
   ansible/inventory/host_vars/<hostname>.yml
```

Key values to set:
- `dns_hostname` — subdomain used for Tailscale and DNS (e.g. `cantina`)
- `server_domain` — your domain (e.g. `cactus-cantina.com`)
- `cert_resolver` — `staging` first, switch to `production` after validating TLS
- `tailscale_tag` — Tailscale ACL tag for this server (e.g. `server`)
- `tailscale_authkey_secret` — Infisical secret name holding the auth key
- `use_btrfs` — `false` for OCI (no separate data disk), `true` for Hetzner/physical
- `data_disk_mountpoint` — `/docker-data`

---

## Step 7 — Add Server to Ansible Inventory 📋

Edit `ansible/inventory/hosts` to add the new host under `[oci]` or `[hetzner]`:

```ini
[oci]
oci-main ansible_host=<tailscale-hostname>.<tailnet>.ts.net
```

The host name must match the `host_vars` filename.

---

## Step 8 — Terraform: Provision the Server 📋

```bash
cd terraform
terraform init
terraform plan -var='cloud_provider=oci'
terraform apply -var='cloud_provider=oci'
```

This creates: OCI instance, VCN, security list, DNS records, Tailscale auth key.

Note the server's public IP from the output. Cloud-init will run on first boot — wait
approximately 2 minutes before proceeding.

_TODO: document .auto.tfvars required variables once Terraform modules are built_

---

## Step 9 — Ansible: Initial Server Configuration 📋

Run from the `ansible/` directory with credentials loaded:

```bash
source ansible/.env

# Install base packages, harden SSH
ansible-playbook playbooks/bootstrap.yml -e target=oci-main

# Install Docker
ansible-playbook playbooks/docker.yml -e target=oci-main

# Install and join Tailscale (subsequent Ansible connections use Tailscale SSH)
ansible-playbook playbooks/tailscale.yml -e target=oci-main
```

After `tailscale.yml`, update the inventory `ansible_host` to the Tailscale hostname
if you used the public IP initially.

---

## Step 10 — Ansible: Storage and Services 📋

```bash
# Create /docker-data directory structure
ansible-playbook playbooks/setup-storage.yml -e target=oci-main

# Render and deploy all service compose files, pull images, start services
ansible-playbook playbooks/deploy-versions.yml -e target=oci-main
```

---

## Step 11 — Ansible: Maintenance Configuration 📋

```bash
# Configure unattended-upgrades with pre/post-reboot hooks
ansible-playbook playbooks/configure-unattended-upgrades.yml -e target=oci-main

# Install backup orchestrator and cron job
ansible-playbook playbooks/install-backup.yml -e target=oci-main
```

---

## Step 12 — Manual: Uptime Kuma 📋

_See the Uptime Kuma Setup section in CLAUDE.md for full instructions._

1. Log in at `https://status-admin.<your-domain>`
2. Create admin account
3. Add Telegram notification channel (bot token + chat ID from Infisical)
4. Add HTTP monitors for each service (5 min interval, 3 retries)
5. Add healthchecks.io push monitor

---

## Step 13 — Manual: Beszel Agent Bootstrap 📋

_See the Beszel Agent Bootstrap section in CLAUDE.md for full instructions._

1. Log in at `https://beszel.<your-domain>`
2. Add a system, copy the public key shown
3. Add `beszel_agent_key` to the server's `host_vars` file
4. Re-run `deploy-versions.yml` — agent starts automatically

---

## Switching TLS from Staging to Production

Once all services are reachable and certs are issuing correctly with Let's Encrypt staging:

1. Change `cert_resolver: staging` → `production` in `host_vars/<hostname>.yml`
2. Run `ansible-playbook playbooks/deploy-versions.yml -e target=<hostname>`
3. Traefik will request production certificates automatically

---

## Notes on Disaster Recovery

Failing over to a new cloud server after primary server failure is a separate procedure
requiring shared Restic credentials and is not covered here. See CLAUDE.md for a summary
of that flow.
