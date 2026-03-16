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
#                     USA MLD BUILD - COLLISION AWARE v2.9
#      https://github.com/mejacobarussell/OSRM_low_resource_build_script
# ==============================================================================

set -uo pipefail

# --- DEFAULTS ---
DEFAULT_CFG="$(dirname "$0")/remote_settings.cfg"
CONFIG_FILE=""
AUTO_RUN=false

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

get_os_name() {
    [ -f /etc/os-release ] && grep ^NAME /etc/os-release | cut -d'"' -f2 | awk '{print $1}' || echo "Linux"
}

# --- FLAG PARSING ---
while getopts ":c:a" opt; do
  case $opt in
    c) CONFIG_FILE="$OPTARG" ;;
    a) AUTO_RUN=true ;;
    :) CONFIG_FILE="$DEFAULT_CFG" ;;
    \?) exit 1 ;;
  esac
done

[[ -z "$CONFIG_FILE" ]] && CONFIG_FILE="$DEFAULT_CFG"

# --- CONFIGURATION LOGIC ---
if [[ ! -f "$CONFIG_FILE" ]] || { echo "⚙️  Config '$CONFIG_FILE' exists."; read -p "   Overwrite? (y/n): " RECONF && [[ "$RECONF" =~ ^[Yy]$ ]]; }; then
    log "🚀 Starting Guided Setup Wizard..."
    echo "-------------------------------------------------------"
    LOCAL_OS=$(get_os_name)
    read -p "Enter Agent Name [$LOCAL_OS]: " AGENT_NAME
    AGENT_NAME_CLEAN=$(echo "${AGENT_NAME:-$LOCAL_OS}" | tr -cd '[:alnum:]_-')
    AGENT_ID="${AGENT_NAME_CLEAN}_${LOCAL_OS}"
    
    read -p "Remote SSH User [root]: " REMOTE_USER; REMOTE_USER=${REMOTE_USER:-root}
    read -p "Remote Host IP: " REMOTE_HOST
    read -p "Remote Build Directory [/mnt/build/osrm_usa]: " REMOTE_DIR; REMOTE_DIR=${REMOTE_DIR:-/mnt/build/osrm_usa}
    read -p "Local appdata Directory [/mnt/user/appdata/osrm_usa]: " LOCAL_DIR; LOCAL_DIR=${LOCAL_DIR:-/mnt/user/appdata/osrm_usa}
    
    echo "--- Resource Allocation ---"
    read -p "CPU Cores [10]: " R_CPUS; R_CPUS=${R_CPUS:-10}
    read -p "RAM Limit [6g]: " R_RAM; R_RAM=${R_RAM:-6g}
    read -p "STXXL Cache (MB) [128000]: " R_STXXL; R_STXXL=${R_STXXL:-128000}

    echo "--- Pushover Notification Settings ---"
    read -p "Enable Pushover? (y/n): " P_ENABLE
    if [[ "$P_ENABLE" =~ ^[Yy]$ ]]; then
        P_ON=true; read -p "User Key: " P_USER; read -p "App Token: " P_TOKEN
        echo "Select Priority (-2 to 2):"
        read -p "Priority [0]: " P_PRIO; P_PRIO=${P_PRIO:-0}
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
PUSHOVER_PRIORITY=$P_PRIO
EOF
    log "✅ Config saved to $CONFIG_FILE"
fi

source "$CONFIG_FILE"

send_push() {
    [[ "$PUSHOVER_ENABLE" == "true" ]] && curl -s --form-string "token=$PUSHOVER_APP_TOKEN" --form-string "user=$PUSHOVER_USER_KEY" --form-string "message=[$AGENT_ID] $1" --form-string "title=YourDitchDoc OSRM" --form-string "priority=$PUSHOVER_PRIORITY" https://api.pushover.net/1/messages.json > /dev/null
}

