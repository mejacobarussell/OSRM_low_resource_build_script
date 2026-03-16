# 🚑 YourDitchDoc: OSRM Remote Builder (v2.9)

A powerful, resource-aware bash script designed for **Unraid users** to build massive OSRM (Open Source Routing Machine) map files on a remote "Powerhouse" server. 

Building the USA map requires significant RAM and CPU. This script allows your low-resource Unraid server to outsource the build, track progress via named containers, and automatically sync the finished data back home.

---

## 📥 Quick Install
Run this command in your Unraid Terminal to download the script and set permissions:

```bash
wget -O OSRM_build_remote.sh [https://raw.githubusercontent.com/mejacobarussell/OSRM_low_resource_build_script/refs/heads/main/OSRM_build_remote.sh](https://raw.githubusercontent.com/mejacobarussell/OSRM_low_resource_build_script/refs/heads/main/OSRM_build_remote.sh) && chmod 777 OSRM_build_remote.sh
```

🔑 SSH Setup (Passwordless Access)To allow the script to work automatically, your Unraid server must be able to talk to the Build Server without a password.

Generate SSH Keys on Unraid 
Open the Unraid Terminal and run: ```hssh-keygen -t rsa -b 4096```
Press Enter for all prompts (leave passphrase empty)

 Copy the Key to the Build ServerReplace root and 192.168.x.x with your build server's details:
```ssh-copy-id root@192.168.x.x```

Verification: Type ```ssh root@192.168.x.x``` 
If you log in without a password prompt, you're ready!

🚀 UsageFirst Run (Setup Wizard)Simply run the script to start the 
Guided Setup: 
```./OSRM_build_remote.sh -c```

The script will detect your OS (Unraid), ask for your remote server details, resource limits (RAM/Cores), and Pushover credentials.

Advanced Flags:
-c custom_name.cfg:
Load/Create a specific config file (useful for building different regions like Europe vs USA).
-a: Auto-Run Mode. Skips the manual "Ready to Sync?" confirmation. Ideal for scheduled cron jobs.

✨ FeaturesCollision Protection: Scans the remote server to see if another Agent is already building a map to prevent CPU overload.Agent Identity: Automatically brands the build with your server's name and OS (e.g., DarylServer_(Unraid)).Named Docker Containers: Remote containers are named osrm-extract-AgentID so you can identify "who is doing what" on the build server.Pushover Alerts: Real-time phone notifications for build start and success.

📉 Pushover Priority SettingsChoose the level that fits your needs:
LevelNameBehavior
-2 LowestNo sound/vibrate, no status bar.
-1 LowSilent status bar entry only.
0 NormalStandard sound and vibration.
1 HighBypasses "Do Not Disturb" / Silent mode.
2 EmergencyRepeating loud alarm until acknowledged.

🛠️ Requirements
Local (Agent): Unraid 6.x+, Docker, rsync.
Remote (Build Server): Any Linux OS with Docker installed and SSH enabled.
Disk Space: Ensure the remote build directory has at least 150GB+ free for USA map processing.

Maintained by: mejacobarussell Jacob Russell NREMTP (YourDitchdoc) www.yourditchdoc.com/ www.EMSTool.com
