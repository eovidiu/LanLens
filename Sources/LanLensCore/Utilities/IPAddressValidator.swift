import Foundation

/// Utility for validating IP addresses and filtering non-routable addresses
///
/// This validator identifies addresses that should NOT be stored as device IPs:
/// - Multicast addresses (224.0.0.0/4 for IPv4, ff00::/8 for IPv6)
/// - Loopback addresses (127.0.0.0/8 for IPv4, ::1 for IPv6)
/// - Link-local addresses (169.254.0.0/16 for IPv4, fe80::/10 for IPv6)
/// - Broadcast addresses (255.255.255.255)
///
/// Example usage:
/// ```swift
/// if IPAddressValidator.isValidDeviceIP("192.168.1.100") {
///     // Safe to store as device IP
/// }
/// ```
public enum IPAddressValidator {

    // MARK: - Primary Validation API

    /// Check if an IP address is valid for use as a device address
    /// Returns true only for unicast addresses that could belong to a real device
    /// - Parameter ip: IPv4 or IPv6 address string
    /// - Returns: true if the address is a valid device IP, false otherwise
    public static func isValidDeviceIP(_ ip: String) -> Bool {
        let trimmed = ip.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        // Check for IPv6 first (contains colons)
        if trimmed.contains(":") {
            return isValidDeviceIPv6(trimmed)
        } else {
            return isValidDeviceIPv4(trimmed)
        }
    }

    /// Validate and return the IP if valid, nil otherwise
    /// Useful for guard-let patterns
    /// - Parameter ip: IPv4 or IPv6 address string
    /// - Returns: The IP if valid, nil if it should be filtered
    public static func validated(_ ip: String?) -> String? {
        guard let ip = ip else { return nil }
        return isValidDeviceIP(ip) ? ip : nil
    }

    // MARK: - Specific Validators

    /// Check if an IPv4 address is multicast (224.0.0.0 - 239.255.255.255)
    /// - Parameter ip: IPv4 address string
    /// - Returns: true if multicast
    public static func isMulticastIPv4(_ ip: String) -> Bool {
        guard let firstOctet = parseFirstOctet(ip) else { return false }
        // Multicast range: 224.0.0.0/4 (224-239)
        return firstOctet >= 224 && firstOctet <= 239
    }

    /// Check if an IPv6 address is multicast (ff00::/8)
    /// - Parameter ip: IPv6 address string
    /// - Returns: true if multicast
    public static func isMulticastIPv6(_ ip: String) -> Bool {
        let normalized = ip.lowercased()
        // Strip interface suffix (e.g., "ff02::1%en0" -> "ff02::1")
        let cleaned = normalized.components(separatedBy: "%").first ?? normalized
        return cleaned.hasPrefix("ff")
    }

    /// Check if an IPv4 address is loopback (127.0.0.0/8)
    /// - Parameter ip: IPv4 address string
    /// - Returns: true if loopback
    public static func isLoopbackIPv4(_ ip: String) -> Bool {
        guard let firstOctet = parseFirstOctet(ip) else { return false }
        return firstOctet == 127
    }

    /// Check if an IPv6 address is loopback (::1)
    /// - Parameter ip: IPv6 address string
    /// - Returns: true if loopback
    public static func isLoopbackIPv6(_ ip: String) -> Bool {
        let normalized = ip.lowercased()
        let cleaned = normalized.components(separatedBy: "%").first ?? normalized
        return cleaned == "::1"
    }

    /// Check if an IPv4 address is link-local (169.254.0.0/16)
    /// - Parameter ip: IPv4 address string
    /// - Returns: true if link-local
    public static func isLinkLocalIPv4(_ ip: String) -> Bool {
        let octets = ip.components(separatedBy: ".")
        guard octets.count == 4,
              let first = Int(octets[0]),
              let second = Int(octets[1]) else {
            return false
        }
        return first == 169 && second == 254
    }

