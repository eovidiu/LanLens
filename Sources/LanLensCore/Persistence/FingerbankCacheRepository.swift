import Foundation
import GRDB
import CryptoKit

// MARK: - Cache Statistics

/// Statistics for Fingerbank cache operations
public struct FingerbankCacheStats: Codable, Sendable, Equatable {
    public var totalEntries: Int
    public var totalHits: Int
    public var totalMisses: Int
    public var lastPruneAt: Date?
    public var lastSyncAt: Date?

    public init(
        totalEntries: Int = 0,
        totalHits: Int = 0,
        totalMisses: Int = 0,
        lastPruneAt: Date? = nil,
        lastSyncAt: Date? = nil
    ) {
        self.totalEntries = totalEntries
        self.totalHits = totalHits
        self.totalMisses = totalMisses
        self.lastPruneAt = lastPruneAt
        self.lastSyncAt = lastSyncAt
    }

    /// Cache hit rate as a percentage (0.0 to 1.0)
    public var hitRate: Double {
        let total = totalHits + totalMisses
        guard total > 0 else { return 0.0 }
        return Double(totalHits) / Double(total)
    }
}

// MARK: - Repository Protocol

/// Protocol for Fingerbank cache persistence operations
public protocol FingerbankCacheRepositoryProtocol: Sendable {
    /// Retrieve a cached fingerprint if valid (not expired, matching signal hash)
    func get(mac: String, signalHash: String) async throws -> DeviceFingerprint?

    /// Store a fingerprint in the cache
    func store(
        mac: String,
        fingerprint: DeviceFingerprint,
        signalHash: String,
        dhcpFingerprint: String?,
        userAgents: [String]?,
        ttl: TimeInterval
    ) async throws

    /// Invalidate (remove) a cached entry for a specific MAC
    func invalidate(mac: String) async throws

    /// Remove all expired entries from the cache
    /// - Returns: Number of entries pruned
    func pruneExpired() async throws -> Int

    /// Get current cache statistics
    func getStats() async throws -> FingerbankCacheStats

    /// Increment hit counter for a cache entry
    func incrementHit(mac: String) async throws
}

// MARK: - Cache Record

/// GRDB record type for fingerbank_cache table
public struct FingerbankCacheRecord: Codable, Sendable, FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "fingerbank_cache"

    public var mac: String
    public var fingerprintJson: String
    public var dhcpFingerprint: String?
    public var userAgents: String?
    public var signalHash: String
    public var fetchedAt: Date
    public var expiresAt: Date
    public var hitCount: Int
    public var lastHitAt: Date?

    enum CodingKeys: String, CodingKey {
        case mac
        case fingerprintJson = "fingerprint_json"
        case dhcpFingerprint = "dhcp_fingerprint"
        case userAgents = "user_agents"
        case signalHash = "signal_hash"
        case fetchedAt = "fetched_at"
        case expiresAt = "expires_at"
        case hitCount = "hit_count"
        case lastHitAt = "last_hit_at"
    }

    public init(
        mac: String,
        fingerprintJson: String,
        dhcpFingerprint: String?,
        userAgents: String?,
        signalHash: String,
        fetchedAt: Date,
        expiresAt: Date,
        hitCount: Int = 0,
        lastHitAt: Date? = nil
    ) {
        self.mac = mac
        self.fingerprintJson = fingerprintJson
        self.dhcpFingerprint = dhcpFingerprint
        self.userAgents = userAgents
        self.signalHash = signalHash
        self.fetchedAt = fetchedAt
        self.expiresAt = expiresAt
        self.hitCount = hitCount
        self.lastHitAt = lastHitAt
    }
}

// MARK: - Stats Record

/// GRDB record type for fingerbank_cache_stats table
public struct FingerbankCacheStatsRecord: Codable, Sendable, FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "fingerbank_cache_stats"

    public var id: Int
    public var totalEntries: Int
    public var totalHits: Int
    public var totalMisses: Int
    public var lastPruneAt: Date?
    public var lastSyncAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case totalEntries = "total_entries"
        case totalHits = "total_hits"
        case totalMisses = "total_misses"
        case lastPruneAt = "last_prune_at"
        case lastSyncAt = "last_sync_at"
    }

    public init(
        id: Int = 1,
        totalEntries: Int = 0,
        totalHits: Int = 0,
        totalMisses: Int = 0,
        lastPruneAt: Date? = nil,
        lastSyncAt: Date? = nil
    ) {
        self.id = id
        self.totalEntries = totalEntries
        self.totalHits = totalHits
        self.totalMisses = totalMisses
        self.lastPruneAt = lastPruneAt
        self.lastSyncAt = lastSyncAt
    }

    public func toStats() -> FingerbankCacheStats {
        FingerbankCacheStats(
            totalEntries: totalEntries,
            totalHits: totalHits,
            totalMisses: totalMisses,
            lastPruneAt: lastPruneAt,
            lastSyncAt: lastSyncAt
        )
    }
}

