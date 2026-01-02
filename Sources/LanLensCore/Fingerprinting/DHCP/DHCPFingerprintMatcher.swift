import Foundation

// MARK: - DHCP Fingerprint Matcher

/// Actor for matching DHCP fingerprints to device identifications.
///
/// This matcher combines database lookups with heuristic analysis to provide
/// device identification from DHCP Option 55 fingerprints. It integrates with
/// the `DeviceTypeInferenceEngine` by generating weighted signals.
///
/// Usage:
/// ```swift
/// let matcher = DHCPFingerprintMatcher.shared
/// let result = await matcher.match(option55: "1,3,6,15,119,252")
/// if result.matchType != .none {
///     print("Device: \(result.deviceName ?? "Unknown")")
///     print("Confidence: \(result.confidence)")
/// }
/// ```
public actor DHCPFingerprintMatcher {

    // MARK: - Singleton

    /// Shared instance for global access
    public static let shared = DHCPFingerprintMatcher()

    // MARK: - Types

    /// Result of a DHCP fingerprint match operation
    public struct MatchResult: Sendable, Equatable {
        /// Identified device name (e.g., "Apple iPhone", "Windows 10 PC")
        public var deviceName: String?

        /// Detected operating system (e.g., "iOS", "Windows", "Android")
        public var operatingSystem: String?

        /// Device vendor/manufacturer
        public var vendor: String?

        /// Suggested device types based on the fingerprint
        public var suggestedTypes: [DeviceType]

        /// Confidence score for this match (0.0 to 1.0)
        public var confidence: Double

        /// Type of match performed
        public var matchType: MatchType

        /// The normalized Option 55 string used for matching
        public var normalizedFingerprint: String?

        /// The hash of the normalized fingerprint
        public var fingerprintHash: String?

        public init(
            deviceName: String? = nil,
            operatingSystem: String? = nil,
            vendor: String? = nil,
            suggestedTypes: [DeviceType] = [],
            confidence: Double = 0.0,
            matchType: MatchType = .none,
            normalizedFingerprint: String? = nil,
            fingerprintHash: String? = nil
        ) {
            self.deviceName = deviceName
            self.operatingSystem = operatingSystem
            self.vendor = vendor
            self.suggestedTypes = suggestedTypes
            self.confidence = min(1.0, max(0.0, confidence))
            self.matchType = matchType
            self.normalizedFingerprint = normalizedFingerprint
            self.fingerprintHash = fingerprintHash
        }

        /// Check if this result contains useful identification data
        public var hasIdentification: Bool {
            matchType != .none && (deviceName != nil || !suggestedTypes.isEmpty)
        }
    }

    /// Type of match performed
    public enum MatchType: String, Sendable, CaseIterable {
        /// Direct hash/fingerprint match in database
        case exact

        /// Partial or similarity-based match
        case fuzzy

        /// Heuristic-based identification (no database match)
        case heuristic

        /// No match found
        case none
    }

    // MARK: - Properties

    /// Reference to the fingerprint database
    private let database: DHCPFingerprintDatabase

    /// Threshold for fuzzy matching (0.0 to 1.0)
    private let fuzzyMatchThreshold: Double = 0.65

    // MARK: - Initialization

    /// Initialize with the shared database
    public init() {
        self.database = DHCPFingerprintDatabase.shared
    }

    /// Initialize with a custom database (useful for testing)
    public init(database: DHCPFingerprintDatabase) {
        self.database = database
    }

    // MARK: - Public Interface

    /// Match a DHCP fingerprint string to device identification.
    ///
    /// This method attempts matching in the following order:
    /// 1. Exact database lookup
    /// 2. Fuzzy database match
    /// 3. Heuristic analysis
    ///
    /// - Parameter option55: DHCP Option 55 string in any supported format
    /// - Returns: Match result with identification data and confidence
    public func match(option55: String) async -> MatchResult {
        let normalized = DHCPOption55Parser.normalize(option55)
        guard !normalized.isEmpty else {
            return MatchResult(matchType: .none)
        }

        let hash = DHCPOption55Parser.computeHash(normalized)

        // Try exact database match
        if let entry = await database.lookup(option55: normalized) {
            Log.debug("DHCP exact match: \(entry.deviceName)", category: .fingerprinting)
            return MatchResult(
                deviceName: entry.deviceName,
                operatingSystem: entry.operatingSystem,
                vendor: entry.vendor,
                suggestedTypes: entry.inferredDeviceTypes,
                confidence: entry.confidence,
                matchType: .exact,
                normalizedFingerprint: normalized,
                fingerprintHash: hash
            )
        }

        // Try fuzzy database match
        if let entry = await database.fuzzyMatch(option55: normalized, threshold: fuzzyMatchThreshold) {
            Log.debug("DHCP fuzzy match: \(entry.deviceName) with confidence \(entry.confidence)", category: .fingerprinting)
            return MatchResult(
                deviceName: entry.deviceName,
                operatingSystem: entry.operatingSystem,
                vendor: entry.vendor,
                suggestedTypes: entry.inferredDeviceTypes,
                confidence: entry.confidence * 0.9, // Reduce confidence for fuzzy matches
                matchType: .fuzzy,
                normalizedFingerprint: normalized,
                fingerprintHash: hash
            )
        }

        // Fall back to heuristic analysis
        let heuristicResult = performHeuristicAnalysis(normalized: normalized)
        if heuristicResult.hasIdentification {
            Log.debug("DHCP heuristic match: \(heuristicResult.deviceName ?? "Unknown") with confidence \(heuristicResult.confidence)", category: .fingerprinting)
        }

        return MatchResult(
            deviceName: heuristicResult.deviceName,
            operatingSystem: heuristicResult.operatingSystem,
            vendor: heuristicResult.vendor,
            suggestedTypes: heuristicResult.suggestedTypes,
            confidence: heuristicResult.confidence,
            matchType: heuristicResult.hasIdentification ? .heuristic : .none,
            normalizedFingerprint: normalized,
            fingerprintHash: hash
        )
    }

    /// Generate inference signals from a DHCP fingerprint match result.
    ///
    /// These signals can be fed into `DeviceTypeInferenceEngine` for
    /// weighted device type determination.
    ///
    /// - Parameter result: A match result from `match(option55:)`
    /// - Returns: Array of signals for the inference engine
    public func generateSignals(from result: MatchResult) -> [DeviceTypeInferenceEngine.Signal] {
        guard result.matchType != .none else { return [] }

        var signals: [DeviceTypeInferenceEngine.Signal] = []

        // Generate signals for each suggested device type
        for deviceType in result.suggestedTypes {
            let signal = DeviceTypeInferenceEngine.Signal(
                source: .dhcpFingerprint,
                suggestedType: deviceType,
                confidence: result.confidence
            )
            signals.append(signal)
        }

        // If no specific types but we have OS information, infer types from OS
        if signals.isEmpty, let os = result.operatingSystem?.lowercased() {
            let inferredTypes = inferDeviceTypesFromOS(os)
            for deviceType in inferredTypes {
                let signal = DeviceTypeInferenceEngine.Signal(
                    source: .dhcpFingerprint,
                    suggestedType: deviceType,
                    confidence: result.confidence * 0.8 // Reduced confidence for OS-inferred types
                )
                signals.append(signal)
            }
        }

        return signals
    }

    /// Convenience method to match a fingerprint and generate signals in one call.
    ///
    /// - Parameter option55: DHCP Option 55 string
    /// - Returns: Array of inference signals
    public func matchAndGenerateSignals(option55: String) async -> [DeviceTypeInferenceEngine.Signal] {
        let result = await match(option55: option55)
        return generateSignals(from: result)
    }

    // MARK: - Private Helpers

    /// Perform heuristic analysis when database lookup fails
    private func performHeuristicAnalysis(normalized: String) -> MatchResult {
        let hint = DHCPOption55Parser.quickHint(for: normalized)
        let options = Set(normalized.split(separator: ",").compactMap { UInt8($0) })

        var deviceName: String?
        var operatingSystem: String?
        var vendor: String?
        var suggestedTypes: [DeviceType] = []
        var confidence: Double = 0.0

        switch hint {
        case .apple:
            operatingSystem = "Apple OS"
            vendor = "Apple Inc."
            // Differentiate between iOS and macOS based on option count
            if options.count <= 7 {
                deviceName = "Apple Mobile Device"
                suggestedTypes = [.phone, .tablet]
            } else {
                deviceName = "Apple Computer"
                suggestedTypes = [.computer]
            }
            confidence = 0.55

        case .windows:
            operatingSystem = "Windows"
            vendor = "Microsoft"
            deviceName = "Windows Device"
            suggestedTypes = [.computer]
            confidence = 0.50

        case .android:
            operatingSystem = "Android"
            deviceName = "Android Device"
            // Could be phone or tablet
            suggestedTypes = [.phone, .tablet]
            confidence = 0.50

        case .linux:
            operatingSystem = "Linux"
            deviceName = "Linux Device"
            // Could be computer, server, or embedded
            suggestedTypes = [.computer, .nas]
            confidence = 0.40

        case .networkEquipment:
            deviceName = "Network Equipment"
            suggestedTypes = [.router, .accessPoint]
            confidence = 0.45

        case .iot:
            deviceName = "IoT Device"
            suggestedTypes = [.hub, .appliance]
            confidence = 0.35

        case .unknown:
            // No useful heuristic match
            break
        }

        return MatchResult(
            deviceName: deviceName,
            operatingSystem: operatingSystem,
            vendor: vendor,
            suggestedTypes: suggestedTypes,
            confidence: confidence,
            matchType: confidence > 0 ? .heuristic : .none,
            normalizedFingerprint: normalized,
            fingerprintHash: DHCPOption55Parser.computeHash(normalized)
        )
    }

    /// Infer device types from operating system name
    private func inferDeviceTypesFromOS(_ os: String) -> [DeviceType] {
        let osLower = os.lowercased()

        if osLower.contains("ios") || osLower.contains("iphone") {
            return [.phone]
        } else if osLower.contains("ipados") || osLower.contains("ipad") {
            return [.tablet]
        } else if osLower.contains("macos") || osLower.contains("mac os") || osLower.contains("osx") {
            return [.computer]
        } else if osLower.contains("tvos") || osLower.contains("apple tv") {
            return [.smartTV]
        } else if osLower.contains("watchos") {
            return [.phone] // Closest match for wearables
        } else if osLower.contains("android") {
            // Android could be phone, tablet, TV, or other
            return [.phone, .tablet]
        } else if osLower.contains("windows") {
            return [.computer]
        } else if osLower.contains("linux") {
            return [.computer, .nas]
        } else if osLower.contains("freebsd") || osLower.contains("bsd") {
            return [.nas, .router]
        } else if osLower.contains("roku") {
            return [.smartTV]
        } else if osLower.contains("tizen") || osLower.contains("webos") {
            return [.smartTV]
        } else if osLower.contains("fire os") || osLower.contains("fireos") {
            return [.smartTV, .tablet]
        }

        return []
    }
}

