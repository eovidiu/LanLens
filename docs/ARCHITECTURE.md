# LanLens Architecture Decision Record

**ADR Status:** Accepted
**Date:** January 2, 2026
**Authors:** Architecture Sub-Agent, Project Curator

---

## 1. Context

LanLens is a native macOS application for network device discovery and analysis. This document captures the architectural decisions, patterns, and technical implementation details.

---

## 2. Modular Package Structure

### 2.1 Decision

Separate the application into two distinct packages:
- **LanLensCore**: Swift Package library containing all business logic
- **LanLensApp**: Xcode project containing the macOS menu bar application

### 2.2 Rationale

- **Testability**: Core logic can be tested independently of UI
- **Reusability**: Core package can be used by future iOS app or CLI
- **Separation of Concerns**: Clear boundary between platform-specific and platform-agnostic code
- **Build Optimization**: Core package can be cached across builds

### 2.3 Structure

```
LanLens/
├── Package.swift                    # LanLensCore package definition
├── Sources/LanLensCore/             # Core library
│   ├── Discovery/                   # Network discovery
│   │   ├── ARPScanner.swift
│   │   ├── MDNSListener.swift
│   │   ├── DNSSDScanner.swift
│   │   ├── SSDPListener.swift
│   │   ├── PortScanner.swift
│   │   ├── DiscoveryManager.swift
│   │   └── DeviceTypeInferenceEngine.swift
│   ├── Fingerprinting/
│   │   ├── DeviceFingerprintManager.swift
│   │   ├── FingerbankService.swift
│   │   ├── FingerprintCacheManager.swift
│   │   └── UPnPDescriptionFetcher.swift
│   ├── Analysis/
│   │   ├── SecurityPostureAssessor.swift
│   │   ├── MDNSTXTRecordAnalyzer.swift
│   │   ├── PortBannerGrabber.swift
│   │   └── MACAddressAnalyzer.swift
│   ├── Persistence/
│   │   ├── Database.swift
│   │   ├── DeviceRepository.swift
│   │   └── DeviceStore.swift
│   ├── Models/
│   │   ├── Device.swift
│   │   └── EnhancedInferenceModels.swift
│   ├── API/
│   │   └── APIServer.swift
│   ├── DI/
│   │   └── DIContainer.swift
│   ├── Protocols/
│   ├── Services/
│   │   ├── CircuitBreaker.swift
│   │   └── SecureStorage.swift
│   ├── Utilities/
│   │   └── MACVendorLookup.swift
│   └── Logging/
│       └── Logger.swift
├── Tests/LanLensCoreTests/
└── LanLensApp/
    └── LanLensApp/
        ├── LanLensMenuBarApp.swift
        ├── Views/
        ├── State/
        └── Services/
```

### 2.4 Consequences

**Positive:**
- Clean separation enables future iOS app development
- Core logic is platform-agnostic
- Testing is simplified

**Negative:**
- Two build systems (SPM + Xcode) must be maintained
- Some code duplication risk between packages

---

## 3. Actor-Based Concurrency Model

### 3.1 Decision

All stateful services are implemented as Swift Actors to ensure thread safety.

### 3.2 Actors in Use

| Actor | Purpose | Isolation |
|-------|---------|-----------|
| `DiscoveryManager` | Orchestrates discovery, maintains device registry | Global singleton |
| `ARPScanner` | Executes ARP commands | Global singleton |
| `MDNSListener` | Manages NWBrowser instances | Global singleton |
| `SSDPListener` | Manages UDP multicast | Global singleton |
| `PortScanner` | Coordinates port scanning | Global singleton |
| `DeviceStore` | In-memory cache + persistence | Global singleton |
| `DeviceBehaviorTracker` | Tracks device presence | Global singleton |
| `DIContainer` | Dependency injection | Global singleton |

### 3.3 Rationale

- Swift 5.5+ actors provide compile-time safety for concurrent access
- Eliminates data races without manual lock management
- Natural fit for network I/O operations

### 3.4 Pattern: Actor with Sendable Callbacks

