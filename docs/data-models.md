# LanLens Data Models Reference

This document provides a complete reference for all data structures used in the LanLens inference system.

## Core Models

### Device

The primary model representing a network device.

```swift
struct Device {
    let mac: String                          // MAC address (primary identifier)
    var ip: String                           // Current IP address
    var hostname: String?                    // mDNS/DNS hostname
    var vendor: String?                      // OUI vendor lookup
    var firstSeen: Date                      // Discovery timestamp
    var lastSeen: Date                       // Most recent observation
    var isOnline: Bool                       // Current presence status
    var smartScore: Int                      // Intelligence score (0-100)
    var deviceType: DeviceType               // Inferred device category

    // Enhanced inference data
    var fingerprint: DeviceFingerprint?      // Detailed fingerprint
    var securityPosture: SecurityPostureData? // Security assessment
    var behaviorProfile: DeviceBehaviorProfile? // Behavior patterns
    var mdnsTXTRecords: MDNSTXTData?         // Parsed mDNS TXT
    var portBanners: PortBannerData?         // Service banners

    var userLabel: String?                   // User-assigned name
}
```

### DeviceType

Enumeration of supported device categories.

```swift
enum DeviceType: String, CaseIterable {
    case smartTV
    case speaker
    case camera
    case thermostat
    case light
    case plug
    case hub
    case printer
    case nas
    case computer
    case phone
    case tablet
    case router
    case accessPoint
    case appliance
    case unknown
}
```

---

## Security Models

### SecurityPostureData

Complete security assessment for a device.

```swift
struct SecurityPostureData: Codable, Sendable {
    var riskLevel: RiskLevel = .unknown
    var riskScore: Int = 0                   // 0-100 (higher = riskier)
    var riskFactors: [RiskFactor] = []
    var riskyPorts: [Int] = []
    var hasWebInterface: Bool = false
    var requiresAuthentication: Bool = true
    var usesEncryption: Bool = false
    var firmwareOutdated: Bool?
    var assessmentDate: Date = Date()
}
```

### RiskLevel

```swift
enum RiskLevel: Int, Codable, Sendable, CaseIterable {
    case unknown = 0
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4

    var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }
}
```

### RiskFactor

Individual security concern.

```swift
struct RiskFactor: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    let description: String          // Human-readable description
    let severity: RiskLevel          // How serious this issue is
    let port: Int?                   // Related port (if applicable)
    let recommendation: String?      // Suggested remediation
}
```

---

## Behavior Models

### DeviceBehaviorProfile

Accumulated behavior observations for a device.

```swift
struct DeviceBehaviorProfile: Codable, Sendable {
    var classification: BehaviorClassification = .unknown
    var presenceHistory: [PresenceRecord] = []  // Max 100 records
    var averageUptimePercent: Double = 0.0
    var isAlwaysOn: Bool = false
    var isIntermittent: Bool = false
    var hasDailyPattern: Bool = false
    var peakHours: [Int] = []                   // 0-23
    var consistentServices: [String] = []
    var firstObserved: Date
    var lastObserved: Date
    var observationCount: Int = 0
}
```

### BehaviorClassification

```swift
enum BehaviorClassification: String, Codable, Sendable, CaseIterable {
    case unknown        // Insufficient data
    case infrastructure // 95%+ uptime (routers, APs)
    case server         // 85-95% uptime with services
    case iot            // High uptime, limited services
    case workstation    // 50-85% with daily pattern
    case portable       // 20-50% uptime
    case mobile         // 5-20% uptime
    case guest          // <5% uptime
}
```

### PresenceRecord

Single presence observation.

```swift
struct PresenceRecord: Codable, Sendable {
    let timestamp: Date
    let isOnline: Bool
    let availableServices: [String]
    let ipAddress: String?
}
```

---

## mDNS TXT Models

### MDNSTXTData

Container for all parsed mDNS TXT record data.

```swift
struct MDNSTXTData: Codable, Sendable {
    var airplay: AirPlayTXTData?
    var googleCast: GoogleCastTXTData?
    var homeKit: HomeKitTXTData?
    var raop: RAOPTXTData?
    var rawRecords: [String: [String: String]] = [:]

    // Storage limits: 8 service types, 32 keys per service, 256 chars per value
}
```

