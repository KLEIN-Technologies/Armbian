#!/bin/bash

###-------------------------------------------------------------------------###
#                              One Click Install                             #
###-------------------------------------------------------------------------###

LOCK_FILE="/root/deploy_basic_borg.lock"
SCRIPT_PATH="/root/deploy_basic_borg.sh"
SERVICE_FILE="/etc/systemd/system/armbian-install.service"
LOG_FILE="/root/deploy_basic_borg.log"
LOGIN_NOTICE_FILE="/etc/profile.d/deploy_notice.sh"

# Redirect all output to the log file
exec > >(tee -a "$LOG_FILE") 2>&1
echo "📦 Script started at $(date)"

# Ensure persistence of this script
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "📥 Downloading install script..."
    curl -fsSL https://raw.githubusercontent.com/KLEIN-Technologies/Armbian/main/deploy_basic_borg.sh -o "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
fi

# Create SSH login message notifier if lock file exists
if [ ! -f "$LOCK_FILE" ]; then
    # Remove login notice if script has completed
    rm -f "$LOGIN_NOTICE_FILE"
else
    cat << 'EOF' > "$LOGIN_NOTICE_FILE"
#!/bin/bash
if [ -f "/root/deploy_basic_borg.lock" ]; then
    echo -e "\e[33m⚠️  Install script is still active. Do not interrupt.\e[0m"
    echo -e "\e[34m📜 Script Path: /root/deploy_basic_borg.sh\e[0m"
    echo -e "\e[36m📦 Log: /root/deploy_basic_borg.log\e[0m"
fi
EOF
    chmod +x "$LOGIN_NOTICE_FILE"
fi

# First-run logic
if [ ! -f "$LOCK_FILE" ]; then
    echo "🧠 First run detected. Updating system and preparing reboot..."
    apt update && apt upgrade -y

    touch "$LOCK_FILE"

    echo "🛠️ Creating systemd service..."
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

    systemctl daemon-reload
    systemctl enable armbian-install.service

    echo "🔁 Rebooting now to continue installation..."
    reboot
    exit 0
fi

#------------------------   Base Utilities   ------------------------#
echo "📦 Installing base packages..."
apt install -y sudo htop hdparm curl mc wget unrar borgbackup

mkdir -p /00_SMB /98_DevOps

#------------------------   Docker Setup   ------------------------#
echo "🐳 Installing Docker..."

sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "🌐 Creating Docker network..."
sudo docker network create --driver=bridge --subnet=10.10.10.0/24 klein-technologies

echo "📦 Installing Portainer..."
sudo docker run -d -p 9002:9000 --name portainer --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v system_portainer:/data portainer/portainer-ce:lts

ln -s /var/lib/docker/volumes/ /99_Volumes

#------------------------   Log2RAM   ------------------------#
echo "🧠 Installing Log2RAM..."
echo "deb [signed-by=/usr/share/keyrings/azlux-archive-keyring.gpg] http://packages.azlux.fr/debian/ bookworm main" | sudo tee /etc/apt/sources.list.d/azlux.list
sudo wget -O /usr/share/keyrings/azlux-archive-keyring.gpg https://azlux.fr/repo.gpg
sudo apt update
sudo apt install -y log2ram

#------------------------   Backup Script   ------------------------#
echo "📝 Creating backup script..."
mkdir -p /00_SMB/Scripts /00_SMB/Scripts/Logs/Docker_Volumes

cat <<'EOF' > /00_SMB/Scripts/Backup_Docker_Volumes
#!/bin/bash

REPO="/00_SMB/Docker_Volumes"
LOG_DIR="/00_SMB/Scripts/Logs/Docker_Volumes"
ARCHIVE_DATE=$(date "+%Y-%m-%d - %Hh:%Mm")
ARCHIVE_NAME="OPi5Plus_Volumes - $ARCHIVE_DATE"
LOGFILE="${LOG_DIR}/borg-backup-${ARCHIVE_DATE}.log"
MIN_FREE_MB=1024

