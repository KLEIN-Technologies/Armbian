#!/bin/bash

# Deploy and schedule rs_dvol.sh Docker volume backup script

SCRIPT_PATH="/00_SMB/Scripts/rs_dvol.sh"
DEPLOY_SCRIPT_NAME="rs_dvol.sh"
CRON_JOB="0 */3 * * * $SCRIPT_PATH"

# 1. Create target directory if missing
mkdir -p /00_SMB/Scripts

# 2. Write the rs_dvol.sh script content
cat > "$SCRIPT_PATH" <<'EOF'
#!/bin/bash

# ==============================================
# rs_dvol.sh - Docker Volumes Backup Script
# ==============================================

# =======================
# CONFIGURATION SECTION
# =======================

BACKUP_SOURCES=(
    "/var/lib/docker/volumes/iot_haos"
    "/var/lib/docker/volumes/lab_haos"
    "/var/lib/docker/volumes/zero_haos"
    "/var/lib/docker/volumes/iot_esphome"
)

EXCLUDE_DIRS=(
    "*/.esphome/"
)

EXCLUDE_FILES=(
    "home-assistant_v2.db"
    "home-assistant_v2.db-wal"
    "home-assistant_v2.db-shm"
)

BACKUP_DEST="/00_SMB/Docker_Volumes"
HOURLY_LIMIT=24
COMPRESS_LEVEL=3

TELEGRAM_TOKEN="insert_token_here"
TELEGRAM_CHAT_ID="insert_id_here"
HOSTNAME=$(hostname)

TELEGRAM_LOG="🚀 Starting Docker Volumes Backup...  

🖥️ $HOSTNAME  
⏰ $(date +'%Hh:%Mmin')  
"

# =======================
# FUNCTIONS SECTION
# =======================

send_telegram() {
    local message="$1"
    [ ${#message} -gt 4000 ] && message="${message:0:4000}…"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d text="${message}" > /dev/null
}

verify_backup() {
    local backup_file="$1"
    for i in {1..5}; do
        [ -f "${BACKUP_DEST}/${backup_file}" ] && return 0
        sleep 1
    done
    return 1
}

create_backup() {
    local timestamp=$(date +"%Y_%m_%d__%Hh_%Mm")
    local backup_file="dvol__${timestamp}.tar.gz"
    local temp_dir=$(mktemp -d)
    local retval=0

    echo "📦 Creating backup structure..." >&2

    for source in "${BACKUP_SOURCES[@]}"; do
        local source_name=$(basename "$source")
        echo "🔹 Copying ${source_name}..." >&2

        if [ ! -d "$source" ]; then
            echo "❌ Source not found: $source" >&2
            TELEGRAM_LOG+="❌ Source not found: $source
"
            retval=1
            continue
        fi

        local exclude_args=()
        for dir in "${EXCLUDE_DIRS[@]}"; do
            exclude_args+=(--exclude="$dir")
        done
        for file in "${EXCLUDE_FILES[@]}"; do
            exclude_args+=(--exclude="$file")
        done

        if ! rsync -a "${exclude_args[@]}" "$source" "$temp_dir"; then
            echo "❌ Failed to copy ${source_name}" >&2
            TELEGRAM_LOG+="❌ Failed to copy ${source_name}
"
            retval=1
        fi
    done

    if [ $retval -ne 0 ]; then
        rm -rf "$temp_dir"
        return $retval
    fi

    echo "🗜️ Compressing backup (level ${COMPRESS_LEVEL})..." >&2
    if ! tar -czf "${BACKUP_DEST}/${backup_file}" -C "$temp_dir" .; then
        echo "❌ Compression failed" >&2
        TELEGRAM_LOG+="❌ Compression failed
"
        rm -rf "$temp_dir"
        return 1
    fi

    rm -rf "$temp_dir"

    if ! verify_backup "$backup_file"; then
        echo "❌ Backup file verification failed: ${backup_file}" >&2
        TELEGRAM_LOG+="❌ Backup verification failed
"
        return 1
    fi

    echo "$backup_file"
    return 0
}

apply_retention() {
    local deleted_count=0
    pushd "$BACKUP_DEST" > /dev/null || return 1

    local backup_count=$(ls dvol__*.tar.gz 2>/dev/null | wc -l)
    if [ $backup_count -gt $HOURLY_LIMIT ]; then
        deleted_count=$((backup_count - $HOURLY_LIMIT))
        echo "♻️ Deleting ${deleted_count} old backups..." >&2
        ls -t dvol__*.tar.gz | tail -n +$((HOURLY_LIMIT+1)) | xargs rm -f
    fi

    popd > /dev/null || return 1
    echo "$deleted_count"
    return 0
}

# =======================
# MAIN SCRIPT SECTION
# =======================

START_TIME=$(date +%s)

mkdir -p "$BACKUP_DEST"
echo "🔄 Starting Docker Volumes Backup..." >&2

if ! backup_file=$(create_backup); then
    TELEGRAM_LOG+="
❌ Backup creation failed
"
    send_telegram "$TELEGRAM_LOG"
    exit 1
fi

if [[ -z "$backup_file" || ! -f "${BACKUP_DEST}/${backup_file}" ]]; then
    TELEGRAM_LOG+="
❌ Backup file missing after creation: ${backup_file}
"
    send_telegram "$TELEGRAM_LOG"
    exit 1
fi

pretty_name="${backup_file#dvol__}"
pretty_name="${pretty_name%.tar.gz}"

TELEGRAM_LOG+="
✅ Backup created successfully  
📄 Filename: ${pretty_name}  
"

deleted_count=0
if ! deleted_count=$(apply_retention); then
    TELEGRAM_LOG+="
⚠️ Retention policy application failed  
"
else
    backup_size=$(du -h "${BACKUP_DEST}/${backup_file}" | cut -f1)
    TELEGRAM_LOG+="📦 Size: ${backup_size}  

♻️ Deleting ${deleted_count} old backups...  
"
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
DURATION_STR=$(printf "%dm %ds" $((DURATION/60)) $((DURATION%60)))

TELEGRAM_LOG+="
✅ Backup completed successfully.  
🕒 Duration: ${DURATION_STR}
"

echo "🕒 Duration ${DURATION_STR}" >&2

send_telegram "$TELEGRAM_LOG"
exit 0
EOF

# 3. Make it executable
chmod +x "$SCRIPT_PATH"

# 4. Install cron job if not already present
if ! crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH"; then
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "✅ Cron job added: every 3 hours"
else
    echo "ℹ️ Cron job already exists."
fi

echo "✅ Script deployed to $SCRIPT_PATH"
