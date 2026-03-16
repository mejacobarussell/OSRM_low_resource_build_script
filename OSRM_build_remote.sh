#!/bin/bash
# ==============================================================================
#  
#   ██╗   ██╗ ██████╗ ██╗   ██╗██████╗ ██████╗ ██╗████████╗ ██████╗██╗  ██╗██████╗  ██████╗  ██████╗ 
#   ╚██╗ ██╔╝██╔═══██╗██║   ██║██╔══██╗██╔══██╗██║╚══██╔══╝██╔════╝██║  ██║██╔══██╗██╔═══██╗██╔════╝ 
#    ╚████╔╝ ██║   ██║██║   ██║██████╔╝██║  ██║██║   ██║   ██║     ███████║██║  ██║██║   ██║██║      
#     ╚██╔╝  ██║   ██║██║   ██║██╔══██╗██║  ██║██║   ██║   ██║     ██╔══██║██║  ██║██║   ██║██║      
#      ██║   ╚██████╔╝╚██████╔╝██║  ██║██████╔╝██║   ██║   ╚██████╗██║  ██║██████╔╝╚██████╔╝╚██████╔╝ 
#      ╚═╝    ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═════╝ ╚═╝   ╚═╝    ╚═════╝╚═╝  ╚═╝╚═════╝  ╚═════╝ ╚═════╝ 
#                                                                                                    
#                      --- OSRM REMOTE BUILD & DEPLOY ---
#                     USA MLD BUILD - AUTO EDITION v1.7
#      https://github.com/mejacobarussell/OSRM_low_resource_build_script
# ==============================================================================

set -uo pipefail

# --- DEFAULTS ---
CONFIG_FILE="$(dirname "$0")/remote_settings.cfg"
AUTO_RUN=false
OSRM_CONTAINER_NAME=""

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

# --- CONFIGURATION WIZARD ---
if [[ ! -f "$CONFIG_FILE" ]]; then
    log "⚠️ Configuration file not found. Starting Setup Wizard..."
    echo "-------------------------------------------------------"
    read -p "Remote SSH User [root]: " REMOTE_USER
    REMOTE_USER=${REMOTE_USER:-root}
    
    read -p "Remote Host IP/Domain: " REMOTE_HOST
    
    read -p "Remote Build Directory [/mnt/build/osrm_usa]: " REMOTE_DIR
    REMOTE_DIR=${REMOTE_DIR:-/mnt/build/osrm_usa}
    
    read -p "Local Unraid Data Directory [/mnt/user/appdata/osrm_usa]: " LOCAL_DIR
    LOCAL_DIR=${LOCAL_DIR:-/mnt/user/appdata/osrm_usa}
    
    read -p "Enable Pushover Notifications? (y/n): " P_ENABLE
    if [[ "$P_ENABLE" =~ ^[Yy]$ ]]; then
        PUSHOVER_ENABLE=true
        read -p "Pushover User Key: " PUSHOVER_USER_KEY
        read -p "Pushover App Token: " PUSHOVER_APP_TOKEN
        read -p "Pushover Priority (-2 to 2) [0]: " PUSHOVER_PRIORITY
        PUSHOVER_PRIORITY=${PUSHOVER_PRIORITY:-0}
    else
        PUSHOVER_ENABLE=false
        PUSHOVER_USER_KEY=""
        PUSHOVER_APP_TOKEN=""
        PUSHOVER_PRIORITY=0
    fi
    echo "-------------------------------------------------------"

    # Create the file
    cat << EOF > "$CONFIG_FILE"
# --- YourDitchDoc Remote Config ---
REMOTE_USER="$REMOTE_USER"
REMOTE_HOST="$REMOTE_HOST"
REMOTE_DIR="$REMOTE_DIR"
LOCAL_DIR="$LOCAL_DIR"

# --- Pushover Settings ---
PUSHOVER_ENABLE=$PUSHOVER_ENABLE
PUSHOVER_USER_KEY="$PUSHOVER_USER_KEY"
PUSHOVER_APP_TOKEN="$PUSHOVER_APP_TOKEN"
PUSHOVER_PRIORITY=$PUSHOVER_PRIORITY
# ----------------------------------
EOF
    log "✅ Configuration saved to $CONFIG_FILE"
fi

# --- FLAG PARSING ---
while getopts "c:a" opt; do
  case $opt in
    c) CONFIG_FILE="$OPTARG" ;;
    a) AUTO_RUN=true ;;
    *) echo "Usage: $0 [-c config_file] [-a auto_run]"; exit 1 ;;
  esac
