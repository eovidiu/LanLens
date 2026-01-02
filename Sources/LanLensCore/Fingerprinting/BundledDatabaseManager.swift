import Foundation
import GRDB

// MARK: - Bundled Fingerprint Entry

/// A fingerprint entry from the bundled offline database
public struct BundledFingerprintEntry: Codable, Sendable, Equatable {
    /// Human-readable device name (e.g., "Apple iPhone 15 Pro")
    public var deviceName: String

    /// Device type categories that map to DeviceType enum (e.g., ["phone", "smartTV"])
    public var deviceTypes: [String]

    /// Device vendor/manufacturer (e.g., "Apple Inc.")
    public var vendor: String?

    /// Operating system name (e.g., "iOS", "Android")
    public var operatingSystem: String?

    /// Confidence score for this match (0.0 to 1.0)
    public var confidence: Double

    public init(
        deviceName: String,
        deviceTypes: [String],
        vendor: String? = nil,
        operatingSystem: String? = nil,
        confidence: Double
    ) {
        self.deviceName = deviceName
        self.deviceTypes = deviceTypes
        self.vendor = vendor
        self.operatingSystem = operatingSystem
        self.confidence = min(1.0, max(0.0, confidence))
    }

    /// Convert device type strings to DeviceType enum values
    public var inferredDeviceTypes: [DeviceType] {
        deviceTypes.compactMap { typeString in
            DeviceType(rawValue: typeString.lowercased())
        }
    }

    /// Best available device type from the entry
    public var primaryDeviceType: DeviceType {
        inferredDeviceTypes.first ?? .unknown
    }
}

// MARK: - Bundled Database Metadata

/// Metadata about the bundled fingerprint database
public struct BundledDatabaseMetadata: Sendable {
    /// Database version string
    public var version: String

    /// Total number of entries in the database
    public var entryCount: Int

    /// Whether the database has been successfully loaded
    public var isLoaded: Bool

    /// Error message if loading failed
    public var loadError: String?

    /// When the database was last loaded into memory
    public var lastLoadedAt: Date?

    public init(
        version: String = "0.0.0",
        entryCount: Int = 0,
        isLoaded: Bool = false,
        loadError: String? = nil,
        lastLoadedAt: Date? = nil
    ) {
        self.version = version
        self.entryCount = entryCount
        self.isLoaded = isLoaded
        self.loadError = loadError
        self.lastLoadedAt = lastLoadedAt
    }
}

// MARK: - Protocol

/// Protocol for querying the bundled offline fingerprint database
public protocol BundledDatabaseManagerProtocol: Sendable {
    /// Query bundled database by MAC OUI prefix (first 3 bytes, e.g., "00:0E:58")
    func queryByOUI(_ oui: String) async -> BundledFingerprintEntry?

    /// Query bundled database by DHCP fingerprint hash
    func queryByDHCPHash(_ hash: String) async -> BundledFingerprintEntry?

    /// Get database metadata (version, entry count, loaded status)
    func getMetadata() async -> BundledDatabaseMetadata

    /// Check if bundled database is available
    var isAvailable: Bool { get async }
}

// MARK: - GRDB Record Types

/// GRDB record for OUI (MAC prefix) lookups
struct BundledOUIRecord: Codable, FetchableRecord, TableRecord {
    static let databaseTableName = "oui_entries"

    var oui: String
    var deviceName: String
    var deviceTypes: String  // JSON array
    var vendor: String?
    var operatingSystem: String?
    var confidence: Double

    enum CodingKeys: String, CodingKey {
        case oui
        case deviceName = "device_name"
        case deviceTypes = "device_types"
        case vendor
        case operatingSystem = "operating_system"
        case confidence
    }
}

/// GRDB record for DHCP fingerprint lookups
struct BundledDHCPRecord: Codable, FetchableRecord, TableRecord {
    static let databaseTableName = "dhcp_entries"

    var dhcpHash: String
    var deviceName: String
    var deviceTypes: String  // JSON array
    var vendor: String?
    var operatingSystem: String?
    var confidence: Double

    enum CodingKeys: String, CodingKey {
        case dhcpHash = "dhcp_hash"
        case deviceName = "device_name"
        case deviceTypes = "device_types"
        case vendor
        case operatingSystem = "operating_system"
        case confidence
    }
}

