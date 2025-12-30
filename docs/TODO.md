# LanLens - Remaining Work

## High Priority

### 1. Persistence Layer (SQLite)
- [ ] Create database schema for devices, services, ports, history
- [ ] Implement DeviceStore actor for CRUD operations
- [ ] Store device first/last seen timestamps
- [ ] Track device online/offline history
- [ ] Persist smart scores and signals

### 2. Menu Bar App Shell
- [ ] Create SwiftUI menu bar application
- [ ] System tray icon with status indicator
- [ ] Quick device list in dropdown
- [ ] Start/stop API server controls
- [ ] Settings panel (port, token, scan intervals)
- [ ] Launch at login option

### 3. Background Scanning
- [ ] Scheduled ARP table refresh (configurable interval)
- [ ] Periodic passive discovery
- [ ] Device online/offline detection
- [ ] Notifications for new devices

## Medium Priority

### 4. Enhanced Device Detection
- [ ] HTTP endpoint probing (fetch device info pages)
- [ ] UPnP device description fetching
- [ ] SNMP discovery (for network equipment)
- [ ] NetBIOS name resolution
- [ ] Hostname resolution via reverse DNS

### 5. VLAN/Multi-Subnet Support
- [ ] Configure multiple subnets to scan
- [ ] Interface selection for scanning
- [ ] Cross-VLAN discovery (requires routing)

### 6. Improved Smart Classification
- [ ] Machine learning model for device classification
- [ ] User feedback loop (confirm/correct device types)
- [ ] Community-contributed device signatures
- [ ] Fingerprinting based on open port combinations

### 7. API Enhancements
- [ ] WebSocket support for real-time updates
- [ ] Device grouping/tagging
- [ ] Search/filter endpoints
- [ ] Export to JSON/CSV
- [ ] Rate limiting

## Low Priority

### 8. iOS Companion App
- [ ] SwiftUI iOS app
- [ ] Server discovery (Bonjour)
- [ ] Device list with smart device highlighting
- [ ] Device detail view with ports/services
- [ ] Push notifications for new devices
- [ ] Widget for device count

### 9. Security Features
- [ ] HTTPS support for API
- [ ] JWT authentication option
- [ ] API key rotation
- [ ] Audit logging

### 10. Network Traffic Analysis
- [ ] Integrate with packet capture (requires root)
- [ ] Track outbound connections per device
- [ ] Identify "phone home" behavior
- [ ] DNS query logging
- [ ] Bandwidth usage per device

### 11. Integration Options
- [ ] Home Assistant integration
- [ ] UniFi controller API (optional)
- [ ] Prometheus metrics endpoint
- [ ] Webhook notifications
- [ ] MQTT publishing

## Technical Debt

### Code Quality
- [ ] Fix Swift 6 concurrency warnings in MDNSListener
- [ ] Fix unreachable catch block in SSDPListener
- [ ] Add more comprehensive unit tests
- [ ] Integration tests for API endpoints
- [ ] Documentation comments for public APIs

### Performance
- [ ] Connection pooling for port scanning
- [ ] Batch ARP lookups
- [ ] Cache DNS resolutions
- [ ] Optimize MAC vendor lookup (trie structure)

## Notes

### User Preferences (from initial discussion)
- Native Swift for Mac
- Menu bar app (minimal UI)
- Passive by default, active scan on demand
- Multi-VLAN support with configurable subnets
- Some history (not full logging)
- Shell out to system tools (don't auto-install)
- Simple token authentication
- App name: "LanLens"

### Architecture Decisions Made
- Actor-based concurrency for thread safety
- Hummingbird for REST API (lightweight, Swift-native)
- SQLite for persistence (via SQLite.swift)
- Command-line tool with API server mode
- Modular discovery (each method in separate file)