### AirPlayTXTData

```swift
struct AirPlayTXTData: Codable, Sendable {
    var model: String?               // e.g., "AppleTV6,2"
    var deviceId: String?
    var sourceVersion: String?
    var protocolVersion: String?
    var osBuildVersion: String?
    var flags: UInt64?
    var features: Set<AirPlayFeature> = []
    var supportsAirPlay2: Bool = false
    var supportsScreenMirroring: Bool = false
    var isAudioOnly: Bool = false
}
```

### AirPlayFeature

```swift
enum AirPlayFeature: String, Codable, Sendable {
    case video, photo, slideshow, screen, screenRotate
    case audio, audioRedundant, ftpDataChunkedSend
    case authentication, metadataFeatures, audioFormat
    case playbackQueue, hudSupported, mfiCert, carPlay
    case supportsUnifiedMediaControl, supportsBufferedAudio
    case supportsPTP, supportsScreenStream, supportsVolume
    case supportsHKPairing, supportsSystemPairing
    case supportsCoreUtils, supportsCoreUtilsScreenLock
}
```

### GoogleCastTXTData

```swift
struct GoogleCastTXTData: Codable, Sendable {
    var modelName: String?           // e.g., "Chromecast"
    var friendlyName: String?        // e.g., "Living Room TV"
    var id: String?
    var firmwareVersion: String?
    var castVersion: Int?
    var capabilities: Int?
    var receiverStatus: Int?
    var iconPath: String?
    var isBuiltIn: Bool = false
    var supportsGroups: Bool = false
}
```

### HomeKitTXTData

```swift
struct HomeKitTXTData: Codable, Sendable {
    var categoryRaw: Int?
    var category: HomeKitCategory?
    var statusFlags: Int?
    var configurationNumber: Int?
    var featureFlags: Int?
    var protocolVersion: String?
    var deviceId: String?
    var stateNumber: Int?
    var modelName: String?
    var isPaired: Bool = false
    var supportsIP: Bool = true
    var supportsBLE: Bool = false
}
```

### HomeKitCategory

36 categories defined by HAP specification:

```swift
enum HomeKitCategory: Int, Codable, Sendable, CaseIterable {
    case other = 1
    case bridge = 2
    case fan = 3
    case garageDoorOpener = 4
    case lightbulb = 5
    case doorLock = 6
    case outlet = 7
    case `switch` = 8
    case thermostat = 9
    case sensor = 10
    case securitySystem = 11
    case door = 12
    case window = 13
    case windowCovering = 14
    case programmableSwitch = 15
    case rangeExtender = 16
    case ipCamera = 17
    case videoDoorbell = 18
    case airPurifier = 19
    case heater = 20
    case airConditioner = 21
    case humidifier = 22
    case dehumidifier = 23
    case appleTv = 24
    case homePod = 25
    case speaker = 26
    case airport = 27
    case sprinkler = 28
    case faucet = 29
    case showerHead = 30
    case television = 31
    case targetController = 32
    case wifiRouter = 33
    case audioReceiver = 34
    case setTopBox = 35
    case streamingStick = 36
}
```

### RAOPTXTData

```swift
struct RAOPTXTData: Codable, Sendable {
    var model: String?
    var audioFormats: String?
    var compressionTypes: String?
    var encryptionTypes: String?
    var metadataTypes: String?
    var transportProtocols: String?
    var protocolVersion: String?
    var statusFlags: Int?
    var supportsLossless: Bool = false
    var supportsHighResolution: Bool = false
}
```

---

## Port Banner Models

### PortBannerData

Container for all parsed service banners.

```swift
struct PortBannerData: Codable, Sendable {
    var ssh: SSHBannerInfo?
    var http: HTTPHeaderInfo?
    var rtsp: RTSPBannerInfo?
    var rawBanners: [Int: String] = [:]  // Port → raw banner
}
```

### SSHBannerInfo

```swift
struct SSHBannerInfo: Codable, Sendable {
    var rawBanner: String             // Full banner text
    var protocolVersion: String?      // e.g., "2.0"
    var softwareVersion: String?      // e.g., "OpenSSH_9.0p1"
    var osHint: String?               // Detected OS
    var isNetworkEquipment: Bool = false
    var isNAS: Bool = false
}
```