TELEGRAM_BOT_TOKEN="your_bot_token_here"
TELEGRAM_CHAT_ID="your_chat_id_here"
send_telegram() {
  local message="$1"
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d text="$message" \
    -d parse_mode="Markdown"
}

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOGFILE") 2>&1
START_EPOCH=$(date +%s)
START_TIME=$(date '+%Y-%m-%d %H:%M:%S')

SOURCES=(
  "/98_DevOps"
  "/97_Test"
  "/var/lib/docker/volumes/lab_esphome"
)

export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes
find "$LOG_DIR" -name "borg-backup-*.log" | sort | head -n -30 | xargs -r rm -f

if [ ! -d "/00_SMB" ]; then
  send_telegram "❌ *[Backup Failed]* /00_SMB is not mounted or missing."
  exit 1
fi

if [ ! -d "$REPO" ]; then
  send_telegram "❌ *[Backup Failed]* Borg repo folder $REPO is missing."
  exit 1
fi

AVAILABLE_MB=$(df --output=avail "$REPO" | tail -1)
if (( AVAILABLE_MB < MIN_FREE_MB )); then
  send_telegram "🛑 *[Backup Failed]* Not enough space in $REPO (only ${AVAILABLE_MB} KB)."
  exit 1
fi

if [ ! -f "$REPO/config" ]; then
  echo "📦 [INFO] Initializing Borg repo at $REPO..."
  borg init --encryption=none "$REPO" || {
    send_telegram "🚫 *[Backup Failed]* Could not initialize repo at $REPO."
    exit 1
  }
fi

echo "🚀 [START] Creating backup: $ARCHIVE_NAME"
borg create \
  --stats \
  --compression "zstd,5" \
  --exclude '**/.esphome' \
  --exclude '**/home-assistant_v2.db' \
  "$REPO::$ARCHIVE_NAME" \
  "${SOURCES[@]}" || {
    send_telegram "💥 *[Backup Failed]* borg create failed for *$ARCHIVE_NAME*"
    exit 1
  }

echo "🧹 [INFO] Pruning old backups..."
borg prune -v --list "$REPO" \
  --keep-hourly=24 \
  --keep-daily=7 \
  --keep-weekly=4 \
  --keep-monthly=3 || {
    send_telegram "⚠️ *[Backup Warning]* prune failed for *$ARCHIVE_NAME*"
    exit 1
  }

END_EPOCH=$(date +%s)
DURATION=$((END_EPOCH - START_EPOCH))
DURATION_MIN=$((DURATION / 60))
END_TIME=$(date '+%Y-%m-%d %H:%M:%S')
LOG_TAIL=$(tail -n 10 "$LOGFILE" | sed 's/*/\\*/g; s/_/\\_/g; s/`/\\`/g')

send_telegram "✅ *[Backup Complete]*  
📁 *Archive:* \`$ARCHIVE_NAME\`  
🕐 *Started:* \`$START_TIME\`  
✅ *Finished:* \`$END_TIME\`  
⏱️ *Duration:* \`${DURATION_MIN} minute(s)\`  
📝 *Last log lines:*  
\`\`\`
$LOG_TAIL
\`\`\`"

echo "✅ [FINISHED] Backup completed at $END_TIME — Duration: ${DURATION_MIN} minute(s)"
EOF

chmod +x /00_SMB/Scripts/Backup_Docker_Volumes

echo "🕒 Adding cron job for backup every 3 hours..."
(crontab -l 2>/dev/null; echo "0 */3 * * * /00_SMB/Scripts/Backup_Docker_Volumes") | crontab -

#------------------------   Cleanup   ------------------------#
echo "🧹 Disabling install service..."
systemctl disable armbian-install.service
rm -f "$SERVICE_FILE"

echo "🧽 Removing SSH login notice..."
rm -f "$LOGIN_NOTICE_FILE"

#------------------------   Final Reboot   ------------------------#
echo "✅ Installation complete. Rebooting system..."
reboot
