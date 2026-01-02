import Foundation
import GRDB

// MARK: - Presence Repository Protocol

/// Protocol for presence record persistence operations
public protocol PresenceRepositoryProtocol: Sendable {
    /// Record a single presence observation
    func recordPresence(mac: String, isOnline: Bool, ip: String?, services: [String], timestamp: Date) async throws
    
    /// Record multiple presence observations in a batch
    func recordPresenceBatch(_ records: [(mac: String, isOnline: Bool, ip: String?, services: [String], timestamp: Date)]) async throws
    
    /// Fetch presence history for a device since a given date
    func fetchHistory(mac: String, since: Date?) async throws -> [PresenceRecord]
    
    /// Fetch presence history for a device within a time range
    func fetchHistory(mac: String, from startDate: Date, to endDate: Date) async throws -> [PresenceRecord]
    
    /// Get all device MACs that were seen between two dates
    func fetchDevicesSeenBetween(start: Date, end: Date) async throws -> [String]
    
    /// Prune old records older than a given date
    func pruneOldRecords(olderThan: Date) async throws -> Int
    
    /// Get the count of presence records for a device
    func countRecords(mac: String) async throws -> Int
    
    /// Get the total count of all presence records
    func countAllRecords() async throws -> Int
    
    /// Delete all presence records for a device
    func deleteRecords(mac: String) async throws
    
    /// Calculate uptime statistics for a device
    func calculateUptimeStats(mac: String, since: Date?) async throws -> UptimeStats
}

// MARK: - Uptime Statistics

/// Statistics calculated from presence history
public struct UptimeStats: Sendable {
    /// Total number of observations
    public let totalObservations: Int
    
    /// Number of online observations
    public let onlineObservations: Int
    
    /// Uptime percentage (0-100)
    public let uptimePercent: Double
    
    /// First observation timestamp
    public let firstSeen: Date?
    
    /// Last observation timestamp
    public let lastSeen: Date?
    
    public init(
        totalObservations: Int = 0,
        onlineObservations: Int = 0,
        uptimePercent: Double = 0,
        firstSeen: Date? = nil,
        lastSeen: Date? = nil
    ) {
        self.totalObservations = totalObservations
        self.onlineObservations = onlineObservations
        self.uptimePercent = uptimePercent
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }
}

// MARK: - Presence Record DB Model

/// GRDB record type for presence_records table
public struct PresenceRecordDB: Codable, Sendable, FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "presence_records"
    
    /// Auto-incremented primary key
    public var id: Int64?
    
    /// Device MAC address (foreign key to devices)
    public var mac: String
    
    /// Timestamp of observation
    public var timestamp: Date
    
    /// Whether device was online
    public var isOnline: Bool
    
    /// IP address at time of observation
    public var ipAddress: String?
    
    /// JSON-encoded available services
    public var availableServices: String
    
    // MARK: - Initialization
    
    public init(
        id: Int64? = nil,
        mac: String,
        timestamp: Date,
        isOnline: Bool,
        ipAddress: String?,
        availableServices: String = "[]"
    ) {
        self.id = id
        self.mac = mac.uppercased()
        self.timestamp = timestamp
        self.isOnline = isOnline
        self.ipAddress = ipAddress
        self.availableServices = availableServices
    }
    
    /// Create from domain model
    public init(mac: String, from record: PresenceRecord) throws {
        let encoder = JSONEncoder()
        let servicesJson = String(data: try encoder.encode(record.availableServices), encoding: .utf8) ?? "[]"
        
        self.init(
            mac: mac,
            timestamp: record.timestamp,
            isOnline: record.isOnline,
            ipAddress: record.ipAddress,
            availableServices: servicesJson
        )
    }
    
    /// Convert to domain model
    public func toPresenceRecord() throws -> PresenceRecord {
        let decoder = JSONDecoder()
        let services = try decoder.decode([String].self, from: Data(availableServices.utf8))
        
        return PresenceRecord(
            timestamp: timestamp,
            isOnline: isOnline,
            availableServices: services,
            ipAddress: ipAddress
        )
    }
    
    // MARK: - GRDB TableRecord
    
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Repository Errors

public enum PresenceRepositoryError: Error, Sendable {
    case encodingFailed(String)
    case decodingFailed(String)
    case deviceNotFound(String)
}

// MARK: - Presence Repository Implementation

/// GRDB-based implementation of presence record persistence
public final class PresenceRepository: PresenceRepositoryProtocol, @unchecked Sendable {
    
    private let database: DatabaseProtocol
    
    // MARK: - Initialization
    
    public init(database: DatabaseProtocol = DatabaseManager.shared) {
        self.database = database
    }
    
    // MARK: - Record Operations
    
    public func recordPresence(
        mac: String,
        isOnline: Bool,
        ip: String?,
        services: [String],
        timestamp: Date = Date()
    ) async throws {
        let normalizedMac = mac.uppercased()
        
        let encoder = JSONEncoder()
        let servicesJson = String(data: try encoder.encode(services), encoding: .utf8) ?? "[]"
        
        let record = PresenceRecordDB(
            mac: normalizedMac,
            timestamp: timestamp,
            isOnline: isOnline,
            ipAddress: ip,
            availableServices: servicesJson
        )
        
        try await database.write { db in
            try record.insert(db)
        }
    }
    
