# LanLens System Specification

**Version:** 1.0
**Date:** January 2, 2026
**Status:** Active Development

---

## 1. System Overview

### 1.1 Purpose

LanLens is a native macOS menu bar application that autonomously discovers, identifies, and analyzes devices on local networks. It provides deep visibility into network device behavior, security posture, and smart device capabilities.

**Core Value Proposition:**
- **Visibility**: Discover all devices on your network with vendor identification
- **Intelligence**: Automatically classify devices by "smart score" based on detected behaviors
- **Security**: Assess device security posture with actionable recommendations
- **Privacy-First**: Runs locally on your Mac, no cloud dependency (Fingerbank opt-in)

### 1.2 Target Users

| User Type | Description | Primary Concerns |
|-----------|-------------|------------------|
| Tech-savvy Homeowner | Has smart home devices, UniFi infrastructure, Mac Mini server | Network visibility, security, device identification |
| Network Administrator | Manages home/small office network | Device inventory, security monitoring |
| Privacy-Conscious User | Wants to know what devices are on network | Transparency, local-only operation |

### 1.3 Platform Requirements

| Requirement | Specification |
|-------------|---------------|
| Operating System | macOS 14.0 (Sonoma) or later |
| Architecture | Apple Silicon (M1/M2/M3/M4) and Intel |
| Runtime | Swift 5.9+ |
| Network Access | Local network (no internet required for core features) |
| Permissions | Network access, local network discovery |

---

## 2. Document Structure

This specification is organized into three linked documents:

| Document | Purpose | Location |
|----------|---------|----------|
| **SPECIFICATION.md** (this document) | System overview, integration points, gaps | `/docs/SPECIFICATION.md` |
| **ARCHITECTURE.md** | Technical architecture, data flow, decisions | `/docs/ARCHITECTURE.md` |
| **UX_SPECIFICATION.md** | UI design, components, interaction patterns | `/docs/UX_SPECIFICATION.md` |

---

## 3. Feature Inventory

### 3.1 Discovery Features

| Feature | Status | Implementation |
|---------|--------|----------------|
| ARP Table Reading | IMPLEMENTED | `ARPScanner.swift` |
| MAC Vendor Lookup | IMPLEMENTED | `MACVendorLookup.swift` |
| mDNS/Bonjour Discovery | IMPLEMENTED | `MDNSListener.swift` |
| SSDP/UPnP Discovery | IMPLEMENTED | `SSDPListener.swift` |
| DNS-SD Discovery | IMPLEMENTED | `DNSSDScanner.swift` |
| Port Scanning (Socket) | IMPLEMENTED | `PortScanner.swift` |
| Port Scanning (nmap) | IMPLEMENTED | `PortScanner.swift` |
| Multi-Subnet Support | NOT IMPLEMENTED | - |
| Active Ping Sweep | PARTIAL | Available via CLI |

### 3.2 Classification Features

| Feature | Status | Implementation |
|---------|--------|----------------|
| Smart Score Calculation | IMPLEMENTED | `DiscoveryManager.swift` |
| mDNS Signal Detection | IMPLEMENTED | `MDNSListener.swift` |
| SSDP Signal Detection | IMPLEMENTED | `SSDPListener.swift` |
| Port-Based Classification | IMPLEMENTED | `PortScanner.swift` |
| Device Type Inference | IMPLEMENTED | `DeviceTypeInferenceEngine.swift` |
| User-Defined Labels | IMPLEMENTED | `DeviceStore.swift` |

### 3.3 Fingerprinting Features

| Feature | Status | Implementation |
|---------|--------|----------------|
| UPnP Device Description (Level 1) | IMPLEMENTED | `UPnPDescriptionFetcher.swift` |
| Fingerbank API (Level 2) | IMPLEMENTED | `FingerbankService.swift` |
| Fingerprint Caching | IMPLEMENTED | `FingerprintCacheManager.swift` |
| Circuit Breaker for API | IMPLEMENTED | `CircuitBreaker.swift` |

### 3.4 Analysis Features

| Feature | Status | Implementation |
|---------|--------|----------------|
| Security Posture Assessment | IMPLEMENTED | `SecurityPostureAssessor.swift` |
| mDNS TXT Record Analysis | IMPLEMENTED | `MDNSTXTRecordAnalyzer.swift` |
| Port Banner Grabbing | IMPLEMENTED | `PortBannerGrabber.swift` |
| MAC Address Analysis | IMPLEMENTED | `MACAddressAnalyzer.swift` |
| Behavior Tracking | IMPLEMENTED | `DeviceBehaviorTracker.swift` (in-memory only) |

