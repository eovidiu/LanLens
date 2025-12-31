import Foundation

/// Analyzes MAC addresses for additional device insights including
/// randomization detection, virtual machine identification, and vendor age estimation.
public final class MACAddressAnalyzer: Sendable {
    
    // MARK: - Singleton
    
    public static let shared = MACAddressAnalyzer()
    
    private init() {}
    
    // MARK: - Known VM OUIs
    
    /// OUI prefixes known to be used by virtual machines
    private static let vmOUIs: Set<String> = [
        "00:0C:29", "00:50:56",  // VMware
        "00:1C:42",              // Parallels
        "00:03:FF",              // Microsoft Hyper-V
        "08:00:27",              // VirtualBox
        "52:54:00",              // QEMU/KVM
        "00:16:3E",              // Xen
    ]
    
    // MARK: - Vendor Classifications
    
    /// Legacy vendors (pre-2000) - older enterprise and networking equipment
    private static let legacyVendors: Set<String> = [
        "3com", "novell", "dec", "sgi", "digital", "cabletron",
        "compaq", "proteon", "ungermann-bass", "wellfleet"
    ]
    
    /// Established vendors (2000-2015) - major networking and computer manufacturers
    private static let establishedVendors: Set<String> = [
        "cisco", "hp", "dell", "netgear", "linksys", "d-link",
        "buffalo", "zyxel", "juniper", "aruba", "motorola"
    ]
    
    /// Modern vendors (2015-2020) - IoT and smart home pioneers
    private static let modernVendors: Set<String> = [
        "ubiquiti", "ring", "nest", "wemo", "belkin", "lifx",
        "ecobee", "august", "arlo", "dropcam", "canary"
    ]
    
    /// Recent vendors (2020+) - newer smart home brands
    private static let recentVendors: Set<String> = [
        "wyze", "eufy", "meross", "govee", "switchbot", "tuya",
        "shelly", "tapo", "kasa"
    ]
    
    /// High confidence vendors - major well-known brands
    private static let highConfidenceVendors: Set<String> = [
        "apple", "samsung", "google", "amazon", "sony", "lg",
        "microsoft", "intel", "nvidia", "amd", "dell", "hp",
        "lenovo", "asus", "cisco", "netgear", "ubiquiti"
    ]
    
    /// Medium confidence vendors - recognized brands
    private static let mediumConfidenceVendors: Set<String> = [
        "tp-link", "d-link", "zyxel", "buffalo", "belkin",
        "linksys", "arris", "motorola", "huawei", "xiaomi",
        "roku", "sonos", "philips", "nest", "ring", "ecobee",
        "honeywell", "lutron", "synology", "qnap", "raspberry pi"
    ]
    
    // MARK: - Vendor Device Category Mappings
    
    /// Maps vendor names to their typical device categories
    private static let vendorDeviceCategories: [String: [DeviceType]] = [
        "apple": [.phone, .tablet, .computer, .smartTV, .speaker, .accessPoint],
        "samsung": [.phone, .tablet, .smartTV, .appliance],
        "google": [.phone, .smartTV, .speaker, .thermostat, .hub],
        "google nest": [.thermostat, .speaker, .camera, .hub],
        "amazon": [.speaker, .smartTV, .tablet, .hub],
        "ring": [.camera],
        "sony": [.smartTV, .speaker, .camera],
        "lg": [.smartTV, .appliance],
        "roku": [.smartTV],
        "sonos": [.speaker],
        "philips hue": [.light, .hub],
        "philips": [.smartTV, .light],
        "nest": [.thermostat, .camera, .speaker],
        "ecobee": [.thermostat],
        "ubiquiti": [.router, .accessPoint, .camera],
        "cisco": [.router, .accessPoint, .hub],
        "netgear": [.router, .accessPoint, .nas],
        "tp-link": [.router, .accessPoint, .plug],
        "tp-link kasa": [.plug, .light],
        "linksys": [.router, .accessPoint],
        "asus": [.router, .computer],
        "synology": [.nas],
        "qnap": [.nas],
        "hp": [.printer, .computer],
        "dell": [.computer],
        "intel": [.computer],
        "raspberry pi": [.computer, .hub],
        "espressif": [.plug, .light, .appliance],  // ESP8266/ESP32 IoT chips
        "tuya": [.plug, .light, .appliance],
        "wyze": [.camera, .plug, .light],
        "arlo": [.camera],
        "logitech": [.camera, .computer],
        "august": [.appliance],  // Smart locks
        "schlage": [.appliance],
        "honeywell": [.thermostat, .appliance],
        "lutron": [.light, .hub],
        "lifx": [.light],
        "nanoleaf": [.light],
        "yeelight": [.light],
        "belkin": [.plug, .router],
        "belkin wemo": [.plug],
        "simplisafe": [.hub, .camera],
        "xiaomi": [.phone, .appliance, .camera],
    ]
    
