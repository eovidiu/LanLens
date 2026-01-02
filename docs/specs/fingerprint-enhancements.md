# Fingerprint Enhancements Feature Specification

**Version:** 1.0  
**Date:** January 2, 2026  
**Status:** Draft - Pending Review  
**Author:** System Specification Curator

---

## 1. Context & Boundaries

### 1.1 Purpose

This specification defines three enhancements to LanLens device fingerprinting capabilities:

1. **Local DHCP Fingerprint Database** - Offline device identification via DHCP Option 55
2. **JA3/JA4 TLS Fingerprinting** - TLS Client Hello fingerprinting for device/app classification
3. **Offline Fingerbank Cache** - Local cache enabling offline operation

These features address the current limitation where device identification requires either:
- Active UPnP responses from devices (many devices do not support UPnP)
- Online access to Fingerbank API (requires internet and API key)

### 1.2 Problem Statement

**Current State:**

| Identification Method | Coverage | Requirements | Offline Capable |
|----------------------|----------|--------------|-----------------|
| UPnP Device Description | ~30% of devices | Device must support UPnP | Yes |
| Fingerbank API | ~80% of devices | Internet + API key | No |
| MAC Vendor Lookup | ~90% of devices | Local OUI database | Yes |

**Gaps:**

1. **No DHCP fingerprinting**: DHCP Option 55 (Parameter Request List) is a highly reliable device identifier, but LanLens does not capture or use this data
2. **No TLS fingerprinting**: Modern devices make TLS connections that reveal device/application identity via JA3/JA4 hashes
3. **No offline Fingerbank**: When offline or rate-limited, fingerprint quality degrades significantly
4. **API dependency**: Users without API keys or internet get significantly degraded device identification

### 1.3 Stakeholders

| Role | Responsibilities | Concerns |
|------|------------------|----------|
| Home User | Primary user scanning home network | Privacy, ease of use, no API keys required |
| Privacy-Conscious User | Uses LanLens for network visibility | No data sent externally, offline operation |
| Power User | Scans multiple networks, needs deep analysis | Accuracy, coverage, detailed fingerprints |
| Developer | Maintains LanLens codebase | Maintainability, testing, performance |

### 1.4 System Boundaries

**In Scope:**
- Local DHCP fingerprint capture and lookup
- Local JA3/JA4 hash capture and lookup
- Embedded fingerprint databases shipped with the app
- Periodic database updates via app updates
- Integration with existing `DeviceTypeInferenceEngine`

**Out of Scope:**
- Active DHCP server implementation
- Man-in-the-middle TLS interception
- Real-time database updates (only via app releases)
- Custom user-contributed fingerprints
- Enterprise NAC integration

### 1.5 External Dependencies

| Dependency | Type | SLA | Failure Impact |
|------------|------|-----|----------------|
| Fingerbank Open Source DB | Static file | N/A (bundled) | Uses stale data until app update |
| JA3/JA4 Database | Static file | N/A (bundled) | Uses stale data until app update |
| BPF/Packet Capture | System capability | macOS API | DHCP/TLS capture unavailable |
| Network Extension | Entitlement | Apple approval | TLS fingerprinting blocked |

---

## 2. Domain Model

### 2.1 Entities

#### DHCPFingerprint

| Attribute | Type | Description | Constraints |
|-----------|------|-------------|-------------|
| `optionList` | `[UInt8]` | DHCP Option 55 parameter request list | Immutable once captured |
| `fingerprint` | `String` | Comma-separated string (e.g., "1,3,6,15,31,33") | Derived from optionList |
| `hash` | `String` | SHA256 hash of fingerprint for lookup | Indexed |
| `capturedAt` | `Date` | When fingerprint was captured | Immutable |
| `macAddress` | `String` | Associated device MAC | Foreign key to Device |

#### TLSFingerprint

| Attribute | Type | Description | Constraints |
|-----------|------|-------------|-------------|
| `ja3Hash` | `String` | JA3 fingerprint (MD5 of Client Hello params) | 32-char hex string |
| `ja3sHash` | `String?` | JA3S fingerprint (server response) | 32-char hex string |
| `ja4Hash` | `String?` | JA4 fingerprint (improved JA3) | Variable format |
| `capturedAt` | `Date` | When fingerprint was captured | Immutable |
| `macAddress` | `String` | Source device MAC | Foreign key to Device |
| `destinationIP` | `String` | TLS connection destination | For context |
| `destinationPort` | `UInt16` | TLS connection port | Default 443 |
| `sni` | `String?` | Server Name Indication | May reveal app/service |

#### FingerprintDatabaseEntry

