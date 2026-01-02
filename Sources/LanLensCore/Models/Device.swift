import Foundation

/// A discovered network device
public struct Device: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let mac: String
    public var ip: String
    public var hostname: String?
    public var vendor: String?

    public var firstSeen: Date
    public var lastSeen: Date
    public var isOnline: Bool

    public var openPorts: [Port]
    public var services: [DiscoveredService]
    public var httpInfo: HTTPInfo?

    public var smartScore: Int
    public var smartSignals: [SmartSignal]
    public var deviceType: DeviceType
    public var userLabel: String?

    /// Device fingerprint data from UPnP and/or Fingerbank
    public var fingerprint: DeviceFingerprint?

    // MARK: - Enhanced Inference Data

    /// Parsed mDNS TXT record data
    public var mdnsTXTRecords: MDNSTXTData?

    /// Parsed port banner data from probing
    public var portBanners: PortBannerData?

    /// MAC address analysis data
    public var macAnalysis: MACAnalysisData?

    /// Security posture assessment
    public var securityPosture: SecurityPostureData?

    /// Device behavior profile over time
    public var behaviorProfile: DeviceBehaviorProfile?

    // MARK: - Network Source Information

    /// The network interface this device was discovered on (e.g., "en0")
    public var sourceInterface: String?

    /// The subnet this device belongs to in CIDR notation (e.g., "192.168.1.0/24")
    public var subnet: String?

    public init(
        id: UUID = UUID(),
        mac: String,
        ip: String,
        hostname: String? = nil,
        vendor: String? = nil,
        firstSeen: Date = Date(),
        lastSeen: Date = Date(),
        isOnline: Bool = true,
        openPorts: [Port] = [],
        services: [DiscoveredService] = [],
        httpInfo: HTTPInfo? = nil,
        smartScore: Int = 0,
        smartSignals: [SmartSignal] = [],
        deviceType: DeviceType = .unknown,
        userLabel: String? = nil,
        fingerprint: DeviceFingerprint? = nil,
        mdnsTXTRecords: MDNSTXTData? = nil,
        portBanners: PortBannerData? = nil,
        macAnalysis: MACAnalysisData? = nil,
        securityPosture: SecurityPostureData? = nil,
        behaviorProfile: DeviceBehaviorProfile? = nil,
        sourceInterface: String? = nil,
        subnet: String? = nil
    ) {
        self.id = id
        self.mac = mac.uppercased()
        self.ip = ip
        self.hostname = hostname
        self.vendor = vendor
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.isOnline = isOnline
        self.openPorts = openPorts
        self.services = services
        self.httpInfo = httpInfo
        self.smartScore = smartScore
        self.smartSignals = smartSignals
        self.deviceType = deviceType
        self.userLabel = userLabel
        self.fingerprint = fingerprint
        self.mdnsTXTRecords = mdnsTXTRecords
        self.portBanners = portBanners
        self.macAnalysis = macAnalysis
        self.securityPosture = securityPosture
        self.behaviorProfile = behaviorProfile
        self.sourceInterface = sourceInterface
        self.subnet = subnet
    }

    /// Display name: user label > hostname > fingerprint name > vendor + MAC suffix
    public var displayName: String {
        if let label = userLabel, !label.isEmpty {
            return label
        }
        if let hostname = hostname, !hostname.isEmpty {
            return hostname
        }
        // Use Fingerbank device name if available
        if let fingerbankName = fingerprint?.fingerbankDeviceName, !fingerbankName.isEmpty {
            let suffix = String(mac.suffix(5)).replacingOccurrences(of: ":", with: "")
            return "\(fingerbankName) (\(suffix))"
        }
        let suffix = String(mac.suffix(5)).replacingOccurrences(of: ":", with: "")
        if let vendor = vendor {
            return "\(vendor) (\(suffix))"
        }
        return "Device (\(suffix))"
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(mac)
    }

    public static func == (lhs: Device, rhs: Device) -> Bool {
        lhs.mac == rhs.mac
    }
}

// MARK: - Port

public struct Port: Codable, Sendable, Hashable {
    public let number: Int
    public let `protocol`: TransportProtocol
    public var state: PortState
    public var serviceName: String?
    public var banner: String?

    public init(
        number: Int,
        protocol: TransportProtocol = .tcp,
        state: PortState = .open,
        serviceName: String? = nil,
        banner: String? = nil
    ) {
        self.number = number
        self.protocol = `protocol`
        self.state = state
        self.serviceName = serviceName
        self.banner = banner
    }
}

