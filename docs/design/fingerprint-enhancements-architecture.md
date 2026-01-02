# Fingerprint Enhancements Architecture Design

**Status:** Proposed  
**Date:** January 2, 2026  
**Author:** Systems Architect  
**Stakeholder:** LanLens Development Team

---

## Executive Summary

This document defines the architecture for three fingerprinting enhancements to LanLens:

1. **Local DHCP Fingerprint Database** - Offline device identification using DHCP Option 55
2. **JA3/JA4 TLS Fingerprinting** - Device/application classification from TLS handshakes
3. **Offline Fingerbank Cache** - SQLite-based cache for airplane mode operation

All three enhancements follow Local-First architecture principles: the UI reads only from local storage, network operations sync in the background, and the app remains fully functional offline.

---

## Table of Contents

1. [Systems Analysis](#1-systems-analysis)
2. [Feature 1: Local DHCP Fingerprint Database](#2-feature-1-local-dhcp-fingerprint-database)
3. [Feature 2: JA3/JA4 TLS Fingerprinting](#3-feature-2-ja3ja4-tls-fingerprinting)
4. [Feature 3: Offline Fingerbank Cache](#4-feature-3-offline-fingerbank-cache)
5. [Integration Architecture](#5-integration-architecture)
6. [Implementation Plan](#6-implementation-plan)
7. [Technical Constraints](#7-technical-constraints)

---

## 1. Systems Analysis

### 1.1 Current Fingerprinting Ecosystem

```
                    CURRENT STATE
                    
┌─────────────────────────────────────────────────────────────┐
│                  Signal Sources (Discovery)                  │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌────────┐│
│  │   ARP   │ │  mDNS   │ │  SSDP   │ │  Ports  │ │ UPnP   ││
│  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └───┬────┘│
└───────┼──────────┼──────────┼──────────┼───────────┼──────┘
        │          │          │          │           │
        └──────────┴──────────┴──────────┴───────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              DeviceTypeInferenceEngine (Actor)              │
│                                                             │
│  Signal Sources & Weights:                                  │
│  • fingerprint: 0.90  (Fingerbank API - requires network)   │
│  • mdnsTXT:     0.85  (Local parsing)                       │
│  • upnp:        0.80  (Local XML fetch)                     │
│  • portBanner:  0.75  (Local probing)                       │
│  • mdns:        0.70  (Local discovery)                     │
│  • ssdp:        0.70  (Local discovery)                     │
│  • hostname:    0.60  (Local resolution)                    │
│  • macAnalysis: 0.60  (Local OUI lookup)                    │
│  • behavior:    0.60  (Local tracking)                      │
│  • port:        0.50  (Local scanning)                      │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 The Gap Analysis

| Capability | Current State | Gap |
|------------|---------------|-----|
| DHCP Fingerprinting | Fingerbank API only | No offline DHCP option 55 matching |
| TLS Fingerprinting | None | No JA3/JA4 hash generation or matching |
| Offline Operation | UPnP/mDNS local only | Fingerbank requires network |
| Signal Diversity | 10 sources | Missing DHCP and TLS as high-confidence signals |

### 1.3 Proposed Ecosystem Extension

```
                    PROPOSED STATE
                    
┌─────────────────────────────────────────────────────────────┐
│                  Signal Sources (Discovery)                  │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌────────┐│
│  │   ARP   │ │  mDNS   │ │  SSDP   │ │  Ports  │ │ UPnP   ││
│  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └───┬────┘│
│       │          │          │          │           │      │
│  ┌────┴────┐ ┌────┴────┐ ┌────┴────────┴───────────┴────┐ │
│  │  DHCP   │ │   TLS   │ │        (existing)            │ │
│  │Option 55│ │ JA3/JA4 │ │                              │ │
│  │ [NEW]   │ │  [NEW]  │ │                              │ │
│  └────┬────┘ └────┬────┘ └──────────────────────────────┘ │
└───────┼──────────┼──────────────────────────────────────────┘
        │          │
        ▼          ▼
┌─────────────────────────────────────────────────────────────┐
│              DeviceTypeInferenceEngine (Actor)              │
│                                                             │
│  NEW Signal Sources:                                        │
│  • dhcpFingerprint: 0.65  (Local DHCP Option 55 database)   │
│  • tlsFingerprint:  0.70  (Local JA3/JA4 database)          │
│                                                             │
│  Enhanced Fallback:                                         │
│  • fingerbankCache: 0.90  (SQLite cache, offline-ready)     │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Feature 1: Local DHCP Fingerprint Database

### 2.1 Overview

DHCP fingerprinting identifies devices based on the order and content of DHCP options requested during the DHCP handshake. Option 55 (Parameter Request List) is particularly valuable because different operating systems and device types request options in characteristic patterns.

### 2.2 Systems Thinking Analysis

**The Iceberg Model:**
- **Visible**: Device type classification in UI
- **Below Surface**: 
  - DHCP packet capture mechanics
  - Option 55 parsing and normalization
  - Fuzzy matching algorithms for partial fingerprints
  - Database versioning and updates

**Stocks and Flows:**
- **Stock**: Local JSON fingerprint database (~10,000 patterns)
- **Flow**: DHCP broadcasts on network (continuous, passive)
- **Constraint**: Cannot intercept DHCP without elevated privileges

### 2.3 Architecture

#### 2.3.1 Component Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                     DHCP Fingerprinting System                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────────────┐    ┌──────────────────────────────────┐   │
│  │  DHCPLeaseMonitor    │    │    DHCPFingerprintDatabase       │   │
│  │  (Actor)             │    │    (Class)                       │   │
│  │                      │    │                                  │   │
│  │  • Monitors leases   │    │  • Loads bundled JSON DB         │   │
│  │  • Parses lease file │───▶│  • Hash-based lookup             │   │
│  │  • Extracts Option55 │    │  • Fuzzy matching fallback       │   │
│  │  • Notifies changes  │    │  • Device type mapping           │   │
│  └──────────────────────┘    └──────────────────────────────────┘   │
│           │                              │                           │
│           │                              │                           │
│           ▼                              ▼                           │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                DHCPFingerprintMatcher (Actor)                │    │
│  │                                                              │    │
│  │  • Correlates MAC with Option 55                             │    │
│  │  • Generates inference signals                               │    │
│  │  • Caches per-device results                                 │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                              │                                       │
│                              ▼                                       │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                DeviceTypeInferenceEngine                     │    │
│  │                (existing - receives new signal source)       │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

#### 2.3.2 Data Flow

```
macOS DHCP Client Lease File                   Bundled Fingerprint DB
/var/db/dhcpclient/leases/*           LanLens.app/Resources/dhcp_fingerprints.json
              │                                         │
              │ FSEvents / periodic poll                │ Load at startup
              ▼                                         ▼
┌─────────────────────────┐            ┌─────────────────────────┐
│   DHCPLeaseMonitor      │            │ DHCPFingerprintDatabase │
│                         │            │                         │
│ Parse XML lease file:   │            │ Index by Option55 hash: │
│ • client_id (MAC)       │            │ "1,3,6,15,119,252" =>   │
│ • option_55             │            │   { device: "iPhone",   │
│ • lease_time            │            │     os: "iOS 17.x",     │
│                         │            │     confidence: 0.92 }  │
└───────────┬─────────────┘            └───────────┬─────────────┘
            │                                      │
            │    ┌────────────────────────────────┐│
            └───▶│   DHCPFingerprintMatcher       │◀┘
                 │                                │
                 │  Input: MAC, Option55 string   │
                 │  Output: Signal(              │
                 │    source: .dhcpFingerprint,  │
                 │    suggestedType: .phone,     │
                 │    confidence: 0.65 * 0.92    │
                 │  )                            │
                 └────────────────────────────────┘
                              │
                              ▼
                 ┌────────────────────────────────┐
                 │  DeviceTypeInferenceEngine     │
                 │  (aggregates with other        │
                 │   signals for final type)      │
                 └────────────────────────────────┘
```

#### 2.3.3 Database Schema (JSON)

```json
{
  "version": "1.0.0",
  "generated": "2026-01-02T00:00:00Z",
  "source": "PacketFence/Satori Community",
  "fingerprints": {
    "1,3,6,15,119,252": {
      "device_name": "Apple iPhone",
      "os": "iOS 17.x",
      "vendor": "Apple",
      "device_types": ["phone"],
      "confidence": 0.92,
      "variants": [
        "1,3,6,15,119,252,95,44,46"
      ]
    },
    "1,28,2,3,15,6,119,12,44,47,26,121,42": {
      "device_name": "Windows 11",
      "os": "Windows 11",
      "vendor": "Microsoft",
      "device_types": ["computer"],
      "confidence": 0.88,
      "variants": []
    }
  },
  "vendor_patterns": {
    "1,3,6,12,15,28,42": {
      "pattern_type": "prefix",
      "device_name": "Generic Linux DHCP Client",
      "device_types": ["computer", "nas", "hub"],
      "confidence": 0.50
    }
  }
}
```

#### 2.3.4 Integration Points

**New Files:**
```
Sources/LanLensCore/
├── Fingerprinting/
│   ├── DHCP/
│   │   ├── DHCPLeaseMonitor.swift       # Monitors lease file changes
│   │   ├── DHCPFingerprintDatabase.swift # Loads and indexes JSON DB
│   │   ├── DHCPFingerprintMatcher.swift  # Matches fingerprints to devices
│   │   └── DHCPOption55Parser.swift      # Parses Option 55 strings
│   └── ...
Resources/
└── dhcp_fingerprints.json               # Bundled fingerprint database
```

**Modified Files:**
```
Sources/LanLensCore/
├── Discovery/
│   └── DeviceTypeInferenceEngine.swift  # Add .dhcpFingerprint signal source
├── Models/
│   └── Device.swift                      # Add dhcpFingerprint: String? field
└── Persistence/
    └── Database.swift                    # Migration v5: add dhcp_fingerprint column
```

### 2.4 Architectural Decisions

| Decision | Recommended | Alternative | Avoid |
|----------|-------------|-------------|-------|
| **Data Source** | macOS DHCP lease files | BPF packet capture | Network Extension (overkill) |
| **Database Format** | Bundled JSON | SQLite | Remote API (defeats offline goal) |
| **Matching Algorithm** | Exact match + fuzzy fallback | ML-based classification | Simple string contains |
| **Update Strategy** | App update bundles new DB | Background download | Manual user update |

**Rationale:**
- macOS stores DHCP lease information in `/var/db/dhcpclient/leases/` as plist/XML files
- Bundled JSON avoids network dependency and simplifies distribution
- Fuzzy matching handles slight variations in Option 55 ordering

### 2.5 Confidence Weighting

```swift
// In DeviceTypeInferenceEngine.swift
private static let sourceWeights: [SignalSource: Double] = [
    // ... existing sources ...
    .dhcpFingerprint: 0.65   // NEW: Good reliability, but less specific than Fingerbank
]
```

**Weight Justification:**
- 0.65 balances between mDNS (0.70) and port-based (0.50) inference
- DHCP fingerprints identify OS/vendor well but may not distinguish device types
- Combined with MAC OUI, provides strong baseline identification

---

## 3. Feature 2: JA3/JA4 TLS Fingerprinting

### 3.1 Overview

JA3 (and its successor JA4) creates a fingerprint from the TLS Client Hello message, capturing:
- SSL/TLS version
- Cipher suites offered
- Extensions
- Elliptic curves
- Point formats

This fingerprint is remarkably stable per client application/device type.

### 3.2 Systems Thinking Analysis

**Tight vs Loose Coupling:**
- **Challenge**: TLS fingerprinting requires packet-level access
- **macOS Reality**: 
  - User-space apps cannot see raw packets without entitlements
  - Network Extension framework requires App Store review
  - BPF requires root privileges

**Feasibility Assessment:**
```
┌─────────────────────────────────────────────────────────────────────┐
│                  TLS Fingerprinting Feasibility                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Option 1: Network Extension (Packet Tunnel Provider)               │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  Pros:                           Cons:                       │    │
│  │  • App Store compliant           • Complex implementation    │    │
│  │  • User grants permission        • System Extension approval │    │
│  │  • Access to all traffic         • Requires System Ext host  │    │
│  └─────────────────────────────────────────────────────────────┘    │
│  Verdict: RECOMMENDED for future (requires significant effort)      │
│                                                                      │
│  Option 2: Passive TLS Proxy (man-in-the-middle)                    │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  Pros:                           Cons:                       │    │
│  │  • Sees Client Hello             • Requires proxy config     │    │
│  │  • No special entitlements       • User friction             │    │
│  │  • Works today                   • Only sees proxied traffic │    │
│  └─────────────────────────────────────────────────────────────┘    │
│  Verdict: ALTERNATIVE for power users                               │
│                                                                      │
│  Option 3: BPF/libpcap with privileged helper                       │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  Pros:                           Cons:                       │    │
│  │  • See all traffic               • NOT App Store compliant   │    │
│  │  • Proven technology             • Requires admin install    │    │
│  │  • Low-level access              • Security implications     │    │
│  └─────────────────────────────────────────────────────────────┘    │
│  Verdict: AVOID for distribution, OK for development/power users    │
│                                                                      │
│  Option 4: Active TLS Probing (connect and capture own hellos)      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  Pros:                           Cons:                       │    │
│  │  • No special permissions        • Only fingerprints servers │    │
│  │  • App Store compliant           • Cannot ID client devices  │    │
│  │  • Simple implementation         • Limited value for LanLens │    │
│  └─────────────────────────────────────────────────────────────┘    │
│  Verdict: LIMITED utility - fingerprints IoT servers, not clients   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 3.3 Recommended Architecture

Given constraints, implement a **two-tier approach**:

#### Tier 1: Active TLS Server Fingerprinting (App Store Compatible)

LanLens initiates TLS connections to discovered devices and captures the **Server Hello** to fingerprint IoT devices acting as servers (cameras, NAS, printers with HTTPS interfaces).

#### Tier 2: Network Extension (Future/Optional)

For users who want full client fingerprinting, offer a separate System Extension that captures Client Hello from other devices.

### 3.4 Tier 1 Architecture (Immediate Implementation)

```
┌─────────────────────────────────────────────────────────────────────┐
│              TLS Server Fingerprinting (Active Probing)              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Device discovered with port 443/8443 open                          │
│              │                                                       │
│              ▼                                                       │
│  ┌────────────────────────────────────────────────────────────┐     │
│  │              TLSFingerprintProber (Actor)                   │     │
│  │                                                             │     │
│  │  1. Establish TCP connection to target:443                  │     │
│  │  2. Send TLS Client Hello (standard)                        │     │
│  │  3. Capture Server Hello response                           │     │
│  │  4. Extract: version, cipher, extensions                    │     │
│  │  5. Generate JA3S hash (server fingerprint)                 │     │
│  └─────────────────────────────────────────────────────────────┘     │
│              │                                                       │
│              ▼                                                       │
│  ┌────────────────────────────────────────────────────────────┐     │
│  │            TLSFingerprintDatabase (Class)                   │     │
│  │                                                             │     │
│  │  Bundled JSON database of known JA3S hashes:                │     │
│  │  • IoT camera servers (Hikvision, Dahua, Axis)              │     │
│  │  • NAS web interfaces (Synology DSM, QNAP)                  │     │
│  │  • Printer admin pages (HP, Canon)                          │     │
│  │  • Router/AP interfaces (Ubiquiti, MikroTik)                │     │
│  └─────────────────────────────────────────────────────────────┘     │
│              │                                                       │
│              ▼                                                       │
│  ┌────────────────────────────────────────────────────────────┐     │
│  │  Signal generated:                                          │     │
│  │  Signal(source: .tlsFingerprint,                            │     │
│  │         suggestedType: .camera,                             │     │
│  │         confidence: 0.70)                                   │     │
│  └─────────────────────────────────────────────────────────────┘     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

#### 3.4.1 JA3S Hash Generation

```swift
/// JA3S (Server) fingerprint components:
/// SSLVersion,Cipher,Extensions
///
/// Example: 771,49195,65281-35
/// - 771 = TLS 1.2
/// - 49195 = TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
/// - 65281-35 = renegotiation_info, session_ticket

public struct JA3SFingerprint: Codable, Sendable, Hashable {
    public let sslVersion: UInt16
    public let cipher: UInt16
    public let extensions: [UInt16]
    
    public var hash: String {
        let components = "\(sslVersion),\(cipher),\(extensions.map(String.init).joined(separator: "-"))"
        return components.md5Hash
    }
}
```

#### 3.4.2 Database Schema (JSON)

```json
{
  "version": "1.0.0",
  "type": "ja3s_server_fingerprints",
  "fingerprints": {
    "e35d62c09e3e": {
      "description": "Hikvision Camera HTTPS Interface",
      "vendor": "Hikvision",
      "device_types": ["camera"],
      "confidence": 0.90
    },
    "f4e8a2b1d9c3": {
      "description": "Synology DSM 7.x",
      "vendor": "Synology",
      "device_types": ["nas"],
      "confidence": 0.85
    },
    "a1b2c3d4e5f6": {
      "description": "Ubiquiti UniFi Controller",
      "vendor": "Ubiquiti",
      "device_types": ["hub", "accessPoint"],
      "confidence": 0.85
    }
  }
}
```

### 3.5 Tier 2 Architecture (Future - Network Extension)

```
┌─────────────────────────────────────────────────────────────────────┐
│       TLS Client Fingerprinting (Network Extension - Future)         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌────────────────────────────────────────────────────────────┐     │
│  │           LanLensTLSExtension.systemextension              │     │
│  │           (Separate target, requires approval)              │     │
│  │                                                             │     │
│  │  ┌────────────────────────────────────────────────────┐    │     │
│  │  │  NEFilterDataProvider                               │    │     │
│  │  │  • Intercept TCP connections on port 443            │    │     │
│  │  │  • Extract Client Hello bytes                       │    │     │
│  │  │  • Generate JA3 hash                                │    │     │
│  │  │  • Pass through (never block)                       │    │     │
│  │  └────────────────────────────────────────────────────┘    │     │
│  │                         │                                   │     │
│  │                         │ XPC                               │     │
│  │                         ▼                                   │     │
│  │  ┌────────────────────────────────────────────────────┐    │     │
│  │  │  TLSFingerprintCollector                            │    │     │
│  │  │  • Correlate JA3 with source IP                     │    │     │
│  │  │  • Map IP to MAC via ARP table                      │    │     │
│  │  │  • Store fingerprint for device                     │    │     │
│  │  └────────────────────────────────────────────────────┘    │     │
│  └─────────────────────────────────────────────────────────────┘     │
│                                                                      │
│  User Flow:                                                          │
│  1. User installs System Extension from LanLens settings             │
│  2. macOS prompts for System Extension approval                      │
│  3. Extension starts passively monitoring TLS handshakes             │
│  4. LanLens receives JA3 hashes via XPC                              │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 3.6 New Files

```
Sources/LanLensCore/
├── Fingerprinting/
│   ├── TLS/
│   │   ├── TLSFingerprintProber.swift     # Active server probing
│   │   ├── TLSFingerprintDatabase.swift   # JA3S database lookup
│   │   ├── JA3SHashGenerator.swift        # Hash computation
│   │   └── TLSClientHelloParser.swift     # Parse TLS handshake bytes
│   └── ...
Resources/
└── tls_fingerprints.json                  # Bundled JA3S database

// Future (separate target):
LanLensTLSExtension/
├── TLSExtensionProvider.swift
├── Info.plist
└── LanLensTLSExtension.entitlements
```

### 3.7 Confidence Weighting

```swift
private static let sourceWeights: [SignalSource: Double] = [
    // ... existing sources ...
    .tlsFingerprint: 0.70   // NEW: High reliability for server-side detection
]
```

---

## 4. Feature 3: Offline Fingerbank Cache

### 4.1 Overview

Convert the existing file-based Fingerbank cache to SQLite for better query performance, atomic operations, and integration with the existing GRDB infrastructure.

### 4.2 Current vs Proposed

```
CURRENT: File-based cache
~/Library/Application Support/LanLens/FingerprintCache/
├── fingerbank/
│   ├── <hash1>.json
│   ├── <hash2>.json
│   └── ...
└── metadata.json

PROPOSED: SQLite cache (integrated with devices.sqlite)
~/Library/Application Support/LanLens/devices.sqlite
└── fingerbank_cache (new table)
```

### 4.3 Architecture

#### 4.3.1 Component Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                  Offline Fingerbank Cache System                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌────────────────────────────────────────────────────────────┐     │
│  │              FingerbankCacheRepository (Class)              │     │
│  │                                                             │     │
│  │  GRDB-based repository for fingerprint cache:               │     │
│  │  • get(mac:) -> DeviceFingerprint?                          │     │
│  │  • store(mac:, fingerprint:, ttl:)                          │     │
│  │  • invalidate(mac:)                                         │     │
│  │  • pruneExpired()                                           │     │
│  │  • preloadCommon() // Seed with common device fingerprints  │     │
│  └─────────────────────────────────────────────────────────────┘     │
│                              │                                       │
│                              │ uses                                  │
│                              ▼                                       │
│  ┌────────────────────────────────────────────────────────────┐     │
│  │              DatabaseManager (existing)                     │     │
│  │              + fingerbank_cache table                       │     │
│  └─────────────────────────────────────────────────────────────┘     │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────┐     │
│  │              FingerbankSyncScheduler (Actor)                │     │
│  │                                                             │     │
│  │  Background sync strategy:                                  │     │
│  │  • Periodic refresh of stale entries (TTL-based)            │     │
│  │  • Batch requests to respect rate limits                    │     │
│  │  • Thermal/power-aware scheduling                           │     │
│  │  • Circuit breaker for API failures                         │     │
│  └─────────────────────────────────────────────────────────────┘     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

#### 4.3.2 Database Schema

```sql
-- Migration v5: Fingerbank cache table
CREATE TABLE fingerbank_cache (
    mac TEXT PRIMARY KEY,
    fingerprint_json TEXT NOT NULL,     -- Serialized DeviceFingerprint
    dhcp_fingerprint TEXT,               -- Option 55 used for lookup
    user_agents TEXT,                    -- JSON array of user agents
    signal_hash TEXT NOT NULL,           -- Hash of lookup parameters
    fetched_at DATETIME NOT NULL,
    expires_at DATETIME NOT NULL,
    hit_count INTEGER NOT NULL DEFAULT 0,
    last_hit_at DATETIME
);

CREATE INDEX idx_fingerbank_cache_expires ON fingerbank_cache(expires_at);
CREATE INDEX idx_fingerbank_cache_signal_hash ON fingerbank_cache(signal_hash);

-- Cache statistics table
CREATE TABLE fingerbank_cache_stats (
    id INTEGER PRIMARY KEY CHECK (id = 1),  -- Singleton row
    total_entries INTEGER NOT NULL DEFAULT 0,
    total_hits INTEGER NOT NULL DEFAULT 0,
    total_misses INTEGER NOT NULL DEFAULT 0,
    last_prune_at DATETIME,
    last_sync_at DATETIME
);
```

#### 4.3.3 Sync Strategy

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Background Sync Strategy                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Trigger Conditions:                                                 │
│  1. App launch (if last sync > 24 hours ago)                         │
│  2. Network becomes available (after being offline)                  │
│  3. New device discovered without cache entry                        │
│  4. Cache entry approaching expiration (TTL - 1 day)                 │
│                                                                      │
│  Throttling:                                                         │
│  ┌────────────────────────────────────────────────────────────┐     │
│  │  Fingerbank Rate Limits:                                    │     │
│  │  • 300 requests/hour                                        │     │
│  │  • 2,000 requests/day                                       │     │
│  │  • 30,000 requests/month                                    │     │
│  │                                                             │     │
│  │  LanLens Batch Strategy:                                    │     │
│  │  • Max 10 requests per sync cycle                           │     │
│  │  • Min 5 second delay between requests                      │     │
│  │  • Prioritize: new devices > stale > preload                │     │
│  └────────────────────────────────────────────────────────────┘     │
│                                                                      │
│  Thermal/Power Awareness:                                            │
│  ┌────────────────────────────────────────────────────────────┐     │
│  │  ProcessInfo.ThermalState  │  Sync Behavior                 │     │
│  │  ─────────────────────────────────────────────────────────  │     │
│  │  .nominal                  │  Normal sync                   │     │
│  │  .fair                     │  Reduce batch size to 5        │     │
│  │  .serious                  │  Pause sync, retry later       │     │
│  │  .critical                 │  Suspend all network activity  │     │
│  └────────────────────────────────────────────────────────────┘     │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────┐     │
│  │  ProcessInfo.isLowPowerModeEnabled                          │     │
│  │  ─────────────────────────────────────────────────────────  │     │
│  │  true                      │  Only sync on user request     │     │
│  │  false                     │  Background sync enabled       │     │
│  └────────────────────────────────────────────────────────────┘     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

#### 4.3.4 Preload Strategy

Bundle a seed database of common device fingerprints for immediate offline use:

```json
// Resources/fingerbank_seed.json
{
  "version": "1.0.0",
  "description": "Common device fingerprints for offline bootstrap",
  "entries": [
    {
      "mac_prefix": "00:0E:58",
      "fingerprint": {
        "fingerbankDeviceName": "D-Link Access Point",
        "fingerbankParents": ["D-Link", "Access Point"],
        "fingerbankScore": 75
      }
    },
    {
      "mac_prefix": "B8:27:EB",
      "fingerprint": {
        "fingerbankDeviceName": "Raspberry Pi",
        "fingerbankParents": ["Raspberry Pi Foundation", "Single-board Computer"],
        "fingerbankScore": 90
      }
    }
  ]
}
```

### 4.4 New Files

```
Sources/LanLensCore/
├── Persistence/
│   └── FingerbankCacheRepository.swift    # GRDB-based cache repository
├── Services/
│   └── FingerbankSyncScheduler.swift      # Background sync orchestration
└── Fingerprinting/
    └── FingerbankCacheManager.swift       # MODIFIED: Delegate to repository

Resources/
└── fingerbank_seed.json                   # Common fingerprints for bootstrap
```

### 4.5 Migration Path

```swift
// Database.swift - Migration v5
migrator.registerMigration("v5_fingerbank_cache") { db in
    try db.create(table: "fingerbank_cache") { t in
        t.column("mac", .text).primaryKey()
        t.column("fingerprint_json", .text).notNull()
        t.column("dhcp_fingerprint", .text)
        t.column("user_agents", .text)
        t.column("signal_hash", .text).notNull()
        t.column("fetched_at", .datetime).notNull()
        t.column("expires_at", .datetime).notNull()
        t.column("hit_count", .integer).notNull().defaults(to: 0)
        t.column("last_hit_at", .datetime)
    }
    
    try db.create(index: "idx_fingerbank_cache_expires", 
                  on: "fingerbank_cache", 
                  columns: ["expires_at"])
    
    try db.create(table: "fingerbank_cache_stats") { t in
        t.column("id", .integer).primaryKey().check { $0 == 1 }
        t.column("total_entries", .integer).notNull().defaults(to: 0)
        t.column("total_hits", .integer).notNull().defaults(to: 0)
        t.column("total_misses", .integer).notNull().defaults(to: 0)
        t.column("last_prune_at", .datetime)
        t.column("last_sync_at", .datetime)
    }
    
    // Migrate existing file-based cache to SQLite
    // This happens asynchronously after migration completes
}
```

---

## 5. Integration Architecture

### 5.1 Unified Signal Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Complete Fingerprinting Pipeline                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    Device Discovered                         │    │
│  │                    (MAC + IP known)                          │    │
│  └───────────────────────────┬─────────────────────────────────┘    │
│                              │                                       │
│      ┌───────────────────────┼───────────────────────┐               │
│      │                       │                       │               │
│      ▼                       ▼                       ▼               │
│  ┌────────┐           ┌────────────┐          ┌────────────┐        │
│  │ Existing│           │ DHCP       │          │ TLS        │        │
│  │ Sources │           │ Fingerprint│          │ Fingerprint│        │
│  │         │           │ [NEW]      │          │ [NEW]      │        │
│  │ • mDNS  │           │            │          │            │        │
│  │ • SSDP  │           │ Read lease │          │ Probe 443  │        │
│  │ • UPnP  │           │ file for   │          │ and capture│        │
│  │ • Ports │           │ Option 55  │          │ Server     │        │
│  │ • MAC   │           │            │          │ Hello      │        │
│  └────┬────┘           └─────┬──────┘          └─────┬──────┘        │
│       │                      │                       │               │
│       │     ┌────────────────┼───────────────────────┘               │
│       │     │                │                                       │
│       ▼     ▼                ▼                                       │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                  FingerbankCacheRepository                    │   │
│  │                  (SQLite - Local First)                       │   │
│  │                                                               │   │
│  │  1. Check cache for MAC + signals hash                        │   │
│  │  2. If HIT: return cached fingerprint (confidence: 0.90)      │   │
│  │  3. If MISS: queue for background Fingerbank API sync         │   │
│  │  4. For immediate use: proceed with other signals             │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                              │                                       │
│                              ▼                                       │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │              DeviceTypeInferenceEngine (Actor)                │   │
│  │                                                               │   │
│  │  Signal Sources (ordered by weight):                          │   │
│  │  ─────────────────────────────────────────────────────────    │   │
│  │  • fingerbankCache:   0.90  (from SQLite cache)               │   │
│  │  • mdnsTXT:           0.85  (parsed TXT records)              │   │
│  │  • upnp:              0.80  (device description XML)          │   │
│  │  • portBanner:        0.75  (SSH/HTTP/RTSP banners)           │   │
│  │  • tlsFingerprint:    0.70  [NEW] (JA3S hash match)           │   │
│  │  • mdns:              0.70  (service type inference)          │   │
│  │  • ssdp:              0.70  (SSDP header inference)           │   │
│  │  • dhcpFingerprint:   0.65  [NEW] (Option 55 match)           │   │
│  │  • hostname:          0.60  (hostname pattern match)          │   │
│  │  • macAnalysis:       0.60  (OUI + randomization)             │   │
│  │  • behavior:          0.60  (presence patterns)               │   │
│  │  • port:              0.50  (open port inference)             │   │
│  │                                                               │   │
│  │  Output: DeviceType + confidence score                        │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                              │                                       │
│                              ▼                                       │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                      Device Record Updated                    │   │
│  │                                                               │   │
│  │  device.deviceType = .camera                                  │   │
│  │  device.smartScore = 85                                       │   │
│  │  device.fingerprint = cachedFingerprint                       │   │
│  │  device.dhcpFingerprint = "1,3,6,15,119,252"                  │   │
│  │  device.tlsFingerprint = "e35d62c09e3e"                       │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 5.2 Protocol Definitions

```swift
// Sources/LanLensCore/Protocols/DHCPFingerprintMatcherProtocol.swift
public protocol DHCPFingerprintMatcherProtocol: Sendable {
    func match(option55: String) async -> DHCPFingerprintMatch?
    func generateSignals(for option55: String) async -> [DeviceTypeInferenceEngine.Signal]
}

// Sources/LanLensCore/Protocols/TLSFingerprintProberProtocol.swift
public protocol TLSFingerprintProberProtocol: Sendable {
    func probeServer(host: String, port: Int) async throws -> JA3SFingerprint
    func generateSignals(from fingerprint: JA3SFingerprint) async -> [DeviceTypeInferenceEngine.Signal]
}

// Sources/LanLensCore/Protocols/FingerbankCacheRepositoryProtocol.swift
public protocol FingerbankCacheRepositoryProtocol: Sendable {
    func get(mac: String, signalHash: String) async -> DeviceFingerprint?
    func store(mac: String, fingerprint: DeviceFingerprint, signalHash: String, ttl: TimeInterval) async
    func invalidate(mac: String) async
    func pruneExpired() async
}
```

### 5.3 Extended Device Model

```swift
// Device.swift additions
public struct Device: Identifiable, Codable, Sendable, Hashable {
    // ... existing fields ...
    
    // NEW: DHCP fingerprinting data
    public var dhcpFingerprint: String?        // Option 55 string
    public var dhcpVendorClass: String?        // Option 60 vendor class
    public var dhcpHostname: String?           // Option 12 hostname
    
    // NEW: TLS fingerprinting data
    public var tlsServerFingerprint: String?   // JA3S hash from probing
    public var tlsClientFingerprint: String?   // JA3 hash (requires extension)
}
```

### 5.4 Database Migration

```swift
// Migration v5: DHCP and TLS fingerprinting + Fingerbank cache
migrator.registerMigration("v5_enhanced_fingerprinting") { db in
    // Device table additions
    try db.alter(table: "devices") { t in
        t.add(column: "dhcpFingerprint", .text)
        t.add(column: "dhcpVendorClass", .text)
        t.add(column: "dhcpHostname", .text)
        t.add(column: "tlsServerFingerprint", .text)
        t.add(column: "tlsClientFingerprint", .text)
    }
    
    // Fingerbank cache table
    try db.create(table: "fingerbank_cache") { t in
        t.column("mac", .text).primaryKey()
        t.column("fingerprint_json", .text).notNull()
        t.column("dhcp_fingerprint", .text)
        t.column("user_agents", .text)
        t.column("signal_hash", .text).notNull()
        t.column("fetched_at", .datetime).notNull()
        t.column("expires_at", .datetime).notNull()
        t.column("hit_count", .integer).notNull().defaults(to: 0)
        t.column("last_hit_at", .datetime)
    }
    
    try db.create(index: "idx_fingerbank_cache_expires", 
                  on: "fingerbank_cache", 
                  columns: ["expires_at"])
    
    // Cache statistics
    try db.create(table: "fingerbank_cache_stats") { t in
        t.column("id", .integer).primaryKey().check { $0 == 1 }
        t.column("total_entries", .integer).notNull().defaults(to: 0)
        t.column("total_hits", .integer).notNull().defaults(to: 0)
        t.column("total_misses", .integer).notNull().defaults(to: 0)
        t.column("last_prune_at", .datetime)
        t.column("last_sync_at", .datetime)
    }
}
```

---

## 6. Implementation Plan

### 6.1 File Structure (Complete)

```
Sources/LanLensCore/
├── Fingerprinting/
│   ├── DHCP/
│   │   ├── DHCPLeaseMonitor.swift           # NEW: FSEvents monitoring
│   │   ├── DHCPFingerprintDatabase.swift    # NEW: JSON database loader
│   │   ├── DHCPFingerprintMatcher.swift     # NEW: Matching logic
│   │   └── DHCPOption55Parser.swift         # NEW: Option 55 parsing
│   ├── TLS/
│   │   ├── TLSFingerprintProber.swift       # NEW: Active TLS probing
│   │   ├── TLSFingerprintDatabase.swift     # NEW: JA3S database
│   │   ├── JA3SHashGenerator.swift          # NEW: Hash computation
│   │   └── TLSClientHelloParser.swift       # NEW: TLS message parsing
│   ├── DeviceFingerprint.swift              # EXISTING
│   ├── DeviceFingerprintManager.swift       # MODIFIED: Orchestrate all sources
│   ├── FingerbankService.swift              # EXISTING
│   ├── FingerprintCacheManager.swift        # DEPRECATED: Migrate to repository
│   └── UPnPDescriptionFetcher.swift         # EXISTING
├── Persistence/
│   ├── Database.swift                        # MODIFIED: Add migration v5
│   ├── DeviceRepository.swift                # MODIFIED: New fields
│   ├── FingerbankCacheRepository.swift       # NEW: SQLite-based cache
│   └── PresenceRepository.swift              # EXISTING
├── Services/
│   ├── CircuitBreaker.swift                  # EXISTING
│   ├── FingerbankSyncScheduler.swift         # NEW: Background sync
│   └── SecureStorage.swift                   # EXISTING
├── Discovery/
│   └── DeviceTypeInferenceEngine.swift       # MODIFIED: New signal sources
├── Models/
│   ├── Device.swift                          # MODIFIED: New fingerprint fields
│   └── EnhancedInferenceModels.swift         # EXISTING
├── Protocols/
│   ├── DHCPFingerprintMatcherProtocol.swift  # NEW
│   ├── TLSFingerprintProberProtocol.swift    # NEW
│   ├── FingerbankCacheRepositoryProtocol.swift # NEW
│   └── ... (existing protocols)
└── DI/
    └── DIContainer.swift                      # MODIFIED: Register new services

Resources/
├── dhcp_fingerprints.json                    # NEW: DHCP fingerprint database
├── tls_fingerprints.json                     # NEW: JA3S fingerprint database
└── fingerbank_seed.json                      # NEW: Common fingerprints seed
```

### 6.2 Phased Rollout

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Implementation Phases                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  PHASE 1: Foundation (Week 1-2)                                      │
│  ────────────────────────────────                                    │
│  Priority: Critical path items                                       │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  1. Database migration v5 (all new columns and tables)       │    │
│  │  2. Protocol definitions for new services                    │    │
│  │  3. DI container updates                                     │    │
│  │  4. Device model extensions                                  │    │
│  │  5. Unit tests for data layer                                │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  PHASE 2: Offline Fingerbank Cache (Week 2-3)                        │
│  ────────────────────────────────────                                │
│  Priority: Most immediate user value                                 │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  1. FingerbankCacheRepository implementation                 │    │
│  │  2. Migration from file-based to SQLite cache                │    │
│  │  3. FingerbankSyncScheduler implementation                   │    │
│  │  4. Seed database creation and bundling                      │    │
│  │  5. Integration with DeviceFingerprintManager                │    │
│  │  6. Unit and integration tests                               │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  PHASE 3: DHCP Fingerprinting (Week 3-4)                             │
│  ────────────────────────────────────                                │
│  Priority: New signal source                                         │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  1. DHCPLeaseMonitor implementation                          │    │
│  │  2. DHCP fingerprint database creation (from Satori/PF)      │    │
│  │  3. DHCPFingerprintMatcher implementation                    │    │
│  │  4. Integration with DeviceTypeInferenceEngine               │    │
│  │  5. Unit tests for DHCP parsing and matching                 │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  PHASE 4: TLS Fingerprinting (Week 4-5)                              │
│  ────────────────────────────────────                                │
│  Priority: Enhanced server identification                            │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  1. TLSFingerprintProber implementation                      │    │
│  │  2. JA3S database creation (IoT servers)                     │    │
│  │  3. Integration with port scanning workflow                  │    │
│  │  4. Integration with DeviceTypeInferenceEngine               │    │
│  │  5. Unit tests for TLS parsing                               │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  PHASE 5: Polish & Documentation (Week 5-6)                          │
│  ────────────────────────────────────                                │
│  Priority: Production readiness                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  1. Settings UI for fingerprint cache management             │    │
│  │  2. Observability and logging                                │    │
│  │  3. Performance profiling and optimization                   │    │
│  │  4. Documentation updates                                    │    │
│  │  5. End-to-end testing                                       │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  PHASE 6: Network Extension (Future)                                 │
│  ────────────────────────────────────                                │
│  Priority: Optional enhancement                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  1. System Extension target setup                            │    │
│  │  2. NEFilterDataProvider implementation                      │    │
│  │  3. XPC communication with main app                          │    │
│  │  4. App Store review process                                 │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 6.3 Dependencies

| Feature | External Dependencies | Internal Dependencies |
|---------|----------------------|----------------------|
| DHCP Fingerprinting | None (bundled JSON) | DatabaseManager, DeviceTypeInferenceEngine |
| TLS Fingerprinting | Network (optional) | PortScanner, DeviceTypeInferenceEngine |
| Fingerbank Cache | GRDB (existing) | FingerbankService, DatabaseManager |

### 6.4 Testing Strategy

```swift
// Test files to create:
Tests/LanLensCoreTests/
├── DHCPFingerprintMatcherTests.swift
├── DHCPOption55ParserTests.swift
├── TLSFingerprintProberTests.swift
├── JA3SHashGeneratorTests.swift
├── FingerbankCacheRepositoryTests.swift
├── FingerbankSyncSchedulerTests.swift
└── DeviceTypeInferenceEngineEnhancedTests.swift
```

---

## 7. Technical Constraints

### 7.1 macOS Permissions Analysis

| Capability | Required Permission | App Store Compatible | Notes |
|------------|---------------------|---------------------|-------|
| Read DHCP lease files | None | Yes | Files in /var/db/dhcpclient/leases/ are readable |
| TLS active probing | Network (outbound) | Yes | Standard URLSession/NWConnection |
| TLS passive capture | Network Extension | Yes (with review) | Requires System Extension approval |
| BPF packet capture | Root/admin | No | Not App Store compatible |
| SQLite persistence | None | Yes | App sandbox writeable |

### 7.2 DHCP Lease File Access

```bash
# macOS DHCP lease file location
/var/db/dhcpclient/leases/

# File format: XML plist
# Example content includes:
# - client_identifier (MAC)
# - lease_time
# - option_55 (Parameter Request List)
# - option_60 (Vendor Class Identifier)

# Permission check:
$ ls -la /var/db/dhcpclient/leases/
drwxr-xr-x  3 root  wheel  96 Jan  2 10:00 .
# Files are world-readable, no special permissions needed
```

**Caveat**: The lease file only contains information about the Mac running LanLens, not other devices on the network. To capture Option 55 from other devices, we would need:

1. **BPF/libpcap** (requires root) - Not App Store compatible
2. **Network Extension** - Requires System Extension approval
3. **Router integration** - Query router's DHCP server (depends on router model)

**Revised Approach for DHCP:**
- Use bundled fingerprint database
- Match against mDNS/SSDP user agent strings that embed OS info
- Consider optional router integration for advanced users

### 7.3 TLS Fingerprinting Constraints

| Approach | What It Captures | Limitations |
|----------|------------------|-------------|
| Active Probing | Server fingerprint (JA3S) | Only devices with HTTPS servers |
| Network Extension | Client fingerprints (JA3) | Requires System Extension install |
| Neither | - | Cannot fingerprint clients without extension |

### 7.4 App Store Compliance

```
┌─────────────────────────────────────────────────────────────────────┐
│                    App Store Compliance Matrix                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  COMPLIANT:                                                          │
│  ✓ Bundled JSON fingerprint databases                                │
│  ✓ SQLite persistence in app sandbox                                 │
│  ✓ Active TLS probing to discovered devices                          │
│  ✓ Reading DHCP lease file (own leases only)                         │
│  ✓ Background sync with rate limiting                                │
│  ✓ System Extension (with Apple review)                              │
│                                                                      │
│  NOT COMPLIANT:                                                      │
│  ✗ BPF/libpcap packet capture                                        │
│  ✗ Raw socket access                                                 │
│  ✗ Kernel extension                                                  │
│  ✗ Privileged helper tools (for network capture)                     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 7.5 Observability Requirements

```swift
// Logging categories to add
extension Log.Category {
    static let dhcpFingerprint = Log.Category("dhcpFingerprint")
    static let tlsFingerprint = Log.Category("tlsFingerprint")
    static let fingerbankCache = Log.Category("fingerbankCache")
}

// Metrics to track
struct FingerprintMetrics {
    var dhcpMatchRate: Double          // % of devices with DHCP fingerprint
    var tlsProbeSuccessRate: Double    // % of HTTPS devices fingerprinted
    var cacheHitRate: Double           // Fingerbank cache effectiveness
    var offlineResolutionRate: Double  // % resolved without network
    var averageInferenceTime: Duration // Time to classify device
}
```

---

## 8. Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| DHCP Option 55 not available for remote devices | High | Medium | Fall back to mDNS/SSDP signals, document limitation |
| TLS probing blocked by firewalls | Medium | Low | Graceful degradation, mark as "unknown TLS" |
| Fingerbank API rate limits | Medium | Medium | Aggressive caching, background sync, circuit breaker |
| Database size growth | Low | Low | TTL-based pruning, maximum entry limits |
| System Extension rejection | Medium | High | Design without it first, add as optional enhancement |

---

## 9. Success Criteria

| Metric | Current | Target |
|--------|---------|--------|
| Offline device classification rate | ~60% | >85% |
| Average classification confidence | 0.65 | 0.75 |
| Time to first classification | 2-5s | <1s (cached) |
| Fingerbank API calls (devices/day) | 50 | <20 (better caching) |
| Supported fingerprint sources | 10 | 12 |

---

## 10. Appendix

### A. DHCP Option 55 Reference

| Option | Name | Common Use |
|--------|------|------------|
| 1 | Subnet Mask | Universal |
| 3 | Router | Universal |
| 6 | DNS Server | Universal |
| 12 | Hostname | Most clients |
| 15 | Domain Name | Enterprise |
| 28 | Broadcast Address | Less common |
| 42 | NTP Server | IoT devices |
| 119 | Domain Search | Modern clients |
| 252 | WPAD | Windows, some browsers |

### B. JA3S Hash Examples

| Hash | Server Type |
|------|-------------|
| `e35d62c09e3e` | Hikvision Camera |
| `f4e8a2b1d9c3` | Synology DSM |
| `a1b2c3d4e5f6` | Ubiquiti UniFi |
| `b2c3d4e5f6a1` | HP Printer |
| `c3d4e5f6a1b2` | Ring Doorbell |

### C. References

- [Fingerbank Documentation](https://fingerbank.org/documentation)
- [JA3/JA3S GitHub](https://github.com/salesforce/ja3)
- [PacketFence Fingerprints](https://github.com/inverse-inc/packetfence/tree/devel/conf/fingerbank)
- [Satori DHCP Fingerprints](https://github.com/xnih/sern/tree/master/fingerprint)
- [Apple Network Extension](https://developer.apple.com/documentation/networkextension)
- [GRDB.swift Documentation](https://github.com/groue/GRDB.swift)

---

**Document Version:** 1.0  
**Last Updated:** January 2, 2026  
**Review Status:** Ready for technical review
