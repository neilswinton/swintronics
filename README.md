# Swintronics

Run your own home server: private photo backup, searchable document storage,
smart home control — on hardware you own, without handing your data to a
cloud service.

This project is a complete, working recipe for that server. It includes the
apps themselves, plus the unglamorous parts most home-server guides skip:
automatic offsite backups, uptime monitoring, and an alert on your phone when
something breaks.

It can run on almost anything — a spare laptop, a mini PC, or a cloud server.
It has been used on [Hetzner](https://www.hetzner.com/cloud) and
[Oracle Cloud](https://www.oracle.com/cloud/free/) (including Oracle's free
tier), both far more affordable than Amazon AWS or Microsoft Azure. (Mine runs
on a retired Dell XPS 13.)

## Why

Installing a self-hosted app is easy. Keeping it — and your family's photos —
safe for years is the hard part. A typical home server accumulates
undocumented tweaks and quietly stops backing up, and when the disk dies
there's no way back. This project takes a different approach: everything is
written down as configuration files, so nothing depends on memory or luck.

- **Rebuildable** — if the hardware dies, a replacement server can be rebuilt
  from this repository and the backups. No archaeology required.
- **Backed up** — nightly encrypted backups go offsite automatically, and a
  watchdog notices if they silently stop.
- **Monitored** — every service is health-checked around the clock, with
  alerts delivered by Telegram.
- **Private by default** — services are reachable only through a personal VPN,
  encrypted end to end. Nothing is exposed to the open internet.
- **No secrets in the open** — passwords and keys live in a secrets manager,
  never in these files.

## What runs on it

| Service | What it does |
|---------|--------------|
| [Immich](https://immich.app) | Private photo and video backup for your phone — the Google Photos replacement |
| [Paperless-ngx](https://docs.paperless-ngx.com) | Scan, index, and search every document you'd otherwise lose in a drawer |
| [Home Assistant](https://www.home-assistant.io) | Smart home control, with [Zigbee2MQTT](https://www.zigbee2mqtt.io) + Mosquitto for Zigbee devices |
| [BentoPDF](https://bentopdf.com) | PDF toolbox — merge, split, convert without uploading to a random website |
| [Gatus](https://gatus.io) | Uptime monitoring and a status page for everything above |
| [Beszel](https://beszel.dev) | Server health at a glance — CPU, memory, disk |
| [Dockhand](https://dockhand.pro) | Web dashboard for the containers everything runs in |
| [Traefik](https://traefik.io) | Routes each service to its own address with automatic HTTPS |
| autoheal | Restarts anything that stops responding |

## Under the hood

For the technically curious: services run as Docker Compose containers, and
two standard automation tools do the heavy lifting.

- **Terraform** (`terraform/`) creates cloud servers, DNS records, and
  generated secrets when deploying beyond your own hardware.
- **Ansible** (`ansible/`) installs and updates everything on the server.
  Service versions are pinned in one file (`ansible/versions.yml`); updating
  a service is a one-line edit plus one command.
- **Backup scripts** (`server-scripts/`) snapshot each service's data with
  restic and report success to healthchecks.io.

## Learn more

- [DEPLOYING.md](DEPLOYING.md) — step-by-step guide to standing up your own
  server, from account signup to running services
- [CLAUDE.md](CLAUDE.md) — architecture reference and operational detail
  (secrets layout, backup/restore, service lifecycle)
