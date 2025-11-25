#!/usr/bin/env bash
# UniFi Backup Script with GPG Encryption
# PURPOSE: Daily backup of UniFi controller configuration + MongoDB database with encryption and retention.
# WHY: Backups contain sensitive data (WiFi PSKs, admin credentials, network topology) requiring encryption at rest.
set -euo pipefail
IFS=$'\n\t'

LOG_FILE="backup-unifi.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Configuration
BACKUP_ROOT="/backup/unifi"
RETENTION_DAYS=30
UNIFI_DATA_DIR="/usr/lib/unifi/data"
UNIFI_AUTOBACKUP="${UNIFI_DATA_DIR}/backup/autobackup"
TIMESTAMP=$(date +'%Y-%m-%d_%H-%M-%S')
TODAY_DIR=$(date +'%Y-%m-%d')
TARGET_DIR="${BACKUP_ROOT}/${TODAY_DIR}"
ARCHIVE_NAME="unifi-backup-${TIMESTAMP}.tar.gz"
META_FILE="metadata.json"

# Security: GPG encryption for backups (contains WiFi PSKs, admin credentials, network topology)
ENABLE_ENCRYPTION=true
GPG_PASSPHRASE_FILE="/root/.unifi-backup-passphrase"  # chmod 600, contains encryption passphrase

function info(){ echo "[INFO] $*"; }
function warn(){ echo "[WARN] $*"; }
function fatal(){ echo "[ERROR] $*"; exit 1; }

if [[ $EUID -ne 0 ]]; then
  fatal "Run as root to access controller data and MongoDB dumps."
fi

# Verify GPG passphrase file exists (if encryption enabled)
if [[ "$ENABLE_ENCRYPTION" == "true" ]]; then
  if [[ ! -f "$GPG_PASSPHRASE_FILE" ]]; then
    fatal "Encryption enabled but passphrase file missing: $GPG_PASSPHRASE_FILE. Create with: echo 'YourStrongPassphrase' > $GPG_PASSPHRASE_FILE && chmod 600 $GPG_PASSPHRASE_FILE"
  fi
  if [[ $(stat -c '%a' "$GPG_PASSPHRASE_FILE" 2>/dev/null) != "600" ]]; then
    warn "Passphrase file permissions not 600; fixing..."
    chmod 600 "$GPG_PASSPHRASE_FILE" || fatal "Failed to set passphrase file permissions."
  fi
fi

if ! systemctl is-active --quiet unifi; then
  warn "UniFi service not active; proceeding (may be intentional)."
fi

mkdir -p "$TARGET_DIR" || fatal "Failed to create target directory: $TARGET_DIR"
cd "$TARGET_DIR"

info "Backing up UniFi autobackups (.unf)..."
if [[ -d "$UNIFI_AUTOBACKUP" ]]; then
  mkdir -p autobackup
  cp -a "$UNIFI_AUTOBACKUP"/*.unf autobackup/ 2>/dev/null || warn "No .unf files found (may be first boot)."
else
  warn "Autobackup directory missing: $UNIFI_AUTOBACKUP"
fi

info "Performing MongoDB dump..."
DUMP_DIR="dump"
mkdir -p "$DUMP_DIR"
MONGODUMP_BIN="/usr/bin/mongodump"
if [[ -x "$MONGODUMP_BIN" ]]; then
  "$MONGODUMP_BIN" --db ace --out "$DUMP_DIR" || warn "mongodump failed; check service."
else
  warn "mongodump binary not found; database backup skipped."
fi

info "Collecting version metadata..."
UNIFI_VER="$(dpkg -s unifi 2>/dev/null | awk -F': ' '/Version/ {print $2}' || echo 'unknown')"
cat > "$META_FILE" <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "unifi_version": "${UNIFI_VER}",
  "mongodb_version": "4.4",
  "host": "$(hostname -f 2>/dev/null || hostname)",
  "backup_root": "${BACKUP_ROOT}",
  "retention_days": ${RETENTION_DAYS},
  "encrypted": ${ENABLE_ENCRYPTION}
}
EOF

info "Creating compressed archive: ${ARCHIVE_NAME}"
tar -czf "$ARCHIVE_NAME" autobackup dump "$META_FILE" 2>/dev/null || fatal "Failed to create archive."

# Encrypt backup if enabled
if [[ "$ENABLE_ENCRYPTION" == "true" ]]; then
  info "Encrypting backup with GPG (AES256)..."
  gpg --batch --yes --passphrase-file "$GPG_PASSPHRASE_FILE" \
      --symmetric --cipher-algo AES256 \
      --output "${ARCHIVE_NAME}.gpg" "$ARCHIVE_NAME" || fatal "GPG encryption failed."
  
  # Remove unencrypted archive (keep only .gpg)
  rm -f "$ARCHIVE_NAME" || warn "Failed to remove unencrypted archive."
  info "Encrypted backup created: ${ARCHIVE_NAME}.gpg"
  
  # Checksum encrypted file
  sha256sum "${ARCHIVE_NAME}.gpg" > "${ARCHIVE_NAME}.gpg.sha256"
else
  # Checksum unencrypted file (if encryption disabled)
  sha256sum "$ARCHIVE_NAME" > "${ARCHIVE_NAME}.sha256"
  warn "Backup NOT encrypted (ENABLE_ENCRYPTION=false). This is NOT recommended for production."
fi

# Cleanup temporary directories
rm -rf autobackup dump "$META_FILE" 2>/dev/null || true

info "Applying retention policy (keep last ${RETENTION_DAYS} days)..."
find "$BACKUP_ROOT" -maxdepth 1 -type d -printf '%f\n' | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | while read -r d; do
  if [[ $(find "$BACKUP_ROOT/$d" -maxdepth 0 -mtime +$RETENTION_DAYS -print) ]]; then
    info "Pruning old backup directory: $d"
    rm -rf "${BACKUP_ROOT:?}/$d" || warn "Failed to remove $d"
  fi
done

if [[ "$ENABLE_ENCRYPTION" == "true" ]]; then
  info "Backup complete (encrypted): ${TARGET_DIR}/${ARCHIVE_NAME}.gpg"
  info "To decrypt: gpg --decrypt ${ARCHIVE_NAME}.gpg > ${ARCHIVE_NAME}"
else
  info "Backup complete (unencrypted): ${TARGET_DIR}/${ARCHIVE_NAME}"
fi

info "Consider offsite sync (rclone, rsync) for disaster recovery."

cat <<'CRON_EXAMPLE'

# Example cron (run daily at 02:00):
# 0 2 * * * /root/unifi-homelab-bootstrap/backup-unifi.sh

# Initialize passphrase file (first run only):
# echo "YourStrongRandomPassphrase" > /root/.unifi-backup-passphrase
# chmod 600 /root/.unifi-backup-passphrase
CRON_EXAMPLE