public enum TransportProtocol: String, Codable, Sendable {
    case tcp
    case udp
}

public enum PortState: String, Codable, Sendable {
    case open
    case closed
    case filtered
}

// MARK: - Discovered Service

public struct DiscoveredService: Codable, Sendable, Hashable {
    public let name: String
    public let type: ServiceDiscoveryType
    public let port: Int?
    public let txt: [String: String]
    /// The mDNS service type (e.g., "_airplay._tcp", "_spotify-connect._tcp")
    public let mdnsServiceType: String?

    public init(
        name: String,
        type: ServiceDiscoveryType,
        port: Int? = nil,
        txt: [String: String] = [:],
        mdnsServiceType: String? = nil
    ) {
        self.name = name
        self.type = type
        self.port = port
        self.txt = txt
        self.mdnsServiceType = mdnsServiceType
    }

    /// A user-friendly display name for the service
    public var displayName: String {
        // For mDNS services, prefer the friendly service type name
        if let mdnsType = mdnsServiceType {
            if let friendly = Self.friendlyServiceName(for: mdnsType) {
                return friendly
            }
        }
        // Clean up raw names: strip MAC prefixes (e.g., "001FF010CA08@CXN100" -> "CXN100")
        if let atIndex = name.firstIndex(of: "@") {
            let afterAt = String(name[name.index(after: atIndex)...])
            if !afterAt.isEmpty {
                return afterAt
            }
        }
        return name
    }

    /// Maps mDNS service types to friendly names
    private static func friendlyServiceName(for mdnsType: String) -> String? {
        switch mdnsType {
        case "_airplay._tcp": return "AirPlay"
        case "_raop._tcp": return "AirPlay Audio"
        case "_spotify-connect._tcp": return "Spotify Connect"
        case "_googlecast._tcp": return "Google Cast"
        case "_hap._tcp", "_homekit._tcp": return "HomeKit"
        case "_printer._tcp", "_ipp._tcp": return "Printer"
        case "_scanner._tcp": return "Scanner"
        case "_http._tcp": return "Web Server"
        case "_https._tcp": return "Secure Web"
        case "_ssh._tcp": return "SSH"
        case "_smb._tcp": return "File Sharing (SMB)"
        case "_afpovertcp._tcp": return "File Sharing (AFP)"
        case "_sonos._tcp": return "Sonos"
        case "_hue._tcp": return "Philips Hue"
        case "_mqtt._tcp": return "MQTT"
        case "_dacp._tcp": return "Remote Control"
        case "_touch-able._tcp": return "Apple Remote"
        case "_companion-link._tcp": return "Companion Link"
        case "_device-info._tcp": return "Device Info"
        default: return nil
        }
    }
}

public enum ServiceDiscoveryType: String, Codable, Sendable {
    case mdns
    case ssdp
    case upnp
}

// MARK: - HTTP Info

public struct HTTPInfo: Codable, Sendable, Hashable {
    public let port: Int
    public let title: String?
    public let server: String?
    public let headers: [String: String]

    public init(
        port: Int,
        title: String? = nil,
        server: String? = nil,
        headers: [String: String] = [:]
    ) {
        self.port = port
        self.title = title
        self.server = server
        self.headers = headers
    }
}

// MARK: - Smart Signal

public struct SmartSignal: Codable, Sendable, Hashable {
    public let type: SignalType
    public let description: String
    public let weight: Int

    public init(type: SignalType, description: String, weight: Int) {
        self.type = type
        self.description = description
        self.weight = weight
    }
}

public enum SignalType: String, Codable, Sendable {
    case openPort
    case mdnsService
    case ssdpService
    case httpServer
    case macVendor
    case hostname
}

// MARK: - Device Type

public enum DeviceType: String, Codable, Sendable, CaseIterable {
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

    public var emoji: String {
        switch self {
        case .smartTV: return "📺"
        case .speaker: return "🔊"
        case .camera: return "📷"
        case .thermostat: return "🌡️"
        case .light: return "💡"
        case .plug: return "🔌"
        case .hub: return "🏠"
        case .printer: return "🖨️"
        case .nas: return "💾"
        case .computer: return "💻"
        case .phone: return "📱"
        case .tablet: return "📱"
        case .router: return "📡"
        case .accessPoint: return "📶"
        case .appliance: return "🏠"
        case .unknown: return "❓"
        }
    }
}
