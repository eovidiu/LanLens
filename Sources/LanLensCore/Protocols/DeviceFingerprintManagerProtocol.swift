import Foundation

/// Protocol for device fingerprint orchestration
public protocol DeviceFingerprintManagerProtocol: Actor {
    /// Fingerprint a device using all available methods (UPnP + Fingerbank)
    /// - Parameters:
    ///   - device: The device to fingerprint
    ///   - locationURL: Optional UPnP LOCATION URL from SSDP discovery
    ///   - fingerbankAPIKey: Optional Fingerbank API key for Level 2 identification
    ///   - dhcpFingerprint: Optional DHCP fingerprint (option 55 parameter request list)
    ///   - userAgents: Optional observed HTTP user agents
    ///   - forceRefresh: Skip cache and fetch fresh data
    /// - Returns: Combined fingerprint data, or nil if no data available
    func fingerprintDevice(
        device: Device,
        locationURL: String?,
        fingerbankAPIKey: String?,
        dhcpFingerprint: String?,
        userAgents: [String]?,
        forceRefresh: Bool
    ) async -> DeviceFingerprint?
    
    /// Quick fingerprint using only Level 1 (UPnP)
    /// - Parameters:
    ///   - device: The device to fingerprint
    ///   - locationURL: UPnP LOCATION URL
    /// - Returns: UPnP fingerprint data, or nil if unavailable
    func quickFingerprint(device: Device, locationURL: String) async -> DeviceFingerprint?
    
    /// Clear fingerprint cache for a specific device
    /// - Parameter mac: MAC address of the device
    func clearCache(for mac: String) async
    
    /// Clear all fingerprint caches
    func clearAllCache() async
    
    /// Get cache statistics
    /// - Returns: Cache metadata with hit/miss statistics
    func getCacheStats() async -> CacheMetadata
}

// MARK: - Conformance

extension DeviceFingerprintManager: DeviceFingerprintManagerProtocol {}
