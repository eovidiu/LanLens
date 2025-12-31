import Foundation

// MARK: - mDNS TXT Record Data Models

/// Parsed mDNS TXT record data from various service types
public struct MDNSTXTData: Codable, Sendable, Hashable {
    // MARK: - Storage Limits

    /// Maximum number of service types to store in rawRecords
    public static let maxServiceTypes = 20
    /// Maximum number of records per service type
    public static let maxRecordsPerService = 50
    /// Maximum length for record values
    public static let maxRecordValueLength = 256

    /// AirPlay TXT record data
    public var airplay: AirPlayTXTData?
    
    /// Google Cast TXT record data
    public var googleCast: GoogleCastTXTData?
    
    /// HomeKit TXT record data
    public var homeKit: HomeKitTXTData?
    
    /// Remote Audio Output Protocol TXT record data
    public var raop: RAOPTXTData?
    
    /// Raw TXT records by service type for additional parsing
    public var rawRecords: [String: [String: String]]
    
    public init(
        airplay: AirPlayTXTData? = nil,
        googleCast: GoogleCastTXTData? = nil,
        homeKit: HomeKitTXTData? = nil,
        raop: RAOPTXTData? = nil,
        rawRecords: [String: [String: String]] = [:]
    ) {
        self.airplay = airplay
        self.googleCast = googleCast
        self.homeKit = homeKit
        self.raop = raop
        self.rawRecords = rawRecords
    }

    // MARK: - Safe Record Insertion

    /// Adds raw records for a service type with enforced size limits.
    /// - Parameters:
    ///   - serviceType: The mDNS service type (e.g., "_airplay._tcp")
    ///   - records: Dictionary of TXT record key-value pairs
    /// - Note: Silently drops records if limits are exceeded
    public mutating func addRawRecords(serviceType: String, records: [String: String]) {
        // Enforce service type limit: only add if under limit or updating existing
        guard rawRecords.count < Self.maxServiceTypes || rawRecords[serviceType] != nil else {
            return
        }

        var limitedRecords: [String: String] = [:]
        var recordCount = 0

        for (key, value) in records {
            guard recordCount < Self.maxRecordsPerService else { break }
            limitedRecords[key] = String(value.prefix(Self.maxRecordValueLength))
            recordCount += 1
        }

        rawRecords[serviceType] = limitedRecords
    }
}

// MARK: - AirPlay TXT Data

/// Parsed AirPlay service TXT records (_airplay._tcp)
public struct AirPlayTXTData: Codable, Sendable, Hashable {
    /// Device model identifier (e.g., "AppleTV6,2")
    public var model: String?
    
    /// Device flags indicating capabilities
    public var flags: UInt64?
    
    /// Parsed feature flags
    public var features: Set<AirPlayFeature>
    
    /// Device ID (typically MAC-based)
    public var deviceId: String?
    
    /// Protocol version (e.g., "1.1")
    public var protocolVersion: String?
    
    /// Source version
    public var sourceVersion: String?
    
    /// OS build version
    public var osBuildVersion: String?
    
    /// Whether device supports AirPlay 2
    public var supportsAirPlay2: Bool
    
    /// Whether device supports screen mirroring
    public var supportsScreenMirroring: Bool
    
    /// Whether device is an audio-only receiver
    public var isAudioOnly: Bool
    
    public init(
        model: String? = nil,
        flags: UInt64? = nil,
        features: Set<AirPlayFeature> = [],
        deviceId: String? = nil,
        protocolVersion: String? = nil,
        sourceVersion: String? = nil,
        osBuildVersion: String? = nil,
        supportsAirPlay2: Bool = false,
        supportsScreenMirroring: Bool = false,
        isAudioOnly: Bool = false
    ) {
        self.model = model
        self.flags = flags
        self.features = features
        self.deviceId = deviceId
        self.protocolVersion = protocolVersion
        self.sourceVersion = sourceVersion
        self.osBuildVersion = osBuildVersion
        self.supportsAirPlay2 = supportsAirPlay2
        self.supportsScreenMirroring = supportsScreenMirroring
        self.isAudioOnly = isAudioOnly
    }
}

