import Foundation
import GRDB

// MARK: - Database Protocol

/// Protocol for database operations, enabling testability
public protocol DatabaseProtocol: Sendable {
    /// Execute a read operation
    func read<T: Sendable>(_ block: @Sendable @escaping (GRDB.Database) throws -> T) async throws -> T
    
    /// Execute a write operation
    func write<T: Sendable>(_ block: @Sendable @escaping (GRDB.Database) throws -> T) async throws -> T
}

// MARK: - Database Errors

public enum DatabaseError: Error, Sendable {
    case initializationFailed(String)
    case migrationFailed(String)
    case invalidPath
    case connectionClosed
}

// MARK: - Database Manager

/// GRDB-based database manager for LanLens device persistence
public final class DatabaseManager: DatabaseProtocol, @unchecked Sendable {
    
    /// Shared instance for production use
    public static let shared: DatabaseManager = {
        do {
            return try DatabaseManager()
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }()
    
    /// The underlying GRDB database pool
    private let dbPool: DatabasePool
    
    /// Current schema version
    private static let schemaVersion = 1
    
    // MARK: - Initialization
    
    /// Initialize with the default database path
    public convenience init() throws {
        let path = try Self.defaultDatabasePath()
        try self.init(path: path)
    }
    
    /// Initialize with a custom database path
    public init(path: String) throws {
        // Create directory if needed
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        
        // Configure database
        var config = Configuration()
        config.prepareDatabase { db in
            // Enable foreign keys
            db.trace { print("SQL: \($0)") }
        }
        
        // Open database pool
        dbPool = try DatabasePool(path: path, configuration: config)
        
        // Run migrations
        try runMigrations()
    }
    
    /// Initialize with an in-memory database (for testing)
    public init(inMemory: Bool) throws {
        guard inMemory else {
            throw DatabaseError.invalidPath
        }
        
        var config = Configuration()
        config.prepareDatabase { db in
            // SQLite in-memory databases are destroyed when the connection closes
        }
        
        dbPool = try DatabasePool(path: ":memory:", configuration: config)
        try runMigrations()
    }
    
    // MARK: - Database Path
    
    /// Returns the default database path in Application Support
    public static func defaultDatabasePath() throws -> String {
        let fileManager = FileManager.default
        
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw DatabaseError.initializationFailed("Could not find Application Support directory")
        }
        
        let lanLensDir = appSupport.appendingPathComponent("LanLens", isDirectory: true)
        return lanLensDir.appendingPathComponent("devices.sqlite").path
    }
    
    // MARK: - Migrations
    