### 3.5 API Features

| Feature | Status | Implementation |
|---------|--------|----------------|
| List All Devices | IMPLEMENTED | `GET /api/devices` |
| List Smart Devices | IMPLEMENTED | `GET /api/devices/smart` |
| Get Device by MAC | IMPLEMENTED | `GET /api/devices/:mac` |
| Trigger Discovery | IMPLEMENTED | `POST /api/discover/passive` |
| Trigger Port Scan | IMPLEMENTED | `POST /api/scan/ports/:mac` |
| Token Authentication | IMPLEMENTED | `AuthMiddleware` |
| WebSocket Updates | NOT IMPLEMENTED | - |

### 3.6 UI Features

| Feature | Status | Implementation |
|---------|--------|----------------|
| Menu Bar Presence | IMPLEMENTED | `LanLensMenuBarApp.swift` |
| Device List Dropdown | IMPLEMENTED | `MenuBarView.swift` |
| Smart/Other Sections | IMPLEMENTED | `DeviceListView.swift` |
| Device Detail View | IMPLEMENTED | `DeviceDetailView.swift` |
| Settings Panel | IMPLEMENTED | `SettingsView.swift` |
| Launch at Login | IMPLEMENTED | `LaunchAtLoginService.swift` |

### 3.7 Persistence Features

| Feature | Status | Implementation |
|---------|--------|----------------|
| SQLite Database | IMPLEMENTED | `DatabaseManager.swift` (GRDB) |
| Device History | PARTIAL | First/last seen tracked |
| User Labels Persistence | IMPLEMENTED | `DeviceStore.swift` |
| Export to JSON/CSV | NOT IMPLEMENTED | - |

---

## 4. External Integrations

### 4.1 Fingerbank API

| Aspect | Specification |
|--------|---------------|
| Endpoint | `https://api.fingerbank.org/api/v2/combinations/interrogate` |
| Authentication | API Key (Bearer token) |
| Rate Limits | 300/hour, 2,000/day, 30,000/month (free tier) |
| Data Sent | MAC address, DHCP fingerprint (if captured), user agents |
| Privacy Impact | MAC addresses transmitted to external server |
| Opt-In | Yes - requires explicit API key configuration |

### 4.2 System Dependencies

| Dependency | Type | Required | Purpose |
|------------|------|----------|---------|
| `/usr/sbin/arp` | System binary | Yes | ARP table reading |
| `/usr/bin/dns-sd` | System binary | Yes | mDNS service discovery |
| `/opt/homebrew/bin/nmap` | External tool | No | Enhanced port scanning |
| `/opt/homebrew/bin/arp-scan` | External tool | No | Active ARP scanning |

### 4.3 Swift Package Dependencies

| Package | Version | Purpose | Usage |
|---------|---------|---------|-------|
| GRDB.swift | 7.0.0+ | SQLite persistence | Device storage |
| Hummingbird | 2.0.0+ | REST API server | API endpoints |
| SQLite.swift | 0.15.0+ | Declared but unused | **TECHNICAL DEBT** |

---

## 5. Security Considerations

### 5.1 Authentication

| Component | Mechanism |
|-----------|-----------|
| REST API | Optional Bearer token authentication |
| Fingerbank | API key stored in Keychain via `SecureStorage.swift` |

### 5.2 Data Protection

| Data Type | Protection | Location |
|-----------|------------|----------|
| Device inventory | SQLite file | `~/Library/Application Support/LanLens/devices.sqlite` |
| Fingerprint cache | JSON files | `~/Library/Application Support/LanLens/FingerprintCache/` |
| Behavior history | In-memory only | Not persisted |
| API key | Keychain | Secure storage |

### 5.3 Network Security

| Aspect | Implementation |
|--------|----------------|
| API binding | Default: `127.0.0.1` (localhost only) |
| TLS for IoT probing | Certificate validation bypassed (necessary for self-signed certs) |
| Port scanning | Rate-limited, no network disruption |

### 5.4 Security Assessment

The `SecurityPostureAssessor` evaluates discovered devices for:
- Risky open ports (Telnet, RDP, VNC, database ports)
- Default/factory hostname patterns
- Outdated software versions (from banners)
- Missing authentication on admin interfaces

---

## 6. Configuration Options

### 6.1 User Preferences (persisted via @AppStorage)