| Attribute | Type | Description | Constraints |
|-----------|------|-------------|-------------|
| `id` | `Int` | Fingerbank device ID | Primary key |
| `name` | `String` | Device name | Required |
| `parents` | `[String]` | Category hierarchy | May be empty |
| `dhcpFingerprints` | `[String]` | Associated DHCP fingerprints | Indexed |
| `ja3Hashes` | `[String]` | Associated JA3 hashes | Indexed |
| `isMobile` | `Bool` | Mobile device flag | Default false |
| `isTablet` | `Bool` | Tablet device flag | Default false |

### 2.2 Entity Relationships

```
Device (1) ----< (N) DHCPFingerprint
Device (1) ----< (N) TLSFingerprint
FingerprintDatabaseEntry (1) ----< (N) DHCPFingerprint (via hash lookup)
FingerprintDatabaseEntry (1) ----< (N) TLSFingerprint (via hash lookup)
```

### 2.3 Invariants

| Invariant | Description | Violation Consequence |
|-----------|-------------|----------------------|
| INV-1 | DHCP fingerprint string MUST be sorted option numbers | Lookup will fail |
| INV-2 | JA3 hash MUST be 32-character lowercase hex | Lookup will fail |
| INV-3 | MAC address MUST be normalized (uppercase, colon-separated) | Duplicate records |
| INV-4 | Database entries MUST have unique fingerprint mappings | Ambiguous lookups |
| INV-5 | `capturedAt` MUST NOT be in the future | Data integrity |

### 2.4 Immutable Fields

The following fields MUST NOT be modified after creation:
- `DHCPFingerprint.optionList`
- `DHCPFingerprint.fingerprint`
- `DHCPFingerprint.hash`
- `DHCPFingerprint.capturedAt`
- `TLSFingerprint.ja3Hash`
- `TLSFingerprint.ja4Hash`
- `TLSFingerprint.capturedAt`
- `FingerprintDatabaseEntry.id`

---

## 3. Functional Requirements

### 3.1 DHCP Fingerprint Capture

#### FR-DHCP-001: Passive DHCP Packet Capture

**Priority**: MUST

**Specification:**
```
Given LanLens is running with packet capture enabled
When a DHCP DISCOVER or DHCP REQUEST packet is observed on the local network
Then LanLens MUST extract the Option 55 (Parameter Request List) from the packet
And normalize the option list to a comma-separated string of decimal values
And compute the SHA256 hash of the normalized string
And associate the fingerprint with the source MAC address
```

**Acceptance Criteria:**
- [ ] DHCP DISCOVER packets (opcode 1, message type 1) are captured
- [ ] DHCP REQUEST packets (opcode 1, message type 3) are captured
- [ ] Option 55 is correctly parsed from DHCP options field
- [ ] Option values are sorted numerically before creating fingerprint string
- [ ] Fingerprint is stored in SQLite database

**Error Scenarios:**

| Condition | Expected Behavior |
|-----------|-------------------|
| Packet capture permission denied | Log warning, disable DHCP capture, continue with other fingerprinting |
| Malformed DHCP packet | Skip packet, log at debug level |
| Option 55 not present | Skip fingerprint capture for this packet |
| Database write fails | Retry once, then log error and continue |

#### FR-DHCP-002: Local DHCP Fingerprint Lookup

**Priority**: MUST

**Specification:**
```
Given a device with a captured DHCP fingerprint
When the DeviceTypeInferenceEngine processes the device
Then it MUST query the local fingerprint database for matching entries
And return device identification data if a match is found
And the match confidence MUST be 0.85 (higher than MAC vendor, lower than Fingerbank API)
```

**Acceptance Criteria:**
- [ ] Database lookup completes in <10ms for 100,000 entries
- [ ] Exact match returns device identification
- [ ] No match returns nil without error
- [ ] Multiple matches return the entry with highest Fingerbank score

#### FR-DHCP-003: DHCP Fingerprint Database Updates

**Priority**: SHOULD

**Specification:**
```
Given a new version of LanLens is released
When the app is updated
Then the embedded DHCP fingerprint database MUST be updated to the bundled version
And existing captured fingerprints MUST NOT be deleted
And the database version MUST be logged
```

**Acceptance Criteria:**
- [ ] Database is stored in app bundle as SQLite or JSON
- [ ] Database version is tracked in metadata
- [ ] Update does not affect user-captured data

### 3.2 TLS Fingerprinting

#### FR-TLS-001: Passive TLS Client Hello Capture

**Priority**: SHOULD

**Specification:**
```
Given LanLens is running with TLS capture enabled
And the user has granted Network Extension permissions
When a TLS Client Hello packet is observed on the local network
Then LanLens MUST extract the following fields:
  - TLS version
  - Cipher suites list
  - Extensions list
  - Elliptic curves
  - EC point formats
And compute the JA3 hash (MD5 of concatenated fields)
And compute the JA4 hash if sufficient data is available
And associate the fingerprint with the source MAC address
```

