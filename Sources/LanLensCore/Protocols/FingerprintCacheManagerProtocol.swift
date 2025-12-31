import Foundation

/// Protocol for fingerprint cache management
public protocol FingerprintCacheManagerProtocol: Actor {
    /// Get cached UPnP fingerprint
    /// - Parameters:
    ///   - mac: Device MAC address
    ///   - locationURL: UPnP LOCATION URL used as cache key component
    /// - Returns: Cached fingerprint if available and not expired
    func getUPnPCache(mac: String, locationURL: String) -> DeviceFingerprint?
    
    /// Store UPnP fingerprint in cache
    /// - Parameters:
    ///   - mac: Device MAC address
    ///   - locationURL: UPnP LOCATION URL used as cache key component
    ///   - fingerprint: Fingerprint data to cache
    func storeUPnPCache(mac: String, locationURL: String, fingerprint: DeviceFingerprint)
    
    /// Get cached Fingerbank fingerprint
    /// - Parameters:
    ///   - mac: Device MAC address
    ///   - dhcpFingerprint: Optional DHCP fingerprint for cache key
    ///   - userAgents: Optional user agents for cache key
    /// - Returns: Cached fingerprint if available and not expired
    func getFingerbankCache(mac: String, dhcpFingerprint: String?, userAgents: [String]?) -> DeviceFingerprint?
    
    /// Store Fingerbank fingerprint in cache
    /// - Parameters:
    ///   - mac: Device MAC address
    ///   - dhcpFingerprint: Optional DHCP fingerprint for cache key
    ///   - userAgents: Optional user agents for cache key
    ///   - fingerprint: Fingerprint data to cache
    func storeFingerbankCache(mac: String, dhcpFingerprint: String?, userAgents: [String]?, fingerprint: DeviceFingerprint)
    
    /// Clear all cached fingerprints
    func clearAllCache()
    
    /// Clear cached fingerprint for a specific device
    /// - Parameter mac: Device MAC address
    func clearCache(for mac: String)
    
    /// Get cache statistics
    /// - Returns: Cache metadata with hit/miss statistics
    func getStats() -> CacheMetadata
}

// MARK: - Conformance

extension FingerprintCacheManager: FingerprintCacheManagerProtocol {}
