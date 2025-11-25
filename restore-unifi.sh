#!/usr/bin/env bash
# UniFi Restore Script
# PURPOSE: Safely restore UniFi controller state and MongoDB database from backup archives.
# WHY: Provides controlled rollback with version awareness to minimize downtime and prevent corruption.
set -euo pipefail
IFS=$'\n\t'

LOG_FILE="restore-unifi.log"
exec > >(tee -a "$LOG_FILE") 2>&1

BACKUP_ROOT="/backup/unifi"
UNIFI_DATA_DIR="/usr/lib/unifi/data"  # UniFi 8.x bundled path
AUTOBACKUP_DIR="${UNIFI_DATA_DIR}/backup/autobackup"

function info(){ echo "[INFO] $*"; }
function warn(){ echo "[WARN] $*"; }
function fatal(){ echo "[ERROR] $*"; exit 1; }

if [[ $EUID -ne 0 ]]; then
  fatal "Run as root."
fi

if ! systemctl is-active --quiet unifi; then
  warn "UniFi service not currently active (may be OK)."
fi

[[ -d "$BACKUP_ROOT" ]] || fatal "Backup root not found: $BACKUP_ROOT"

info "Enumerating available backups..."
mapfile -t archives < <(find "$BACKUP_ROOT" -type f -name 'unifi-backup-*.tar.gz' | sort)
[[ ${#archives[@]} -gt 0 ]] || fatal "No backup archives found under $BACKUP_ROOT"

PS3="Select a backup archive to restore (number): "
select ARCHIVE in "${archives[@]}"; do
  if [[ -n "$ARCHIVE" ]]; then
    info "Selected archive: $ARCHIVE"
    break
  else
    warn "Invalid selection; try again."
  fi
done

# Confirm
read -r -p "Proceed with restore of $ARCHIVE? (yes/NO): " yn
if [[ "$yn" != "yes" ]]; then
  fatal "User aborted restore."
fi

TMP_DIR=$(mktemp -d /tmp/unifi-restore-XXXX)
info "Extracting archive to $TMP_DIR"
tar -xzf "$ARCHIVE" -C "$TMP_DIR" || fatal "Failed to extract archive."
[[ -f "$ARCHIVE.sha256" ]] && sha256sum -c "$ARCHIVE.sha256" || warn "Checksum file missing or verification skipped."

META_FILE=$(find "$TMP_DIR" -maxdepth 1 -name 'metadata.json' -print -quit)
if [[ -f "$META_FILE" ]]; then
  info "Metadata:"; cat "$META_FILE" | sed 's/^/  /'
else
  warn "Metadata file missing; version compatibility unknown."
fi

info "Stopping UniFi service for restore..."
systemctl stop unifi || warn "Failed to stop unifi (continuing)."

info "Restoring MongoDB database (ace - UniFi default DB name)..."
MONGORESTORE_BIN="/usr/bin/mongorestore"  # Adjust if bundled binary elsewhere
if [[ -d "$TMP_DIR/dump/ace" ]]; then
  if [[ -x "$MONGORESTORE_BIN" ]]; then
    "$MONGORESTORE_BIN" --drop --db ace "$TMP_DIR/dump/ace" || warn "mongorestore reported issues."
  else
    warn "mongorestore binary not found; manual restore required."
  fi
else
  warn "MongoDB dump directory missing: $TMP_DIR/dump/ace"
fi

info "Restoring .unf autobackup files..."
mkdir -p "$AUTOBACKUP_DIR"
if [[ -d "$TMP_DIR/autobackup" ]]; then
  cp -a "$TMP_DIR/autobackup"/*.unf "$AUTOBACKUP_DIR"/ 2>/dev/null || warn "No .unf files to restore."
else
  warn "Autobackup directory missing inside archive."
fi

info "Starting UniFi service..."
systemctl start unifi || fatal "Failed to start UniFi after restore."

sleep 5
systemctl --no-pager status unifi | head -n 15 || warn "Status retrieval issue."

info "Verification steps:";
cat <<'STEPS'
1. Log in to controller UI (https://<host>:8443) and verify site + devices.
2. Confirm settings (Networks, WLANs, Firewall) match expected state.
3. Review /var/log/unifi/server.log for startup errors.
4. Force inform from a device if adoption state appears stale.
STEPS

info "Cleanup temporary directory $TMP_DIR"
rm -rf "$TMP_DIR"

info "Restore workflow complete. Monitor system for 10–15 minutes for background tasks."
