# VLAN Design

## Network Topology Overview
| VLAN ID | Name       | Subnet           | Gateway       | Purpose                |
|---------|------------|------------------|---------------|------------------------|
| 1       | Management | 192.168.1.0/24   | 192.168.1.1   | Core infra + controller|
| 10      | IoT        | 192.168.10.0/24  | 192.168.10.1  | Isolated smart devices |
| 20      | Guest      | 192.168.20.0/24  | 192.168.20.1  | Guest captive portal   |
| 30      | Servers    | 192.168.30.0/24  | 192.168.30.1  | Server & services VLAN |
| TBD     | VoIP       | 192.168.40.0/24  | 192.168.40.1  | Future expansion       |
| TBD     | Cameras    | 192.168.50.0/24  | 192.168.50.1  | Future expansion       |

## DHCP Configuration
| VLAN | DHCP Range              | Exclusions        | Lease Time | DNS Servers              |
|------|-------------------------|-------------------|------------|--------------------------|
| 1    | 192.168.1.100-192.168.1.199 | .10 (controller) | 12h        | 192.168.1.10, 1.1.1.1    |
| 10   | 192.168.10.100-192.168.10.199 | .10 (controller) | 12h        | 192.168.1.10             |
| 20   | 192.168.20.100-192.168.20.199 | N/A             | 8h         | 192.168.1.10             |
| 30   | 192.168.30.100-192.168.30.199 | .10 (controller) | 24h        | 192.168.1.10             |

## Inter-VLAN Routing Rules (Conceptual)
| Source VLAN | Destination | Action | Rationale |
|-------------|-------------|--------|-----------|
| IoT (10)    | RFC1918     | Block  | Prevent lateral movement |
| IoT (10)    | WAN         | Allow  | Internet-only access |
| Guest (20)  | RFC1918     | Block  | Guest isolation |
| Guest (20)  | WAN         | Allow  | Internet access |
| Servers (30)| Management (1) | Allow Specific Ports | Admin protocols (SSH, RDP) |
| Management (1)| All VLANs | Allow  | Administrative control |

## Future Expansion Notes
- VoIP VLAN: QoS prioritization; SIP/RTP specific allowances.
- Camera VLAN: High-bandwidth isolated segment; consider NVR placement.
- Consider segmentation enhancements with micro-segmentation if scale increases.

## Design Principles
1. Least privilege: Limit cross-VLAN access.
2. Clear purpose per VLAN reduces troubleshooting complexity.
3. Predictable addressing eases documentation and monitoring.

---
End of VLAN design document.
