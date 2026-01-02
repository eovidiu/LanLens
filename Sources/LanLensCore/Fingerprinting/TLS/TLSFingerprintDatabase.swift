import Foundation

// MARK: - TLS Fingerprint Database

/// Actor for loading and querying the bundled TLS fingerprint database.
///
/// This database contains known JA3S fingerprints mapped to device/server information.
/// The database is loaded from a JSON file bundled with the application and cached in memory
/// for fast lookups.
///
/// Usage:
/// ```swift
/// let db = TLSFingerprintDatabase.shared
/// if let entry = await db.lookup(ja3sHash: "ae4edc6faf64d08308082ad26be60767") {
///     print("Server: \(entry.description)")
/// }
/// ```
public actor TLSFingerprintDatabase {

    // MARK: - Singleton

    /// Shared instance for global access
    public static let shared = TLSFingerprintDatabase()

    // MARK: - Types

    /// A fingerprint entry from the database
    public struct Entry: Codable, Sendable, Equatable {
        /// Human-readable description (e.g., "nginx/1.x", "Apache/2.4")
        public var description: String

        /// Vendor/organization (e.g., "NGINX Inc.", "Apache Software Foundation")
        public var vendor: String?

        /// Device types this fingerprint is associated with (e.g., ["server", "router"])
        public var deviceTypes: [String]

        /// Confidence score for this match (0.0 to 1.0)
        public var confidence: Double

        /// Application/server name (e.g., "nginx", "OpenSSL", "Go")
        public var applicationName: String?

        /// TLS library or stack used (e.g., "OpenSSL", "BoringSSL", "Go crypto/tls")
        public var tlsLibrary: String?

        public init(
            description: String,
            vendor: String? = nil,
            deviceTypes: [String] = [],
            confidence: Double = 0.8,
            applicationName: String? = nil,
            tlsLibrary: String? = nil
        ) {
            self.description = description
            self.vendor = vendor
            self.deviceTypes = deviceTypes
            self.confidence = min(1.0, max(0.0, confidence))
            self.applicationName = applicationName
            self.tlsLibrary = tlsLibrary
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

    /// Metadata about the loaded database
    public struct Metadata: Sendable {
        /// Database version string
        public var version: String

        /// Total number of fingerprint entries
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

    // MARK: - Internal Storage Structures

    /// JSON structure for the fingerprint database file
    private struct DatabaseFile: Codable {
        var version: String
        var fingerprints: [String: FingerprintJSON]

        struct FingerprintJSON: Codable {
            var description: String
            var vendor: String?
            var device_types: [String]
            var confidence: Double
            var application_name: String?
            var tls_library: String?

            func toEntry() -> Entry {
                Entry(
                    description: description,
                    vendor: vendor,
                    deviceTypes: device_types,
                    confidence: confidence,
                    applicationName: application_name,
                    tlsLibrary: tls_library
                )
            }
        }
    }

    // MARK: - Properties

    /// Database file name in the bundle
    private static let databaseFileName = "tls_fingerprints"
    private static let databaseFileExtension = "json"

    /// In-memory cache of fingerprints by JA3S hash
    private var fingerprintsByHash: [String: Entry] = [:]

    /// Current metadata
    private var _metadata: Metadata = Metadata()

    /// JSON decoder for parsing
    private let decoder = JSONDecoder()

    // MARK: - Initialization

    private init() {
        // Database loading is deferred to first access
    }

    // MARK: - Public Interface

    /// Get the current database metadata
    public var metadata: Metadata {
        get async {
            await ensureLoaded()
            return _metadata
        }
    }

    /// Check if the database is available and loaded
    public var isAvailable: Bool {
        get async {
            await ensureLoaded()
            return _metadata.isLoaded
        }
    }

    /// Load the database from the bundled JSON file.
    ///
    /// This method is called automatically on first access, but can be called
    /// explicitly to preload the database during app initialization.
    ///
    /// - Throws: Error if the database file cannot be read or parsed
    public func loadDatabase() async throws {
        guard let url = Bundle.main.url(
            forResource: Self.databaseFileName,
            withExtension: Self.databaseFileExtension
        ) else {
            _metadata.loadError = "Database file not found in bundle"
            _metadata.isLoaded = false
            Log.info("TLS fingerprint database not found in bundle - offline lookup disabled", category: .tls)
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let database = try decoder.decode(DatabaseFile.self, from: data)

            // Populate cache
            fingerprintsByHash.removeAll()

            for (ja3sHash, fingerprintJSON) in database.fingerprints {
                let entry = fingerprintJSON.toEntry()
                // Normalize hash to lowercase for consistent lookups
                fingerprintsByHash[ja3sHash.lowercased()] = entry
            }

            // Update metadata
            _metadata = Metadata(
                version: database.version,
                entryCount: fingerprintsByHash.count,
                isLoaded: true,
                loadError: nil,
                lastLoadedAt: Date()
            )

            Log.info("TLS fingerprint database loaded: version=\(_metadata.version), entries=\(_metadata.entryCount)", category: .tls)

        } catch {
            _metadata.loadError = error.localizedDescription
            _metadata.isLoaded = false
            Log.error("Failed to load TLS fingerprint database: \(error.localizedDescription)", category: .tls)
            throw error
        }
    }

    /// Look up a fingerprint by its JA3S hash.
    ///
    /// - Parameter ja3sHash: The JA3S hash (32 hex characters)
    /// - Returns: Matching entry if found, nil otherwise
    public func lookup(ja3sHash: String) async -> Entry? {
        await ensureLoaded()
        guard _metadata.isLoaded else { return nil }

        // Normalize hash to lowercase
        let normalizedHash = ja3sHash.lowercased()

        if let entry = fingerprintsByHash[normalizedHash] {
            Log.debug("TLS fingerprint hit for hash \(normalizedHash.prefix(16))...", category: .cache)
            return entry
        }
        return nil
    }

    /// Look up a fingerprint by JA3SFingerprint object.
    ///
    /// - Parameter fingerprint: The JA3S fingerprint
    /// - Returns: Matching entry if found, nil otherwise
    public func lookup(fingerprint: JA3SFingerprint) async -> Entry? {
        await lookup(ja3sHash: fingerprint.hash)
    }

    /// Get all fingerprints for a specific vendor.
    ///
    /// - Parameter vendor: Vendor name to search for (case-insensitive partial match)
    /// - Returns: Array of matching entries with their hashes
    public func fingerprints(forVendor vendor: String) async -> [(hash: String, entry: Entry)] {
        await ensureLoaded()
        guard _metadata.isLoaded else { return [] }

        let searchTerm = vendor.lowercased()
        return fingerprintsByHash.compactMap { hash, entry in
            if entry.vendor?.lowercased().contains(searchTerm) == true {
                return (hash, entry)
            }
            return nil
        }
    }

    /// Get all fingerprints for a specific application.
    ///
    /// - Parameter applicationName: Application name to search for (case-insensitive partial match)
    /// - Returns: Array of matching entries with their hashes
    public func fingerprints(forApplication applicationName: String) async -> [(hash: String, entry: Entry)] {
        await ensureLoaded()
        guard _metadata.isLoaded else { return [] }

        let searchTerm = applicationName.lowercased()
        return fingerprintsByHash.compactMap { hash, entry in
            if entry.applicationName?.lowercased().contains(searchTerm) == true {
                return (hash, entry)
            }
            return nil
        }
    }

    /// Get all fingerprints that use a specific TLS library.
    ///
    /// - Parameter tlsLibrary: TLS library name to search for (case-insensitive partial match)
    /// - Returns: Array of matching entries with their hashes
    public func fingerprints(forTLSLibrary tlsLibrary: String) async -> [(hash: String, entry: Entry)] {
        await ensureLoaded()
        guard _metadata.isLoaded else { return [] }

        let searchTerm = tlsLibrary.lowercased()
        return fingerprintsByHash.compactMap { hash, entry in
            if entry.tlsLibrary?.lowercased().contains(searchTerm) == true {
                return (hash, entry)
            }
            return nil
        }
    }

    // MARK: - Private Helpers

    /// Ensure the database is loaded before operations
    private func ensureLoaded() async {
        guard !_metadata.isLoaded && _metadata.loadError == nil else { return }

        do {
            try await loadDatabase()
        } catch {
            // Error already logged and stored in metadata
        }
    }
}

// MARK: - DeviceFingerprint Conversion

extension TLSFingerprintDatabase.Entry {

    /// Convert to a DeviceFingerprint for integration with existing fingerprinting flow.
    ///
    /// - Returns: A DeviceFingerprint populated with TLS-derived data
    public func toDeviceFingerprint() -> DeviceFingerprint {
        DeviceFingerprint(
            manufacturer: vendor,
            fingerbankDeviceName: description,
            operatingSystem: nil,
            source: .tlsFingerprint,
            timestamp: Date(),
            cacheHit: true
        )
    }
}
