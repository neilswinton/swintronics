# Getting Started with Ansible for Docker Updates

Day-to-day service management for an already-deployed cluster. For standing up
a new server from scratch, see [DEPLOYING.md](../DEPLOYING.md).

## Project Structure

```
ansible/
├── ansible.cfg                    # Ansible configuration
├── requirements.yml               # Required Ansible collections
├── versions.yml                   # Single file tracking all service versions
├── inventory/
│   ├── hosts                      # Server inventory (xps13, future cloud hosts)
│   ├── group_vars/                # Per-cluster variables (paths, domains)
│   └── host_vars/                 # Per-host variables (disk layout, DNS names)
├── playbooks/
│   ├── deploy-versions.yml        # Main deploy playbook
│   ├── install-backup.yml         # Backup orchestrator + cron
│   ├── configure-system-services.yml  # unattended-upgrades, reboot hooks
│   └── delete-service.yml         # Server-side teardown for removed services
└── services/                      # Compose files as Jinja2 templates, per service
```

## Step 1: Install Ansible

On your local machine (the one you use to manage servers):

```bash
sudo apt update
sudo apt install ansible
```

Verify installation:
```bash
ansible --version
```

## Step 2: Install Required Collections

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
```

This installs the `community.docker`, `ansible.posix`, and `infisical.vault` collections.

## Step 3: Configure Infisical

The playbooks authenticate to Infisical using a Machine Identity (Universal Auth).

**One-time setup:**
1. Create a Machine Identity in Infisical with Universal Auth and grant it read access to the Runtime project
2. Copy `ansible/.env.example` to `ansible/.env` and fill in your Client ID, Client Secret, and project UUID
3. Install the required Python package:

```bash
cp ansible/.env.example ansible/.env
# edit ansible/.env with your values
pip install infisicalsdk
```

**Before each session**, source the env file:
```bash
source ansible/.env
```

## Step 4: Test Connectivity

```bash
ansible swintronics -m ping
```

You should see:
```
xps13 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

If this fails, check:
- Is the hostname correct in `inventory/hosts`?
- For remote hosts: can you SSH to the server, and is Tailscale running on both machines?

## Step 5: Update Services

All service versions live in one file: `versions.yml`. To update a service,
edit its version there and run the deploy playbook:

```bash
ansible-playbook playbooks/deploy-versions.yml
```

What happens:
1. Renders every service's Jinja2 templates from `services/` to the server
2. Detects which rendered files actually changed
3. Pulls new images and restarts **only** the changed services (Traefik first)
4. Prunes unused Docker images and ensures DNS CNAMEs exist

If nothing changed, the playbook exits cleanly with no restarts — it's always
safe to run.

Floating tags (e.g. `"stable"`, `"2"`, `"v3.7"`) pick up new releases on pull;
pinned tags (e.g. `"0.18.7"`) only change when you edit `versions.yml`. See the
comments at the top of `versions.yml` for the tag strategy per service.

## Common Commands

**Check what would change (dry run):**
```bash
ansible-playbook playbooks/deploy-versions.yml --check
```

**Target a specific cluster** (default is all clusters):
```bash
ansible-playbook playbooks/deploy-versions.yml -e target=swintronics
```

**Temporarily disable a service** (stop containers, keep files and data):
add its name to `disabled_services` in `versions.yml` and deploy. Remove the
name and deploy again to re-enable. Gatus monitors for the service are
disabled and re-enabled on the same deploys.

**Verbose output (for debugging):**
```bash
ansible-playbook playbooks/deploy-versions.yml -v     # or -vvv
```

## Troubleshooting

### "Could not match supplied host pattern"
- Check the host is in `inventory/hosts`
- Try: `ansible-inventory --list` to see all hosts

### "Failed to connect to the host"
- For remote hosts, test SSH directly and check `tailscale status`
- The XPS13 (`xps13`) uses a local connection — no SSH involved

### Infisical login fails
- Did you `source ansible/.env` in this shell?
- Verify the Machine Identity credentials and project UUID in `.env`
- `pip install infisicalsdk` must be installed in the Python Ansible uses

### A service didn't restart after a version bump
- The playbook only restarts services whose rendered files changed — check the
  playbook output for the "Updated: ..." summary line
- Confirm the version key in `versions.yml` matches the service's key in
  `deploy-versions.yml`'s `_service_config` (see the Service Name Mapping
  table in CLAUDE.md)