/// GRDB record for database metadata
struct BundledMetadataRecord: Codable, FetchableRecord, TableRecord {
    static let databaseTableName = "metadata"

    var key: String
    var value: String
}

// MARK: - Implementation

/// Actor-based manager for the bundled offline fingerprint database
/// Loads fingerprint data shipped with the app for offline device identification
public actor BundledDatabaseManager: BundledDatabaseManagerProtocol {

    /// Shared instance
    public static let shared = BundledDatabaseManager()

    /// Resource name for the bundled database file
    private static let bundledDatabaseName = "fingerprints"
    private static let bundledDatabaseExtension = "sqlite"

    /// Cached database connection
    private var dbQueue: DatabaseQueue?

    /// Cached metadata
    private var metadata: BundledDatabaseMetadata

    /// JSON decoder for parsing device types array
    private let decoder: JSONDecoder

    // MARK: - Initialization

    public init() {
        self.metadata = BundledDatabaseMetadata()
        self.decoder = JSONDecoder()

        // Defer database loading to first access
        // This avoids blocking app startup
    }

    // MARK: - Database Loading

    /// Load the bundled database if not already loaded
    private func ensureLoaded() async {
        guard dbQueue == nil else { return }

        do {
            try await loadDatabase()
        } catch {
            Log.warning("Failed to load bundled fingerprint database: \(error.localizedDescription)", category: .fingerprinting)
            metadata.loadError = error.localizedDescription
            metadata.isLoaded = false
        }
    }

    /// Load the bundled SQLite database from app resources
    private func loadDatabase() async throws {
        // Look for the database in the app bundle
        guard let dbURL = Bundle.main.url(
            forResource: Self.bundledDatabaseName,
            withExtension: Self.bundledDatabaseExtension
        ) else {
            Log.info("Bundled fingerprint database not found in app bundle - offline lookup disabled", category: .fingerprinting)
            metadata.loadError = "Database file not found in bundle"
            metadata.isLoaded = false
            return
        }

        Log.debug("Loading bundled fingerprint database from: \(dbURL.path)", category: .fingerprinting)

        // Open database in read-only mode
        var config = Configuration()
        config.readonly = true

        dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)

        // Load metadata
        try await loadMetadata()

        metadata.isLoaded = true
        metadata.lastLoadedAt = Date()
        metadata.loadError = nil

        Log.info("Bundled fingerprint database loaded: version=\(metadata.version), entries=\(metadata.entryCount)", category: .fingerprinting)
    }

    /// Load metadata from the database
    private func loadMetadata() async throws {
        guard let db = dbQueue else { return }

        let (version, entryCount) = try await db.read { dbConnection -> (String?, Int) in
            // Read version from metadata table
            let versionValue: String?
            if let versionRecord = try BundledMetadataRecord
                .filter(Column("key") == "version")
                .fetchOne(dbConnection) {
                versionValue = versionRecord.value
            } else {
                versionValue = nil
            }

            // Count OUI entries
            let ouiCount = try BundledOUIRecord.fetchCount(dbConnection)

            // Count DHCP entries
            let dhcpCount = try BundledDHCPRecord.fetchCount(dbConnection)

            return (versionValue, ouiCount + dhcpCount)
        }

        // Update metadata outside the closure
        if let version = version {
            metadata.version = version
        }
        metadata.entryCount = entryCount
    }

    // MARK: - BundledDatabaseManagerProtocol

    public var isAvailable: Bool {
        get async {
            await ensureLoaded()
            return dbQueue != nil && metadata.isLoaded
        }
    }

    public func getMetadata() async -> BundledDatabaseMetadata {
        await ensureLoaded()
        return metadata
    }

    public func queryByOUI(_ oui: String) async -> BundledFingerprintEntry? {
        await ensureLoaded()

        guard let db = dbQueue else {
            Log.debug("Bundled database not available for OUI query", category: .fingerprinting)
            return nil
        }

        // Normalize OUI: uppercase, remove separators, take first 6 hex chars
        let normalizedOUI = normalizeOUI(oui)
        guard !normalizedOUI.isEmpty else {
            Log.debug("Invalid OUI format: \(oui)", category: .fingerprinting)
            return nil
        }

        do {
            let entry = try await db.read { [decoder] dbConnection -> BundledFingerprintEntry? in
                guard let record = try BundledOUIRecord
                    .filter(Column("oui") == normalizedOUI)
                    .fetchOne(dbConnection) else {
                    return nil
                }

                return try self.convertToEntry(record: record, decoder: decoder)
            }

            if entry != nil {
                Log.debug("Bundled database OUI hit for \(normalizedOUI)", category: .cache)
            }

            return entry
        } catch {
            Log.error("Bundled database OUI query failed: \(error.localizedDescription)", category: .fingerprinting)
            return nil
        }
    }

    public func queryByDHCPHash(_ hash: String) async -> BundledFingerprintEntry? {
        await ensureLoaded()

        guard let db = dbQueue else {
            Log.debug("Bundled database not available for DHCP query", category: .fingerprinting)
            return nil
        }

        guard !hash.isEmpty else {
            return nil
        }

        do {
            let entry = try await db.read { [decoder] dbConnection -> BundledFingerprintEntry? in
                guard let record = try BundledDHCPRecord
                    .filter(Column("dhcp_hash") == hash)
                    .fetchOne(dbConnection) else {
                    return nil
                }

                return try self.convertDHCPToEntry(record: record, decoder: decoder)
            }

            if entry != nil {
                Log.debug("Bundled database DHCP hit for hash \(hash.prefix(16))...", category: .cache)
            }

            return entry
        } catch {
            Log.error("Bundled database DHCP query failed: \(error.localizedDescription)", category: .fingerprinting)
            return nil
        }
    }

    // MARK: - Helper Methods

    /// Normalize OUI to uppercase hex without separators
    private func normalizeOUI(_ oui: String) -> String {
        // Remove common separators and convert to uppercase
        let cleaned = oui
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .uppercased()

        // Take first 6 characters (3 bytes = OUI)
        return String(cleaned.prefix(6))
    }

    /// Extract OUI from a full MAC address
    public func extractOUI(from mac: String) -> String {
        normalizeOUI(mac)
    }

    /// Convert OUI record to BundledFingerprintEntry
    /// This is nonisolated to allow calling from GRDB read closures
    private nonisolated func convertToEntry(record: BundledOUIRecord, decoder: JSONDecoder) throws -> BundledFingerprintEntry {
        // Parse device types JSON array
        let deviceTypes: [String]
        if let data = record.deviceTypes.data(using: .utf8) {
            deviceTypes = (try? decoder.decode([String].self, from: data)) ?? []
        } else {
            deviceTypes = []
        }

        return BundledFingerprintEntry(
            deviceName: record.deviceName,
            deviceTypes: deviceTypes,
            vendor: record.vendor,
            operatingSystem: record.operatingSystem,
            confidence: record.confidence
        )
    }

    /// Convert DHCP record to BundledFingerprintEntry
    /// This is nonisolated to allow calling from GRDB read closures
    private nonisolated func convertDHCPToEntry(record: BundledDHCPRecord, decoder: JSONDecoder) throws -> BundledFingerprintEntry {
        // Parse device types JSON array
        let deviceTypes: [String]
        if let data = record.deviceTypes.data(using: .utf8) {
            deviceTypes = (try? decoder.decode([String].self, from: data)) ?? []
        } else {
            deviceTypes = []
        }

        return BundledFingerprintEntry(
            deviceName: record.deviceName,
            deviceTypes: deviceTypes,
            vendor: record.vendor,
            operatingSystem: record.operatingSystem,
            confidence: record.confidence
        )
    }
}

// MARK: - DeviceFingerprint Conversion Extension

extension BundledFingerprintEntry {
    /// Convert to a DeviceFingerprint for integration with existing fingerprinting flow
    public func toDeviceFingerprint() -> DeviceFingerprint {
        DeviceFingerprint(
            manufacturer: vendor,
            fingerbankDeviceName: deviceName,
            operatingSystem: operatingSystem,
            source: .fingerbank,  // Treat bundled as fingerbank source
            timestamp: Date(),
            cacheHit: true  // Bundled lookups are effectively cache hits
        )
    }
}