// MARK: - Repository Errors

public enum FingerbankCacheRepositoryError: Error, Sendable {
    case encodingFailed(String)
    case decodingFailed(String)
    case statsNotFound
}

// MARK: - Repository Implementation

/// SQLite-based implementation of Fingerbank cache persistence
public final class FingerbankCacheRepository: FingerbankCacheRepositoryProtocol, @unchecked Sendable {

    /// Default TTL for Fingerbank cache entries: 30 days
    public static let defaultTTL: TimeInterval = 2_592_000 // 30 days in seconds

    private let database: DatabaseProtocol
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // MARK: - Initialization

    public init(database: DatabaseProtocol = DatabaseManager.shared) {
        self.database = database

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - FingerbankCacheRepositoryProtocol

    public func get(mac: String, signalHash: String) async throws -> DeviceFingerprint? {
        let normalizedMac = mac.uppercased()
        let now = Date()

        return try await database.read { [decoder] db in
            guard let record = try FingerbankCacheRecord.fetchOne(db, key: normalizedMac) else {
                // Cache miss - record stats update will happen in caller
                return nil
            }

            // Check expiration
            if record.expiresAt < now {
                Log.debug("Cache entry expired for MAC \(normalizedMac)", category: .cache)
                return nil
            }

            // Check signal hash match (signals may have changed)
            if record.signalHash != signalHash {
                Log.debug("Cache entry signal mismatch for MAC \(normalizedMac)", category: .cache)
                return nil
            }

            // Decode fingerprint
            guard let jsonData = record.fingerprintJson.data(using: .utf8) else {
                throw FingerbankCacheRepositoryError.decodingFailed("Invalid JSON string for MAC \(normalizedMac)")
            }

            var fingerprint = try decoder.decode(DeviceFingerprint.self, from: jsonData)
            fingerprint.cacheHit = true

            Log.debug("Cache hit for MAC \(normalizedMac)", category: .cache)
            return fingerprint
        }
    }

    public func store(
        mac: String,
        fingerprint: DeviceFingerprint,
        signalHash: String,
        dhcpFingerprint: String?,
        userAgents: [String]?,
        ttl: TimeInterval
    ) async throws {
        let normalizedMac = mac.uppercased()
        let now = Date()
        let expiresAt = now.addingTimeInterval(ttl)

        // Encode fingerprint to JSON
        let jsonData = try encoder.encode(fingerprint)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw FingerbankCacheRepositoryError.encodingFailed("Failed to encode fingerprint for MAC \(normalizedMac)")
        }

        // Encode user agents array if present
        let userAgentsString: String?
        if let agents = userAgents {
            let agentsData = try encoder.encode(agents)
            userAgentsString = String(data: agentsData, encoding: .utf8)
        } else {
            userAgentsString = nil
        }

        let record = FingerbankCacheRecord(
            mac: normalizedMac,
            fingerprintJson: jsonString,
            dhcpFingerprint: dhcpFingerprint,
            userAgents: userAgentsString,
            signalHash: signalHash,
            fetchedAt: now,
            expiresAt: expiresAt,
            hitCount: 0,
            lastHitAt: nil
        )

        try await database.write { db in
            // Check if this is a new entry or update
            let existingCount = try FingerbankCacheRecord.filter(Column("mac") == normalizedMac).fetchCount(db)
            let isNewEntry = existingCount == 0

            try record.save(db, onConflict: .replace)

            // Update stats if this is a new entry
            if isNewEntry {
                try db.execute(sql: """
                    UPDATE fingerbank_cache_stats
                    SET total_entries = total_entries + 1
                    WHERE id = 1
                """)
            }
        }

        Log.debug("Stored cache entry for MAC \(normalizedMac), expires: \(expiresAt)", category: .cache)
    }

    public func invalidate(mac: String) async throws {
        let normalizedMac = mac.uppercased()

        let deleted = try await database.write { db -> Bool in
            let deletedCount = try FingerbankCacheRecord.deleteOne(db, key: normalizedMac)

            if deletedCount {
                try db.execute(sql: """
                    UPDATE fingerbank_cache_stats
                    SET total_entries = MAX(0, total_entries - 1)
                    WHERE id = 1
                """)
            }

            return deletedCount
        }

        if deleted {
            Log.debug("Invalidated cache entry for MAC \(normalizedMac)", category: .cache)
        }
    }