/// AirPlay feature flags parsed from TXT records
public enum AirPlayFeature: String, Codable, Sendable, CaseIterable {
    case video = "video"
    case photo = "photo"
    case slideshow = "slideshow"
    case screen = "screen"
    case screenRotate = "screenRotate"
    case audio = "audio"
    case audioRedundant = "audioRedundant"
    case ftpDataChunkedSend = "ftpDataChunkedSend"
    case authentication = "authentication"
    case metadataFeatures = "metadataFeatures"
    case audioFormat = "audioFormat"
    case playbackQueue = "playbackQueue"
    case hudSupported = "hudSupported"
    case mfiCert = "mfiCert"
    case carPlay = "carPlay"
    case supportsUnifiedMediaControl = "supportsUnifiedMediaControl"
    case supportsBufferedAudio = "supportsBufferedAudio"
    case supportsPTP = "supportsPTP"
    case supportsScreenStream = "supportsScreenStream"
    case supportsVolume = "supportsVolume"
    case supportsHKPairing = "supportsHKPairing"
    case supportsSystemPairing = "supportsSystemPairing"
    case supportsCoreUtils = "supportsCoreUtils"
    case supportsCoreUtilsScreenLock = "supportsCoreUtilsScreenLock"
    case unknown = "unknown"
}

// MARK: - Google Cast TXT Data

/// Parsed Google Cast service TXT records (_googlecast._tcp)
public struct GoogleCastTXTData: Codable, Sendable, Hashable {
    /// Device unique identifier
    public var id: String?
    
    /// Device model name (e.g., "Chromecast", "Google Home Mini")
    public var modelName: String?
    
    /// Friendly name set by user
    public var friendlyName: String?
    
    /// Icon path for device
    public var iconPath: String?
    
    /// Firmware version
    public var firmwareVersion: String?
    
    /// Chromecast version (ca = cast version)
    public var castVersion: Int?
    
    /// Device capabilities bitfield
    public var capabilities: Int?
    
    /// Receiver status
    public var receiverStatus: Int?
    
    /// Whether this is a Chromecast built-in (TV with cast)
    public var isBuiltIn: Bool
    
    /// Whether device supports groups
    public var supportsGroups: Bool
    
    public init(
        id: String? = nil,
        modelName: String? = nil,
        friendlyName: String? = nil,
        iconPath: String? = nil,
        firmwareVersion: String? = nil,
        castVersion: Int? = nil,
        capabilities: Int? = nil,
        receiverStatus: Int? = nil,
        isBuiltIn: Bool = false,
        supportsGroups: Bool = false
    ) {
        self.id = id
        self.modelName = modelName
        self.friendlyName = friendlyName
        self.iconPath = iconPath
        self.firmwareVersion = firmwareVersion
        self.castVersion = castVersion
        self.capabilities = capabilities
        self.receiverStatus = receiverStatus
        self.isBuiltIn = isBuiltIn
        self.supportsGroups = supportsGroups
    }
}

// MARK: - HomeKit TXT Data

/// Parsed HomeKit Accessory Protocol TXT records (_hap._tcp)
public struct HomeKitTXTData: Codable, Sendable, Hashable {
    /// Accessory category
    public var category: HomeKitCategory?
    
    /// Raw category value
    public var categoryRaw: Int?
    
    /// Status flags
    public var statusFlags: Int?
    
    /// Configuration number (changes when accessory config changes)
    public var configurationNumber: Int?
    
    /// Feature flags
    public var featureFlags: Int?
    
    /// Protocol version
    public var protocolVersion: String?
    
    /// State number
    public var stateNumber: Int?
    
    /// Device ID
    public var deviceId: String?
    