```swift
public actor DiscoveryManager {
    public typealias DeviceUpdateHandler = @Sendable (Device, UpdateType) -> Void
    private var onDeviceUpdate: DeviceUpdateHandler?

    public func startPassiveDiscovery(onUpdate: @escaping DeviceUpdateHandler) async {
        onDeviceUpdate = onUpdate
        // ...
    }
}
```

---

## 4. Protocol-Oriented Service Design

### 4.1 Decision

All major services conform to protocols, enabling dependency injection and testing.

### 4.2 Protocol Hierarchy

```
ARPScannerProtocol          → ARPScanner
MDNSListenerProtocol        → MDNSListener
SSDPListenerProtocol        → SSDPListener
PortScannerProtocol         → PortScanner
FingerbankServiceProtocol   → FingerbankService
FingerprintCacheManagerProtocol → FingerprintCacheManager
DeviceFingerprintManagerProtocol → DeviceFingerprintManager
DatabaseProtocol            → DatabaseManager
DeviceRepositoryProtocol    → DeviceRepository
DeviceStoreProtocol         → DeviceStore
```

### 4.3 Dependency Injection Container

```swift
public actor DIContainer {
    public static let shared = DIContainer()

    private var _arpScanner: (any ARPScannerProtocol)?

    public var arpScanner: any ARPScannerProtocol {
        get {
            if let scanner = _arpScanner { return scanner }
            let scanner = ARPScanner.shared
            _arpScanner = scanner
            return scanner
        }
    }

    // Testing: inject mocks
    public func setARPScanner(_ scanner: any ARPScannerProtocol) {
        _arpScanner = scanner
    }
}
```

---

## 5. Multi-Protocol Discovery Pipeline

### 5.1 Decision

Implement a multi-protocol discovery strategy that combines passive and active techniques.

### 5.2 Discovery Flow

```
┌─────────────────────────────────────────────────────────────┐
│                     DISCOVERY PIPELINE                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │  ARP Table  │    │    mDNS     │    │    SSDP     │     │
│  │  (passive)  │    │  (passive)  │    │  (passive)  │     │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘     │
│         │                  │                  │             │
│         └──────────────────┼──────────────────┘             │
│                            │                                │
│                            ▼                                │
│              ┌────────────────────────┐                     │
│              │   DiscoveryManager     │                     │
│              │   (Device Registry)    │                     │
│              └────────────────────────┘                     │
│                            │                                │
│                            ▼                                │
│              ┌────────────────────────┐                     │
│              │   Fingerprinting       │                     │
│              │   (UPnP + Fingerbank)  │                     │
│              └────────────────────────┘                     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 5.3 Protocol Details

| Protocol | Transport | Port | Trigger |
|----------|-----------|------|---------|
| ARP | Layer 2 | N/A | CLI: `/usr/sbin/arp -an` |
| mDNS | UDP Multicast | 5353 | NWBrowser + `dns-sd` |
| SSDP | UDP Multicast | 1900 | M-SEARCH + NOTIFY listener |
| DNS-SD | UDP | 5353 | `dns-sd -B` + `dns-sd -L` |
| Port Scan | TCP | Various | Socket connect or nmap |

### 5.4 Service Types Monitored (28+)

```swift
static let serviceTypes = [
    "_airplay._tcp", "_raop._tcp", "_homekit._tcp",
    "_hap._tcp", "_googlecast._tcp", "_spotify-connect._tcp",
    "_sonos._tcp", "_http._tcp", "_https._tcp",
    "_printer._tcp", "_ipp._tcp", "_ipps._tcp",
    "_ssh._tcp", "_sftp-ssh._tcp", "_smb._tcp",
    "_afpovertcp._tcp", "_nfs._tcp", "_ftp._tcp",
    "_mqtt._tcp", "_rtsp._tcp", "_daap._tcp",
    "_dacp._tcp", "_touch-able._tcp", "_companion-link._tcp",
    "_sleep-proxy._udp", "_device-info._tcp",
    "_hue._tcp", "_nanoleaf._tcp"
]
```

---

## 6. Two-Tier Fingerprinting

### 6.1 Decision

Implement a tiered fingerprinting system with local (UPnP) and cloud (Fingerbank) levels.

### 6.2 Architecture

```
Device Discovered (with SSDP LOCATION URL)
                │
                ▼
