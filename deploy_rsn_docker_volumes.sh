#!/bin/bash

# ================================================================
# 🛠️ Docker Volumes Backup Script Installer
# 📂 Creates script and sets up 3-hour cron job
# ================================================================

# Configuration
SCRIPT_NAME="sal-rsn_docker_volumes.sh"
SCRIPT_DIR="/00_SMB/Scripts"
SCRIPT_PATH="${SCRIPT_DIR}/${SCRIPT_NAME}"
CRON_JOB="0 */3 * * * ${SCRIPT_PATH}"

# Create the Scripts directory if it doesn't exist
mkdir -p "$SCRIPT_DIR"

# Create the backup script
cat > "$SCRIPT_PATH" << 'INSTALLER_EOF'
#!/bin/bash

# ================================================================
# 🔄 Multi-Folder Docker Volume Backup Script
# 🕒 Hourly Backups with Version Retention & Pruning
# 🗂️ Timestamped Backups (docker_vol - YYYY-MM-DD - HHh:MMm)
# 📁 Destination: /00_SMB/Docker_Volumes
# 📝 Logs: /00_SMB/Scripts/Logs/sal-rsn_docker_volumes.log
# ================================================================

# === CONFIGURATION ===
SOURCE_DIRS=(
    "/var/lib/docker/volumes/lab_haos"
    "/var/lib/docker/volumes/lab_esphome"
    "/var/lib/docker/volumes/zero_haos"
)

# Exclusions - modify these to match your needs
FOLDER_EXCLUDES=(
    "*/cache"
    "*/tmp"
    "*/logs"
    "*/node_modules"
    "*/esphome"
)

FILE_EXCLUDES=(
    "home-assistant_v2.db-wal"
    "home-assistant_v2.db-shm"
    "home-assistant_v2.db"
    "*.log"
    "*.tmp"
)

DEST_BASE="/00_SMB/Docker_Volumes"
LOG_DIR="/00_SMB/Scripts/Logs"
LOG_FILE="${LOG_DIR}/sal-rsn_docker_volumes.log"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M")
FILENAME_SAFE_TIMESTAMP=$(date +"%Y_%m_%d__%Hh_%Mm")
BACKUP_NAME="$FILENAME_SAFE_TIMESTAMP"
BACKUP_DEST="${DEST_BASE}/${BACKUP_NAME}"
HOSTNAME=$(hostname)

# Retention policies
HOURLY_LIMIT=24    # Keep 24 hourly backups (1 day)
DAILY_LIMIT=7      # Keep 7 daily backups
WEEKLY_LIMIT=4     # Keep 4 weekly backups
MONTHLY_LIMIT=3    # Keep 3 monthly backups

# Telegram Config
TELEGRAM_BOT_TOKEN="7890138907:AAGAGLdi5z7XnBWgVKYHYW1rs9KASCWDcKk"
TELEGRAM_CHAT_ID="8167593683"
TELEGRAM_API="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"

# === FUNCTIONS ===
send_telegram() {
    local message="$1"
    local response_file=$(mktemp)
    local status_code
    
    status_code=$(curl -s -X POST "$TELEGRAM_API" \
        -H "Content-Type: application/json" \
        -d "{\"chat_id\":\"$TELEGRAM_CHAT_ID\",\"text\":\"$message\"}" \
        -w "%{http_code}" \
        -o "$response_file" 2>> "$LOG_FILE")
    
    if [ "$status_code" -ne 200 ]; then
        echo "❌ Telegram Error (HTTP $status_code): $(cat "$response_file")" >> "$LOG_FILE"
        rm "$response_file"
        return 1
    fi
    
    rm "$response_file"
    return 0
}

prune_old_backups() {
    local FOLDER=$1
    local KEEP=$2
    local REMOVED=()

    # Skip if directory doesn't exist
    [ ! -d "$FOLDER" ] && return

    COUNT=$(find "$FOLDER" -maxdepth 1 -type d -name "*" | wc -l)
    if (( COUNT > KEEP )); then
        while IFS= read -r OLD; do
            REMOVED+=("$(basename "$OLD")")
            echo "🗑️ Removing old backup: $OLD" | tee -a "$LOG_FILE"
            rm -rf "$OLD"
        done < <(find "$FOLDER" -maxdepth 1 -type d -name "*" | sort | head -n $((COUNT - KEEP)))
    fi
    echo "${REMOVED[@]}"
}

generate_exclusion_args() {
    local args=()
    
    for pattern in "${FOLDER_EXCLUDES[@]}"; do
        args+=("--exclude=$pattern")
    done
    
    for pattern in "${FILE_EXCLUDES[@]}"; do
        args+=("--exclude=$pattern")
    done
    
    echo "${args[@]}"
}