    /// Model name
    public var modelName: String?
    
    /// Whether accessory is paired
    public var isPaired: Bool
    
    /// Whether accessory supports IP transport
    public var supportsIP: Bool
    
    /// Whether accessory supports BLE transport
    public var supportsBLE: Bool
    
    public init(
        category: HomeKitCategory? = nil,
        categoryRaw: Int? = nil,
        statusFlags: Int? = nil,
        configurationNumber: Int? = nil,
        featureFlags: Int? = nil,
        protocolVersion: String? = nil,
        stateNumber: Int? = nil,
        deviceId: String? = nil,
        modelName: String? = nil,
        isPaired: Bool = false,
        supportsIP: Bool = true,
        supportsBLE: Bool = false
    ) {
        self.category = category
        self.categoryRaw = categoryRaw
        self.statusFlags = statusFlags
        self.configurationNumber = configurationNumber
        self.featureFlags = featureFlags
        self.protocolVersion = protocolVersion
        self.stateNumber = stateNumber
        self.deviceId = deviceId
        self.modelName = modelName
        self.isPaired = isPaired
        self.supportsIP = supportsIP
        self.supportsBLE = supportsBLE
    }
}

/// HomeKit accessory categories as defined in HAP specification
public enum HomeKitCategory: Int, Codable, Sendable, CaseIterable {
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
    case televisionSetTopBox = 35
    case televisionStreamingStick = 36
    
    /// Human-readable display name for the category
    public var displayName: String {
        switch self {
        case .other: return "Other"
        case .bridge: return "Bridge"
        case .fan: return "Fan"
        case .garageDoorOpener: return "Garage Door Opener"
        case .lightbulb: return "Lightbulb"
        case .doorLock: return "Door Lock"
        case .outlet: return "Outlet"
        case .switch: return "Switch"
        case .thermostat: return "Thermostat"
        case .sensor: return "Sensor"
        case .securitySystem: return "Security System"
        case .door: return "Door"
        case .window: return "Window"
        case .windowCovering: return "Window Covering"
        case .programmableSwitch: return "Programmable Switch"
        case .rangeExtender: return "Range Extender"
        case .ipCamera: return "IP Camera"
        case .videoDoorbell: return "Video Doorbell"
        case .airPurifier: return "Air Purifier"
        case .heater: return "Heater"
        case .airConditioner: return "Air Conditioner"
        case .humidifier: return "Humidifier"
        case .dehumidifier: return "Dehumidifier"
        case .appleTv: return "Apple TV"
        case .homePod: return "HomePod"
        case .speaker: return "Speaker"
        case .airport: return "AirPort"
        case .sprinkler: return "Sprinkler"
        case .faucet: return "Faucet"
        case .showerHead: return "Shower Head"
        case .television: return "Television"
        case .targetController: return "Target Controller"
        case .wifiRouter: return "Wi-Fi Router"
        case .audioReceiver: return "Audio Receiver"
        case .televisionSetTopBox: return "Set-Top Box"
        case .televisionStreamingStick: return "Streaming Stick"
        }
    }
    
    /// Map to DeviceType for inference
    public var suggestedDeviceType: DeviceType {
        switch self {
        case .lightbulb, .switch, .outlet:
            return .light
        case .thermostat, .heater, .airConditioner:
            return .thermostat
        case .ipCamera, .videoDoorbell:
            return .camera
        case .speaker, .homePod, .audioReceiver:
            return .speaker
        case .appleTv, .television, .televisionSetTopBox, .televisionStreamingStick:
            return .smartTV
        case .bridge, .wifiRouter, .airport, .rangeExtender:
            return .hub
        case .fan, .airPurifier, .humidifier, .dehumidifier:
            return .appliance
        case .garageDoorOpener, .doorLock, .door, .window, .windowCovering:
            return .appliance
        case .securitySystem:
            return .hub
        case .sensor, .programmableSwitch:
            return .hub
        case .sprinkler, .faucet, .showerHead:
            return .appliance
        case .targetController, .other:
            return .unknown
        }
    }
}

