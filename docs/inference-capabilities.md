# LanLens Inference Capabilities

This document describes all the data elements that LanLens can infer, detect, and analyze from network devices.

## Table of Contents

1. [Device Type Inference](#device-type-inference)
2. [Security Posture Assessment](#security-posture-assessment)
3. [Behavior Profile Analysis](#behavior-profile-analysis)
4. [mDNS TXT Record Analysis](#mdns-txt-record-analysis)
5. [Port Banner Analysis](#port-banner-analysis)
6. [MAC Address Analysis](#mac-address-analysis)
7. [Signal Sources and Confidence](#signal-sources-and-confidence)

---

## Device Type Inference

LanLens classifies devices into one of the following categories:

| Device Type | Icon | Examples |
|-------------|------|----------|
| `smartTV` | 📺 | Apple TV, Roku, Chromecast, Smart TVs |
| `speaker` | 🔊 | Sonos, HomePod, Echo, Google Home |
| `camera` | 📷 | Ring, Arlo, Wyze, IP cameras |
| `thermostat` | 🌡️ | Nest, Ecobee |
| `light` | 💡 | Philips Hue, LIFX, Nanoleaf |
| `plug` | 🔌 | WeMo, Kasa, smart outlets |
| `hub` | 🏠 | SmartThings, Home Assistant, bridges |
| `printer` | 🖨️ | HP, Canon, Epson, Brother |
| `nas` | 💾 | Synology, QNAP, TrueNAS |
| `computer` | 💻 | Mac, PC, Linux workstations |
| `phone` | 📱 | iPhone, Android phones |
| `tablet` | 📱 | iPad, Android tablets |
| `router` | 📡 | Network routers, gateways |
| `accessPoint` | 📶 | Wireless access points |
| `appliance` | 🏠 | Smart locks, fans, generic IoT |
| `unknown` | ❓ | Unidentified devices |

### Inference Signal Sources

Device type is inferred by combining signals from multiple sources with weighted confidence:

| Source | Weight | Description |
|--------|--------|-------------|
| `fingerprint` | 0.90 | Fingerbank database lookups |
| `mdnsTXT` | 0.85 | Parsed mDNS TXT records |
| `upnp` | 0.80 | UPnP device descriptions |
| `portBanner` | 0.75 | Service banners (SSH, HTTP, RTSP) |
| `mdns` | 0.70 | mDNS service types |
| `ssdp` | 0.70 | SSDP headers |
| `hostname` | 0.60 | Device hostname patterns |
| `macAnalysis` | 0.60 | MAC address vendor analysis |
| `behavior` | 0.60 | Presence patterns over time |
| `port` | 0.50 | Open port numbers |

---

## Security Posture Assessment

LanLens evaluates the security posture of each device and assigns a risk level.

### Risk Levels

| Level | Numeric | Description |
|-------|---------|-------------|
| `low` | 1 | Minimal security concerns |
| `medium` | 2 | Some security issues present |
| `high` | 3 | Significant vulnerabilities |
| `critical` | 4 | Severe exposure requiring immediate attention |
| `unknown` | 0 | Insufficient data for assessment |

### Risky Port Detection

The following ports are flagged when exposed:

#### Critical Risk Ports
| Port | Service | Risk Description |
|------|---------|------------------|
| 23 | Telnet | Unencrypted remote access with plaintext credentials |
| 1433 | MSSQL | Microsoft SQL Server database exposed |
| 1521 | Oracle | Oracle database listener exposed |
| 3306 | MySQL | MySQL database exposed |
| 6379 | Redis | In-memory database without authentication |
| 27017 | MongoDB | NoSQL database exposed |

#### High Risk Ports
| Port | Service | Risk Description |
|------|---------|------------------|
| 3389 | RDP | Remote Desktop Protocol exposed |
| 5900-5902 | VNC | Virtual Network Computing exposed |

#### Medium Risk Ports
| Port | Service | Risk Description |
|------|---------|------------------|
| 21 | FTP | Unencrypted file transfer |
| 25 | SMTP | Mail server exposed, potential spam relay |
| 110 | POP3 | Unencrypted email retrieval |
| 135 | RPC | Windows RPC endpoint mapper |
| 139 | NetBIOS | Windows file sharing (legacy) |
| 445 | SMB | Windows file sharing, common attack vector |

### Hostname Security Analysis

The following hostname patterns indicate security concerns:

**Default Hostname Patterns** (Medium Risk):
- `router`, `gateway`, `admin`, `default`, `setup`, `wireless`
- Vendor defaults: `linksys`, `netgear`, `tp-link`, `asus`, `dlink`

**Weak Hostname Patterns** (Low Risk):
- `desktop-`, `laptop-`, `android-`, `iphone`, `ipad`
- `galaxy`, `pixel`, `computer`, `device`, `unknown`

### SSH Banner Security Analysis

- SSH Protocol version 1 → **Critical** (deprecated and insecure)
- OpenSSH versions < 7.0 → **High** (known vulnerabilities)
- Dropbear detected → Indicates embedded device

### HTTP Header Security Analysis

- Outdated Apache 1.x → **High** (end-of-life)
- IIS 5/6 → **Critical** (end-of-life with critical vulnerabilities)
- Server version in headers → **Low** (information disclosure)
- X-Powered-By header → **Low** (technology stack disclosure)
- Basic Auth without HTTPS → **Medium** (credentials in cleartext)
- Admin interface without authentication → **Medium**
- Camera interface without authentication → **High**

### Security Posture Data Structure

```swift
struct SecurityPostureData {
    var riskLevel: RiskLevel           // Overall risk classification
    var riskScore: Int                 // Score 0-100 (higher = riskier)
    var riskFactors: [RiskFactor]      // Individual issues identified
    var riskyPorts: [Int]              // Ports contributing to risk
    var hasWebInterface: Bool          // Device has web admin
    var requiresAuthentication: Bool   // Auth required for services
    var usesEncryption: Bool           // Encrypted protocols in use
    var firmwareOutdated: Bool?        // Firmware age indicator
    var assessmentDate: Date           // When assessment was performed
}
```

---

## Behavior Profile Analysis

LanLens tracks device presence patterns over time to classify device behavior.

### Behavior Classifications

| Classification | Expected Uptime | Suggested Device Types |
|----------------|-----------------|------------------------|
| `infrastructure` | 95-100% | Routers, switches, access points |
| `server` | 90-100% | NAS, home servers |
| `iot` | 85-100% | Smart home devices with limited services |
| `workstation` | 30-70% | Desktop computers with daily patterns |
| `portable` | 10-50% | Laptops, tablets |
| `mobile` | 5-30% | Phones with highly intermittent presence |
| `guest` | 0-5% | Devices seen only briefly |

### Pattern Detection

**Daily Pattern Detection**:
- Analyzes peak activity hours (0-23)
- Detects contiguous usage blocks (e.g., 9-17 for work, 18-23 for entertainment)
- Allows up to 2 gaps (morning + evening usage)

**Peak Hour Analysis**:
- Business hours peak (9-17) → Suggests workstation
- Evening peak (18-23) → Suggests entertainment device

### Behavior Profile Data Structure

```swift
struct DeviceBehaviorProfile {
    var classification: BehaviorClassification
    var presenceHistory: [PresenceRecord]  // Up to 100 records
    var averageUptimePercent: Double       // 0-100
    var isAlwaysOn: Bool                   // Infrastructure, server, IoT
    var isIntermittent: Bool               // Portable, mobile, guest
    var hasDailyPattern: Bool              // Regular usage schedule
    var peakHours: [Int]                   // Hours with most activity (0-23)
    var consistentServices: [String]       // Services always available
    var firstObserved: Date
    var lastObserved: Date
    var observationCount: Int
}
```

### Inference Signal Generation

| Behavior | Suggested Type | Confidence |
|----------|---------------|------------|
| Infrastructure | Router | 0.40 |
| Server | NAS | 0.35 |
| IoT (evening peak) | Smart TV | 0.35 |
| IoT (other) | Hub | 0.30 |
| Workstation (business hours) | Computer | 0.35 |
| Workstation (evening) | Smart TV | 0.35 |
| Portable | Computer | 0.30 |
| Mobile | Phone | 0.30 |
| Guest | Phone | 0.25 |

---

## mDNS TXT Record Analysis

LanLens parses TXT records from four major service types.

### AirPlay (`_airplay._tcp`)

**Extracted Data**:
- `model`: Device model identifier (e.g., "AppleTV6,2")
- `deviceId`: Device ID (MAC-based)
- `protocolVersion`: Protocol version
- `sourceVersion`: Software version
- `osBuildVersion`: OS build
- `flags`: Capability bitmask

**Feature Flags Detected**:
- Video, Photo, Slideshow, Screen mirroring
- Audio, Audio redundant, High-resolution audio
- Screen rotation, HUD support
- CarPlay, HomeKit pairing, System pairing
- AirPlay 2 support (buffered audio)
- PTP synchronization, Volume control

**Inference Signals**:
| Model Pattern | Suggested Type | Confidence |
|---------------|---------------|------------|
| `appletv` | Smart TV | 0.95 |
| `homepod`, `audioaccessory` | Speaker | 0.95 |
| `macbook`, `mac`, `imac` | Computer | 0.90 |
| `ipad` | Tablet | 0.90 |
| `iphone` | Phone | 0.90 |
| `airport` | Hub | 0.85 |
| Audio-only device | Speaker | 0.70 |

### Google Cast (`_googlecast._tcp`)

**Extracted Data**:
- `modelName` (md): Device model (e.g., "Chromecast", "Google Home Mini")
- `friendlyName` (fn): User-set device name
- `id`: Unique device identifier
- `firmwareVersion` (ve): Firmware version
- `castVersion` (ca): Chromecast protocol version
- `capabilities`: Capability bitmask
- `isBuiltIn`: Whether Cast is built into a TV
- `supportsGroups`: Multi-room audio support

**Inference Signals**:
| Model Pattern | Suggested Type | Confidence |
|---------------|---------------|------------|
| `chromecast` | Smart TV | 0.95 |
| `google home`, `nest audio/mini` | Speaker | 0.90 |
| `nest hub`, `home hub` | Smart TV | 0.85 |
| Built-in Cast (with model) | Smart TV | 0.85 |
| Built-in Cast (no model) | Smart TV | 0.80 |

### HomeKit (`_hap._tcp`)

**Extracted Data**:
- `category` (ci): HAP category identifier
- `statusFlags` (sf): Pairing status
- `configurationNumber` (c#): Config version
- `featureFlags` (ff): Transport support (IP/BLE)
- `protocolVersion` (pv): HAP version
- `deviceId` (id): Accessory ID
- `modelName` (md): Model description
- `isPaired`: Whether accessory is paired
- `supportsIP`, `supportsBLE`: Transport support

**HomeKit Category Mappings** (36 categories):

| Category | Device Type | Confidence |
|----------|-------------|------------|
| Apple TV (24) | Smart TV | 0.95 |
| HomePod (25) | Speaker | 0.95 |
| IP Camera (17), Video Doorbell (18) | Camera | 0.95 |
| Thermostat (9), Heater (20), AC (21) | Thermostat | 0.95 |
| Lightbulb (5), Switch (8), Outlet (7) | Light | 0.90 |
| Door Lock (6), Garage Opener (4) | Appliance | 0.90 |
| Bridge (2), Wi-Fi Router (33), AirPort (27) | Hub | 0.90 |
| Sensor (10), Programmable Switch (15) | Hub | 0.80 |
| Television (31), Set-Top Box (35), Streaming Stick (36) | Smart TV | 0.95 |
| Speaker (26), Audio Receiver (34) | Speaker | 0.95 |

### RAOP (`_raop._tcp`)

**Extracted Data**:
- `model` (am): Apple model identifier
- `audioFormats` (cn): Supported audio codecs
- `compressionTypes`, `encryptionTypes`: Audio processing
- `metadataTypes`, `transportProtocols`: Protocol details
- `protocolVersion` (vs): RAOP version
- `statusFlags` (sf): Device status
- `supportsLossless`, `supportsHighResolution`: Audio quality

**Inference Signals**:
| Model Pattern | Suggested Type | Confidence |
|---------------|---------------|------------|
| `appletv` | Smart TV | 0.95 |
| `homepod`, `audioaccessory` | Speaker | 0.95 |
| `airport` | Hub | 0.85 |
| `macbook`, `mac`, `imac` | Computer | 0.90 |
| Generic RAOP device | Speaker | 0.60 |

---

## Port Banner Analysis

LanLens probes common ports and parses service banners.

### SSH Banner Analysis (Port 22)

**Parsed Information**:
- `protocolVersion`: SSH protocol version (1.x is critical risk)
- `softwareVersion`: SSH implementation (e.g., "OpenSSH_9.0p1")
- `osHint`: Detected operating system

**OS Detection from SSH Banner**:
| Pattern | OS Hint |
|---------|---------|
| ubuntu, debian, fedora, centos, redhat, linux | Linux |
| freebsd, openbsd, netbsd | FreeBSD |
| dropbear | Embedded |
| apple, macos, darwin | macOS |
| windows, openssh_for_windows | Windows |

**Network Equipment Detection**:
- Cisco, Juniper, MikroTik, Ubiquiti, RouterOS, EdgeOS

**NAS Detection**:
- Synology, QNAP, Drobo, Netgear, ReadyNAS, TerraMaster

**Inference Signals**:
| Detection | Suggested Type | Confidence |
|-----------|---------------|------------|
| macOS | Computer | 0.80 |
| Windows | Computer | 0.75 |
| Linux | Computer | 0.60 |
| Embedded (Dropbear) | Hub | 0.65 |
| FreeBSD | NAS | 0.55 |
| Network equipment keywords | Router | 0.80 |
| NAS vendor keywords | NAS | 0.85 |

### HTTP Header Analysis (Ports 80, 443, 8080, 8443)

**Parsed Headers**:
- `Server`: Web server identification
- `X-Powered-By`: Technology stack
- `WWW-Authenticate`: Authentication method
- `Content-Type`: Response content type

**Device Detection from Server Header**:

| Pattern | Device Type | Confidence |
|---------|-------------|------------|
| Synology, QNAP, DSM, TrueNAS, UnRAID | NAS | 0.95 |
| Printer, CUPS, HP, Canon, Epson, Brother | Printer | 0.90 |
| Hikvision, Dahua, Axis, Foscam, Amcrest, Reolink | Camera | 0.90 |
| MikroTik, OpenWRT, DD-WRT, Tomato, router | Router | 0.80 |
| Home Assistant, OpenHAB, Domoticz, Hubitat | Hub | 0.90 |
| Plex, Emby, Jellyfin | NAS | 0.70 |
| Apache, Nginx, IIS | Computer | 0.50 |

### RTSP Banner Analysis (Port 554)

**Parsed Information**:
- `server`: RTSP server identification
- `methods`: Supported RTSP methods (OPTIONS, DESCRIBE, SETUP, PLAY)
- `contentBase`: Stream base URL
- `requiresAuth`: Whether authentication is needed
- `cameraVendor`: Detected camera brand

**Camera Vendor Detection**:
- Hikvision, Dahua, Axis, Foscam, Amcrest, Reolink
- Vivotek, GeoVision, Ubiquiti/UniFi, Hanwha/Samsung

**Inference Signals**:
| Detection | Suggested Type | Confidence |
|-----------|---------------|------------|
| Known camera vendor | Camera | 0.95 |
| DESCRIBE/PLAY/SETUP support | Camera | 0.85 |
| RTSP without streaming methods | Smart TV | 0.50 |

---

## MAC Address Analysis

LanLens extracts insights from MAC addresses.

### Analyzed Properties

- **OUI**: First 3 bytes identifying the vendor
- **Vendor**: Manufacturer name from OUI lookup
- **Locally Administered**: Bit 1 of first byte set
- **Randomized**: Locally administered + not multicast (iOS 14+, Android 10+)
- **Virtual Machine**: Known VM OUI ranges

### Virtual Machine OUI Detection

| OUI Prefix | Vendor |
|------------|--------|
| 00:0C:29, 00:50:56 | VMware |
| 00:1C:42 | Parallels |
| 00:03:FF | Microsoft Hyper-V |
| 08:00:27 | VirtualBox |
| 52:54:00 | QEMU/KVM |
| 00:16:3E | Xen |

### Vendor Confidence Levels

| Level | Description | Examples |
|-------|-------------|----------|
| `high` | Major well-known brands | Apple, Samsung, Google, Amazon, Cisco |
| `medium` | Recognized brands | TP-Link, D-Link, Sonos, Nest, Ring |
| `low` | Known vendor but less common | Various smaller manufacturers |
| `randomized` | Detected as randomized MAC | Mobile device privacy feature |
| `unknown` | No vendor information | Unknown OUI |

### OUI Age Estimation

| Era | Examples |
|-----|----------|
| `legacy` (pre-2010) | 3Com, DEC, Compaq, Novell |
| `established` (2010-2015) | Cisco, HP, Dell, Netgear, Linksys |
| `modern` (2015-2020) | Ubiquiti, Ring, Nest, LIFX |
| `recent` (2020+) | Wyze, Eufy, Meross, Govee, SwitchBot |

### Vendor Device Category Mappings

| Vendor | Typical Devices |
|--------|-----------------|
| Apple | Phone, Tablet, Computer, Smart TV, Speaker, AP |
| Samsung | Phone, Tablet, Smart TV, Appliance |
| Google/Nest | Phone, Smart TV, Speaker, Thermostat, Camera, Hub |
| Amazon | Speaker, Smart TV, Tablet, Hub |
| Ring | Camera |
| Sonos | Speaker |
| Roku | Smart TV |
| Philips Hue | Light, Hub |
| Synology, QNAP | NAS |
| Ubiquiti | Router, AP, Camera |
| Espressif, Tuya | Plug, Light, Appliance (IoT chips) |

### Vendor Specializations

Some vendors exclusively produce one device type:
- Sonos → Speaker
- Roku → Smart TV
- Ecobee → Thermostat
- Ring, Arlo → Camera
- Synology, QNAP → NAS
- LIFX, Nanoleaf, Yeelight → Light

### Inference Signals

| Detection | Suggested Type | Confidence |
|-----------|---------------|------------|
| Randomized MAC | Phone | 0.60 |
| VM OUI | Computer | 0.85 |
| Legacy OUI | Router | 0.40 |
| Specialized vendor (high confidence) | Varies | 0.70 |
| Specialized vendor (medium confidence) | Varies | 0.55 |
| Single-category vendor | Varies | 0.65 |

---

## Signal Sources and Confidence

### Overall Inference Process

1. **Collect Signals**: Gather signals from all available sources
2. **Apply Weights**: Each signal is weighted by source reliability
3. **Aggregate Scores**: Sum weighted confidence per device type
4. **Select Best Match**: Return type with highest aggregated score

### Confidence Calculation

```
Weighted Confidence = Signal Confidence × Source Weight

Type Score = Σ (Weighted Confidence for all signals suggesting this type)

Final Type = Type with highest Score
```

### Enhanced Inference

When using `inferTypeWithEnhancedData`:
1. Combines traditional signals with enhanced analyzers
2. Adds signals from mDNS TXT, Port Banners, and MAC Analysis
3. Returns both device type and normalized confidence (0.0-1.0)

### Data Persistence

- **Behavior Profiles**: Persisted to `~/Library/Application Support/LanLens/behavior_profiles.json`
- **Fingerprint Cache**: Cached with TTL (Time-To-Live)
- **LRU Eviction**: Maximum 1000 behavior profiles retained

### Privacy Features

- Optional device ID hashing (SHA256 with salt)
- MAC address randomization detection
- Local-only data storage (no cloud transmission)
