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
#                     USA MLD BUILD - AUTO EDITION v1.9
#      https://github.com/mejacobarussell/OSRM_low_resource_build_script
# ==============================================================================

set -uo pipefail

# --- DEFAULTS ---
CONFIG_FILE="$(dirname "$0")/remote_settings.cfg"
AUTO_RUN=false
OSRM_CONTAINER_NAME=""
SELECTED_REMOTE=""

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

# --- CONFIGURATION WIZARD ---
if [[ ! -f "$CONFIG_FILE" ]]; then
    log "⚠️ Configuration file not found. Starting Setup Wizard..."
    echo "-------------------------------------------------------"
    read -p "Remote SSH User [root]: " REMOTE_USER
    REMOTE_USER=${REMOTE_USER:-root}
    read -p "Remote Host IP: " REMOTE_HOST
    read -p "Remote Build Directory [/mnt/build/osrm_usa]: " REMOTE_DIR
    REMOTE_DIR=${REMOTE_DIR:-/mnt/build/osrm_usa}
    read -p "Local Unraid Data Directory [/mnt/user/appdata/osrm_usa]: " LOCAL_DIR
    LOCAL_DIR=${LOCAL_DIR:-/mnt/user/appdata/osrm_usa}
    
    read -p "Enable Pushover? (y/n): " P_ENABLE
    if [[ "$P_ENABLE" =~ ^[Yy]$ ]]; then
        P_ON=true; read -p "Pushover User Key: " P_USER; read -p "Pushover App Token: " P_TOKEN; read -p "Priority (0): " P_PRIO
    else
        P_ON=false; P_USER=""; P_TOKEN=""; P_PRIO=0
    fi

    cat << EOF > "$CONFIG_FILE"
# --- YourDitchDoc Remote Config ---
REMOTE_USER="$REMOTE_USER"
REMOTE_HOSTS=("$REMOTE_HOST")
REMOTE_DIR="$REMOTE_DIR"
LOCAL_DIR="$LOCAL_DIR"
# --- Pushover Settings ---
PUSHOVER_ENABLE=$P_ON
PUSHOVER_USER_KEY="$P_USER"
PUSHOVER_APP_TOKEN="$P_TOKEN"
PUSHOVER_PRIORITY=${P_PRIO:-0}
EOF
    log "✅ Configuration saved to $CONFIG_FILE"
fi

# --- LOAD SETTINGS & FLAGS ---
while getopts "c:a" opt; do
  case $opt in
    c) CONFIG_FILE="$OPTARG" ;;
    a) AUTO_RUN=true ;;
    *) exit 1 ;;
  esac
done
source "$CONFIG_FILE"

# --- PUSHOVER FUNCTION ---
send_push() {
    if [[ "${PUSHOVER_ENABLE:-false}" == "true" ]]; then
        curl -s --form-string "token=$PUSHOVER_APP_TOKEN" --form-string "user=$PUSHOVER_USER_KEY" \
        --form-string "message=$1" --form-string "title=YourDitchDoc OSRM" \
        --form-string "priority=$PUSHOVER_PRIORITY" https://api.pushover.net/1/messages.json > /dev/null
    fi
}

# --- 1. PICK REMOTE MACHINE ---
if [ ${#REMOTE_HOSTS[@]} -eq 1 ]; then
    SELECTED_REMOTE="${REMOTE_HOSTS[0]}"
else
    echo "🌐 Choose Build Server:"
    select remote in "${REMOTE_HOSTS[@]}" "Cancel"; do
        case $remote in "Cancel") exit 0 ;; *) [[ -n "$remote" ]] && SELECTED_REMOTE="$remote" && break ;; esac
    done
fi

# --- 2. PICK LOCAL CONTAINER ---
mapfile -t CONTAINERS < <(docker ps --format "{{.Names}}")
if [ ${#CONTAINERS[@]} -eq 0 ]; then log "❌ No containers found!"; exit 1; fi
echo "Select target container:"
select choice in "${CONTAINERS[@]}" "Cancel"; do
    case $choice in "Cancel") exit 0 ;; *) [[ -n "$choice" ]] && OSRM_CONTAINER_NAME="$choice" && break ;; esac
done

# --- 3. REMOTE BUILD & AUTO-DOWNLOAD ---
log "Connecting to $SELECTED_REMOTE..."
send_push "🚀 Build process initiated on $SELECTED_REMOTE"

ssh "$REMOTE_USER@$SELECTED_REMOTE" << REMOTE_CMD
    mkdir -p "$REMOTE_DIR"
    cd "$REMOTE_DIR"
    
    # Check for USA PBF
    if [ ! -f "us-latest.osm.pbf" ]; then
        echo "[REMOTE] ⚠️ us-latest.osm.pbf NOT FOUND! Starting Emergency Download..."
        if command -v wget &> /dev/null; then
            wget https://download.geofabrik.de/north-america/us-latest.osm.pbf
        elif command -v curl &> /dev/null; then
            curl -O https://download.geofabrik.de/north-america/us-latest.osm.pbf
        else
            echo "[REMOTE] ❌ ERROR: Neither wget nor curl found. Cannot download map."
            exit 1
        fi
    fi

    echo "disk=/data/stxxl_cache,128000,syscall" > .stxxl
    
    echo "[REMOTE] Extracting..."
    docker run --rm -v "\$(pwd):/data" osrm/osrm-backend osrm-extract -p /opt/car.lua /data/us-latest.osm.pbf
    
    echo "[REMOTE] Partitioning..."
    docker run --rm -v "\$(pwd):/data" osrm/osrm-backend osrm-partition /data/us-latest.osrm
    
    echo "[REMOTE] Customizing..."
    docker run --rm -v "\$(pwd):/data" osrm/osrm-backend osrm-customize /data/us-latest.osrm
    
    rm -f stxxl_cache .stxxl
REMOTE_CMD

# --- 4. STOP, SYNC, START ---
if [ "$AUTO_RUN" = false ]; then
    read -p "⚠️ Build finished. Ready to STOP and SYNC? (y/n): " CONFIRM
    [[ ! "$CONFIRM" =~ ^[Yy]$ ]] && exit 0
fi

log "Stopping $OSRM_CONTAINER_NAME..."
docker stop "$OSRM_CONTAINER_NAME"

log "Syncing files..."
rsync -avz --delete --progress "$REMOTE_USER@$SELECTED_REMOTE:$REMOTE_DIR/" "$LOCAL_DIR/"

log "Starting $OSRM_CONTAINER_NAME..."
docker start "$OSRM_CONTAINER_NAME"

# --- 5. FINISH ---
log "YourDitchDoc: Rescue Complete."
send_push "✅ OSRM Updated! $OSRM_CONTAINER_NAME is back online."