    /// Check if an IPv6 address is link-local (fe80::/10)
    /// - Parameter ip: IPv6 address string
    /// - Returns: true if link-local
    public static func isLinkLocalIPv6(_ ip: String) -> Bool {
        let normalized = ip.lowercased()
        let cleaned = normalized.components(separatedBy: "%").first ?? normalized
        return cleaned.hasPrefix("fe80:")
    }

    /// Check if an IPv4 address is broadcast (255.255.255.255)
    /// - Parameter ip: IPv4 address string
    /// - Returns: true if broadcast
    public static func isBroadcastIPv4(_ ip: String) -> Bool {
        return ip == "255.255.255.255"
    }

    // MARK: - Private Helpers

    /// Validate IPv4 address for device use
    private static func isValidDeviceIPv4(_ ip: String) -> Bool {
        // Must not be multicast
        if isMulticastIPv4(ip) {
            return false
        }

        // Must not be loopback
        if isLoopbackIPv4(ip) {
            return false
        }

        // Must not be link-local (APIPA)
        if isLinkLocalIPv4(ip) {
            return false
        }

        // Must not be broadcast
        if isBroadcastIPv4(ip) {
            return false
        }

        // Basic format validation - must have 4 octets
        let octets = ip.components(separatedBy: ".")
        guard octets.count == 4 else { return false }

        for octet in octets {
            guard let value = Int(octet), value >= 0, value <= 255 else {
                return false
            }
        }

        return true
    }

    /// Validate IPv6 address for device use
    private static func isValidDeviceIPv6(_ ip: String) -> Bool {
        // Must not be multicast
        if isMulticastIPv6(ip) {
            return false
        }

        // Must not be loopback
        if isLoopbackIPv6(ip) {
            return false
        }

        // Note: Link-local IPv6 (fe80::/10) is acceptable for device identification
        // Unlike IPv4 link-local which indicates DHCP failure, IPv6 link-local is normal

        return true
    }

    /// Parse the first octet of an IPv4 address
    private static func parseFirstOctet(_ ip: String) -> Int? {
        let octets = ip.components(separatedBy: ".")
        guard octets.count == 4 else { return nil }
        return Int(octets[0])
    }

    // MARK: - Reason Reporting (for Logging)

    /// Get a human-readable reason why an IP is invalid
    /// Returns nil if the IP is valid
    /// - Parameter ip: IPv4 or IPv6 address string
    /// - Returns: Reason string if invalid, nil if valid
    public static func invalidReason(for ip: String) -> String? {
        let trimmed = ip.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            return "empty address"
        }

        if trimmed.contains(":") {
            // IPv6
            if isMulticastIPv6(trimmed) {
                return "IPv6 multicast (ff00::/8)"
            }
            if isLoopbackIPv6(trimmed) {
                return "IPv6 loopback (::1)"
            }
        } else {
            // IPv4
            if isMulticastIPv4(trimmed) {
                return "IPv4 multicast (224.0.0.0/4)"
            }
            if isLoopbackIPv4(trimmed) {
                return "IPv4 loopback (127.0.0.0/8)"
            }
            if isLinkLocalIPv4(trimmed) {
                return "IPv4 link-local (169.254.0.0/16)"
            }
            if isBroadcastIPv4(trimmed) {
                return "IPv4 broadcast"
            }
        }

        return nil
    }
}

// MARK: - Well-Known Multicast Addresses (Documentation)

extension IPAddressValidator {
    /// Common multicast addresses encountered in network discovery
    /// Listed here for reference and debugging
    public enum WellKnownMulticast {
        // IPv4 Multicast
        public static let mdns = "224.0.0.251"              // mDNS/Bonjour
        public static let ssdp = "239.255.255.250"          // SSDP/UPnP
        public static let spotifyConnect = "239.255.90.90"  // Spotify Connect
        public static let allHosts = "224.0.0.1"            // All hosts
        public static let allRouters = "224.0.0.2"          // All routers

        // IPv6 Multicast
        public static let mdnsIPv6 = "ff02::fb"             // mDNS over IPv6
        public static let allNodesIPv6 = "ff02::1"          // All nodes
        public static let allRoutersIPv6 = "ff02::2"        // All routers
    }
}
