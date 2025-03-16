#!/bin/bash

###-------------------------------------------------------------------------###
#                              One Click Install                              #
###-------------------------------------------------------------------------###

MARKER_FILE="/tmp/first_run_completed"
SCRIPT_PATH="/root/inst_basic_soft_sd.sh"

# Check if the script is running for the first time
if [ ! -f "$MARKER_FILE" ]; then
    echo "First run: Updating system and scheduling reboot..."
    touch "$MARKER_FILE"
    
    # Save a local copy of the script for rerunning after reboot
    curl -fsSL https://raw.githubusercontent.com/KLEIN-Technologies/Armbian/main/inst_basic_soft_sd.sh -o "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"

    # Schedule the script to run again after reboot using cron
    echo "@reboot root /bin/bash $SCRIPT_PATH" > /etc/cron.d/auto_rerun
    chmod 644 /etc/cron.d/auto_rerun

    # Perform update & upgrade
    apt update && apt upgrade -y
    
    # Reboot to continue installation
    reboot
    exit 0
fi

#---------------------------   Minimum Packages   ----------------------------#
apt install -y sudo htop hdparm curl mc wget unrar samba wsdd2

# Start Web Service Dynamic Discovery
systemctl enable --now wsdd2

# Create directories
mkdir -p /00_SMB /98_DevOps

#------------------------   Docker (Debian) + Webmin  ------------------------#

# Add Docker's official GPG key and repository
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \  
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \  
  $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | \  
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y

# Install Docker Engine
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Install Portainer-CE
docker run -d -p 9002:9000 --name portainer --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v sys_portainer:/data portainer/portainer-ce:latest

# Symbolic Link (Docker Volumes)
ln -s /var/lib/docker/volumes/ /99_Volumes

#--------------------------------   Webmin   ---------------------------------#
curl -o setup-repos.sh https://raw.githubusercontent.com/webmin/webmin/master/setup-repos.sh
yes | sh setup-repos.sh
apt-get install -y webmin --install-recommends

#--------------------------------   Log2RAM   --------------------------------#
echo "deb [signed-by=/usr/share/keyrings/azlux-archive-keyring.gpg] http://packages.azlux.fr/debian/ bookworm main" | tee /etc/apt/sources.list.d/azlux.list
wget -O /usr/share/keyrings/azlux-archive-keyring.gpg https://azlux.fr/repo.gpg
apt update
apt install -y log2ram

# Cleanup: Remove auto-rerun
rm -f /etc/cron.d/auto_rerun

# Reboot
reboot
