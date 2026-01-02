import Foundation
import CryptoKit

// MARK: - DHCP Option 55 Parser

/// Parses and normalizes DHCP Option 55 (Parameter Request List) fingerprints.
///
/// DHCP Option 55 contains a list of DHCP option codes that the client is requesting.
/// The sequence and specific codes requested create a unique fingerprint that can
/// identify the device type, operating system, and sometimes specific device models.
///
/// Example fingerprints:
/// - Apple iOS: "1,3,6,15,119,252"
/// - Windows 10: "1,3,6,15,31,33,43,44,46,47,119,121,249,252"
/// - Android: "1,3,6,15,26,28,51,58,59,43"
public struct DHCPOption55Parser: Sendable {

    // MARK: - Normalization

    /// Parse Option 55 from various formats to a normalized form.
    ///
    /// Supported input formats:
    /// - Decimal comma-separated: "1,3,6,15,119,252"
    /// - Hex colon-separated: "01:03:06:0f:77:fc"
    /// - Hex comma-separated: "01,03,06,0f,77,fc"
    /// - Space-separated: "1 3 6 15 119 252"
    ///
    /// Output: Sorted, deduplicated, comma-separated decimal string.
    ///
    /// - Parameter input: The Option 55 string in any supported format
    /// - Returns: Normalized Option 55 string (e.g., "1,3,6,15,119,252")
    public static func normalize(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var values: [UInt8] = []

        // Detect format and parse
        if trimmed.contains(":") {
            // Hex colon-separated format: "01:03:06:0f:77:fc"
            values = parseHexSeparated(trimmed, separator: ":")
        } else if trimmed.contains(",") {
            // Could be decimal or hex comma-separated
            let components = trimmed.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            if isHexFormat(components) {
                values = parseHexComponents(components)
            } else {
                values = parseDecimalComponents(components)
            }
        } else if trimmed.contains(" ") {
            // Space-separated decimal format
            let components = trimmed.split(separator: " ").map { String($0) }
            values = parseDecimalComponents(components)
        } else {
            // Single value
            if let value = UInt8(trimmed) {
                values = [value]
            } else if trimmed.count == 2, let value = UInt8(trimmed, radix: 16) {
                values = [value]
            }
        }

        // Sort and deduplicate
        let uniqueSorted = Array(Set(values)).sorted()

        // Format as comma-separated decimal string
        return uniqueSorted.map { String($0) }.joined(separator: ",")
    }

