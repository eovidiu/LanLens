# LanLens System Specification

**Version:** 2.0
**Date:** January 2, 2026
**Status:** Production Ready

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

This specification is organized into linked documents:

| Document | Purpose | Location |
|----------|---------|----------|
| **SPECIFICATION.md** (this document) | System overview, features, integrations | `/docs/SPECIFICATION.md` |
| **ARCHITECTURE.md** | Technical architecture, data flow, decisions | `/docs/ARCHITECTURE.md` |
| **UX_SPECIFICATION.md** | UI design, components, interaction patterns | `/docs/UX_SPECIFICATION.md` |
| **data-models.md** | Complete data structure reference | `/docs/data-models.md` |
| **inference-capabilities.md** | Device type inference documentation | `/docs/inference-capabilities.md` |
| **device-fingerprinting.md** | UPnP and Fingerbank integration | `/docs/device-fingerprinting.md` |

### Feature Specifications

| Document | Purpose | Location |
|----------|---------|----------|
| **fingerprint-enhancements.md** | DHCP, JA3/JA4, and offline cache features | `/docs/specs/fingerprint-enhancements.md` |
| **fingerprint-enhancements-checklist.md** | Implementation tracking | `/docs/specs/fingerprint-enhancements-checklist.md` |

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
| Multi-VLAN/Interface Support | IMPLEMENTED | `NetworkInterfaceManager.swift` |
| Active Ping Sweep | IMPLEMENTED | Available via CLI and API |

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
| Export Devices | IMPLEMENTED | `GET /api/devices/export?format=json\|csv` |
| Trigger Discovery | IMPLEMENTED | `POST /api/discover/passive` |
| Trigger Port Scan | IMPLEMENTED | `POST /api/scan/ports/:mac` |
| Token Authentication | IMPLEMENTED | `AuthMiddleware` |
| WebSocket Updates | IMPLEMENTED | `ws://host:port/api/ws` |

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
| Device History | IMPLEMENTED | First/last seen, presence records |
| User Labels Persistence | IMPLEMENTED | `DeviceStore.swift` |
| Enhanced Inference Persistence | IMPLEMENTED | Migration v2 |
| Behavior History | IMPLEMENTED | Migration v4, `presence_records` table |
| Export to JSON/CSV | IMPLEMENTED | `ExportService.swift` |

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

| Issue | Severity | Description | Status |
|-------|----------|-------------|--------|
| SQLite.swift unused | Low | Declared in Package.swift but GRDB is used | RESOLVED - Removed |
| Enhanced inference not persisted | Medium | DB schema missing enhanced fields | RESOLVED - Migration v2 |
| Behavior tracking volatile | Medium | Presence history lost on app restart | RESOLVED - Migration v4 |

### 7.2 Future Enhancements

| Feature | Priority | Specification | Notes |
|---------|----------|---------------|-------|
| Offline Fingerbank Cache | P1 | [specs/fingerprint-enhancements.md](specs/fingerprint-enhancements.md) | Bundled database for offline device identification |
| DHCP Fingerprint Capture | P2 | [specs/fingerprint-enhancements.md](specs/fingerprint-enhancements.md) | Passive DHCP Option 55 capture |
| TLS/JA3 Fingerprinting | P2 | [specs/fingerprint-enhancements.md](specs/fingerprint-enhancements.md) | TLS Client Hello fingerprinting |
| iOS companion app | P3 | Not specified | Server discovery via Bonjour, device list |
| SNMP discovery | P4 | Not specified | For network equipment with SNMP enabled |

### 7.3 Documentation Status

| Documentation | Status | Notes |
|---------------|--------|-------|
| System specification | Complete | This document |
| Architecture decisions | Complete | ARCHITECTURE.md |
| UX specification | Complete | UX_SPECIFICATION.md |
| Data models | Complete | data-models.md |
| Inference capabilities | Complete | inference-capabilities.md |
| Fingerprinting guide | Complete | device-fingerprinting.md |
| Fingerprint enhancements spec | Complete | specs/fingerprint-enhancements.md |
| Implementation checklist | Complete | specs/fingerprint-enhancements-checklist.md |

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

**Total Unit Tests: 159**

| Component | Test File | Test Count |
|-----------|-----------|------------|
| DeviceTypeInferenceEngine | `DeviceTypeInferenceEngineTests.swift` | 41 |
| MACAddressAnalyzer | `MACAddressAnalyzerTests.swift` | 43 |
| SecurityPostureAssessor | `SecurityPostureAssessorTests.swift` | 34 |
| ExportService | `ExportServiceTests.swift` | 23 |
| SmartScore | `SmartScoreTests.swift` | 11 |
| MACVendorLookup | `LanLensTests.swift` | 7 |

---

## 10. Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 2.0 | 2026-01-02 | Project Curator | Updated to reflect complete implementation: WebSocket, Export, Multi-VLAN, 159 tests, DB migrations v2-v4 |
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
