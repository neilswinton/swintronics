# Deploying a New Server

This is a living runbook. Steps are added and refined as each phase is tested.
Status markers: ✅ validated | 🚧 in progress | 📋 planned

This repo can stand up the cluster on three kinds of target. **Part 1 (account
setup)** and **Part 3 (Ansible deployment)** are identical for all of them; only
**Part 2 (provisioning)** differs. Pick your target, then read Part 1 → your
Part 2 option → Part 3 → Part 4.

| Target | Status | Provisioned by | Notes |
|--------|--------|----------------|-------|
| Physical laptop / bare metal | ✅ | You install the OS + data disk | Current primary (XPS13, `swintronics.com`) |
| Oracle Cloud (OCI) | ✅ | Terraform (`cloud_provider=oci`) | Free-tier A1.Flex; experimentation (`cactus-cantina.com`) |
| Hetzner Cloud | 📋 | Terraform (`cloud_provider=hetzner`) | Disaster-recovery target; not yet exercised |

Throughout this runbook `<target>` is the Ansible inventory host name for the
server you're deploying (e.g. `xps13`, `oci-1`, `hetzner-1`). Substitute it in
every `-e target=<target>` invocation.

---

## What You'll End Up With

A server — physical or cloud — running Docker Compose services behind Traefik,
connected to your Tailscale network, with secrets from Infisical and monitoring
via Gatus and Beszel. Services are managed by Ansible from your local machine (on
the laptop target, that machine _is_ the server).

---

## Local Tools Required

```bash
# Clone this repository
git clone https://github.com/neilswinton/swintronics.git
cd swintronics

# Terraform
brew install terraform       # macOS
# or: https://developer.hashicorp.com/terraform/downloads

# Ansible
pip install ansible infisicalsdk
ansible-galaxy collection install -r ansible/requirements.yml

# Tailscale (for connecting to server after initial setup)
# https://tailscale.com/download
```

On the laptop target these tools run on the server itself. For cloud targets they
run on your workstation.

---

# Part 1 — Common Account Setup (all targets)

Accounts required before you start:

