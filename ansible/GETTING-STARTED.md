# Getting Started with Ansible for Docker Updates

## Project Structure

```
ansible-docker/
├── ansible.cfg                    # Ansible configuration
├── requirements.yml               # Required Ansible collections
├── inventory/
│   ├── hosts                      # Server inventory
│   └── group_vars/
│       └── all.yml               # Global variables (API keys, paths)
└── playbooks/
    └── update-service.yml        # Main update playbook
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

Navigate to the project directory and install dependencies:

```bash
cd ansible-docker
ansible-galaxy collection install -r requirements.yml
```

This installs the `community.docker`, `ansible.posix`, and `infisical.vault` collections.

## Step 3: Configure Infisical

The playbook authenticates to Infisical using a Machine Identity (Universal Auth).

**One-time setup:**
1. Add secrets to your Infisical project: `HEALTHCHECKS_API_KEY` and `HEALTHCHECKS_KUMA_CHECK_UUID`
2. Create a Machine Identity in Infisical with Universal Auth and grant it read access to the project
3. Copy `ansible/.env.example` to `ansible/.env` and fill in your Client ID, Client Secret, and project UUID

```bash
cp ansible/.env.example ansible/.env
# edit ansible/.env with your values
```

4. Install the required Python package:
```bash
pip install infisicalsdk
```

**Before each session**, source the env file:
```bash
source ansible/.env
```

## Step 4: Test Connectivity

Test if Ansible can connect to your server:

```bash
ansible swintronics -m ping
```

You should see:
```
swintronics-1 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

If this fails, check:
- Can you SSH to the server? `ssh neil@swintronics-1`
- Is Tailscale running on both machines?
- Is the hostname correct in `inventory/hosts`?

## Step 5: Run Your First Update

Test the playbook by updating a service (example: Immich to v1.117.0):

```bash
ansible-playbook playbooks/update-service.yml \
  -e "service_name=immich" \
  -e "new_version=v1.117.0"
```

What happens:
1. Pauses healthchecks.io monitor
2. Stops Uptime Kuma
3. Updates `/home/neil/swintronics/docker-services/immich/.env`
4. Pulls new image
5. Restarts Immich container
6. Waits for container to be running
7. Starts Uptime Kuma back up
8. Resumes healthchecks.io monitor

## Step 6: Update Other Services

For other services, just change the service name and version:

**Paperless:**
```bash
ansible-playbook playbooks/update-service.yml \
  -e "service_name=paperless-ngx" \
  -e "new_version=2.13.5"
```

**Uptime Kuma** (automatically skips stopping/starting itself):
```bash
ansible-playbook playbooks/update-service.yml \
  -e "service_name=kuma" \
  -e "new_version=1.23.13"
```

**Stirling PDF:**
```bash
ansible-playbook playbooks/update-service.yml \
  -e "service_name=stirling-pdf" \
  -e "new_version=0.33.0"
```

## Common Commands

**Check what would change (dry run):**
```bash
ansible-playbook playbooks/update-service.yml \
  -e "service_name=immich" \
  -e "new_version=v1.117.0" \
  --check
```

**See verbose output:**
```bash
ansible-playbook playbooks/update-service.yml \
  -e "service_name=immich" \
  -e "new_version=v1.117.0" \
  -v
```

**Extra verbose (for debugging):**
```bash
ansible-playbook playbooks/update-service.yml \
  -e "service_name=immich" \
  -e "new_version=v1.117.0" \
  -vvv
```

## Troubleshooting

### "Could not match supplied host pattern"
- Check that `swintronics-1` is in `inventory/hosts`
- Try: `ansible-inventory --list` to see all hosts

### "Failed to connect to the host"
- Test SSH: `ssh neil@swintronics-1`
- Check Tailscale is running: `tailscale status`
- Verify hostname resolves: `ping swintronics-1`

### "Failed to import the required Python library (Docker SDK for Python)"
- The server needs Docker SDK: `ssh neil@swintronics-1`
- Then: `sudo apt install python3-docker`

### ".env file not found"
- Check the service path in your inventory
- Verify: `ssh neil@swintronics-1 "ls /home/neil/swintronics/docker-services/immich/.env"`

### "Container not found"
- The container name must match the service name
- Check: `ssh neil@swintronics-1 "docker ps"`
- If container name differs, you'll need to adjust the playbook

## Next Steps

Once you're comfortable running playbooks from the command line, you can:

1. **Set up Semaphore** for a web UI
2. **Create templates** for each service
3. **Run updates with one click** instead of typing commands

But master the CLI first - it's helpful for debugging!

## Understanding the Playbook

The playbook does this in order:

1. **Validate** - Makes sure you provided service_name and new_version
2. **Pause healthchecks** - API call to pause monitoring
3. **Stop Kuma** - Unless we're updating Kuma itself
4. **Backup .env** - Saves current version
5. **Update .env** - Changes IMMICH_VERSION (or whatever service)
6. **Pull image** - Downloads new Docker image
7. **Restart** - Recreates container with new image
8. **Wait** - Ensures container is running
9. **Start Kuma** - Brings monitoring back up
10. **Resume healthchecks** - API call to resume monitoring
11. **Report** - Shows success message

## Service Name to Variable Mapping

The playbook automatically converts service names to variable names:

- `immich` → `IMMICH_VERSION`
- `paperless-ngx` → `PAPERLESS_NGX_VERSION`
- `kuma` → `KUMA_VERSION`
- `stirling-pdf` → `STIRLING_PDF_VERSION`
- `linkwarden` → `LINKWARDEN_VERSION`
- `dozzle` → `DOZZLE_VERSION`
- `traefik` → `TRAEFIK_VERSION`

Make sure your `.env` files use these exact variable names!
