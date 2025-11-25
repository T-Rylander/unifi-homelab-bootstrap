# Security Best Practices

## Overview
This document provides production-grade security hardening for the UniFi homelab bootstrap environment. While the repository itself contains no credentials, the **operational environment** handles sensitive data requiring defense-in-depth measures.

---

## 🔐 Backup Security (CRITICAL)

### Threat Model
UniFi backups (`.unf` files + MongoDB dumps) contain:
- **WiFi PSKs** (all SSIDs including hidden networks)
- **RADIUS shared secrets** (if enterprise auth configured)
- **Admin password hashes** (bcrypt, but still sensitive)
- **Network topology** (VLANs, firewall rules, device locations)
- **SNMP community strings**
- **VPN credentials** (if configured)

**Impact of breach:** Full network compromise, credential harvesting, topology reconnaissance for targeted attacks.

### Encryption at Rest (MANDATORY for Production)

**GPG Symmetric Encryption (AES256):**
```bash
# Initialize passphrase file (one-time setup)
sudo bash -c "echo 'YourStrongRandomPassphrase123!@#' > /root/.unifi-backup-passphrase"
sudo chmod 600 /root/.unifi-backup-passphrase

# Verify permissions
ls -l /root/.unifi-backup-passphrase
# Output should be: -rw------- 1 root root (600 permissions)
```

**Passphrase Requirements:**
- Minimum 20 characters
- Mix of uppercase, lowercase, numbers, symbols
- Store securely (password manager, encrypted vault)
- **DO NOT commit to git** (already in `.gitignore`)

**Backup Script Behavior:**
- `ENABLE_ENCRYPTION=true` (default): Creates `.gpg` encrypted files, deletes unencrypted `.tar.gz`
- `ENABLE_ENCRYPTION=false`: Leaves backups unencrypted (NOT recommended)

**Manual Decryption (for restore):**
```bash
# Decrypt backup
gpg --decrypt unifi-backup-2025-11-25_02-00-00.tar.gz.gpg > unifi-backup-2025-11-25_02-00-00.tar.gz

# Verify integrity
sha256sum -c unifi-backup-2025-11-25_02-00-00.tar.gz.gpg.sha256

# Extract
tar -xzf unifi-backup-2025-11-25_02-00-00.tar.gz
```

### Offsite Backup Security

**Encrypted sync to remote storage:**
```bash
# Example: rclone to encrypted cloud storage
rclone sync /backup/unifi remote:unifi-backups --exclude "*.tar.gz" --include "*.gpg"

# rsync over SSH with key-based auth
rsync -avz --include="*.gpg" --exclude="*.tar.gz" /backup/unifi/ backup-server:/backups/unifi/
```

**DO NOT:**
- Upload unencrypted backups to cloud storage
- Store backups on same physical host (no DR capability)
- Use unencrypted protocols (FTP, HTTP) for offsite transfers

---

## 🛡️ MongoDB Hardening

### Localhost-Only Binding (Default - Verify)

**Check current binding:**
```bash
sudo ss -tulpn | grep 27017
```
**Expected output:** `127.0.0.1:27017` (localhost only)  
**Dangerous output:** `0.0.0.0:27017` (all interfaces - exposed to network)

**If exposed, fix immediately:**
```bash
sudo nano /etc/mongod.conf

# Ensure these settings:
net:
  bindIp: 127.0.0.1
  port: 27017

# Restart MongoDB
sudo systemctl restart mongod
```

### Authentication (Optional for Phase 1, Mandatory for Phase 2+)

Phase 1 (single-server UniFi only): Authentication not required (localhost binding sufficient).  
Phase 2+ (Samba AD integration): Enable MongoDB authentication.

```bash
# Create admin user (inside mongo shell)
mongo
use admin
db.createUser({
  user: "admin",
  pwd: "StrongPasswordHere",
  roles: [ { role: "userAdminAnyDatabase", db: "admin" } ]
})

# Enable authentication in config
sudo nano /etc/mongod.conf
security:
  authorization: enabled

sudo systemctl restart mongod
```

**Update UniFi connection string** (if authentication enabled):  
Edit `/usr/lib/unifi/data/system.properties`:
```properties
db.mongo.uri=mongodb://admin:StrongPasswordHere@127.0.0.1:27017/ace
```

---

## 🔥 Firewall Configuration (UFW)

### Phase 1: Bootstrap VLAN (10.0.1.0/24)

**Initial setup (permissive for adoption):**
```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing

# SSH (critical - lock to management IP if known)
sudo ufw allow from 10.0.1.0/24 to any port 22

# UniFi Controller (bootstrap network access)
sudo ufw allow from 10.0.1.0/24 to any port 8080
sudo ufw allow from 10.0.1.0/24 to any port 8443
sudo ufw allow from 10.0.1.0/24 to any port 8880
sudo ufw allow from 10.0.1.0/24 to any port 8843

# STUN (device discovery - UDP)
sudo ufw allow 3478/udp
sudo ufw allow 10001/udp

# Enable firewall
sudo ufw enable
sudo ufw status verbose
```

### Phase 2: Production (Servers VLAN 10.0.10.0/24)

