# Fingerprint Enhancements Implementation Checklist

**Version:** 1.0  
**Date:** January 2, 2026  
**Status:** Planning  
**Specification:** [fingerprint-enhancements.md](./fingerprint-enhancements.md)

---

## Implementation Overview

This checklist tracks implementation progress for the Fingerprint Enhancements feature set:

1. **Phase 1**: Offline Fingerbank Cache (Foundation)
2. **Phase 2**: Local DHCP Fingerprint Database
3. **Phase 3**: JA3/JA4 TLS Fingerprinting

---

## Phase Dependencies

```
Phase 1: Offline Fingerbank Cache
    |
    +---> Phase 2: DHCP Fingerprinting (depends on bundled DB infrastructure)
    |
    +---> Phase 3: TLS Fingerprinting (depends on bundled DB infrastructure)
```

Phase 1 MUST be completed before Phases 2 and 3.
Phases 2 and 3 MAY be implemented in parallel after Phase 1.

---

## Phase 1: Offline Fingerbank Cache

**Goal:** Enable device identification without internet access using bundled database

### 1.1 Bundled Database Infrastructure

- [ ] **1.1.1** Create `BundledDatabaseManager` actor
  - File: `Sources/LanLensCore/Fingerprinting/BundledDatabaseManager.swift`
  - Protocol: `BundledDatabaseManagerProtocol`
  - Dependencies: GRDB
  
- [ ] **1.1.2** Define bundled database schema
  - File: `Resources/fingerprints-schema.sql`
  - Tables: `devices`, `dhcp_fingerprints`, `ja3_fingerprints`, `oui_mappings`
  
- [ ] **1.1.3** Create database initialization logic
  - Load from app bundle at startup
  - Handle missing/corrupt database gracefully
  - Log database version and entry count
  
- [ ] **1.1.4** Implement query methods
  - `queryByOUI(_ oui: String) async -> FingerprintDatabaseEntry?`
  - `queryByDHCPHash(_ hash: String) async -> FingerprintDatabaseEntry?`
  - `queryByJA3Hash(_ hash: String) async -> (device: FingerprintDatabaseEntry?, application: String?)`

### 1.2 Database Generation

- [ ] **1.2.1** Create database generation script
  - File: `scripts/generate-fingerprint-db.py`
  - Input: Fingerbank open-source data
  - Output: `fingerprints.sqlite`
  
- [ ] **1.2.2** Download and process Fingerbank data
  - Source: https://github.com/fingerbank/fingerbank
  - Extract top 100,000 device entries
  - Map DHCP fingerprints to device IDs
  
- [ ] **1.2.3** Add OUI to device mappings
  - Map MAC OUI prefixes to most common device types
  - Include vendor names from IEEE OUI database
  
- [ ] **1.2.4** Generate and verify database
  - Run generation script
  - Verify entry counts
  - Test query performance (<10ms target)

### 1.3 FingerprintLookupService

- [ ] **1.3.1** Create `FingerprintLookupService` actor
  - File: `Sources/LanLensCore/Fingerprinting/FingerprintLookupService.swift`
  - Protocol: `FingerprintLookupServiceProtocol`
  
- [ ] **1.3.2** Implement lookup ordering
  1. Check cache (existing `FingerprintCacheManager`)
  2. Check bundled database by DHCP hash
  3. Check bundled database by OUI
  4. Query Fingerbank API (if enabled)
  
- [ ] **1.3.3** Return source information
  - Add `source` field to results
  - Support sources: cache, localDHCP, localOUI, fingerbankAPI, none
  
- [ ] **1.3.4** Integrate with `DeviceFingerprintManager`
  - Update existing manager to use new lookup service
  - Maintain backward compatibility

### 1.4 Cache Enhancements

- [ ] **1.4.1** Increase cache TTL to 30 days
  - Update `FingerprintCacheManager` default TTL
  - Make TTL configurable via Settings
  
- [ ] **1.4.2** Add cache statistics to API
  - Implement `GET /api/fingerprints/stats` endpoint
  - Include cache hit rate, age distribution

### 1.5 Testing

- [ ] **1.5.1** Unit tests for `BundledDatabaseManager`
  - Test database loading
  - Test query methods
  - Test missing database handling
  
- [ ] **1.5.2** Unit tests for `FingerprintLookupService`
  - Test lookup ordering
  - Test fallback behavior
  - Test source attribution
  
- [ ] **1.5.3** Integration tests
  - Test offline operation
  - Test database migration
  
- [ ] **1.5.4** Performance tests
  - Verify <10ms query time
  - Verify <500ms startup time

