# Infisical Integration Setup

Your playbook is now configured to pull secrets from Infisical Cloud instead of storing them in files.

## Step 1: Add Secrets to Infisical

1. Log into Infisical Cloud
2. Go to project: **Swintronics Runtime**
3. Select environment: **dev**
4. Add these secrets:
   - Key: `HEALTHCHECKS_API_KEY`
     Value: (your healthchecks.io API key)
   - Key: `HEALTHCHECKS_KUMA_CHECK_UUID`
     Value: (your Kuma heartbeat check UUID)

## Step 2: Create Machine Identity Credentials File

On your local machine (where you run Ansible), create `~/.infisical.json`:

```bash
cat > ~/.infisical.json << 'EOF'
{
  "client_id": "your-machine-identity-client-id",
  "client_secret": "your-machine-identity-client-secret"
}
EOF
```

Replace with your actual machine identity credentials.

Secure the file:
```bash
chmod 600 ~/.infisical.json
```

## Step 3: Install Infisical CLI (Required)

The Ansible lookup plugin uses the Infisical CLI under the hood.

```bash
# Install Infisical CLI
curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.deb.sh' | sudo -E bash
sudo apt-get update
sudo apt-get install -y infisical
```

Verify installation:
```bash
infisical --version
```

## Step 4: Test Infisical Connection

Test that you can retrieve secrets:

```bash
infisical secrets get HEALTHCHECKS_API_KEY \
  --projectId="Swintronics Runtime" \
  --env=dev
```

If this works, Ansible will be able to pull secrets too.

## How It Works

When you run the playbook, Ansible:
1. Reads machine identity credentials from `~/.infisical.json`
2. Authenticates with Infisical Cloud
3. Fetches secrets at runtime
4. Uses them in the playbook
5. Secrets are never stored in files or version control

## Testing the Integration

Run a test to verify everything works:

```bash
cd ansible-docker
ansible-playbook playbooks/update-service.yml \
  -e "service_name=immich" \
  -e "new_version=v1.117.0" \
  --check
```

The `--check` flag does a dry run without making changes.

## Troubleshooting

### "Could not find infisical executable"

Install the Infisical CLI (Step 3 above).

### "Authentication failed"

- Check `~/.infisical.json` has correct credentials
- Verify the machine identity has access to the project
- Check project ID is exactly "Swintronics Runtime"

### "Secret not found"

- Verify secrets exist in Infisical
- Check you're using the correct environment (dev)
- Make sure secret names match exactly:
  - `HEALTHCHECKS_API_KEY`
  - `HEALTHCHECKS_KUMA_CHECK_UUID`

### Permission Issues

If the lookup plugin can't read `~/.infisical.json`:
```bash
chmod 600 ~/.infisical.json
```

## For Semaphore

When running through Semaphore, you'll need to:

1. Mount `~/.infisical.json` into the Semaphore container
2. Install Infisical CLI in the Semaphore container
3. Or use environment variables for credentials

See SEMAPHORE-SETUP.md for details on Semaphore integration with Infisical.

## Security Benefits

✅ Secrets never stored in Git
✅ Secrets never in plain text files
✅ Centralized secret management
✅ Audit trail of secret access
✅ Easy rotation - update once in Infisical, works everywhere
✅ Machine identity instead of personal credentials
