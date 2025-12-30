# LanLens - Current Status

## Overview

LanLens is a native macOS CLI application written in Swift that discovers and identifies "smart" devices on a local network. It's designed to run on a Mac Mini as a background service, exposing a REST API for a future iOS companion app.

## Architecture

```
LanLens/
├── Package.swift                    # Swift Package Manager config
├── Sources/
│   └── LanLens/
│       ├── App/
│       │   └── main.swift           # CLI entry point
│       └── Core/
│           ├── API/
│           │   └── APIServer.swift  # Hummingbird REST API
│           ├── Discovery/
│           │   ├── ARPScanner.swift      # ARP table reading
│           │   ├── MDNSListener.swift    # NWBrowser-based mDNS
│           │   ├── DNSSDScanner.swift    # dns-sd command-based discovery
│           │   ├── SSDPListener.swift    # UPnP/SSDP discovery
│           │   ├── PortScanner.swift     # nmap/socket port scanning
│           │   └── DiscoveryManager.swift # Orchestrates all discovery
│           ├── Models/
│           │   └── Device.swift     # Device, Port, Service models
│           ├── Utilities/
│           │   ├── ShellExecutor.swift   # Shell command runner
│           │   ├── ToolChecker.swift     # External tool availability
│           │   └── MACVendorLookup.swift # MAC OUI vendor database
│           └── LanLensCore.swift    # Public API exports
└── Tests/
    └── LanLensTests/
        └── LanLensTests.swift       # Unit tests
```

## Dependencies

- **SQLite.swift** (0.15.0) - For future persistence
- **Hummingbird** (2.0.0) - REST API framework

## Completed Features

### 1. MAC Vendor Database
- ~500 OUI prefixes covering major vendors
- Apple, Ubiquiti, Sonos, Google/Nest, Amazon/Ring, Samsung, LG, Sony, Roku, Philips Hue, Espressif (ESP8266/ESP32), Tuya, TP-Link, Xiaomi, Raspberry Pi, and many more
- Handles various MAC formats (with/without colons, single-digit hex)

### 2. ARP Table Scanner
- Reads `/usr/sbin/arp` output to get current network devices
- Extracts IP, MAC, and interface information
- Supports active subnet scanning via ping sweep

### 3. Passive Discovery
- **mDNS/Bonjour** via Network.framework NWBrowser
- **SSDP/UPnP** via UDP multicast listener
- **dns-sd command** for more reliable mDNS discovery
- Monitors 28+ service types (HomeKit, AirPlay, Google Cast, MQTT, etc.)

### 4. Port Scanning
- **nmap integration** when available (service/version detection)
- **Socket-based fallback** when nmap not installed
- 28 common smart device ports
- Quick scan mode (10 key ports)
- Smart signal detection from open ports

### 5. Smart Device Classification
- Scoring system (0-100) based on signals:
  - mDNS service types (+10-30 points)
  - SSDP/UPnP responses (+10-25 points)
  - Open ports (+5-30 points)
  - Vendor identification
- Device type inference (camera, speaker, TV, hub, thermostat, etc.)

### 6. REST API Server
- Built with Hummingbird 2.0
- Optional token authentication
- Endpoints:
  - `GET /health` - Health check
  - `GET /api/devices` - List all devices
  - `GET /api/devices/smart` - List smart devices only
  - `GET /api/devices/:mac` - Get device by MAC
  - `GET /api/discover/arp` - Read ARP table
  - `POST /api/discover/passive` - Run passive discovery
  - `POST /api/discover/dnssd` - Run dns-sd discovery
  - `POST /api/scan/ports/:mac` - Scan ports for device
  - `POST /api/scan/quick` - Quick scan all devices
  - `POST /api/scan/full` - Full scan all devices
  - `GET /api/scan/nmap-status` - Check nmap availability
  - `GET /api/tools` - Check tool status

### 7. CLI Interface
```bash
# Run one-time discovery scan
lanlens

# Start REST API server
lanlens --serve
lanlens -s --port 3000 --host 0.0.0.0 --token mysecret

# Show help
lanlens --help
```

## External Tools

| Tool | Required | Purpose | Install |
|------|----------|---------|---------|
| arp | Yes | ARP table reading | Built-in macOS |
| dns-sd | Yes | mDNS discovery | Built-in macOS |
| nmap | No | Port scanning with service detection | `brew install nmap` |
| arp-scan | No | Faster ARP scanning | `brew install arp-scan` |

## Build & Run

```bash
# Build
swift build

# Run discovery scan
swift run lanlens

# Run API server
swift run lanlens --serve

# Run tests
swift test
```

## Current Test Coverage

- MAC vendor lookup (exact match)
- MAC vendor lookup (unknown OUI returns nil)

## Last Updated

2025-12-29
