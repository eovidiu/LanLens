import Foundation
import os

/// Manages network interface enumeration and selection for multi-VLAN scanning
public actor NetworkInterfaceManager {
    public static let shared = NetworkInterfaceManager()
    
    private let shell = ShellExecutor.shared
    private let logger = Logger(subsystem: "com.lanlens", category: "NetworkInterfaceManager")
    
    /// Represents a network interface with its configuration
    public struct NetworkInterface: Identifiable, Codable, Sendable, Hashable {
        public let id: String           // e.g., "en0"
        public let name: String         // e.g., "Wi-Fi"
        public let ipAddress: String
        public let subnetMask: String
        public let isActive: Bool
        
        /// CIDR prefix length calculated from subnet mask
        public var cidrPrefix: Int {
            subnetMaskToCIDR(subnetMask)
        }
        
        /// Subnet in CIDR notation (e.g., "192.168.1.0/24")
        public var cidr: String {
            "\(networkAddress)/\(cidrPrefix)"
        }
        
        /// Network address calculated from IP and subnet mask
        public var networkAddress: String {
            calculateNetworkAddress(ip: ipAddress, mask: subnetMask)
        }
        
        public init(id: String, name: String, ipAddress: String, subnetMask: String, isActive: Bool) {
            self.id = id
            self.name = name
            self.ipAddress = ipAddress
            self.subnetMask = subnetMask
            self.isActive = isActive
        }
    }
    
    // MARK: - State
    
    private var cachedInterfaces: [NetworkInterface] = []
    private var lastRefresh: Date?
    private let cacheValiditySeconds: TimeInterval = 30
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public API
    
    /// Get all available network interfaces with IPv4 addresses
    public func getAvailableInterfaces() async -> [NetworkInterface] {
        // Return cached if fresh
        if let lastRefresh = lastRefresh,
           Date().timeIntervalSince(lastRefresh) < cacheValiditySeconds,
           !cachedInterfaces.isEmpty {
            return cachedInterfaces
        }
        
        await refreshInterfaces()
        return cachedInterfaces
    }
    
    /// Get interfaces that are currently selected for scanning
    /// Returns all active interfaces if none are explicitly selected
    public func getSelectedInterfaces(selectedIds: Set<String>) async -> [NetworkInterface] {
        let available = await getAvailableInterfaces()
        
        if selectedIds.isEmpty {
            // Default: return all active interfaces
            return available.filter { $0.isActive }
        }
        
        return available.filter { selectedIds.contains($0.id) && $0.isActive }
    }
    
    /// Force refresh of interface list
    public func refreshInterfaces() async {
        do {
            cachedInterfaces = try await enumerateInterfaces()
            lastRefresh = Date()
            logger.info("Refreshed interfaces: found \(self.cachedInterfaces.count) interfaces")
        } catch {
            logger.error("Failed to enumerate interfaces: \(error.localizedDescription)")
            cachedInterfaces = []
        }
    }
    
    /// Get a friendly name for an interface ID
    public func getFriendlyName(for interfaceId: String) -> String {
        // Common macOS interface mappings
        switch interfaceId {
        case "en0":
            return "Wi-Fi"
        case "en1":
            return "Ethernet"
        case "en2":
            return "Thunderbolt Ethernet"
        case "en3":
            return "USB Ethernet"
        case "en4":
            return "Ethernet 2"
        case "en5":
            return "Ethernet 3"
        case "bridge0":
            return "Bridge"
        case "bridge100":
            return "VM Bridge"
        case "lo0":
            return "Loopback"
        case "awdl0":
            return "AWDL"
        case "llw0":
            return "Low Latency WLAN"
        case "utun0", "utun1", "utun2", "utun3", "utun4":
            return "VPN Tunnel"
        default:
            if interfaceId.hasPrefix("utun") {
                return "VPN Tunnel"
            }
            if interfaceId.hasPrefix("en") {
                return "Ethernet"
            }
            if interfaceId.hasPrefix("bridge") {
                return "Bridge"
            }
            return interfaceId.uppercased()
        }
    }
    
    // MARK: - Interface Enumeration
    
    /// Enumerate all network interfaces using ifconfig
    private func enumerateInterfaces() async throws -> [NetworkInterface] {
        // Get list of interface names
        let listResult = try await shell.execute(path: "/sbin/ifconfig", arguments: ["-l"])
        guard listResult.succeeded else {
            throw NetworkInterfaceError.commandFailed(listResult.stderr)
        }
        
        let interfaceNames = listResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: " ")
            .filter { !$0.isEmpty }
        
        var interfaces: [NetworkInterface] = []
        
        for name in interfaceNames {
            // Skip loopback and virtual interfaces we don't care about
            guard shouldIncludeInterface(name) else { continue }
            
            if let interface = try await parseInterface(name: name) {
                interfaces.append(interface)
            }
        }
        
        return interfaces.sorted { $0.id < $1.id }
    }
    
    /// Parse interface details from ifconfig output
    private func parseInterface(name: String) async throws -> NetworkInterface? {
        let result = try await shell.execute(path: "/sbin/ifconfig", arguments: [name])
        guard result.succeeded else { return nil }
        
        let output = result.stdout
        
        // Parse IPv4 address: "inet 192.168.1.100 netmask 0xffffff00 broadcast 192.168.1.255"
        guard let inetMatch = output.range(of: #"inet (\d+\.\d+\.\d+\.\d+) netmask (0x[0-9a-fA-F]+)"#, options: .regularExpression) else {
            return nil // No IPv4 address configured
        }
        
        let inetLine = String(output[inetMatch])
        
        // Extract IP address
        guard let ipMatch = inetLine.range(of: #"\d+\.\d+\.\d+\.\d+"#, options: .regularExpression) else {
            return nil
        }
        let ipAddress = String(inetLine[ipMatch])
        
        // Skip localhost
        if ipAddress.hasPrefix("127.") {
            return nil
        }
        
        // Extract netmask (hex format)
        guard let maskMatch = inetLine.range(of: #"0x[0-9a-fA-F]+"#, options: .regularExpression) else {
            return nil
        }
        let hexMask = String(inetLine[maskMatch])
        let subnetMask = hexToSubnetMask(hexMask)
        
        // Check if interface is active
        let isActive = output.contains("status: active") || 
                       output.contains("<UP,") || 
                       (output.contains("RUNNING") && !output.contains("status: inactive"))
        
        let friendlyName = getFriendlyName(for: name)
        
        return NetworkInterface(
            id: name,
            name: friendlyName,
            ipAddress: ipAddress,
            subnetMask: subnetMask,
            isActive: isActive
        )
    }
    
    /// Determine if an interface should be included in enumeration
    private func shouldIncludeInterface(_ name: String) -> Bool {
        // Include: en*, bridge*, vmnet* (VMware), vnic* (Parallels)
        // Exclude: lo*, awdl*, llw*, utun* (VPN tunnels - typically point-to-point)
        
        let includePrefixes = ["en", "bridge", "vmnet", "vnic"]
        let excludePrefixes = ["lo", "awdl", "llw", "utun", "gif", "stf", "p2p", "ap"]
        
        for prefix in excludePrefixes {
            if name.hasPrefix(prefix) {
                return false
            }
        }
        
        for prefix in includePrefixes {
            if name.hasPrefix(prefix) {
                return true
            }
        }
        
        return false
    }
}

