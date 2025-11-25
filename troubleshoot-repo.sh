#!/usr/bin/env bash
# MongoDB 4.4 Repository Troubleshooter for Ubuntu 22.04/24.04
# PURPOSE: Manual fix for apt repository indexing failures (GPG format conflicts, cache hiccups).
# USAGE: sudo bash troubleshoot-repo.sh
set -euo pipefail

function info(){ echo -e "[INFO] $*"; }
function warn(){ echo -e "[WARN] $*"; }
function fatal(){ echo -e "[ERROR] $*"; exit 1; }

if [[ $EUID -ne 0 ]]; then
  fatal "Run as root (sudo)."
fi

info "MongoDB 4.4 Repository Troubleshooter"
info "Detecting Ubuntu version..."
UBUNTU_CODENAME=$(lsb_release -cs 2>/dev/null || echo "jammy")
if [[ "$UBUNTU_CODENAME" == "noble" ]]; then
  info "Ubuntu 24.04 detected; using Jammy (22.04) repository."
  UBUNTU_CODENAME="jammy"
fi

# Step 1: Remove existing MongoDB repo (if present)
if [[ -f /etc/apt/sources.list.d/mongodb-org-4.4.list ]]; then
  info "Removing existing MongoDB repository file..."
  rm -f /etc/apt/sources.list.d/mongodb-org-4.4.list
fi

# Step 2: Clear GPG keyrings (modern and legacy)
info "Clearing existing MongoDB GPG keys..."
rm -f /usr/share/keyrings/mongodb-server-4.4.gpg
apt-key del 656408E390CFB1F5 2>/dev/null || info "Legacy key not found (OK)."

# Step 3: Add MongoDB GPG key (modern signed-by method)
info "Adding MongoDB GPG key (signed-by keyring)..."
curl -fsSL https://www.mongodb.org/static/pgp/server-4.4.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-4.4.gpg || warn "Modern keyring creation failed."

# Step 4: Add MongoDB GPG key (legacy apt-key method as fallback)
info "Adding MongoDB GPG key (legacy apt-key fallback)..."
curl -fsSL https://www.mongodb.org/static/pgp/server-4.4.asc | apt-key add - || warn "Legacy apt-key add failed."

# Step 5: Create MongoDB repository file (modern format)
info "Creating MongoDB repository entry..."
cat > /etc/apt/sources.list.d/mongodb-org-4.4.list <<EOF
deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-4.4.gpg ] https://repo.mongodb.org/apt/ubuntu ${UBUNTU_CODENAME}/mongodb-org/4.4 multiverse
EOF

# Step 6: Update apt cache (with fix-missing)
info "Updating apt cache (first pass)..."
apt-get update -y 2>&1 | tee /tmp/apt-update.log || warn "First apt update showed warnings."

info "Updating apt cache (second pass with --fix-missing)..."
apt-get update --fix-missing -y || warn "Fix-missing update completed with warnings."

# Step 7: Verify MongoDB packages are now available
info "Verifying MongoDB 4.4 repository indexing..."
if apt-cache policy mongodb-org | grep -q "mongodb-org-4.4"; then
  info " SUCCESS: MongoDB 4.4 repository is now accessible."
  info "Available version: $(apt-cache policy mongodb-org | grep Candidate | awk '{print $2}')"
  info "You can now run: sudo apt-get install -y mongodb-org"
else
  fatal "MongoDB repository still not indexed. Check /tmp/apt-update.log for errors."
fi

info "Troubleshooting complete. If issues persist, see docs/troubleshooting.md."