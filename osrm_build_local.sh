@echo off
SETLOCAL EnableDelayedExpansion

:: ==============================================================================
::  
::   YourDitchDoc's OSRM LOCAL BUILD SYSTEM
::   USA MLD BUILD - AUTO EDITION v1.0
::   https://github.com/mejacobarussell/OSRM_low_resource_build_script
:: ==============================================================================

:: --- CONFIGURATION ---
SET "WORK_DIR=C:\osrm_usa"
SET "MEMORY=6g"
SET "SWAP_LIMIT=140g"
SET "CPUS=10"
SET "STXXL_SIZE=128000"
SET "OSRM_IMAGE=osrm/osrm-backend"

echo [%DATE% %TIME%] Initializing YourDitchDoc Build...

:: --- 1. DIRECTORY SETUP ---
if not exist "%WORK_DIR%" (
    echo [%DATE% %TIME%] Creating directory %WORK_DIR%
    mkdir "%WORK_DIR%"
    mkdir "%WORK_DIR%\logs"
)
cd /d "%WORK_DIR%"

:: --- 2. STXXL SETUP ---
echo disk=/data/stxxl_cache,%STXXL_SIZE%,syscall > .stxxl
echo [%DATE% %TIME%] STXXL config created.

:: --- 3. STEP 1: EXTRACT ---
echo [%DATE% %TIME%] Starting osrm-extract...
docker run --rm ^
  --name osrm_extract ^
  --memory="%MEMORY%" ^
  --memory-swap="%SWAP_LIMIT%" ^
  --shm-size="2g" ^
  --cpus="%CPUS%" ^
  -v "%WORK_DIR%:/data" ^
  "%OSRM_IMAGE%" ^
  osrm-extract -p /opt/car.lua --threads "%CPUS%" /data/us-latest.osm.pbf

:: --- 4. STEP 2: PARTITION ---
echo [%DATE% %TIME%] Starting osrm-partition...
docker run --rm ^
  --name osrm_partition ^
  --memory="%MEMORY%" ^
  --memory-swap="$SWAP_LIMIT" ^
  --shm-size="2g" ^
  --cpus="%CPUS%" ^
  -v "%WORK_DIR%:/data" ^
  "%OSRM_IMAGE%" ^
  osrm-partition --threads "%CPUS%" /data/us-latest.osrm

:: --- 5. STEP 3: CUSTOMIZE ---
echo [%DATE% %TIME%] Starting osrm-customize...
docker run --rm ^
  --name osrm_customize ^
  --memory="%MEMORY%" ^
  --memory-swap="$SWAP_LIMIT" ^
  --shm-size="2g" ^
  --cpus="%CPUS%" ^
  -v "%WORK_DIR%:/data" ^
  "%OSRM_IMAGE%" ^
  osrm-customize --threads "%CPUS%" /data/us-latest.osrm

:: --- 6. CLEANUP ---
del /f /q stxxl_cache
echo.
echo    ________________
echo   ^|                ^|____
echo   ^|     RESCUE     ^|    \
echo   ^|      [+]       ^|     \
echo   ^|________________^|______\
echo    (O)              (O)
echo.
echo [%DATE% %TIME%] YourDitchDoc: USA map resuscitated!
pause
