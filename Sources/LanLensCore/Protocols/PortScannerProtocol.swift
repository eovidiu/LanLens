import Foundation

/// Protocol for port scanning services
public protocol PortScannerProtocol: Actor {
    /// Port scan result type
    associatedtype ScanResultType: Sendable
    
    /// Port information type
    associatedtype PortInfoType: Sendable
    
    /// Check if nmap is available on the system
    /// - Returns: true if nmap is installed and executable
    func isNmapAvailable() async -> Bool
    
    /// Scan a single host for open ports
    /// - Parameters:
    ///   - ip: IP address to scan
    ///   - ports: Optional array of specific ports to scan (defaults to smart device ports)
    ///   - useNmap: Whether to use nmap if available (defaults to true)
    /// - Returns: Scan result containing open ports and timing information
    func scan(ip: String, ports: [UInt16]?, useNmap: Bool) async -> ScanResultType
    
    /// Quick scan for common smart device ports
    /// - Parameter ip: IP address to scan
    /// - Returns: Scan result with common port status
    func quickScan(ip: String) async -> ScanResultType
    
    /// Scan multiple hosts in parallel
    /// - Parameters:
    ///   - ips: Array of IP addresses to scan
    ///   - ports: Optional array of specific ports to scan
    /// - Returns: Dictionary mapping IP addresses to scan results
    func scanHosts(_ ips: [String], ports: [UInt16]?) async -> [String: ScanResultType]
}

// MARK: - Conformance

extension PortScanner: PortScannerProtocol {
    public typealias ScanResultType = ScanResult
    public typealias PortInfoType = PortInfo
}