// MARK: - RAOP TXT Data

/// Parsed Remote Audio Output Protocol TXT records (_raop._tcp)
public struct RAOPTXTData: Codable, Sendable, Hashable {
    /// Audio formats supported (comma-separated)
    public var audioFormats: String?
    
    /// Compression types supported
    public var compressionTypes: String?
    
    /// Encryption types supported
    public var encryptionTypes: String?
    
    /// Metadata types supported
    public var metadataTypes: String?
    
    /// Transport protocols supported
    public var transportProtocols: String?
    
    /// Protocol version
    public var protocolVersion: String?
    
    /// Status flags
    public var statusFlags: Int?
    
    /// Device model
    public var model: String?
    
    /// Whether device supports lossless audio
    public var supportsLossless: Bool
    
    /// Whether device supports high-resolution audio
    public var supportsHighResolution: Bool
    
    public init(
        audioFormats: String? = nil,
        compressionTypes: String? = nil,
        encryptionTypes: String? = nil,
        metadataTypes: String? = nil,
        transportProtocols: String? = nil,
        protocolVersion: String? = nil,
        statusFlags: Int? = nil,
        model: String? = nil,
        supportsLossless: Bool = false,
        supportsHighResolution: Bool = false
    ) {
        self.audioFormats = audioFormats
        self.compressionTypes = compressionTypes
        self.encryptionTypes = encryptionTypes
        self.metadataTypes = metadataTypes
        self.transportProtocols = transportProtocols
        self.protocolVersion = protocolVersion
        self.statusFlags = statusFlags
        self.model = model
        self.supportsLossless = supportsLossless
        self.supportsHighResolution = supportsHighResolution
    }
}

// MARK: - Port Banner Data

/// Parsed banner information from port probing
public struct PortBannerData: Codable, Sendable, Hashable {
    /// SSH banner information
    public var ssh: SSHBannerInfo?
    
    /// HTTP/HTTPS header information
    public var http: HTTPHeaderInfo?
    
    /// RTSP banner information
    public var rtsp: RTSPBannerInfo?
    
    /// Raw banners by port number
    public var rawBanners: [Int: String]
    
    public init(
        ssh: SSHBannerInfo? = nil,
        http: HTTPHeaderInfo? = nil,
        rtsp: RTSPBannerInfo? = nil,
        rawBanners: [Int: String] = [:]
    ) {
        self.ssh = ssh
        self.http = http
        self.rtsp = rtsp
        self.rawBanners = rawBanners
    }
}

/// Parsed SSH version banner
public struct SSHBannerInfo: Codable, Sendable, Hashable {
    /// Full banner string
    public var rawBanner: String
    
    /// Protocol version (e.g., "2.0")
    public var protocolVersion: String?
    
    /// Software version (e.g., "OpenSSH_8.9p1")
    public var softwareVersion: String?
    
    /// Operating system hint from banner
    public var osHint: String?
    
    /// Whether this appears to be a router/switch SSH
    public var isNetworkEquipment: Bool
    
    /// Whether this appears to be a NAS SSH
    public var isNAS: Bool
    
    public init(
        rawBanner: String,
        protocolVersion: String? = nil,
        softwareVersion: String? = nil,
        osHint: String? = nil,
        isNetworkEquipment: Bool = false,
        isNAS: Bool = false
    ) {
        self.rawBanner = rawBanner
        self.protocolVersion = protocolVersion
        self.softwareVersion = softwareVersion
        self.osHint = osHint
        self.isNetworkEquipment = isNetworkEquipment
        self.isNAS = isNAS
    }
}

/// Parsed HTTP header information
public struct HTTPHeaderInfo: Codable, Sendable, Hashable {
    /// Server header value
    public var server: String?
    
