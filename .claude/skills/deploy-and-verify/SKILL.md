---
name: deploy-and-verify
description: Deploy Ansible changes and verify they actually landed on the target before reporting success. Use after editing ansible/versions.yml or any ansible/services/*. Catches the "edited playbook but never ran it" and "ran playbook but container crashed" failure modes. Optional arg: a single service name to scope deploy to update-service.yml.
---

# Deploy and Verify

Run the Ansible deploy, then prove the change actually landed on the target host. Do **not** report success based on Ansible's exit code alone — past incidents (Telegram-on-reboot, #56) were caused by undeployed code.

## Workflow

### 1. Identify what's about to change

```bash
cd /home/neil/git/swintronics
git status ansible/ ansible/versions.yml
git diff --stat ansible/
```

Note the touched paths under `ansible/services/<service>/` and any version bumps in `versions.yml`. These are the services to verify in step 3.

### 2. Run the deploy

If the user invoked `/deploy-and-verify <service>` with a service name:

```bash
cd /home/neil/git/swintronics/ansible
source .env
# Look up the new_version from versions.yml if needed:
ansible-playbook playbooks/update-service.yml -e service_name=<service> -e new_version=<version>
```

Otherwise (no arg → multi-service deploy):

```bash
cd /home/neil/git/swintronics/ansible
source .env
ansible-playbook playbooks/deploy-versions.yml
```

If Ansible exits non-zero, stop here and report the failure with the relevant task output. Do **not** continue to verification.

If Ansible exits zero but its summary says `changed=0` for every host AND the git diff in step 1 was non-empty, that's a red flag — Ansible thinks nothing changed but you have local edits. Surface this and ask the user.

### 3. Verify on the target

The target host is read from the inventory — for the XPS13 it's `localhost` (control node *is* the server). For remote targets, prefix the verification commands with `ssh <tailscale-host>` or use `ansible <host> -m shell -a "..."`.

For **each** service identified in step 1, check three things:

**(a) Rendered compose file landed.** The file mtime on the server should be within the last few minutes:

```bash
stat -c '%y %n' /home/neil/swintronics/docker-services/<service-dir>/compose.yml
```

Map service → directory using the table in `CLAUDE.md` (e.g. `immich` → `immich-app`, `kuma` → `uptime-kuma`).

**(b) Container is running.** `State` must be `running`, not `exited`/`restarting`/`created`:

```bash
cd /home/neil/swintronics/docker-services/<service-dir>
docker compose ps --format json | jq '.[] | {Service, State, Status}'
```

If any container is in `restarting`, wait 30s and re-check — if still restarting, pull `docker compose logs --tail=50 <service>` and surface the failure.

**(c) For version bumps: running image tag matches `versions.yml`.**

```bash
docker compose ps --format json | jq -r '.[] | "\(.Service) \(.Image)"'
```

Compare each `<service> <image:tag>` line against the value in `ansible/versions.yml`. Mismatch means the deploy ran but the container didn't restart with the new image — flag it.

### 4. Report

One line per check, pass/fail. If everything passes:

```
deploy-and-verify: <service>
  ✓ ansible playbook completed
  ✓ rendered compose file landed (mtime <Xs ago>)
  ✓ container running (Up <Xs>)
  ✓ image tag matches versions.yml
```

If anything fails, lead with the failure and the next debugging step (usually `docker compose logs` or re-running the playbook with `-vv`).

## What this skill does *not* cover

- Service-specific behavior checks (curl health endpoints, trigger a test notification). Those belong in Gatus/Kuma, not this skill.
- Rollback. If a deploy lands but the container crashes, the operator decides whether to revert `versions.yml` or fix forward.
- Multi-host fan-out. For now, assumes a single target host per invocation.
