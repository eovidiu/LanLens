# LanLens

A macOS menu bar application for discovering and identifying devices on your local network.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- **Network Discovery** - Automatically discovers devices using ARP, mDNS, SSDP, and DNS-SD protocols
- **Device Fingerprinting** - Identifies device types, manufacturers, and models via UPnP and Fingerbank
- **Port Scanning** - Detects open ports and running services
- **Smart Classification** - Categorizes devices as smart TVs, speakers, cameras, thermostats, etc.
- **Menu Bar Interface** - Quick access from your menu bar with a clean, native macOS design
- **REST API** - Optional local API server for integration with other tools

## Screenshots

| Main View | Device Detail | Settings |
|-----------|---------------|----------|
| ![Main](docs/mockups/menubar_main.png) | ![Detail](docs/mockups/device_detail.png) | ![Settings](docs/mockups/settings_panel.png) |

## Installation

### Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15+ (for building from source)

### Building from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/eovidiu/LanLens.git
   cd LanLens
   ```

2. Build the Swift package:
   ```bash
   swift build
   ```

3. Build and run the macOS app:
   ```bash
   cd LanLensApp
   open LanLensApp.xcodeproj
   ```
   Then build and run in Xcode (⌘R).

## Usage

### Basic Scanning

1. Click the LanLens icon in your menu bar
2. The app automatically discovers devices on your network
3. Click any device to see detailed information

### Device Fingerprinting

LanLens uses two levels of device identification:

| Level | Method | Requirements |
|-------|--------|--------------|
| 1 | UPnP Device Description | None (automatic) |
| 2 | Fingerbank API | Free API key from [fingerbank.org](https://fingerbank.org) |

To enable Level 2 fingerprinting:
1. Get a free API key from [fingerbank.org](https://fingerbank.org)
2. Open Settings in LanLens
3. Enable Fingerbank and enter your API key

### REST API

LanLens includes an optional REST API server for integration:

1. Open Settings
2. Enable "API Server"
3. Configure port and authentication
4. Access the API at `http://localhost:8080/api/devices`

## Project Structure

```
LanLens/
├── Sources/LanLens/
│   ├── Core/                    # LanLensCore library
│   │   ├── Discovery/           # Network discovery (ARP, mDNS, SSDP)
│   │   ├── Fingerprinting/      # Device identification
│   │   ├── Models/              # Data models
│   │   ├── API/                 # REST API server
│   │   └── Utilities/           # MAC vendor lookup, etc.
│   ├── App/                     # CLI application
│   └── MenuBarApp/              # Menu bar app (SPM version)
├── LanLensApp/                  # Xcode project for macOS app
│   └── LanLensApp/
│       ├── Views/               # SwiftUI views
│       ├── State/               # App state management
│       └── Services/            # Background services
├── Tests/                       # Unit tests
└── docs/                        # Documentation
```

## Privacy

- **Local-only by default**: All scanning happens on your local network
- **No data collection**: LanLens doesn't send any data to external servers (except Fingerbank if enabled)
- **Fingerbank is opt-in**: MAC addresses are only sent to Fingerbank if you explicitly enable it and provide an API key

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Fingerbank](https://fingerbank.org) for device fingerprinting database
- [Hummingbird](https://github.com/hummingbird-project/hummingbird) for the Swift HTTP server
- [SQLite.swift](https://github.com/stephencelis/SQLite.swift) for database support
