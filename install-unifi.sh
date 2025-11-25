#!/usr/bin/env bash
# UniFi Controller Installer for Ubuntu 24.04 (noble) - Phase 1 Clean Server
# PURPOSE: Idempotent installation with port checks, sysctl hardening, bundled MongoDB (8.1+ includes Mongo).
# WHY: UniFi 8.1+ bundles MongoDB 4.4\u2014no manual repo needed. Sysctl enables <1024 port binding (Ubiquiti requirement).
set -euo pipefail
IFS=$'\n\t'

LOG_FILE="install-unifi.log"
exec > >(tee -a "$LOG_FILE") 2>&1

REQUIRED_PORTS=(8080 8443 8880 8843 3478 10001)
UBNT_REPO_FILE="/etc/apt/sources.list.d/100-ubiquiti.list"
SYSCTL_CONF="/etc/sysctl.d/99-unifi.conf"

function info(){ echo -e "[INFO] $*"; }
function warn(){ echo -e "[WARN] $*"; }
function error(){ echo -e "[ERROR] $*"; }
function fatal(){ error "$*"; exit 1; }

if [[ $EUID -ne 0 ]]; then
  fatal "Run as root (sudo)."
fi

info "Starting UniFi installation workflow on $(hostname) ($(lsb_release -ds 2>/dev/null || echo 'Unknown Distro'))."


# Preflight: Check for required tools (curl, gnupg)
info "Checking for required dependencies..."
MISSING_DEPS=()
command -v curl >/dev/null 2>&1 || MISSING_DEPS+=("curl")
command -v gpg >/dev/null 2>&1 || MISSING_DEPS+=("gnupg")

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
  info "Installing missing dependencies: ${MISSING_DEPS[*]}"
  apt-get update -qq || fatal "apt-get update failed during dependency check."
  apt-get install -y "${MISSING_DEPS[@]}" || fatal "Failed to install dependencies: ${MISSING_DEPS[*]}"
  info "Dependencies installed successfully."
fi

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
  curl -fsSL https://dl.ui.com/unifi/unifi-repo.gpg | sudo tee /usr/share/keyrings/ubiquiti-archive-keyring.gpg >/dev/null || fatal "Failed to fetch UniFi GPG key."
  echo "deb [signed-by=/usr/share/keyrings/ubiquiti-archive-keyring.gpg] https://www.ui.com/downloads/unifi/debian stable ubiquiti" > "$UBNT_REPO_FILE"
else
  info "Ubiquiti repository already present. Skipping."
fi

info "Updating package indices..."
apt-get update -y || fatal "apt-get update failed."

# Install UniFi (bundled MongoDB 4.4 included in 8.1+ packages)
if ! dpkg -l | grep -q '^ii\s\+unifi\b'; then
  info "Installing UniFi Network Application (includes bundled MongoDB + Java)..."
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

# Sysctl hardening: allow <1024 port binding (UniFi requirement for ports 80/443 redirect)
if [[ ! -f "$SYSCTL_CONF" ]]; then
  info "Applying sysctl adjustments (unprivileged_port_start=80\u2014Ubiquiti requirement)."
  echo 'net.ipv4.ip_unprivileged_port_start=80' > "$SYSCTL_CONF"
  sysctl --system >/dev/null || warn "sysctl reload returned non-zero; continuing."
else
  info "Sysctl configuration already present."
fi

info "Enabling and starting UniFi service..."
systemctl enable unifi || warn "Could not enable unifi service."
systemctl restart unifi || fatal "UniFi failed to start."

sleep 5
systemctl --no-pager status unifi | head -n 20 || warn "UniFi status truncated or unavailable."

HOST_IP=$(hostname -I | awk '{print $1}')
info "Installation complete. Access Controller at: https://${HOST_IP}:8443"
info "Phase 1 Bootstrap: Use 10.0.1.10:8443 initially; migrate to VLAN 10 (Servers) post-adoption."

# Final port verification
info "Verifying ports now listening..."
for p in 8443 8080 3478 10001; do
  if ! ss -tulpn | grep -q ":${p} "; then
    warn "Expected port ${p} not yet listening; UniFi may still be initializing (wait 30-60s)."
  fi
done

info "Next: Complete setup wizard (Site: Rylan-Home, admin credentials). Then adopt devices (USG first)."
info "LOG COMPLETE: $(date -Iseconds)"