    /// Vendors that specialize in a single device type
    private static let vendorSpecializations: [String: DeviceType] = [
        "sonos": .speaker,
        "roku": .smartTV,
        "ecobee": .thermostat,
        "ring": .camera,
        "arlo": .camera,
        "synology": .nas,
        "qnap": .nas,
        "philips hue": .light,
        "lifx": .light,
        "nanoleaf": .light,
        "yeelight": .light,
        "august": .appliance,
        "schlage": .appliance,
        "simplisafe": .hub,
    ]
    
    // MARK: - Public Methods
    
    /// Analyze a MAC address for additional device insights
    /// - Parameters:
    ///   - mac: The MAC address to analyze
    ///   - vendor: Optional vendor name from OUI lookup
    /// - Returns: MACAnalysisData containing analysis results
    public func analyze(mac: String, vendor: String?) -> MACAnalysisData {
        let normalizedOUI = normalizeOUI(mac)
        let firstByte = parseFirstByte(mac)
        
        // Check for locally administered / randomized MAC
        let isLocallyAdministered = (firstByte & 0x02) != 0
        let isMulticast = (firstByte & 0x01) != 0
        let isRandomized = isLocallyAdministered && !isMulticast
        
        Log.debug("MAC analysis: \(mac) -> OUI=\(normalizedOUI) LA=\(isLocallyAdministered) MC=\(isMulticast) Random=\(isRandomized)", category: .macAnalysis)
        
        // Determine vendor confidence
        let vendorConfidence = determineVendorConfidence(
            vendor: vendor,
            oui: normalizedOUI,
            isRandomized: isRandomized
        )
        
        // Get vendor categories and specialization
        let (categories, specialization) = getVendorDeviceInfo(vendor: vendor)
        
        // Estimate OUI age
        let ageEstimate = estimateOUIAge(vendor: vendor, oui: normalizedOUI)
        
        // Check for VM
        let isVM = Self.vmOUIs.contains(normalizedOUI)
        if isVM {
            Log.info("MAC \(mac) identified as virtual machine OUI", category: .macAnalysis)
        }
        
        return MACAnalysisData(
            oui: normalizedOUI,
            vendor: vendor,
            isLocallyAdministered: isLocallyAdministered,
            isRandomized: isRandomized,
            ageEstimate: ageEstimate,
            vendorConfidence: vendorConfidence,
            vendorCategories: categories,
            vendorSpecialization: specialization
        )
    }
    
