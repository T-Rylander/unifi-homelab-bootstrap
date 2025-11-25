# Firewall Rules

## UniFi Firewall Rule Format
| Field | Description |
|-------|-------------|
| Name  | Descriptive, include direction + purpose |
| Action| Accept / Drop / Reject |
| Protocol | TCP / UDP / Any |
| Source / Destination | Networks, VLANs, IP ranges |
| Logging | Enable for deny rules (sample only) |

Naming Convention: `<Direction>-<Zone>-<Purpose>` (e.g., `LAN_IN-IoT-Deny-RFC1918`).

## LAN IN Rules (Examples)
### Management VLAN (1)
- Allow full access to controller services (8080, 8443, STUN 3478).

### IoT VLAN (10)
| Name | Action | Src | Dst | Protocol/Ports | Notes |
|------|--------|-----|-----|----------------|-------|
| LAN_IN-IoT-Deny-RFC1918 | Drop | IoT | RFC1918 | Any | Blocks lateral movement |
| LAN_IN-IoT-Allow-Internet | Accept | IoT | WAN | Any | Default outbound |

### Guest VLAN (20)
| Name | Action | Src | Dst | Protocol/Ports | Notes |
|------|--------|-----|-----|----------------|-------|
| LAN_IN-Guest-Deny-RFC1918 | Drop | Guest | RFC1918 | Any | Guest isolation |
| LAN_IN-Guest-Allow-Internet | Accept | Guest | WAN | Any | Captive portal + internet |

### Servers VLAN (30)
| Name | Action | Src | Dst | Protocol/Ports | Notes |
|------|--------|-----|-----|----------------|-------|
| LAN_IN-Servers-Allow-SSH-Controller | Accept | Servers | Controller | TCP/22 | Administrative access |
| LAN_IN-Servers-Allow-HTTPS-Controller | Accept | Servers | Controller | TCP/8443 | API/UI access |
| LAN_IN-Servers-Deny-Unused | Drop | Servers | IoT/Guest | Any | Reduce risk surface |

## WAN OUT Rules
| Name | Action | Src | Dst | Ports | Notes |
|------|--------|-----|-----|-------|-------|
| WAN_OUT-Default-Allow | Accept | Any | WAN | Any | Standard outbound |
| WAN_OUT-Log-Deny | Drop (log) | Any | WAN | High-risk (e.g., known bad) | Optional logging rule |

## Port Forwarding Examples (If Required)
| External Port | Internal IP | Internal Port | Protocol | Purpose |
|---------------|-------------|---------------|----------|---------|
| 8443 | 192.168.1.10 | 8443 | TCP | Remote UI access |
| 3478 | 192.168.1.10 | 3478 | UDP | STUN for remote adoption |

Security Warning: Exposing controller UI to WAN increases attack surface. Prefer VPN for remote management.

## Rule Review Process
1. Audit quarterly.
2. Export firewall config before changes.
3. Enable logging selectively to avoid performance impact.

---
End of firewall rule document.
