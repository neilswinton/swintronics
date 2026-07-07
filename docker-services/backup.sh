#!/bin/bash
set -euo pipefail

# Backup orchestrator. Iterates docker-service directories and runs backup
# hooks (backup-prepare, backup-execute, backup-remote) when present.
#
# Phase order:
#   1. backup-prepare  — all services running (exports, DB dumps)
#   2. backup-execute  — btrfs snapshots; each service stops/starts its own
#                        containers as needed
#   3. backup-remote   — all services running (restic upload + health pings)
#
# Usage: backup.sh [--debug]

# ── Configuration ────────────────────────────────────────────────────────────

DOCKER_SERVICES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    local continue_on_error="${2:-false}"
    echo "━━ Phase: ${hook} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    for dir in "${DOCKER_SERVICES}"/*/; do
        # deploy-versions.yml marks disabled_services with a .disabled file;
        # their containers are down, so running hooks would fail or restart them
        if [ -e "${dir}/.disabled" ]; then
            if [ -x "${dir}/${hook}" ]; then
                echo "⏭ ${hook}: $(basename "${dir}") (disabled — skipped)"
            fi
            continue
        fi
        if [ -x "${dir}/${hook}" ]; then
            local service rc=0
            service=$(basename "${dir}")
            echo "▶ ${hook}: ${service}"
            if $debug; then
                (cd "${dir}" && bash -x ./"${hook}") || rc=$?
            else
                (cd "${dir}" && ./"${hook}") || rc=$?
            fi
            if [ $rc -ne 0 ]; then
                if $continue_on_error; then
                    echo "⚠ ${hook} for ${service} failed (rc=${rc}); continuing"
                else
                    return $rc
                fi
            fi
        fi
    done
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

trap 'hc_resume' ERR

# ── Main ─────────────────────────────────────────────────────────────────────

date +"🕓 Backup started at %Y-%m-%d %H:%M:%S"

run_hooks backup-prepare

hc_pause
run_hooks backup-execute
hc_resume

run_hooks backup-remote true

date +"✅ Backup complete at %Y-%m-%d %H:%M:%S"
