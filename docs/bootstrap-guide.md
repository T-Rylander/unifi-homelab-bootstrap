# UniFi Bootstrap Guide

## 1. Pre-Installation
### 1.1 Ubuntu 24.04 Base Install
1. Download official Ubuntu Server 24.04 ISO.
2. Perform minimal install (no snaps beyond defaults, optional OpenSSH).
3. Update packages:
```bash
sudo apt update && sudo apt -y full-upgrade
```
4. Reboot.

### 1.2 Static IP Configuration (Netplan Example)
Edit `/etc/netplan/01-netcfg.yaml`:
```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eno1:
      addresses: [192.168.1.10/24]
      gateway4: 192.168.1.1
      nameservers:
        addresses: [192.168.1.10, 1.1.1.1]
```
Apply:
```bash
sudo netplan apply
```

### 1.3 DNS A Record (Samba AD DC)
Add record in AD-integrated DNS:
- Name: `unifi`
- FQDN: `unifi.rylan-home.local`
- IP: `192.168.1.10`
Validation:
```bash
host unifi.rylan-home.local
```

### 1.4 Firewall Rules (UFW Example)
Open required UniFi ports:
```bash
sudo ufw allow 8080/tcp
sudo ufw allow 8443/tcp
sudo ufw allow 8880/tcp
sudo ufw allow 8843/tcp
sudo ufw allow 3478/udp
sudo ufw reload
```

## 2. Controller Installation
### 2.1 Run Installer
```bash
sudo bash install-unifi.sh
```
Expected output includes controller URL.

### 2.2 Initial Setup Wizard
Browse to:
```
https://unifi.rylan-home.local:8443
```
Follow prompts:
- Create admin account
- Opt-out of telemetry if desired
- Define site name

Placeholder screenshot references:
- [Screenshot: Initial Setup]
- [Screenshot: Device Adoption]

### 2.3 SSL Certificate Options
Options:
| Method | Complexity | Notes |
|--------|------------|-------|
| Self-Signed | Low | Default; browser warnings |
| Let's Encrypt | Medium | Requires public DNS or DNS challenge |
| Internal CA | Medium | Issue from Samba AD CA if available |

## 3. Device Adoption
### 3.1 Factory Reset Procedure
Hold reset button ~10 seconds until LED flash sequence confirms reset.

### 3.2 Power-On Sequence
1. Controller host (`rylan-dc`)
2. USG / gateway
3. Switches
4. Access Points

### 3.3 UI Adoption Workflow
Devices should appear automatically:
- Status: Pending → Adopt → Provisioning → Connected

### 3.4 SSH Fallback (Layer 3 Adoption)
Use `adopt-devices.sh` if stuck:
```bash
sudo bash adopt-devices.sh -c 192.168.1.10 -d 192.168.1.22
```
Or batch:
```bash
sudo bash adopt-devices.sh -c unifi.rylan-home.local -f devices.txt -k /root/.ssh/unifi
```

## 4. Post-Installation
### 4.1 Backups
Set cron (see `backup-unifi.sh`). Confirm archive + metadata creation.

### 4.2 Update Strategy
- Avoid automatic major upgrades; review UniFi release notes.
- Backup prior to upgrade.

### 4.3 Monitoring Recommendations
| Tool | Purpose |
|------|---------|
| `top` / `htop` | Resource usage |
| `journalctl -u unifi` | Service logs |
| `server.log` | Application diagnostics |
| External Syslog | Centralized logging |

### 4.4 Security Hardening
- Restrict management access by VLAN.
- Enforce strong admin password + 2FA.
- Periodically rotate SSH keys.

---
End of bootstrap guide.
