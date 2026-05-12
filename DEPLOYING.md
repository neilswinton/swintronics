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
| [Infisical](https://infisical.com) | Secrets management | Create a project per deployment — See Step 1 |
| [Oracle Cloud (OCI)](https://oracle.com/cloud/free) | Server (free tier) | See Step 2 |
| [Cloudflare](https://cloudflare.com) | DNS + TLS certs | Must manage your domain — See Step 3 |
| [Tailscale](https://tailscale.com) | VPN / Ansible connectivity | Free for personal use — See Step 6 |
| [SMTP2Go](https://www.smtp2go.com) | Outbound email (Paperless, alerts) | Free tier: 1000 emails/month — See Step 7 |
| [Telegram](https://telegram.org) | Push notifications (Uptime Kuma) | Free; requires a bot token + chat ID — See Step 8 |
| [Healthchecks.io](https://healthchecks.io) | Backup monitoring pings | Free tier sufficient |

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

---

## Step 1 — Infisical Project Setup 📋

1. Sign up or log in at [infisical.com](https://infisical.com)

2. Create a new project for this deployment — do not reuse an existing project's secrets
   - Note the **project ID** (Project Settings → General) — you'll need it for `terraform/.auto.tfvars`

Remaining secrets are added as you complete each account setup step. A full checklist
is in Step 13 — verify everything is in place before running Terraform.

---

## Step 2 — OCI Account Setup 📋

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

---

## Step 3 — Cloudflare Account and Domain Setup 📋

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

## Step 4 — Infisical Machine Identity for Terraform 📋

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

## Step 5 — Terraform State Backend (Cloudflare R2) 📋

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

## Step 6 — Tailscale Account Setup 📋

1. Sign up at [tailscale.com](https://tailscale.com)

2. **Choose an identity provider** — Tailscale requires an IdP for login:
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

## Step 7 — SMTP2Go Setup 📋

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

## Step 8 — Telegram Bot Setup 📋

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

## Step 9 — Configure Ansible Credentials 📋

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

## Step 10 — Create host_vars for the New Server 📋

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
- `use_btrfs` — `true` for servers with a data disk (OCI, Hetzner, physical)
- `data_disk_mountpoint` — `/docker-data`

---

## Step 11 — Add Server to Ansible Inventory 📋

Edit `ansible/inventory/hosts` to add the new host under `[oci]` or `[hetzner]`:

```ini
[oci]
oci-main ansible_host=<tailscale-hostname>.<tailnet>.ts.net
```

The host name must match the `host_vars` filename.

---

## Step 12 — Validate Infisical Secrets 📋

Before running Terraform, verify all required secrets are present in your Infisical
project (environment: `dev`). Use the Infisical dashboard to check each folder.

### Folder `/`
| Secret name | Added in |
|-------------|----------|
| `CF_API_EMAIL` | Step 3 |
| `CF_DNS_API_TOKEN` | Step 3 |
| `CF_ZONE_ID` | Step 3 |
| `SMTP_HOST` | Step 7 |
| `SMTP_PORT` | Step 7 |
| `SMTP_USERNAME` | Step 7 |
| `SMTP_PASSWORD` | Step 7 |
| `SMTP_FROM` | Step 7 |

### Folder `/terraform`
| Secret name | Added in |
|-------------|----------|
| `OCI_TENANCY_OCID` | Step 2 |
| `OCI_USER_OCID` | Step 2 |
| `OCI_FINGERPRINT` | Step 2 |
| `OCI_PRIVATE_KEY` | Step 2 |
| `OCI_REGION` | Step 2 |
| `TS_MS_PROVIDER_OAUTH_CLIENT_ID` | Step 6 |
| `TS_MS_PROVIDER_OAUTH_CLIENT_SECRET` | Step 6 |
| `B2_MASTER_KEY_ID` | Backblaze B2 master/admin key (with `writeKeys` + `listKeys`) |
| `B2_MASTER_KEY` | Backblaze B2 master/admin key secret |
| `HEALTHCHECKS_API_KEY` | healthchecks.io project API key (Settings → API Access → "API key (read/write)") |

### Folder `/server`
| Secret name | Added in |
|-------------|----------|
| `TELEGRAM_BOT_TOKEN` | Step 8 |
| `TELEGRAM_CHAT_ID` | Step 8 |

_Terraform creates the bucket-scoped restic application key, the healthchecks.io
heartbeat check, and the restic password, then writes `B2_ACCOUNT_ID`,
`B2_ACCOUNT_KEY`, `RESTIC_REPOSITORY`, `RESTIC_PASSWORD`,
`HEALTHCHECKS_HEARTBEAT_CHECK_UUID`, and `HEALTHCHECKS_API_KEY` into the runtime
project. Ansible's `install-backup.yml` reads them and renders
`docker-services/backup.env`._

---

## Step 13 — Terraform: Provision the Server 📋

```bash
cd terraform
terraform init -backend-config=backend.hcl
terraform plan -var='cloud_provider=oci'
terraform apply -var='cloud_provider=oci'
```

This creates: OCI instance, VCN, security list, DNS records, Tailscale auth key,
and a runtime Infisical project populated with generated service secrets.

Note the server's public IP from the output. Cloud-init will run on first boot — wait
approximately 2 minutes before proceeding.

---

## Step 14 — Ansible: Initial Server Configuration 📋

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

## Step 15 — Ansible: Storage and Services 📋

```bash
# Create /docker-data directory structure
ansible-playbook playbooks/setup-storage.yml -e target=oci-main

# Render and deploy all service compose files, pull images, start services
ansible-playbook playbooks/deploy-versions.yml -e target=oci-main
```

---

## Step 16 — Ansible: Maintenance Configuration 📋

```bash
# Configure unattended-upgrades with pre/post-reboot hooks
ansible-playbook playbooks/configure-unattended-upgrades.yml -e target=oci-main

# Install backup orchestrator and cron job
ansible-playbook playbooks/install-backup.yml -e target=oci-main
```

---

## Step 17 — Manual: Uptime Kuma 📋

_See the Uptime Kuma Setup section in CLAUDE.md for full instructions._

1. Log in at `https://status-admin.<your-domain>`
2. Create admin account
3. Add Telegram notification channel (bot token + chat ID from Infisical)
4. Add HTTP monitors for each service (5 min interval, 3 retries)
5. Add healthchecks.io push monitor

---

## Step 18 — Manual: Beszel Agent Bootstrap 📋

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

1. Change `cert_resolver: staging` → `production` in `host_vars/<hostname>.yml`
2. Run `ansible-playbook playbooks/deploy-versions.yml -e target=<hostname>`
3. Traefik will request production certificates automatically

---

## Notes on Disaster Recovery

Failing over to a new cloud server after primary server failure is a separate procedure
requiring shared Restic credentials and is not covered here. See CLAUDE.md for a summary
of that flow.
