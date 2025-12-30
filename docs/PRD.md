# LanLens - Product Requirements Document

**Version:** 1.0
**Date:** December 29, 2024
**Status:** In Development

---

## 1. Executive Summary

### 1.1 Problem Statement

Home networks have become increasingly complex with dozens of "smart" devices that:
- Phone home to cloud services without user awareness
- Run embedded web servers and APIs
- Communicate on various protocols (mDNS, SSDP, MQTT)
- May have security vulnerabilities or unexpected behaviors

Existing solutions like UniFi's app show device presence but don't classify device intelligence or identify what makes a device "smart."

### 1.2 Solution

**LanLens** is a native macOS application that autonomously discovers and classifies network devices, identifying which ones exhibit "smart" behavior through protocol analysis, port scanning, and service detection.

### 1.3 Key Value Proposition

- **Visibility**: See all devices on your network with vendor identification
- **Intelligence**: Automatically classify devices by "smart score" based on detected behaviors
- **API-Driven**: REST API enables automation and iOS companion app
- **Privacy-First**: Runs locally on your Mac Mini, no cloud dependency

---

## 2. Background & Context

### 2.1 User Profile

**Primary User:** Tech-savvy homeowner with:
- UniFi-based network infrastructure (UDM, switches, APs)
- Mac Mini M4 available as always-on server
- Apple TV boxes and various smart home devices
- Desire to understand network device behavior

### 2.2 Existing Solutions Considered

| Solution | Limitation |
|----------|------------|
| UniFi App | Shows devices but no smart classification |
| Pi-hole/AdGuard | DNS-based, requires network reconfiguration |
| Fing | Consumer-focused, limited API |
| nmap | Command-line only, no persistence |

### 2.3 Design Principles

1. **Native Mac experience** - SwiftUI menu bar app
2. **Passive by default** - No network disruption
3. **Active on demand** - Port scanning when requested
4. **API-first** - Enable iOS app and automation
5. **No auto-installation** - Don't install tools without asking

---

## 3. Product Requirements

### 3.1 Functional Requirements

#### FR-1: Device Discovery

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-1.1 | Read ARP table to enumerate network devices | P0 |
| FR-1.2 | Resolve MAC addresses to vendor names | P0 |
| FR-1.3 | Listen for mDNS/Bonjour service advertisements | P0 |
| FR-1.4 | Listen for SSDP/UPnP announcements | P0 |
| FR-1.5 | Use dns-sd command for reliable mDNS discovery | P0 |
| FR-1.6 | Support multiple subnets/VLANs | P1 |
| FR-1.7 | Active subnet ping sweep on demand | P1 |

#### FR-2: Smart Classification

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-2.1 | Calculate "smart score" (0-100) per device | P0 |
| FR-2.2 | Detect smart signals from mDNS service types | P0 |
| FR-2.3 | Detect smart signals from SSDP responses | P0 |
| FR-2.4 | Detect smart signals from open ports | P0 |
| FR-2.5 | Infer device type (TV, speaker, camera, etc.) | P0 |
| FR-2.6 | Support user-defined labels/overrides | P1 |

#### FR-3: Port Scanning

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-3.1 | Socket-based port scanning (no dependencies) | P0 |
| FR-3.2 | nmap integration when available | P0 |
| FR-3.3 | Service version detection via nmap | P1 |
| FR-3.4 | Quick scan mode (10 common ports) | P0 |
| FR-3.5 | Full scan mode (28 smart device ports) | P0 |

#### FR-4: REST API

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-4.1 | List all discovered devices | P0 |
| FR-4.2 | List smart devices with minimum score filter | P0 |
| FR-4.3 | Get device details by MAC address | P0 |
| FR-4.4 | Trigger passive discovery | P0 |
| FR-4.5 | Trigger port scan for device | P0 |
| FR-4.6 | Simple token authentication | P0 |
| FR-4.7 | WebSocket for real-time updates | P2 |

#### FR-5: User Interface

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-5.1 | Menu bar presence with status indicator | P1 |
| FR-5.2 | Dropdown showing device list | P1 |
| FR-5.3 | Smart/regular device sections | P1 |
| FR-5.4 | Device detail view | P1 |
| FR-5.5 | Settings panel | P1 |
| FR-5.6 | Launch at login option | P2 |