    public func pruneExpired() async throws -> Int {
        let now = Date()

        let prunedCount = try await database.write { db -> Int in
            // Count expired entries before deletion
            let expiredCount = try FingerbankCacheRecord
                .filter(Column("expires_at") < now)
                .fetchCount(db)

            if expiredCount > 0 {
                // Delete expired entries
                try db.execute(
                    sql: "DELETE FROM fingerbank_cache WHERE expires_at < ?",
                    arguments: [now]
                )

                // Update stats
                try db.execute(sql: """
                    UPDATE fingerbank_cache_stats
                    SET total_entries = MAX(0, total_entries - ?),
                        last_prune_at = ?
                    WHERE id = 1
                """, arguments: [expiredCount, now])
            } else {
                // Just update prune timestamp
                try db.execute(sql: """
                    UPDATE fingerbank_cache_stats
                    SET last_prune_at = ?
                    WHERE id = 1
                """, arguments: [now])
            }

            return expiredCount
        }

        if prunedCount > 0 {
            Log.info("Pruned \(prunedCount) expired cache entries", category: .cache)
        }

        return prunedCount
    }

    public func getStats() async throws -> FingerbankCacheStats {
        try await database.read { db in
            guard let statsRecord = try FingerbankCacheStatsRecord.fetchOne(db, key: 1) else {
                throw FingerbankCacheRepositoryError.statsNotFound
            }
            return statsRecord.toStats()
        }
    }

    public func incrementHit(mac: String) async throws {
        let normalizedMac = mac.uppercased()
        let now = Date()

        try await database.write { db in
            // Update cache entry hit count
            try db.execute(sql: """
                UPDATE fingerbank_cache
                SET hit_count = hit_count + 1,
                    last_hit_at = ?
                WHERE mac = ?
            """, arguments: [now, normalizedMac])

            // Update global hit count
            try db.execute(sql: """
                UPDATE fingerbank_cache_stats
                SET total_hits = total_hits + 1
                WHERE id = 1
            """)
        }
    }

    // MARK: - Additional Utility Methods

    /// Record a cache miss in statistics
    public func recordMiss() async throws {
        try await database.write { db in
            try db.execute(sql: """
                UPDATE fingerbank_cache_stats
                SET total_misses = total_misses + 1
                WHERE id = 1
            """)
        }
    }

    /// Update the last sync timestamp
    public func updateSyncTimestamp() async throws {
        let now = Date()
        try await database.write { db in
            try db.execute(sql: """
                UPDATE fingerbank_cache_stats
                SET last_sync_at = ?
                WHERE id = 1
            """, arguments: [now])
        }
    }

    /// Get all cached entries (for debugging/export)
    public func fetchAll() async throws -> [FingerbankCacheRecord] {
        try await database.read { db in
            try FingerbankCacheRecord.fetchAll(db)
        }
    }

    /// Get count of valid (non-expired) entries
    public func countValid() async throws -> Int {
        let now = Date()
        return try await database.read { db in
            try FingerbankCacheRecord
                .filter(Column("expires_at") >= now)
                .fetchCount(db)
        }
    }

    /// Clear all cache entries
    public func deleteAll() async throws {
        try await database.write { db in
            try FingerbankCacheRecord.deleteAll(db)

            // Reset stats
            try db.execute(sql: """
                UPDATE fingerbank_cache_stats
                SET total_entries = 0,
                    total_hits = 0,
                    total_misses = 0,
                    last_prune_at = NULL,
                    last_sync_at = NULL
                WHERE id = 1
            """)
        }

        Log.info("Cleared all Fingerbank cache entries", category: .cache)
    }
}

// MARK: - Signal Hash Utility

extension FingerbankCacheRepository {
    /// Generate a signal hash for cache key validation
    /// This hash changes when the device's network signals change, invalidating stale cache entries
    public static func generateSignalHash(mac: String, dhcpFingerprint: String?, userAgents: [String]?) -> String {
        var combined = mac.uppercased()

        if let dhcp = dhcpFingerprint, !dhcp.isEmpty {
            combined += ":\(dhcp)"
        }

        if let agents = userAgents, !agents.isEmpty {
            combined += ":\(agents.sorted().joined(separator: ","))"
        }

        let hash = SHA256.hash(data: Data(combined.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