# === MAIN BACKUP ===
{
    echo "🚀 Starting backup at $TIMESTAMP"
    echo "📂 Source directories: ${SOURCE_DIRS[*]}"
    echo "🚫 Exclusions:"
    echo "   Folders: ${FOLDER_EXCLUDES[*]}"
    echo "   Files: ${FILE_EXCLUDES[*]}"
    START_TIME=$(date +%s)
    mkdir -p "$BACKUP_DEST" "$LOG_DIR"

    # Send startup notification
    if ! send_telegram "🔔 Backup script started on $HOSTNAME at $TIMESTAMP"; then
        echo "⚠️ Couldn't send startup notification" | tee -a "$LOG_FILE"
    fi

    # Generate rsync exclusion arguments
    EXCLUSION_ARGS=($(generate_exclusion_args))

    # Backup each volume
    for DIR in "${SOURCE_DIRS[@]}"; do
        if [ ! -d "$DIR" ]; then
            echo "❌ Source directory not found: $DIR" | tee -a "$LOG_FILE"
            send_telegram "❌ Backup Failed: Directory not found - $DIR"
            continue
        fi

        NAME=$(basename "$DIR")
        DEST_PATH="$BACKUP_DEST/$NAME"
        echo "📦 Backing up $DIR ➡️ $DEST_PATH"
        echo "🔍 Using exclusions: ${EXCLUSION_ARGS[*]}"

        if ! rsync -avh --delete "${EXCLUSION_ARGS[@]}" "$DIR/" "$DEST_PATH/"; then
            send_telegram "❌ Backup Failed for $NAME\n📅 $TIMESTAMP"
            echo "❌ Backup failed for $DIR" | tee -a "$LOG_FILE"
            exit 1
        fi
    done

    # Retention management
    echo "🧹 Cleaning up old backups..."
    REMOVED_HOURLY=$(prune_old_backups "$DEST_BASE" $HOURLY_LIMIT)
    REMOVED_DAILY=$(prune_old_backups "${DEST_BASE}/daily" $DAILY_LIMIT)
    REMOVED_WEEKLY=$(prune_old_backups "${DEST_BASE}/weekly" $WEEKLY_LIMIT)
    REMOVED_MONTHLY=$(prune_old_backups "${DEST_BASE}/monthly" $MONTHLY_LIMIT)

    # Calculate duration
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    MIN=$((DURATION / 60))
    SEC=$((DURATION % 60))

    # Prepare deleted summary
    DELETED_SUMMARY=""
    [ -n "$REMOVED_HOURLY" ] && DELETED_SUMMARY+="🕒 Hourly Deleted:\n$(echo "$REMOVED_HOURLY" | tr ' ' '\n')\n"
    [ -n "$REMOVED_DAILY" ] && DELETED_SUMMARY+="📆 Daily Deleted:\n$(echo "$REMOVED_DAILY" | tr ' ' '\n')\n"
    [ -n "$REMOVED_WEEKLY" ] && DELETED_SUMMARY+="🗓️ Weekly Deleted:\n$(echo "$REMOVED_WEEKLY" | tr ' ' '\n')\n"
    [ -n "$REMOVED_MONTHLY" ] && DELETED_SUMMARY+="📅 Monthly Deleted:\n$(echo "$REMOVED_MONTHLY" | tr ' ' '\n')\n"
    [ -z "$DELETED_SUMMARY" ] && DELETED_SUMMARY="♻️ No old backups deleted."

    # Prepare the clean message format
    MESSAGE="✅ Docker Volumes Backup Complete
📅 $TIMESTAMP
📁 Saved to: /Docker_Volumes
📄 File: $BACKUP_NAME
🕒 Duration: ${MIN}m ${SEC}s

${DELETED_SUMMARY}

🖥️ Host: $HOSTNAME"

    # Send completion notification
    if ! send_telegram "$MESSAGE"; then
        echo "⚠️ Couldn't send completion notification" | tee -a "$LOG_FILE"
    fi

    echo "✅ Backup completed successfully in ${MIN}m ${SEC}s"
    echo "--------------------------------------------------"
} >> "$LOG_FILE" 2>&1
INSTALLER_EOF

# Make the script executable
chmod +x "$SCRIPT_PATH"

# Create the Logs directory
mkdir -p "${SCRIPT_DIR}/Logs"

# Add cron job if it doesn't already exist
if ! crontab -l | grep -q "$SCRIPT_PATH"; then
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "✅ Added cron job to run every 3 hours"
else
    echo "ℹ️ Cron job already exists"
fi

echo "✨ Installation complete!"
echo "Script created at: $SCRIPT_PATH"
echo "Cron job schedule:"
echo "$CRON_JOB"