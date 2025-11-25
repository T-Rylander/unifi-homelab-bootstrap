# UniFi Bootstrap Guide (Phase 1: Clean Server)

## Overview: Phased Architecture
- **Phase 1 (This Guide):** UniFi Controller on clean Ubuntu 24.04 (no Samba). Bootstrap VLAN 1 (10.0.1.0/24).
- **Phase 2:** Samba AD DC integration; migrate controller to Servers VLAN 10 (10.0.10.10).
- **Phase 3:** Services (FreePBX VLAN 40, osTicket VLAN 30, segmented firewall rules).

## 1. Pre-Installation (Phase 1: Clean Server)
### 1.1 Ubuntu 24.04 Base Install
1. Download official Ubuntu Server 24.04 LTS ISO.
2. Perform minimal install (no snaps beyond defaults, enable OpenSSH).
3. Set hostname: `rylan-dc` (consistent for Phase 2 AD promotion).
4. Update packages:
```bash
sudo apt update && sudo apt -y full-upgrade
sudo reboot
```

### 1.2 Static IP Configuration (Bootstrap VLAN 1)
Edit `/etc/netplan/01-netcfg.yaml`:
```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp4s0:  # Adjust interface name (use `ip a` to verify)
      addresses: [10.0.1.10/24]
      routes:
        - to: default
          via: 10.0.1.1
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]  # Public DNS for Phase 1
```
Apply:
```bash
sudo netplan apply
ping -c 3 8.8.8.8
```

### 1.3 DNS (Phase 1: Skip A Record)
No Samba AD yet—use IP directly (`10.0.1.10`) for controller access. Phase 2 adds `unifi.rylan-home.local` DNS entry.

### 1.4 Firewall Rules (UFW - Recommended for Phase 1)

**Security posture:** Enable UFW to restrict controller access to bootstrap VLAN only. This prevents unauthorized access during adoption phase.

```bash
# Default deny incoming (critical for production)
sudo ufw default deny incoming
sudo ufw default allow outgoing

# SSH access (restrict to bootstrap VLAN for safety)
sudo ufw allow from 10.0.1.0/24 to any port 22 comment 'SSH (bootstrap VLAN)'

# UniFi Controller ports (LAN access only)
sudo ufw allow from 10.0.1.0/24 to any port 8080 comment 'UniFi inform (devices)'
sudo ufw allow from 10.0.1.0/24 to any port 8443 comment 'Controller UI'
sudo ufw allow from 10.0.1.0/24 to any port 8880 comment 'HTTP redirect'
sudo ufw allow from 10.0.1.0/24 to any port 8843 comment 'Guest portal HTTPS'

# STUN/Discovery (UDP - required for device adoption)
sudo ufw allow 3478/udp comment 'STUN'
sudo ufw allow 10001/udp comment 'Device discovery'

# Enable firewall
sudo ufw --force enable
sudo ufw status verbose
```

**Expected output:**
```
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), disabled (routed)

To                         Action      From
--                         ------      ----
22                         ALLOW       10.0.1.0/24                # SSH (bootstrap VLAN)
8080                       ALLOW       10.0.1.0/24                # UniFi inform (devices)
8443                       ALLOW       10.0.1.0/24                # Controller UI
8880                       ALLOW       10.0.1.0/24                # HTTP redirect
8843                       ALLOW       10.0.1.0/24                # Guest portal HTTPS
3478/udp                   ALLOW       Anywhere                   # STUN
10001/udp                  ALLOW       Anywhere                   # Device discovery
```

**Phase 2 migration:** When moving controller to Servers VLAN 10, update firewall rules to allow management VLAN 20 (devices) and user VLAN 30 (admin access). See `docs/security.md § Firewall Configuration` for production ruleset.

**Alternative (not recommended):** Leave UFW disabled for Phase 1 if troubleshooting network connectivity issues, but **enable before production use**.

## 2. Controller Installation (Phase 1)
### 2.1 Clone Repository
```bash
cd /root
git clone https://github.com/T-Rylander/unifi-homelab-bootstrap.git
cd unifi-homelab-bootstrap
```