┌──────────────────────────────────────┐
│     Level 1: UPnP Description        │ ◄── Always runs
│     (Fetch XML from device)          │
└──────────────────┬───────────────────┘
                   │
                   ▼
┌──────────────────────────────────────┐
│     Check: Fingerbank Enabled?       │
└──────────────────┬───────────────────┘
                   │
        ┌──────────┴──────────┐
        │ Yes                 │ No
        ▼                     ▼
┌───────────────────┐   ┌───────────────────┐
│ Level 2:          │   │ Return Level 1    │
│ Fingerbank API    │   │ Data Only         │
└───────────────────┘   └───────────────────┘
```

### 6.3 Fingerbank Integration

**Circuit Breaker Pattern:**
```swift
public actor CircuitBreaker {
    enum State { case closed, open, halfOpen }
    private var state: State = .closed
    private var failureCount: Int = 0

    func execute<T>(_ operation: () async throws -> T) async throws -> T {
        // Prevents cascading failures when Fingerbank is unavailable
    }
}
```

**Rate Limiting:**
- 300 requests/hour, 2,000/day, 30,000/month
- Automatic backoff when limits approached
- Cache TTL: 7 days (Fingerbank), 24 hours (UPnP)

---

## 7. GRDB-Based Persistence

### 7.1 Decision

Use GRDB.swift for SQLite persistence instead of SQLite.swift.

### 7.2 Rationale

- **Better Swift Integration**: GRDB provides more idiomatic Swift APIs
- **Migration Support**: Built-in schema migration system
- **Async Support**: Native async/await support
- **Performance**: Connection pooling via DatabasePool

### 7.3 Database Schema

**Migration v1 (Initial):**
```sql
CREATE TABLE devices (
    mac TEXT PRIMARY KEY,
    id TEXT NOT NULL,
    ip TEXT NOT NULL,
    hostname TEXT,
    vendor TEXT,
    firstSeen DATETIME NOT NULL,
    lastSeen DATETIME NOT NULL,
    isOnline BOOLEAN NOT NULL DEFAULT 1,
    smartScore INTEGER NOT NULL DEFAULT 0,
    deviceType TEXT NOT NULL DEFAULT 'unknown',
    userLabel TEXT,
    openPorts TEXT NOT NULL DEFAULT '[]',
    services TEXT NOT NULL DEFAULT '[]',
    httpInfo TEXT,
    smartSignals TEXT NOT NULL DEFAULT '[]',
    fingerprint TEXT
);

CREATE INDEX idx_devices_ip ON devices(ip);
CREATE INDEX idx_devices_lastSeen ON devices(lastSeen);
CREATE INDEX idx_devices_isOnline ON devices(isOnline);
```

**Migration v2 (Enhanced Inference):**
```sql
ALTER TABLE devices ADD COLUMN mdnsTXTRecords TEXT;
ALTER TABLE devices ADD COLUMN portBanners TEXT;
ALTER TABLE devices ADD COLUMN macAnalysis TEXT;
ALTER TABLE devices ADD COLUMN securityPosture TEXT;
ALTER TABLE devices ADD COLUMN behaviorProfile TEXT;
```

**Migration v3 (Network Source):**
```sql
ALTER TABLE devices ADD COLUMN networkSource TEXT;
```

**Migration v4 (Presence Records):**
```sql
CREATE TABLE presence_records (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    mac TEXT NOT NULL REFERENCES devices(mac) ON DELETE CASCADE,
    timestamp DATETIME NOT NULL,
    isOnline BOOLEAN NOT NULL,
    ipAddress TEXT,
    availableServices TEXT NOT NULL DEFAULT '[]',
    UNIQUE(mac, timestamp)
);

