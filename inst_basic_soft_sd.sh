#!/bin/bash

###-------------------------------------------------------------------------###
#                              One Click Install                              #
###-------------------------------------------------------------------------###

# Define a persistent lock file location
LOCK_FILE="/root/inst_basic_soft_sd.lock"

# Check if the script is being run for the first time or after a reboot
if [ ! -f "$LOCK_FILE" ]; then
    echo "First run: Updating and upgrading the system..."
    apt update && apt upgrade -y

    # Create a persistent lock file to indicate the script has been run
    touch "$LOCK_FILE"

    # Schedule the script to run again after reboot
    echo "Scheduling script to run after reboot..."
    (crontab -l 2>/dev/null; echo "@reboot curl -fsSL https://raw.githubusercontent.com/KLEIN-Technologies/Armbian/main/inst_basic_soft_sd.sh | bash") | crontab -

    # Reboot the system
    echo "Rebooting the system..."
    reboot
fi

#---------------------------   Minimum Packages   ----------------------------#

echo "Installing minimum required packages..."
apt install sudo -y              # sudo
apt install htop -y              # htop
apt install hdparm -y            # HDParm
apt install curl -y              # CuRL Install
apt install mc -y                # Midnight Commander
apt install wget -y              # Wget Installer
apt install unrar -y             # Unrar
apt-get install samba -y         # Samba Server

apt install wsdd2 -y             # Web Service Dynamic Discovery
systemctl start wsdd2            # Start Web Service Dynamic Discovery
systemctl status wsdd2           # Status Web Service Dynamic Discovery

mkdir -p /00_SMB                 # Create DATA directory
mkdir -p /98_DevOps

#------------------------   Docker (Debian) + Webmin  ------------------------#

echo "Installing Docker..."
#-- Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

#-- Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y

#-- Install Docker Engine
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

# Install Portainer-Ce
echo "Installing Portainer..."
sudo docker run -d -p 9002:9000 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v sys_portainer:/data portainer/portainer-ce:latest

#-- Symbolic Link (Docker Volumes)
ln -s /var/lib/docker/volumes/ /99_Volumes

#--------------------------------   Webmin   ---------------------------------#

echo "Installing Webmin..."
curl -o setup-repos.sh https://raw.githubusercontent.com/webmin/webmin/master/setup-repos.sh
yes | sh setup-repos.sh

apt-get install webmin --install-recommends -y

#--------------------------------   Log2RAM   --------------------------------#

echo "Installing Log2RAM..."
echo "deb [signed-by=/usr/share/keyrings/azlux-archive-keyring.gpg] http://packages.azlux.fr/debian/ bookworm main" | sudo tee /etc/apt/sources.list.d/azlux.list
sudo wget -O /usr/share/keyrings/azlux-archive-keyring.gpg  https://azlux.fr/repo.gpg
sudo apt update
sudo apt install log2ram -y

# Clean up the lock file and cron job
echo "Cleaning up..."
rm -f "$LOCK_FILE"
crontab -l | grep -v "@reboot curl -fsSL https://raw.githubusercontent.com/KLEIN-Technologies/Armbian/main/inst_basic_soft_sd.sh | bash" | crontab -

# Final Reboot
echo "Installation complete. Rebooting the system..."
sudo reboot