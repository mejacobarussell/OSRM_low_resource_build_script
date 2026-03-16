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
#                     USA MLD BUILD - AUTO EDITION v1.2
#      https://github.com/mejacobarussell/OSRM_low_resource_build_script
# ==============================================================================

set -uo pipefail

# --- CONFIGURATION ---
REMOTE_USER="root"
REMOTE_HOST="your.remote.ip"
REMOTE_DIR="/mnt/build/osrm_usa"
LOCAL_DIR="/mnt/array_cache/osrm_usa"
OSRM_CONTAINER_NAME="osrm-usa"
OSRM_IMAGE="osrm/osrm-backend"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

# --- 1. REMOTE BUILD INITIATION ---
log "Connecting to $REMOTE_HOST to start the build..."
ssh "$REMOTE_USER@$REMOTE_HOST" << 'REMOTE_CMD'
    mkdir -p /mnt/build/osrm_usa
    cd /mnt/build/osrm_usa
    
    # STXXL Config for the remote heavy lifting
    echo "disk=/data/stxxl_cache,128000,syscall" > .stxxl
    
    # Run Extract, Partition, Customize
    docker run --rm -v "$(pwd):/data" osrm/osrm-backend osrm-extract -p /opt/car.lua /data/us-latest.osm.pbf
    docker run --rm -v "$(pwd):/data" osrm/osrm-backend osrm-partition /data/us-latest.osrm
    docker run --rm -v "$(pwd):/data" osrm/osrm-backend osrm-customize /data/us-latest.osrm
    
    rm -f stxxl_cache .stxxl
REMOTE_CMD

# --- 2. PULL FILES BACK ---
log "Build finished on remote. Syncing files back to local storage..."
rsync -avz --progress "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/" "$LOCAL_DIR/"

# --- 3. DOCKER MANAGEMENT & DEPLOYMENT ---
echo " "
read -p "⚠️ Build files are local. Ready to stop '$OSRM_CONTAINER_NAME' and update? (y/n): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    log "Update aborted. Files are saved in $LOCAL_DIR."
    exit 0
fi

# Check if container is running
if [ "$(docker ps -q -f name=$OSRM_CONTAINER_NAME)" ]; then
    log "Stopping existing OSRM container..."
    docker stop "$OSRM_CONTAINER_NAME"
    log "Removing old container..."
    docker rm "$OSRM_CONTAINER_NAME"
fi

# --- 4. START THE NEW ENGINE ---
log "Starting the updated OSRM Engine..."
docker run -d \
  --name "$OSRM_CONTAINER_NAME" \
  --restart always \
  -p 5000:5000 \
  -v "$LOCAL_DIR:/data" \
  "$OSRM_IMAGE" \
  osrm-routed --algorithm mld /data/us-latest.osrm

# --- 5. FINISH ---
echo " "
echo "   ________________"
echo "  |                |____"
echo "  |     RESCUE     |    \ "
echo "  |      [+]       |     \ "
echo "  |________________|______\ "
echo "   (O)              (O)     "
echo " "
log "YourDitchDoc: Remote build complete and local container restarted!"