### 2.2 Run Installer
```bash
sudo bash install-unifi.sh
```
**Runtime:** ~5 minutes. Output shows controller URL (`https://10.0.1.10:8443`).

**Expected Output:** Script performs resilience checks for MongoDB repository indexing. If `apt-cache policy mongodb-org` fails after initial `apt update`, the installer automatically:
1. Attempts legacy `apt-key` GPG import (fallback for Ubuntu 24.04 keyring format conflicts).
2. Runs `apt-get update --fix-missing` to force cache refresh.
3. Re-verifies MongoDB 4.4 availability before proceeding.

### 2.2.1 MongoDB Repository Contingency (Manual Fix)
**Symptom:** Installer fails with "MongoDB repository still not accessible" or `apt-get install mongodb-org` returns "Unable to locate package."

**Root Cause:** Ubuntu 24.04 (noble) uses modern signed-by keyrings, but MongoDB 4.4's GPG key format triggers deprecation warnings. Combined with apt cache stubbornness (especially on fresh installs), the multiverse packages may not index on first `apt update`.

**Manual Fix (if installer fallback fails):**
```bash
# Run dedicated troubleshooter script
sudo bash troubleshoot-repo.sh
```

**What it does:**
- Removes existing MongoDB repo files and GPG keys (clean slate).
- Adds MongoDB GPG key via **both** modern (signed-by keyring) and legacy (apt-key) methods.
- Creates repository entry for Jammy (22.04) if on Noble (24.04)—MongoDB 4.4 lacks Noble packages.
- Runs double `apt update` (standard + `--fix-missing`) to force cache indexing.
- Verifies `apt-cache policy mongodb-org` shows candidate version from mongodb-org-4.4 repository.

**Expected Output (success):**
```
[INFO] ✓ SUCCESS: MongoDB 4.4 repository is now accessible.
[INFO] Available version: 4.4.29
[INFO] You can now run: sudo apt-get install -y mongodb-org
```

**If still failing:**
1. Check `/tmp/apt-update.log` for specific errors (i386 architecture warnings are normal; ignore).
2. Verify outbound HTTPS works: `curl -I https://repo.mongodb.org` (should return `200 OK`).
3. Confirm Ubuntu codename: `lsb_release -cs` (noble → uses jammy repo; jammy → native).
4. See **§ Troubleshooting** for "MongoDB repo indexing fails" detailed diagnostics.

**After manual fix succeeds:**
```bash
# Resume installation (MongoDB now installable)
sudo apt-get install -y mongodb-org
sudo systemctl enable mongod && sudo systemctl start mongod
sudo apt-get install -y unifi
```

