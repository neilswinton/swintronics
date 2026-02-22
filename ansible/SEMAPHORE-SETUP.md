# Setting Up Semaphore for Docker Updates

Once you're comfortable running playbooks from the command line, you can add Semaphore for a web UI.

## Prerequisites

1. You've tested the playbooks successfully from CLI
2. Semaphore is installed (using the docker-compose from earlier)
3. You've logged into Semaphore

## Step 1: Add This Project to Semaphore

### Option A: Local Files (Easiest to Start)

1. Copy this entire `ansible-docker` directory to your Semaphore server
2. Place it in the Semaphore playbooks mount: `/opt/semaphore/playbooks/docker-updates/`

### Option B: Git Repository (Recommended for Production)

1. Push this directory to a Git repository
2. In Semaphore: **Repositories** → **New Repository**
3. Configure:
   - Name: "Docker Service Updates"
   - URL: Your Git URL
   - Branch: main
   - Access Key: (if private repo)

## Step 2: Create Key Store Entry

Even though Tailscale handles SSH auth, Semaphore needs a key entry:

1. Go to **Key Store** → **New Key**
2. Type: **None** (since Tailscale handles it)
3. Name: "Tailscale SSH"
4. Save

(Alternatively, if Tailscale SSH doesn't work through Semaphore, add your actual SSH private key here)

## Step 3: Add Inventory

1. Go to **Inventory** → **New Inventory**
2. Name: "Swintronics Servers"
3. Content: Paste from `inventory/hosts`
4. Type: **Static YAML**
5. Save

## Step 4: Create Environment Variables

1. Go to **Environment** → **New Environment**
2. Name: "Production"
3. Variables (JSON format):

```json
{
  "healthchecks_api_key": "your-actual-api-key",
  "healthchecks_check_uuid": "your-kuma-check-uuid",
  "docker_services_path": "/home/neil/swintronics/docker-services"
}
```

4. Save

## Step 5: Create Task Templates

Now create a template for each service you want to manage.

### Example: Update Immich Template

1. Go to **Task Templates** → **New Template**
2. Configure:
   - **Name**: "Update Immich"
   - **Playbook**: `playbooks/update-service.yml`
   - **Inventory**: "Swintronics Servers"
   - **Repository**: Your repository
   - **Environment**: "Production"
   - **Extra Variables**:
   ```json
   {
     "service_name": "immich",
     "new_version": "v1.117.0"
   }
   ```
   - **Description**: "Update Immich to a new version"
3. Save

### Create Templates for Other Services

Repeat for each service, just changing the service_name:

**Paperless:**
```json
{
  "service_name": "paperless-ngx",
  "new_version": "2.13.5"
}
```

**Uptime Kuma:**
```json
{
  "service_name": "kuma",
  "new_version": "1.23.13"
}
```

**Stirling PDF:**
```json
{
  "service_name": "stirling-pdf",
  "new_version": "0.33.0"
}
```

And so on for linkwarden, dozzle, traefik.

## Step 6: Run Your First Update from Semaphore

1. Go to **Task Templates**
2. Click "Update Immich"
3. Click **Run**
4. In the variables screen, change `new_version` to the version you want
5. Click **Run**
6. Watch the real-time logs!

## Using Semaphore Day-to-Day

### To Update a Service:

1. Open Semaphore
2. Click the service template (e.g., "Update Immich")
3. Click **Run**
4. Edit the `new_version` variable
5. Click **Run**
6. Watch it work!

### Schedule Automatic Updates

You can set up automatic updates (though be careful - test first!):

1. Edit a Task Template
2. Enable **Cron Schedule**
3. Example schedules:
   - `0 2 * * 0` = 2 AM every Sunday
   - `0 3 1 * *` = 3 AM on the 1st of each month

## Tips

### Override Variables Per Run

When you click Run on a template, you can override any variable:
- Change the version
- Change the service name (to update a different service)
- Add debugging flags

### View History

- Each template shows all past runs
- Click any run to see the full log
- See who ran it and when
- Check success/failure status

### Notifications

Set up notifications in Template settings:
- Slack webhook
- Telegram bot
- Email (via SMTP)
- Get notified when updates succeed or fail

## Troubleshooting in Semaphore

### "Repository not found"

If using local files:
- Make sure files are in Semaphore's mounted volume
- Check: `docker exec -it semaphore ls /playbooks`

### "Inventory not found"

- Verify inventory is created in Semaphore
- Check it's selected in the template

### "Variable not defined"

- Check the Environment has your API keys
- Verify the Environment is selected in the template
- Make sure extra variables are valid JSON

### SSH Connection Fails

Tailscale SSH through Semaphore might need special config:
- Try adding your actual SSH key to Key Store
- Or configure Semaphore to use SSH agent forwarding

## Advanced: Generic Update Template

Instead of one template per service, you can create a single generic template:

**Name**: "Update Any Service"
**Extra Variables**:
```json
{
  "service_name": "",
  "new_version": ""
}
```

Then fill in both fields when running. Less convenient but fewer templates to manage.

## Security Note

Your healthchecks.io API key is stored in Semaphore's database, encrypted with the `SEMAPHORE_ACCESS_KEY_ENCRYPTION` key from your `.env` file. Keep that key safe!