    public func recordPresenceBatch(
        _ records: [(mac: String, isOnline: Bool, ip: String?, services: [String], timestamp: Date)]
    ) async throws {
        guard !records.isEmpty else { return }

        let encoder = JSONEncoder()
        var dbRecords: [PresenceRecordDB] = []

        for record in records {
            let servicesJson = String(data: try encoder.encode(record.services), encoding: .utf8) ?? "[]"
            dbRecords.append(PresenceRecordDB(
                mac: record.mac.uppercased(),
                timestamp: record.timestamp,
                isOnline: record.isOnline,
                ipAddress: record.ip,
                availableServices: servicesJson
            ))
        }

        // Capture as let to satisfy Sendable requirement
        let recordsToInsert = dbRecords
        try await database.write { db in
            for record in recordsToInsert {
                try record.insert(db)
            }
        }
    }
    
    // MARK: - Query Operations
    
    public func fetchHistory(mac: String, since: Date?) async throws -> [PresenceRecord] {
        let normalizedMac = mac.uppercased()
        
        return try await database.read { db in
            var query = PresenceRecordDB
                .filter(Column("mac") == normalizedMac)
                .order(Column("timestamp").desc)
            
            if let since = since {
                query = query.filter(Column("timestamp") >= since)
            }
            
            let records = try query.fetchAll(db)
            return try records.map { try $0.toPresenceRecord() }
        }
    }
    
    public func fetchHistory(mac: String, from startDate: Date, to endDate: Date) async throws -> [PresenceRecord] {
        let normalizedMac = mac.uppercased()
        
        return try await database.read { db in
            let records = try PresenceRecordDB
                .filter(Column("mac") == normalizedMac)
                .filter(Column("timestamp") >= startDate)
                .filter(Column("timestamp") <= endDate)
                .order(Column("timestamp").desc)
                .fetchAll(db)
            
            return try records.map { try $0.toPresenceRecord() }
        }
    }
    
    public func fetchDevicesSeenBetween(start: Date, end: Date) async throws -> [String] {
        try await database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT mac FROM presence_records
                    WHERE timestamp >= ? AND timestamp <= ?
                    ORDER BY mac
                    """,
                arguments: [start, end]
            )
            return rows.map { $0["mac"] as String }
        }
    }
    
    public func countRecords(mac: String) async throws -> Int {
        let normalizedMac = mac.uppercased()
        
        return try await database.read { db in
            try PresenceRecordDB
                .filter(Column("mac") == normalizedMac)
                .fetchCount(db)
        }
    }
    
    public func countAllRecords() async throws -> Int {
        try await database.read { db in
            try PresenceRecordDB.fetchCount(db)
        }
    }
    
    // MARK: - Delete Operations
    
    public func deleteRecords(mac: String) async throws {
        let normalizedMac = mac.uppercased()
        
        _ = try await database.write { db in
            try PresenceRecordDB
                .filter(Column("mac") == normalizedMac)
                .deleteAll(db)
        }
    }
    
    public func pruneOldRecords(olderThan: Date) async throws -> Int {
        try await database.write { db in
            try PresenceRecordDB
                .filter(Column("timestamp") < olderThan)
                .deleteAll(db)
        }
    }
    
    // MARK: - Statistics
    
    public func calculateUptimeStats(mac: String, since: Date?) async throws -> UptimeStats {
        let normalizedMac = mac.uppercased()
        
        return try await database.read { db in
            var query = PresenceRecordDB
                .filter(Column("mac") == normalizedMac)
            
            if let since = since {
                query = query.filter(Column("timestamp") >= since)
            }
            
            let records = try query.fetchAll(db)
            
            guard !records.isEmpty else {
                return UptimeStats()
            }
            
            let totalCount = records.count
            let onlineCount = records.filter { $0.isOnline }.count
            let uptimePercent = (Double(onlineCount) / Double(totalCount)) * 100.0
            
            let sortedByTime = records.sorted { $0.timestamp < $1.timestamp }
            let firstSeen = sortedByTime.first?.timestamp
            let lastSeen = sortedByTime.last?.timestamp
            
            return UptimeStats(
                totalObservations: totalCount,
                onlineObservations: onlineCount,
                uptimePercent: uptimePercent,
                firstSeen: firstSeen,
                lastSeen: lastSeen
            )
        }
    }
    
    // MARK: - Advanced Queries
    
    /// Get the most recent presence record for a device
    public func fetchLatestRecord(mac: String) async throws -> PresenceRecord? {
        let normalizedMac = mac.uppercased()
        
        return try await database.read { db in
            guard let record = try PresenceRecordDB
                .filter(Column("mac") == normalizedMac)
                .order(Column("timestamp").desc)
                .fetchOne(db)
            else {
                return nil
            }
            return try record.toPresenceRecord()
        }
    }
    
    /// Get peak activity hours for a device (returns hours 0-23 with activity counts)
    public func fetchPeakHours(mac: String, since: Date?) async throws -> [Int: Int] {
        let normalizedMac = mac.uppercased()
        
        return try await database.read { db in
            var query = PresenceRecordDB
                .filter(Column("mac") == normalizedMac)
                .filter(Column("isOnline") == true)
            
            if let since = since {
                query = query.filter(Column("timestamp") >= since)
            }
            
            let records = try query.fetchAll(db)
            
            var hourCounts: [Int: Int] = [:]
            let calendar = Calendar.current
            
            for record in records {
                let hour = calendar.component(.hour, from: record.timestamp)
                hourCounts[hour, default: 0] += 1
            }
            
            return hourCounts
        }
    }
}