done

# --- LOAD SETTINGS ---
source "$CONFIG_FILE"

# --- PUSHOVER FUNCTION ---
send_push() {
    if [[ "${PUSHOVER_ENABLE:-false}" == "true" ]]; then
        curl -s \
          --form-string "token=$PUSHOVER_APP_TOKEN" \
          --form-string "user=$PUSHOVER_USER_KEY" \
          --form-string "message=$1" \
          --form-string "title=YourDitchDoc OSRM" \
          --form-string "priority=$PUSHOVER_PRIORITY" \
          https://api.pushover.net/1/messages.json > /dev/null
    fi
}

# --- 1. DYNAMIC CONTAINER PICKER ---
echo " "
echo "📋 Scanning Unraid for OSRM containers..."
mapfile -t CONTAINERS < <(docker ps --format "{{.Names}}")

if [ ${#CONTAINERS[@]} -eq 0 ]; then
    log "❌ No running Docker containers found! Start OSRM manually once."
    exit 1
fi

echo "Please select the OSRM container to target for this update:"
select choice in "${CONTAINERS[@]}" "Cancel"; do
    case $choice in
        "Cancel") exit 0 ;;
        *) 
            if [[ -n "$choice" ]]; then
                OSRM_CONTAINER_NAME="$choice"
                break
            fi
            ;;
    esac
done

log "Targeting Container: $OSRM_CONTAINER_NAME"

# --- 2. REMOTE BUILD ---
log "Connecting to $REMOTE_HOST to start the build..."
send_push "🚀 Build started on $REMOTE_HOST for $OSRM_CONTAINER_NAME"

ssh "$REMOTE_USER@$REMOTE_HOST" << REMOTE_CMD
    mkdir -p "$REMOTE_DIR"
    cd "$REMOTE_DIR"
    echo "disk=/data/stxxl_cache,128000,syscall" > .stxxl
    
    echo "[REMOTE] Starting Extraction..."
    docker run --rm -v "\$(pwd):/data" osrm/osrm-backend osrm-extract -p /opt/car.lua /data/us-latest.osm.pbf
    
    echo "[REMOTE] Starting Partitioning..."
    docker run --rm -v "\$(pwd):/data" osrm/osrm-backend osrm-partition /data/us-latest.osrm
    
    echo "[REMOTE] Starting Customization..."
    docker run --rm -v "\$(pwd):/data" osrm/osrm-backend osrm-customize /data/us-latest.osrm
    
    echo "[REMOTE] Cleaning up cache..."
    rm -f stxxl_cache .stxxl
REMOTE_CMD

# --- 3. PRE-SYNC STOP (AUTO-LOGIC) ---
echo " "
if [ "$AUTO_RUN" = false ]; then
    read -p "⚠️ Build finished. Ready to STOP and SYNC? (y/n): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        log "Aborted. New files stay on remote server."
        send_push "⚠️ Build finished, but local sync was aborted."
        exit 0
    fi
else
    log "AUTO-RUN active: Proceeding with stop and sync..."
fi

if [ "$(docker ps -q -f name=$OSRM_CONTAINER_NAME)" ]; then
    log "Stopping $OSRM_CONTAINER_NAME..."
    docker stop "$OSRM_CONTAINER_NAME"
fi

# --- 4. SYNC FILES ---
log "Syncing files from remote to Unraid..."
rsync -avz --delete --progress "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/" "$LOCAL_DIR/"

# --- 5. RESTART ---
log "Starting $OSRM_CONTAINER_NAME..."
docker start "$OSRM_CONTAINER_NAME"

# --- 6. VERIFICATION ---
log "Verifying container health..."
sleep 5
LOG_CHECK=$(docker logs --tail 5 "$OSRM_CONTAINER_NAME")
echo "--- LATEST LOGS ---"
echo "$LOG_CHECK"
echo "-------------------"

# --- 7. FINISH ---
echo " "
echo "   ________________"
echo "  |                |____"
echo "  |     RESCUE     |    \ "
echo "  |      [+]       |     \ "
echo "  |________________|______\ "
echo "   (O)              (O)     "
echo " "
log "YourDitchDoc: Rescue Complete."
send_push "✅ OSRM Rescue Complete! $OSRM_CONTAINER_NAME is back online."