    /// X-Powered-By header
    public var poweredBy: String?
    
    /// WWW-Authenticate header (indicates auth method)
    public var authenticate: String?
    
    /// Content-Type of default response
    public var contentType: String?
    
    /// Detected web framework or CMS
    public var detectedFramework: String?
    
    /// Whether this appears to be an admin interface
    public var isAdminInterface: Bool
    
    /// Whether this appears to be a camera web interface
    public var isCameraInterface: Bool
    
    /// Whether this appears to be a printer interface
    public var isPrinterInterface: Bool
    
    /// Whether this appears to be a router interface
    public var isRouterInterface: Bool
    
    /// Whether this appears to be a NAS interface
    public var isNASInterface: Bool

    /// Whether TLS certificate was properly verified.
    /// False indicates certificate validation was bypassed (common for IoT device probing).
    /// This field provides observability into TLS security posture.
    public var tlsCertificateVerified: Bool

    public init(
        server: String? = nil,
        poweredBy: String? = nil,
        authenticate: String? = nil,
        contentType: String? = nil,
        detectedFramework: String? = nil,
        isAdminInterface: Bool = false,
        isCameraInterface: Bool = false,
        isPrinterInterface: Bool = false,
        isRouterInterface: Bool = false,
        isNASInterface: Bool = false,
        tlsCertificateVerified: Bool = false
    ) {
        self.server = server
        self.poweredBy = poweredBy
        self.authenticate = authenticate
        self.contentType = contentType
        self.detectedFramework = detectedFramework
        self.isAdminInterface = isAdminInterface
        self.isCameraInterface = isCameraInterface
        self.isPrinterInterface = isPrinterInterface
        self.isRouterInterface = isRouterInterface
        self.isNASInterface = isNASInterface
        self.tlsCertificateVerified = tlsCertificateVerified
    }
}

/// Parsed RTSP banner information
public struct RTSPBannerInfo: Codable, Sendable, Hashable {
    /// Server header value
    public var server: String?
    
    /// Supported RTSP methods
    public var methods: [String]
    
    /// Content-Base URL
    public var contentBase: String?
    
    /// Whether authentication is required
    public var requiresAuth: Bool
    
    /// Detected camera brand
    public var cameraVendor: String?
    
    public init(
        server: String? = nil,
        methods: [String] = [],
        contentBase: String? = nil,
        requiresAuth: Bool = false,
        cameraVendor: String? = nil
    ) {
        self.server = server
        self.methods = methods
        self.contentBase = contentBase
        self.requiresAuth = requiresAuth
        self.cameraVendor = cameraVendor
    }
}

// MARK: - MAC Analysis Data

/// Analysis data derived from MAC address
public struct MACAnalysisData: Codable, Sendable, Hashable {
    /// OUI (first 3 bytes) of MAC address
    public var oui: String
    
    /// Vendor name from OUI lookup
    public var vendor: String?
    
    /// Whether this is a locally administered MAC (LAA)
    public var isLocallyAdministered: Bool
    
    /// Whether this appears to be a randomized MAC (iOS 14+, Android 10+)
    public var isRandomized: Bool
    
    /// Age estimate based on OUI registration date
    public var ageEstimate: OUIAgeEstimate?
    
    /// Vendor confidence level
    public var vendorConfidence: VendorConfidence
    
    /// Known device categories for this vendor
    public var vendorCategories: [DeviceType]
    
    /// Whether vendor is known for specific device type
    public var vendorSpecialization: DeviceType?
    
    public init(
        oui: String,
        vendor: String? = nil,
        isLocallyAdministered: Bool = false,
        isRandomized: Bool = false,
        ageEstimate: OUIAgeEstimate? = nil,
        vendorConfidence: VendorConfidence = .unknown,
        vendorCategories: [DeviceType] = [],
        vendorSpecialization: DeviceType? = nil
    ) {
        self.oui = oui
        self.vendor = vendor
        self.isLocallyAdministered = isLocallyAdministered
        self.isRandomized = isRandomized
        self.ageEstimate = ageEstimate
        self.vendorConfidence = vendorConfidence
        self.vendorCategories = vendorCategories
        self.vendorSpecialization = vendorSpecialization
    }
}

