import Foundation

/// Caches ARP table entries with TTL-based expiration
/// Reduces system calls and improves scan performance
public actor ARPCache {
    public static let shared = ARPCache()

    /// Cached ARP entry with timestamp
    public struct CachedEntry: Sendable {
        public let entry: ARPScanner.ARPEntry
        public let cachedAt: Date

        public init(entry: ARPScanner.ARPEntry, cachedAt: Date = Date()) {
            self.entry = entry
            self.cachedAt = cachedAt
        }

        public func isExpired(ttl: TimeInterval) -> Bool {
            Date().timeIntervalSince(cachedAt) > ttl
        }
    }

    /// Cache configuration
    public struct Config: Sendable {
        /// Time-to-live for cached entries
        public let ttl: TimeInterval
        /// Maximum entries to cache
        public let maxEntries: Int
        /// Whether to automatically refresh expired entries
        public let autoRefresh: Bool

        public init(
            ttl: TimeInterval = 30.0,  // 30 seconds default
            maxEntries: Int = 500,
            autoRefresh: Bool = true
        ) {
            self.ttl = ttl
            self.maxEntries = maxEntries
            self.autoRefresh = autoRefresh
        }

        public static let `default` = Config()
        public static let aggressive = Config(ttl: 60.0, maxEntries: 1000)
        public static let minimal = Config(ttl: 10.0, maxEntries: 100, autoRefresh: false)
    }

    // MARK: - State

    private var cache: [String: CachedEntry] = [:]  // MAC -> CachedEntry
    private var ipIndex: [String: String] = [:]     // IP -> MAC (for reverse lookup)
    private var lastFullRefresh: Date?
    private let config: Config

    // MARK: - Statistics

    private(set) var hitCount: Int = 0
    private(set) var missCount: Int = 0
    private(set) var refreshCount: Int = 0

    // MARK: - Initialization

    public init(config: Config = .default) {
        self.config = config
    }

    // MARK: - Public API

    /// Get cached ARP table, refreshing if needed
    /// - Parameter forceRefresh: Force a full refresh even if cache is valid
    /// - Returns: Array of ARP entries
    public func getARPTable(forceRefresh: Bool = false) async throws -> [ARPScanner.ARPEntry] {
        // Check if we need to refresh
        let needsRefresh = forceRefresh || shouldRefresh()

        if needsRefresh {
            try await refresh()
        }

        return cache.values.map(\.entry)
    }

    /// Get entry by MAC address
    /// - Parameter mac: MAC address (case-insensitive)
    /// - Returns: Cached entry if found and not expired
    public func getByMAC(_ mac: String) -> ARPScanner.ARPEntry? {
        let normalizedMAC = mac.uppercased()

        guard let cached = cache[normalizedMAC],
              !cached.isExpired(ttl: config.ttl) else {
            missCount += 1
            return nil
        }

        hitCount += 1
        return cached.entry
    }

    /// Get entry by IP address
    /// - Parameter ip: IP address
    /// - Returns: Cached entry if found and not expired
    public func getByIP(_ ip: String) -> ARPScanner.ARPEntry? {
        guard let mac = ipIndex[ip],
              let cached = cache[mac],
              !cached.isExpired(ttl: config.ttl) else {
            missCount += 1
            return nil
        }

        hitCount += 1
        return cached.entry
    }

    /// Refresh the cache from the ARP table
    public func refresh() async throws {
        let entries = try await ARPScanner.shared.getARPTable()
        updateCache(with: entries)
        lastFullRefresh = Date()
        refreshCount += 1
        Log.debug("ARP cache refreshed: \(entries.count) entries", category: .arp)
    }

    /// Clear all cached entries
    public func clear() {
        cache.removeAll()
        ipIndex.removeAll()
        lastFullRefresh = nil
        Log.debug("ARP cache cleared", category: .arp)
    }

    /// Get cache statistics
    public func getStats() -> ARPCacheStats {
        ARPCacheStats(
            entryCount: cache.count,
            hitCount: hitCount,
            missCount: missCount,
            refreshCount: refreshCount,
            hitRate: hitCount + missCount > 0
                ? Double(hitCount) / Double(hitCount + missCount)
                : 0,
            lastRefresh: lastFullRefresh
        )
    }

    /// Reset statistics
    public func resetStats() {
        hitCount = 0
        missCount = 0
        refreshCount = 0
    }

    // MARK: - Private Helpers

    private func shouldRefresh() -> Bool {
        guard let lastRefresh = lastFullRefresh else {
            return true  // Never refreshed
        }

        return Date().timeIntervalSince(lastRefresh) > config.ttl
    }

    private func updateCache(with entries: [ARPScanner.ARPEntry]) {
        let now = Date()

        // Clear old entries if we're at capacity
        if cache.count + entries.count > config.maxEntries {
            evictOldestEntries(count: cache.count + entries.count - config.maxEntries)
        }

        // Update cache
        for entry in entries {
            let mac = entry.mac.uppercased()

            // Update MAC -> Entry mapping
            cache[mac] = CachedEntry(entry: entry, cachedAt: now)

            // Update IP -> MAC index
            ipIndex[entry.ip] = mac
        }
    }

    private func evictOldestEntries(count: Int) {
        let sortedEntries = cache.sorted { $0.value.cachedAt < $1.value.cachedAt }
        let toEvict = sortedEntries.prefix(count)

        for (mac, cached) in toEvict {
            cache.removeValue(forKey: mac)
            ipIndex.removeValue(forKey: cached.entry.ip)
        }

        Log.debug("ARP cache evicted \(count) entries", category: .arp)
    }
}

// MARK: - Statistics

public struct ARPCacheStats: Sendable {
    public let entryCount: Int
    public let hitCount: Int
    public let missCount: Int
    public let refreshCount: Int
    public let hitRate: Double
    public let lastRefresh: Date?
}
