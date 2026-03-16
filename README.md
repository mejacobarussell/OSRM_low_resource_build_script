# 🚑 YourDitchDoc: OSRM Remote Builder (v2.9)

A powerful, resource-aware bash script designed for **Unraid users** to build massive OSRM (Open Source Routing Machine) map files on a remote "Powerhouse" server. 

Building the USA map requires significant RAM and CPU. This script allows your low-resource Unraid server to outsource the build, track progress via named containers, and automatically sync the finished data back home.

---

## 📥 Quick Install
Run this command in your Unraid Terminal to download the script and set permissions:

```bash
wget -O OSRM_build_remote.sh [https://raw.githubusercontent.com/mejacobarussell/OSRM_low_resource_build_script/refs/heads/main/OSRM_build_remote.sh](https://raw.githubusercontent.com/mejacobarussell/OSRM_low_resource_build_script/refs/heads/main/OSRM_build_remote.sh) && chmod 777 OSRM_build_remote.sh