#### FR-6: Persistence

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-6.1 | Store device history in SQLite | P1 |
| FR-6.2 | Track first/last seen timestamps | P1 |
| FR-6.3 | Persist user labels | P1 |
| FR-6.4 | Export to JSON/CSV | P2 |

### 3.2 Non-Functional Requirements

| ID | Requirement | Target |
|----|-------------|--------|
| NFR-1 | ARP table read latency | < 500ms |
| NFR-2 | API response time | < 100ms |
| NFR-3 | Memory footprint | < 50MB |
| NFR-4 | CPU usage (idle) | < 1% |
| NFR-5 | Startup time | < 2s |

### 3.3 Constraints

- **macOS 14+** (Sonoma) required for latest SwiftUI features
- **No root access** - use standard user permissions
- **Local network only** - no internet connectivity required
- **Optional tools** - nmap enhances but isn't required

---

## 4. Technical Architecture

### 4.1 Technology Stack

| Layer | Technology |
|-------|------------|
| Language | Swift 5.9+ |
| UI Framework | SwiftUI |
| Networking | Network.framework |
| API Server | Hummingbird 2.0 |
| Database | SQLite.swift |
| Package Manager | Swift Package Manager |

### 4.2 Module Structure

```
LanLensCore (Library)
├── Discovery/
│   ├── ARPScanner        # ARP table reading
│   ├── MDNSListener      # NWBrowser-based mDNS
│   ├── DNSSDScanner      # dns-sd command wrapper
│   ├── SSDPListener      # UPnP/SSDP discovery
│   ├── PortScanner       # nmap/socket scanning
│   └── DiscoveryManager  # Orchestration
├── Models/
│   └── Device            # Core data models
├── Utilities/
│   ├── ShellExecutor     # Command execution
│   ├── ToolChecker       # External tool detection
│   └── MACVendorLookup   # OUI database
├── API/
│   └── APIServer         # REST endpoints
└── Storage/
    └── DeviceStore       # SQLite persistence (TODO)

LanLens (Executable)
└── App/
    └── main.swift        # CLI entry point
```

### 4.3 External Dependencies

| Tool | Path | Required | Purpose |
|------|------|----------|---------|
| arp | /usr/sbin/arp | Yes | ARP table reading |
| dns-sd | /usr/bin/dns-sd | Yes | mDNS discovery |
| nmap | /opt/homebrew/bin/nmap | No | Port scanning |
| arp-scan | /opt/homebrew/bin/arp-scan | No | Active ARP scanning |

### 4.4 API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /health | Health check |
| GET | /api/devices | List all devices |
| GET | /api/devices/smart | List smart devices |
| GET | /api/devices/:mac | Get device by MAC |
| GET | /api/discover/arp | Read ARP table |
| POST | /api/discover/passive | Run passive discovery |
| POST | /api/discover/dnssd | Run dns-sd discovery |
| POST | /api/scan/ports/:mac | Scan ports for device |
| POST | /api/scan/quick | Quick scan all devices |
| POST | /api/scan/full | Full scan all devices |
| GET | /api/scan/nmap-status | Check nmap availability |
| GET | /api/tools | Check tool status |

---

## 5. Smart Score Algorithm

### 5.1 Signal Types

| Signal Type | Weight Range | Examples |
|-------------|--------------|----------|
| mDNS Service | 10-30 | HomeKit (+30), AirPlay (+25), HTTP (+15) |
| SSDP/UPnP | 10-25 | MediaRenderer (+25), Basic (+10) |
| Open Port | 5-30 | MQTT (+25), RTSP (+20), HTTP (+5) |
| Vendor Match | 0-10 | Known IoT vendor (+10) |

### 5.2 Score Calculation

```
smartScore = min(100, Σ(signal.weight) + serviceBonux + portBonus)

serviceBonux = services.count > 0 ? 5 : 0
portBonus = openPorts.count * 5
```

### 5.3 Device Type Inference

Priority order:
1. mDNS service type (highest confidence)
2. SSDP device description
3. Open port combination
4. Vendor name matching