**Acceptance Criteria:**
- [ ] TLS 1.0, 1.1, 1.2, and 1.3 Client Hello packets are parsed
- [ ] JA3 hash matches reference implementation output
- [ ] SNI is extracted when present
- [ ] Destination IP and port are recorded
- [ ] Fingerprint is stored in SQLite database

**Error Scenarios:**

| Condition | Expected Behavior |
|-----------|-------------------|
| Network Extension not authorized | Disable TLS capture, log warning, continue |
| Encrypted Client Hello (ECH) | Extract available fields, log partial capture |
| Malformed TLS packet | Skip packet, log at debug level |
| High packet rate (>1000/sec) | Sample packets, log rate limiting |

#### FR-TLS-002: Local JA3/JA4 Lookup

**Priority**: SHOULD

**Specification:**
```
Given a device with captured TLS fingerprints
When the DeviceTypeInferenceEngine processes the device
Then it MUST query the local JA3/JA4 database for matching entries
And return device/application identification if a match is found
And the match confidence MUST be 0.80
```

**Acceptance Criteria:**
- [ ] Database lookup completes in <10ms
- [ ] JA3 hash lookup returns application/device type
- [ ] JA4 hash lookup returns application/device type
- [ ] Both JA3 and JA4 matches increase confidence to 0.90

#### FR-TLS-003: TLS Fingerprint Aggregation

**Priority**: MAY

**Specification:**
```
Given a device with multiple captured TLS fingerprints over time
When displaying device information
Then LanLens MAY show:
  - Most common JA3 hash (primary application)
  - Unique JA3 hash count (application diversity)
  - Common destinations (SNI values)
```

### 3.3 Offline Fingerbank Cache

#### FR-CACHE-001: Bundled Fingerbank Database

**Priority**: MUST

**Specification:**
```
Given LanLens is installed
Then the app bundle MUST contain a pre-populated fingerprint database
And the database MUST include at least the top 10,000 Fingerbank device entries
And the database MUST be queryable by MAC OUI prefix
And the database MUST be queryable by DHCP fingerprint hash
```

**Acceptance Criteria:**
- [ ] Database size is <50MB uncompressed
- [ ] Database includes device hierarchy (parents)
- [ ] Database includes mobile/tablet flags
- [ ] Database is loaded at app startup in <500ms
- [ ] Database queries return results in <10ms

#### FR-CACHE-002: Offline-First Lookup Strategy

**Priority**: MUST

**Specification:**
```
Given a device MAC address and optional DHCP fingerprint
When fingerprint lookup is requested
Then LanLens MUST:
  1. Check local fingerprint cache (previous API responses)
  2. Check bundled Fingerbank database by DHCP fingerprint (if available)
  3. Check bundled Fingerbank database by MAC OUI
  4. If online AND API key configured: query Fingerbank API
  5. Return best available match with source indicator
```

**Acceptance Criteria:**
- [ ] Offline lookup returns results without network access
- [ ] Cache hits are preferred over bundled database
- [ ] Bundled database is preferred over API calls
- [ ] API is only called when local data is insufficient
- [ ] Response includes `source` field indicating data origin

#### FR-CACHE-003: Cache Persistence

**Priority**: MUST

**Specification:**
```
Given LanLens has queried the Fingerbank API for a device
When the response is received
Then the response MUST be cached locally
And the cache entry MUST have a TTL of 30 days (increased from current 7 days)
And the cache MUST survive app restarts
And the cache MUST be stored in the Application Support directory
```

**Acceptance Criteria:**
- [ ] Cache entries persist across app restarts
- [ ] TTL is configurable (default 30 days)
- [ ] Cache is stored in `~/Library/Application Support/LanLens/FingerprintCache/`
- [ ] Cache can be cleared via Settings

---

## 4. Non-Functional Requirements

### 4.1 Performance

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| DHCP fingerprint capture latency | <5ms from packet receipt | Instrumented logging |
| TLS fingerprint capture latency | <10ms from packet receipt | Instrumented logging |
| Local database lookup | <10ms for single query | Unit test benchmark |
| Database load time at startup | <500ms | App startup metrics |
| Memory overhead for databases | <100MB | Memory profiler |
| CPU overhead for packet capture | <5% idle | Activity Monitor |

### 4.2 Reliability

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| Fingerprint capture success rate | >95% of DHCP/TLS packets | Capture vs observed ratio |
| Database lookup availability | 100% when app is running | Exception monitoring |
| Cache data integrity | Zero corruption events | Checksum verification |

### 4.3 Security

| Requirement | Implementation |
|-------------|----------------|
| DHCP data is local only | No external transmission |
| TLS data is local only | No external transmission (except Fingerbank MAC lookup if enabled) |
| Database files are user-readable only | chmod 600 on cache files |
| No captured payloads stored | Only fingerprint hashes stored |

### 4.4 Privacy

