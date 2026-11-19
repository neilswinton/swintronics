# Public host recipe (archived)

From 2026-11-16 to 2026-11-19 the cluster had a second, **public** node: an
OCI ARM instance serving Ente photo sharing on `swintronics.com`, joined to the
tailnet for management only. It worked end to end, but it wasn't solving a
real problem, so it was taken down. The code was removed from `main`, and
this page records where to find it and what was learned.

## Where the code is

| What | Where |
|---|---|
| Last `main` commit with the public host | tag **`public-oci-host-v1`** (`f7c0c25`) |
| Nightly security reboot on a public host (never merged) | tag **`public-oci-host-patching`**, PR #170 |
| Terraform: OCI host, `tag:public` auth key, Ente secrets, Cloudflare cleanup | PR #159 |
| Ansible: `enabled_services` allowlist, `public_host`, OCI host firewall, no Traefik dashboard | PR #160 |
| Ente (`ente`, `ente-api`, `ente-accounts`, `albums`) + Gatus "Public Services" | PR #161 |
| Hawser agent (Dockhand manages the host over the tailnet, no public UI) | PR #162 |
| `ente_disable_registration` | PR #163 |
| Open work at teardown (backups, Beszel, update heartbeats, hardening) | issue #164 and sub-issues |

To bring it back, start from the tag:

```bash
git diff main public-oci-host-v1 --stat           # everything that was removed
git checkout public-oci-host-v1 -- <paths>        # restore selected files
# or revert the decommission PR as a whole
```

The `CLAUDE.md` at the tag has the full "Public Host (OCI)" section, with the
operating notes.

## How it was put together

1. **Terraform** (`cloud_provider = "oci"`, `server_hostname = "oci-pub"`):
   A1.Flex instance + btrfs block volume, a security list that opens only
   `public_web_ports` (443) plus SSH from the control node's IP, an
   `oci-pub.<domain>` A record, and a reusable `tag:public` Tailscale auth key
   stored as `TS_PUBLIC_AUTH_KEY`.
2. **Inventory:** the host sits in its own `[public]` group, deliberately
   *outside* `clusters`, so default-target playbooks never touch it. Always run
   with `-e target=oci`. Ansible connected to the public address with the
   Terraform admin key.
3. **Host vars:** `public_host: true` (Traefik dashboard/API off, no trusted
   forwarded headers), `enabled_services` allowlist, `public_tcp_ports: [443]`,
   `dns_cname_target: oci-pub.<domain>`, `tailscale_tag: public`.
4. **Playbooks:** bootstrap → docker → tailscale → setup-storage →
   deploy-versions, each with `-e target=oci`.
5. **Tailnet policy:** `tag:public` in `tagOwners` (owned by the Terraform
   OAuth client's tag); a grant allowing `tag:public` → `tag:server` on
   tcp:443 only, so a compromised public host can't reach anything else.
6. **Container management:** Hawser in edge mode dials the XPS13's Dockhand
   over the tailnet; token from Dockhand's "Hawser edge" environment, stored as
   `HAWSER_TOKEN`.

## Lessons and gotchas

- **OCI account:** upgrade to Pay As You Go at once, or idle Always Free
  instances get reclaimed. The account was left open and empty (us-ashburn-1
  home region).
- **OCI Ubuntu images ship their own iptables firewall**
  (`/etc/iptables/rules.v4`) on top of the VCN security list. Ports must be
  opened in both (`bootstrap.yml`, `public_tcp_ports`).
- **Port 80 isn't needed:** certificates use the Cloudflare DNS challenge.
- **No apex or wildcard DNS:** the wildcard made every unclaimed name resolve
  to a server; per-service CNAMEs only (kept on `main`).
- **`deploy-versions.yml` starts and then recreates a changed stack**, which
  interrupted Ente's first-run DB migration (issue #166, still open).
- **Patching:** the stock image runs unattended-upgrades but never reboots.
  The XPS13's `configure-system-services.yml` can't simply target a second
  host: its Gatus update endpoints have fixed keys, and its reboot hooks drive
  the XPS13's healthchecks.io heartbeat. See PR #170 and issue #165.
- **Backups:** a public host should get its own restic repo and key, not the
  XPS13's (issue #167).
- **Ente specifics:** photos are E2E-encrypted in an R2 bucket (created by
  hand), so the Postgres DB is the critical state. New accounts get 10 GB; raise
  it with `update subscriptions set storage=...` in `ente-postgres`. Login
  codes go via SMTP2GO when the `ENTE_SMTP_*` secrets exist. Brave Shields
  blocked web uploads until lowered.
