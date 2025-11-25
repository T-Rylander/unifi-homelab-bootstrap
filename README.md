# UniFi Homelab Bootstrap

> Production‑grade, native (non‑Docker) deployment of the UniFi Network Application (Controller) on Ubuntu 24.04 LTS. Clean server foundation—Phase 1 (UniFi only), Phase 2 (Samba AD integration), Phase 3 (services: FreePBX, osTicket). Zero‑touch bootstrap for long‑term homelab stability.

## Mission Statement
Provide a reproducible, zero‑touch bootstrap process for installing, operating, backing up, and restoring a UniFi Network Application on a fresh Ubuntu 24.04 server. Phased architecture enables controlled expansion: Phase 1 establishes network foundation; Phase 2 adds Active Directory; Phase 3 layers services (VoIP, ticketing). Designed for 5+ year operational stability and ops handoff readiness.

## Hardware / Platform
| Component | Model | Role | Notes |
|-----------|-------|------|-------|
| `rylan-dc` | Dell R620 | Ubuntu 24.04 LTS Server | Fresh install; UniFi Controller (Phase 1), Samba AD (Phase 2) |
| Gateway | USG-3P | Edge routing | Factory reset; adopts first |
| Core Switch | US-8-60W | Upstairs PoE distribution | 8-port managed; powers APs |
| Trunk Switch | TL-SG108 | Downstairs 5-port | Unmanaged; no adoption (trunk only) |
| Access Points | 2× UAP-AC-Lite | Wireless coverage | Factory reset; adopt after switches |
| Future VoIP | GRP2601P | Desk phones | Phase 3: VLAN 40, DHCP opt 66/160 |

## Prerequisites Checklist (Phase 1: Clean Server)
- Fresh Ubuntu 24.04 LTS installation (server, minimal packages) on `rylan-dc`.
- Static IP configured: `10.0.1.10/24` (bootstrap VLAN 1), gateway `10.0.1.1`.
- DNS: Use public resolver (8.8.8.8) initially; migrate to AD in Phase 2.
- Outbound internet access for apt repositories.
- System time synchronized (systemd-timesyncd default OK).
- Sufficient resources: ≥2 vCPU, ≥4GB RAM, ≥32GB storage.
- Open ports (ensure unused): 8080, 8443, 8880, 8843, 3478/udp, 10001/udp.
- SSH access with key‑based authentication for administrative scripts.
- **NO Samba** installed yet—Phase 2 only.

## Quick Start (Phase 1: Three Steps)
1. **Install Controller:** `sudo bash install-unifi.sh` (runtime: ~5min)
2. **Adopt Devices:** Power sequence: USG-3P (wait 5min provision) → US-8-60W → APs. UI: `https://10.0.1.10:8443`. Fallback: `sudo bash adopt-devices.sh`.
3. **Configure VLANs + Backups:** Settings > Networks (create v4.2 VLANs). Schedule `backup-unifi.sh` via cron.

**Next:** Phase 2 (Samba AD integration—separate guide), Phase 3 (FreePBX on VLAN 40, osTicket on User VLAN 30).

## ASCII Architecture Diagram (v4.2 Final)
```
    ISP (WAN)
        |
    [USG-3P] (10.0.1.1 bootstrap → 10.0.20.2 mgmt VLAN 20)
        |
   [US-8-60W] (Upstairs PoE Core, VLAN 20: 10.0.20.3)
        |   \ 
        |    +--[UAP-AC-Lite] (10.0.20.10)
        |    +--[UAP-AC-Lite] (10.0.20.11)
        |
    (1Gb Cat6 Trunk: All VLANs)
        |
   [TL-SG108] (Unmanaged 5-port, downstairs—no adoption)
        |
        +--[rylan-dc] (10.0.1.10 bootstrap → 10.0.10.10 Servers VLAN)
        |              Phase 1: UniFi Controller
        |              Phase 2: + Samba AD DC
        +--[Future: FreePBX] (VLAN 40: 10.0.40.30)
        +--[Future: Pi5 osTicket] (VLAN 30: 10.0.30.40)
        +--[Workstations] (VLAN 30: User Devices)
```

## VLAN Design (v4.2 Final)
| VLAN ID | Name | Subnet | Gateway | Purpose |
|---------|------|--------|---------|----------|
| 1 | Bootstrap | 10.0.1.0/24 | 10.0.1.1 | Initial setup only |
| 10 | Servers | 10.0.10.0/24 | 10.0.10.1 | rylan-dc infrastructure |
| 20 | Management | 10.0.20.0/24 | 10.0.20.1 | UniFi gear (USG/US-8/APs) |
| 30 | User Devices | 10.0.30.0/24 | 10.0.30.1 | Workstations, Pi5 osTicket |
| 40 | VoIP | 10.0.40.0/24 | 10.0.40.1 | FreePBX + GRP2601P phones |
| 90 | Guest/IoT | 10.0.90.0/24 | 10.0.90.1 | Isolated devices |

See `docs/vlan-design.md` for DHCP ranges, inter-VLAN firewall rules, and QoS.

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
- Target UniFi Network Application: Tested `8.5.93` (November 2025 baseline).
- MongoDB: **Bundled with UniFi package** (4.4.x included—no manual repo needed post-8.1+).
- Java: Bundled with UniFi (OpenJDK 17+); avoid system Java conflicts.
- Ubuntu: 24.04 LTS Server (noble); kernel 6.8+.

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
