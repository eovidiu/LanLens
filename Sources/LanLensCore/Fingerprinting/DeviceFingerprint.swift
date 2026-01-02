import Foundation

// MARK: - Device Fingerprint

/// Comprehensive device identification data from multiple sources
public struct DeviceFingerprint: Codable, Sendable, Hashable {
    // MARK: Level 1: UPnP Data

    /// Human-readable device name from UPnP (e.g., "Living Room Roku")
    public var friendlyName: String?

    /// Device manufacturer (e.g., "Roku, Inc.")
    public var manufacturer: String?

    /// Manufacturer website URL
    public var manufacturerURL: String?

    /// Device model description (e.g., "Roku Streaming Player")
    public var modelDescription: String?

    /// Model name (e.g., "Roku Ultra")
    public var modelName: String?

    /// Model number (e.g., "4800X")
    public var modelNumber: String?

    /// Device serial number (if exposed)
    public var serialNumber: String?

    /// UPnP device type URN (e.g., "urn:roku-com:device:player:1-0")
    public var upnpDeviceType: String?

    /// List of UPnP services exposed by the device
    public var upnpServices: [UPnPService]?

    // MARK: Level 2: Fingerbank Data

    /// Device name from Fingerbank (e.g., "Apple iPhone 15 Pro")
    public var fingerbankDeviceName: String?

    /// Fingerbank device ID for reference
    public var fingerbankDeviceId: Int?

    /// Device category hierarchy (e.g., ["Apple", "Apple iPhone", "Apple iPhone 15"])
    public var fingerbankParents: [String]?

    /// Confidence score from Fingerbank (0-100)
    public var fingerbankScore: Int?

    /// Operating system name
    public var operatingSystem: String?

    /// OS version (e.g., "iOS 17.2")
    public var osVersion: String?

    /// Whether device is a mobile device
    public var isMobile: Bool?

    /// Whether device is a tablet
    public var isTablet: Bool?

    // MARK: Metadata

    /// Source of the fingerprint data
    public var source: FingerprintSource

    /// When fingerprint was captured
    public var timestamp: Date

    /// Whether this came from cache
    public var cacheHit: Bool

    public init(
        friendlyName: String? = nil,
        manufacturer: String? = nil,
        manufacturerURL: String? = nil,
        modelDescription: String? = nil,
        modelName: String? = nil,
        modelNumber: String? = nil,
        serialNumber: String? = nil,
        upnpDeviceType: String? = nil,
        upnpServices: [UPnPService]? = nil,
        fingerbankDeviceName: String? = nil,
        fingerbankDeviceId: Int? = nil,
        fingerbankParents: [String]? = nil,
        fingerbankScore: Int? = nil,
        operatingSystem: String? = nil,
        osVersion: String? = nil,
        isMobile: Bool? = nil,
        isTablet: Bool? = nil,
        source: FingerprintSource = .none,
        timestamp: Date = Date(),
        cacheHit: Bool = false
    ) {
        self.friendlyName = friendlyName
        self.manufacturer = manufacturer
        self.manufacturerURL = manufacturerURL
        self.modelDescription = modelDescription
        self.modelName = modelName
        self.modelNumber = modelNumber
        self.serialNumber = serialNumber
        self.upnpDeviceType = upnpDeviceType
        self.upnpServices = upnpServices
        self.fingerbankDeviceName = fingerbankDeviceName
        self.fingerbankDeviceId = fingerbankDeviceId
        self.fingerbankParents = fingerbankParents
        self.fingerbankScore = fingerbankScore
        self.operatingSystem = operatingSystem
        self.osVersion = osVersion
        self.isMobile = isMobile
        self.isTablet = isTablet
        self.source = source
        self.timestamp = timestamp
        self.cacheHit = cacheHit
    }

    /// Check if fingerprint has any meaningful data
    public var hasData: Bool {
        friendlyName != nil ||
        manufacturer != nil ||
        modelName != nil ||
        fingerbankDeviceName != nil ||
        fingerbankScore != nil
    }