### HTTPHeaderInfo

```swift
struct HTTPHeaderInfo: Codable, Sendable {
    var server: String?               // Server header
    var poweredBy: String?            // X-Powered-By header
    var authenticate: String?         // WWW-Authenticate header
    var contentType: String?
    var detectedFramework: String?    // PHP, ASP.NET, Express.js
    var isAdminInterface: Bool = false
    var isCameraInterface: Bool = false
    var isPrinterInterface: Bool = false
    var isRouterInterface: Bool = false
    var isNASInterface: Bool = false
    var tlsCertificateVerified: Bool = false
}
```

### RTSPBannerInfo

```swift
struct RTSPBannerInfo: Codable, Sendable {
    var server: String?
    var methods: [String] = []        // OPTIONS, DESCRIBE, SETUP, PLAY, etc.
    var contentBase: String?
    var requiresAuth: Bool = false
    var cameraVendor: String?         // Detected camera brand
}
```

---

## MAC Analysis Models

### MACAnalysisData

Results of MAC address analysis.

```swift
struct MACAnalysisData: Codable, Sendable {
    var oui: String                   // Normalized OUI (XX:XX:XX)
    var vendor: String?
    var isLocallyAdministered: Bool = false
    var isRandomized: Bool = false
    var ageEstimate: OUIAgeEstimate = .unknown
    var vendorConfidence: VendorConfidence = .unknown
    var vendorCategories: [DeviceType] = []
    var vendorSpecialization: DeviceType?
}
```

### VendorConfidence

```swift
enum VendorConfidence: String, Codable, Sendable {
    case high        // Major well-known brands
    case medium      // Recognized brands
    case low         // Known but uncommon
    case randomized  // Detected randomized MAC
    case unknown     // No vendor data
}
```

### OUIAgeEstimate

```swift
enum OUIAgeEstimate: String, Codable, Sendable {
    case legacy      // Pre-2010
    case established // 2010-2015
    case modern      // 2015-2020
    case recent      // 2020+
    case unknown
}
```

---

## Inference Engine Models

### Signal

A single inference signal from any source.

```swift
struct Signal: Sendable, Hashable {
    let source: SignalSource
    let suggestedType: DeviceType
    let confidence: Double  // 0.0 to 1.0
}
```

### SignalSource

```swift
enum SignalSource: String, Sendable, CaseIterable {
    case ssdp          // SSDP headers
    case mdns          // mDNS service types
    case port          // Open port numbers
    case fingerprint   // Fingerbank data
    case upnp          // UPnP descriptions
    case hostname      // Hostname patterns
    case mdnsTXT       // Parsed TXT records
    case portBanner    // Parsed banners
    case macAnalysis   // MAC analysis
    case behavior      // Presence patterns
}
```

---

## Fingerprint Models

### DeviceFingerprint

Device identification from various sources.

```swift
struct DeviceFingerprint: Codable, Sendable {
    var friendlyName: String?        // UPnP friendly name
    var manufacturer: String?        // UPnP manufacturer
    var modelName: String?           // UPnP model
    var modelNumber: String?
    var serialNumber: String?
    var upnpDeviceType: String?
    var fingerbankDeviceName: String?
    var fingerbankParents: [String]? // Category hierarchy
    var isMobile: Bool?
    var isTablet: Bool?
}
```

---

## Storage and Persistence

### PersistedBehaviorData

Structure for persisting behavior profiles to disk.

```swift
struct PersistedBehaviorData: Codable {
    let profiles: [String: DeviceBehaviorProfile]
    let lastAccessTime: [String: Date]
    let hashSalt: String
    let hashDeviceIds: Bool
}
```

Storage location: `~/Library/Application Support/LanLens/behavior_profiles.json`

### Limits and Constraints

| Constraint | Value | Purpose |
|------------|-------|---------|
| Max presence records | 100 per device | Memory management |
| Max behavior profiles | 1000 | LRU eviction |
| Persistence interval | Every 10 updates | Durability |
| Min observations for classification | 10 | Reliability |
| Max banner size | 512 bytes | Security |
| Max mDNS service types | 8 | Storage limits |
| Max mDNS keys per service | 32 | Storage limits |
| Max mDNS value length | 256 chars | Storage limits |
