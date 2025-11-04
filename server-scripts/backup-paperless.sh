#!/bin/bash
set -euo pipefail



# 📍 CONFIGURATION
DATE=$(date +%F_%H-%M)
BACKUP_DATA_PATH="/swintronics-data/volumes/paperless/export"


exec >/swintronics-data/logs/cron/paperless-backup."${DATE}".log 2>&1

date +"🕓 Starting Paperless backup at %Y-%m-%d %H:%M:%S"

cd /home/neil/swintronics/docker-services
# shellcheck disable=SC1091
. .env
# shellcheck disable=SC1091
. ./paperless/docker-compose.env
# shellcheck disable=SC1091
. ./backup.env

# Export the paperless data
docker compose exec -T webserver document_exporter ../export


# 📦 Run Restic backup
echo "Backing up snapshot with Restic..."
# shellcheck disable=SC2086
restic backup "${BACKUP_DATA_PATH}" 
restic forget  --keep-daily 7 --keep-weekly 4 --keep-monthly 3 --prune
restic check

# Notify Uptime Kuma of success
curl -fsS -o /dev/null --retry 3 "${KUMA_PAPERLESS_PUSH_URL}" || echo "Uptime Kuma ping failed"
date +"✅ Backup complete at %Y-%m-%d %H:%M:%S"
exit 0

# ❌ Error handler
# shellcheck disable=SC2317
trap 'echo "❌ Backup failed at $(date +%Y-%m-%d\ %H:%M:%S)"; exit 1' ERR