CREATE INDEX idx_presence_mac ON presence_records(mac);
CREATE INDEX idx_presence_timestamp ON presence_records(timestamp);
```

### 7.4 Three-Layer Architecture

```
┌─────────────────────────────────────────┐
│           DeviceStore (Actor)           │  ◄── In-memory cache
│     - devices: [String: Device]         │      with auto-sync
└────────────────┬────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────┐
│        DeviceRepository (Class)         │  ◄── CRUD operations
└────────────────┬────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────┐
│       DatabaseManager (Class)           │  ◄── GRDB wrapper
│     - dbPool: DatabasePool              │
└─────────────────────────────────────────┘
```

### 7.5 Schema Evolution

The database schema has evolved through four migrations:
- **v1**: Core device table with basic fields
- **v2**: Enhanced inference data (mDNS TXT, port banners, MAC analysis, security posture, behavior profile)
- **v3**: Network source tracking for multi-VLAN support
- **v4**: Separate presence_records table for behavior history

---

## 8. Observable State Management

### 8.1 Decision

Use the `@Observable` macro (iOS 17+) with `@MainActor` for UI state.

### 8.2 AppState Architecture

```swift
@Observable
@MainActor
final class AppState {
    // Published State
    private(set) var devices: [Device] = []
    private(set) var isScanning = false
    private(set) var isAPIRunning = false
    private(set) var lastScanTime: Date?
    private(set) var scanError: String?
    var selectedDevice: Device?

    // Cached Filtered Arrays (Performance)
    private(set) var smartDevices: [Device] = []
    private(set) var otherDevices: [Device] = []

    // Debouncing (Prevents Task Spawning)
    private var pendingUpdates: [(Device, UpdateType)] = []
    private var debounceTask: Task<Void, Never>?
    private let debounceInterval: Duration = .milliseconds(100)
}
```

### 8.3 Debounced Updates

```swift
private func queueDeviceUpdate(_ device: Device, type: UpdateType) {
    pendingUpdates.append((device, type))

    debounceTask?.cancel()
    debounceTask = Task {
        try? await Task.sleep(for: debounceInterval)
        guard !Task.isCancelled else { return }
        processPendingUpdates()
    }
}
```

---

## 9. Thermal-Aware Background Scanning

### 9.1 Decision

Implement thermal pressure monitoring to reduce CPU usage when system is under thermal stress.

### 9.2 Implementation

```swift
// BackgroundScanner.swift
private func adjustForThermalState(_ state: ProcessInfo.ThermalState) {
    switch state {
    case .nominal:
        // Normal operation
    case .fair:
        // Reduce scan frequency
    case .serious:
        // Minimal scanning
    case .critical:
        // Suspend scanning
    }
}
```

---

## 10. Data Model

### 10.1 Core Device Model

```swift
public struct Device: Identifiable, Codable, Sendable, Hashable {
    // Identity
    public let id: UUID
    public let mac: String
    public var ip: String
    public var hostname: String?
    public var vendor: String?

    // Lifecycle
    public var firstSeen: Date
    public var lastSeen: Date
    public var isOnline: Bool

    // Discovery Results
    public var openPorts: [Port]
    public var services: [DiscoveredService]
    public var httpInfo: HTTPInfo?

    // Classification
    public var smartScore: Int
    public var smartSignals: [SmartSignal]
    public var deviceType: DeviceType
    public var userLabel: String?

    // Fingerprinting
    public var fingerprint: DeviceFingerprint?

    // Enhanced Analysis
    public var mdnsTXTRecords: MDNSTXTData?
    public var portBanners: PortBannerData?
    public var macAnalysis: MACAnalysisData?
    public var securityPosture: SecurityPostureData?
    public var behaviorProfile: DeviceBehaviorProfile?
}
```

### 10.2 Device Types

```swift
public enum DeviceType: String, Codable, Sendable, CaseIterable {
    case smartTV, speaker, camera, thermostat, light, plug
    case hub, printer, nas, computer, phone, tablet
    case router, accessPoint, appliance, unknown
}
```

---

## 11. REST API

### 11.1 Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check with uptime, device count |
| GET | `/api/devices` | List all devices |
| GET | `/api/devices/smart?minScore=20` | List smart devices |
| GET | `/api/devices/:mac` | Get device by MAC |
| GET | `/api/devices/export?format=json\|csv` | Export devices |
| POST | `/api/discover/passive?duration=10` | Run passive discovery |
| POST | `/api/discover/arp` | Read ARP table |
| POST | `/api/discover/dnssd` | Run DNS-SD discovery |
| POST | `/api/scan/ports/:mac` | Scan ports for device |
| POST | `/api/scan/quick` | Quick scan all devices |
| POST | `/api/scan/full` | Full scan all devices |
| GET | `/api/scan/nmap-status` | Check nmap availability |
| GET | `/api/tools` | Check tool status |
| WS | `/api/ws` | WebSocket for real-time updates |

### 11.2 Authentication

```swift
struct AuthMiddleware: RouterMiddleware {
    let token: String

