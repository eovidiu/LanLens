# Changelog

All notable changes to LanLens will be documented in this file.

## [1.2.0] - 2026-01-02

### Added
- **Offline Fingerprint Database**: Bundled OUI database for vendor identification without internet
- **DHCP Fingerprinting**: Bundled database of DHCP Option 55 fingerprints for device type identification
- **TLS/JA3S Fingerprinting**: Active TLS probing during deep scan to identify server software via JA3S hashes
- **Fingerprinting UI Card**: New device detail section showing fingerprint information
- **Multiple Fingerprint Sources**: Extended `FingerprintSource` enum with `dhcpFingerprint` and `tlsFingerprint` cases

### Technical
- Added `BundledDatabaseManager` actor for offline fingerprint database queries
- Added `DHCPOption55Parser`, `DHCPFingerprintDatabase`, `DHCPFingerprintMatcher` for DHCP fingerprinting
- Added `TLSHandshakeParser`, `TLSFingerprintDatabase`, `TLSFingerprintMatcher`, `TLSFingerprintProber` for TLS fingerprinting
- TLS probing integrated into deep scan workflow

### Documentation
- Updated device-fingerprinting.md with new fingerprinting levels (2-4)
- Marked fingerprint-enhancements specification as Implemented
- Updated fingerprint-enhancements-checklist with completion status

## [1.1.0] - 2026-01-02

### Added
- **Deep Scan Stop Button**: Cancel long-running port scans with a stop button or Escape key
- **Friendly Service Names**: mDNS services now display user-friendly names (e.g., "AirPlay" instead of cryptic identifiers)
- **Service Deduplication**: Services are now deduplicated by display name for cleaner presentation
- **Clear Data Confirmation**: New popover-based confirmation dialog for clearing device data

### Fixed
- **Multicast IP Filtering**: Properly filters out multicast addresses (224.x.x.x, 239.x.x.x) from device list
- **DNS-SD Hostname Resolution**: Improved hostname discovery from mDNS/DNS-SD services
- **Menu Bar Window Behavior**: Clear data confirmation no longer dismisses the entire menu bar window
- **Toggle Alignment**: Settings toggles now properly align to the right

### Improved
- **Defense-in-depth**: Added IP validation at multiple layers (DeviceStore) to prevent invalid devices
- **Scan Cancellation**: Deep scans now support proper Task cancellation with checkpoints
- **Service Display**: MAC address prefixes stripped from service names for cleaner display

## [1.0.0] - Initial Release

### Features
- Network device discovery via ARP scanning
- mDNS/Bonjour service discovery
- SSDP/UPnP device detection
- Port scanning with banner grabbing
- Fingerbank API integration for device identification
- Smart device type inference
- Device persistence with SQLite
- WebSocket API for real-time updates
- Export to JSON/CSV
- macOS menu bar app with native dark theme