| Service | Purpose | Notes |
|---------|---------|-------|
| [Infisical](https://infisical.com) | Secrets management | Create a project per deployment — Step 1.1 |
| [Cloudflare](https://cloudflare.com) | DNS + TLS certs | Must manage your domain — Step 1.2 |
| [Tailscale](https://tailscale.com) | VPN / Ansible connectivity | Free for personal use — Step 1.5 |
| [SMTP2Go](https://www.smtp2go.com) | Outbound email (Immich account creation & password resets, alerts) | Free tier: 1000 emails/month — Step 1.6 |
| [Telegram](https://telegram.org) | Push notifications (Gatus alerts, reboot hooks) | Free; bot token + chat ID — Step 1.7 |
| [Backblaze B2](https://www.backblaze.com/cloud-storage) | Backup storage (restic) | Step 1.8 |
| [Healthchecks.io](https://healthchecks.io) | Backup monitoring pings | Free tier sufficient — Step 1.8 |

Cloud targets also need a provider account (OCI or Hetzner) — that lives in
Part 2 alongside the provisioning it enables.

---

## Step 1.1 — Infisical Project Setup 📋

1. Sign up or log in at [infisical.com](https://infisical.com)

2. Create a new project for this deployment — do not reuse an existing project's secrets
   - Note the **project ID** (Project Settings → General) — you'll need it for `terraform/.auto.tfvars`

Remaining secrets are added as you complete each account setup step. A full checklist
is in Step 3.4 — verify everything is in place before running Terraform.

---

## Step 1.2 — Cloudflare Account and Domain Setup 📋

1. Sign up at [cloudflare.com](https://cloudflare.com) if you don't have an account

2. Add your domain to Cloudflare
   - Dashboard → Add a domain → enter your domain name → Continue
   - Select the **Free** plan
   - Cloudflare will scan for existing DNS records — review and confirm
   - Copy the two Cloudflare nameservers shown (e.g. `xxx.ns.cloudflare.com`)
   - Log in to your domain registrar and replace the existing nameservers with the Cloudflare ones
   - Back in Cloudflare, click **Done, check nameservers** — propagation can take minutes to hours

3. Get your Zone ID
   - Dashboard → click your domain → **Overview** tab
   - Scroll down on the right sidebar — copy the **Zone ID**

4. Create a scoped API token
   - My Profile (top right) → **API Tokens** → **Create Token**
   - Use the **Edit zone DNS** template
   - Under **Zone Resources**: Include → Specific zone → select your domain
   - Click **Continue to summary** → **Create Token**
   - **Copy the token immediately** — it is only shown once

5. Add to Infisical (folder `/`, environment `dev`):

   | Secret name | Value |
   |-------------|-------|
   | `CF_API_EMAIL` | Your Cloudflare account email |
   | `CF_DNS_API_TOKEN` | API token from above |
   | `CF_ZONE_ID` | Zone ID from above |

---

## Step 1.3 — Infisical Machine Identity for Terraform 📋

Terraform needs a Machine Identity with enough privilege to read secrets from your
source project, create the runtime project, populate it with generated secrets, and
create the `docker_deploy` identity that Ansible uses.

1. Infisical → **Organization Settings** → Access Control → Machine Identities → **Add Identity**
   - Name: `terraform`
   - Organization role: **Admin** (required to create projects and new identities)

2. Add authentication to the identity
   - Click the identity → Authentication → **Add Universal Auth**
   - Copy the **Client ID**; click **Generate** to create a Client Secret
   - **Copy the client secret immediately** — it is only shown once

3. Grant the identity access to your source project
   - Go to your source Infisical project → Settings → Access Control → Machine Identities
   - Add the `terraform` identity with **Admin** role

4. Note your source project ID
   - Project Settings → General → copy the **Project ID** (UUID)

5. Store credentials in `terraform/.auto.tfvars`:
   ```hcl
   infisical_client_id     = "<client-id>"
   infisical_client_secret = "<client-secret>"
   infisical_project_id    = "<source-project-id>"
   admin_user              = "<your-username>"   # OS user created on provisioned servers
   ```

---

## Step 1.4 — Terraform State Backend (Cloudflare R2) 📋

Terraform state is stored in a Cloudflare R2 bucket. Each deployment needs its own
bucket (or at minimum a unique key path within a shared bucket) so deployments don't
overwrite each other's state.

1. Create an R2 bucket
   - Cloudflare dashboard → **R2 Object Storage** → **Create bucket**
   - Name it something like `cantina-tfstate`
   - Note your **Account ID** shown on the R2 overview page

2. Create an R2 API token
   - R2 → **Manage R2 API Tokens** → **Create API Token**
   - Permissions: **Object Read & Write**
   - Scope: limit to the bucket you just created
   - Copy the **Access Key ID** and **Secret Access Key** — shown only once

3. Create `terraform/backend.hcl` from the example:
   ```bash
   cp terraform/backend.hcl.example terraform/backend.hcl
   ```
   Fill in:
   ```hcl
   bucket = "cantina-tfstate"
   key    = "cantina/terraform.tfstate"
   endpoints = {
     s3 = "https://<account-id>.r2.cloudflarestorage.com"
   }
   ```

4. Export R2 credentials before running Terraform:
   ```bash
   export AWS_ACCESS_KEY_ID=<access-key-id>
   export AWS_SECRET_ACCESS_KEY=<secret-access-key>
   ```
   Or store them in a local env file (gitignored) and `source` it before each session.

---

## Step 1.5 — Tailscale Account Setup 📋

1. Sign up at [tailscale.com](https://tailscale.com)

2. **Choose an identity provider (IdP)** — Tailscale requires an IdP for login.
   Every user of the tailnet must authenticate through the **same** IdP, so pick one
   everyone can use: if you choose Google login, for example, every person who needs
   access must have a Google account.
   - **Social login (recommended)** — Google, GitHub, Microsoft, or Apple. Easiest
     option; anyone who needs access to the tailnet can use a shared account or be
     invited individually.
   - **Azure AD** — works but complex to configure without prior Azure experience.
   - **Zitadel** — open source IdP with a free cloud tier; good middle ground if you
     want your own IdP without the Azure complexity.

3. Once logged in, note your **tailnet name** (shown in the top left of the admin
   console, e.g. `your-name.ts.net`)

4. Create the `server` tag — tags are required for the Terraform OAuth provider and
   for issuing auth keys to servers:
   - Admin console → **Access Controls** → edit the ACL JSON
   - Add to the `tagOwners` section:
     ```json
     "tagOwners": {
       "tag:server": ["autogroup:admin"]
     }
     ```
   - Save the ACL

5. Create an OAuth client for Terraform
   - Admin console → Settings → **Trust Credentials** → **+Credential**
   - Scopes: `auth_keys`, `devices:core`, `dns:read`, `oauth_keys`
   - Tag: `tag:server`
   - Copy the **Client ID** and **Client Secret** — shown only once

6. Add to Infisical (folder `/terraform`, environment `dev`):

   | Secret name | Value |
   |-------------|-------|
   | `TS_MS_PROVIDER_OAUTH_CLIENT_ID` | OAuth Client ID from above |
   | `TS_MS_PROVIDER_OAUTH_CLIENT_SECRET` | OAuth Client Secret from above |

   Terraform uses the OAuth client to generate a Tailscale auth key automatically —
   no manual auth key creation is needed.

---

## Step 1.6 — SMTP2Go Setup 📋

Provides outbound email — most importantly for Immich's account-creation and
password-reset flows, and for alerts.

1. Sign up at [smtp2go.com](https://www.smtp2go.com)

2. Add and verify a sender domain or address
   - Senders → Verified Senders → Add Sender Domain
   - Follow the DNS verification steps (adds TXT/CNAME records in Cloudflare)

3. Get SMTP credentials
   - Settings → SMTP Users → Add SMTP User
   - Copy the username and password shown

4. Add to Infisical (folder `/`, environment `dev`):

   | Secret name | Value |
   |-------------|-------|
   | `SMTP_HOST` | `mail.smtp2go.com` |
   | `SMTP_PORT` | `587` |
   | `SMTP_USERNAME` | SMTP user from above |
   | `SMTP_PASSWORD` | SMTP password from above |
   | `SMTP_FROM` | Your verified sender address |

---

## Step 1.7 — Telegram Bot Setup 📋

1. Open Telegram and search for **@BotFather**

2. Create a new bot
   - Send `/newbot` and follow the prompts
   - Copy the **bot token** (format: `123456:ABC-DEF...`)

3. Get your chat ID
   - Start a conversation with your new bot (send it any message)
   - Fetch `https://api.telegram.org/bot<TOKEN>/getUpdates` in a browser
   - Copy the `id` field from `message.chat` in the response

4. Add to Infisical (folder `/server`, environment `dev`):

   | Secret name | Value |
   |-------------|-------|
   | `TELEGRAM_BOT_TOKEN` | Bot token from BotFather |
   | `TELEGRAM_CHAT_ID` | Chat ID from above |

---

## Step 1.8 — Backblaze B2 and Healthchecks.io 📋

Terraform provisions the per-deployment backup resources (a bucket-scoped restic
application key, the restic repository + password, and the healthchecks.io
heartbeat check). You supply the parent credentials it uses to do so.

1. **Backblaze B2** — sign up at [backblaze.com](https://www.backblaze.com/cloud-storage).
   B2 is not free, but was chosen for its high quality and low cost.
   - Account → Application Keys → create a **master/admin** application key with
     `writeKeys` + `listKeys` capabilities (Terraform mints the bucket-scoped key from it)
   - Copy the key ID and key secret

2. **Healthchecks.io** — sign up at [healthchecks.io](https://healthchecks.io)
   - Settings → API Access → copy the **API key (read/write)**

3. Add to Infisical (folder `/terraform`, environment `dev`):

   | Secret name | Value |
   |-------------|-------|
   | `B2_MASTER_KEY_ID` | B2 master/admin key ID |
   | `B2_MASTER_KEY` | B2 master/admin key secret |
   | `HEALTHCHECKS_API_KEY` | healthchecks.io read/write API key |

---

# Part 2 — Provision the Target

Complete **one** of the options below, matching your target. Cloud options (A, B)
run Terraform to create the server; the laptop option (C) uses hardware you set up
yourself and runs Terraform only for DNS, Tailscale, and the runtime secrets project.

All three run `terraform init` the same way:

```bash
cd terraform
terraform init -backend-config=backend.hcl
```

---

## Option A — Oracle Cloud (OCI) ✅

### A.1 — OCI Account Setup

1. Sign up at [oracle.com/cloud/free](https://oracle.com/cloud/free)
   - Select **US East (Ashburn)** as your home region — this cannot be changed later
   - Always Free A1.Flex instances are only available in your home region

2. **Immediately upgrade to Pay As You Go**
   - OCI reclaims "idle" free-tier instances after approximately 7 days of low activity
   - Upgrading to PAYG keeps Always Free resources permanently; you are not charged for them
   - Billing → Upgrade → Pay As You Go
   - **Note:** OCI will issue a $100 authorization hold when upgrading — this is a verification
     charge that is immediately reversed and not actually collected. Use a card with a limit
     above $100; a virtual card with a low limit (e.g. $20/month) will cause the upgrade to fail.

3. Generate an API signing key
   - Profile (top right) → My Profile → API Keys → Add API Key
   - Download the private key; note the fingerprint shown after adding

4. Collect the following values (all visible in the OCI console):
   - **Tenancy OCID** — Profile → Tenancy
   - **User OCID** — Profile → My Profile
   - **Fingerprint** — shown after adding API key
   - **Private key** — the PEM file you downloaded
   - **Region** — `us-ashburn-1`

5. Add to Infisical (folder `/terraform`, environment `dev`):

   | Secret name | Value |
   |-------------|-------|
   | `OCI_TENANCY_OCID` | Tenancy OCID |
   | `OCI_USER_OCID` | User OCID |
   | `OCI_FINGERPRINT` | API key fingerprint |
   | `OCI_PRIVATE_KEY` | Full PEM file contents |
   | `OCI_REGION` | `us-ashburn-1` |

### A.2 — Provision

```bash
terraform plan  -var='cloud_provider=oci'
terraform apply -var='cloud_provider=oci'
```

Instance sizing (ocpus, memory, disk sizes) defaults to a free-tier A1.Flex; override
via the `oci = { ... }` object in `.auto.tfvars` if needed.

This creates: OCI instance, VCN, security list, DNS records, Tailscale auth key,
and a runtime Infisical project populated with generated service secrets. Note the
server's public IP from the output — cloud-init runs on first boot, so wait ~2
minutes before proceeding to Part 3.

---

## Option B — Hetzner Cloud 📋

> Not yet exercised end-to-end. The Terraform module exists
> (`terraform/modules/hetzner`); treat the first run as validation.

### B.1 — Hetzner Account Setup

1. Sign up at [hetzner.com/cloud](https://www.hetzner.com/cloud)

2. Create a project in the Hetzner Cloud Console

3. Generate an API token
   - Project → Security → **API Tokens** → Generate API Token
   - Permission: **Read & Write**
   - Copy the token — shown only once

4. Add to Infisical (folder `/terraform`, environment `dev`):

   | Secret name | Value |
   |-------------|-------|
   | `HETZNER_TOKEN` | Hetzner Cloud API token |

### B.2 — Provision

Server type, image, region, and volume size default to a small btrfs-capable
instance; override via the `hetzner = { ... }` object in `.auto.tfvars` if needed:

```hcl
# hetzner = {
#   server_type    = "CPX11"
#   volume_size_gb = 40
# }
```

```bash
terraform plan  -var='cloud_provider=hetzner'
terraform apply -var='cloud_provider=hetzner'
```

This creates: Hetzner server + attached data volume, network, firewall, DNS records,
Tailscale auth key, and a runtime Infisical project populated with generated service
secrets. Note the server's public IP from the output and wait ~2 minutes for
cloud-init before proceeding to Part 3.

Hetzner is also the disaster-recovery target — restoring existing data onto a fresh
Hetzner server is a distinct flow; see **Disaster Recovery** in Part 4.

---

## Option C — Physical Laptop / Bare Metal ✅

No server is provisioned by Terraform — you supply the hardware and OS. Terraform
still runs to create DNS records, the Tailscale auth key, and the runtime secrets
project.

### C.1 — Prepare the Machine

1. Install Ubuntu Server 24.04 (or similar) and create your admin user
2. Attach and mount a **btrfs** data disk at `/docker-data` — this is where all
   stateful service volumes live (`setup-storage.yml` creates btrfs subvolumes under it)
3. Ensure the machine is reachable and you can `sudo` on it
4. Laptop-only hardening (masking sleep/suspend, ignoring lid close) is applied by
   `laptop.yml` in Part 3 — nothing to do here

### C.2 — Provision DNS + Tailscale + Secrets

Run Terraform with **no** `cloud_provider` (defaults to null / local-only), so it
skips server creation but still manages DNS, the Tailscale auth key, and the runtime
Infisical project:

```bash
terraform plan
terraform apply
```

The control node for a laptop deployment is the laptop itself — Ansible connects
locally (`ansible_connection=local`) rather than over SSH/Tailscale.

---

# Part 3 — Common Ansible Deployment (all targets)

From here the steps are identical for every target; only the inventory entry and
connection method differ. Cloud targets connect over SSH (then Tailscale); the
laptop target connects locally.

## Step 3.1 — Configure Ansible Credentials 📋

Copy the Ansible env file and fill in your Infisical credentials:

```bash
cp ansible/.env.example ansible/.env
# edit ansible/.env:
#   INFISICAL_CLIENT_ID     — docker_deploy Machine Identity client ID (output by terraform apply)
#   INFISICAL_CLIENT_SECRET — docker_deploy Machine Identity client secret
#   INFISICAL_PROJECT_ID    — runtime project ID (created by Terraform)
```

`terraform apply` creates the `docker_deploy` Machine Identity and the runtime
project; their values appear in the Terraform outputs.

---

## Step 3.2 — Create host_vars for the Target 📋

Copy the example and fill in values:

```bash
cp ansible/inventory/host_vars/localhost.yml.example \
   ansible/inventory/host_vars/<target>.yml
```

Common values:
- `admin_user` — OS user created during provisioning
- `dns_hostname` — subdomain used for DNS/Tailscale (e.g. `oci-1`, `xps13`)
- `tailscale_tag` — Tailscale ACL tag (e.g. `server`)
- `tailscale_authkey_secret` — Infisical secret name holding the auth key
- `use_btrfs` — `true` for a btrfs data disk (all current targets)
- `data_disk_mountpoint` — `/docker-data`

Cloud target extras (see `host_vars/oci-1.yml`):
- `ansible_user` + `ansible_ssh_private_key_file` — the admin key Terraform wrote to
  `terraform/artifacts/` for the first (pre-Tailscale) connection
- `tailscale_ip` / `dns_cname_target` — set once Tailscale is up

Laptop target extras (see `host_vars/xps13.yml`):
- Runs with `ansible_connection=local` (set in the inventory, below)
- `tailscale_subnet` / `tailscale_exit_node` — advertise the LAN / act as an exit node
- `hardware_watchdog_module`, `zigbee_dongle_path`, `docker_gid` — hardware specifics

---

## Step 3.3 — Add Target to Ansible Inventory 📋

Edit `ansible/inventory/hosts`.

**Laptop / local** — the control node and the server are the same machine:

```ini
[local]
xps13 ansible_connection=local ansible_host=localhost
```

**Cloud (OCI / Hetzner)** — add the host under a cloud group, initially pointing at
the public IP, later at the Tailscale hostname:

```ini
[oci]
oci-1 ansible_host=<public-ip-or-tailscale-hostname>

[hetzner]
hetzner-1 ansible_host=<public-ip-or-tailscale-hostname>
```

The host name must match the `host_vars` filename.

---

## Step 3.4 — Validate Infisical Secrets 📋

Before running Ansible, verify all required secrets are present in your Infisical
project (environment: `dev`). Use the dashboard to check each folder.

### Folder `/`
| Secret name | Added in |
|-------------|----------|
| `CF_API_EMAIL` | Step 1.2 |
| `CF_DNS_API_TOKEN` | Step 1.2 |
| `CF_ZONE_ID` | Step 1.2 |
| `SMTP_HOST` | Step 1.6 |
| `SMTP_PORT` | Step 1.6 |
| `SMTP_USERNAME` | Step 1.6 |
| `SMTP_PASSWORD` | Step 1.6 |
| `SMTP_FROM` | Step 1.6 |

### Folder `/terraform`
| Secret name | Added in |
|-------------|----------|
| `TS_MS_PROVIDER_OAUTH_CLIENT_ID` | Step 1.5 |
| `TS_MS_PROVIDER_OAUTH_CLIENT_SECRET` | Step 1.5 |
| `B2_MASTER_KEY_ID` | Step 1.8 |
| `B2_MASTER_KEY` | Step 1.8 |
| `HEALTHCHECKS_API_KEY` | Step 1.8 |
| _OCI:_ `OCI_TENANCY_OCID`, `OCI_USER_OCID`, `OCI_FINGERPRINT`, `OCI_PRIVATE_KEY`, `OCI_REGION` | Step A.1 (OCI target only) |
| _Hetzner:_ `HETZNER_TOKEN` | Step B.1 (Hetzner target only) |

### Folder `/server`
| Secret name | Added in |
|-------------|----------|
| `TELEGRAM_BOT_TOKEN` | Step 1.7 |
| `TELEGRAM_CHAT_ID` | Step 1.7 |

_Terraform creates the bucket-scoped restic application key, the healthchecks.io
heartbeat check, and the restic password, then writes `B2_ACCOUNT_ID`,
`B2_ACCOUNT_KEY`, `RESTIC_REPOSITORY`, `RESTIC_PASSWORD`,
`HEALTHCHECKS_HEARTBEAT_CHECK_UUID`, and `HEALTHCHECKS_API_KEY` into the runtime
project. Ansible's `install-backup.yml` reads them and renders
`docker-services/backup.env`._

---

## Step 3.5 — Initial Server Configuration 📋

Run from the `ansible/` directory with credentials loaded:

```bash
source ansible/.env

# Install base packages, harden SSH
ansible-playbook playbooks/bootstrap.yml -e target=<target>

# Install Docker
ansible-playbook playbooks/docker.yml -e target=<target>

# Install and join Tailscale (subsequent Ansible connections use Tailscale SSH)
ansible-playbook playbooks/tailscale.yml -e target=<target>
```

For **cloud** targets: after `tailscale.yml`, update the inventory `ansible_host`
(and `host_vars` `tailscale_ip` / `dns_cname_target`) to the Tailscale hostname so
later runs go over Tailscale instead of the public IP.

For the **laptop** target only, apply laptop hardening (mask sleep/suspend, ignore
lid close):

```bash
ansible-playbook playbooks/laptop.yml -e target=<target>
```

---

## Step 3.6 — Storage and Services 📋

```bash
# Create /docker-data directory structure (btrfs subvolumes when use_btrfs=true)
ansible-playbook playbooks/setup-storage.yml -e target=<target>

# Render and deploy all service compose files, pull images, start services
ansible-playbook playbooks/deploy-versions.yml -e target=<target>
```

---

## Step 3.7 — Maintenance Configuration 📋

```bash
# Configure unattended-upgrades with pre/post-reboot hooks
ansible-playbook playbooks/configure-system-services.yml -e target=<target>

# Install backup orchestrator and cron job
ansible-playbook playbooks/install-backup.yml -e target=<target>
```

---

# Part 4 — Post-Deploy (all targets)

## Monitoring: Gatus ✅

Nothing manual to do — Gatus is config-driven and deployed like any other service
by `deploy-versions.yml` (endpoints in `ansible/services/gatus/config.yaml.j2`,
Telegram alerts using the bot from Step 1.7). Verify at `https://gatus.<your-domain>`.

---

## Manual: Beszel Agent Bootstrap 📋

_See the Beszel Agent Bootstrap section in CLAUDE.md for full instructions._

1. Log in at `https://beszel.<your-domain>` — first user becomes a superuser
2. Create a second user (Settings → Users → Add User) — superusers can't use universal tokens
3. Log in as the second user
4. Settings → Tokens → enable a permanent universal token; copy the UUID
5. Click "Add System" → copy the SSH public key shown (don't submit the form)
6. Set `BESZEL_AGENT_KEY` and `BESZEL_AGENT_TOKEN` in the Infisical Runtime project
7. Re-run `deploy-versions.yml` — agent deploys and auto-registers

---

## Switching TLS from Staging to Production

Once all services are reachable and certs are issuing correctly with Let's Encrypt staging:

1. Change `cert_resolver: staging` → `production` in `host_vars/<target>.yml`
2. Run `ansible-playbook playbooks/deploy-versions.yml -e target=<target>`
3. Traefik will request production certificates automatically

---

## Disaster Recovery

Failing over from the primary server to a fresh cloud server (Hetzner is the intended
DR target) is a distinct procedure: it reuses the **same** Restic repository
credentials as the primary and restores data into a matching
`/docker-data/volumes/` layout before starting services. That flow is not fully
automated here — see the "Restore / Disaster Recovery" and "Scenario B" sections in
CLAUDE.md for the current outline.
