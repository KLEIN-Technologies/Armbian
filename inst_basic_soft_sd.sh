#!/bin/bash

###-------------------------------------------------------------------------###
#                              One Click Install                              #
###-------------------------------------------------------------------------###

MARKER_FILE="/tmp/first_run_completed"

# If the script was already run once, remove marker and continue installation
if [ -f "$MARKER_FILE" ]; then
    echo "Resuming installation after reboot..."
    rm -f "$MARKER_FILE"  # Remove marker
else
    echo "First run: Updating system and scheduling reboot..."
    touch "$MARKER_FILE"
    
    # Update & Upgrade
    apt update && apt upgrade -y

    # Schedule the script to rerun itself after reboot
    chmod +x "$0"
    echo "@reboot root $0" > /etc/cron.d/auto_rerun

    # Reboot
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
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \  
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
