import Foundation

// MARK: - TLS Fingerprint Matcher

/// Actor for matching TLS fingerprints to device identifications.
///
/// This matcher combines database lookups with heuristic analysis to provide
/// device identification from JA3S fingerprints. It integrates with
/// the `DeviceTypeInferenceEngine` by generating weighted signals.
///
/// Usage:
/// ```swift
/// let matcher = TLSFingerprintMatcher.shared
/// let result = await matcher.match(ja3sHash: "ae4edc6faf64d08308082ad26be60767")
/// if result.matchType != .none {
///     print("Server: \(result.description ?? "Unknown")")
///     print("Confidence: \(result.confidence)")
/// }
/// ```
public actor TLSFingerprintMatcher {

    // MARK: - Singleton

    /// Shared instance for global access
    public static let shared = TLSFingerprintMatcher()

    // MARK: - Types

    /// Result of a TLS fingerprint match operation
    public struct MatchResult: Sendable, Equatable {
        /// Description of the matched server/device
        public var description: String?

        /// Vendor/organization
        public var vendor: String?

        /// Application/server name (e.g., "nginx", "Apache")
        public var applicationName: String?

        /// TLS library (e.g., "OpenSSL", "BoringSSL")
        public var tlsLibrary: String?

        /// Suggested device types based on the fingerprint
        public var suggestedTypes: [DeviceType]

        /// Confidence score for this match (0.0 to 1.0)
        public var confidence: Double

        /// Type of match performed
        public var matchType: MatchType

        /// The JA3S hash used for matching
        public var ja3sHash: String?

        public init(
            description: String? = nil,
            vendor: String? = nil,
            applicationName: String? = nil,
            tlsLibrary: String? = nil,
            suggestedTypes: [DeviceType] = [],
            confidence: Double = 0.0,
            matchType: MatchType = .none,
            ja3sHash: String? = nil
        ) {
            self.description = description
            self.vendor = vendor
            self.applicationName = applicationName
            self.tlsLibrary = tlsLibrary
            self.suggestedTypes = suggestedTypes
            self.confidence = min(1.0, max(0.0, confidence))
            self.matchType = matchType
            self.ja3sHash = ja3sHash
        }

        /// Check if this result contains useful identification data
        public var hasIdentification: Bool {
            matchType != .none && (description != nil || !suggestedTypes.isEmpty)
        }
    }

    /// Type of match performed
    public enum MatchType: String, Sendable, CaseIterable {
        /// Direct JA3S hash match in database
        case exact

        /// No match found
        case none
    }

    // MARK: - Properties

    /// Reference to the fingerprint database
    private let database: TLSFingerprintDatabase

    // MARK: - Initialization

    /// Initialize with the shared database
    public init() {
        self.database = TLSFingerprintDatabase.shared
    }

    /// Initialize with a custom database (useful for testing)
    public init(database: TLSFingerprintDatabase) {
        self.database = database
    }

    // MARK: - Public Interface

    /// Match a JA3S hash to device/server identification.
    ///
    /// - Parameter ja3sHash: The JA3S hash (32 hex characters)
    /// - Returns: Match result with identification data and confidence
    public func match(ja3sHash: String) async -> MatchResult {
        guard JA3SHashGenerator.isValidJA3SHash(ja3sHash) else {
            Log.debug("Invalid JA3S hash format: \(ja3sHash)", category: .tls)
            return MatchResult(matchType: .none, ja3sHash: ja3sHash)
        }

        // Try database lookup
        if let entry = await database.lookup(ja3sHash: ja3sHash) {
            Log.debug("TLS fingerprint exact match: \(entry.description)", category: .tls)
            return MatchResult(
                description: entry.description,
                vendor: entry.vendor,
                applicationName: entry.applicationName,
                tlsLibrary: entry.tlsLibrary,
                suggestedTypes: entry.inferredDeviceTypes,
                confidence: entry.confidence,
                matchType: .exact,
                ja3sHash: ja3sHash
            )
        }

        // No match found
        Log.debug("No TLS fingerprint match for hash: \(ja3sHash.prefix(16))...", category: .tls)
        return MatchResult(matchType: .none, ja3sHash: ja3sHash)
    }

    /// Match a JA3S fingerprint to device/server identification.
    ///
    /// - Parameter fingerprint: The JA3S fingerprint
    /// - Returns: Match result with identification data and confidence
    public func match(fingerprint: JA3SFingerprint) async -> MatchResult {
        await match(ja3sHash: fingerprint.hash)
    }

    /// Match a TLS probe result.
    ///
    /// - Parameter probeResult: Result from TLSFingerprintProber
    /// - Returns: Match result with identification data and confidence
    public func match(probeResult: TLSFingerprintProber.ProbeResult) async -> MatchResult {
        guard let fingerprint = probeResult.ja3sFingerprint else {
            return MatchResult(matchType: .none)
        }
        return await match(fingerprint: fingerprint)
    }

    /// Generate inference signals from a TLS fingerprint match result.
    ///
    /// These signals can be fed into `DeviceTypeInferenceEngine` for
    /// weighted device type determination.
    ///
    /// - Parameter result: A match result from `match(ja3sHash:)`
    /// - Returns: Array of signals for the inference engine
    public func generateSignals(from result: MatchResult) -> [DeviceTypeInferenceEngine.Signal] {
        guard result.matchType != .none else { return [] }

        var signals: [DeviceTypeInferenceEngine.Signal] = []

        // Generate signals for each suggested device type
        for deviceType in result.suggestedTypes {
            let signal = DeviceTypeInferenceEngine.Signal(
                source: .tlsFingerprint,
                suggestedType: deviceType,
                confidence: result.confidence
            )
            signals.append(signal)
        }

        // If no specific types but we have application info, infer types from application
        if signals.isEmpty, let app = result.applicationName?.lowercased() {
            let inferredTypes = inferDeviceTypesFromApplication(app)
            for deviceType in inferredTypes {
                let signal = DeviceTypeInferenceEngine.Signal(
                    source: .tlsFingerprint,
                    suggestedType: deviceType,
                    confidence: result.confidence * 0.8  // Reduced confidence for inferred types
                )
                signals.append(signal)
            }
        }

        return signals
    }

    /// Convenience method to match a fingerprint and generate signals in one call.
    ///
    /// - Parameter ja3sHash: JA3S hash
    /// - Returns: Array of inference signals
    public func matchAndGenerateSignals(ja3sHash: String) async -> [DeviceTypeInferenceEngine.Signal] {
        let result = await match(ja3sHash: ja3sHash)
        return generateSignals(from: result)
    }

    // MARK: - Private Helpers

    /// Infer device types from application/server name
    private func inferDeviceTypesFromApplication(_ app: String) -> [DeviceType] {
        let appLower = app.lowercased()

        // Web servers often run on computers/NAS
        if appLower.contains("nginx") || appLower.contains("apache") ||
           appLower.contains("iis") || appLower.contains("lighttpd") {
            return [.computer, .nas]
        }

        // Embedded web servers
        if appLower.contains("micro_httpd") || appLower.contains("thttpd") ||
           appLower.contains("boa") || appLower.contains("mini_httpd") {
            return [.router, .hub]
        }

        // NAS-specific
        if appLower.contains("synology") || appLower.contains("qnap") ||
           appLower.contains("netgear") {
            return [.nas]
        }

        // Printer servers
        if appLower.contains("cups") || appLower.contains("hp") ||
           appLower.contains("printer") || appLower.contains("jetdirect") {
            return [.printer]
        }

        // Smart home hubs
        if appLower.contains("hue") || appLower.contains("homekit") ||
           appLower.contains("smartthings") || appLower.contains("home assistant") {
            return [.hub]
        }

        // Camera/DVR
        if appLower.contains("hikvision") || appLower.contains("dahua") ||
           appLower.contains("axis") || appLower.contains("surveillance") {
            return [.camera]
        }

        // Router firmware
        if appLower.contains("dd-wrt") || appLower.contains("openwrt") ||
           appLower.contains("tomato") || appLower.contains("mikrotik") {
            return [.router]
        }

        // Generic TLS libraries suggest general servers
        if appLower.contains("openssl") || appLower.contains("boringssl") ||
           appLower.contains("gnutls") || appLower.contains("mbedtls") {
            return [.computer]
        }

        return []
    }
}

