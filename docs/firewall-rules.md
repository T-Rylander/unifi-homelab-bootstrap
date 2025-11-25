# Firewall Rules (v4.2 VLANs)

## UniFi Firewall Rule Format
| Field | Description |
|-------|-------------|
| Name  | `<Direction>-<SrcVLAN>-<DstVLAN>-<Purpose>` |
| Action| Accept / Drop / Reject |
| Protocol | TCP / UDP / Any |
| Source / Destination | VLAN networks (10.0.x.0/24) or Port Groups |
| Logging | Enable for deny rules (troubleshooting only) |

**Configuration Location:** Settings > Security > Firewall & Security > Create New Rule (LAN IN, LAN OUT, WAN IN).

## LAN IN Rules (Inter-VLAN Access Control)
### User Devices (30) → Servers (10)
| Name | Action | Src | Dst | Protocol/Ports | Notes |
|------|--------|-----|-----|----------------|-------|
| LAN_IN-User-Servers-DNS | Accept | 10.0.30.0/24 | 10.0.10.10 | UDP/53 | DNS resolution |
| LAN_IN-User-Servers-AD | Accept | 10.0.30.0/24 | 10.0.10.10 | TCP/88,389,636 | AD authentication |
| LAN_IN-User-Servers-HTTPS | Accept | 10.0.30.0/24 | 10.0.10.10 | TCP/8443 | Controller UI |

### User Devices (30) → User Devices (30) [osTicket]
| Name | Action | Src | Dst | Protocol/Ports | Notes |
|------|--------|-----|-----|----------------|-------|
| LAN_IN-User-osTicket | Accept | 10.0.30.0/24 | 10.0.30.40 | TCP/80,443 | Helpdesk access |

### VoIP (40) → Servers (10)
| Name | Action | Src | Dst | Protocol/Ports | Notes |
|------|--------|-----|-----|----------------|-------|
| LAN_IN-VoIP-Servers-LDAP | Accept | 10.0.40.0/24 | 10.0.10.10 | TCP/389,636 | FreePBX directory |
| LAN_IN-VoIP-Servers-NTP | Accept | 10.0.40.0/24 | 10.0.10.10 | UDP/123 | Time sync |

### VoIP (40) Internal (SIP/RTP)
| Name | Action | Src | Dst | Protocol/Ports | Notes |
|------|--------|-----|-----|----------------|-------|
| LAN_IN-VoIP-VoIP-SIP | Accept | 10.0.40.0/24 | 10.0.40.0/24 | UDP/5060, TCP/5061 | Signaling |
| LAN_IN-VoIP-VoIP-RTP | Accept | 10.0.40.0/24 | 10.0.40.0/24 | UDP/10000-20000 | Media streams |

### Guest/IoT (90) Isolation
| Name | Action | Src | Dst | Protocol/Ports | Notes |
|------|--------|-----|-----|----------------|-------|
| LAN_IN-Guest-Deny-RFC1918 | Drop (Log) | 10.0.90.0/24 | RFC1918 Networks | Any | Block local access |
| LAN_IN-Guest-Allow-Internet | Accept | 10.0.90.0/24 | WAN | Any | Internet only |

### Management (20) → Servers (10) [Controller Access]
| Name | Action | Src | Dst | Protocol/Ports | Notes |
|------|--------|-----|-----|----------------|-------|
| LAN_IN-Mgmt-Servers-UniFi | Accept | 10.0.20.0/24 | 10.0.10.10 | TCP/8080,8443 | Device inform + UI |

## WAN OUT Rules (Egress Control)
| Name | Action | Src | Dst | Ports | Notes |
|------|--------|-----|-----|-------|-------|
| WAN_OUT-Default-Allow | Accept | All VLANs | WAN | Any | Standard outbound (NAT) |
| WAN_OUT-Block-VoIP-Toll-Fraud | Drop | 10.0.40.0/24 | Premium-rate prefixes | TCP/UDP | Optional: geo-blocking |

## WAN IN Rules (Inbound Access - Caution)
**Default:** Drop all (implicit deny). Only add rules if absolutely required.

| Name | Action | Src | Dst | Ports | Notes |
|------|--------|-----|-----|-------|-------|
| WAN_IN-Allow-VPN | Accept | Any | 10.0.10.10 | UDP/51820 (WireGuard) | Secure remote access (Phase 3) |
| WAN_IN-Drop-All | Drop (Log) | Any | Any | Any | Explicit deny + logging |

## Port Forwarding (Avoid if Possible)
**Recommended:** Use VPN (WireGuard/OpenVPN on Servers VLAN) instead of direct port forwards.

If required:
| External Port | Internal IP | Internal Port | Protocol | Purpose | Risk Level |
|---------------|-------------|---------------|----------|---------|------------|
| 51820 | 10.0.10.10 | 51820 | UDP | WireGuard VPN | Low (if keys secured) |
| ~~8443~~ | ~~10.0.10.10~~ | ~~8443~~ | ~~TCP~~ | ~~Controller UI~~ | **HIGH** (do not forward) |

Security Warning: Never expose UniFi controller (8443/8080) directly to WAN. Use VPN tunnel for remote management.

## Rule Application Order (UniFi Processing)
1. WAN IN: First match wins (place specific rules before broad drops).
2. LAN IN: Top-to-bottom evaluation (order matters for overlapping rules).
3. Default Policy: Drop (if no match).

## Rule Review Process
1. **Quarterly Audit:** Review logs for denied traffic patterns; adjust rules.
2. **Change Control:** Export JSON config (`Settings > System > Backup`) before edits.
3. **Logging:** Enable only for deny rules (reduces disk I/O on USG).
4. **Testing:** Use `nmap` or `nc` from isolated VLAN to verify blocks.

## Example Rule Creation (UI Workflow)
1. Settings > Security > Firewall & Security > **Create New Rule**.
2. Type: `LAN IN` (inter-VLAN), `WAN IN` (inbound), `WAN OUT` (egress).
3. Rule Applied: `Before Predefined Rules` (ensures custom logic priority).
4. Action: Accept/Drop/Reject.
5. IPv4 Protocol: TCP/UDP/ICMP/Any.
6. Source: Type `Network`, Value `10.0.30.0/24`.
7. Destination: Type `Network`, Value `10.0.10.10/32`.
8. Port: Destination port `8443`.
9. Enable Logging: Check only for deny rules.
10. Save & provision.

---
End of firewall rules (v4.2).
