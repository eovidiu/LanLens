import Foundation

/// Centralized engine for inferring device types from multiple signal sources.
/// Uses weighted confidence scoring to aggregate signals and determine the most likely device type.
public actor DeviceTypeInferenceEngine {
    
    // MARK: - Singleton
    
    public static let shared = DeviceTypeInferenceEngine()
    
    private init() {}
    
    // MARK: - Types
    
    /// Sources of device type inference signals
    public enum SignalSource: String, Sendable, CaseIterable {
        case ssdp
        case mdns
        case port
        case fingerprint
        case upnp
        case hostname
        case mdnsTXT         // Parsed mDNS TXT records (high confidence)
        case portBanner      // Parsed port banners (medium-high confidence)
        case macAnalysis     // MAC address analysis (medium confidence)
        case behavior        // Device presence/usage patterns
        case dhcpFingerprint // DHCP Option 55 fingerprint (high confidence)
    }
    
    /// A signal suggesting a device type with associated confidence
    public struct Signal: Sendable, Hashable {
        public let source: SignalSource
        public let suggestedType: DeviceType
        public let confidence: Double  // 0.0 to 1.0
        
        public init(source: SignalSource, suggestedType: DeviceType, confidence: Double) {
            self.source = source
            self.suggestedType = suggestedType
            self.confidence = min(1.0, max(0.0, confidence))  // Clamp to valid range
        }
    }
    
    // MARK: - Base Confidence Weights
    
    /// Base confidence weights by signal source
    /// Higher values indicate more reliable sources
    private static let sourceWeights: [SignalSource: Double] = [
        .fingerprint: 0.9,      // Fingerbank data is most reliable
        .mdnsTXT: 0.85,         // Parsed mDNS TXT records are very informative
        .upnp: 0.8,             // UPnP device descriptions are quite accurate
        .portBanner: 0.75,      // Parsed port banners provide good device info
        .mdns: 0.7,             // mDNS service types are good indicators
        .ssdp: 0.7,             // SSDP headers are good indicators
        .dhcpFingerprint: 0.65, // DHCP Option 55 fingerprint - per architecture doc
        .hostname: 0.6,         // Hostnames can be informative but less reliable
        .macAnalysis: 0.60,     // MAC analysis is useful but less specific
        .behavior: 0.6,         // Behavior patterns are informative but not definitive
        .port: 0.5              // Port-based inference is least reliable
    ]
    
    // MARK: - Main Inference Method
    
    /// Aggregate signals and return the most likely device type
    /// - Parameter signals: Array of signals from various sources
    /// - Returns: The device type with highest aggregated confidence, or .unknown if no signals
    public func infer(signals: [Signal]) -> DeviceType {
        guard !signals.isEmpty else { return .unknown }
        
        // Aggregate confidence scores per device type
        var typeScores: [DeviceType: Double] = [:]
        
        for signal in signals {
            // Skip unknown type signals
            guard signal.suggestedType != .unknown else { continue }
            
            // Get base weight for this source
            let baseWeight = Self.sourceWeights[signal.source] ?? 0.5
            
            // Calculate weighted confidence
            let weightedConfidence = signal.confidence * baseWeight
            
            // Accumulate score for this type
            typeScores[signal.suggestedType, default: 0.0] += weightedConfidence
        }
        
        // Return type with highest score, or .unknown if no valid signals
        return typeScores.max(by: { $0.value < $1.value })?.key ?? .unknown
    }
    
    // MARK: - Factory Methods for Creating Signals
    
    /// Create signals from SSDP headers
    /// - Parameters:
    ///   - server: SSDP SERVER header value
    ///   - usn: SSDP USN header value
    ///   - st: SSDP ST (Search Target) header value
    /// - Returns: Array of inferred signals
    public func signalsFromSSDPHeaders(server: String?, usn: String?, st: String?) -> [Signal] {
        var signals: [Signal] = []
        
        let serverLower = server?.lowercased() ?? ""
        let usnLower = usn?.lowercased() ?? ""
        let stLower = st?.lowercased() ?? ""
        
        // Roku detection
        if serverLower.contains("roku") {
            signals.append(Signal(source: .ssdp, suggestedType: .smartTV, confidence: 0.95))
        }
        
        // TV manufacturers
        if serverLower.contains("samsung") || serverLower.contains("lg") || serverLower.contains("sony") ||
           serverLower.contains("vizio") || serverLower.contains("tcl") || serverLower.contains("hisense") {
            signals.append(Signal(source: .ssdp, suggestedType: .smartTV, confidence: 0.85))
        }
        
        // Sonos detection
        if serverLower.contains("sonos") || usnLower.contains("sonos") {
            signals.append(Signal(source: .ssdp, suggestedType: .speaker, confidence: 0.95))
        }
        
        // Philips Hue
        if serverLower.contains("philips-hue") || usnLower.contains("hue") {
            signals.append(Signal(source: .ssdp, suggestedType: .hub, confidence: 0.95))
        }
        
        // Printer detection
        if stLower.contains("printer") || serverLower.contains("printer") {
            signals.append(Signal(source: .ssdp, suggestedType: .printer, confidence: 0.90))
        }
        
        // Media server/renderer
        if stLower.contains("mediaserver") || stLower.contains("mediarenderer") {
            signals.append(Signal(source: .ssdp, suggestedType: .smartTV, confidence: 0.75))
        }
        
        // NAS devices
        if serverLower.contains("synology") || serverLower.contains("qnap") ||
           serverLower.contains("drobo") || serverLower.contains("netgear readynas") {
            signals.append(Signal(source: .ssdp, suggestedType: .nas, confidence: 0.90))
        }
        
        // Router detection
        if serverLower.contains("router") || serverLower.contains("gateway") ||
           stLower.contains("internetgatewaydevice") {
            signals.append(Signal(source: .ssdp, suggestedType: .router, confidence: 0.85))
        }
        
        // Bose/audio brands
        if serverLower.contains("bose") || serverLower.contains("denon") ||
           serverLower.contains("yamaha") || serverLower.contains("onkyo") {
            signals.append(Signal(source: .ssdp, suggestedType: .speaker, confidence: 0.85))
        }
        
        // StreamMagic / Cambridge Audio
        if serverLower.contains("streammagic") || serverLower.contains("cambridge audio") {
            signals.append(Signal(source: .ssdp, suggestedType: .speaker, confidence: 0.90))
        }
        
        // Ring doorbell/camera
        if serverLower.contains("ring") {
            signals.append(Signal(source: .ssdp, suggestedType: .camera, confidence: 0.85))
        }
        
        // Nest devices
        if serverLower.contains("nest") {
            // Could be thermostat or camera - lower confidence
            signals.append(Signal(source: .ssdp, suggestedType: .thermostat, confidence: 0.60))
        }
        
        // WeMo
        if serverLower.contains("wemo") {
            signals.append(Signal(source: .ssdp, suggestedType: .plug, confidence: 0.85))
        }
        
        return signals
    }
    
    /// Create signals from mDNS service type
    /// - Parameter serviceType: The mDNS service type (e.g., "_airplay._tcp")
    /// - Returns: Array of inferred signals
    public func signalsFromMDNSServiceType(_ serviceType: String) -> [Signal] {
        var signals: [Signal] = []
        
        switch serviceType {
        // HomeKit
        case "_hap._tcp", "_homekit._tcp":
            signals.append(Signal(source: .mdns, suggestedType: .hub, confidence: 0.80))
            
        // AirPlay (Apple TV, speakers, etc.)
        case "_airplay._tcp", "_raop._tcp":
            signals.append(Signal(source: .mdns, suggestedType: .smartTV, confidence: 0.80))
            
        // Google Cast
        case "_googlecast._tcp":
            signals.append(Signal(source: .mdns, suggestedType: .smartTV, confidence: 0.85))
            
        // Audio devices
        case "_spotify-connect._tcp", "_sonos._tcp":
            signals.append(Signal(source: .mdns, suggestedType: .speaker, confidence: 0.90))
            
        // Printers and scanners
        case "_printer._tcp", "_ipp._tcp":
            signals.append(Signal(source: .mdns, suggestedType: .printer, confidence: 0.95))
        case "_scanner._tcp":
            signals.append(Signal(source: .mdns, suggestedType: .printer, confidence: 0.85))
            
        // Philips Hue
        case "_hue._tcp":
            signals.append(Signal(source: .mdns, suggestedType: .light, confidence: 0.95))
            
        // Thermostats
        case "_ecobee._tcp", "_nest._tcp":
            signals.append(Signal(source: .mdns, suggestedType: .thermostat, confidence: 0.90))
            
        // Amazon devices
        case "_amzn-wplay._tcp", "_alexa._tcp":
            signals.append(Signal(source: .mdns, suggestedType: .speaker, confidence: 0.85))
            
        // Computer-like services
        case "_ssh._tcp", "_smb._tcp", "_afpovertcp._tcp":
            signals.append(Signal(source: .mdns, suggestedType: .computer, confidence: 0.70))
            
        // Bond Home (fans, shades)
        case "_bond._tcp":
            signals.append(Signal(source: .mdns, suggestedType: .appliance, confidence: 0.85))
            
        // Lutron
        case "_leap._tcp":
            signals.append(Signal(source: .mdns, suggestedType: .hub, confidence: 0.85))
            
        // MQTT (IoT)
        case "_mqtt._tcp":
            signals.append(Signal(source: .mdns, suggestedType: .hub, confidence: 0.60))
            
        // DACP / Apple Remote
        case "_dacp._tcp", "_touch-able._tcp":
            signals.append(Signal(source: .mdns, suggestedType: .smartTV, confidence: 0.70))
            
        // Companion link
        case "_companion-link._tcp":
            signals.append(Signal(source: .mdns, suggestedType: .smartTV, confidence: 0.65))
            
        default:
            break
        }
        
        return signals
    }
    
    /// Create signals from open port number
    /// - Parameter port: The port number
    /// - Returns: Array of inferred signals
    public func signalsFromPort(_ port: Int) -> [Signal] {
        var signals: [Signal] = []
        
        switch port {
        // RTSP - cameras
        case 554:
            signals.append(Signal(source: .port, suggestedType: .camera, confidence: 0.75))
            
        // Sonos
        case 1400:
            signals.append(Signal(source: .port, suggestedType: .speaker, confidence: 0.85))
            
        // AirPlay
        case 7000:
            signals.append(Signal(source: .port, suggestedType: .smartTV, confidence: 0.75))
            
        // Google Cast
        case 8008, 8009:
            signals.append(Signal(source: .port, suggestedType: .smartTV, confidence: 0.80))
            
        // Home Assistant
        case 8123:
            signals.append(Signal(source: .port, suggestedType: .hub, confidence: 0.90))
            
        // Plex
        case 32400:
            signals.append(Signal(source: .port, suggestedType: .computer, confidence: 0.70))
            
        // Printing
        case 9100:
            signals.append(Signal(source: .port, suggestedType: .printer, confidence: 0.85))
            
        // MQTT (IoT)
        case 1883, 8883:
            signals.append(Signal(source: .port, suggestedType: .hub, confidence: 0.60))
            
        // UPnP/Synology
        case 5000, 5001:
            signals.append(Signal(source: .port, suggestedType: .nas, confidence: 0.50))
            
        // DAAP (iTunes)
        case 3689:
            signals.append(Signal(source: .port, suggestedType: .computer, confidence: 0.60))
            
        // AFP (Mac file sharing)
        case 548:
            signals.append(Signal(source: .port, suggestedType: .computer, confidence: 0.65))
            
        default:
            break
        }
        
        return signals
    }
    
    /// Create signals from device fingerprint data
    /// - Parameter fingerprint: The device fingerprint
    /// - Returns: Array of inferred signals
    public func signalsFromFingerprint(_ fingerprint: DeviceFingerprint) -> [Signal] {
        var signals: [Signal] = []
        
        // Check Fingerbank parent hierarchy
        if let parents = fingerprint.fingerbankParents {
            let combined = parents.joined(separator: " ").lowercased()
            
            // Mobile devices
            if combined.contains("iphone") || combined.contains("android") || combined.contains("phone") {
                signals.append(Signal(source: .fingerprint, suggestedType: .phone, confidence: 0.95))
            }
            
            // Tablets
            if combined.contains("ipad") || combined.contains("tablet") {
                signals.append(Signal(source: .fingerprint, suggestedType: .tablet, confidence: 0.95))
            }
            
            // Computers
            if combined.contains("macbook") || combined.contains("imac") || combined.contains("mac") ||
               combined.contains("windows") || combined.contains("laptop") || combined.contains("desktop") ||
               combined.contains("pc") {
                signals.append(Signal(source: .fingerprint, suggestedType: .computer, confidence: 0.90))
            }
            
            // Streaming devices / Smart TVs
            if combined.contains("roku") || combined.contains("chromecast") || combined.contains("apple tv") ||
               combined.contains("fire tv") || combined.contains("smart tv") || combined.contains("androidtv") {
                signals.append(Signal(source: .fingerprint, suggestedType: .smartTV, confidence: 0.95))
            }
            
            // Speakers
            if combined.contains("sonos") || combined.contains("speaker") || combined.contains("echo") ||
               combined.contains("homepod") || combined.contains("soundbar") {
                signals.append(Signal(source: .fingerprint, suggestedType: .speaker, confidence: 0.90))
            }
            
            // Cameras
            if combined.contains("camera") || combined.contains("ring") || combined.contains("nest cam") ||
               combined.contains("arlo") || combined.contains("wyze") {
                signals.append(Signal(source: .fingerprint, suggestedType: .camera, confidence: 0.90))
            }
            
            // Thermostats
            if combined.contains("nest") && combined.contains("thermostat") ||
               combined.contains("ecobee") || combined.contains("thermostat") {
                signals.append(Signal(source: .fingerprint, suggestedType: .thermostat, confidence: 0.90))
            }
            
            // Lights
            if combined.contains("hue") || combined.contains("light") || combined.contains("lifx") ||
               combined.contains("nanoleaf") {
                signals.append(Signal(source: .fingerprint, suggestedType: .light, confidence: 0.85))
            }
            
            // Printers
            if combined.contains("printer") || combined.contains("laserjet") || combined.contains("inkjet") {
                signals.append(Signal(source: .fingerprint, suggestedType: .printer, confidence: 0.95))
            }
            
            // NAS
            if combined.contains("synology") || combined.contains("qnap") || combined.contains("nas") ||
               combined.contains("drobo") {
                signals.append(Signal(source: .fingerprint, suggestedType: .nas, confidence: 0.90))
            }
            
            // Routers
            if combined.contains("router") || combined.contains("gateway") ||
               combined.contains("access point") || combined.contains("wifi") {
                signals.append(Signal(source: .fingerprint, suggestedType: .router, confidence: 0.85))
            }
            
            // Smart plugs
            if combined.contains("wemo") || combined.contains("smart plug") || combined.contains("kasa") {
                signals.append(Signal(source: .fingerprint, suggestedType: .plug, confidence: 0.85))
            }
            
            // Smart hubs
            if combined.contains("hub") || combined.contains("bridge") || combined.contains("smartthings") {
                signals.append(Signal(source: .fingerprint, suggestedType: .hub, confidence: 0.80))
            }
        }
        
        // Check UPnP device type
        if let upnpType = fingerprint.upnpDeviceType?.lowercased() {
            if upnpType.contains("mediarenderer") || upnpType.contains("tv") || upnpType.contains("player") {
                signals.append(Signal(source: .upnp, suggestedType: .smartTV, confidence: 0.85))
            }
            if upnpType.contains("printer") {
                signals.append(Signal(source: .upnp, suggestedType: .printer, confidence: 0.90))
            }
            if upnpType.contains("bridge") || upnpType.contains("hub") {
                signals.append(Signal(source: .upnp, suggestedType: .hub, confidence: 0.85))
            }
            if upnpType.contains("basic") && upnpType.contains("device") {
                // Generic UPnP device - low confidence
                signals.append(Signal(source: .upnp, suggestedType: .hub, confidence: 0.40))
            }
        }
        
        // Check manufacturer
        if let manufacturer = fingerprint.manufacturer?.lowercased() {
            // TV manufacturers
            if manufacturer.contains("roku") || manufacturer.contains("samsung") ||
               manufacturer.contains("lg") || manufacturer.contains("sony") || manufacturer.contains("vizio") ||
               manufacturer.contains("tcl") || manufacturer.contains("hisense") {
                signals.append(Signal(source: .fingerprint, suggestedType: .smartTV, confidence: 0.80))
            }
            
            // Speaker manufacturers
            if manufacturer.contains("sonos") || manufacturer.contains("bose") ||
               manufacturer.contains("harman") || manufacturer.contains("jbl") {
                signals.append(Signal(source: .fingerprint, suggestedType: .speaker, confidence: 0.85))
            }
            
            // Printer manufacturers
            if manufacturer.contains("hp") || manufacturer.contains("canon") ||
               manufacturer.contains("epson") || manufacturer.contains("brother") || manufacturer.contains("xerox") {
                signals.append(Signal(source: .fingerprint, suggestedType: .printer, confidence: 0.80))
            }
            
            // Philips Hue
            if manufacturer.contains("philips") && fingerprint.modelName?.lowercased().contains("hue") == true {
                signals.append(Signal(source: .fingerprint, suggestedType: .hub, confidence: 0.90))
            }
            
            // Apple devices
            if manufacturer.contains("apple") {
                if let model = fingerprint.modelName?.lowercased() {
                    if model.contains("tv") {
                        signals.append(Signal(source: .fingerprint, suggestedType: .smartTV, confidence: 0.95))
                    } else if model.contains("homepod") {
                        signals.append(Signal(source: .fingerprint, suggestedType: .speaker, confidence: 0.95))
                    }
                }
            }
            
            // NAS manufacturers
            if manufacturer.contains("synology") || manufacturer.contains("qnap") ||
               manufacturer.contains("netgear") && fingerprint.modelName?.lowercased().contains("readynas") == true {
                signals.append(Signal(source: .fingerprint, suggestedType: .nas, confidence: 0.90))
            }
            
            // Networking manufacturers
            if manufacturer.contains("ubiquiti") || manufacturer.contains("cisco") ||
               manufacturer.contains("netgear") || manufacturer.contains("tp-link") ||
               manufacturer.contains("asus") || manufacturer.contains("linksys") {
                // Could be router or access point
                signals.append(Signal(source: .fingerprint, suggestedType: .router, confidence: 0.60))
            }
        }
        
        // Check mobile/tablet flags
        if fingerprint.isMobile == true {
            signals.append(Signal(source: .fingerprint, suggestedType: .phone, confidence: 0.90))
        }
        if fingerprint.isTablet == true {
            signals.append(Signal(source: .fingerprint, suggestedType: .tablet, confidence: 0.90))
        }
        
        return signals
    }
    
    /// Create signals from hostname
    /// - Parameter hostname: The device hostname
    /// - Returns: Array of inferred signals
    public func signalsFromHostname(_ hostname: String) -> [Signal] {
        var signals: [Signal] = []
        let lower = hostname.lowercased()
        
        // iPhones
        if lower.contains("iphone") {
            signals.append(Signal(source: .hostname, suggestedType: .phone, confidence: 0.85))
        }
        
        // iPads
        if lower.contains("ipad") {
            signals.append(Signal(source: .hostname, suggestedType: .tablet, confidence: 0.85))
        }
        
        // Macs
        if lower.contains("macbook") || lower.contains("imac") || lower.contains("-mac") ||
           lower.contains("macmini") || lower.contains("macpro") || lower.hasSuffix("s-mac") ||
           lower.hasSuffix("s-mbp") || lower.hasSuffix("s-mba") {
            signals.append(Signal(source: .hostname, suggestedType: .computer, confidence: 0.80))
        }
        
        // Apple TV
        if lower.contains("apple-tv") || lower.contains("appletv") {
            signals.append(Signal(source: .hostname, suggestedType: .smartTV, confidence: 0.90))
        }
        
        // HomePod
        if lower.contains("homepod") {
            signals.append(Signal(source: .hostname, suggestedType: .speaker, confidence: 0.90))
        }
        
        // Roku
        if lower.contains("roku") {
            signals.append(Signal(source: .hostname, suggestedType: .smartTV, confidence: 0.85))
        }
        
        // Chromecast
        if lower.contains("chromecast") || lower.contains("google-home") {
            signals.append(Signal(source: .hostname, suggestedType: .smartTV, confidence: 0.85))
        }
        
        // Sonos
        if lower.contains("sonos") {
            signals.append(Signal(source: .hostname, suggestedType: .speaker, confidence: 0.90))
        }
        
        // Echo / Alexa
        if lower.contains("echo") || lower.contains("alexa") {
            signals.append(Signal(source: .hostname, suggestedType: .speaker, confidence: 0.85))
        }
        
        // Philips Hue
        if lower.contains("hue") || lower.contains("philips-hue") {
            signals.append(Signal(source: .hostname, suggestedType: .hub, confidence: 0.85))
        }
        
        // Ring
        if lower.contains("ring") && (lower.contains("doorbell") || lower.contains("camera")) {
            signals.append(Signal(source: .hostname, suggestedType: .camera, confidence: 0.85))
        }
        
        // Nest
        if lower.contains("nest") {
            if lower.contains("cam") {
                signals.append(Signal(source: .hostname, suggestedType: .camera, confidence: 0.85))
            } else if lower.contains("thermostat") {
                signals.append(Signal(source: .hostname, suggestedType: .thermostat, confidence: 0.85))
            } else {
                // Generic Nest - could be various
                signals.append(Signal(source: .hostname, suggestedType: .thermostat, confidence: 0.50))
            }
        }
        
        // Printers
        if lower.contains("printer") || lower.contains("laserjet") || lower.contains("deskjet") ||
           lower.contains("officejet") || lower.contains("pixma") {
            signals.append(Signal(source: .hostname, suggestedType: .printer, confidence: 0.85))
        }
        
        // NAS
        if lower.contains("nas") || lower.contains("synology") || lower.contains("diskstation") ||
           lower.contains("qnap") {
            signals.append(Signal(source: .hostname, suggestedType: .nas, confidence: 0.85))
        }
        
        // Routers/APs
        if lower.contains("router") || lower.contains("gateway") || lower.contains("ap-") ||
           lower.contains("accesspoint") || lower.contains("unifi") {
            signals.append(Signal(source: .hostname, suggestedType: .router, confidence: 0.75))
        }
        
        // Android devices
        if lower.contains("android") || lower.contains("galaxy") || lower.contains("pixel") {
            signals.append(Signal(source: .hostname, suggestedType: .phone, confidence: 0.75))
        }
        
        // Windows PCs
        if lower.contains("desktop") || lower.contains("laptop") || lower.contains("-pc") {
            signals.append(Signal(source: .hostname, suggestedType: .computer, confidence: 0.70))
        }
        
        // Smart plugs
        if lower.contains("wemo") || lower.contains("kasa") || lower.contains("smart-plug") {
            signals.append(Signal(source: .hostname, suggestedType: .plug, confidence: 0.80))
        }
        
        // Cameras
        if lower.contains("camera") || lower.contains("cam-") || lower.contains("arlo") ||
           lower.contains("wyze") {
            signals.append(Signal(source: .hostname, suggestedType: .camera, confidence: 0.80))
        }
        
        return signals
    }

    /// Create signals from DHCP fingerprint data.
    ///
    /// This method uses the DHCPFingerprintMatcher to analyze DHCP Option 55
    /// fingerprints and generate inference signals.
    ///
    /// - Parameter option55: DHCP Option 55 fingerprint string (e.g., "1,3,6,15,119,252")
    /// - Returns: Array of inferred signals
    public func signalsFromDHCPFingerprint(_ option55: String) async -> [Signal] {
        let matcher = DHCPFingerprintMatcher.shared
        return await matcher.matchAndGenerateSignals(option55: option55)
    }

    /// Create signals from a pre-computed DHCP match result.
    ///
    /// Use this when you already have a match result from DHCPFingerprintMatcher
    /// to avoid duplicate database lookups.
    ///
    /// - Parameter matchResult: A match result from DHCPFingerprintMatcher
    /// - Returns: Array of inferred signals
    public func signalsFromDHCPMatchResult(_ matchResult: DHCPFingerprintMatcher.MatchResult) async -> [Signal] {
        let matcher = DHCPFingerprintMatcher.shared
        return await matcher.generateSignals(from: matchResult)
    }

    // MARK: - Convenience Methods

    /// Infer device type from all available data sources
    /// - Parameters:
    ///   - ssdpServer: SSDP server header
    ///   - ssdpUSN: SSDP USN header
    ///   - ssdpST: SSDP ST header
    ///   - mdnsServiceTypes: Array of mDNS service types
    ///   - openPorts: Array of open port numbers
    ///   - fingerprint: Device fingerprint
    ///   - hostname: Device hostname
    /// - Returns: The most likely device type
    public func inferFromAllSources(
        ssdpServer: String? = nil,
        ssdpUSN: String? = nil,
        ssdpST: String? = nil,
        mdnsServiceTypes: [String]? = nil,
        openPorts: [Int]? = nil,
        fingerprint: DeviceFingerprint? = nil,
        hostname: String? = nil
    ) -> DeviceType {
        var allSignals: [Signal] = []

        // SSDP signals
        allSignals.append(contentsOf: signalsFromSSDPHeaders(server: ssdpServer, usn: ssdpUSN, st: ssdpST))

        // mDNS signals
        if let serviceTypes = mdnsServiceTypes {
            for serviceType in serviceTypes {
                allSignals.append(contentsOf: signalsFromMDNSServiceType(serviceType))
            }
        }

        // Port signals
        if let ports = openPorts {
            for port in ports {
                allSignals.append(contentsOf: signalsFromPort(port))
            }
        }

        // Fingerprint signals
        if let fp = fingerprint {
            allSignals.append(contentsOf: signalsFromFingerprint(fp))
        }

        // Hostname signals
        if let name = hostname {
            allSignals.append(contentsOf: signalsFromHostname(name))
        }

        return infer(signals: allSignals)
    }

    // MARK: - Enhanced Inference with Analyzer Data

    /// Infer device type using enhanced data from analyzers.
    /// Combines traditional signals with parsed mDNS TXT records, port banners, and MAC analysis.
    /// - Parameters:
    ///   - signals: Array of existing signals from discovery
    ///   - mdnsTXTData: Parsed mDNS TXT record data (optional)
    ///   - portBannerData: Parsed port banner data (optional)
    ///   - macAnalysisData: MAC address analysis data (optional)
    /// - Returns: Tuple of (DeviceType, confidence score 0.0-1.0)
    public func inferTypeWithEnhancedData(
        signals: [Signal],
        mdnsTXTData: MDNSTXTData?,
        portBannerData: PortBannerData?,
        macAnalysisData: MACAnalysisData?
    ) async -> (DeviceType, Double) {
        var allSignals = signals

        // Add signals from mDNS TXT data
        if let mdnsData = mdnsTXTData {
            let mdnsSignals = await MDNSTXTRecordAnalyzer.shared.generateSignals(from: mdnsData)
            allSignals.append(contentsOf: mdnsSignals)
            Log.debug("Added \(mdnsSignals.count) signals from mDNS TXT analyzer", category: .mdnsTXT)
        }

        // Add signals from port banner data
        if let bannerData = portBannerData {
            let bannerSignals = await PortBannerGrabber.shared.generateSignals(from: bannerData)
            allSignals.append(contentsOf: bannerSignals)
            Log.debug("Added \(bannerSignals.count) signals from port banner analyzer", category: .portBanner)
        }

        // Add signals from MAC analysis data
        if let macData = macAnalysisData {
            let macSignals = MACAddressAnalyzer.shared.generateSignals(from: macData)
            allSignals.append(contentsOf: macSignals)
            Log.debug("Added \(macSignals.count) signals from MAC address analyzer", category: .macAnalysis)
        }

        // If no signals, return unknown with zero confidence
        guard !allSignals.isEmpty else {
            return (.unknown, 0.0)
        }

        // Aggregate confidence scores per device type
        var typeScores: [DeviceType: Double] = [:]
        var typeCounts: [DeviceType: Int] = [:]

        for signal in allSignals {
            guard signal.suggestedType != .unknown else { continue }

            let baseWeight = Self.sourceWeights[signal.source] ?? 0.5
            let weightedConfidence = signal.confidence * baseWeight

            typeScores[signal.suggestedType, default: 0.0] += weightedConfidence
            typeCounts[signal.suggestedType, default: 0] += 1
        }

        // Find the type with highest score
        guard let bestMatch = typeScores.max(by: { $0.value < $1.value }) else {
            return (.unknown, 0.0)
        }

        // Calculate a normalized confidence score (0.0-1.0)
        // Based on the aggregated score relative to theoretical maximum
        let totalSignals = allSignals.count
        let maxPossibleScore = Double(totalSignals) * 0.9 // Assume max weight is ~0.9
        let normalizedConfidence = min(1.0, bestMatch.value / max(1.0, maxPossibleScore))

        Log.info("Enhanced inference result: \(bestMatch.key.rawValue) with confidence \(String(format: "%.2f", normalizedConfidence)) from \(allSignals.count) signals", category: .discovery)

        return (bestMatch.key, normalizedConfidence)
    }

    /// Infer device type with enhanced data and return just the type (convenience wrapper)
    /// - Parameters:
    ///   - signals: Array of existing signals from discovery
    ///   - mdnsTXTData: Parsed mDNS TXT record data (optional)
    ///   - portBannerData: Parsed port banner data (optional)
    ///   - macAnalysisData: MAC address analysis data (optional)
    /// - Returns: The most likely device type
    public func inferWithEnhancedData(
        signals: [Signal],
        mdnsTXTData: MDNSTXTData?,
        portBannerData: PortBannerData?,
        macAnalysisData: MACAnalysisData?
    ) async -> DeviceType {
        let (deviceType, _) = await inferTypeWithEnhancedData(
            signals: signals,
            mdnsTXTData: mdnsTXTData,
            portBannerData: portBannerData,
            macAnalysisData: macAnalysisData
        )
        return deviceType
    }
}
