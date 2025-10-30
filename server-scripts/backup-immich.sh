#!/bin/bash
set -euo pipefail



# 📍 CONFIGURATION
DATE=$(date +%F_%H-%M)
DAY=$(date +%A)
SOURCE_SUBVOLUME_PATH="/swintronics-data/volumes/immich/library"
SNAP_DIR="/swintronics-data/snapshots/immich/library/backup"
DB_DUMP="${SOURCE_SUBVOLUME_PATH}/immich_db.sql"
RESTIC_TAGS="--tag immich --tag ${DATE}"
IMMICH_SERVICES="immich-server immich-machine-learning"

exec >/swintronics-data/logs/cron/photo-backup.${DATE}.log 2>&1

cd /home/neil/swintronics/docker-services
. .env
. ./immich-app/.env
. ./backup.env

# 🧹 Clean up previous snapshot if it exists
test -d "${SNAP_DIR}" && btrfs property set -ts "${SNAP_DIR}" ro false && btrfs subvolume delete "${SNAP_DIR}"

# 🔔 Healthchecks.io URLs
HC_PING_URL="https://hc-ping.com/529e5971-f85c-40a1-80ff-d7af6527b165"

# 🚦 Notify Healthchecks.io of start
curl -fsS -o /dev/null --retry 3 "${HC_PING_URL}/start" || echo "Healthchecks.io start ping failed"

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
# shellcheck disable=SC2086
restic backup ${RESTIC_TAGS} "${SNAP_DIR}" 
restic forget  --keep-daily 7 --keep-weekly 4 --keep-monthly 3 --prune
         
# 🗄️ Rename snapshot to day of the week.  Remove previous week's as needed
ARCHIVE_DIR="$(dirname ${SNAP_DIR})/${DAY}"
test -d "${ARCHIVE_DIR}" &&  btrfs property set -ts "${ARCHIVE_DIR}" ro false && btrfs subvolume delete "${ARCHIVE_DIR}"
mv "${SNAP_DIR}"  "${ARCHIVE_DIR}"

# TODO: second disk
# TODO: remove snaps -- or all but latest
# TODO: healthcheck
# TODO: cronjob

# ✅ Notify Healthchecks.io of success
curl -fsS -o /dev/null --retry 3  "${HC_PING_URL}" || echo "Healthchecks.io success ping failed"

echo "✅ Backup complete: ${DATE}"
exit 0

# ❌ Error handler
trap 'curl -fsS --retry 3 "${HC_PING_URL}/fail" || echo "Healthchecks.io failure ping failed"' ERR