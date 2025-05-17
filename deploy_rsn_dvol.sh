#!/bin/bash

# ================================================================
# 🚀 Deployment Script for Docker Volume Backup with Cron
# 📄 Creates sal-rsn_docker_volumes.sh with Telegram + Rotation
# 🕒 Adds Cron Job: Every 3 Hours
# ================================================================

SCRIPT_DIR="/00_SMB/Scripts"
SCRIPT_PATH="${SCRIPT_DIR}/sal-rsn_docker_volumes.sh"
DEPLOY_LOG="${SCRIPT_DIR}/deploy_rsn_dvol.log"

# === Create Script Directory ===
mkdir -p "$SCRIPT_DIR"

# === Write Backup Script ===
cat << 'EOF' > "$SCRIPT_PATH"
#!/bin/bash

# ================================================================
# 🔄 Docker Volumes Backup Script with Telegram & Retention
# 📦 Timestamped Snapshots: docker_vol - YYYY-MM-DD - HHh:MMm
# 📁 Destination: /00_SMB/Docker_Volumes
# 🕒 Runs Every 3 Hours (Suggested via cron)
# 🔔 Sends Telegram notifications with summary and backup duration
# ================================================================

# === CONFIGURATION ===
SOURCE_DIRS=(
    "/var/lib/docker/volumes/iot_haos"
    "/var/lib/docker/volumes/iot_esphome"
    "/var/lib/docker/volumes/lab_haos"
)

DEST_BASE="/00_SMB/Docker_Volumes"
LOG_DIR="/00_SMB/Scripts/Logs"
LOG_FILE="${LOG_DIR}/sal-rsn_docker_volumes.log"
TIMESTAMP=$(date +"%Y-%m-%d - %Hh:%Mm")
BACKUP_NAME="docker_vol - $TIMESTAMP"
BACKUP_DEST="${DEST_BASE}/${BACKUP_NAME}"

# Retention policies
HOURLY_LIMIT=24
DAILY_LIMIT=7
WEEKLY_LIMIT=4
MONTHLY_LIMIT=3

# === TELEGRAM CONFIG ===
TELEGRAM_BOT_TOKEN="7890138907:AAGAGLdi5z7XnBWgVKYHYW1rs9KASCWDcKk"
TELEGRAM_CHAT_ID="8167593683"

# === EXCLUSIONS ===
FOLDER_EXCLUDES=(
    '.esphome'
)
FILE_EXCLUDES=(
    'home-assistant_v2.db'
    'home-assistant_v2.db-shm'
    'home-assistant_v2.db-wal'
)

# === FUNCTIONS ===
send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d text="$message" \
        -d parse_mode="Markdown"
}

prune_old_backups() {
    local FOLDER=$1
    local KEEP=$2
    local PATTERN="docker_vol - *"
    local REMOVED=()

    COUNT=$(find "$FOLDER" -maxdepth 1 -type d -name "$PATTERN" | wc -l)
    if (( COUNT > KEEP )); then
        REMOVE=$(find "$FOLDER" -maxdepth 1 -type d -name "$PATTERN" | sort | head -n $(($COUNT - $KEEP)))
        for OLD in $REMOVE; do
            REMOVED+=("$(basename "$OLD")")
            echo "🗑️ Removing old backup: $OLD" | tee -a "$LOG_FILE"
            rm -rf "$OLD"
        done
    fi
    echo "${REMOVED[@]}"
}

rotate_snapshots() {
    local TYPE=$1
    local LIMIT=$2
    local MATCH_PATTERN="docker_vol - *"
    local PREFIX_DIR="${DEST_BASE}/${TYPE}"

    mkdir -p "$PREFIX_DIR"
    COUNT=$(find "$DEST_BASE" -maxdepth 1 -type d -name "$MATCH_PATTERN" | sort | wc -l)

    if [[ "$TYPE" == "daily" && $COUNT -gt $HOURLY_LIMIT ]]; then
        TARGET=$(find "$DEST_BASE" -maxdepth 1 -type d -name "$MATCH_PATTERN" | sort | sed -n "${HOURLY_LIMIT}p")
        [ -d "$TARGET" ] && mv "$TARGET" "$PREFIX_DIR/"
        echo "📦 Rolled up to 📆 Daily: $(basename "$TARGET")" | tee -a "$LOG_FILE"
    elif [[ "$TYPE" == "weekly" ]]; then
        COUNT=$(find "$PREFIX_DIR" -maxdepth 1 -type d -name "$MATCH_PATTERN" | sort | wc -l)
        if [ $COUNT -gt $DAILY_LIMIT ]; then
            TARGET=$(find "$PREFIX_DIR" -maxdepth 1 -type d -name "$MATCH_PATTERN" | sort | sed -n "${DAILY_LIMIT}p")
            [ -d "$TARGET" ] && mv "$TARGET" "${DEST_BASE}/weekly/"
            echo "📦 Rolled up to 🗓️ Weekly: $(basename "$TARGET")" | tee -a "$LOG_FILE"
        fi
    elif [[ "$TYPE" == "monthly" ]]; then
        COUNT=$(find "${DEST_BASE}/weekly" -maxdepth 1 -type d -name "$MATCH_PATTERN" | sort | wc -l)
        if [ $COUNT -gt $WEEKLY_LIMIT ]; then
            TARGET=$(find "${DEST_BASE}/weekly" -maxdepth 1 -type d -name "$MATCH_PATTERN" | sort | sed -n "${WEEKLY_LIMIT}p")
            [ -d "$TARGET" ] && mv "$TARGET" "${DEST_BASE}/monthly/"
            echo "📦 Rolled up to 📅 Monthly: $(basename "$TARGET")" | tee -a "$LOG_FILE"
        fi
    fi
}