    /// Best available device name
    public var bestName: String? {
        fingerbankDeviceName ?? friendlyName ?? modelName
    }

    /// Best available manufacturer
    public var bestManufacturer: String? {
        manufacturer ?? fingerbankParents?.first
    }
}

// MARK: - UPnP Service

/// A UPnP service discovered on a device
public struct UPnPService: Codable, Sendable, Hashable {
    /// Service type URN (e.g., "urn:dial-multiscreen-org:service:dial:1")
    public var serviceType: String

    /// Service ID (e.g., "urn:dial-multiscreen-org:serviceId:dial")
    public var serviceId: String

    /// Control URL for the service
    public var controlURL: String?

    /// Event subscription URL
    public var eventSubURL: String?

    /// Service Control Protocol Description URL
    public var SCPDURL: String?

    public init(
        serviceType: String,
        serviceId: String,
        controlURL: String? = nil,
        eventSubURL: String? = nil,
        SCPDURL: String? = nil
    ) {
        self.serviceType = serviceType
        self.serviceId = serviceId
        self.controlURL = controlURL
        self.eventSubURL = eventSubURL
        self.SCPDURL = SCPDURL
    }
}

// MARK: - Fingerprint Source

/// Indicates where fingerprint data came from
public enum FingerprintSource: String, Codable, Sendable {
    /// Level 1: UPnP device description only
    case upnp

    /// Level 2: Fingerbank API only
    case fingerbank

    /// Both UPnP and Fingerbank contributed data
    case both

    /// TLS Server Hello fingerprint (JA3S)
    case tlsFingerprint

    /// No fingerprint data available
    case none
}

// MARK: - Cache Structures

/// Cache entry for UPnP data
public struct UPnPCacheEntry: Codable, Sendable {
    public var mac: String
    public var locationURL: String
    public var fingerprint: DeviceFingerprint
    public var fetchedAt: Date
    public var expiresAt: Date

    public init(mac: String, locationURL: String, fingerprint: DeviceFingerprint, ttlSeconds: TimeInterval = 86400) {
        self.mac = mac
        self.locationURL = locationURL
        self.fingerprint = fingerprint
        self.fetchedAt = Date()
        self.expiresAt = Date().addingTimeInterval(ttlSeconds)
    }

    public var isExpired: Bool {
        Date() > expiresAt
    }
}

/// Cache entry for Fingerbank data
public struct FingerbankCacheEntry: Codable, Sendable {
    public var mac: String
    public var signalHash: String
    public var fingerprint: DeviceFingerprint
    public var fetchedAt: Date
    public var expiresAt: Date

    public init(mac: String, signalHash: String, fingerprint: DeviceFingerprint, ttlSeconds: TimeInterval = 604800) {
        self.mac = mac
        self.signalHash = signalHash
        self.fingerprint = fingerprint
        self.fetchedAt = Date()
        self.expiresAt = Date().addingTimeInterval(ttlSeconds)
    }

    public var isExpired: Bool {
        Date() > expiresAt
    }
}

/// Cache metadata tracking statistics
public struct CacheMetadata: Codable, Sendable {
    public var created: Date
    public var upnpStats: CacheStats
    public var fingerbankStats: CacheStats

    public init() {
        self.created = Date()
        self.upnpStats = CacheStats()
        self.fingerbankStats = CacheStats()
    }
}

/// Statistics for a cache type
public struct CacheStats: Codable, Sendable {
    public var entries: Int
    public var hits: Int
    public var misses: Int

    public init(entries: Int = 0, hits: Int = 0, misses: Int = 0) {
        self.entries = entries
        self.hits = hits
        self.misses = misses
    }

    public var hitRate: Double {
        let total = hits + misses
        guard total > 0 else { return 0 }
        return Double(hits) / Double(total)
    }
}