| Data Type | Captured | Stored | Transmitted |
|-----------|----------|--------|-------------|
| DHCP Option 55 | Yes | Hash only | Never |
| TLS Client Hello | Yes | Hash only | Never |
| MAC Address | Yes | Yes | Only to Fingerbank if enabled |
| Destination IP/Port | Yes | Yes | Never |
| SNI (Server Name) | Yes | Yes | Never |

---

## 5. Data Requirements

### 5.1 Bundled Database Schema

#### Table: `dhcp_fingerprints`

```sql
CREATE TABLE dhcp_fingerprints (
    id INTEGER PRIMARY KEY,
    fingerprint_hash TEXT NOT NULL UNIQUE,     -- SHA256 of sorted option list
    fingerprint_string TEXT NOT NULL,          -- Human-readable "1,3,6,15,..."
    device_id INTEGER NOT NULL,                -- FK to devices
    confidence INTEGER DEFAULT 85,             -- 0-100
    FOREIGN KEY (device_id) REFERENCES devices(id)
);

CREATE INDEX idx_dhcp_hash ON dhcp_fingerprints(fingerprint_hash);
```

#### Table: `ja3_fingerprints`

```sql
CREATE TABLE ja3_fingerprints (
    id INTEGER PRIMARY KEY,
    ja3_hash TEXT NOT NULL,                    -- 32-char MD5 hex
    ja4_hash TEXT,                             -- JA4 format
    device_id INTEGER,                         -- FK to devices (may be null for app-only)
    application_name TEXT,                     -- e.g., "Chrome", "curl"
    os_name TEXT,                              -- e.g., "Windows 10", "macOS"
    confidence INTEGER DEFAULT 80,
    FOREIGN KEY (device_id) REFERENCES devices(id)
);

CREATE INDEX idx_ja3_hash ON ja3_fingerprints(ja3_hash);
CREATE INDEX idx_ja4_hash ON ja3_fingerprints(ja4_hash);
```

#### Table: `devices` (bundled Fingerbank subset)

```sql
CREATE TABLE devices (
    id INTEGER PRIMARY KEY,                    -- Fingerbank device ID
    name TEXT NOT NULL,                        -- Device name
    parent_id INTEGER,                         -- Parent device ID
    parent_name TEXT,                          -- Parent name for display
    hierarchy TEXT,                            -- JSON array of parent names
    is_mobile INTEGER DEFAULT 0,
    is_tablet INTEGER DEFAULT 0,
    score INTEGER DEFAULT 50                   -- Default confidence
);

CREATE INDEX idx_device_name ON devices(name);
```

#### Table: `oui_mappings`

```sql
CREATE TABLE oui_mappings (
    oui TEXT PRIMARY KEY,                      -- XX:XX:XX format
    device_id INTEGER,                         -- Most common device for this OUI
    vendor_name TEXT,                          -- Vendor name
    FOREIGN KEY (device_id) REFERENCES devices(id)
);
```

### 5.2 User Data Schema Extensions

Add to existing `devices` table (migration v5):

```sql
ALTER TABLE devices ADD COLUMN dhcp_fingerprint_hash TEXT;
ALTER TABLE devices ADD COLUMN dhcp_fingerprint_string TEXT;
ALTER TABLE devices ADD COLUMN dhcp_captured_at DATETIME;
```

New table for TLS fingerprints (migration v5):

```sql
CREATE TABLE tls_fingerprints (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    mac TEXT NOT NULL,
    ja3_hash TEXT NOT NULL,
    ja4_hash TEXT,
    sni TEXT,
    destination_ip TEXT,
    destination_port INTEGER,
    captured_at DATETIME NOT NULL,
    FOREIGN KEY (mac) REFERENCES devices(mac) ON DELETE CASCADE
);

CREATE INDEX idx_tls_mac ON tls_fingerprints(mac);
CREATE INDEX idx_tls_ja3 ON tls_fingerprints(ja3_hash);
CREATE INDEX idx_tls_captured ON tls_fingerprints(captured_at);
```

### 5.3 Data Retention

| Data Type | Retention Period | Cleanup Trigger |
|-----------|-----------------|-----------------|
| Captured DHCP fingerprints | Indefinite (associated with device) | Device deletion |
| Captured TLS fingerprints | 90 days | Automated cleanup job |
| Fingerbank API cache | 30 days TTL | Cache expiration |
| Bundled database | Until app update | App update replaces |

### 5.4 Data Volume Estimates

| Data Type | Estimated Size | Growth Rate |
|-----------|---------------|-------------|
| Bundled DHCP database | ~5MB (50,000 entries) | Per app release |
| Bundled JA3 database | ~10MB (100,000 entries) | Per app release |
| Bundled device database | ~20MB (100,000 entries) | Per app release |
| User DHCP captures | ~100 bytes/device | Slow (device count) |
| User TLS captures | ~200 bytes/capture | Medium (connection count) |

---

## 6. Architecture

### 6.1 Component Diagram