### 1.6 Documentation

- [ ] **1.6.1** Update `device-fingerprinting.md`
  - Add bundled database section
  - Document offline capabilities
  
- [ ] **1.6.2** Update `ARCHITECTURE.md`
  - Add ADR-007 for bundled database
  - Update data flow diagram
  
- [ ] **1.6.3** Update README.md
  - Add offline fingerprinting feature
  - Update feature list

---

## Phase 2: Local DHCP Fingerprint Database

**Goal:** Capture and identify devices via DHCP Option 55 fingerprints

### 2.1 DHCP Packet Capture

- [ ] **2.1.1** Create `PacketCaptureService` actor
  - File: `Sources/LanLensCore/Discovery/PacketCaptureService.swift`
  - Protocol: `PacketCaptureServiceProtocol`
  
- [ ] **2.1.2** Implement BPF-based DHCP capture
  - Open `/dev/bpf` device
  - Set filter for DHCP packets (port 67/68)
  - Handle permissions gracefully
  
- [ ] **2.1.3** Parse DHCP packets
  - Extract Option 55 (Parameter Request List)
  - Normalize to sorted comma-separated string
  - Compute SHA256 hash
  
- [ ] **2.1.4** Handle capture states
  - Implement state machine (Disabled, Starting, Running, Stopping)
  - Handle permission errors gracefully
  
- [ ] **2.1.5** Add Settings toggle
  - "Enable DHCP Fingerprint Capture" (default: off)
  - Permission request flow

### 2.2 DHCP Fingerprint Storage

- [ ] **2.2.1** Database migration v5
  - Add `dhcp_fingerprint_hash` to devices table
  - Add `dhcp_fingerprint_string` to devices table
  - Add `dhcp_captured_at` to devices table
  
- [ ] **2.2.2** Create `CapturedFingerprintRepository`
  - File: `Sources/LanLensCore/Persistence/CapturedFingerprintRepository.swift`
  - CRUD operations for captured fingerprints
  
- [ ] **2.2.3** Integrate with `DiscoveryManager`
  - Associate captured DHCP fingerprints with devices by MAC
  - Trigger re-inference on new fingerprint

### 2.3 DHCP Fingerprint Lookup

- [ ] **2.3.1** Add DHCP fingerprint to bundled database
  - Include ~50,000 DHCP fingerprint entries
  - Map to Fingerbank device IDs
  
- [ ] **2.3.2** Update `FingerprintLookupService`
  - Add DHCP hash lookup step
  - Set confidence to 0.85
  
- [ ] **2.3.3** Update `DeviceTypeInferenceEngine`
  - Add DHCP fingerprint as signal source
  - Weight: 0.85 (between Fingerbank API and UPnP)

### 2.4 Testing

- [ ] **2.4.1** Unit tests for DHCP parsing
  - Test Option 55 extraction
  - Test normalization
  - Test hash computation
  
- [ ] **2.4.2** Unit tests for `PacketCaptureService`
  - Test state machine
  - Test permission handling
  
- [ ] **2.4.3** Integration tests
  - Test end-to-end capture flow
  - Test database storage

### 2.5 Documentation

- [ ] **2.5.1** Update `device-fingerprinting.md`
  - Add DHCP fingerprinting section
  - Document capture requirements
  
- [ ] **2.5.2** Update `SPECIFICATION.md`
  - Add DHCP capture to feature inventory
  - Update security considerations

---

## Phase 3: JA3/JA4 TLS Fingerprinting

**Goal:** Identify devices and applications via TLS Client Hello fingerprints

### 3.1 TLS Packet Capture

- [ ] **3.1.1** Extend `PacketCaptureService` for TLS
  - Add TLS capture methods
  - Filter for TCP port 443 + TLS handshake
  
- [ ] **3.1.2** Implement TLS Client Hello parsing
  - Extract TLS version, cipher suites, extensions
  - Extract elliptic curves, EC point formats
  - Extract SNI (Server Name Indication)
  
- [ ] **3.1.3** Compute JA3 hash
  - Concatenate fields per JA3 specification
  - Compute MD5 hash
  - Validate against reference implementation
  
- [ ] **3.1.4** Compute JA4 hash (optional)
  - Implement JA4 algorithm
  - Store alongside JA3
  
- [ ] **3.1.5** Handle TLS 1.3 specifics
  - Parse encrypted extensions where possible
  - Handle Encrypted Client Hello (ECH)

### 3.2 TLS Fingerprint Storage

- [ ] **3.2.1** Database migration v5 (continued)
  - Create `tls_fingerprints` table
  - Indexes on mac, ja3_hash, captured_at
  
