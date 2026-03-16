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
#                     USA MLD BUILD - SMART FLAGS v2.5
#      https://github.com/mejacobarussell/OSRM_low_resource_build_script
# ==============================================================================

set -uo pipefail

# --- DEFAULTS ---
DEFAULT_CFG="$(dirname "$0")/remote_settings.cfg"
CONFIG_FILE="$DEFAULT_CFG"
AUTO_RUN=false
OSRM_CONTAINER_NAME=""
SELECTED_REMOTE=""

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

get_os_name() {
    if [ -f /etc/os-release ]; then
        grep ^NAME /etc/os-release | cut -d'"' -f2 | awk '{print $1}'
    else
        echo "Linux-Generic"
    fi
}

# --- FLAG PARSING ---
# Added a check to handle -c without an argument gracefully
while getopts ":c:a" opt; do
  case $opt in
    c) CONFIG_FILE="$OPTARG" ;;
    a) AUTO_RUN=true ;;
    :) # If -c is provided without an argument, use the default
       log "⚠️ No config file specified with -c. Using default: $DEFAULT_CFG"
       CONFIG_FILE="$DEFAULT_CFG"
       ;;
    \?) echo "Usage: $0 [-c config_file] [-a auto_run]"; exit 1 ;;
  esac
done

# --- CONFIGURATION LOGIC ---
RUN_WIZARD=false

if [[ ! -f "$CONFIG_FILE" ]]; then
    RUN_WIZARD=true
else
    echo "⚙️  Configuration file '$CONFIG_FILE' exists."
    read -p "   Re-run Setup Wizard to overwrite? (y/n): " RECONFIRM
    [[ "$RECONFIRM" =~ ^[Yy]$ ]] && RUN_WIZARD=true
fi

if [ "$RUN_WIZARD" = true ]; then
    log "🚀 Starting Setup Wizard..."
    echo "-------------------------------------------------------"
    LOCAL_OS=$(get_os_name)
    read -p "Enter Agent Name [$LOCAL_OS]: " AGENT_NAME
    AGENT_NAME=${AGENT_NAME:-$LOCAL_OS}
    AGENT_ID="${AGENT_NAME}_(${LOCAL_OS})"
    
    read -p "Remote SSH User [root]: " REMOTE_USER
    REMOTE_USER=${REMOTE_USER:-root}
    read -p "Remote Host IP: " REMOTE_HOST
    read -p "Remote Build Directory [/mnt/build/osrm_usa]: " REMOTE_DIR
    REMOTE_DIR=${REMOTE_DIR:-/mnt/build/osrm_usa}
    read -p "Local Unraid Data Directory [/mnt/user/appdata/osrm_usa]: " LOCAL_DIR
    LOCAL_DIR=${LOCAL_DIR:-/mnt/user/appdata/osrm_usa}
    
    echo "--- Resource Allocation ---"
    read -p "Remote CPU Cores [10]: " R_CPUS
    R_CPUS=${R_CPUS:-10}
    read -p "Remote RAM Limit [6g]: " R_RAM
    R_RAM=${R_RAM:-6g}
    read -p "STXXL Disk Cache Size (MB) [128000]: " R_STXXL
    R_STXXL=${R_STXXL:-128000}

    read -p "Enable Pushover? (y/n): " P_ENABLE
    if [[ "$P_ENABLE" =~ ^[Yy]$ ]]; then
        P_ON=true; read -p "User Key: " P_USER; read -p "App Token: " P_TOKEN; read -p "Priority [0]: " P_PRIO
    else
        P_ON=false; P_USER=""; P_TOKEN=""; P_PRIO=0
    fi

    cat << EOF > "$CONFIG_FILE"
AGENT_ID="$AGENT_ID"
REMOTE_USER="$REMOTE_USER"
REMOTE_HOSTS=("$REMOTE_HOST")
REMOTE_DIR="$REMOTE_DIR"
LOCAL_DIR="$LOCAL_DIR"
REMOTE_CPUS="$R_CPUS"
REMOTE_RAM="$R_RAM"
STXXL_SIZE="$R_STXXL"
PUSHOVER_ENABLE=$P_ON
PUSHOVER_USER_KEY="$P_USER"
PUSHOVER_APP_TOKEN="$P_TOKEN"
PUSHOVER_PRIORITY=${P_PRIO:-0}
EOF
    log "✅ Configuration saved to $CONFIG_FILE"
