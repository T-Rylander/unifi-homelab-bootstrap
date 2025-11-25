# VLAN Design (v4.2 Final)

## Network Topology Overview
| VLAN ID | Name         | Subnet        | Gateway    | Purpose                          |
|---------|--------------|---------------|------------|----------------------------------|
| 1       | Bootstrap    | 10.0.1.0/24   | 10.0.1.1   | Initial setup only (Phase 1)     |
| 10      | Servers      | 10.0.10.0/24  | 10.0.10.1  | rylan-dc (Controller + Samba AD) |
| 20      | Management   | 10.0.20.0/24  | 10.0.20.1  | UniFi gear (USG/US-8/APs)        |
| 30      | User Devices | 10.0.30.0/24  | 10.0.30.1  | Workstations, Pi5 osTicket       |
| 40      | VoIP         | 10.0.40.0/24  | 10.0.40.1  | FreePBX + GRP2601P phones        |
| 90      | Guest/IoT    | 10.0.90.0/24  | 10.0.90.1  | Isolated devices                 |

## DHCP Configuration
| VLAN | DHCP Range       | Static Reservations | Lease Time | DNS Servers            |
|------|------------------|---------------------|------------|------------------------|
| 1    | .100-.250        | .10 (rylan-dc)      | 12h        | 8.8.8.8 (Phase 1)      |
| 10   | .100-.200        | .10 (rylan-dc)      | 24h        | 10.0.10.10 (Phase 2 AD)|
| 20   | .100-.150        | .2 (USG), .3 (US-8) | 24h        | 10.0.10.10             |
| 30   | .100-.250        | .40 (Pi5 osTicket)  | 12h        | 10.0.10.10             |
| 40   | .100-.200        | .30 (FreePBX)       | 24h        | 10.0.10.10             |
| 90   | .100-.250        | None                | 8h         | 8.8.8.8 (isolated)     |

## Inter-VLAN Routing Rules (Firewall Logic)
| Source VLAN | Destination VLAN | Action | Ports/Protocol | Rationale |
|-------------|------------------|--------|----------------|-----------|
| User (30)   | Servers (10)     | Allow  | 53/UDP, 88/TCP, 389/TCP | DNS + AD authentication |
| User (30)   | User (30)        | Allow  | 80/443/TCP | osTicket (10.0.30.40) |
| VoIP (40)   | Servers (10)     | Allow  | 389/636/TCP | LDAP for FreePBX directory |
| VoIP (40)   | VoIP (40)        | Allow  | 5060/UDP, 5061/TCP, 10000-20000/UDP | SIP + RTP |
| Guest/IoT (90) | RFC1918       | Drop   | All | Isolation (no local access) |
| Guest/IoT (90) | WAN           | Allow  | All | Internet only |
| Management (20)| Servers (10)  | Allow  | 8080/8443/TCP | Controller API/UI |
| Servers (10) | All VLANs       | Allow  | All | Administrative control |

## VoIP VLAN (40) Configuration Notes (Phase 3)
### DHCP Options for Grandstream GRP2601P
- **Option 66 (TFTP Server):** `tftp://10.0.40.30` (FreePBX auto-provisioning)
- **Option 160 (HTTP URL):** `http://10.0.40.30/provision` (XML config endpoint)

### QoS (DSCP Marking)
- SIP signaling (5060/5061): `EF` (Expedited Forwarding, DSCP 46)
- RTP media (10000-20000): `EF` (DSCP 46)
- Configure via Settings > Profiles > Switch Ports > QoS: Voice priority.

### LLDP-MED
Enable on US-8-60W ports connected to phones (auto-VLAN assignment + PoE class).

## Future Expansion Notes
- **Camera VLAN (50):** High-bandwidth isolated; NVR on Servers VLAN 10.
- **DMZ VLAN (80):** Public-facing services with strict inbound rules.
- **Micro-segmentation:** Per-device firewall rules if compliance required.

## Design Principles
1. **Least Privilege:** Default deny inter-VLAN; explicit allow rules only.
2. **Clear Purpose:** Each VLAN single-function (reduces ACL complexity).
3. **Predictable Addressing:** Static reservations for infrastructure (.10, .30, .40).
4. **Phase Alignment:** Bootstrap (1) → Infrastructure (10/20) → Services (30/40/90).

---
End of VLAN design (v4.2).
