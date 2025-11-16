#!/bin/bash
set -euo pipefail

# Default action
action="up"

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --up)
            ;;
        --down)
            action="down"
            ;;
        --debug)
            set -x
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: $0 [--up|--down]"
            exit 1
            ;;
    esac
done

if [ "$action" == "up" ];then

    (cd networking;docker compose up -d)
    for svc in dozzle stirling-pdf immich-app paperless monitoring; do (cd $svc;docker compose up -d);done
    sleep 30
    (cd uptime-kuma;docker compose up -d)
    # Tell Healthchecks.io to resume monitoring the cluster heartbeat from uptime-kuma
    curl --header "X-Api-Key: ${HEARTBEAT_HEALTHCHECK_API_KEY}" --request POST --data "" "${HEARTBEAT_HEALTHCHECK_RESUME_URL}"

else 
    # Tell Healthchecks.io to pause monitoring the cluster heartbeat from uptime-kuma
    curl --header "X-Api-Key: ${HEARTBEAT_HEALTHCHECK_API_KEY}" --request POST --data "" "${HEARTBEAT_HEALTHCHECK_PAUSE_URL}"
    (cd uptime-kuma;docker compose down)
    for svc in dozzle stirling-pdf immich-app paperless monitoring; do (cd $svc;docker compose down);done
    sleep 2
    (cd networking;docker compose down)
fi 