// MARK: - Batch Operations

extension TLSFingerprintMatcher {

    /// Match multiple JA3S hashes in batch.
    ///
    /// - Parameter hashes: Array of JA3S hashes to match
    /// - Returns: Dictionary mapping hashes to their match results
    public func matchBatch(_ hashes: [String]) async -> [String: MatchResult] {
        var results: [String: MatchResult] = [:]

        for hash in hashes {
            results[hash] = await match(ja3sHash: hash)
        }

        return results
    }

    /// Match multiple TLS probe results.
    ///
    /// - Parameter probeResults: Array of probe results
    /// - Returns: Array of match results (same order as input)
    public func matchBatch(probeResults: [TLSFingerprintProber.ProbeResult]) async -> [MatchResult] {
        var results: [MatchResult] = []

        for probeResult in probeResults {
            let matchResult = await match(probeResult: probeResult)
            results.append(matchResult)
        }

        return results
    }

    /// Get statistics about match quality for a batch of hashes.
    ///
    /// - Parameter hashes: Array of JA3S hashes
    /// - Returns: Statistics about match quality
    public func matchStatistics(_ hashes: [String]) async -> MatchStatistics {
        let results = await matchBatch(hashes)

        var exactMatches = 0
        var noMatches = 0
        var totalConfidence: Double = 0

        for result in results.values {
            switch result.matchType {
            case .exact:
                exactMatches += 1
                totalConfidence += result.confidence
            case .none:
                noMatches += 1
            }
        }

        let total = results.count
        return MatchStatistics(
            totalFingerprints: total,
            exactMatches: exactMatches,
            noMatches: noMatches,
            averageConfidence: exactMatches > 0 ? totalConfidence / Double(exactMatches) : 0
        )
    }

    /// Statistics about TLS fingerprint matching
    public struct MatchStatistics: Sendable {
        public var totalFingerprints: Int
        public var exactMatches: Int
        public var noMatches: Int
        public var averageConfidence: Double

        /// Percentage of fingerprints with any match
        public var matchRate: Double {
            guard totalFingerprints > 0 else { return 0 }
            return Double(exactMatches) / Double(totalFingerprints)
        }
    }
}