// MARK: - Batch Operations

extension DHCPFingerprintMatcher {

    /// Match multiple fingerprints in batch.
    ///
    /// - Parameter fingerprints: Array of Option 55 strings to match
    /// - Returns: Dictionary mapping fingerprints to their match results
    public func matchBatch(_ fingerprints: [String]) async -> [String: MatchResult] {
        var results: [String: MatchResult] = [:]

        for fingerprint in fingerprints {
            results[fingerprint] = await match(option55: fingerprint)
        }

        return results
    }

    /// Get statistics about match quality for a batch of fingerprints.
    ///
    /// - Parameter fingerprints: Array of Option 55 strings
    /// - Returns: Statistics about match quality
    public func matchStatistics(_ fingerprints: [String]) async -> MatchStatistics {
        let results = await matchBatch(fingerprints)

        var exactMatches = 0
        var fuzzyMatches = 0
        var heuristicMatches = 0
        var noMatches = 0
        var totalConfidence: Double = 0

        for result in results.values {
            switch result.matchType {
            case .exact:
                exactMatches += 1
            case .fuzzy:
                fuzzyMatches += 1
            case .heuristic:
                heuristicMatches += 1
            case .none:
                noMatches += 1
            }
            totalConfidence += result.confidence
        }

        let total = results.count
        return MatchStatistics(
            totalFingerprints: total,
            exactMatches: exactMatches,
            fuzzyMatches: fuzzyMatches,
            heuristicMatches: heuristicMatches,
            noMatches: noMatches,
            averageConfidence: total > 0 ? totalConfidence / Double(total) : 0
        )
    }

    /// Statistics about DHCP fingerprint matching
    public struct MatchStatistics: Sendable {
        public var totalFingerprints: Int
        public var exactMatches: Int
        public var fuzzyMatches: Int
        public var heuristicMatches: Int
        public var noMatches: Int
        public var averageConfidence: Double

        /// Percentage of fingerprints with any match
        public var matchRate: Double {
            guard totalFingerprints > 0 else { return 0 }
            return Double(exactMatches + fuzzyMatches + heuristicMatches) / Double(totalFingerprints)
        }

        /// Percentage of fingerprints with exact database match
        public var exactMatchRate: Double {
            guard totalFingerprints > 0 else { return 0 }
            return Double(exactMatches) / Double(totalFingerprints)
        }
    }
}
