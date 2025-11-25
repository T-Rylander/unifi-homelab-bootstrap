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

### 1.4 Firewall Rules (UFW - Optional for Phase 1)
Open required UniFi ports (if UFW enabled):
```bash
sudo ufw allow 8080/tcp
sudo ufw allow 8443/tcp
sudo ufw allow 8880/tcp
sudo ufw allow 8843/tcp
sudo ufw allow 3478/udp
sudo ufw allow 10001/udp
sudo ufw allow 22/tcp  # SSH
sudo ufw enable
sudo ufw status
```
Alternatively, leave UFW disabled for Phase 1 (enable in Phase 2 with VLAN rules).

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
- **UAP-AC-Lite:** Hold reset button 10 seconds until LED ring flashes white/blue (factory defaults restored).

### 3.2 Power-On Sequence (Critical Order)
1. **Controller:** Verify `https://10.0.1.10:8443` accessible (wait 60s post-reboot for services).
2. **USG-3P (Gateway):** Power on, wait **5 minutes** for firmware download + provisioning. LED: White steady = adopted.
3. **US-8-60W (Switch):** Power on after USG stable. Wait 2-3 minutes. LED: White = adopted.
4. **UAP-AC-Lite (APs):** Power on after switch stable. Each takes 2-3 minutes. LED: White = adopted, blue = broadcasting.

### 3.3 UI Adoption Workflow (Automatic Discovery)
Devices should appear in **Devices** tab:
- Status progression: `Pending` → `Adopt` (click button) → `Provisioning` → `Connected`
- If stuck in `Adopting` >10 minutes: Use SSH fallback (Section 3.4).

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