---

## 6. User Interface Design

### 6.1 Menu Bar States

| State | Icon | Indicator |
|-------|------|-----------|
| Idle | Lens icon | Gray |
| Scanning | Lens icon | Pulsing blue |
| New device | Lens icon | Brief green flash |
| API running | Lens icon | Small green dot |

### 6.2 Device List Layout

```
┌──────────────────────────────────────┐
│ 🔍 LanLens                      ⚙️   │
├──────────────────────────────────────┤
│ SMART DEVICES (5)                    │
│ ────────────────────────────────────│
│ 📺 Living Room TV         ●●●●○ 85  │
│    192.168.1.45 • Samsung           │
│                                      │
│ OTHER DEVICES (12)               ▼  │
├──────────────────────────────────────┤
│ 🔄 Scan Now │ 🟢 API: Running │ ··· │
└──────────────────────────────────────┘
```

### 6.3 Color Scheme

**Dark Mode:**
- Background: #1E1E1E
- Card: #2D2D2D
- Accent: #007AFF
- Success: #30D158

**Light Mode:**
- Background: #FFFFFF
- Card: #F2F2F7
- Accent: #007AFF
- Success: #34C759

---

## 7. Implementation Phases

### Phase 1: Core Engine (COMPLETED)

- [x] MAC vendor database (~500 OUIs)
- [x] ARP table scanner
- [x] mDNS listener (NWBrowser)
- [x] dns-sd command scanner
- [x] SSDP/UPnP listener
- [x] Port scanner (socket + nmap)
- [x] Smart score calculation
- [x] REST API server
- [x] CLI interface

### Phase 2: Persistence & Background (IN PROGRESS)

- [ ] SQLite database schema
- [ ] Device history tracking
- [ ] Background scanning daemon
- [ ] Scheduled scan intervals
- [ ] Online/offline detection

### Phase 3: Menu Bar App

- [ ] SwiftUI MenuBarExtra
- [ ] Device list view
- [ ] Settings panel
- [ ] Launch at login
- [ ] Notifications

### Phase 4: iOS Companion App

- [ ] Server discovery (Bonjour)
- [ ] Device list with scores
- [ ] Device detail view
- [ ] Push notifications
- [ ] Widget

---

## 8. Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Device discovery rate | > 95% | Devices found vs. router DHCP list |
| Smart classification accuracy | > 90% | Manual verification of top 20 devices |
| API uptime | > 99.9% | Monitoring over 30 days |
| Scan completion time | < 30s | Full discovery + quick port scan |
| User satisfaction | > 4/5 | Post-launch survey |

---

## 9. Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| False smart classification | Medium | Medium | User feedback/override system |
| Network disruption from scanning | High | Low | Passive-first approach, rate limiting |
| nmap not installed | Low | Medium | Socket-based fallback |
| Cross-VLAN limitations | Medium | High | Document requirements, multi-interface support |
| API security breach | High | Low | Token auth, localhost binding by default |

---

## 10. Future Considerations

### 10.1 Potential Enhancements

- Machine learning for device fingerprinting
- Traffic analysis for "phone home" detection
- Integration with Home Assistant
- UniFi controller API integration
- Prometheus metrics export

### 10.2 Out of Scope

- Network configuration changes
- Firewall rule management
- Device blocking/quarantine
- Cross-network discovery
- Cloud sync/backup

---

## Appendix A: Glossary

| Term | Definition |
|------|------------|
| ARP | Address Resolution Protocol - maps IP to MAC addresses |
| mDNS | Multicast DNS - local network service discovery (Bonjour) |
| SSDP | Simple Service Discovery Protocol - UPnP device discovery |
| OUI | Organizationally Unique Identifier - first 3 bytes of MAC |
| Smart Score | 0-100 metric indicating likelihood of "smart" behavior |

## Appendix B: References

- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [Hummingbird Documentation](https://hummingbird.codes)
- [mDNS RFC 6762](https://datatracker.ietf.org/doc/html/rfc6762)
- [UPnP Device Architecture](http://upnp.org/specs/arch/UPnP-arch-DeviceArchitecture-v1.1.pdf)
