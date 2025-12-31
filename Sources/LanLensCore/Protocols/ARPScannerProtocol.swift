import Foundation

/// Protocol for ARP table scanning and subnet discovery
public protocol ARPScannerProtocol: Actor {
    /// ARP table entry representing a discovered device
    associatedtype Entry: Sendable
    
    /// Get current ARP table entries
    /// - Returns: Array of ARP entries with IP, MAC, and interface information
    /// - Throws: Error if the ARP command fails
    func getARPTable() async throws -> [Entry]
    
    /// Ping sweep a subnet to populate ARP table, then read it
    /// - Parameter subnet: Subnet in CIDR notation (e.g., "192.168.1.0/24")
    /// - Returns: Array of ARP entries for the scanned subnet
    /// - Throws: Error if subnet is invalid or too large
    func scanSubnet(_ subnet: String) async throws -> [Entry]
}

// MARK: - Conformance

extension ARPScanner: ARPScannerProtocol {}
