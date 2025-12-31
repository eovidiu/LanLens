import Foundation

/// Protocol for SSDP (Simple Service Discovery Protocol) listeners
public protocol SSDPListenerProtocol: Actor {
    /// SSDP device information type
    associatedtype SSDPDeviceType: Sendable
    
    /// Handler for device discovery callbacks
    typealias DeviceHandler = @Sendable (SSDPDeviceType) -> Void
    
    /// Start listening for SSDP announcements
    /// - Parameter onDiscovered: Callback invoked when a device is discovered
    func start(onDiscovered: @escaping DeviceHandler) async
    
    /// Stop listening for SSDP announcements
    func stop()
    
    /// Get all discovered devices
    /// - Returns: Array of discovered SSDP devices
    func getDiscoveredDevices() -> [SSDPDeviceType]
    
    /// Send M-SEARCH to discover devices
    func sendMSearch() async
}

// MARK: - Conformance

extension SSDPListener: SSDPListenerProtocol {}