    func handle(_ request: Request, context: Context,
                next: (Request, Context) async throws -> Response) async throws -> Response {
        // Check Authorization: Bearer <token>
    }
}
```

### 11.3 WebSocket Events

The WebSocket endpoint at `/api/ws` broadcasts real-time events:

| Event Type | Trigger | Payload |
|------------|---------|---------|
| `deviceDiscovered` | New device found | Device object |
| `deviceUpdated` | Device info changed | Device object |
| `deviceOffline` | Device went offline | Device object |
| `scanStarted` | Scan begins | `{scanType, deviceCount: null}` |
| `scanCompleted` | Scan ends | `{scanType, deviceCount}` |

**Connection Authentication:**
- Query parameter: `?token=YOUR_TOKEN`
- Validates against configured API auth token

### 11.4 Export Format

**JSON Export:**
```json
{
  "exportDate": "2026-01-02T12:00:00Z",
  "deviceCount": 42,
  "devices": [/* Device objects */]
}
```

**CSV Export:**
```csv
mac,ip,hostname,vendor,deviceType,smartScore,isOnline,firstSeen,lastSeen
00:11:22:33:44:55,192.168.1.100,device.local,Apple,computer,75,true,2026-01-01T00:00:00Z,2026-01-02T12:00:00Z
```

---

## 12. Technical Debt Summary

| Issue | Priority | Status |
|-------|----------|--------|
| SQLite.swift declared but unused | Low | RESOLVED - Removed from Package.swift |
| Enhanced inference models not persisted | Medium | RESOLVED - Migration v2 |
| Behavior tracking not persisted | Medium | RESOLVED - Migration v4 |
| Test coverage | High | RESOLVED - 159 unit tests across 6 test files |

---

## 13. Decision Log

### ADR-001: Use GRDB over SQLite.swift

**Status:** Accepted

**Decision:** Use GRDB.swift despite SQLite.swift being declared in Package.swift.

**Consequences:** Better async support, cleaner migration syntax. Technical debt: remove SQLite.swift dependency.

### ADR-002: Actor-based Singletons

**Status:** Accepted

**Decision:** Implement all stateful services as actors with `shared` singleton instances.

**Consequences:** Compile-time thread safety, global state acceptable for app scope, DI container enables testing.

### ADR-003: Two-Tier Fingerprinting

**Status:** Accepted

**Decision:** Add optional Fingerbank integration as Level 2.

**Consequences:** Better device identification, privacy consideration (opt-in by design).

### ADR-004: WebSocket for Real-Time Updates

**Status:** Accepted

**Decision:** Implement WebSocket support using HummingbirdWebSocket for real-time device update broadcasts.

**Consequences:** Enables iOS companion app and other clients to receive live updates without polling.

### ADR-005: Multi-VLAN via Network Interface Manager

**Status:** Accepted

**Decision:** Implement network interface enumeration and selection for multi-VLAN scanning via `NetworkInterfaceManager`.

**Consequences:** Users can scan devices across multiple VLANs/subnets when routing permits.

### ADR-006: Behavior History Persistence

**Status:** Accepted

**Decision:** Store presence history in a separate `presence_records` table (migration v4) rather than JSON blob in devices table.

**Consequences:** Efficient querying, automatic cleanup via foreign key cascade, better long-term storage.
