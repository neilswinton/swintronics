#!/bin/bash
set -euo pipefail

# Default value
debug=false

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --debug)
      debug=true
      ;;
    --no-debug)
      debug=false
      ;;
    *)
      echo "Unknown option: $arg"
      echo "Usage: $0 [--debug|--no-debug]"
      exit 1
      ;;
  esac
done

# 📍 CONFIGURATION
DATE=$(date +%F_%H-%M)
RESTIC_SERVICE_TAG="docker-services"
SOURCE_PATH="/home/neil/swintronics/docker-services"

if $debug; then
    set -x
else
    exec >/swintronics-data/logs/cron/docker-services/docker-backup."${DATE}".log 2>&1
fi 

date +"🕓 Starting docker backup at %Y-%m-%d %H:%M:%S"

cd "${SOURCE_PATH}"

# shellcheck disable=SC1091
. ../docker-services/backup.env

# 📦 Run Restic backup
echo "Backing up ${RESTIC_SERVICE_TAG} with Restic..."
restic backup --tag "${RESTIC_SERVICE_TAG}" --tag "${DATE}" "${SOURCE_PATH}" 
restic forget --tag "${RESTIC_SERVICE_TAG}" --keep-daily 7 --keep-weekly 4 --prune
restic check

# Notify Uptime Kuma of success
curl -fsS -o /dev/null --retry 3 "${KUMA_DOCKERFILE_PUSH_URL}" || echo "Uptime Kuma ping failed"
date +"✅ Backup complete at %Y-%m-%d %H:%M:%S"
exit 0

# ❌ Error handler
# shellcheck disable=SC2317
trap 'echo "❌ Backup failed at $(date +%Y-%m-%d\ %H:%M:%S)"; exit 1' ERR