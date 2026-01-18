#!/bin/bash
set -euo pipefail
# Default values
action="up"
wait=30
pull=false
normal_services=("dozzle" "stirling-pdf" "immich-app" "paperless" "monitoring"  "linkwarden" "karakeep-app")

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            set -x
            shift
    ;;

        --up)
            action="up"
            shift
    ;;

        --down)
            action="down"
            shift
    ;;        
        --pull)
            pull=true
            shift
    ;;

        --wait)
            if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                wait="$2"
                shift 2
                else
                    echo "Error: --wait requires a numeric argument"
                    exit 1
                fi
        ;;

            *)
                echo "Unknown option: $1"
                echo "Usage: $0 [--debug|--no-debug] [--wait < seconds > ]"
                exit 1
        ;;
        esac
    done


# shellcheck disable=SC1091
. ./backup.env 

if [ "$action" == "up" ];then

    if $pull; then
        for svc in "${normal_services[@]}"; do (cd $svc;docker compose pull);done
    fi
    
    (cd networking;docker compose up -d)
    for svc in "${normal_services[@]}"; do (echo $svc;cd $svc;docker compose up -d);done
    sleep "$wait"
    (cd uptime-kuma;docker compose up -d)
    # Tell Healthchecks.io to resume monitoring the cluster heartbeat from uptime-kuma
    curl --header "X-Api-Key: ${HEARTBEAT_HEALTHCHECK_API_KEY}" --request POST --data "" "${HEARTBEAT_HEALTHCHECK_RESUME_URL}"

else 
    # Tell Healthchecks.io to pause monitoring the cluster heartbeat from uptime-kuma
    curl --header "X-Api-Key: ${HEARTBEAT_HEALTHCHECK_API_KEY}" --request POST --data "" "${HEARTBEAT_HEALTHCHECK_PAUSE_URL}"
    (cd uptime-kuma;docker compose down)
    for svc in "${normal_services[@]}"; do (cd $svc;docker compose down);done
    sleep 2
    (cd networking;docker compose down)
fi 


