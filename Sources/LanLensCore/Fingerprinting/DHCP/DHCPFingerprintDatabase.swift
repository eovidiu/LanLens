import Foundation

// MARK: - DHCP Fingerprint Database

/// Actor for loading and querying the bundled DHCP fingerprint database.
///
/// This database contains known DHCP Option 55 fingerprints mapped to device information.
/// The database is loaded from a JSON file bundled with the application and cached in memory
/// for fast lookups.
///
/// Usage:
/// ```swift
/// let db = DHCPFingerprintDatabase.shared
/// if let entry = await db.lookup(option55: "1,3,6,15,119,252") {
///     print("Device: \(entry.deviceName)")
/// }
/// ```
public actor DHCPFingerprintDatabase {

    // MARK: - Singleton

    /// Shared instance for global access
    public static let shared = DHCPFingerprintDatabase()

    // MARK: - Types

    /// A fingerprint entry from the database
    public struct Entry: Codable, Sendable, Equatable {
        /// Human-readable device name (e.g., "Apple iPhone", "Samsung Galaxy S23")
        public var deviceName: String

        /// Operating system name (e.g., "iOS", "Android", "Windows")
        public var operatingSystem: String?

        /// Device vendor/manufacturer (e.g., "Apple Inc.", "Samsung")
        public var vendor: String?

        /// Device type categories (e.g., ["phone"], ["computer", "laptop"])
        public var deviceTypes: [String]

        /// Confidence score for this match (0.0 to 1.0)
        public var confidence: Double

        public init(
            deviceName: String,
            operatingSystem: String? = nil,
            vendor: String? = nil,
            deviceTypes: [String] = [],
            confidence: Double = 0.8
        ) {
            self.deviceName = deviceName
            self.operatingSystem = operatingSystem
            self.vendor = vendor
            self.deviceTypes = deviceTypes
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
            var device_name: String
            var os: String?
            var vendor: String?
            var device_types: [String]
            var confidence: Double

            func toEntry() -> Entry {
                Entry(
                    deviceName: device_name,
                    operatingSystem: os,
                    vendor: vendor,
                    deviceTypes: device_types,
                    confidence: confidence
                )
            }
        }
    }

    // MARK: - Properties

    /// Database file name in the bundle
    private static let databaseFileName = "dhcp_fingerprints"
    private static let databaseFileExtension = "json"

    /// In-memory cache of fingerprints by normalized Option 55 string
    private var fingerprintsByOption55: [String: Entry] = [:]

    /// In-memory cache of fingerprints by hash
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
            Log.info("DHCP fingerprint database not found in bundle - offline lookup disabled", category: .fingerprinting)
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let database = try decoder.decode(DatabaseFile.self, from: data)

            // Populate caches
            fingerprintsByOption55.removeAll()
            fingerprintsByHash.removeAll()

            for (option55, fingerprintJSON) in database.fingerprints {
                let entry = fingerprintJSON.toEntry()
                let normalized = DHCPOption55Parser.normalize(option55)

                // Store by normalized Option 55
                fingerprintsByOption55[normalized] = entry

                // Also store by hash for efficient lookups
                let hash = DHCPOption55Parser.computeHash(normalized)
                fingerprintsByHash[hash] = entry
            }

            // Update metadata
            _metadata = Metadata(
                version: database.version,
                entryCount: fingerprintsByOption55.count,
                isLoaded: true,
                loadError: nil,
                lastLoadedAt: Date()
            )

            Log.info("DHCP fingerprint database loaded: version=\(_metadata.version), entries=\(_metadata.entryCount)", category: .fingerprinting)

        } catch {
            _metadata.loadError = error.localizedDescription
            _metadata.isLoaded = false
            Log.error("Failed to load DHCP fingerprint database: \(error.localizedDescription)", category: .fingerprinting)
            throw error
        }
    }

    /// Look up a fingerprint by its normalized Option 55 hash.
    ///
    /// - Parameter option55Hash: SHA256 hash of the normalized Option 55 string
    /// - Returns: Matching entry if found, nil otherwise
    public func lookup(option55Hash: String) async -> Entry? {
        await ensureLoaded()
        guard _metadata.isLoaded else { return nil }

        if let entry = fingerprintsByHash[option55Hash] {
            Log.debug("DHCP fingerprint hit for hash \(option55Hash.prefix(16))...", category: .cache)
            return entry
        }
        return nil
    }

    /// Look up a fingerprint by its Option 55 string.
    ///
    /// The string will be normalized and hashed internally.
    ///
    /// - Parameter option55: Option 55 string in any supported format
    /// - Returns: Matching entry if found, nil otherwise
    public func lookup(option55: String) async -> Entry? {
        await ensureLoaded()
        guard _metadata.isLoaded else { return nil }

        let normalized = DHCPOption55Parser.normalize(option55)
        guard !normalized.isEmpty else { return nil }

        // Try direct lookup first
        if let entry = fingerprintsByOption55[normalized] {
            Log.debug("DHCP fingerprint hit for \(normalized)", category: .cache)
            return entry
        }

        // Try hash lookup as fallback
        let hash = DHCPOption55Parser.computeHash(normalized)
        return fingerprintsByHash[hash]
    }

    /// Perform a fuzzy match for partial or variant fingerprints.
    ///
    /// This method attempts to find a match even when the exact fingerprint
    /// is not in the database. It uses subset matching and similarity scoring.
    ///
    /// - Parameters:
    ///   - option55: Option 55 string to match
    ///   - threshold: Minimum similarity score (0.0 to 1.0) to consider a match
    /// - Returns: Best matching entry if similarity exceeds threshold, nil otherwise
    public func fuzzyMatch(option55: String, threshold: Double = 0.7) async -> Entry? {
        await ensureLoaded()
        guard _metadata.isLoaded else { return nil }

        let normalized = DHCPOption55Parser.normalize(option55)
        guard !normalized.isEmpty else { return nil }

        // First try exact match
        if let exact = fingerprintsByOption55[normalized] {
            return exact
        }

        let targetOptions = Set(normalized.split(separator: ",").map { String($0) })
        guard !targetOptions.isEmpty else { return nil }

        var bestMatch: (entry: Entry, score: Double)?

        for (storedOption55, entry) in fingerprintsByOption55 {
            let storedOptions = Set(storedOption55.split(separator: ",").map { String($0) })

            // Calculate Jaccard similarity
            let intersection = targetOptions.intersection(storedOptions)
            let union = targetOptions.union(storedOptions)
            let similarity = Double(intersection.count) / Double(union.count)

            if similarity >= threshold {
                // Adjust score by the entry's own confidence
                let adjustedScore = similarity * entry.confidence

                if bestMatch == nil || adjustedScore > bestMatch!.score {
                    bestMatch = (entry, adjustedScore)
                }
            }
        }

        if let match = bestMatch {
            Log.debug("DHCP fingerprint fuzzy match: similarity=\(String(format: "%.2f", match.score)) for \(match.entry.deviceName)", category: .fingerprinting)
            // Return entry with adjusted confidence based on match quality
            var adjustedEntry = match.entry
            adjustedEntry.confidence = match.score
            return adjustedEntry
        }

        return nil
    }

    /// Get all fingerprints for a specific vendor.
    ///
    /// - Parameter vendor: Vendor name to search for (case-insensitive partial match)
    /// - Returns: Array of matching entries
    public func fingerprints(forVendor vendor: String) async -> [Entry] {
        await ensureLoaded()
        guard _metadata.isLoaded else { return [] }

        let searchTerm = vendor.lowercased()
        return fingerprintsByOption55.values.filter { entry in
            entry.vendor?.lowercased().contains(searchTerm) == true
        }
    }

    /// Get all fingerprints for a specific device type.
    ///
    /// - Parameter deviceType: Device type to search for
    /// - Returns: Array of matching entries
    public func fingerprints(forDeviceType deviceType: DeviceType) async -> [Entry] {
        await ensureLoaded()
        guard _metadata.isLoaded else { return [] }

        let typeString = deviceType.rawValue.lowercased()
        return fingerprintsByOption55.values.filter { entry in
            entry.deviceTypes.contains { $0.lowercased() == typeString }
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

extension DHCPFingerprintDatabase.Entry {

    /// Convert to a DeviceFingerprint for integration with existing fingerprinting flow.
    ///
    /// - Returns: A DeviceFingerprint populated with DHCP-derived data
    public func toDeviceFingerprint() -> DeviceFingerprint {
        DeviceFingerprint(
            manufacturer: vendor,
            fingerbankDeviceName: deviceName,
            operatingSystem: operatingSystem,
            source: .fingerbank, // Treat DHCP lookup as fingerbank-equivalent
            timestamp: Date(),
            cacheHit: true // Bundled lookups are effectively cache hits
        )
    }
}
