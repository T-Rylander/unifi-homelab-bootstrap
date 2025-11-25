# Troubleshooting

## Common Issues
| Issue | Symptom | Likely Cause | Resolution |
|-------|---------|--------------|------------|
| Stuck "Adopting" | Device never finalizes | Inform URL / DNS mismatch | Verify `set-inform` points to controller IP/FQDN |
| MongoDB version mismatch | Service fails to start | Upgraded system repo pulled newer Mongo | Re-run `install-unifi.sh` to re-pin 4.4 |
| Port 8080 in use | Install aborts | Residual process (old service) | `ss -tulpn | grep :8080`; stop conflicting service |
| Missing curl/gnupg | Install script fails at GPG key download | Minimal Ubuntu install lacks required tools | Script auto-installs dependencies (v2.0+) |
| MongoDB repo missing | UniFi install fails: mongodb-org-server not found | MongoDB repository not added | Script v2.1+ auto-adds MongoDB 4.4 repo |
| SSL warnings | Browser shows insecure | Self-signed default cert | Replace with Let's Encrypt or internal CA cert |
| Restore failure | UI missing settings | Partial backup extraction | Re-run restore; check archive integrity (sha256) |

## Diagnostic Commands
| Task | Command |
|------|---------|
| UniFi service status | `systemctl status unifi` |
| MongoDB service status | `systemctl status mongodb` |
| Controller logs | `tail -f /var/log/unifi/server.log` |
| Port usage | `ss -tulpn | grep -E '8080|8443|8880|8843'` |
| Java process check | `ps -ef | grep -i unifi` |
| DNS resolution | `dig +short unifi.rylan-home.local` |
| MongoDB version | `mongo --quiet --eval 'db.version()'` |

## Recovery Procedures
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