/// Estimated device age based on OUI registration date
public enum OUIAgeEstimate: String, Codable, Sendable, CaseIterable {
    case legacy = "legacy"           // Before 2010
    case established = "established" // 2010-2015
    case modern = "modern"           // 2015-2020
    case recent = "recent"           // 2020-present
    case unknown = "unknown"
}

/// Confidence level in vendor identification
public enum VendorConfidence: String, Codable, Sendable, CaseIterable {
    case high = "high"           // Major vendor, well-known OUI
    case medium = "medium"       // Recognized vendor, valid OUI
    case low = "low"             // Unknown vendor or LAA
    case randomized = "randomized" // Detected as randomized MAC
    case unknown = "unknown"
}

// MARK: - Security Posture Data

/// Security assessment data for a device
public struct SecurityPostureData: Codable, Sendable, Hashable {
    /// Overall risk level
    public var riskLevel: RiskLevel
    
    /// Risk score (0-100, higher is riskier)
    public var riskScore: Int
    
    /// Individual risk factors identified
    public var riskFactors: [RiskFactor]
    
    /// Open ports that increase risk
    public var riskyPorts: [Int]
    
    /// Whether device exposes a web interface
    public var hasWebInterface: Bool
    
    /// Whether device requires authentication for services
    public var requiresAuthentication: Bool
    
    /// Whether device uses encrypted protocols
    public var usesEncryption: Bool
    
    /// Whether device firmware appears outdated
    public var firmwareOutdated: Bool?
    
    /// Last security assessment timestamp
    public var assessmentDate: Date
    
    public init(
        riskLevel: RiskLevel = .unknown,
        riskScore: Int = 0,
        riskFactors: [RiskFactor] = [],
        riskyPorts: [Int] = [],
        hasWebInterface: Bool = false,
        requiresAuthentication: Bool = true,
        usesEncryption: Bool = true,
        firmwareOutdated: Bool? = nil,
        assessmentDate: Date = Date()
    ) {
        self.riskLevel = riskLevel
        self.riskScore = riskScore
        self.riskFactors = riskFactors
        self.riskyPorts = riskyPorts
        self.hasWebInterface = hasWebInterface
        self.requiresAuthentication = requiresAuthentication
        self.usesEncryption = usesEncryption
        self.firmwareOutdated = firmwareOutdated
        self.assessmentDate = assessmentDate
    }
}

/// Risk level classification
public enum RiskLevel: String, Codable, Sendable, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
    case unknown = "unknown"
    
    /// Numeric value for sorting (higher = more risky)
    public var numericValue: Int {
        switch self {
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        case .critical: return 4
        case .unknown: return 0
        }
    }
}

/// A specific risk factor identified for a device
public struct RiskFactor: Codable, Sendable, Hashable {
    /// Category of the risk
    public var category: String
    
    /// Human-readable description
    public var description: String
    
    /// Severity level
    public var severity: RiskLevel
    
    /// Points contributed to risk score
    public var scoreContribution: Int
    
    /// Recommended remediation action
    public var remediation: String?
    
    public init(
        category: String,
        description: String,
        severity: RiskLevel,
        scoreContribution: Int,
        remediation: String? = nil
    ) {
        self.category = category
        self.description = description
        self.severity = severity
        self.scoreContribution = scoreContribution
        self.remediation = remediation
    }
}

// MARK: - Device Behavior Profile

/// Behavioral profile based on device observation over time
public struct DeviceBehaviorProfile: Codable, Sendable, Hashable {
    /// Behavioral classification
    public var classification: BehaviorClassification
    