```
+------------------------------------------------------------------+
|                        LanLensCore                                |
+------------------------------------------------------------------+
|                                                                   |
|  +-------------------+    +--------------------+                  |
|  | PacketCapture     |    | FingerprintLookup  |                 |
|  | Service           |    | Service            |                 |
|  +-------------------+    +--------------------+                  |
|  | - DHCPCapture     |    | - LocalDBLookup    |                 |
|  | - TLSCapture      |    | - CacheLookup      |                 |
|  |                   |    | - APILookup        |                 |
|  +--------+----------+    +----------+---------+                 |
|           |                          |                            |
|           v                          v                            |
|  +-------------------+    +--------------------+                  |
|  | CapturedFingerprint|   | BundledDatabase    |                 |
|  | Repository        |    | Manager            |                 |
|  +-------------------+    +--------------------+                  |
|  | - saveDHCP()      |    | - loadDatabase()   |                 |
|  | - saveTLS()       |    | - queryByDHCP()    |                 |
|  | - getByMAC()      |    | - queryByJA3()     |                 |
|  |                   |    | - queryByOUI()     |                 |
|  +--------+----------+    +----------+---------+                 |
|           |                          |                            |
|           v                          v                            |
|  +--------------------------------------------------+            |
|  |              DatabaseManager (GRDB)               |            |
|  |  - devices.sqlite (user data)                    |            |
|  |  - fingerprints.sqlite (bundled, read-only)      |            |
|  +--------------------------------------------------+            |
|                                                                   |
+------------------------------------------------------------------+
```

### 6.2 Data Flow

```
1. DHCP Packet Received
   |
   v
2. PacketCaptureService.handleDHCPPacket()
   |
   v
3. Extract Option 55 -> Normalize -> Hash
   |
   v
4. CapturedFingerprintRepository.saveDHCP(mac, hash)
   |
   v
5. DiscoveryManager receives device update
   |
   v
6. DeviceTypeInferenceEngine.inferType()
   |
   +---> FingerprintLookupService.lookup(mac, dhcpHash)
         |
         +---> CacheLookup (previous API responses)
         |     |
         |     +--(hit)--> Return cached result
         |
         +---> LocalDBLookup (bundled database)
         |     |
         |     +--(hit)--> Return local result
         |
         +---> APILookup (if enabled and online)
               |
               +--> FingerbankService.interrogate()
               |
               +--> Cache response
               |
               +--> Return API result
```

### 6.3 Technology Choices

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| Packet Capture | BPF (Berkeley Packet Filter) | Native macOS support, low overhead |
| Database | SQLite via GRDB | Consistent with existing persistence |
| Bundled DB Format | SQLite | Read-only, indexed, efficient |
| Hash Algorithm | SHA256 (DHCP), MD5 (JA3) | SHA256 for security, MD5 for JA3 compatibility |

---

## 7. API Contracts

### 7.1 Internal APIs

#### PacketCaptureService

```swift
public protocol PacketCaptureServiceProtocol: Sendable {
    /// Start capturing DHCP packets
    func startDHCPCapture() async throws
    
    /// Stop capturing DHCP packets
    func stopDHCPCapture() async
    
    /// Start capturing TLS Client Hello packets
    func startTLSCapture() async throws
    
    /// Stop capturing TLS packets
    func stopTLSCapture() async
    
    /// Check if capture is available (permissions granted)
    var isCaptureAvailable: Bool { get async }
    
    /// Callback for captured DHCP fingerprints
    var onDHCPFingerprint: (@Sendable (DHCPFingerprint) -> Void)? { get set }
    
    /// Callback for captured TLS fingerprints
    var onTLSFingerprint: (@Sendable (TLSFingerprint) -> Void)? { get set }
}
```

#### FingerprintLookupService

```swift
public protocol FingerprintLookupServiceProtocol: Sendable {
    /// Look up device by all available fingerprints
    func lookup(
        mac: String,
        dhcpFingerprint: String?,
        ja3Hash: String?
    ) async -> FingerprintLookupResult
    
    /// Lookup result with source information
    struct FingerprintLookupResult: Sendable {
        let deviceFingerprint: DeviceFingerprint?
        let source: LookupSource
        let confidence: Double
    }
    
    enum LookupSource: String, Sendable {
        case cache          // Previous API response
        case localDHCP      // Bundled DHCP database
        case localJA3       // Bundled JA3 database
        case localOUI       // Bundled OUI->device mapping
        case fingerbankAPI  // Live API call
        case none           // No match found
    }
}
```

#### BundledDatabaseManager