fi

# --- LOAD & PREVIEW ---
source "$CONFIG_FILE"
if [[ -z "${REMOTE_HOSTS+x}" ]]; then REMOTE_HOSTS=(); fi

echo "-------------------------------------------------------"
echo "🔍 LOADED SETTINGS (Agent: $AGENT_ID)"
echo "   Config: $CONFIG_FILE"
echo "   Remote: ${REMOTE_HOSTS[*]} ($REMOTE_USER)"
echo "   Limits: $REMOTE_CPUS Cores / $REMOTE_RAM RAM"
echo "   Sync:   $LOCAL_DIR"
echo "-------------------------------------------------------"

# --- PUSHOVER ---
send_push() {
    if [[ "${PUSHOVER_ENABLE:-false}" == "true" ]]; then
        curl -s --form-string "token=$PUSHOVER_APP_TOKEN" --form-string "user=$PUSHOVER_USER_KEY" \
        --form-string "message=[$AGENT_ID] $1" --form-string "title=YourDitchDoc OSRM" \
        --form-string "priority=$PUSHOVER_PRIORITY" https://api.pushover.net/1/messages.json > /dev/null
    fi
}

# --- 1. PICK REMOTE ---
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

# --- 3. REMOTE BUILD ---
log "Agent $AGENT_ID: Requesting build on $SELECTED_REMOTE..."
send_push "🚀 Remote Build Starting"

ssh "$REMOTE_USER@$SELECTED_REMOTE" << REMOTE_CMD
    mkdir -p "$REMOTE_DIR"
    cd "$REMOTE_DIR"
    [ ! -f "us-latest.osm.pbf" ] && wget https://download.geofabrik.de/north-america/us-latest.osm.pbf
    echo "disk=/data/stxxl_cache,$STXXL_SIZE,syscall" > .stxxl
    echo "[REMOTE] Extracting..."
    docker run --rm --memory="$REMOTE_RAM" --cpus="$REMOTE_CPUS" -v "\$(pwd):/data" osrm/osrm-backend osrm-extract -p /opt/car.lua --threads "$REMOTE_CPUS" /data/us-latest.osm.pbf
    docker run --rm --memory="$REMOTE_RAM" --cpus="$REMOTE_CPUS" -v "\$(pwd):/data" osrm/osrm-backend osrm-partition --threads "$REMOTE_CPUS" /data/us-latest.osrm
    docker run --rm --memory="$REMOTE_RAM" --cpus="$REMOTE_CPUS" -v "\$(pwd):/data" osrm/osrm-backend osrm-customize --threads "$REMOTE_CPUS" /data/us-latest.osrm
    rm -f stxxl_cache .stxxl
REMOTE_CMD

# --- 4. STOP, SYNC, START ---
if [ "$AUTO_RUN" = false ]; then
    echo " "
    read -p "⚠️ Build finished. Agent $AGENT_ID ready to STOP and SYNC? (y/n): " CONFIRM
    [[ ! "$CONFIRM" =~ ^[Yy]$ ]] && exit 0
fi

log "Agent $AGENT_ID: Stopping $OSRM_CONTAINER_NAME..."
docker stop "$OSRM_CONTAINER_NAME"
log "Agent $AGENT_ID: Syncing files..."
rsync -avz --delete --progress "$REMOTE_USER@$SELECTED_REMOTE:$REMOTE_DIR/" "$LOCAL_DIR/"
log "Agent $AGENT_ID: Starting $OSRM_CONTAINER_NAME..."
docker start "$OSRM_CONTAINER_NAME"

# --- 5. FINISH ---
log "YourDitchDoc: Agent $AGENT_ID Rescue Complete."
send_push "✅ Map Update Complete!"
