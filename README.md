# 🚑 YourDitchDoc: OSRM Remote Builder (v2.9)

A powerful, resource-aware bash script designed for **Unraid users** to build massive OSRM (Open Source Routing Machine) map files on a remote "Powerhouse" server. 

Building the USA map requires significant RAM and CPU. This script allows your low-resource Unraid server to outsource the build, track progress via named containers, and automatically sync the finished data back home.

---

## 📥 Quick Install
Run this command in your Unraid Terminal to download the script and set permissions:

```bash
wget -O OSRM_build_remote.sh [https://raw.githubusercontent.com/mejacobarussell/OSRM_low_resource_build_script/refs/heads/main/OSRM_build_remote.sh](https://raw.githubusercontent.com/mejacobarussell/OSRM_low_resource_build_script/refs/heads/main/OSRM_build_remote.sh) && chmod 777 OSRM_build_remote.sh

🔑 SSH Setup (Passwordless Access)
To allow the script to work automatically, your Unraid server must be able to talk to the Build Server without a password.

1. Generate SSH Keys on Unraid
Open the Unraid Terminal and run:

Bash
ssh-keygen -t rsa -b 4096
# Press Enter for all prompts (leave passphrase empty)
2. Copy the Key to the Build Server
Replace root and 192.168.x.x with your build server's details:

Bash
ssh-copy-id root@192.168.x.x
Verification: Type ssh root@192.168.x.x. If you log in without a password prompt, you're ready!