    /// Compute SHA256 hash of a normalized Option 55 string for database lookup.
    ///
    /// The hash provides a consistent key for database lookups regardless of
    /// input format variations. This enables efficient indexing and matching.
    ///
    /// - Parameter normalizedOption55: A normalized Option 55 string (use `normalize()` first)
    /// - Returns: Lowercase hex-encoded SHA256 hash
    public static func computeHash(_ normalizedOption55: String) -> String {
        guard !normalizedOption55.isEmpty else { return "" }

        let data = Data(normalizedOption55.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Parse raw bytes from a DHCP packet to an Option 55 string.
    ///
    /// This method converts raw DHCP Option 55 bytes directly to the normalized format.
    /// Useful when capturing DHCP packets at the network level.
    ///
    /// - Parameter bytes: Raw Option 55 bytes from a DHCP packet
    /// - Returns: Normalized Option 55 string, or nil if bytes are empty
    public static func parseFromBytes(_ bytes: [UInt8]) -> String? {
        guard !bytes.isEmpty else { return nil }

        // Bytes are already the option codes - sort, dedupe, format
        let uniqueSorted = Array(Set(bytes)).sorted()
        return uniqueSorted.map { String($0) }.joined(separator: ",")
    }

    // MARK: - Validation

    /// Validates whether a string is a valid DHCP Option 55 fingerprint.
    ///
    /// - Parameter input: The fingerprint string to validate
    /// - Returns: True if the fingerprint is valid
    public static func isValid(_ input: String) -> Bool {
        let normalized = normalize(input)
        guard !normalized.isEmpty else { return false }

        // Should contain only valid DHCP option codes (1-255)
        let components = normalized.split(separator: ",")
        for component in components {
            guard let value = UInt8(component), value > 0 else {
                return false
            }
        }
        return true
    }

    /// Returns human-readable descriptions of the DHCP options in a fingerprint.
    ///
    /// - Parameter normalizedOption55: A normalized Option 55 string
    /// - Returns: Array of tuples containing (option code, option name)
    public static func describeOptions(_ normalizedOption55: String) -> [(code: UInt8, name: String)] {
        let components = normalizedOption55.split(separator: ",")
        return components.compactMap { component in
            guard let code = UInt8(component) else { return nil }
            return (code, optionName(for: code))
        }
    }

    // MARK: - Private Helpers

    /// Parse hex-separated format (e.g., "01:03:06")
    private static func parseHexSeparated(_ input: String, separator: Character) -> [UInt8] {
        let components = input.split(separator: separator).map { String($0) }
        return parseHexComponents(components)
    }

    /// Parse array of hex string components
    private static func parseHexComponents(_ components: [String]) -> [UInt8] {
        return components.compactMap { UInt8($0, radix: 16) }
    }

    /// Parse array of decimal string components
    private static func parseDecimalComponents(_ components: [String]) -> [UInt8] {
        return components.compactMap { UInt8($0) }
    }

    /// Detect if components appear to be hex format
    private static func isHexFormat(_ components: [String]) -> Bool {
        // If any component contains a-f characters, it's hex
        // Also consider it hex if all components are exactly 2 chars with leading zeros
        let hexChars = CharacterSet(charactersIn: "abcdefABCDEF")
        for component in components {
            if component.rangeOfCharacter(from: hexChars) != nil {
                return true
            }
            // Check for leading zero pattern (e.g., "01", "03", "06")
            if component.count == 2, component.first == "0", let val = Int(component), val < 10 {
                return true
            }
        }
        return false
    }

    /// Get human-readable name for a DHCP option code
    private static func optionName(for code: UInt8) -> String {
        switch code {
        case 1: return "Subnet Mask"
        case 2: return "Time Offset"
        case 3: return "Router"
        case 4: return "Time Server"
        case 5: return "Name Server"
        case 6: return "DNS Server"
        case 7: return "Log Server"
        case 12: return "Hostname"
        case 15: return "Domain Name"
        case 23: return "Default IP TTL"
        case 26: return "Interface MTU"
        case 28: return "Broadcast Address"
        case 31: return "Perform Router Discovery"
        case 33: return "Static Route"
        case 42: return "NTP Server"
        case 43: return "Vendor Specific Info"
        case 44: return "NetBIOS Name Server"
        case 45: return "NetBIOS Datagram Server"
        case 46: return "NetBIOS Node Type"
        case 47: return "NetBIOS Scope"
        case 50: return "Requested IP"
        case 51: return "IP Lease Time"
        case 53: return "DHCP Message Type"
        case 54: return "Server Identifier"
        case 55: return "Parameter Request List"
        case 57: return "Max DHCP Message Size"
        case 58: return "Renewal Time"
        case 59: return "Rebinding Time"
        case 60: return "Vendor Class Identifier"
        case 61: return "Client Identifier"
        case 77: return "User Class"
        case 81: return "FQDN"
        case 95: return "LDAP"
        case 100: return "PCode"
        case 101: return "TCode"
        case 119: return "Domain Search"
        case 121: return "Classless Static Route"
        case 249: return "Private/Classless Static Route (MS)"
        case 252: return "WPAD"
        default: return "Option \(code)"
        }
    }
}

// MARK: - Known Fingerprint Patterns

extension DHCPOption55Parser {

    /// Common device type hints based on Option 55 patterns.
    /// These are heuristics and should be combined with database lookups for accuracy.
    public enum DeviceHint: String, Sendable {
        case apple = "Apple Device"
        case windows = "Windows"
        case android = "Android"
        case linux = "Linux"
        case networkEquipment = "Network Equipment"
        case iot = "IoT Device"
        case unknown = "Unknown"
    }

    /// Get a quick device hint based on Option 55 pattern characteristics.
    ///
    /// This is a heuristic-based quick check. For accurate identification,
    /// use `DHCPFingerprintMatcher` with the full database.
    ///
    /// - Parameter normalizedOption55: A normalized Option 55 string
    /// - Returns: A device hint based on pattern analysis
    public static func quickHint(for normalizedOption55: String) -> DeviceHint {
        let options = Set(normalizedOption55.split(separator: ",").compactMap { UInt8($0) })

        // Apple devices typically request option 252 (WPAD) and 119 (Domain Search)
        // and have a relatively short list
        if options.contains(252) && options.contains(119) && options.count < 10 {
            return .apple
        }

        // Windows typically has a longer list with options 31, 33, 249
        if options.contains(31) && options.contains(33) && (options.contains(249) || options.contains(121)) {
            return .windows
        }

        // Android often includes 26 (MTU) and 28 (Broadcast)
        if options.contains(26) && options.contains(28) && options.count < 15 {
            return .android
        }

        // Linux often has option 77 (User Class) or minimal set
        if options.contains(77) || (options.count <= 6 && options.contains(1) && options.contains(3) && options.contains(6)) {
            return .linux
        }

        // Very minimal lists often indicate network equipment or embedded devices
        if options.count <= 4 {
            return .networkEquipment
        }

        // IoT devices often have unusual patterns
        if options.contains(43) && options.count < 8 {
            return .iot
        }

        return .unknown
    }
}