// MARK: - Helper Functions

/// Convert hex netmask to dotted decimal
private func hexToSubnetMask(_ hex: String) -> String {
    // Remove "0x" prefix if present
    let cleanHex = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
    
    guard cleanHex.count == 8 else { return "255.255.255.0" }
    
    var octets: [Int] = []
    var index = cleanHex.startIndex
    
    for _ in 0..<4 {
        let endIndex = cleanHex.index(index, offsetBy: 2)
        let hexByte = String(cleanHex[index..<endIndex])
        if let value = Int(hexByte, radix: 16) {
            octets.append(value)
        } else {
            octets.append(255)
        }
        index = endIndex
    }
    
    return octets.map { String($0) }.joined(separator: ".")
}

/// Convert subnet mask to CIDR prefix length
private func subnetMaskToCIDR(_ mask: String) -> Int {
    let octets = mask.components(separatedBy: ".").compactMap { Int($0) }
    guard octets.count == 4 else { return 24 }
    
    var bits = 0
    for octet in octets {
        var value = octet
        while value > 0 {
            bits += value & 1
            value >>= 1
        }
    }
    return bits
}

/// Calculate network address from IP and subnet mask
private func calculateNetworkAddress(ip: String, mask: String) -> String {
    let ipOctets = ip.components(separatedBy: ".").compactMap { UInt8($0) }
    let maskOctets = mask.components(separatedBy: ".").compactMap { UInt8($0) }
    
    guard ipOctets.count == 4, maskOctets.count == 4 else {
        return ip
    }
    
    var networkOctets: [UInt8] = []
    for i in 0..<4 {
        networkOctets.append(ipOctets[i] & maskOctets[i])
    }
    
    return networkOctets.map { String($0) }.joined(separator: ".")
}

// MARK: - Errors

public enum NetworkInterfaceError: Error, LocalizedError {
    case commandFailed(String)
    case parseError(String)
    case interfaceNotFound(String)
    
    public var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return "Interface command failed: \(message)"
        case .parseError(let message):
            return "Failed to parse interface: \(message)"
        case .interfaceNotFound(let name):
            return "Interface not found: \(name)"
        }
    }
}
