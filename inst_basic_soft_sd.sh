#!/bin/bash

###-------------------------------------------------------------------------###
#                              One Click Install                              #
###-------------------------------------------------------------------------###

MARKER_FILE="/tmp/first_run_completed"
SCRIPT_PATH="/root/inst_basic_soft_sd.sh"
SERVICE_FILE="/etc/systemd/system/install-script.service"

# Save the script locally in case it's run via curl
if [ ! -f "$SCRIPT_PATH" ]; then
    curl -fsSL https://raw.githubusercontent.com/KLEIN-Technologies/Armbian/main/inst_basic_soft_sd.sh -o "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
fi

# If first-time execution, schedule a systemd service and reboot
if [ ! -f "$MARKER_FILE" ]; then
    echo "First run detected. Scheduling script to run after reboot..."
    touch "$MARKER_FILE"

    # Create a systemd service to rerun the script after reboot
    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Armbian Auto-Install Script
After=network.target

[Service]
ExecStart=/bin/bash $SCRIPT_PATH
Type=simple
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # Enable the service and reboot
    systemctl daemon-reload
    systemctl enable install-script.service

    echo "Rebooting now to continue installation..."
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

# Cleanup: Remove systemd service so it doesn’t run on every boot
systemctl disable install-script.service
rm -f "$SERVICE_FILE"

# Reboot
reboot