    /// Generate inference signals from MAC analysis data
    /// - Parameter data: The MACAnalysisData to generate signals from
    /// - Returns: Array of signals for the DeviceTypeInferenceEngine
    public func generateSignals(from data: MACAnalysisData) -> [DeviceTypeInferenceEngine.Signal] {
        var signals: [DeviceTypeInferenceEngine.Signal] = []
        
        // Randomized MAC strongly suggests mobile device
        if data.isRandomized {
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .macAnalysis,
                suggestedType: .phone,
                confidence: 0.60
            ))
            Log.debug("Generated phone signal (0.60) for randomized MAC", category: .macAnalysis)
        }
        
        // VM OUI strongly suggests computer
        if isVirtualMachineOUI(data.oui) {
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .macAnalysis,
                suggestedType: .computer,
                confidence: 0.85
            ))
            Log.debug("Generated computer signal (0.85) for VM OUI \(data.oui)", category: .macAnalysis)
        }
        
        // Legacy OUI suggests router or old network equipment
        if data.ageEstimate == .legacy {
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .macAnalysis,
                suggestedType: .router,
                confidence: 0.40
            ))
            Log.debug("Generated router signal (0.40) for legacy OUI", category: .macAnalysis)
        }
        
        // Add signals for vendor specialization
        if let specialization = data.vendorSpecialization,
           data.vendorConfidence == .high || data.vendorConfidence == .medium {
            let confidence: Double = data.vendorConfidence == .high ? 0.70 : 0.55
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .macAnalysis,
                suggestedType: specialization,
                confidence: confidence
            ))
            Log.debug("Generated \(specialization.rawValue) signal (\(confidence)) for vendor specialization", category: .macAnalysis)
        }
        
        // Add signals for single-category vendors with high confidence
        if data.vendorCategories.count == 1,
           let singleCategory = data.vendorCategories.first,
           data.vendorConfidence == .high {
            // Only add if we haven't already added a specialization signal for the same type
            if data.vendorSpecialization != singleCategory {
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .macAnalysis,
                    suggestedType: singleCategory,
                    confidence: 0.65
                ))
                Log.debug("Generated \(singleCategory.rawValue) signal (0.65) for single-category vendor", category: .macAnalysis)
            }
        }
        
        return signals
    }
    
    // MARK: - Private Helpers
    
    /// Normalize MAC address to OUI format (first 3 bytes, uppercase, colon-separated)
    private func normalizeOUI(_ mac: String) -> String {
        // Clean the MAC address
        let cleaned = mac.uppercased()
            .replacingOccurrences(of: "-", with: ":")
            .replacingOccurrences(of: ".", with: "")
        
        // Split by colons if present
        var components: [String]
        if cleaned.contains(":") {
            components = cleaned.components(separatedBy: ":").prefix(3).map { component in
                if component.count == 1 {
                    return "0" + component
                }
                return String(component.prefix(2))
            }
        } else {
            // No separators - assume pairs of hex digits
            var pairs: [String] = []
            var remaining = cleaned
            while !remaining.isEmpty && pairs.count < 3 {
                let end = remaining.index(remaining.startIndex, offsetBy: min(2, remaining.count))
                var pair = String(remaining[..<end])
                if pair.count == 1 {
                    pair = "0" + pair
                }
                pairs.append(pair)
                remaining = String(remaining[end...])
            }
            components = pairs
        }
        
        // Ensure we have 3 components
        while components.count < 3 {
            components.append("00")
        }
        
        return components.map { $0.padding(toLength: 2, withPad: "0", startingAt: 0) }.joined(separator: ":")
    }
    
    /// Parse the first byte of a MAC address
    private func parseFirstByte(_ mac: String) -> UInt8 {
        let cleaned = mac.uppercased()
            .replacingOccurrences(of: "-", with: ":")
            .replacingOccurrences(of: ".", with: "")
        
        let firstComponent: String
        if cleaned.contains(":") {
            firstComponent = String(cleaned.components(separatedBy: ":").first ?? "00")
        } else {
            firstComponent = String(cleaned.prefix(2))
        }
        
        // Pad if needed
        let padded = firstComponent.count == 1 ? "0" + firstComponent : firstComponent
        return UInt8(padded, radix: 16) ?? 0
    }
    
    /// Check if an OUI belongs to a virtual machine
    private func isVirtualMachineOUI(_ oui: String) -> Bool {
        Self.vmOUIs.contains(oui)
    }
    
    /// Determine the confidence level for a vendor identification
    private func determineVendorConfidence(vendor: String?, oui: String, isRandomized: Bool) -> VendorConfidence {
        // Randomized MACs have their own confidence level
        if isRandomized {
            return .randomized
        }
        
        // No vendor means unknown
        guard let vendor = vendor else {
            return .unknown
        }
        
        let vendorLower = vendor.lowercased()
        
        // Check for high confidence vendors
        for highVendor in Self.highConfidenceVendors {
            if vendorLower.contains(highVendor) {
                return .high
            }
        }
        
        // Check for medium confidence vendors
        for mediumVendor in Self.mediumConfidenceVendors {
            if vendorLower.contains(mediumVendor) {
                return .medium
            }
        }
        
        // Known vendor but not in our lists = low confidence
        return .low
    }
    
    /// Get device categories and specialization for a vendor
    private func getVendorDeviceInfo(vendor: String?) -> ([DeviceType], DeviceType?) {
        guard let vendor = vendor else {
            return ([], nil)
        }
        
        let vendorLower = vendor.lowercased()
        
        // First check for exact matches in specializations
        for (key, specialization) in Self.vendorSpecializations {
            if vendorLower.contains(key) {
                let categories = Self.vendorDeviceCategories[key] ?? [specialization]
                return (categories, specialization)
            }
        }
        
        // Then check for categories
        for (key, categories) in Self.vendorDeviceCategories {
            if vendorLower.contains(key) {
                return (categories, nil)
            }
        }
        
        return ([], nil)
    }
    
    /// Estimate the age of an OUI based on vendor name
    private func estimateOUIAge(vendor: String?, oui: String) -> OUIAgeEstimate {
        guard let vendor = vendor else {
            return .unknown
        }
        
        let vendorLower = vendor.lowercased()
        
        // Check legacy vendors
        for legacy in Self.legacyVendors {
            if vendorLower.contains(legacy) {
                return .legacy
            }
        }
        
        // Check recent vendors (do this before established to catch newer brands)
        for recent in Self.recentVendors {
            if vendorLower.contains(recent) {
                return .recent
            }
        }
        
        // Check modern vendors
        for modern in Self.modernVendors {
            if vendorLower.contains(modern) {
                return .modern
            }
        }
        
        // Check established vendors
        for established in Self.establishedVendors {
            if vendorLower.contains(established) {
                return .established
            }
        }
        
        // Major consumer electronics brands are generally established or modern
        for high in Self.highConfidenceVendors {
            if vendorLower.contains(high) {
                return .established
            }
        }
        
        return .unknown
    }
}