```swift
public actor BundledDatabaseManager {
    /// Shared instance
    public static let shared: BundledDatabaseManager
    
    /// Load bundled database at startup
    public func initialize() async throws
    
    /// Query by DHCP fingerprint hash
    public func queryByDHCPHash(_ hash: String) async -> FingerprintDatabaseEntry?
    
    /// Query by JA3 hash
    public func queryByJA3Hash(_ hash: String) async -> (device: FingerprintDatabaseEntry?, application: String?)
    
    /// Query by MAC OUI
    public func queryByOUI(_ oui: String) async -> FingerprintDatabaseEntry?
    
    /// Database version information
    public var databaseVersion: String { get }
    public var databaseDate: Date { get }
    public var entryCount: Int { get }
}
```

### 7.2 REST API Extensions

#### GET /api/fingerprints/stats

Returns fingerprinting statistics:

```json
{
  "bundledDatabase": {
    "version": "2026.01.01",
    "dhcpEntries": 50000,
    "ja3Entries": 100000,
    "deviceEntries": 100000
  },
  "captures": {
    "dhcpCaptureEnabled": true,
    "tlsCaptureEnabled": false,
    "dhcpCaptureCount": 42,
    "tlsCaptureCount": 0
  },
  "cache": {
    "entries": 15,
    "hitRate": 0.89,
    "oldestEntry": "2025-12-15T10:00:00Z"
  },
  "api": {
    "enabled": true,
    "requestsThisHour": 12,
    "quotaRemaining": 288
  }
}
```

#### GET /api/devices/:mac/fingerprints

Returns all fingerprint data for a device:

```json
{
  "mac": "00:11:22:33:44:55",
  "dhcp": {
    "fingerprintString": "1,3,6,15,31,33,43,44,46,47,119,121,249,252",
    "hash": "a1b2c3...",
    "capturedAt": "2026-01-02T10:00:00Z",
    "matchedDevice": "Apple iPhone 15 Pro",
    "matchSource": "localDHCP",
    "confidence": 85
  },
  "tls": [
    {
      "ja3Hash": "abc123...",
      "sni": "api.apple.com",
      "capturedAt": "2026-01-02T10:01:00Z",
      "matchedApplication": "iOS System",
      "matchSource": "localJA3"
    }
  ],
  "fingerbank": {
    "deviceName": "Apple iPhone 15 Pro",
    "score": 87,
    "source": "cache",
    "cachedAt": "2025-12-20T10:00:00Z"
  }
}
```

### 7.3 Error Codes

| Error Code | Description | HTTP Status |
|------------|-------------|-------------|
| CAPTURE_UNAVAILABLE | Packet capture not available | 503 |
| CAPTURE_PERMISSION_DENIED | Missing permissions | 403 |
| DATABASE_NOT_LOADED | Bundled database not initialized | 503 |
| LOOKUP_TIMEOUT | Database query exceeded timeout | 504 |

---

## 8. State Machines

### 8.1 Packet Capture States

```
States:
+------------+     +-----------+     +---------+     +------------+
|  Disabled  | --> |  Starting | --> | Running | --> |  Stopping  |
+------------+     +-----------+     +---------+     +------------+
      ^                                   |               |
      |                                   v               |
      +-----------------------------------+---------------+
                        (stop or error)
```

| State | Description | Terminal |
|-------|-------------|----------|
| Disabled | Capture not started | No |
| Starting | Initializing BPF/Network Extension | No |
| Running | Actively capturing packets | No |
| Stopping | Cleaning up resources | No |

| From | To | Trigger | Guards |
|------|----|---------|--------|
| Disabled | Starting | startCapture() called | Permissions granted |
| Starting | Running | BPF/Extension initialized | No errors |
| Starting | Disabled | Initialization failed | Error occurred |
| Running | Stopping | stopCapture() called | None |
| Running | Stopping | Error during capture | Error occurred |
| Stopping | Disabled | Cleanup complete | None |

### 8.2 Fingerprint Lookup States

```
                    +------------------+
                    |  Check Cache     |
                    +--------+---------+
                             |
              +--------------+--------------+
              | Hit                         | Miss
              v                             v
    +------------------+          +------------------+
    | Return Cached    |          | Check Local DB   |
    +------------------+          +--------+---------+
                                           |
                                +-----------+----------+
                                | Hit                  | Miss
                                v                      v
                      +------------------+   +------------------+
                      | Return Local     |   | Check API Enabled|
                      +------------------+   +--------+---------+
                                                      |
                                            +---------+---------+
                                            | Enabled         | Disabled
                                            v                 v
                                  +------------------+  +------------------+
                                  | Query API        |  | Return No Match  |
                                  +------------------+  +------------------+
```

---

## 9. Security

### 9.1 Authentication

| Component | Mechanism |
|-----------|-----------|
| Packet Capture | macOS system permissions (App Sandbox exceptions or Network Extension) |
| Bundled Database | App bundle signing (read-only) |
| User Database | File system permissions (user-only) |

### 9.2 Authorization

