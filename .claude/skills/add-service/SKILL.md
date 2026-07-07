---
name: add-service
description: Add a new Docker Compose service to the cluster — scaffold the repo config (compose template, service config entries, Gatus monitoring, docs), then deploy. Use when the user says `/add-service <name>` or asks to add/install a new self-hosted service. Args: service name, plus the upstream image or GitHub repo if known. Mirrors /delete-service.
---

# Add Service

Scaffold everything a new service needs in the repo, then deploy it with
`/deploy-and-verify`. Server-side creation (directories, rendered templates,
containers, DNS records) is entirely handled by `deploy-versions.yml` — this
skill's job is the repo config that feeds it.

## 1. Research upstream

- Find the upstream image and its tag scheme (pinned vs floating — see the
  tag strategy comment at the top of `ansible/versions.yml`).
- If upstream publishes a runtime compose file, save it verbatim as
  `ansible/services/<name>/upstream.yml` (repo convention: diffable reference
  copy). If upstream only has build-from-source compose files, skip it and
  note that in the CLAUDE.md upstream-compose list.
- Note what state it keeps: volumes → stateful; config-only or none →
  stateless.

## 2. Scaffold repo files

Use a similar existing service as the pattern (`bentopdf` for a simple
stateless web app, `paperless` for stateful with DB + backups).

- `ansible/services/<name>/compose.yml.j2` — adapt from upstream:
  - image tag from `{{ versions.<name> }}`
  - join the external `proxy` network (defined in
    `docker-services/networks.yml`)
  - Traefik labels for HTTPS routing (`Host(\`<dns-name>.{{ server_domain }}\`)`,
    cert resolver from `{{ cert_resolver }}`) — copy a working service's label
    block
  - healthcheck if the image supports one (autoheal restarts unhealthy
    containers)
  - bind data under `{{ data_disk_mountpoint }}/volumes/<name>/`
- `ansible/services/<name>/.env.j2` — secrets from Infisical
  (`{{ infisical_secrets.secrets.X }}`); if new secrets are needed, tell the
  user to create them in the Runtime project first
- Stateful services with backups: `backup-prepare` / `backup-execute` /
  `backup-remote` hooks (see immich/paperless)

## 3. Wire the config entries

- `ansible/versions.yml` — version entry with the upstream releases URL and
  pin rationale comment, matching the file's existing style
- `ansible/playbooks/deploy-versions.yml` — `_service_config` entry: `dir`,
  `dns_names`, `files` list (mark `.env` files `secret: true`, backup hooks
  `executable: true`)
- `ansible/playbooks/setup-storage.yml` — `_service_storage` entry
  (`stateful: true` → btrfs subvolume; `false` → logs dir only)
- `ansible/services/gatus/config.yaml.j2` — endpoint block (copy an existing
  one; use a lightweight health/status URL, Telegram alerts); lowercase keys;
  make `enabled:` conditional on the service key so disabling the service
  also pauses its monitor:
  `enabled: {{ ('<service-key>' not in disabled_services | default([])) | lower }}`
- `CLAUDE.md` — row in the Service Name Mapping table; update the
  upstream-compose convention list

## 4. Ship it

- Feature branch, show the diff, confirm with the user, commit, PR (per the
  git workflow).
- Stateful services: run `setup-storage.yml` before the first deploy so the
  subvolume exists.
- Deploy with `/deploy-and-verify <name>` — it confirms the container is
  actually up, and `deploy-versions.yml` creates the DNS CNAME automatically.

## Verify

- Container running and healthy on the target
- `https://<dns-name>.<server_domain>` serves the UI through Traefik
- Gatus shows the new endpoint green
- For stateful services: data lands under
  `<data_disk_mountpoint>/volumes/<name>/` and, if backups were added, a
  one-shot backup run succeeds end-to-end