# === START BACKUP ===
mkdir -p "$BACKUP_DEST" "$LOG_DIR"
START_TIME=$(date +%s)

echo "🔁 [$TIMESTAMP] Starting backup..." | tee -a "$LOG_FILE"

FAILED_DIRS=()

for DIR in "${SOURCE_DIRS[@]}"; do
    NAME=$(basename "$DIR")
    DEST_PATH="$BACKUP_DEST/$NAME"
    echo "📦 Backing up $DIR ➡️ $DEST_PATH" | tee -a "$LOG_FILE"

    EXCLUDE_ARGS=()
    for EX in "${FOLDER_EXCLUDES[@]}" "${FILE_EXCLUDES[@]}"; do
        EXCLUDE_ARGS+=("--exclude=$EX")
    done

    if ! rsync -a --delete "${EXCLUDE_ARGS[@]}" "$DIR/" "$DEST_PATH/"; then
        FAILED_DIRS+=("$DIR")
        echo "❌ Backup failed for $DIR" | tee -a "$LOG_FILE"
    fi
done

if [ ${#FAILED_DIRS[@]} -gt 0 ]; then
    send_telegram "❌ *Backup Failed for:* \n\`\`\`\n${FAILED_DIRS[*]}\n\`\`\`\n📅 $TIMESTAMP"
fi

echo "✅ Backup saved to $BACKUP_DEST" | tee -a "$LOG_FILE"

# === PRUNE & ROLLUP ===
REMOVED_HOURLY=$(prune_old_backups "$DEST_BASE" $HOURLY_LIMIT)
rotate_snapshots "daily" $DAILY_LIMIT
REMOVED_DAILY=$(prune_old_backups "${DEST_BASE}/daily" $DAILY_LIMIT)
rotate_snapshots "weekly" $WEEKLY_LIMIT
REMOVED_WEEKLY=$(prune_old_backups "${DEST_BASE}/weekly" $WEEKLY_LIMIT)
rotate_snapshots "monthly" $MONTHLY_LIMIT
REMOVED_MONTHLY=$(prune_old_backups "${DEST_BASE}/monthly" $MONTHLY_LIMIT)

# === FINISH & REPORT ===
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MIN=$((DURATION / 60))
SEC=$((DURATION % 60))

# Combine deleted summary
DELETED_SUMMARY=""
[ -n "$REMOVED_HOURLY" ] && DELETED_SUMMARY+="🕒 *Hourly Deleted:*\n$(echo "$REMOVED_HOURLY" | tr ' ' '\n')\n"
[ -n "$REMOVED_DAILY" ] && DELETED_SUMMARY+="📆 *Daily Deleted:*\n$(echo "$REMOVED_DAILY" | tr ' ' '\n')\n"
[ -n "$REMOVED_WEEKLY" ] && DELETED_SUMMARY+="🗓️ *Weekly Deleted:*\n$(echo "$REMOVED_WEEKLY" | tr ' ' '\n')\n"
[ -n "$REMOVED_MONTHLY" ] && DELETED_SUMMARY+="📅 *Monthly Deleted:*\n$(echo "$REMOVED_MONTHLY" | tr ' ' '\n')\n"
[ -z "$DELETED_SUMMARY" ] && DELETED_SUMMARY="♻️ No old backups deleted."

# === SEND TELEGRAM REPORT ===
send_telegram "$(cat <<EOM
✅ *Docker Volumes Backup Complete*
📅 $TIMESTAMP
📁 Saved to: \`/Docker_Volumes\`
🕒 Duration: ${MIN}m ${SEC}s

${DELETED_SUMMARY}
EOM
)"

echo "✅ [$TIMESTAMP] Backup cycle complete! Took ${MIN}m ${SEC}s" | tee -a "$LOG_FILE"
echo "----------------------------------------------------" >> "$LOG_FILE"
EOF

# === Make Executable ===
chmod +x "$SCRIPT_PATH"
chmod 700 "$SCRIPT_PATH"

# === Add Cron Job ===
CRON_CMD="${SCRIPT_PATH} # rsn_dvol_backup"
( crontab -l 2>/dev/null | grep -v -F "$CRON_CMD" ; echo "0 */3 * * * $CRON_CMD" ) | crontab -

# === Log Deployment ===
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
echo "✅ [$TIMESTAMP] Deployed sal-rsn_docker_volumes.sh and updated cron." | tee -a "$DEPLOY_LOG"
