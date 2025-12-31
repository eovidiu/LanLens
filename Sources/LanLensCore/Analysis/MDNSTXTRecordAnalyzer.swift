import Foundation

/// Analyzes mDNS TXT records to extract device identification data.
/// Parses AirPlay, Google Cast, HomeKit, and RAOP service TXT records
/// and generates inference signals for device type determination.
public actor MDNSTXTRecordAnalyzer {
    
    // MARK: - Singleton
    
    public static let shared = MDNSTXTRecordAnalyzer()
    
    private init() {}

    // MARK: - Bounded Integer Parsing Helpers

    /// Parses a UInt64 from string with optional maximum bound.
    /// Logs a warning if the value exceeds the expected maximum.
    /// - Parameters:
    ///   - string: The string to parse
    ///   - max: Maximum expected value (default: UInt64.max)
    ///   - fieldName: Name of the field for logging purposes
    /// - Returns: The parsed value if valid, nil otherwise
    private func parseUInt64(_ string: String, max: UInt64 = UInt64.max, fieldName: String = "unknown") -> UInt64? {
        guard let value = UInt64(string) else {
            Log.debug("Failed to parse UInt64 for field '\(fieldName)': '\(string)'", category: .mdnsTXT)
            return nil
        }
        if value > max {
            Log.warning("Value \(value) for field '\(fieldName)' exceeds expected maximum \(max)", category: .mdnsTXT)
        }
        return value
    }

    /// Parses an Int from string with optional bounds.
    /// Logs a warning if the value is outside the expected range.
    /// - Parameters:
    ///   - string: The string to parse
    ///   - min: Minimum expected value (default: Int.min)
    ///   - max: Maximum expected value (default: Int.max)
    ///   - fieldName: Name of the field for logging purposes
    /// - Returns: The parsed value if valid and within bounds, nil otherwise
    private func parseInt(_ string: String, min: Int = Int.min, max: Int = Int.max, fieldName: String = "unknown") -> Int? {
        guard let value = Int(string) else {
            Log.debug("Failed to parse Int for field '\(fieldName)': '\(string)'", category: .mdnsTXT)
            return nil
        }
        if value < min || value > max {
            Log.warning("Value \(value) for field '\(fieldName)' outside expected range [\(min), \(max)]", category: .mdnsTXT)
            return nil
        }
        return value
    }

    /// Parses a port number (1-65535) from string.
    /// - Parameters:
    ///   - string: The string to parse
    ///   - fieldName: Name of the field for logging purposes
    /// - Returns: The parsed port if valid, nil otherwise
    private func parsePort(_ string: String, fieldName: String = "port") -> Int? {
        return parseInt(string, min: 1, max: 65535, fieldName: fieldName)
    }

    /// Parses a percentage value (0-100) from string.
    /// - Parameters:
    ///   - string: The string to parse
    ///   - fieldName: Name of the field for logging purposes
    /// - Returns: The parsed percentage if valid, nil otherwise
    private func parsePercentage(_ string: String, fieldName: String = "percentage") -> Int? {
        return parseInt(string, min: 0, max: 100, fieldName: fieldName)
    }

    // MARK: - Service Type Constants
    
    private enum ServiceType {
        static let airplay = "_airplay._tcp"
        static let googlecast = "_googlecast._tcp"
        static let homekit = "_hap._tcp"
        static let raop = "_raop._tcp"
    }
    
    // MARK: - Public Methods
    
    /// Analyzes TXT records for a given service type and returns parsed data.
    /// - Parameters:
    ///   - serviceType: The mDNS service type (e.g., "_airplay._tcp")
    ///   - txtRecords: Dictionary of TXT record key-value pairs
    /// - Returns: Parsed MDNSTXTData containing service-specific information
    public func analyze(serviceType: String, txtRecords: [String: String]) -> MDNSTXTData {
        Log.debug("Analyzing TXT records for service: \(serviceType), keys: \(txtRecords.keys.joined(separator: ", "))", category: .mdnsTXT)
        
        var data = MDNSTXTData()
        
        // Store raw records with size limits enforced
        data.addRawRecords(serviceType: serviceType, records: txtRecords)
        
        // Parse based on service type
        switch serviceType.lowercased() {
        case ServiceType.airplay:
            data.airplay = parseAirPlayTXT(txtRecords)
            Log.info("Parsed AirPlay TXT: model=\(data.airplay?.model ?? "nil")", category: .mdnsTXT)
            
        case ServiceType.googlecast:
            data.googleCast = parseGoogleCastTXT(txtRecords)
            Log.info("Parsed Google Cast TXT: model=\(data.googleCast?.modelName ?? "nil"), name=\(data.googleCast?.friendlyName ?? "nil")", category: .mdnsTXT)
            
        case ServiceType.homekit:
            data.homeKit = parseHomeKitTXT(txtRecords)
            Log.info("Parsed HomeKit TXT: category=\(data.homeKit?.category?.displayName ?? "nil"), paired=\(data.homeKit?.isPaired ?? false)", category: .mdnsTXT)
            
        case ServiceType.raop:
            data.raop = parseRAOPTXT(txtRecords)
            Log.info("Parsed RAOP TXT: model=\(data.raop?.model ?? "nil")", category: .mdnsTXT)
            
        default:
            Log.debug("Unknown service type for TXT parsing: \(serviceType)", category: .mdnsTXT)
        }
        
        return data
    }
    
    /// Generates inference signals from parsed mDNS TXT data.
    /// - Parameter data: The parsed MDNSTXTData
    /// - Returns: Array of signals for device type inference
    public func generateSignals(from data: MDNSTXTData) -> [DeviceTypeInferenceEngine.Signal] {
        var signals: [DeviceTypeInferenceEngine.Signal] = []
        
        // Generate signals from AirPlay data
        if let airplay = data.airplay {
            signals.append(contentsOf: signalsFromAirPlay(airplay))
        }
        
        // Generate signals from Google Cast data
        if let googleCast = data.googleCast {
            signals.append(contentsOf: signalsFromGoogleCast(googleCast))
        }
        
        // Generate signals from HomeKit data
        if let homeKit = data.homeKit {
            signals.append(contentsOf: signalsFromHomeKit(homeKit))
        }
        
        // Generate signals from RAOP data
        if let raop = data.raop {
            signals.append(contentsOf: signalsFromRAOP(raop))
        }
        
        Log.debug("Generated \(signals.count) signals from mDNS TXT data", category: .mdnsTXT)
        return signals
    }
    
    // MARK: - AirPlay Parsing
    
    private func parseAirPlayTXT(_ records: [String: String]) -> AirPlayTXTData {
        var airplay = AirPlayTXTData()
        
        // Parse model identifier (e.g., "AppleTV5,3")
        airplay.model = records["model"]
        
        // Parse device ID
        airplay.deviceId = records["deviceid"]
        
        // Parse source version
        airplay.sourceVersion = records["srcvers"]
        
        // Parse protocol version
        airplay.protocolVersion = records["vv"] ?? records["pk"]
        
        // Parse OS build version
        airplay.osBuildVersion = records["osvers"]
        
        // Parse flags (UInt64 bitmask - log if suspiciously large but allow any valid UInt64)
        if let flagsStr = records["flags"], let flags = parseUInt64(flagsStr, fieldName: "AirPlay flags") {
            airplay.flags = flags
        }
        
        // Parse features bitmask
        if let featuresStr = records["features"] {
            airplay.features = parseAirPlayFeatures(featuresStr)
            
            // Determine capabilities from features
            airplay.supportsAirPlay2 = airplay.features.contains(.supportsBufferedAudio)
            airplay.supportsScreenMirroring = airplay.features.contains(.screen) || airplay.features.contains(.supportsScreenStream)
            airplay.isAudioOnly = !airplay.supportsScreenMirroring && airplay.features.contains(.audio)
        }
        
        return airplay
    }
    
    private func parseAirPlayFeatures(_ featuresStr: String) -> Set<AirPlayFeature> {
        var features = Set<AirPlayFeature>()
        
        // Features can be a hex string like "0x5A7FFFF7,0x1E" (comma-separated for high/low bits)
        // or a single hex value
        let components = featuresStr.split(separator: ",")
        var combined: UInt64 = 0
        
        for (index, component) in components.enumerated() {
            let cleanHex = component.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "0x", with: "")
                .replacingOccurrences(of: "0X", with: "")

            if let value = UInt64(cleanHex, radix: 16) {
                if index == 0 {
                    combined = value
                } else {
                    // Second component is high bits
                    combined |= (value << 32)
                }
            } else {
                Log.debug("Failed to parse AirPlay features hex component '\(cleanHex)' at index \(index)", category: .mdnsTXT)
            }
        }

        // Map feature bits to AirPlayFeature enum
        // Based on Apple AirPlay feature flags
        if combined & (1 << 0) != 0 { features.insert(.video) }
        if combined & (1 << 1) != 0 { features.insert(.photo) }
        if combined & (1 << 5) != 0 { features.insert(.slideshow) }
        if combined & (1 << 7) != 0 { features.insert(.screen) }
        if combined & (1 << 8) != 0 { features.insert(.screenRotate) }
        if combined & (1 << 9) != 0 { features.insert(.audio) }
        if combined & (1 << 11) != 0 { features.insert(.audioRedundant) }
        if combined & (1 << 12) != 0 { features.insert(.ftpDataChunkedSend) }
        if combined & (1 << 14) != 0 { features.insert(.authentication) }
        if combined & (1 << 15) != 0 { features.insert(.metadataFeatures) }
        if combined & (1 << 16) != 0 { features.insert(.audioFormat) }
        if combined & (1 << 17) != 0 { features.insert(.playbackQueue) }
        if combined & (1 << 18) != 0 { features.insert(.hudSupported) }
        if combined & (1 << 26) != 0 { features.insert(.mfiCert) }
        if combined & (1 << 27) != 0 { features.insert(.carPlay) }
        if combined & (1 << 38) != 0 { features.insert(.supportsUnifiedMediaControl) }
        if combined & (1 << 40) != 0 { features.insert(.supportsBufferedAudio) }
        if combined & (1 << 41) != 0 { features.insert(.supportsPTP) }
        if combined & (1 << 42) != 0 { features.insert(.supportsScreenStream) }
        if combined & (1 << 44) != 0 { features.insert(.supportsVolume) }
        if combined & (1 << 46) != 0 { features.insert(.supportsHKPairing) }
        if combined & (1 << 48) != 0 { features.insert(.supportsSystemPairing) }
        if combined & (1 << 50) != 0 { features.insert(.supportsCoreUtils) }
        if combined & (1 << 51) != 0 { features.insert(.supportsCoreUtilsScreenLock) }
        
        return features
    }
    
    // MARK: - Google Cast Parsing
    
    private func parseGoogleCastTXT(_ records: [String: String]) -> GoogleCastTXTData {
        var cast = GoogleCastTXTData()
        
        // Parse model name (md = model description)
        cast.modelName = records["md"]
        
        // Parse friendly name (fn = friendly name)
        cast.friendlyName = records["fn"]
        
        // Parse device ID
        cast.id = records["id"]
        
        // Parse firmware version (ve = version)
        cast.firmwareVersion = records["ve"]
        
        // Parse cast version (ca = cast version/capabilities bitmask)
        // Note: "ca" is a capabilities bitmask, not a port number. Valid range is 0-65535.
        if let caStr = records["ca"], let ca = parseInt(caStr, min: 0, max: 65535, fieldName: "GoogleCast ca (capabilities)") {
            cast.castVersion = ca
            cast.capabilities = ca
        }

        // Parse receiver status (rs = receiver status, typically small integer)
        if let rsStr = records["rs"], let rs = parseInt(rsStr, min: 0, max: 255, fieldName: "GoogleCast rs (receiver status)") {
            cast.receiverStatus = rs
        }
        
        // Parse icon path
        cast.iconPath = records["ic"]
        
        // Determine if built-in (e.g., TV with Chromecast)
        if let bs = records["bs"] {
            cast.isBuiltIn = bs == "1" || bs.lowercased() == "true"
        }
        
        // Determine group support (st = status, typically 0 or 1)
        if let st = records["st"] {
            cast.supportsGroups = st == "1" || (parseInt(st, min: 0, max: 255, fieldName: "GoogleCast st (status)") ?? 0) > 0
        }
        
        return cast
    }
    
    // MARK: - HomeKit Parsing
    
    private func parseHomeKitTXT(_ records: [String: String]) -> HomeKitTXTData {
        var homeKit = HomeKitTXTData()
        
        // Parse category ID (ci = category identifier, HAP spec defines values 1-31)
        if let ciStr = records["ci"], let ci = parseInt(ciStr, min: 1, max: 255, fieldName: "HomeKit ci (category)") {
            homeKit.categoryRaw = ci
            homeKit.category = HomeKitCategory(rawValue: ci)
        }

        // Parse status flags (sf = status flags, typically 0 or 1 for pairing status)
        // Bit 0: Not paired (1 = not paired, 0 = paired)
        if let sfStr = records["sf"], let sf = parseInt(sfStr, min: 0, max: 255, fieldName: "HomeKit sf (status flags)") {
            homeKit.statusFlags = sf
            homeKit.isPaired = (sf & 0x01) == 0  // Bit 0 = 0 means paired
        }

        // Parse configuration number (c# = config number, incrementing counter)
        if let cStr = records["c#"], let c = parseInt(cStr, min: 1, max: Int.max, fieldName: "HomeKit c# (config number)") {
            homeKit.configurationNumber = c
        }

        // Parse device ID
        homeKit.deviceId = records["id"]

        // Parse state number (s# = state number, incrementing counter)
        if let sStr = records["s#"], let s = parseInt(sStr, min: 1, max: Int.max, fieldName: "HomeKit s# (state number)") {
            homeKit.stateNumber = s
        }

        // Parse feature flags (ff = feature flags, bitmask)
        if let ffStr = records["ff"], let ff = parseInt(ffStr, min: 0, max: 255, fieldName: "HomeKit ff (feature flags)") {
            homeKit.featureFlags = ff
            // Bit 0: Supports HAP over IP
            // Bit 1: Supports HAP over BLE
            homeKit.supportsIP = (ff & 0x01) != 0
            homeKit.supportsBLE = (ff & 0x02) != 0
        } else {
            // Default to IP support if no feature flags
            homeKit.supportsIP = true
        }
        
        // Parse protocol version (pv = protocol version)
        homeKit.protocolVersion = records["pv"]
        
        // Parse model name (md = model description)
        homeKit.modelName = records["md"]
        
        return homeKit
    }
    
    // MARK: - RAOP Parsing
    
    private func parseRAOPTXT(_ records: [String: String]) -> RAOPTXTData {
        var raop = RAOPTXTData()
        
        // Parse Apple model (am = Apple model)
        raop.model = records["am"]
        
        // Parse audio formats (cn = audio codecs)
        raop.audioFormats = records["cn"]
        
        // Parse compression types (et = encryption types, sometimes used for compression)
        raop.compressionTypes = records["tp"]
        
        // Parse encryption types
        raop.encryptionTypes = records["et"]
        
        // Parse metadata types (md = metadata types, different from model)
        raop.metadataTypes = records["md"]
        
        // Parse transport protocols (tp = transport protocols)
        raop.transportProtocols = records["tp"]
        
        // Parse protocol version (vs = version)
        raop.protocolVersion = records["vs"]

        // Parse status flags (sf = status flags, bitmask)
        if let sfStr = records["sf"], let sf = parseInt(sfStr, min: 0, max: Int.max, fieldName: "RAOP sf (status flags)") {
            raop.statusFlags = sf
        }
        
        // Parse features to determine audio quality support
        if let ftStr = records["ft"] {
            let features = parseRAOPFeatures(ftStr)
            // Check for lossless and high-resolution support
            // Based on RAOP feature flags
            raop.supportsLossless = features & (1 << 30) != 0
            raop.supportsHighResolution = features & (1 << 31) != 0
        }
        
        return raop
    }
    
    private func parseRAOPFeatures(_ featuresStr: String) -> UInt64 {
        let components = featuresStr.split(separator: ",")
        var combined: UInt64 = 0

        for (index, component) in components.enumerated() {
            let cleanHex = component.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "0x", with: "")
                .replacingOccurrences(of: "0X", with: "")

            if let value = UInt64(cleanHex, radix: 16) {
                if index == 0 {
                    combined = value
                } else {
                    combined |= (value << 32)
                }
            } else {
                Log.debug("Failed to parse RAOP features hex component '\(cleanHex)' at index \(index)", category: .mdnsTXT)
            }
        }

        return combined
    }
    
    // MARK: - Signal Generation
    
    private func signalsFromAirPlay(_ airplay: AirPlayTXTData) -> [DeviceTypeInferenceEngine.Signal] {
        var signals: [DeviceTypeInferenceEngine.Signal] = []
        
        if let model = airplay.model?.lowercased() {
            // Apple TV detection
            if model.contains("appletv") {
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .mdnsTXT,
                    suggestedType: .smartTV,
                    confidence: 0.95
                ))
                Log.debug("AirPlay signal: Apple TV detected from model '\(model)'", category: .mdnsTXT)
            }
            // HomePod detection
            else if model.contains("homepod") || model.contains("audioaccessory") {
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .mdnsTXT,
                    suggestedType: .speaker,
                    confidence: 0.95
                ))
                Log.debug("AirPlay signal: HomePod detected from model '\(model)'", category: .mdnsTXT)
            }
            // MacBook/Mac detection
            else if model.contains("macbook") || model.contains("mac") || model.contains("imac") {
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .mdnsTXT,
                    suggestedType: .computer,
                    confidence: 0.90
                ))
                Log.debug("AirPlay signal: Mac detected from model '\(model)'", category: .mdnsTXT)
            }
            // iPad detection
            else if model.contains("ipad") {
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .mdnsTXT,
                    suggestedType: .tablet,
                    confidence: 0.90
                ))
                Log.debug("AirPlay signal: iPad detected from model '\(model)'", category: .mdnsTXT)
            }
            // iPhone detection
            else if model.contains("iphone") {
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .mdnsTXT,
                    suggestedType: .phone,
                    confidence: 0.90
                ))
                Log.debug("AirPlay signal: iPhone detected from model '\(model)'", category: .mdnsTXT)
            }
            // AirPort Express (audio-only AirPlay)
            else if model.contains("airport") {
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .mdnsTXT,
                    suggestedType: .hub,
                    confidence: 0.85
                ))
                Log.debug("AirPlay signal: AirPort detected from model '\(model)'", category: .mdnsTXT)
            }
        }
        
        // Additional detection based on capabilities
        if airplay.isAudioOnly && signals.isEmpty {
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .mdnsTXT,
                suggestedType: .speaker,
                confidence: 0.70
            ))
            Log.debug("AirPlay signal: Audio-only device detected", category: .mdnsTXT)
        }
        
        return signals
    }
    
    private func signalsFromGoogleCast(_ googleCast: GoogleCastTXTData) -> [DeviceTypeInferenceEngine.Signal] {
        var signals: [DeviceTypeInferenceEngine.Signal] = []
        
        if let model = googleCast.modelName?.lowercased() {
            // Chromecast detection
            if model.contains("chromecast") {
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .mdnsTXT,
                    suggestedType: .smartTV,
                    confidence: 0.95
                ))
                Log.debug("Google Cast signal: Chromecast detected from model '\(model)'", category: .mdnsTXT)
            }
            // Google Home / Nest Audio speakers
            else if model.contains("google home") || model.contains("nest audio") || 
                    model.contains("home mini") || model.contains("home max") ||
                    model.contains("nest mini") {
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .mdnsTXT,
                    suggestedType: .speaker,
                    confidence: 0.90
                ))
                Log.debug("Google Cast signal: Google/Nest speaker detected from model '\(model)'", category: .mdnsTXT)
            }
            // Nest Hub displays
            else if model.contains("nest hub") || model.contains("home hub") {
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .mdnsTXT,
                    suggestedType: .smartTV,
                    confidence: 0.85
                ))
                Log.debug("Google Cast signal: Nest Hub detected from model '\(model)'", category: .mdnsTXT)
            }
            // Generic TV with Cast built-in
            else if googleCast.isBuiltIn {
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .mdnsTXT,
                    suggestedType: .smartTV,
                    confidence: 0.85
                ))
                Log.debug("Google Cast signal: Built-in Cast TV detected", category: .mdnsTXT)
            }
        } else if googleCast.isBuiltIn {
            // Built-in Cast without model name
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .mdnsTXT,
                suggestedType: .smartTV,
                confidence: 0.80
            ))
            Log.debug("Google Cast signal: Built-in Cast device detected (no model)", category: .mdnsTXT)
        }
        
        return signals
    }
    
    private func signalsFromHomeKit(_ homeKit: HomeKitTXTData) -> [DeviceTypeInferenceEngine.Signal] {
        var signals: [DeviceTypeInferenceEngine.Signal] = []
        
        if let category = homeKit.category {
            // Use the category suggested device type
            let deviceType = category.suggestedDeviceType
            
            // Higher confidence for specific categories
            let confidence: Double
            switch category {
            case .appleTv, .homePod, .speaker, .television:
                confidence = 0.95
            case .ipCamera, .videoDoorbell:
                confidence = 0.95
            case .thermostat, .heater, .airConditioner:
                confidence = 0.95
            case .lightbulb, .switch, .outlet:
                confidence = 0.90
            case .doorLock, .garageDoorOpener:
                confidence = 0.90
            case .bridge, .wifiRouter, .airport:
                confidence = 0.90
            case .sensor, .programmableSwitch:
                confidence = 0.80
            default:
                confidence = 0.80
            }
            
            if deviceType != .unknown {
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .mdnsTXT,
                    suggestedType: deviceType,
                    confidence: confidence
                ))
                Log.debug("HomeKit signal: \(category.displayName) -> \(deviceType) with confidence \(confidence)", category: .mdnsTXT)
            }
        }
        
        return signals
    }
    
    private func signalsFromRAOP(_ raop: RAOPTXTData) -> [DeviceTypeInferenceEngine.Signal] {
        var signals: [DeviceTypeInferenceEngine.Signal] = []
        
        if let model = raop.model?.lowercased() {
            // Apple TV detection
            if model.contains("appletv") {
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .mdnsTXT,
                    suggestedType: .smartTV,
                    confidence: 0.95
                ))
                Log.debug("RAOP signal: Apple TV detected from model '\(model)'", category: .mdnsTXT)
            }
            // HomePod detection
            else if model.contains("homepod") || model.contains("audioaccessory") {
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .mdnsTXT,
                    suggestedType: .speaker,
                    confidence: 0.95
                ))
                Log.debug("RAOP signal: HomePod detected from model '\(model)'", category: .mdnsTXT)
            }
            // AirPort Express
            else if model.contains("airport") {
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .mdnsTXT,
                    suggestedType: .hub,
                    confidence: 0.85
                ))
                Log.debug("RAOP signal: AirPort detected from model '\(model)'", category: .mdnsTXT)
            }
            // Mac detection
            else if model.contains("macbook") || model.contains("mac") || model.contains("imac") {
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .mdnsTXT,
                    suggestedType: .computer,
                    confidence: 0.90
                ))
                Log.debug("RAOP signal: Mac detected from model '\(model)'", category: .mdnsTXT)
            }
        }
        
        // If no model but RAOP is present, likely an audio receiver
        if signals.isEmpty {
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .mdnsTXT,
                suggestedType: .speaker,
                confidence: 0.60
            ))
            Log.debug("RAOP signal: Generic audio receiver detected", category: .mdnsTXT)
        }
        
        return signals
    }
}
