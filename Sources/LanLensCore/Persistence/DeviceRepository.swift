import Foundation
import GRDB

// MARK: - Device Repository Protocol

/// Protocol for device persistence operations, enabling testability
public protocol DeviceRepositoryProtocol: Sendable {
    /// Save a single device
    func save(device: Device) async throws
    
    /// Save multiple devices in a batch
    func saveAll(devices: [Device]) async throws
    
    /// Fetch a device by MAC address
    func fetch(mac: String) async throws -> Device?
    
    /// Fetch all devices
    func fetchAll() async throws -> [Device]
    
    /// Delete a device by MAC address
    func delete(mac: String) async throws
    
    /// Delete all devices
    func deleteAll() async throws
    
    /// Fetch devices matching a predicate
    func fetch(where predicate: @Sendable @escaping (DeviceRecord) -> Bool) async throws -> [Device]
    
    /// Count total devices
    func count() async throws -> Int

    /// Mark all devices as offline
    func markAllOffline() async throws
}

// MARK: - Device Record

/// GRDB record type for Device persistence
public struct DeviceRecord: Codable, Sendable, FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "devices"
    
    // Primary key
    public var mac: String
    
    // Core fields
    public var id: String
    public var ip: String
    public var hostname: String?
    public var vendor: String?
    public var firstSeen: Date
    public var lastSeen: Date
    public var isOnline: Bool
    public var smartScore: Int
    public var deviceType: String
    public var userLabel: String?
    
    // JSON-encoded complex fields
    public var openPorts: String
    public var services: String
    public var httpInfo: String?
    public var smartSignals: String
    public var fingerprint: String?
    
    // MARK: - Conversion from Device
    
    public init(from device: Device) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        self.mac = device.mac
        self.id = device.id.uuidString
        self.ip = device.ip
        self.hostname = device.hostname
        self.vendor = device.vendor
        self.firstSeen = device.firstSeen
        self.lastSeen = device.lastSeen
        self.isOnline = device.isOnline
        self.smartScore = device.smartScore
        self.deviceType = device.deviceType.rawValue
        self.userLabel = device.userLabel
        
        // Encode complex types as JSON
        self.openPorts = String(data: try encoder.encode(device.openPorts), encoding: .utf8) ?? "[]"
        self.services = String(data: try encoder.encode(device.services), encoding: .utf8) ?? "[]"
        
        if let httpInfo = device.httpInfo {
            self.httpInfo = String(data: try encoder.encode(httpInfo), encoding: .utf8)
        } else {
            self.httpInfo = nil
        }
        
        self.smartSignals = String(data: try encoder.encode(device.smartSignals), encoding: .utf8) ?? "[]"
        
        if let fingerprint = device.fingerprint {
            self.fingerprint = String(data: try encoder.encode(fingerprint), encoding: .utf8)
        } else {
            self.fingerprint = nil
        }
    }
    
    // MARK: - Conversion to Device
    
    public func toDevice() throws -> Device {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        guard let uuid = UUID(uuidString: id) else {
            throw DeviceRepositoryError.invalidUUID(id)
        }
        
        let decodedPorts: [Port] = try decoder.decode([Port].self, from: Data(openPorts.utf8))
        let decodedServices: [DiscoveredService] = try decoder.decode([DiscoveredService].self, from: Data(services.utf8))
        
        let decodedHttpInfo: HTTPInfo?
        if let httpInfoJson = httpInfo {
            decodedHttpInfo = try decoder.decode(HTTPInfo.self, from: Data(httpInfoJson.utf8))
        } else {
            decodedHttpInfo = nil
        }
        
        let decodedSignals: [SmartSignal] = try decoder.decode([SmartSignal].self, from: Data(smartSignals.utf8))
        
        let decodedFingerprint: DeviceFingerprint?
        if let fingerprintJson = fingerprint {
            decodedFingerprint = try decoder.decode(DeviceFingerprint.self, from: Data(fingerprintJson.utf8))
        } else {
            decodedFingerprint = nil
        }
        
        guard let deviceTypeEnum = DeviceType(rawValue: deviceType) else {
            throw DeviceRepositoryError.invalidDeviceType(deviceType)
        }
        
        return Device(
            id: uuid,
            mac: mac,
            ip: ip,
            hostname: hostname,
            vendor: vendor,
            firstSeen: firstSeen,
            lastSeen: lastSeen,
            isOnline: isOnline,
            openPorts: decodedPorts,
            services: decodedServices,
            httpInfo: decodedHttpInfo,
            smartScore: smartScore,
            smartSignals: decodedSignals,
            deviceType: deviceTypeEnum,
            userLabel: userLabel,
            fingerprint: decodedFingerprint
        )
    }
}

