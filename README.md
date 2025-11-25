# UniFi Homelab Bootstrap

> Production‑grade, native (non‑Docker) deployment of the UniFi Network Application (Controller) on Ubuntu 24.04 LTS alongside a Samba Active Directory Domain Controller in a long‑term homelab environment (`rylan-home.local`).

## Mission Statement
Provide a reproducible, zero‑touch bootstrap process for installing, operating, backing up, and restoring a UniFi Network Application in a mixed infrastructure homelab where stability, maintainability, and auditability matter over 5+ years.

## Hardware / Platform
| Component | Role | Notes |
|-----------|------|-------|
| `rylan-dc` | Ubuntu 24.04 LTS Server | Hosts Samba AD DC + UniFi Controller |
| USG / Gateway | Edge routing | Factory reset prior to adoption |
| UniFi Switches | Switching fabric | All reset; VLANs defined post‑bootstrap |
| UniFi APs | Wireless | Reset; adoption via Layer 2 preferred |

## Prerequisites Checklist
- Fresh Ubuntu 24.04 LTS installation (server, minimal packages) on `rylan-dc`.
- Static IP configured (e.g. `192.168.1.10`).
- DNS A record: `unifi.rylan-home.local` → `192.168.1.10` in Samba AD.
- Outbound internet access for apt repositories.
- System time synchronized (chrony or systemd-timesyncd).
- Sufficient resources: ≥2 vCPU, ≥2GB RAM, ≥16GB storage.
- Open ports (ensure unused): 8080, 8443, 8880, 8843, 3478/udp.
- SSH access with key‑based authentication for administrative scripts.

## Quick Start (Three Steps)
1. Install Controller: `sudo bash install-unifi.sh`
2. Adopt Devices: Power on devices (gateway → switches → APs) and complete setup wizard at `https://unifi.rylan-home.local:8443`. Use `adopt-devices.sh` if stuck.
3. Configure Backups: Schedule `backup-unifi.sh` via cron (example inside script).

## ASCII Architecture Diagram
```
+---------------------------------------------------------------+
|                        rylan-home.local                       |
|                                                               |
|  +-------------+      +------------------+                    |
|  |  Clients    |----->|  UniFi APs (L2)  |                    |
|  +-------------+      +------------------+                    |
|          |                      |                            |
|          |                +-----------+                      |
|          +--------------->| Switches  |<----------------+    |
|                           +-----------+                 |    |
|                                   |                      |    |
|                               +-------+                  |    |
|       +-----------------------|  USG  |------------------+    |
|       |                       +-------+                       |
|       |                           | WAN                       |
|  +----------+  AD / DNS  +---------------+                     |
|  |  Clients |<---------->| rylan-dc (AD) |                     |
|  +----------+            | + UniFi Ctrl |                     |
|                          +---------------+                     |
+---------------------------------------------------------------+
```

## Repository Contents
| Path | Purpose |
|------|---------|
| `install-unifi.sh` | Idempotent UniFi + MongoDB 4.4 installer (with repo pinning & port checks) |
| `adopt-devices.sh` | Batch / individual SSH "set-inform" adoption helper |
| `backup-unifi.sh` | Daily backup (UniFi `.unf` + MongoDB dump + retention) |
| `restore-unifi.sh` | Interactive restore workflow with safety checks |
| `docs/` | Detailed operational / design documentation |
| `.github/workflows/` | CI: daily backup runner & script validation |
| `devices.txt` | Example list of device IPs for adoption batch mode |
| `LICENSE` | MIT License |

See `docs/bootstrap-guide.md` to begin.

## Workflows / Badges
| Workflow | Status Badge |
|----------|--------------|
| Validate Scripts | ![Validate Scripts](https://github.com/rylan-miller/unifi-homelab-bootstrap/actions/workflows/validate-scripts.yml/badge.svg) |
| Daily Backup | ![Daily Backup](https://github.com/rylan-miller/unifi-homelab-bootstrap/actions/workflows/backup-daily.yml/badge.svg) |

*(Badges will render after repository & workflow creation.)*

## Version Compatibility
- Target UniFi Network Application: Tested baseline `8.0.28` (adjust as releases progress).
- MongoDB pinned: `4.4.x` (UniFi 8.x requirement). NOTE: Ubuntu 24.04 (noble) does not have native MongoDB 4.4 packages; script leverages focal repository with pinning and explicit version constraints.
- Java: Use bundled UniFi Java (avoid system default overrides).

## Security Considerations
- Prefer SSH key authentication for all administrative scripts (avoid passwords in automation).
- Restrict controller access via firewall to trusted management VLAN(s).
- Enable strong admin password and consider 2FA.
- Backups contain sensitive configuration; store compressed archives in encrypted volume or offsite storage with access controls.
- Validate integrity of packages by using official GPG keys (script enforced).

## Troubleshooting (Summary)
| Symptom | Likely Cause | Reference |
|---------|--------------|-----------|
| Device stuck "Adopting" | DNS / inform URL mismatch | `docs/troubleshooting.md` |
| Port 8080 conflict | Residual process (old controller, other app) | `install-unifi.sh` preflight |
| MongoDB start failure | Version mismatch / repository issue | `install-unifi.sh` logs |
| SSL browser warning | Self‑signed certificate default | See `docs/bootstrap-guide.md` |
| Backup restore error | Version incompatibility | `restore-unifi.sh` checks |

## Operational Lifecycle
- Daily automated backups (GitHub Action + local cron) ensure restore points.
- Validation CI enforces shell and markdown hygiene (`shellcheck`, markdown lint, YAML validation).
- Documentation kept modular for future expansion (VLANs, firewall rules, migrations).

## Contributing / Maintenance
1. Fork & branch (`feat/vlan-refactor`, `fix/backup-retention`).
2. Run `validate-scripts.yml` locally equivalent: `shellcheck *.sh`.
3. Open PR with summary + testing notes.
4. Keep scripts idempotent and avoid destructive operations outside explicit restore sequence.

## License
MIT – see `LICENSE`.

---
For deep dives: `docs/vlan-design.md`, `docs/firewall-rules.md`, `docs/bootstrap-guide.md`, `docs/ai-copilot-commands.md`.
