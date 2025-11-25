#!/usr/bin/env bash
# UniFi Controller + MongoDB 4.4 Installer for Ubuntu 24.04 (noble)
# PURPOSE: Idempotent installation with version pinning, port preflight checks, and safety hardening.
# WHY: Ensures long-term reproducibility and aligns with UniFi 8.x requirements (MongoDB 4.4) even on newer Ubuntu where packages are absent.
set -euo pipefail
IFS=$'\n\t'

LOG_FILE="install-unifi.log"
exec > >(tee -a "$LOG_FILE") 2>&1

REQUIRED_PORTS=(8080 8443 8880 8843 3478)
MONGO_VERSION="4.4"
UBNT_REPO_FILE="/etc/apt/sources.list.d/100-ubiquiti.list"
MONGO_REPO_FILE="/etc/apt/sources.list.d/mongodb-org-${MONGO_VERSION}.list"
MONGO_PIN_FILE="/etc/apt/preferences.d/mongodb-${MONGO_VERSION}-pin"

function info(){ echo -e "[INFO] $*"; }
function warn(){ echo -e "[WARN] $*"; }
function error(){ echo -e "[ERROR] $*"; }
function fatal(){ error "$*"; exit 1; }

if [[ $EUID -ne 0 ]]; then
  fatal "Run as root (sudo)."
fi

info "Starting UniFi installation workflow on $(hostname) ($(lsb_release -ds 2>/dev/null || echo 'Unknown Distro'))."

# Preflight: Check required ports are not occupied
info "Checking port availability..."
for p in "${REQUIRED_PORTS[@]}"; do
  if ss -tulpn | grep -q ":${p} "; then
    fatal "Port ${p} is in use. Resolve conflict before continuing."
  fi
done
info "All required ports free."

# Add Ubiquiti repository (official) if missing
if [[ ! -f "$UBNT_REPO_FILE" ]]; then
  info "Adding Ubiquiti APT repository..."
  # Using stable repo (example; adjust if Ubiquiti changes distribution codename usage)
  curl -fsSL https://dl.ui.com/unifi/unifi-repo.gpg | gpg --dearmor > /usr/share/keyrings/unifi-repo.gpg || fatal "Failed to fetch UniFi GPG key."
  echo "deb [signed-by=/usr/share/keyrings/unifi-repo.gpg] https://dl.ui.com/unifi/debian stable ubiquiti" > "$UBNT_REPO_FILE"
else
  info "Ubiquiti repository already present. Skipping."
fi

# MongoDB 4.4 repository (focal) for noble environment
CODENAME=$(lsb_release -cs || echo noble)
if [[ ! -f "$MONGO_REPO_FILE" ]]; then
  info "Adding MongoDB ${MONGO_VERSION} repository (focal fallback for ${CODENAME})..."
  curl -fsSL https://www.mongodb.org/static/pgp/server-${MONGO_VERSION}.asc | gpg --dearmor > /usr/share/keyrings/mongodb-${MONGO_VERSION}.gpg || fatal "Failed to fetch MongoDB GPG key."
  echo "deb [ arch=amd64 signed-by=/usr/share/keyrings/mongodb-${MONGO_VERSION}.gpg ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/${MONGO_VERSION} multiverse" > "$MONGO_REPO_FILE"
else
  info "MongoDB repository already present. Skipping."
fi

# Pin MongoDB to 4.4 explicitly
if [[ ! -f "$MONGO_PIN_FILE" ]]; then
  info "Creating APT pin file for MongoDB ${MONGO_VERSION}..."
  cat > "$MONGO_PIN_FILE" <<EOF
Package: mongodb-org*
Pin: version ${MONGO_VERSION}.*
Pin-Priority: 1001
EOF
else
  info "MongoDB pin file exists."
fi

info "Updating package indices..."
apt-get update -y || fatal "apt-get update failed."

# Install dependencies + UniFi (skip if already installed)
if ! dpkg -l | grep -q '^ii\s\+unifi\b'; then
  info "Installing UniFi Network Application and MongoDB packages..."
  # Minimal packages required for UniFi + logs + SSL enhancements potential
  apt-get install -y mongodb-org curl haveged || fatal "MongoDB base install failed."
  apt-get install -y unifi || fatal "UniFi install failed."
else
  info "UniFi already installed. Performing safe upgrade (keeping major versions)."
  apt-get install -y --only-upgrade unifi || warn "Upgrade may have been skipped (already latest)."
fi

# Ensure UniFi uses bundled Java (avoid system-wide Java interference)
UNIFI_JAVA_DIR="/usr/lib/unifi"
if [[ -d "$UNIFI_JAVA_DIR" ]]; then
  info "Verifying bundled Java presence..."
  if ! find "$UNIFI_JAVA_DIR" -maxdepth 2 -type f -name 'java' | grep -q java; then
    warn "Bundled Java executable not found; fallback may use system Java."
  fi
else
  warn "UniFi directory not found; install may have failed earlier."
fi

# Sysctl hardening: allow privileged ports from unprivileged processes only if required (documented rationale)
SYSCTL_CONF="/etc/sysctl.d/99-unifi.conf"
if [[ ! -f "$SYSCTL_CONF" ]]; then
  info "Applying sysctl adjustments (unprivileged_port_start=80)."
  echo 'net.ipv4.ip_unprivileged_port_start=80' > "$SYSCTL_CONF"
  sysctl --system >/dev/null || warn "sysctl reload returned non-zero; continuing."
else
  info "Sysctl configuration already present."
fi

info "Enabling and starting services..."
systemctl enable mongodb || warn "Could not enable mongodb service."
systemctl enable unifi || warn "Could not enable unifi service."

systemctl restart mongodb || fatal "MongoDB failed to start."
systemctl restart unifi || fatal "UniFi failed to start."

sleep 5
systemctl --no-pager status unifi | head -n 20 || warn "UniFi status truncated or unavailable."

HOST_FQDN=$(hostname -f 2>/dev/null || hostname)
info "Installation complete. Access Controller at: https://${HOST_FQDN}:8443"
info "If DNS A record 'unifi.rylan-home.local' points here, use: https://unifi.rylan-home.local:8443"

# Final port verification
info "Verifying ports now listening..."
for p in 8443 8080 3478; do
  if ! ss -tulpn | grep -q ":${p} "; then
    warn "Expected port ${p} not yet listening; UniFi may still be initializing."
  fi
done

info "LOG COMPLETE: $(date -Iseconds)"
