#!/bin/bash

###-------------------------------------------------------------------------###
#                              One Click Install                              #
###-------------------------------------------------------------------------###

# Define lock file and script path
LOCK_FILE="/root/inst_basic_soft_sd.lock"
SCRIPT_PATH="/root/inst_basic_soft_sd.sh"
SERVICE_FILE="/etc/systemd/system/armbian-install.service"
LOG_FILE="/root/inst_basic_soft_sd.log"

# Redirect all output to the log file for debugging
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Script started at $(date)"

# Ensure script persists across reboots
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "Downloading the script to ensure persistence..."
    curl -fsSL https://raw.githubusercontent.com/KLEIN-Technologies/Armbian/main/inst_basic_soft_sd.sh -o "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
fi

# Check if the script is running for the first time
if [ ! -f "$LOCK_FILE" ]; then
    echo "First run detected. Updating system and scheduling reboot..."
    apt update && apt upgrade -y

    # Create a lock file to track first run
    touch "$LOCK_FILE"

    # Create a systemd service to rerun the script after reboot
    echo "Setting up systemd service to rerun script after reboot..."
    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Armbian Auto-Install Script
After=network-online.target

[Service]
ExecStart=/bin/bash $SCRIPT_PATH
Restart=always
Type=simple
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd, enable service, and reboot
    systemctl daemon-reload
    systemctl enable armbian-install.service

    echo "Rebooting now to continue installation..."
    reboot
    exit 0
fi

#---------------------------   Minimum Packages   ----------------------------#

echo "Installing minimum required packages..."
apt install -y sudo htop hdparm curl mc wget unrar samba wsdd2

# Start Web Service Dynamic Discovery
systemctl enable --now wsdd2

mkdir -p /00_SMB
mkdir -p /98_DevOps

#------------------------   Docker (Debian) + Webmin  ------------------------#

echo "Installing Docker..."
# Add Docker's official GPG key
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y

# Install Docker Engine
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Install Portainer-CE
echo "Installing Portainer..."
sudo docker run -d -p 9002:9000 --name portainer --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v sys_portainer:/data portainer/portainer-ce:latest

# Symbolic Link (Docker Volumes)
ln -s /var/lib/docker/volumes/ /99_Volumes

#--------------------------------   Webmin   ---------------------------------#

echo "Installing Webmin..."
curl -o setup-repos.sh https://raw.githubusercontent.com/webmin/webmin/master/setup-repos.sh
yes | sh setup-repos.sh
apt-get install -y webmin --install-recommends

#--------------------------------   Log2RAM   --------------------------------#

echo "Installing Log2RAM..."
echo "deb [signed-by=/usr/share/keyrings/azlux-archive-keyring.gpg] http://packages.azlux.fr/debian/ bookworm main" | sudo tee /etc/apt/sources.list.d/azlux.list
sudo wget -O /usr/share/keyrings/azlux-archive-keyring.gpg https://azlux.fr/repo.gpg
sudo apt update
sudo apt install -y log2ram

# Cleanup: Remove systemd service so it doesn’t run on every boot
echo "Cleaning up systemd service..."
systemctl disable armbian-install.service
rm -f "$SERVICE_FILE"

# Final Reboot
echo "Installation complete. Rebooting the system..."
sudo reboot
