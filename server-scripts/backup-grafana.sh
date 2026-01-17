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

# shellcheck disable=SC1091
. /home/neil/swintronics/docker-services/backup.env

# 📍 CONFIGURATION
DATE=$(date +%F_%H-%M)
DOCKER_SERVICE_NAME="grafana"
RESTIC_SERVICE_TAG="${DOCKER_SERVICE_NAME}"
COMPOSE_DIRECTORY_PATH="/home/neil/swintronics/docker-services/monitoring"
BACKUP_DATA_PATH="${DOCKER_VOLUMES_ROOT}/${DOCKER_SERVICE_NAME}"

if $debug; then
    set -x
else
    exec >"${DOCKER_CRON_LOGS_ROOT}/${RESTIC_SOURCE_TAG}/nightly.${DATE}".log 2>&1
fi 

date +"🕓 Starting ${RESTIC_SERVICE_TAG} backup at %Y-%m-%d %H:%M:%S"

cd "${COMPOSE_DIRECTORY_PATH}"

# Stop grafana
docker compose stop "${DOCKER_SERVICE_NAME}"

# 📦 Run Restic backup
echo "Backing up ${RESTIC_SERVICE_TAG} with Restic..."
restic backup --tag "${RESTIC_SERVICE_TAG}" --tag "${DATE}" "${BACKUP_DATA_PATH}" 
restic forget --tag "${RESTIC_SERVICE_TAG}" --keep-daily 7 --keep-weekly 4 --prune
restic check

# Restart grafana
docker compose start "${DOCKER_SERVICE_NAME}"

date +"✅ Backup complete at %Y-%m-%d %H:%M:%S"
exit 0

# ❌ Error handler
# shellcheck disable=SC2317
trap 'echo "❌ Backup failed at $(date +%Y-%m-%d\ %H:%M:%S)"; exit 1' ERR