| Setting | Default | Description |
|---------|---------|-------------|
| `enableAPIServer` | false | Run REST API server |
| `apiPort` | 8080 | API server port |
| `apiHost` | "127.0.0.1" | API server bind address |
| `apiAuthEnabled` | false | Require authentication |
| `apiAuthToken` | (empty) | Bearer token for API |
| `enableFingerbankLookup` | false | Use Fingerbank API |
| `launchAtLogin` | false | Start with system |
| `autoScanOnLaunch` | true | Run scan when app starts |
| `scanIntervalMinutes` | 5 | Background scan interval |
| `enableNotifications` | true | Show system notifications |
| `notifyOnNewDevice` | true | Alert for new devices |
| `notifyOnDeviceOffline` | false | Alert when device goes offline |

### 6.2 Thermal Management

| State | Behavior |
|-------|----------|
| Nominal | Normal scanning |
| Fair | Reduced scan frequency |
| Serious | Minimal scanning |
| Critical | Scanning suspended |

---

## 7. Identified Gaps

### 7.1 Technical Debt

| Issue | Severity | Description | Recommendation |
|-------|----------|-------------|----------------|
| SQLite.swift unused | Low | Declared in Package.swift but GRDB is used | Remove from dependencies |
| Enhanced inference not persisted | Medium | `mdnsTXTRecords`, `portBanners`, `macAnalysis`, `securityPosture`, `behaviorProfile` not in DB schema | Add migration v2 |
| Dual cache stores | Medium | `DeviceStore` cache and `DiscoveryManager.devices` registry are separate | Unify into single source of truth |
| Behavior tracking volatile | Medium | Presence history lost on app restart | Persist to database |

### 7.2 Missing Features

| Feature | Status | Priority | Notes |
|---------|--------|----------|-------|
| Multi-VLAN support | Missing | P1 | Requires network interface enumeration |
| WebSocket real-time updates | Missing | P2 | For iOS companion app |
| Export to JSON/CSV | Missing | P2 | Device inventory export |
| iOS companion app | Not started | Phase 4 | Server discovery, device list |

### 7.3 Documentation Gaps

| Missing Documentation | Priority | Notes |
|-----------------------|----------|-------|
| API endpoint docs for fingerprint stats | Medium | Mentioned but not implemented |
| Error handling documentation | Medium | No comprehensive error catalog |
| Deployment guide | Low | Installation/distribution not documented |
| Testing strategy | High | No test coverage targets documented |

---

## 8. Non-Functional Requirements

### 8.1 Performance Targets

| Metric | Target | Status |
|--------|--------|--------|
| ARP table read latency | < 500ms | ASSUMED MET |
| API response time | < 100ms | ASSUMED MET |
| Memory footprint | < 50MB | NOT MEASURED |
| CPU usage (idle) | < 1% | NOT MEASURED |
| Startup time | < 2s | NOT MEASURED |

### 8.2 Observability

| Capability | Implementation |
|------------|----------------|
| Logging | `Logger.swift` with categories |
| Metrics | None implemented |
| Health endpoint | `GET /health` with uptime, device count |

---

## 9. Traceability Matrix

### 9.1 Critical Paths

| User Goal | Implementation | Test Coverage |
|-----------|----------------|---------------|
| See all network devices | ARPScanner + MACVendorLookup | Vendor lookup tested |
| Identify smart devices | smartScore calculation | No dedicated tests |
| Get device fingerprint | UPnP + Fingerbank | No dedicated tests |
| Assess security | Port + banner analysis | No dedicated tests |

### 9.2 Test Coverage

| Component | Unit Tests | Integration Tests |
|-----------|------------|-------------------|
| MACVendorLookup | Yes (2 tests) | No |
| ARPScanner | No | No |
| DiscoveryManager | No | No |
| DeviceStore | No | No |
| API endpoints | No | No |

---

## 10. Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-02 | Project Curator | Initial consolidated specification |

---

## Appendix A: File Location Reference

### Core Package (LanLensCore)

| Path | Purpose |
|------|---------|
| `Sources/LanLensCore/Discovery/` | Network discovery modules |
| `Sources/LanLensCore/Fingerprinting/` | Device identification |
| `Sources/LanLensCore/Analysis/` | Security and behavior analysis |
| `Sources/LanLensCore/Persistence/` | Database and storage |
| `Sources/LanLensCore/Models/` | Data models |
| `Sources/LanLensCore/API/` | REST API server |
| `Sources/LanLensCore/DI/` | Dependency injection |
| `Sources/LanLensCore/Protocols/` | Service protocols |

### App Package (LanLensApp)

| Path | Purpose |
|------|---------|
| `LanLensApp/Views/` | SwiftUI views |
| `LanLensApp/Views/Components/` | Reusable UI components |
| `LanLensApp/State/` | Observable state management |
| `LanLensApp/Services/` | App-level services |
