#!/bin/bash
set -euo pipefail

# Backup orchestrator. Iterates docker-service directories and runs backup
# hooks (backup-prepare, backup-execute, backup-remote) when present.
#
# Phase order:
#   1. backup-prepare  — all services running (exports, DB dumps)
#   2. backup-execute  — kuma stopped, healthchecks paused (btrfs snapshots;
#                        each service stops/starts its own containers as needed)
#   3. backup-remote   — all services running (restic upload + health pings)
#
# Usage: backup.sh [--debug]

# ── Configuration ────────────────────────────────────────────────────────────

DOCKER_SERVICES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUMA_DIR="${DOCKER_SERVICES}/uptime-kuma"

# ── Common environment ───────────────────────────────────────────────────────

# shellcheck disable=SC1091
. "${DOCKER_SERVICES}/backup.env"

# ── Configuration ────────────────────────────────────────────────────────────

export DATE DAY DATA_MOUNTPOINT
DATE=$(date +%F_%H-%M)
DAY=$(date +%A)
DATA_MOUNTPOINT="${DATA_MOUNTPOINT:-/mnt/docker-data}"
LOG_DIR="${DATA_MOUNTPOINT}/logs/cron"

debug=false
for arg in "$@"; do
  case "$arg" in
    --debug) debug=true ;;
    *) echo "Unknown option: $arg"; echo "Usage: $0 [--debug]"; exit 1 ;;
  esac
done

if $debug; then
    set -x
else
    mkdir -p "${LOG_DIR}"
    exec >"${LOG_DIR}/backup.${DATE}.log" 2>&1
fi

# ── Helpers ──────────────────────────────────────────────────────────────────

run_hooks() {
    local hook="$1"
    echo "━━ Phase: ${hook} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    for dir in "${DOCKER_SERVICES}"/*/; do
        if [ -x "${dir}/${hook}" ]; then
            echo "▶ ${hook}: $(basename "${dir}")"
            if $debug; then
                (cd "${dir}" && bash -x ./"${hook}")
            else
                (cd "${dir}" && ./"${hook}")
            fi
        fi
    done
}

kuma_stop() {
    echo "Stopping Uptime Kuma..."
    (cd "${KUMA_DIR}" && docker compose stop uptime-kuma) || true
}

kuma_start() {
    echo "Starting Uptime Kuma..."
    (cd "${KUMA_DIR}" && docker compose start uptime-kuma) || true
    echo "Waiting for Uptime Kuma to be ready..."
    local attempts=60
    while [ $attempts -gt 0 ]; do
        sleep 2
        curl -fsS -o /dev/null http://localhost:3001 2>/dev/null && return
        attempts=$((attempts - 1))
    done
    echo "Warning: Uptime Kuma did not become ready in time"
}

hc_pause() {
    curl -fsS -o /dev/null --retry 3 \
        --header "X-Api-Key: ${HEARTBEAT_HEALTHCHECK_API_KEY}" \
        --request POST --data "" \
        "${HEARTBEAT_HEALTHCHECK_PAUSE_URL}" || echo "HC pause failed (continuing)"
}

hc_resume() {
    curl -fsS -o /dev/null --retry 3 \
        --header "X-Api-Key: ${HEARTBEAT_HEALTHCHECK_API_KEY}" \
        --request POST --data "" \
        "${HEARTBEAT_HEALTHCHECK_RESUME_URL}" || echo "HC resume failed (continuing)"
}

# Ensure kuma is restarted and HC resumed even if something fails
trap 'kuma_start; hc_resume' ERR

# ── Main ─────────────────────────────────────────────────────────────────────

date +"🕓 Backup started at %Y-%m-%d %H:%M:%S"

run_hooks backup-prepare

kuma_stop
hc_pause

run_hooks backup-execute

kuma_start
hc_resume

run_hooks backup-remote

date +"✅ Backup complete at %Y-%m-%d %H:%M:%S"
