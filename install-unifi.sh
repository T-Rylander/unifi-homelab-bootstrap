#!/usr/bin/env bash
# UniFi Controller Installer for Ubuntu 22.04/24.04 - Phase 1 Clean Server
# PURPOSE: Idempotent installation with MongoDB 4.4, port checks, and sysctl hardening.
# WHY: UniFi Network Application requires MongoDB 4.4 as external dependency on Debian/Ubuntu systems.
set -euo pipefail
IFS=$'\n\t'

LOG_FILE="install-unifi.log"
exec > >(tee -a "$LOG_FILE") 2>&1

REQUIRED_PORTS=(8080 8443 8880 8843 3478 10001)
UBNT_REPO_FILE="/etc/apt/sources.list.d/100-ubiquiti.list"
MONGO_REPO_FILE="/etc/apt/sources.list.d/mongodb-org-4.4.list"
SYSCTL_CONF="/etc/sysctl.d/99-unifi.conf"

function info(){ echo -e "[INFO] $*"; }
function warn(){ echo -e "[WARN] $*"; }
function error(){ echo -e "[ERROR] $*"; }
function fatal(){ error "$*"; exit 1; }

if [[ $EUID -ne 0 ]]; then
  fatal "Run as root (sudo)."
fi

info "Starting UniFi installation workflow on $(hostname) ($(lsb_release -ds 2>/dev/null || echo 'Unknown Distro'))."

# Detect Ubuntu version for MongoDB repo
UBUNTU_CODENAME=$(lsb_release -cs 2>/dev/null || echo "jammy")
if [[ "$UBUNTU_CODENAME" == "noble" ]]; then
  info "Ubuntu 24.04 detected; using Jammy (22.04) MongoDB repository for compatibility."
  UBUNTU_CODENAME="jammy"
fi

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

# Add MongoDB 4.4 repository if missing
if [[ ! -f "$MONGO_REPO_FILE" ]]; then
  info "Adding MongoDB 4.4 repository (codename: ${UBUNTU_CODENAME})..."
  curl -fsSL https://www.mongodb.org/static/pgp/server-4.4.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-4.4.gpg || fatal "Failed to fetch MongoDB GPG key."
  echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-4.4.gpg ] https://repo.mongodb.org/apt/ubuntu ${UBUNTU_CODENAME}/mongodb-org/4.4 multiverse" > "$MONGO_REPO_FILE"
else
  info "MongoDB repository already present. Skipping."
fi

# Add Ubiquiti repository (official) if missing
if [[ ! -f "$UBNT_REPO_FILE" ]]; then
  info "Adding Ubiquiti APT repository..."
  curl -fsSL https://dl.ui.com/unifi/unifi-repo.gpg | gpg --dearmor -o /usr/share/keyrings/ubiquiti-archive-keyring.gpg || fatal "Failed to fetch UniFi GPG key."
  echo "deb [signed-by=/usr/share/keyrings/ubiquiti-archive-keyring.gpg] https://www.ui.com/downloads/unifi/debian stable ubiquiti" > "$UBNT_REPO_FILE"
else
  info "Ubiquiti repository already present. Skipping."
fi

info "Updating package indices..."
apt-get update -y || fatal "apt-get update failed."

# Verify MongoDB repository is properly indexed (resilience check)
info "Verifying MongoDB 4.4 repository accessibility..."
if ! apt-cache policy mongodb-org | grep -q "mongodb-org-4.4"; then
  warn "MongoDB repo not indexed after initial apt update—attempting legacy GPG fallback..."
  
  # Legacy apt-key method (fallback for GPG format conflicts on 24.04)
  curl -fsSL https://www.mongodb.org/static/pgp/server-4.4.asc | apt-key add - || warn "Legacy apt-key add failed (proceeding)."
  
  # Force repository refresh with --fix-missing
  apt-get update --fix-missing -y || warn "Fix-missing update completed with warnings."
  
  # Second verification attempt
  if ! apt-cache policy mongodb-org | grep -q "mongodb-org-4.4"; then
    fatal "MongoDB repository still not accessible. Manual intervention required. See docs/bootstrap-guide.md § MongoDB Repo Contingency."
  else
    info "MongoDB repo now indexed after legacy fallback."
  fi
else
  info "MongoDB repository verified (no fallback needed)."
fi

# Install MongoDB 4.4 first (UniFi dependency)
if ! dpkg -l | grep -q '^ii\s\+mongodb-org\b'; then
  info "Installing MongoDB 4.4..."
  apt-get install -y mongodb-org || fatal "MongoDB installation failed. Check /var/log/apt/term.log for details."
  systemctl enable mongod
  systemctl start mongod || warn "MongoDB service failed to start (may need manual intervention)."
else
  info "MongoDB already installed. Skipping."
fi

# Install UniFi Network Application
if ! dpkg -l | grep -q '^ii\s\+unifi\b'; then
  info "Installing UniFi Network Application..."
  apt-get install -y unifi || fatal "UniFi install failed."
else
  info "UniFi already installed. Performing safe upgrade (keeping major versions)."
  apt-get install -y --only-upgrade unifi || warn "Upgrade may have been skipped (already latest)."
fi

# Sysctl hardening: allow <1024 port binding (UniFi requirement for ports 80/443 redirect)
if [[ ! -f "$SYSCTL_CONF" ]]; then
  info "Applying sysctl adjustments (unprivileged_port_start=80Ubiquiti requirement)."
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