    private func runMigrations() throws {
        var migrator = DatabaseMigrator()
        
        // Version 1: Initial schema
        migrator.registerMigration("v1_initial") { db in
            // Create devices table
            try db.create(table: "devices", ifNotExists: true) { t in
                t.column("mac", .text).primaryKey()
                t.column("id", .text).notNull()
                t.column("ip", .text).notNull()
                t.column("hostname", .text)
                t.column("vendor", .text)
                t.column("firstSeen", .datetime).notNull()
                t.column("lastSeen", .datetime).notNull()
                t.column("isOnline", .boolean).notNull().defaults(to: true)
                t.column("smartScore", .integer).notNull().defaults(to: 0)
                t.column("deviceType", .text).notNull().defaults(to: "unknown")
                t.column("userLabel", .text)
                t.column("openPorts", .text).notNull().defaults(to: "[]")
                t.column("services", .text).notNull().defaults(to: "[]")
                t.column("httpInfo", .text)
                t.column("smartSignals", .text).notNull().defaults(to: "[]")
                t.column("fingerprint", .text)
            }

            // Create indexes for common queries
            try db.create(index: "idx_devices_ip", on: "devices", columns: ["ip"])
            try db.create(index: "idx_devices_lastSeen", on: "devices", columns: ["lastSeen"])
            try db.create(index: "idx_devices_isOnline", on: "devices", columns: ["isOnline"])
        }

        // Version 2: Enhanced inference fields (Issue #2)
        migrator.registerMigration("v2_enhanced_inference") { db in
            try db.alter(table: "devices") { t in
                t.add(column: "mdnsTXTRecords", .text)
                t.add(column: "portBanners", .text)
                t.add(column: "macAnalysis", .text)
                t.add(column: "securityPosture", .text)
                t.add(column: "behaviorProfile", .text)
            }
        }

        // Version 3: Network source information for multi-VLAN support (Issue #6)
        migrator.registerMigration("v3_network_source") { db in
            try db.alter(table: "devices") { t in
                t.add(column: "sourceInterface", .text)
                t.add(column: "subnet", .text)
            }
            // Index for filtering by interface/subnet
            try db.create(index: "idx_devices_sourceInterface", on: "devices", columns: ["sourceInterface"])
            try db.create(index: "idx_devices_subnet", on: "devices", columns: ["subnet"])
        }

        // Version 4: Presence records table for behavior tracking (Issue #4)
        migrator.registerMigration("v4_presence_records") { db in
            // Create presence_records table for historical behavior tracking
            try db.create(table: "presence_records", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("mac", .text).notNull().indexed()
                t.column("timestamp", .datetime).notNull().indexed()
                t.column("isOnline", .boolean).notNull()
                t.column("ipAddress", .text)
                t.column("availableServices", .text).notNull().defaults(to: "[]")
                t.foreignKey(["mac"], references: "devices", columns: ["mac"], onDelete: .cascade)
            }

            // Composite index for efficient time-range queries per device
            try db.create(index: "idx_presence_mac_timestamp", on: "presence_records", columns: ["mac", "timestamp"])
        }

        // Version 5: Fingerbank cache tables (replaces file-based cache)
        migrator.registerMigration("v5_fingerbank_cache") { db in
            // Create fingerbank_cache table for SQLite-based fingerprint caching
            try db.create(table: "fingerbank_cache", ifNotExists: true) { t in
                t.column("mac", .text).primaryKey()
                t.column("fingerprint_json", .text).notNull()
                t.column("dhcp_fingerprint", .text)
                t.column("user_agents", .text)
                t.column("signal_hash", .text).notNull()
                t.column("fetched_at", .datetime).notNull()
                t.column("expires_at", .datetime).notNull()
                t.column("hit_count", .integer).notNull().defaults(to: 0)
                t.column("last_hit_at", .datetime)
            }

            // Index for expiration-based queries (pruning)
            try db.create(index: "idx_fingerbank_cache_expires", on: "fingerbank_cache", columns: ["expires_at"])

            // Index for signal hash lookups (cache validation)
            try db.create(index: "idx_fingerbank_cache_signal_hash", on: "fingerbank_cache", columns: ["signal_hash"])

            // Create cache statistics singleton table
            try db.create(table: "fingerbank_cache_stats", ifNotExists: true) { t in
                t.column("id", .integer).primaryKey().check { $0 == 1 }
                t.column("total_entries", .integer).notNull().defaults(to: 0)
                t.column("total_hits", .integer).notNull().defaults(to: 0)
                t.column("total_misses", .integer).notNull().defaults(to: 0)
                t.column("last_prune_at", .datetime)
                t.column("last_sync_at", .datetime)
            }

            // Insert singleton row for statistics
            try db.execute(sql: """
                INSERT INTO fingerbank_cache_stats (id, total_entries, total_hits, total_misses)
                VALUES (1, 0, 0, 0)
            """)
        }

        // Apply migrations
        try migrator.migrate(dbPool)
    }
    
    // MARK: - DatabaseProtocol
    
    public func read<T: Sendable>(_ block: @Sendable @escaping (GRDB.Database) throws -> T) async throws -> T {
        try await dbPool.read(block)
    }
    
    public func write<T: Sendable>(_ block: @Sendable @escaping (GRDB.Database) throws -> T) async throws -> T {
        try await dbPool.write(block)
    }
    
    // MARK: - Utility
    
    /// Delete the database file (useful for testing or reset)
    public static func deleteDatabase() throws {
        let path = try defaultDatabasePath()
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: path) {
            try fileManager.removeItem(atPath: path)
        }
        // Also remove WAL and SHM files
        let walPath = path + "-wal"
        let shmPath = path + "-shm"
        if fileManager.fileExists(atPath: walPath) {
            try fileManager.removeItem(atPath: walPath)
        }
        if fileManager.fileExists(atPath: shmPath) {
            try fileManager.removeItem(atPath: shmPath)
        }
    }
}
