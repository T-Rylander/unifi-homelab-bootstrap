#!/usr/bin/env bash
# UniFi Backup Script
# PURPOSE: Perform daily backup of UniFi controller configuration and MongoDB database with retention management.
# WHY: Ensures rapid recovery and historical snapshots while controlling storage growth.
set -euo pipefail
IFS=$'\n\t'

LOG_FILE="backup-unifi.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Configuration
BACKUP_ROOT="/backup/unifi"          # Adjust if external storage mounted (e.g. /mnt/secure-backup)
RETENTION_DAYS=30                     # Keep last N days of backups
MONGO_DB="unifi"
TIMESTAMP=$(date +'%Y-%m-%d_%H-%M-%S')
TODAY_DIR=$(date +'%Y-%m-%d')
TARGET_DIR="${BACKUP_ROOT}/${TODAY_DIR}" # Date-based folder
ARCHIVE_NAME="unifi-backup-${TIMESTAMP}.tar.gz"
META_FILE="metadata.json"

function info(){ echo "[INFO] $*"; }
function warn(){ echo "[WARN] $*"; }
function fatal(){ echo "[ERROR] $*"; exit 1; }

if [[ $EUID -ne 0 ]]; then
  fatal "Run as root to access controller data and Mongo dumps."
fi

if ! systemctl is-active --quiet unifi; then
  warn "UniFi service not active; proceeding (may be intentional)."
fi

mkdir -p "$TARGET_DIR" || fatal "Failed to create target directory: $TARGET_DIR"
cd "$TARGET_DIR"

info "Backing up UniFi autobackups (.unf)..."
UNIFI_AUTOBACKUP_DIR="/var/lib/unifi/backup"
if [[ -d "$UNIFI_AUTOBACKUP_DIR" ]]; then
  cp -a "$UNIFI_AUTOBACKUP_DIR" . || warn "Failed to copy autobackup directory."
else
  warn "Autobackup directory missing: $UNIFI_AUTOBACKUP_DIR"
fi

info "Performing MongoDB dump for database: ${MONGO_DB}"
DUMP_DIR="dump"
mkdir -p "$DUMP_DIR"
mongodump --db "$MONGO_DB" --out "$DUMP_DIR" || warn "mongodump returned non-zero; check MongoDB status."

info "Collecting version metadata..."
UNIFI_VER="$(dpkg -s unifi 2>/dev/null | awk -F': ' '/Version/ {print $2}' || echo 'unknown')"
cat > "$META_FILE" <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "unifi_version": "${UNIFI_VER}",
  "mongo_version": "$(mongo --quiet --eval 'db.version()' 2>/dev/null || echo 'unknown')",
  "host": "$(hostname -f || hostname)",
  "retention_days": ${RETENTION_DAYS}
}
EOF

info "Creating compressed archive ${ARCHIVE_NAME}"
tar -czf "$ARCHIVE_NAME" backup dump "$META_FILE" || fatal "Failed to create archive."
sha256sum "$ARCHIVE_NAME" > "${ARCHIVE_NAME}.sha256"

info "Applying retention policy (keep last ${RETENTION_DAYS} days)";
find "$BACKUP_ROOT" -maxdepth 1 -type d -printf '%f\n' | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | while read -r d; do
  # If directory older than retention_days, remove
  if [[ $(find "$BACKUP_ROOT/$d" -maxdepth 0 -mtime +$RETENTION_DAYS -print) ]]; then
    info "Pruning old backup directory: $d"
    rm -rf "${BACKUP_ROOT:?}/$d" || warn "Failed to remove $d"
  fi
done

info "Backup complete: ${TARGET_DIR}/${ARCHIVE_NAME}"
info "Consider offsite sync (e.g., rsync or rclone) for resilience."

cat <<'CRON'
# Example cron (run daily at 02:00):
# 0 2 * * * /usr/local/sbin/backup-unifi.sh
CRON
