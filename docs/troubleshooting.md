# Troubleshooting

## Common Issues
| Issue | Symptom | Likely Cause | Resolution |
|-------|---------|--------------|------------|
| Stuck "Adopting" | Device never finalizes | Inform URL / DNS mismatch | Verify `set-inform` points to controller IP/FQDN |
| MongoDB version mismatch | Service fails to start | Upgraded system repo pulled newer Mongo | Re-run `install-unifi.sh` to re-pin 4.4 |
| Port 8080 in use | Install aborts | Residual process (old service) | `ss -tulpn | grep :8080`; stop conflicting service |
| Missing curl/gnupg | Install script fails at GPG key download | Minimal Ubuntu install lacks required tools | Script auto-installs dependencies (v2.0+) |
| MongoDB repo missing | UniFi install fails: mongodb-org-server not found | MongoDB repository not added | Script v2.1+ auto-adds MongoDB 4.4 repo |
| MongoDB repo indexing fails | `apt-cache policy mongodb-org` returns no candidate | GPG keyring format conflict (Ubuntu 24.04) or apt cache staleness | Run `sudo bash troubleshoot-repo.sh` (dual GPG method + double update) |
| Apt update shows GPG warnings | "Key stored in legacy trusted.gpg keyring" during `apt update` | Modern Ubuntu prefers signed-by keyrings over apt-key | Non-fatal; installer uses both methods for resilience |
| Noble (24.04) missing MongoDB packages | Repository added but `apt-cache` shows no versions | MongoDB 4.4 lacks noble-specific builds | Script auto-detects and uses jammy (22.04) repo on noble systems |
| SSL warnings | Browser shows insecure | Self-signed default cert | Replace with Let's Encrypt or internal CA cert |
| Restore failure | UI missing settings | Partial backup extraction | Re-run restore; check archive integrity (sha256) |

## Diagnostic Commands
| Task | Command |
|------|---------|
| UniFi service status | `systemctl status unifi` |
| MongoDB service status | `systemctl status mongod` |
| Controller logs | `tail -f /var/log/unifi/server.log` |
| Port usage | `ss -tulpn | grep -E '8080|8443|8880|8843'` |
| Java process check | `ps -ef | grep -i unifi` |
| DNS resolution | `dig +short unifi.rylan-home.local` |
| MongoDB version | `mongod --version | head -n1` |
| **MongoDB repo check** | `apt-cache policy mongodb-org` |
| **APT update logs** | `cat /var/log/apt/term.log` (last install) |
| **GPG key verification** | `apt-key list | grep -i mongo` (legacy) or `ls /usr/share/keyrings/mongo*` (modern) |

## Recovery Procedures
### MongoDB Repository Fix (Complete Reset)
**When to use:** `install-unifi.sh` fails at MongoDB install; manual `apt-get install mongodb-org` returns "Unable to locate package."

**Step-by-step:**
```bash
# 1. Run dedicated troubleshooter (preferred method)
cd /root/unifi-homelab-bootstrap
sudo bash troubleshoot-repo.sh
```

**Manual alternative (if troubleshooter unavailable):**
```bash
# 1. Remove existing repo and keys
sudo rm -f /etc/apt/sources.list.d/mongodb-org-4.4.list
sudo rm -f /usr/share/keyrings/mongodb-server-4.4.gpg
sudo apt-key del 656408E390CFB1F5 2>/dev/null  # Legacy key (may not exist)

# 2. Detect Ubuntu version
CODENAME=$(lsb_release -cs)
[[ "$CODENAME" == "noble" ]] && CODENAME="jammy"  # 24.04 fallback

# 3. Add GPG key (dual method for resilience)
curl -fsSL https://www.mongodb.org/static/pgp/server-4.4.asc | \
  sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-4.4.gpg
curl -fsSL https://www.mongodb.org/static/pgp/server-4.4.asc | sudo apt-key add -

# 4. Create repository file
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-4.4.gpg ] https://repo.mongodb.org/apt/ubuntu ${CODENAME}/mongodb-org/4.4 multiverse" | \
  sudo tee /etc/apt/sources.list.d/mongodb-org-4.4.list

# 5. Double update (force cache refresh)
sudo apt-get update -y
sudo apt-get update --fix-missing -y

# 6. Verify (should show 4.4.x candidate version)
apt-cache policy mongodb-org | grep Candidate
```

**Success indicator:** `Candidate: 4.4.29` (or similar 4.4.x version).

**If still failing:**
- Check network: `curl -I https://repo.mongodb.org` (should return HTTP 200).
- Inspect apt logs: `sudo cat /var/log/apt/term.log | grep -i mongo`.
- Verify Ubuntu version compatibility: Only Jammy (22.04) and Focal (20.04) have native MongoDB 4.4 packages; Noble (24.04) uses Jammy repo.

### Controller Reset Without Losing Config
1. Stop service: `systemctl stop unifi`.
2. Backup `/var/lib/unifi/` manually.
3. Reinstall package: `apt-get install --reinstall unifi`.
4. Start service: `systemctl start unifi`.

### Manual Device SSH Adoption
```bash
ssh ubnt@DEVICE_IP "set-inform http://192.168.1.10:8080/inform"
```
Repeat if status remains "Pending" (device re-informs periodically).

### Database Repair (Last Resort)
```bash
systemctl stop unifi
systemctl stop mongodb
mongod --dbpath /var/lib/mongodb --repair
systemctl start mongodb
systemctl start unifi
```
Warning: Repair may take time; ensure sufficient disk space.

## When to Escalate
- Persistent database corruption.
- Consistent high CPU >85% with minimal clients.
- Authentication anomalies (unexpected admin sessions).

---
End of troubleshooting document.