// MARK: - Repository Errors

public enum DeviceRepositoryError: Error, Sendable {
    case invalidUUID(String)
    case invalidDeviceType(String)
    case encodingFailed(String)
    case decodingFailed(String)
}

// MARK: - Device Repository Implementation

/// GRDB-based implementation of device persistence
public final class DeviceRepository: DeviceRepositoryProtocol, @unchecked Sendable {
    
    private let database: DatabaseProtocol
    
    // MARK: - Initialization
    
    public init(database: DatabaseProtocol = DatabaseManager.shared) {
        self.database = database
    }
    
    // MARK: - CRUD Operations
    
    public func save(device: Device) async throws {
        let record = try DeviceRecord(from: device)
        try await database.write { db in
            try record.save(db, onConflict: .replace)
        }
    }
    
    public func saveAll(devices: [Device]) async throws {
        guard !devices.isEmpty else { return }
        
        let records = try devices.map { try DeviceRecord(from: $0) }
        
        try await database.write { db in
            for record in records {
                try record.save(db, onConflict: .replace)
            }
        }
    }
    
    public func fetch(mac: String) async throws -> Device? {
        let normalizedMac = mac.uppercased()
        
        return try await database.read { db in
            guard let record = try DeviceRecord.fetchOne(db, key: normalizedMac) else {
                return nil
            }
            return try record.toDevice()
        }
    }
    
    public func fetchAll() async throws -> [Device] {
        try await database.read { db in
            let records = try DeviceRecord.fetchAll(db)
            return try records.map { try $0.toDevice() }
        }
    }
    
    public func delete(mac: String) async throws {
        let normalizedMac = mac.uppercased()
        
        _ = try await database.write { db in
            try DeviceRecord.deleteOne(db, key: normalizedMac)
        }
    }
    
    public func deleteAll() async throws {
        _ = try await database.write { db in
            try DeviceRecord.deleteAll(db)
        }
    }
    
    public func fetch(where predicate: @Sendable @escaping (DeviceRecord) -> Bool) async throws -> [Device] {
        try await database.read { db in
            let allRecords = try DeviceRecord.fetchAll(db)
            let filteredRecords = allRecords.filter(predicate)
            return try filteredRecords.map { try $0.toDevice() }
        }
    }
    
    public func count() async throws -> Int {
        try await database.read { db in
            try DeviceRecord.fetchCount(db)
        }
    }
    
    // MARK: - Specialized Queries
    
    /// Fetch all online devices
    public func fetchOnlineDevices() async throws -> [Device] {
        try await database.read { db in
            let records = try DeviceRecord
                .filter(Column("isOnline") == true)
                .fetchAll(db)
            return try records.map { try $0.toDevice() }
        }
    }
    
    /// Fetch devices seen after a specific date
    public func fetchDevicesSeenAfter(_ date: Date) async throws -> [Device] {
        try await database.read { db in
            let records = try DeviceRecord
                .filter(Column("lastSeen") >= date)
                .fetchAll(db)
            return try records.map { try $0.toDevice() }
        }
    }
    
    /// Mark all devices as offline
    public func markAllOffline() async throws {
        try await database.write { db in
            try db.execute(sql: "UPDATE devices SET isOnline = 0")
        }
    }
    
    /// Update only the online status and lastSeen for a device
    public func updateOnlineStatus(mac: String, isOnline: Bool, lastSeen: Date) async throws {
        let normalizedMac = mac.uppercased()
        
        try await database.write { db in
            try db.execute(
                sql: "UPDATE devices SET isOnline = ?, lastSeen = ? WHERE mac = ?",
                arguments: [isOnline, lastSeen, normalizedMac]
            )
        }
    }
}
