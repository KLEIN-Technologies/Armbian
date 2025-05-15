#!/bin/bash

echo "Starting Proxmox VE installation on Debian 12 (Bookworm)..."

# Step 1: Update System
echo "Updating system..."
apt update && apt upgrade -y

# Step 2: Remove previous Proxmox key if exists
echo "Removing old Proxmox keys..."
rm -f /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg
rm -f /usr/share/keyrings/proxmox-release-bookworm.gpg

# Step 3: Add Proxmox Repository and GPG Key
echo "Adding Proxmox repository..."
echo "deb [signed-by=/usr/share/keyrings/proxmox-release-bookworm.gpg] http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve.list

echo "Downloading and adding Proxmox GPG key..."
curl -fsSL http://download.proxmox.com/debian/proxmox-release-bookworm.gpg | tee /usr/share/keyrings/proxmox-release-bookworm.gpg > /dev/null

# Step 4: Update APT
echo "Updating package lists..."
apt update

# Step 5: Install Proxmox VE
echo "Installing Proxmox VE and dependencies..."
apt install -y proxmox-ve postfix open-iscsi

# Step 6: Remove conflicting packages (if using a desktop environment)
echo "Removing os-prober (if exists)..."
apt remove -y os-prober

# Step 7: Configure GRUB for IOMMU (if needed for PCI passthrough)
echo 'Updating GRUB to enable IOMMU...'
echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on"' >> /etc/default/grub
update-grub

# Step 8: Remove Enterprise Repository (to avoid subscription errors)
echo "Disabling Proxmox Enterprise Repository..."
rm -f /etc/apt/sources.list.d/pve-enterprise.list
apt update

# Step 9: Final Message and Reboot
echo "Installation complete! Please reboot to apply changes."
echo "Rebooting in 10 seconds... Press Ctrl+C to cancel."
sleep 10
reboot
