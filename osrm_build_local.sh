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
#                      --- OSRM LOCAL BUILD SYSTEM ---
#                     USA MLD BUILD - AUTO EDITION v1.0
#      https://github.com/mejacobarussell/OSRM_low_resource_build_script
# ==============================================================================

set -uo pipefail

# --- CONFIGURATION ---
WORK_DIR="/mnt/array_cache/osrm_usa"
MEMORY="6g"           # Physical RAM limit
SWAP_LIMIT="140g"     # RAM + Swap limit for Docker
CPUS="10"
STXXL_SIZE="128000"   # 128GB OSRM internal disk cache
OSRM_IMAGE="osrm/osrm-backend"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

# --- 1. DIRECTORY SETUP ---
# Creates the work dir and log dir if they don't exist
if [ ! -d "$WORK_DIR" ]; then
    log "Creating missing directory: $WORK_DIR"
    mkdir -p "$WORK_DIR/logs"
fi
cd "$WORK_DIR"

# --- 2. SYSTEM SWAP CHECK / CREATION ---
TOTAL_SWAP=$(free -g | awk '/Swap:/ {print $2}')

if [ "$TOTAL_SWAP" -lt 100 ]; then
    echo "⚠️  LOW SWAP DETECTED: You only have ${TOTAL_SWAP}GB swap."
    echo "For a USA build on 6GB RAM, we need ~128GB of swap on an NVMe/SSD."
    read -p "Would you like YourDitchDoc to create a 128GB swap file now? (y/n): " MAKE_SWAP
    
    if [[ "$MAKE_SWAP" =~ ^[Yy]$ ]]; then
        read -p "Enter full path for swap file [/mnt/array_cache/swapfile]: " SWAP_PATH
        SWAP_PATH="${SWAP_PATH:-/mnt/array_cache/swapfile}"
        
        log "Allocating 128GB swap file at $SWAP_PATH (this may take a minute)..."
        # fallocate is instant, but some file systems (XFS/ZFS) prefer dd
        sudo fallocate -l 128G "$SWAP_PATH" || sudo dd if=/dev/zero of="$SWAP_PATH" bs=1G count=128
        
        sudo chmod 600 "$SWAP_PATH"
        sudo mkswap "$SWAP_PATH"
        sudo swapon "$SWAP_PATH"
        log "✅ Swap is now active!"
    else
        log "❌ Build aborted. OSRM will crash without sufficient swap."
        exit 1
    fi
fi

# --- 3. STXXL SETUP ---
# Creates the virtual memory expansion for OSRM internals
cat > "$WORK_DIR/.stxxl" << STX
disk=/data/stxxl_cache,$STXXL_SIZE,syscall
STX
log "STXXL config created (Internal Disk Cache)"

# --- 4. STEP 1: EXTRACT ---
log "Starting osrm-extract (Parsing USA PBF)..."
docker run --rm \
  --name osrm_extract \
  --memory="$MEMORY" \
  --memory-swap="$SWAP_LIMIT" \
  --shm-size="2g" \
  --cpus="$CPUS" \
  -v "$WORK_DIR:/data" \
  "$OSRM_IMAGE" \
  osrm-extract -p /opt/car.lua --threads "$CPUS" /data/us-latest.osm.pbf

# --- 5. STEP 2: PARTITION ---
log "Starting osrm-partition (Multi-Level Dijkstra)..."
docker run --rm \
  --name osrm_partition \
  --memory="$MEMORY" \
  --memory-swap="$SWAP_LIMIT" \
  --shm-size="2g" \
  --cpus="$CPUS" \
  -v "$WORK_DIR:/data" \
  "$OSRM_IMAGE" \
  osrm-partition --threads "$CPUS" /data/us-latest.osrm

# --- 6. STEP 3: CUSTOMIZE ---
log "Starting osrm-customize (Metric Calculation)..."
docker run --rm \
  --name osrm_customize \
  --memory="$MEMORY" \
  --memory-swap="$SWAP_LIMIT" \
  --shm-size="2g" \
  --cpus="$CPUS" \
  -v "$WORK_DIR:/data" \
  "$OSRM_IMAGE" \
  osrm-customize --threads "$CPUS" /data/us-latest.osrm

# --- 7. CLEANUP & FINISH ---
log "Build Complete! Cleaning up STXXL cache file..."
rm -f "$WORK_DIR/stxxl_cache"

echo " "
echo "   ________________"
echo "  |                |____"
echo "  |     RESCUE     |    \ "
echo "  |      [+]       |     \ "
echo "  |________________|______\ "
echo "   (O)              (O)     "
echo " "
log "YourDitchDoc: The USA map has been successfully resuscitated!"
