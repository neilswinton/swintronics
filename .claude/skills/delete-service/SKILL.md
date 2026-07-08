---
name: delete-service
description: Completely delete a service — repo config, docs, server files, containers, data, and DNS. Use when the user says `/delete-service <name>` or asks to remove a service entirely (not just disable it; for that, add the service to disabled_services in versions.yml). Existing restic snapshots are preserved. Mirrors /add-service.
---

# Delete Service

Remove a service from the cluster completely: repo config, documentation,
server-side files and state, and DNS. The one thing this must NOT touch is
existing restic snapshots — the service stops being backed up (its backup
hooks are deleted with its compose directory), but old snapshots stay
restorable until pruned separately.

Disabling vs deleting: if the user may want the service back with its data,
add it to `disabled_services` in `ansible/versions.yml` instead. Deletion is
for services that are gone for good.

## 1. Collect the service's identity BEFORE editing anything

Look up the service in `_service_config` in
`ansible/playbooks/deploy-versions.yml` and record:

- `dir` — the compose directory name (often differs from the service key:
  `immich` → `immich-app`, `traefik` → `networking`)
- `dns_names` — the CNAME records to delete (`immich` → `photos`,
  `homeassistant` → `ha`, `zigbee2mqtt` → `z2m`)
- volume directory — from `_service_storage` in
  `ansible/playbooks/setup-storage.yml` (usually matches the service, not the
  compose dir: `immich` → `volumes/immich`)

These parameters feed the playbook in step 3; once step 2 lands, the mapping
is gone from the repo.

## 2. Repo cleanup (feature branch + PR, per the git workflow)

Remove every trace of the service:

- `ansible/versions.yml` — version entry; also remove from `disabled_services`
- `ansible/playbooks/deploy-versions.yml` — `_service_config` entry
- `ansible/playbooks/setup-storage.yml` — `_service_storage` entry
- `ansible/services/<dir>/` — delete the whole directory
- `ansible/services/gatus/config.yaml.j2` — the service's endpoint block(s),
  including any `external-endpoints` backup entries
- `CLAUDE.md` — service-mapping table row and upstream-compose convention
  note; check the Gatus/monitoring docs too
- Grep for stragglers: `grep -rn -i '<name>' . | grep -v .git/`

Show the diff, confirm with the user, commit, open the PR.

## 3. Server teardown (after the PR merges)

```bash
cd ansible && source .env
ansible-playbook playbooks/delete-service.yml \
  -e service_dir=<dir> \
  -e volume_dir=<volume-dir> \
  -e '{"dns_names": ["<name1>", "<name2>"]}'
```

`volume_dir` defaults to `service_dir`; pass it only when they differ. The
playbook stops and removes containers + named volumes, deletes the compose
directory, data volumes, logs, and the local snapshot staging area
(`<data_disk_mountpoint>/snapshots/<volume_dir>`), prunes images, and deletes
the CNAMEs.

Then run `deploy-versions.yml` (or `/deploy-and-verify gatus`) so Gatus is
re-rendered without the deleted service's monitor.

## 4. Manual follow-ups (remind the user)

- Infisical: delete service-specific secrets (e.g. `<SVC>_DB_PASSWORD`,
  `HC_<SVC>_PING_URL`) from the Runtime project
- healthchecks.io: delete the service's check if it had one
- Restic: snapshots tagged `<service>` remain — do NOT delete them; pruning
  old snapshots is a deliberate, separate decision

## Verify

- `grep -rn -i '<name>' .` in the repo comes back clean (settings.local.json
  permission strings are harmless leftovers)
- `docker ps` on the target shows no containers for the service
- The service's directories are gone from `docker-services/` and
  `/docker-data/volumes/`
- `restic snapshots --tag <service>` still lists the old snapshots
