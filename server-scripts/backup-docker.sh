#!/bin/bash
set -euo pipefail



# 📍 CONFIGURATION
DATE=$(date +%F_%H-%M)
RESTIC_TAGS="--tag docker --tag ${DATE}"
SOURCE_PATH="/home/neil/swintronics/docker-services"


exec >/swintronics-data/logs/cron/docker-services/docker-backup."${DATE}".log 2>&1

date +"🕓 Starting docker backup at %Y-%m-%d %H:%M:%S"

cd /home/neil/swintronics

. ./docker-services/backup.env

# 📦 Run Restic backup
echo "Backing up docker-services with Restic..."
# shellcheck disable=SC2086
restic backup ${RESTIC_TAGS} "${SOURCE_PATH}" 
restic forget  --keep-daily 7 --keep-weekly 4 --keep-monthly 3 --prune
restic check

# Notify Uptime Kuma of success
curl -fsS -o /dev/null --retry 3 "${KUMA_DOCKERFILE_PUSH_URL}" || echo "Uptime Kuma ping failed"
date +"✅ Backup complete at %Y-%m-%d %H:%M:%S"
exit 0

# ❌ Error handler
# shellcheck disable=SC2317
trap 'echo "❌ Backup failed at $(date +%Y-%m-%d\ %H:%M:%S)"; exit 1' ERR