    /// Presence records over time
    public var presenceHistory: [PresenceRecord]
    
    /// Average uptime percentage (0-100)
    public var averageUptimePercent: Double
    
    /// Whether device has consistent presence (servers, IoT)
    public var isAlwaysOn: Bool
    
    /// Whether device has intermittent presence (mobile, laptop)
    public var isIntermittent: Bool
    
    /// Whether device follows a daily pattern
    public var hasDailyPattern: Bool
    
    /// Peak activity hours (0-23)
    public var peakHours: [Int]
    
    /// Services that are consistently available
    public var consistentServices: [String]
    
    /// First observation timestamp
    public var firstObserved: Date
    
    /// Most recent observation timestamp
    public var lastObserved: Date
    
    /// Total number of observations
    public var observationCount: Int
    
    public init(
        classification: BehaviorClassification = .unknown,
        presenceHistory: [PresenceRecord] = [],
        averageUptimePercent: Double = 0,
        isAlwaysOn: Bool = false,
        isIntermittent: Bool = false,
        hasDailyPattern: Bool = false,
        peakHours: [Int] = [],
        consistentServices: [String] = [],
        firstObserved: Date = Date(),
        lastObserved: Date = Date(),
        observationCount: Int = 0
    ) {
        self.classification = classification
        self.presenceHistory = presenceHistory
        self.averageUptimePercent = averageUptimePercent
        self.isAlwaysOn = isAlwaysOn
        self.isIntermittent = isIntermittent
        self.hasDailyPattern = hasDailyPattern
        self.peakHours = peakHours
        self.consistentServices = consistentServices
        self.firstObserved = firstObserved
        self.lastObserved = lastObserved
        self.observationCount = observationCount
    }
}

/// Classification of device behavior patterns
public enum BehaviorClassification: String, Codable, Sendable, CaseIterable {
    case infrastructure = "infrastructure"   // Routers, switches, APs - always on
    case server = "server"                   // NAS, servers - always on
    case iot = "iot"                         // IoT devices - always on, limited services
    case workstation = "workstation"         // Desktop computers - daily pattern
    case portable = "portable"               // Laptops, tablets - intermittent
    case mobile = "mobile"                   // Phones - highly intermittent
    case guest = "guest"                     // Seen only briefly
    case unknown = "unknown"
    
    /// Expected uptime percentage for this classification
    public var expectedUptimeRange: ClosedRange<Double> {
        switch self {
        case .infrastructure: return 95...100
        case .server: return 90...100
        case .iot: return 85...100
        case .workstation: return 30...70
        case .portable: return 10...50
        case .mobile: return 5...30
        case .guest: return 0...5
        case .unknown: return 0...100
        }
    }
    
    /// Suggested device type based on behavior
    public var suggestedDeviceTypes: [DeviceType] {
        switch self {
        case .infrastructure:
            return [.router, .accessPoint, .hub]
        case .server:
            return [.nas, .computer]
        case .iot:
            return [.camera, .thermostat, .light, .plug, .speaker, .appliance]
        case .workstation:
            return [.computer]
        case .portable:
            return [.computer, .tablet]
        case .mobile:
            return [.phone, .tablet]
        case .guest:
            return [.phone, .computer]
        case .unknown:
            return []
        }
    }
}

/// A single presence observation record
public struct PresenceRecord: Codable, Sendable, Hashable {
    /// Timestamp of observation
    public var timestamp: Date
    
    /// Whether device was online
    public var isOnline: Bool
    
    /// Services available during observation
    public var availableServices: [String]
    
    /// IP address at time of observation
    public var ipAddress: String?
    
    public init(
        timestamp: Date = Date(),
        isOnline: Bool = true,
        availableServices: [String] = [],
        ipAddress: String? = nil
    ) {
        self.timestamp = timestamp
        self.isOnline = isOnline
        self.availableServices = availableServices
        self.ipAddress = ipAddress
    }
}
