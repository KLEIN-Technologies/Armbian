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
TELEGRAM_BOT_TOKEN="YOUR_TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="YOUR_TELEGRAM_CHAT_ID"
TELEGRAM_API_URL="https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage"

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

# Start notification
send_telegram_notification "🚀 Starting update and upgrade ...

🖥️ $(hostname)  
⏰ $current_time  

✅ Update started successfully"

# Start timer
start_time=$(date +%s)

# Update and upgrade commands
if apt-get update -y; then
    send_telegram_notification "✅ Update completed successfully"
    
    # Perform upgrade
    if apt-get upgrade -y; then
        # Calculate duration
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        minutes=$((duration / 60))
        seconds=$((duration % 60))
        
        send_telegram_notification "✅ Upgrade completed successfully  
🕒 Duration: ${minutes}m ${seconds}s"
    else
        send_telegram_notification "❌ Upgrade failed"
        exit 1
    fi
else
    send_telegram_notification "❌ Update failed"
    exit 1
fi

exit 0
EOL

# Make the script executable
chmod +x "$SCRIPT_PATH"

# Add to crontab (runs every week at 3:00 AM)
(crontab -l 2>/dev/null; echo "0 3 * * 0 $SCRIPT_PATH") | crontab -

echo "Cron job script created at $SCRIPT_PATH"
echo "Cron job scheduled to run every Sunday at 3:00 AM"