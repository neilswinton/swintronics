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
DAY=$(date +%A)
SOURCE_SUBVOLUME_PATH="/swintronics-data/volumes/immich/library"
SNAP_DIR="/swintronics-data/snapshots/immich/library/backup"
DB_DUMP="${SOURCE_SUBVOLUME_PATH}/immich_db.sql"
RESTIC_SERVICE_TAG="immich"
IMMICH_SERVICES="immich-server immich-machine-learning"

if $debug; then
    set -x
else
    exec >/swintronics-data/logs/cron/immich/photo-backup."${DATE}".log 2>&1
fi 

date +"🕓 Starting Immich backup at %Y-%m-%d %H:%M:%S"

cd /home/neil/swintronics/docker-services/immich-app

# shellcheck disable=SC1091
. .env

# shellcheck disable=SC1091
. ../backup.env

# 🧹 Clean up previous snapshot if it exists
test -d "${SNAP_DIR}" && btrfs property set -ts "${SNAP_DIR}" ro false && btrfs subvolume delete "${SNAP_DIR}"


# 🚦 Notify Healthchecks.io of start
curl -fsS -o /dev/null --retry 3 "${HC_PHOTO_PING_URL}/start" || echo "Healthchecks.io start ping failed"

# Save the image versions to a file so we can match them to the backup later if needed
echo "Saving Immich Docker image versions..."
docker compose images > "${SOURCE_SUBVOLUME_PATH}/immich_docker_images.txt"

# 🛑 Stop Immich containers
echo "Stopping Immich containers..."

# shellcheck disable=SC2086
docker compose stop ${IMMICH_SERVICES}

# 🧱 Ensure Postgres is running
echo "Ensuring Postgres is running..."
docker compose up -d database

# 🗃️ Dump PostgreSQL database
echo "Dumping Immich database to ${DB_DUMP}..."
docker compose exec database pg_dumpall --clean --if-exists -U postgres > $DB_DUMP

# 📸 Create Btrfs snapshot
echo "Creating Btrfs snapshot at ${SNAP_DIR}..."
btrfs subvolume snapshot -r "${SOURCE_SUBVOLUME_PATH}" "${SNAP_DIR}"

# 🚀 Restart Immich containers
echo "Restarting Immich containers..."
# shellcheck disable=SC2086
docker compose start ${IMMICH_SERVICES}


# 📦 Run Restic backup
echo "Backing up snapshot with Restic..."
restic backup --tag "${RESTIC_SERVICE_TAG}" --tag "${DATE}" "${SNAP_DIR}" 
restic forget --tag "${RESTIC_SERVICE_TAG}" --keep-daily 7 --keep-weekly 4 --keep-monthly 3 --prune
restic check
         
# 🗄️ Rename snapshot to day of the week.  Remove previous week's as needed
ARCHIVE_DIR="$(dirname ${SNAP_DIR})/${DAY}"
test -d "${ARCHIVE_DIR}" &&  btrfs property set -ts "${ARCHIVE_DIR}" ro false && btrfs subvolume delete "${ARCHIVE_DIR}"
mv "${SNAP_DIR}"  "${ARCHIVE_DIR}"

# ✅ Notify Healthchecks.io of success
curl -fsS -o /dev/null --retry 3  "${HC_PHOTO_PING_URL}" || echo "Healthchecks.io success ping failed"

# Notify Uptime Kuma of success
curl -fsS -o /dev/null --retry 3  "${KUMA_PHOTO_PUSH_URL}" || echo "Uptime Kuma photo backup ping failed"
date +"✅ Backup complete at %Y-%m-%d %H:%M:%S"
exit 0

# ❌ Error handler
# shellcheck disable=SC2317
trap 'curl -fsS --retry 3 "${HC_PHOTO_PING_URL}/fail" || echo "Healthchecks.io failure ping failed"' ERR