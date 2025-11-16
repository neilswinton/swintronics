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
SOURCE_SUBVOLUME_PATH="/swintronics-data/volumes/uptime-kuma"
SNAP_DIR="/swintronics-data/snapshots/uptime-kuma/nightly"
RESTIC_SERVICE_TAG="kuma"
SERVICES="uptime-kuma"
SERVICE_DIRECTORY="/home/neil/swintronics/docker-services/uptime-kuma"
LOG_DIRECTORY="/swintronics-data/logs/cron/uptime-kuma"

if $debug; then
    set -x
else
    exec >"${LOG_DIRECTORY}/backup.${DATE}".log 2>&1
fi 

date +"🕓 Starting Immich backup at %Y-%m-%d %H:%M:%S"

cd "${SERVICE_DIRECTORY}"

# shellcheck disable=SC1091
. .env

# shellcheck disable=SC1091
. ../backup.env

# 🧹 Clean up previous snapshot if it exists
test -d "${SNAP_DIR}" && btrfs property set -ts "${SNAP_DIR}" ro false && btrfs subvolume delete "${SNAP_DIR}"


# Tell Healthchecks.io to pause monitoring the cluster heartbeat from uptime-kuma
curl --header "X-Api-Key: ${HEARTBEAT_HEALTHCHECK_API_KEY}" --request POST --data "" "${HEARTBEAT_HEALTHCHECK_PAUSE_URL}"

# 🛑 Stop containers
echo "Stopping containers..."

# shellcheck disable=SC2086
docker compose stop ${SERVICES}

# 📸 Create Btrfs snapshot
echo "Creating Btrfs snapshot at ${SNAP_DIR}..."
btrfs subvolume snapshot -r "${SOURCE_SUBVOLUME_PATH}" "${SNAP_DIR}"

# 🚀 Restart containers
echo "Restarting containers..."
# shellcheck disable=SC2086
docker compose start ${SERVICES}

# Tell Healthchecks.io to resume monitoring the cluster heartbeat from uptime-kuma
curl --header "X-Api-Key: ${HEARTBEAT_HEALTHCHECK_API_KEY}" --request POST --data "" "${HEARTBEAT_HEALTHCHECK_RESUME_URL}"

# 📦 Run Restic backup
echo "Backing up snapshot with Restic..."
restic backup --tag "${RESTIC_SERVICE_TAG}" --tag "${DATE}" "${SNAP_DIR}" 
restic forget --tag "${RESTIC_SERVICE_TAG}" --keep-daily 7 --keep-weekly 2 --prune
restic check
exit 0 


# ❌ Error handler
# shellcheck disable=SC2317
echo 'Kuma backup failed' ERR && exit 1