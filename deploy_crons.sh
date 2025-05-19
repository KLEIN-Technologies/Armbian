#!/bin/bash

# deploy_crons.sh - Creates cronjobs.sh script for auto-updating Armbian OS

# Define the target directory and script path
TARGET_DIR="/00_SMB/Scripts"
SCRIPT_PATH="$TARGET_DIR/cronjobs.sh"

# Create the target directory if it doesn't exist
mkdir -p "$TARGET_DIR"

# Create the cronjobs.sh script
cat > "$SCRIPT_PATH" << 'EOL'
#!/bin/bash

# cronjobs.sh - Auto update and upgrade Armbian OS with Telegram notifications

# Telegram bot configuration (replace with your actual values)
TELEGRAM_BOT_TOKEN="7369801782:AAGltfab2_gIlP7l1aOFsxgXmalqUXz4FXw"
TELEGRAM_CHAT_ID="8167593683"
TELEGRAM_API_URL="https://api.telegram.org/bot7369801782:AAGltfab2_gIlP7l1aOFsxgXmalqUXz4FXw/sendMessage"

# Function to send Telegram notification
send_telegram_notification() {
    local message="$1"
    curl -s -X POST "$TELEGRAM_API_URL" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d text="$message" \
        -d parse_mode="Markdown" > /dev/null
}

# Get current time in desired format
current_time=$(date "+%Hh:%Mmin")

# Initialize message
MESSAGE="🚀 System Update Report 🚀

🖥️ Host:* $(hostname)  
⏰ Time:* $current_time  

"

# Start timer
start_time=$(date +%s)

# Update process
MESSAGE+="🔹 Update   Process Started ..."

if apt-get update -y; then
    MESSAGE+=" ✅"
else
    MESSAGE+=" ❌"
    send_telegram_notification "$MESSAGE"
    exit 1
fi

# Add spacing between sections
MESSAGE+="

"

# Upgrade process
MESSAGE+="🔹 Upgrade Process Started ..."

if apt-get upgrade -y; then
    MESSAGE+=" ✅"
else
    MESSAGE+=" ❌"
    send_telegram_notification "$MESSAGE"
    exit 1
fi

# Calculate duration
end_time=$(date +%s)
duration=$((end_time - start_time))
minutes=$((duration / 60))
seconds=$((duration % 60))

# Add final status
MESSAGE+="

🕒 Duration: ${minutes}m ${seconds}s

✅ All operations completed successfully"

# Send the complete message
send_telegram_notification "$MESSAGE"

exit 0
EOL

# Make the script executable
chmod +x "$SCRIPT_PATH"

# Add to crontab (runs every week at 3:00 AM)
(crontab -l 2>/dev/null; echo "0 3 * * 0 $SCRIPT_PATH") | crontab -

echo "Cron job script created at $SCRIPT_PATH"
echo "Cron job scheduled to run every Sunday at 3:00 AM"