# --- 1. PICK REMOTE ---
[[ -z "${REMOTE_HOSTS+x}" ]] && REMOTE_HOSTS=()
if [ ${#REMOTE_HOSTS[@]} -gt 1 ]; then
    echo "🌐 Choose Build Server:"
    select remote in "${REMOTE_HOSTS[@]}" "Cancel"; do [ "$remote" == "Cancel" ] && exit 0; [[ -n "$remote" ]] && SELECTED_REMOTE="$remote" && break; done
else
    SELECTED_REMOTE="${REMOTE_HOSTS[0]}"
fi

# --- 2. REMOTE STATUS CHECK ---
log "🔍 Checking remote server status..."
BUSY_AGENTS=$(ssh "$REMOTE_USER@$SELECTED_REMOTE" "docker ps --format '{{.Names}}' | grep 'osrm-' | sed 's/osrm-.*-//' | sort -u")

if [[ -n "$BUSY_AGENTS" ]]; then
    echo "-------------------------------------------------------"
    echo "⚠️  WARNING: Remote server is currently BUSY!"
    echo "   Active Build(s) detected from: $BUSY_AGENTS"
    echo "-------------------------------------------------------"
    read -p "   Do you want to proceed anyway? (y/n): " PROCEED
    [[ ! "$PROCEED" =~ ^[Yy]$ ]] && exit 0
fi

# --- 3. LOCAL CONTAINER PICKER ---
mapfile -t CONTAINERS < <(docker ps --format "{{.Names}}")
[ ${#CONTAINERS[@]} -eq 0 ] && log "❌ No Docker containers!" && exit 1
echo "Select target local container:"
select choice in "${CONTAINERS[@]}" "Cancel"; do [ "$choice" == "Cancel" ] && exit 0; [[ -n "$choice" ]] && OSRM_CONTAINER_NAME="$choice" && break; done

# --- 4. REMOTE BUILD ---
log "Agent $AGENT_ID: Requesting build on $SELECTED_REMOTE..."
send_push "🚀 Remote Build Starting"

ssh "$REMOTE_USER@$SELECTED_REMOTE" << REMOTE_CMD
    mkdir -p "$REMOTE_DIR"; cd "$REMOTE_DIR"
    [ ! -f "us-latest.osm.pbf" ] && wget https://download.geofabrik.de/north-america/us-latest.osm.pbf
    echo "disk=/data/stxxl_cache,$STXXL_SIZE,syscall" > .stxxl
    
    docker run --rm --name "osrm-extract-$AGENT_ID" --memory="$REMOTE_RAM" --cpus="$REMOTE_CPUS" -v "\$(pwd):/data" osrm/osrm-backend osrm-extract -p /opt/car.lua --threads "$REMOTE_CPUS" /data/us-latest.osm.pbf
    docker run --rm --name "osrm-partition-$AGENT_ID" --memory="$REMOTE_RAM" --cpus="$REMOTE_CPUS" -v "\$(pwd):/data" osrm/osrm-backend osrm-partition --threads "$REMOTE_CPUS" /data/us-latest.osrm
    docker run --rm --name "osrm-customize-$AGENT_ID" --memory="$REMOTE_RAM" --cpus="$REMOTE_CPUS" -v "\$(pwd):/data" osrm/osrm-backend osrm-customize --threads "$REMOTE_CPUS" /data/us-latest.osrm
    
    rm -f stxxl_cache .stxxl
REMOTE_CMD

# --- 5. DEPLOY ---
[ "$AUTO_RUN" = false ] && { echo " "; read -p "⚠️ Ready to sync to Agent $AGENT_ID? (y/n): " CONFIRM; [[ ! "$CONFIRM" =~ ^[Yy]$ ]] && exit 0; }

log "Agent $AGENT_ID: Cycling $OSRM_CONTAINER_NAME..."
docker stop "$OSRM_CONTAINER_NAME"
rsync -avz --delete --progress "$REMOTE_USER@$SELECTED_REMOTE:$REMOTE_DIR/" "$LOCAL_DIR/"
docker start "$OSRM_CONTAINER_NAME"

log "YourDitchDoc: Rescue Complete."
send_push "✅ Map Update Complete!"
