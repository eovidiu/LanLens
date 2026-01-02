import Foundation

/// Main orchestrator for device fingerprinting
/// Coordinates Level 1 (UPnP) and Level 2 (Fingerbank) fingerprinting with caching
///
/// Lookup order for Fingerbank data:
/// 1. SQLite cache (FingerbankCacheRepository) - primary cache
/// 2. File cache (FingerprintCacheManager) - migration fallback
/// 3. Bundled database (BundledDatabaseManager) - offline fallback
/// 4. Fingerbank API - online lookup
public actor DeviceFingerprintManager {
    public static let shared = DeviceFingerprintManager()

    private let upnpFetcher = UPnPDescriptionFetcher.shared
    private let fingerbankService = FingerbankService.shared
    private let cacheManager = FingerprintCacheManager.shared

    // New SQLite-based cache (primary)
    private let sqliteCache: FingerbankCacheRepository?

    // Bundled offline database
    private let bundledDatabase: BundledDatabaseManager

    /// Whether to use the legacy file cache as fallback during migration
    private let useLegacyFileCacheFallback: Bool

    private init() {
        // Initialize SQLite cache with shared database
        self.sqliteCache = FingerbankCacheRepository(database: DatabaseManager.shared)
        self.bundledDatabase = BundledDatabaseManager.shared
        self.useLegacyFileCacheFallback = true  // Enable during migration period
    }

    /// Initialize with custom dependencies (for testing)
    public init(
        sqliteCache: FingerbankCacheRepository?,
        bundledDatabase: BundledDatabaseManager,
        useLegacyFileCacheFallback: Bool = true
    ) {
        self.sqliteCache = sqliteCache
        self.bundledDatabase = bundledDatabase
        self.useLegacyFileCacheFallback = useLegacyFileCacheFallback
    }

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
        Log.debug("Starting fingerprint for \(device.mac)", category: .fingerprinting)
        Log.debug("  - Location URL: \(locationURL ?? "nil")", category: .fingerprinting)
        Log.debug("  - Fingerbank API Key: \(fingerbankAPIKey != nil ? "provided" : "nil")", category: .fingerprinting)
        Log.debug("  - Force Refresh: \(forceRefresh)", category: .fingerprinting)

        var upnpFingerprint: DeviceFingerprint?
        var fingerbankFingerprint: DeviceFingerprint?

        // Level 1: UPnP fingerprinting
        if let location = locationURL ?? getLocationURL(from: device) {
            Log.debug("Level 1 (UPnP): Processing...", category: .fingerprinting)
            if !forceRefresh {
                // Check cache first
                upnpFingerprint = await cacheManager.getUPnPCache(mac: device.mac, locationURL: location)
                if upnpFingerprint != nil {
                    Log.debug("Level 1 (UPnP): Cache HIT", category: .cache)
                }
            }

            if upnpFingerprint == nil {
                Log.debug("Level 1 (UPnP): Fetching from device...", category: .fingerprinting)
                // Fetch fresh
                upnpFingerprint = await upnpFetcher.fetchDescription(from: location)

                // Cache the result
                if let fp = upnpFingerprint {
                    Log.debug("Level 1 (UPnP): Caching result - name=\(fp.friendlyName ?? "nil") model=\(fp.modelName ?? "nil")", category: .cache)
                    await cacheManager.storeUPnPCache(mac: device.mac, locationURL: location, fingerprint: fp)
                } else {
                    Log.debug("Level 1 (UPnP): Fetch returned nil", category: .fingerprinting)
                }
            }
        } else {
            Log.debug("Level 1 (UPnP): Skipped - no location URL", category: .fingerprinting)
        }

        // Level 2: Fingerbank lookup with tiered cache strategy
        // Order: SQLite cache -> File cache (migration) -> Bundled DB -> API
        Log.debug("Level 2 (Fingerbank): Processing...", category: .fingerprinting)

        if !forceRefresh {
            // Generate signal hash for cache validation
            let signalHash = FingerbankCacheRepository.generateSignalHash(
                mac: device.mac,
                dhcpFingerprint: dhcpFingerprint,
                userAgents: userAgents
            )

            // Step 1: Check SQLite cache (primary)
            if let cache = sqliteCache {
                do {
                    fingerbankFingerprint = try await cache.get(mac: device.mac, signalHash: signalHash)
                    if fingerbankFingerprint != nil {
                        Log.debug("Level 2 (Fingerbank): SQLite cache HIT", category: .cache)
                        try? await cache.incrementHit(mac: device.mac)
                    }
                } catch {
                    Log.warning("Level 2 (Fingerbank): SQLite cache error - \(error)", category: .cache)
                }
            }

            // Step 2: Check legacy file cache (migration fallback)
            if fingerbankFingerprint == nil && useLegacyFileCacheFallback {
                fingerbankFingerprint = await cacheManager.getFingerbankCache(
                    mac: device.mac,
                    dhcpFingerprint: dhcpFingerprint,
                    userAgents: userAgents
                )
                if fingerbankFingerprint != nil {
                    Log.debug("Level 2 (Fingerbank): File cache HIT (legacy)", category: .cache)

                    // Migrate to SQLite cache for future lookups
                    if let cache = sqliteCache, let fp = fingerbankFingerprint {
                        try? await cache.store(
                            mac: device.mac,
                            fingerprint: fp,
                            signalHash: signalHash,
                            dhcpFingerprint: dhcpFingerprint,
                            userAgents: userAgents,
                            ttl: FingerbankCacheRepository.defaultTTL
                        )
                        Log.debug("Level 2 (Fingerbank): Migrated file cache entry to SQLite", category: .cache)
                    }
                }
            }

            // Step 3: Check bundled offline database
            if fingerbankFingerprint == nil {
                fingerbankFingerprint = await lookupBundledDatabase(
                    mac: device.mac,
                    dhcpFingerprint: dhcpFingerprint
                )
                if fingerbankFingerprint != nil {
                    Log.debug("Level 2 (Fingerbank): Bundled database HIT", category: .cache)
                }
            }
        }

        // Step 4: Call Fingerbank API if still no result and API key provided
        if fingerbankFingerprint == nil {
            if let apiKey = fingerbankAPIKey, !apiKey.isEmpty {
                Log.debug("Level 2 (Fingerbank): Calling API for \(device.mac)...", category: .fingerprinting)

                do {
                    fingerbankFingerprint = try await fingerbankService.interrogate(
                        mac: device.mac,
                        dhcpFingerprint: dhcpFingerprint,
                        userAgents: userAgents,
                        apiKey: apiKey
                    )

                    // Store in both caches during migration period
                    if let fp = fingerbankFingerprint {
                        Log.info("Level 2 (Fingerbank): SUCCESS - device=\(fp.fingerbankDeviceName ?? "nil") score=\(fp.fingerbankScore ?? 0)", category: .fingerprinting)

                        let signalHash = FingerbankCacheRepository.generateSignalHash(
                            mac: device.mac,
                            dhcpFingerprint: dhcpFingerprint,
                            userAgents: userAgents
                        )

                        // Store in SQLite cache (primary)
                        if let cache = sqliteCache {
                            try? await cache.store(
                                mac: device.mac,
                                fingerprint: fp,
                                signalHash: signalHash,
                                dhcpFingerprint: dhcpFingerprint,
                                userAgents: userAgents,
                                ttl: FingerbankCacheRepository.defaultTTL
                            )
                        }

                        // Also store in file cache during migration
                        if useLegacyFileCacheFallback {
                            await cacheManager.storeFingerbankCache(
                                mac: device.mac,
                                dhcpFingerprint: dhcpFingerprint,
                                userAgents: userAgents,
                                fingerprint: fp
                            )
                        }
                    }
                } catch {
                    Log.error("Level 2 (Fingerbank): ERROR - \(error)", category: .fingerprinting)

                    // Record cache miss in SQLite stats
                    if let cache = sqliteCache {
                        try? await cache.recordMiss()
                    }
                }
            } else {
                Log.debug("Level 2 (Fingerbank): Skipped API call - no API key", category: .fingerprinting)
            }
        }

        // Merge results
        let result = mergeFingerprints(upnp: upnpFingerprint, fingerbank: fingerbankFingerprint)
        Log.debug("Final result for \(device.mac): \(result != nil ? "success" : "nil")", category: .fingerprinting)
        return result
    }

    /// Quick fingerprint using only Level 1 (UPnP)
    public func quickFingerprint(device: Device, locationURL: String) async -> DeviceFingerprint? {
        return await fingerprintDevice(device: device, locationURL: locationURL)
    }

    /// Clear fingerprint cache for a device
    public func clearCache(for mac: String) async {
        // Clear from SQLite cache
        if let cache = sqliteCache {
            try? await cache.invalidate(mac: mac)
        }

        // Clear from legacy file cache
        await cacheManager.clearCache(for: mac)
    }

    /// Clear all fingerprint caches
    public func clearAllCache() async {
        // Clear SQLite cache
        if let cache = sqliteCache {
            try? await cache.deleteAll()
        }

        // Clear legacy file cache
        await cacheManager.clearAllCache()
    }

    /// Get cache statistics (combined from both cache layers)
    public func getCacheStats() async -> CacheMetadata {
        return await cacheManager.getStats()
    }

    /// Get SQLite cache statistics
    public func getSQLiteCacheStats() async -> FingerbankCacheStats? {
        guard let cache = sqliteCache else { return nil }
        return try? await cache.getStats()
    }

    /// Get bundled database metadata
    public func getBundledDatabaseMetadata() async -> BundledDatabaseMetadata {
        return await bundledDatabase.getMetadata()
    }

    /// Prune expired entries from the SQLite cache
    /// - Returns: Number of entries pruned
    @discardableResult
    public func pruneExpiredCache() async -> Int {
        guard let cache = sqliteCache else { return 0 }
        return (try? await cache.pruneExpired()) ?? 0
    }

    /// Migrate all entries from file cache to SQLite cache
    /// Call this once during app upgrade to transfer existing cache data
    /// - Returns: Number of entries migrated
    @discardableResult
    public func migrateFileCacheToSQLite() async -> Int {
        guard sqliteCache != nil else {
            Log.warning("Cannot migrate: SQLite cache not available", category: .cache)
            return 0
        }

        // Note: The file cache doesn't expose a method to enumerate all entries
        // Migration happens opportunistically when entries are accessed
        // This method is a placeholder for future bulk migration if needed
        Log.info("Cache migration: entries are migrated on-demand when accessed", category: .cache)
        return 0
    }

    // MARK: - Private Helpers

    /// Look up device in the bundled offline database
    private func lookupBundledDatabase(mac: String, dhcpFingerprint: String?) async -> DeviceFingerprint? {
        // Check if bundled database is available
        guard await bundledDatabase.isAvailable else {
            return nil
        }

        // Try OUI lookup first (using MAC prefix)
        let oui = await bundledDatabase.extractOUI(from: mac)
        if let entry = await bundledDatabase.queryByOUI(oui) {
            Log.debug("Bundled DB: OUI match for \(oui) -> \(entry.deviceName)", category: .fingerprinting)
            return entry.toDeviceFingerprint()
        }

        // Try DHCP fingerprint lookup if available
        if let dhcp = dhcpFingerprint, !dhcp.isEmpty {
            // Generate hash for DHCP fingerprint
            let dhcpHash = FingerbankCacheRepository.generateSignalHash(
                mac: mac,
                dhcpFingerprint: dhcp,
                userAgents: nil
            )

            if let entry = await bundledDatabase.queryByDHCPHash(dhcpHash) {
                Log.debug("Bundled DB: DHCP match for hash -> \(entry.deviceName)", category: .fingerprinting)
                return entry.toDeviceFingerprint()
            }
        }

        return nil
    }

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