- [ ] **3.2.2** Extend `CapturedFingerprintRepository`
  - Add TLS fingerprint CRUD operations
  - Implement 90-day retention cleanup
  
- [ ] **3.2.3** Integrate with `DiscoveryManager`
  - Associate TLS fingerprints with devices
  - Track most common JA3 per device

### 3.3 JA3 Database

- [ ] **3.3.1** Source JA3 database
  - Use public JA3 fingerprint repositories
  - Map hashes to applications and devices
  
- [ ] **3.3.2** Add JA3 to bundled database
  - Include ~100,000 JA3 entries
  - Include application names (Chrome, curl, etc.)
  
- [ ] **3.3.3** Update `FingerprintLookupService`
  - Add JA3 hash lookup step
  - Return both device and application info
  - Set confidence to 0.80

### 3.4 UI Integration

- [ ] **3.4.1** Add TLS fingerprints to device detail
  - Show most common JA3/JA4 hashes
  - Show matched applications
  - Show common destinations (SNI)
  
- [ ] **3.4.2** Add Settings controls
  - "Enable TLS Fingerprint Capture" (default: off)
  - "TLS Data Retention Period" (default: 90 days)

### 3.5 Testing

- [ ] **3.5.1** Unit tests for TLS parsing
  - Test Client Hello extraction
  - Test JA3 computation
  - Test JA4 computation
  
- [ ] **3.5.2** Integration tests
  - Test end-to-end TLS capture
  - Test database storage
  - Test retention cleanup

### 3.6 Documentation

- [ ] **3.6.1** Update `device-fingerprinting.md`
  - Add TLS fingerprinting section
  - Document JA3/JA4 format
  
- [ ] **3.6.2** Update `ARCHITECTURE.md`
  - Add ADR-008 for JA3
  - Add ADR-009 for BPF

---

## API & Integration Updates

### API Endpoints

- [ ] **API-001** `GET /api/fingerprints/stats`
  - Implement endpoint
  - Add to `APIServer.swift`
  
- [ ] **API-002** `GET /api/devices/:mac/fingerprints`
  - Implement endpoint
  - Return all fingerprint data for device
  
- [ ] **API-003** Update `GET /api/devices` response
  - Include fingerprint sources
  - Include DHCP/TLS data if captured

### WebSocket Events

- [ ] **WS-001** Add `fingerprintCaptured` event
  - Broadcast when new fingerprint captured
  - Include mac, type (dhcp/tls), match info
  
- [ ] **WS-002** Add `fingerprintMatched` event
  - Broadcast when fingerprint matches device
  - Include device identification

---

## Database Migrations

### Migration v5 Summary

```sql
-- DHCP fingerprint fields on devices table
ALTER TABLE devices ADD COLUMN dhcp_fingerprint_hash TEXT;
ALTER TABLE devices ADD COLUMN dhcp_fingerprint_string TEXT;
ALTER TABLE devices ADD COLUMN dhcp_captured_at DATETIME;

-- TLS fingerprints table
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

- [ ] **DB-001** Create migration v5 in `Database.swift`
- [ ] **DB-002** Test migration from v4 to v5
- [ ] **DB-003** Test fresh install with v5 schema

---

## Quality Gates

### Phase 1 Completion Criteria

- [ ] Bundled database loads in <500ms
- [ ] OUI lookup returns results in <10ms
- [ ] Offline mode works without internet
- [ ] All unit tests pass
- [ ] Documentation updated

### Phase 2 Completion Criteria

- [ ] DHCP packets captured on test network
- [ ] Option 55 correctly parsed and stored
- [ ] DHCP lookup improves device identification
- [ ] Settings toggle works correctly
- [ ] All unit tests pass
- [ ] Documentation updated

### Phase 3 Completion Criteria

- [ ] TLS Client Hello captured on test network
- [ ] JA3 hash matches reference implementation
- [ ] JA3 lookup identifies applications
- [ ] 90-day retention cleanup works
- [ ] Settings toggles work correctly
- [ ] All unit tests pass
- [ ] Documentation updated

---

## Risk Register

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| BPF permissions not available in App Store | High | High | Document alternative distribution methods |
| Bundled database too large | Medium | Medium | Compress, use top entries only |
| DHCP capture misses packets | Medium | Low | Document limitations, use as supplement |
| JA3 database outdated quickly | High | Medium | Regular updates, focus on common apps |
| TLS 1.3 ECH reduces effectiveness | Medium | Medium | Document limitations, use other signals |

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-02 | System Specification Curator | Initial checklist |