| Action | Required Permission |
|--------|---------------------|
| Enable DHCP capture | Network access + packet capture entitlement |
| Enable TLS capture | Network Extension entitlement |
| Query bundled database | None (bundled with app) |
| Query user database | None (user's own data) |

### 9.3 Data Protection

| Data | Protection |
|------|------------|
| Bundled database | Code-signed, read-only |
| User database | File permissions 600, encrypted at rest via macOS |
| Captured fingerprints | Hashed before storage (DHCP); raw hashes (TLS - required for lookup) |

### 9.4 Audit Logging

| Event | Logged Data |
|-------|-------------|
| Capture started | Capture type, timestamp |
| Capture stopped | Capture type, timestamp, packet count |
| Permission denied | Capture type, timestamp |
| Database loaded | Database version, entry count |

---

## 10. Operations

### 10.1 Service Level Objectives

| SLO | Target | Measurement |
|-----|--------|-------------|
| Fingerprint lookup availability | 99.9% | Success rate of lookup operations |
| Bundled database load time | <500ms | App startup metrics |
| Offline lookup latency (p95) | <50ms | Performance logging |

### 10.2 Alerts

| Alert | Condition | Severity |
|-------|-----------|----------|
| Database Load Failed | Bundled database failed to load | Critical |
| Capture Permission Denied | User denied packet capture | Warning |
| High Capture Drop Rate | >10% packets dropped | Warning |

### 10.3 Observability

| Metric | Type | Purpose |
|--------|------|---------|
| `fingerprint.lookup.count` | Counter | Total lookups by source |
| `fingerprint.capture.count` | Counter | Packets captured by type |
| `fingerprint.db.load_time_ms` | Histogram | Database initialization time |
| `fingerprint.lookup.latency_ms` | Histogram | Lookup latency by source |

---

## 11. Testing Strategy

### 11.1 Unit Tests

| Component | Test Focus | Coverage Target |
|-----------|-----------|-----------------|
| DHCPParser | Option 55 extraction, normalization | 90% |
| TLSParser | Client Hello parsing, JA3 computation | 90% |
| BundledDatabaseManager | Query accuracy, performance | 85% |
| FingerprintLookupService | Lookup ordering, fallback logic | 90% |

### 11.2 Integration Tests

| Test | Description |
|------|-------------|
| End-to-end DHCP capture | Capture real DHCP packet, store, lookup |
| End-to-end TLS capture | Capture real TLS handshake, compute JA3 |
| Offline operation | All lookups with network disabled |
| Database migration | Upgrade from v4 to v5 schema |

### 11.3 Invariant Tests

| Invariant | Test |
|-----------|------|
| INV-1 (DHCP sorted) | Verify fingerprint string is sorted |
| INV-2 (JA3 format) | Verify JA3 hash is 32-char hex |
| INV-3 (MAC normalized) | Verify MAC uppercase and colon-separated |

### 11.4 Load Tests

| Test | Target |
|------|--------|
| Concurrent lookups | 100 concurrent lookups in <1s total |
| Large database query | 100,000 entry database query in <10ms |
| High capture rate | 1000 packets/sec without drops |

---

## 12. Decisions (ADRs)

### ADR-007: Use SQLite for Bundled Database

**Status:** Proposed

**Context:**
The bundled fingerprint database needs to be queryable offline, loadable quickly, and maintainable across app updates.

**Decision:**
Use SQLite (via GRDB) for the bundled database, stored as a read-only file in the app bundle.

**Consequences:**
- Positive: Consistent with existing GRDB usage, efficient queries, indexed
- Positive: Read-only prevents accidental modification
- Negative: Database updates require app releases
- Negative: Increases app bundle size by ~35MB

### ADR-008: JA3 for TLS Fingerprinting

**Status:** Proposed

**Context:**
Multiple TLS fingerprinting methods exist (JA3, JA3S, JA4, JARM). Need to select primary method.

**Decision:**
Use JA3 as primary fingerprint, with optional JA4 support.

**Consequences:**
- Positive: JA3 is widely adopted with large public databases
- Positive: JA4 provides improved accuracy when available
- Negative: JA3 uses MD5 (cryptographically weak, but acceptable for fingerprinting)
- Negative: TLS 1.3 with ECH may reduce effectiveness

### ADR-009: BPF for Packet Capture

**Status:** Proposed

**Context:**
Need to capture DHCP and TLS packets passively without requiring kernel extensions.

**Decision:**
Use Berkeley Packet Filter (BPF) via `/dev/bpf` for packet capture on macOS.

**Consequences:**
- Positive: Native macOS support, no kernel extensions
- Positive: Can filter at capture time (efficient)
- Negative: Requires elevated permissions or App Sandbox exception
- Negative: May not work in all network configurations (VPNs, etc.)

---

## 13. Traceability

### 13.1 Requirements to Implementation

| Requirement | Implementation File | Test File |
|-------------|---------------------|-----------|
| FR-DHCP-001 | `PacketCaptureService.swift` | `PacketCaptureServiceTests.swift` |
| FR-DHCP-002 | `FingerprintLookupService.swift` | `FingerprintLookupServiceTests.swift` |
| FR-DHCP-003 | `BundledDatabaseManager.swift` | `BundledDatabaseManagerTests.swift` |
| FR-TLS-001 | `PacketCaptureService.swift` | `PacketCaptureServiceTests.swift` |
| FR-TLS-002 | `FingerprintLookupService.swift` | `FingerprintLookupServiceTests.swift` |
| FR-CACHE-001 | `BundledDatabaseManager.swift` | `BundledDatabaseManagerTests.swift` |
| FR-CACHE-002 | `FingerprintLookupService.swift` | `FingerprintLookupServiceTests.swift` |
| FR-CACHE-003 | `FingerprintCacheManager.swift` | `FingerprintCacheManagerTests.swift` |

### 13.2 Requirements to Tests

| Requirement | Test Count | Status |
|-------------|------------|--------|
| FR-DHCP-001 | 8 | Planned |
| FR-DHCP-002 | 5 | Planned |
| FR-DHCP-003 | 3 | Planned |
| FR-TLS-001 | 10 | Planned |
| FR-TLS-002 | 5 | Planned |
| FR-TLS-003 | 3 | Planned |
| FR-CACHE-001 | 6 | Planned |
| FR-CACHE-002 | 8 | Planned |
| FR-CACHE-003 | 4 | Planned |

---

## 14. Privacy Considerations

### 14.1 Data Collection Summary

| Data Type | Collected | Purpose | Retention |
|-----------|-----------|---------|-----------|
| DHCP Option 55 | Yes | Device identification | Indefinite |
| TLS Client Hello | Yes | App identification | 90 days |
| MAC Address | Yes | Device correlation | Indefinite |
| Destination IPs | Yes | Connection context | 90 days |
| SNI | Yes | Service identification | 90 days |
| Packet Payloads | No | N/A | N/A |

### 14.2 Data Transmission

| Data | Transmitted To | Condition |
|------|----------------|-----------|
| MAC Address | Fingerbank API | Only if Fingerbank enabled AND not in local cache |
| DHCP Fingerprint | Fingerbank API | Only if Fingerbank enabled AND not in local cache |
| TLS Fingerprints | Nowhere | Never transmitted externally |
| SNI | Nowhere | Never transmitted externally |

### 14.3 User Controls

| Control | Location | Default |
|---------|----------|---------|
| Enable DHCP Capture | Settings > Fingerprinting | Off |
| Enable TLS Capture | Settings > Fingerprinting | Off |
| Enable Fingerbank API | Settings > Fingerprinting | Off |
| Clear Captured Fingerprints | Settings > Advanced | N/A (action) |
| TLS Data Retention | Settings > Fingerprinting | 90 days |

### 14.4 Privacy-First Defaults

All capture features are **disabled by default**. Users must explicitly opt-in to:
1. DHCP fingerprint capture
2. TLS fingerprint capture
3. Fingerbank API integration

Local-only fingerprint databases work without any network access or user opt-in.

---

## 15. Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-02 | System Specification Curator | Initial specification |

---

## Appendix A: DHCP Option 55 Reference

Common DHCP Option 55 values and their meanings:

| Option | Name | Description |
|--------|------|-------------|
| 1 | Subnet Mask | Network mask |
| 3 | Router | Default gateway |
| 6 | DNS Server | Domain name servers |
| 15 | Domain Name | Domain suffix |
| 28 | Broadcast | Broadcast address |
| 31 | Router Discovery | Perform router discovery |
| 33 | Static Route | Static routing table |
| 43 | Vendor Specific | Vendor-specific options |
| 44 | WINS Server | NetBIOS name servers |
| 46 | NetBIOS Node | NetBIOS node type |
| 47 | NetBIOS Scope | NetBIOS scope ID |
| 119 | Domain Search | DNS search suffixes |
| 121 | Classless Route | Classless static routes |
| 249 | Private | Microsoft classless routes |
| 252 | WPAD | Web proxy auto-discovery |

## Appendix B: JA3 Fingerprint Format

JA3 fingerprint is an MD5 hash of the following comma-separated fields:

```
SSLVersion,Ciphers,Extensions,EllipticCurves,EllipticCurvePointFormats
```

Example:
```
769,47-53-5-10-49161-49162-49171-49172-50-56-19-4,0-10-11,23-24-25,0
```

MD5: `e7d705a3286e19ea42f587b344ee6865`

## Appendix C: File Location Reference

| File | Location | Purpose |
|------|----------|---------|
| User database | `~/Library/Application Support/LanLens/devices.sqlite` | User device data |
| Fingerprint cache | `~/Library/Application Support/LanLens/FingerprintCache/` | API response cache |
| Bundled database | `LanLens.app/Contents/Resources/fingerprints.sqlite` | Read-only fingerprint DB |
