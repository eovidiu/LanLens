import Foundation

/// Protocol for mDNS/Bonjour service discovery listeners
public protocol MDNSListenerProtocol: Actor {
    /// mDNS service information type
    associatedtype MDNSServiceType: Sendable
    
    /// Handler for service discovery callbacks
    typealias ServiceHandler = @Sendable (MDNSServiceType) -> Void
    
    /// Start browsing for mDNS services
    /// - Parameters:
    ///   - serviceTypes: Optional array of service types to browse for (e.g., ["_http._tcp", "_hap._tcp"])
    ///   - onDiscovered: Callback invoked when a service is discovered
    func start(serviceTypes: [String]?, onDiscovered: @escaping ServiceHandler) async
    
    /// Stop all mDNS browsers
    func stop()
    
    /// Get all discovered services
    /// - Returns: Array of discovered mDNS services
    func getDiscoveredServices() -> [MDNSServiceType]
}

// MARK: - Conformance

extension MDNSListener: MDNSListenerProtocol {}