### 2.3 Initial Setup Wizard
Browse to:
```
https://10.0.1.10:8443
```
Accept self-signed certificate warning (fix in Phase 2 with Let's Encrypt or internal CA).

Follow prompts:
- **Site Name:** Rylan-Home
- **Admin Credentials:** Strong password + 2FA (optional but recommended)
- **Telemetry:** Opt-out if privacy-sensitive
- **Auto-Update:** Disable (manual control preferred)

Placeholder screenshot references:
- [Screenshot: Initial Setup Wizard]
- [Screenshot: Device Discovery]

### 2.3 SSL Certificate Options
Options:
| Method | Complexity | Notes |
|--------|------------|-------|
| Self-Signed | Low | Default; browser warnings |
| Let's Encrypt | Medium | Requires public DNS or DNS challenge |
| Internal CA | Medium | Issue from Samba AD CA if available |

## 3. Device Adoption (Phase 1: Bootstrap VLAN 1)
### 3.1 Factory Reset Procedure (All Devices)
- **USG-3P:** Hold reset button 10 seconds until white LED rapid blink (releases after ~15s total).
- **US-8-60W:** Hold reset button 10 seconds until status LED alternates (device reboots).
- **USW-Flex-Mini:** Hold reset button 10 seconds until LED flashes white/amber (factory reset confirmed).
- **UAP-AC-Lite:** Hold reset button 10 seconds until LED ring flashes white/blue (factory defaults restored).

### 3.2 Power-On Sequence (Critical Order)
1. **Controller:** Verify `https://10.0.1.10:8443` accessible (wait 60s post-reboot for services).
2. **USG-3P (Gateway):** Power on, wait **5 minutes** for firmware download + provisioning. LED: White steady = adopted.
3. **US-8-60W (Switch):** Power on after USG stable. Wait 2-3 minutes. LED: White = adopted.
4. **USW-Flex-Mini (Switch):** Connect Port 1 to US-8-60W Port 2. Power on. Wait 2-3 minutes. LED: White = adopted.
5. **UAP-AC-Lite (APs):** Power on after switches stable. Each takes 2-3 minutes. LED: White = adopted, blue = broadcasting.

**Total Adoption Count: 4 devices** (USG-3P, US-8-60W, USW-Flex-Mini, 2× APs).

### 3.3 UI Adoption Workflow (Automatic Discovery)
Devices should appear in **Devices** tab (expected: 4 total):
- Status progression: `Pending` → `Adopt` (click button) → `Provisioning` → `Connected`
- If stuck in `Adopting` >10 minutes: Use SSH fallback (Section 3.4).

**Post-Adoption Verification:**
```bash
ping 10.0.1.1   # USG-3P
ping 10.0.1.2   # US-8-60W
ping 10.0.1.3   # USW-Flex-Mini
ping 10.0.1.10  # AP #1
ping 10.0.1.11  # AP #2
```

### 3.4 SSH Fallback (Layer 3 Adoption)
Default credentials: `ubnt/ubnt` (change post-adoption via Settings > Site > Device Authentication).

Single device (USG example):
```bash
sudo bash adopt-devices.sh -c 10.0.1.10 -d 10.0.1.1 -p
```
Batch mode (all devices from `devices.txt`):
```bash
sudo bash adopt-devices.sh -c 10.0.1.10 -f devices.txt -p
```
Enter password `ubnt` when prompted.

## 4. VLAN Configuration (Post-Adoption)
### 4.1 Create VLANs (Settings > Networks)
Follow v4.2 table (see `vlan-design.md`). Example for Servers VLAN:
1. Click **Create New Network**.
2. Name: `Servers`, VLAN ID: `10`, Gateway/Subnet: `10.0.10.1/24`.
3. DHCP Range: `10.0.10.100` - `10.0.10.200`.
4. DNS: `10.0.10.10` (future Samba AD; use 8.8.8.8 for Phase 1).
5. Repeat for Management (20), User Devices (30), VoIP (40), Guest/IoT (90).

### 4.2 Configure Trunk Ports (Settings > Devices > US-8-60W > Ports)
Set upstairs US-8-60W ports 7-8 as **trunk** (All VLANs) for downlink to TL-SG108 unmanaged switch.

### 4.3 Migrate Controller IP (Optional)
Move `rylan-dc` from bootstrap VLAN 1 (10.0.1.10) to Servers VLAN 10 (10.0.10.10):
1. Update netplan: `addresses: [10.0.10.10/24]`, gateway `10.0.10.1`.
2. Apply: `sudo netplan apply`.
3. UI: Settings > System > Controller Hostname/IP: `10.0.10.10`.
4. Devices re-inform automatically (or force via SSH).

## 5. Post-Installation (Phase 1 Complete)
### 5.1 Backups
Schedule daily backups:
```bash
sudo crontab -e
# Add line:
0 2 * * * /root/unifi-homelab-bootstrap/backup-unifi.sh
```

### 5.2 Update Strategy
Manual only (no auto-updates):
```bash
sudo apt update
sudo apt install --only-upgrade unifi
```
Always backup before upgrading.

### 5.3 Monitoring
| Tool | Purpose |
|------|---------|
| `systemctl status unifi` | Service health |
| `tail -f /usr/lib/unifi/logs/server.log` | Application logs |
| UI: Insights > Statistics | Device uptime, clients |

### 5.4 Security Hardening
- Change default SSH credentials (`ubnt/ubnt`) via Settings > Site > Device Authentication.
- Enable controller admin 2FA (Settings > Admins).
- Restrict management VLAN 20 access (Phase 2 firewall rules).

### 5.6 Next: Phase 2 (Samba AD Integration)
See separate guide for Samba AD DC installation, DNS migration, and VLAN 10 controller finalization.

---
End of Phase 1 bootstrap guide.
