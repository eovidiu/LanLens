import Foundation

/// Main orchestrator for device fingerprinting
/// Coordinates Level 1 (UPnP) and Level 2 (Fingerbank) fingerprinting with caching
public actor DeviceFingerprintManager {
    public static let shared = DeviceFingerprintManager()

    private let upnpFetcher = UPnPDescriptionFetcher.shared
    private let fingerbankService = FingerbankService.shared
    private let cacheManager = FingerprintCacheManager.shared

    private init() {}

    /// Fingerprint a device using all available methods
    /// - Parameters:
    ///   - device: The device to fingerprint
    ///   - locationURL: Optional UPnP LOCATION URL (from SSDP discovery)
    ///   - fingerbankAPIKey: Optional Fingerbank API key for Level 2
    ///   - dhcpFingerprint: Optional DHCP fingerprint
    ///   - userAgents: Optional observed user agents
    ///   - forceRefresh: Skip cache and fetch fresh data
    /// - Returns: Combined fingerprint data, or nil if no data available
    public func fingerprintDevice(
        device: Device,
        locationURL: String? = nil,
        fingerbankAPIKey: String? = nil,
        dhcpFingerprint: String? = nil,
        userAgents: [String]? = nil,
        forceRefresh: Bool = false
    ) async -> DeviceFingerprint? {
        var upnpFingerprint: DeviceFingerprint?
        var fingerbankFingerprint: DeviceFingerprint?

        // Level 1: UPnP fingerprinting
        if let location = locationURL ?? getLocationURL(from: device) {
            if !forceRefresh {
                // Check cache first
                upnpFingerprint = await cacheManager.getUPnPCache(mac: device.mac, locationURL: location)
            }

            if upnpFingerprint == nil {
                // Fetch fresh
                upnpFingerprint = await upnpFetcher.fetchDescription(from: location)

                // Cache the result
                if let fp = upnpFingerprint {
                    await cacheManager.storeUPnPCache(mac: device.mac, locationURL: location, fingerprint: fp)
                }
            }
        }

        // Level 2: Fingerbank (if API key provided)
        if let apiKey = fingerbankAPIKey, !apiKey.isEmpty {
            if !forceRefresh {
                // Check cache first
                fingerbankFingerprint = await cacheManager.getFingerbankCache(
                    mac: device.mac,
                    dhcpFingerprint: dhcpFingerprint,
                    userAgents: userAgents
                )
            }

            if fingerbankFingerprint == nil {
                // Fetch from API
                do {
                    fingerbankFingerprint = try await fingerbankService.interrogate(
                        mac: device.mac,
                        dhcpFingerprint: dhcpFingerprint,
                        userAgents: userAgents,
                        apiKey: apiKey
                    )

                    // Cache the result
                    if let fp = fingerbankFingerprint {
                        await cacheManager.storeFingerbankCache(
                            mac: device.mac,
                            dhcpFingerprint: dhcpFingerprint,
                            userAgents: userAgents,
                            fingerprint: fp
                        )
                    }
                } catch {
                    // Fingerbank failed - continue with Level 1 only
                    // Could log the error here for debugging
                }
            }
        }

        // Merge results
        return mergeFingerprints(upnp: upnpFingerprint, fingerbank: fingerbankFingerprint)
    }

    /// Quick fingerprint using only Level 1 (UPnP)
    public func quickFingerprint(device: Device, locationURL: String) async -> DeviceFingerprint? {
        return await fingerprintDevice(device: device, locationURL: locationURL)
    }

    /// Clear fingerprint cache for a device
    public func clearCache(for mac: String) async {
        await cacheManager.clearCache(for: mac)
    }

    /// Clear all fingerprint caches
    public func clearAllCache() async {
        await cacheManager.clearAllCache()
    }

    /// Get cache statistics
    public func getCacheStats() async -> CacheMetadata {
        return await cacheManager.getStats()
    }

    // MARK: - Private Helpers

    /// Extract LOCATION URL from device's SSDP services
    private func getLocationURL(from device: Device) -> String? {
        for service in device.services {
            if service.type == .ssdp, let location = service.txt["location"], !location.isEmpty {
                return location
            }
        }
        return nil
    }

    /// Merge UPnP and Fingerbank fingerprints into one
    private func mergeFingerprints(upnp: DeviceFingerprint?, fingerbank: DeviceFingerprint?) -> DeviceFingerprint? {
        guard upnp != nil || fingerbank != nil else {
            return nil
        }

        // Determine source
        let source: FingerprintSource
        if upnp != nil && fingerbank != nil {
            source = .both
        } else if upnp != nil {
            source = .upnp
        } else {
            source = .fingerbank
        }

        // Determine cache hit status
        let cacheHit = (upnp?.cacheHit ?? false) && (fingerbank?.cacheHit ?? true)

        // Merge all fields, preferring Fingerbank data when both exist
        return DeviceFingerprint(
            // UPnP fields (only from UPnP)
            friendlyName: upnp?.friendlyName,
            manufacturer: upnp?.manufacturer,
            manufacturerURL: upnp?.manufacturerURL,
            modelDescription: upnp?.modelDescription,
            modelName: upnp?.modelName,
            modelNumber: upnp?.modelNumber,
            serialNumber: upnp?.serialNumber,
            upnpDeviceType: upnp?.upnpDeviceType,
            upnpServices: upnp?.upnpServices,

            // Fingerbank fields (only from Fingerbank)
            fingerbankDeviceName: fingerbank?.fingerbankDeviceName,
            fingerbankDeviceId: fingerbank?.fingerbankDeviceId,
            fingerbankParents: fingerbank?.fingerbankParents,
            fingerbankScore: fingerbank?.fingerbankScore,
            operatingSystem: fingerbank?.operatingSystem,
            osVersion: fingerbank?.osVersion,
            isMobile: fingerbank?.isMobile,
            isTablet: fingerbank?.isTablet,

            // Metadata
            source: source,
            timestamp: Date(),
            cacheHit: cacheHit
        )
    }
}

// MARK: - Device Extension

extension Device {
    /// Get the SSDP location URL if available
    public var ssdpLocationURL: String? {
        for service in services {
            if service.type == .ssdp, let location = service.txt["location"], !location.isEmpty {
                return location
            }
        }
        return nil
    }
}
