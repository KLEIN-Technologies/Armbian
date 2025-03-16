#!/bin/bash

###-------------------------------------------------------------------------###
#                              One Click Install                              #
###-------------------------------------------------------------------------###

# Check if the script is being run for the first time or after a reboot
if [ ! -f /var/run/inst_basic_soft_sd.lock ]; then
    # First run: Update & Upgrade
    apt update && apt upgrade -y
    touch /var/run/inst_basic_soft_sd.lock
    reboot
fi

#---------------------------   Minimum Packages   ----------------------------#

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

mkdir /00_SMB                                        # Create DATA directory
mkdir /98_DevOps

#------------------------   Docker (Debian) + Webmin  ------------------------#

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
sudo docker run -d -p 9002:9000 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v sys_portainer:/data portainer/portainer-ce:latest

#-- Symbolic Link (Docker Volumes)
ln -s /var/lib/docker/volumes/ /99_Volumes

#--------------------------------   Webmin   ---------------------------------#

curl -o setup-repos.sh https://raw.githubusercontent.com/webmin/webmin/master/setup-repos.sh
yes | sh setup-repos.sh

apt-get install webmin --install-recommends -y

#--------------------------------   Log2RAM   --------------------------------#
echo "deb [signed-by=/usr/share/keyrings/azlux-archive-keyring.gpg] http://packages.azlux.fr/debian/ bookworm main" | sudo tee /etc/apt/sources.list.d/azlux.list
sudo wget -O /usr/share/keyrings/azlux-archive-keyring.gpg  https://azlux.fr/repo.gpg
sudo apt update
sudo apt install log2ram -y

# Clean up the lock file
rm -f /var/run/inst_basic_soft_sd.lock

# Final Reboot
sudo reboot