**After VLAN migration, restrict to management VLAN:**
```bash
# Remove bootstrap VLAN rules
sudo ufw delete allow from 10.0.1.0/24 to any port 8443

# Add production rules (management VLAN only)
sudo ufw allow from 10.0.20.0/24 to any port 8080 comment 'UniFi inform (devices)'
sudo ufw allow from 10.0.30.0/24 to any port 8443 comment 'Controller UI (user VLAN)'
sudo ufw allow from 10.0.10.0/24 to any port 8443 comment 'Controller UI (servers)'

# Lock SSH to management VLAN + specific admin IP
sudo ufw delete allow from 10.0.1.0/24 to any port 22
sudo ufw allow from 10.0.30.5 to any port 22 comment 'Admin workstation only'

sudo ufw reload
```

**Deny internet access to controller (optional hardening):**
```bash
# Requires local apt mirror or exception for updates
sudo ufw deny out to any port 80,443
```

---

## 🔑 Controller Access Hardening

### Strong Admin Credentials

**Password requirements:**
- Minimum 20 characters
- Passphrase-style recommended: `CorrectHorseBatteryStaple2025!`
- Use password manager (KeePass, Bitwarden)

**Enable Two-Factor Authentication:**
1. UniFi UI → Settings → Admins → [Your Account]
2. Enable "Two-Factor Authentication"
3. Scan QR code with authenticator app (Authy, Google Authenticator)
4. Store backup codes securely

### Session Management

**Controller settings (Settings → System → Advanced):**
- Auto-logout idle sessions: 15 minutes
- Restrict UI access to specific VLANs (firewall rules above)
- Disable remote access (Ubiquiti cloud) if not required

### TLS Certificate Hardening

**Replace self-signed certificate:**
- **Let's Encrypt:** Requires public DNS or DNS-01 challenge (Phase 2 with Samba AD DNS)
- **Internal CA:** Issue from Samba AD Certificate Services (Phase 2)

**Example (Let's Encrypt with certbot):**
```bash
sudo certbot certonly --standalone -d unifi.rylan-home.local
sudo cp /etc/letsencrypt/live/unifi.rylan-home.local/fullchain.pem /usr/lib/unifi/data/
sudo cp /etc/letsencrypt/live/unifi.rylan-home.local/privkey.pem /usr/lib/unifi/data/
sudo chown unifi:unifi /usr/lib/unifi/data/*.pem
sudo systemctl restart unifi
```

---

## 🌐 Network Segmentation (VLAN Isolation)

### Inter-VLAN Firewall Rules

**Implement principle of least privilege:**
- Guest/IoT VLAN 90 → **DENY** all RFC1918 (no LAN access)
- User VLAN 30 → **ALLOW** specific services only (DNS, AD, controller UI)
- Management VLAN 20 → **DENY** internet (devices don't need WAN)

See `docs/firewall-rules.md` for complete ruleset.

### Controller VLAN Placement

**Phase 1:** Bootstrap VLAN 1 (10.0.1.10)  
**Phase 2+:** Servers VLAN 10 (10.0.10.10) — isolated from user traffic

**Static DHCP reservation critical:** Prevents IP changes breaking device adoption.

---

## 🔍 Audit and Monitoring

### Log Monitoring

**Critical logs to monitor:**
```bash
# Controller authentication failures
sudo tail -f /var/log/unifi/server.log | grep -i "authentication failed"

# MongoDB unauthorized access attempts
sudo tail -f /var/log/mongodb/mongod.log | grep -i "unauthorized"

# UFW denied connections
sudo tail -f /var/log/ufw.log | grep -i "BLOCK"
```

**Centralized logging (Phase 3 - optional):**
- Ship logs to Graylog/ELK/Splunk
- Alert on anomalies (brute force, privilege escalation)

### Security Checklist (Quarterly Review)

- [ ] Backup encryption enabled (`ENABLE_ENCRYPTION=true`)
- [ ] GPG passphrase file permissions `600` (root-only)
- [ ] MongoDB bound to `127.0.0.1` only
- [ ] UFW enabled with VLAN-specific rules
- [ ] Controller admin 2FA enabled
- [ ] TLS certificate valid (not self-signed)
- [ ] Offsite encrypted backups tested (restore drill)
- [ ] No credentials in git repository (`.gitignore` enforced)
- [ ] SSH key-based auth only (password auth disabled)
- [ ] Samba AD security policies applied (Phase 2)

---

## 📞 Incident Response

### Suspected Compromise

**Immediate actions:**
1. **Isolate controller:** Disconnect network interface or shutdown VM.
2. **Rotate credentials:** Change admin password, WiFi PSKs, RADIUS secrets.
3. **Audit logs:** Check `/var/log/unifi/server.log` for unauthorized access.
4. **Factory reset devices:** If attacker adopted rogue devices.
5. **Restore from backup:** Use last known-good encrypted backup.

**Forensics:**
```bash
# Check active admin sessions
curl -k https://localhost:8443/api/s/default/stat/admin

# Review MongoDB for unauthorized changes
mongo ace --eval "db.admin.find().pretty()"

# UFW connection log analysis
sudo grep "DPT=8443" /var/log/ufw.log | awk '{print $12}' | sort | uniq -c
```

---

## 📚 Security Resources

**Official Documentation:**
- [Ubiquiti UniFi Security Best Practices](https://help.ui.com/hc/en-us/articles/204952154)
- [MongoDB Security Checklist](https://docs.mongodb.com/manual/administration/security-checklist/)
- [Ubuntu UFW Configuration](https://help.ubuntu.com/community/UFW)

**Community Audits:**
- r/Ubiquiti security discussions
- SANS homelab hardening guides
- NIST Cybersecurity Framework (CSF) for small networks

---

**Last Updated:** 2025-11-25  
**Audit Frequency:** Quarterly (or after major configuration changes)
