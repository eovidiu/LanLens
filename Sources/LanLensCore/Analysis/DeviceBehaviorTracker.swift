import Foundation
import CryptoKit

/// Tracks device behavior patterns over time to classify devices by their network presence.
/// Uses accumulated presence observations to determine if a device is infrastructure (always-on),
/// a workstation (daily pattern), portable (intermittent), or a mobile/guest device.
///
/// Persistence Strategy:
/// - Presence records are stored in the database (presence_records table)
/// - In-memory profile cache is maintained for performance
/// - Profiles are rebuilt from database records on demand
/// - Legacy JSON file is migrated on first load, then removed
public actor DeviceBehaviorTracker {

    // MARK: - Singleton

    public static let shared = DeviceBehaviorTracker()

    private init() {
        self.presenceRepository = PresenceRepository()
        Task {
            await migrateFromJsonIfNeeded()
            await loadProfilesFromDatabase()
        }
    }
    
    /// Initialize with a custom repository (for testing)
    public init(presenceRepository: PresenceRepositoryProtocol) {
        self.presenceRepository = presenceRepository
    }

    // MARK: - Configuration

    /// Maximum number of presence records to retain per device in memory cache
    private static let maxPresenceRecordsInMemory = 100

    /// Minimum observations required before classification is considered reliable
    private static let minObservationsForClassification = 10

    /// Maximum number of device profiles to retain in memory (LRU eviction when exceeded)
    private static let maxProfilesInMemory = 1000

    /// Number of updates between automatic database writes
    private static let persistenceInterval = 10
    
    /// Default retention period for presence records (30 days)
    private static let defaultRetentionDays = 30

    /// When enabled, MAC addresses are hashed with SHA256 before storing
    public var hashDeviceIds: Bool = false
    
    // MARK: - Presence Thresholds
    
    /// Thresholds for behavior classification based on uptime percentage
    private enum UptimeThreshold {
        /// Devices online 95%+ of the time (routers, servers, NAS)
        static let infrastructure: Double = 95.0
        
        /// Devices online 85-95% of the time (IoT devices)
        static let iot: Double = 85.0
        
        /// Devices online 50-85% of the time with patterns (workstations)
        static let workstation: Double = 50.0
        
        /// Devices online 20-50% of the time (portable devices)
        static let portable: Double = 20.0
        
        /// Devices online 5-20% of the time (mobile devices)
        static let mobile: Double = 5.0
        
        /// Below 5% considered guest devices
    }
    
    // MARK: - Storage

    /// Presence record repository for database persistence
    private let presenceRepository: PresenceRepositoryProtocol

    /// In-memory cache of device behavior profiles (keyed by normalized MAC)
    private var profileCache: [String: DeviceBehaviorProfile] = [:]

    /// Tracks last access time for each cached profile for LRU eviction
    private var lastAccessTime: [String: Date] = [:]

    /// Counter for triggering periodic persistence
    private var updatesSinceLastPersist: Int = 0
    
    /// Batch of pending presence records to write
    private var pendingRecords: [(mac: String, isOnline: Bool, ip: String?, services: [String], timestamp: Date)] = []

    /// Salt for hashing device IDs
    private var hashSalt: String = ""
    
    /// Whether initial load from database has completed
    private var isLoaded: Bool = false
    
    // MARK: - Public Methods
    
    /// Record a presence observation for a device.
    /// - Parameters:
    ///   - deviceId: Unique device identifier (typically MAC address)
    ///   - isPresent: Whether the device is currently online
    ///   - services: Optional list of available services during this observation
    ///   - ipAddress: Optional IP address at time of observation
    public func recordPresence(
        for deviceId: String,
        isPresent: Bool,
        services: [String] = [],
        ipAddress: String? = nil
    ) async {
        let storageId = normalizeDeviceId(deviceId)
        let now = Date()

        // Create new record
        let record = PresenceRecord(
            timestamp: now,
            isOnline: isPresent,
            availableServices: services,
            ipAddress: ipAddress
        )

        // Get or create profile in cache
        var profile = profileCache[storageId] ?? DeviceBehaviorProfile(
            firstObserved: now,
            lastObserved: now
        )

        // Update timestamps
        profile.lastObserved = now
        profile.observationCount += 1

        // Add record to in-memory history
        profile.presenceHistory.append(record)

        // Trim in-memory history if needed
        if profile.presenceHistory.count > Self.maxPresenceRecordsInMemory {
            let overflow = profile.presenceHistory.count - Self.maxPresenceRecordsInMemory
            profile.presenceHistory.removeFirst(overflow)
        }

        // Update consistent services if present
        if isPresent && !services.isEmpty {
            profile.consistentServices = updateConsistentServices(
                existing: profile.consistentServices,
                newServices: services,
                history: profile.presenceHistory
            )
        }

        // Store updated profile and access time in cache
        profileCache[storageId] = profile
        lastAccessTime[storageId] = now

        // Queue for database persistence
        pendingRecords.append((mac: storageId, isOnline: isPresent, ip: ipAddress, services: services, timestamp: now))

        // Enforce LRU eviction if we exceed max profiles in memory
        evictLeastRecentlyUsedIfNeeded()

        // Periodic persistence to database
        updatesSinceLastPersist += 1
        if updatesSinceLastPersist >= Self.persistenceInterval {
            await flushPendingRecords()
            updatesSinceLastPersist = 0
        }

        Log.debug("Recorded presence for \(storageId): online=\(isPresent), observations=\(profile.observationCount)", category: .behavior)
    }
    
    /// Get the current behavior profile for a device.
    /// - Parameter deviceId: Unique device identifier
    /// - Returns: The device's behavior profile, or nil if no observations exist
    public func getProfile(for deviceId: String) async -> DeviceBehaviorProfile? {
        let storageId = normalizeDeviceId(deviceId)
        
        // Check cache first
        if let cached = profileCache[storageId] {
            lastAccessTime[storageId] = Date()
            return cached
        }
        
        // Try to load from database
        do {
            let history = try await presenceRepository.fetchHistory(mac: storageId, since: nil)
            guard !history.isEmpty else { return nil }
            
            let profile = buildProfile(from: history)
            profileCache[storageId] = profile
            lastAccessTime[storageId] = Date()
            return profile
        } catch {
            Log.error("Failed to fetch profile from database for \(storageId): \(error)", category: .behavior)
            return nil
        }
    }
    
    /// Update and return the behavior classification for a device.
    /// Classification is based on accumulated presence data.
    /// - Parameter deviceId: Unique device identifier
    /// - Returns: The updated behavior classification
    @discardableResult
    public func updateClassification(for deviceId: String) async -> BehaviorClassification {
        let storageId = normalizeDeviceId(deviceId)

        guard var profile = await getProfile(for: deviceId) else {
            Log.debug("No profile found for \(storageId), returning unknown classification", category: .behavior)
            return .unknown
        }

        // Update access time
        lastAccessTime[storageId] = Date()

        // Calculate metrics
        let uptimePercent = calculateUptimePercent(from: profile.presenceHistory)
        let peakHours = calculatePeakHours(from: profile.presenceHistory)
        let hasDailyPattern = detectDailyPattern(from: profile.presenceHistory, peakHours: peakHours)

        // Update profile metrics
        profile.averageUptimePercent = uptimePercent
        profile.peakHours = peakHours
        profile.hasDailyPattern = hasDailyPattern

        // Determine classification
        let classification = classifyBehavior(
            uptimePercent: uptimePercent,
            hasDailyPattern: hasDailyPattern,
            observationCount: profile.observationCount,
            peakHours: peakHours
        )

        // Update profile flags
        profile.classification = classification
        profile.isAlwaysOn = classification == .infrastructure || classification == .server || classification == .iot
        profile.isIntermittent = classification == .portable || classification == .mobile || classification == .guest

        // Store updated profile in cache
        profileCache[storageId] = profile

        Log.info("Updated classification for \(storageId): \(classification.rawValue) (uptime: \(String(format: "%.1f", uptimePercent))%, observations: \(profile.observationCount))", category: .behavior)

        return classification
    }
    
    /// Generate inference signals from a device's behavior profile.
    /// - Parameter profile: The device behavior profile
    /// - Returns: Array of signals for the DeviceTypeInferenceEngine
    public func generateSignals(from profile: DeviceBehaviorProfile) -> [DeviceTypeInferenceEngine.Signal] {
        var signals: [DeviceTypeInferenceEngine.Signal] = []
        
        // Only generate signals if we have sufficient observations
        guard profile.observationCount >= Self.minObservationsForClassification else {
            Log.debug("Insufficient observations (\(profile.observationCount)) for signal generation", category: .behavior)
            return signals
        }
        
        // Generate signals based on behavior classification
        switch profile.classification {
        case .infrastructure:
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .behavior,
                suggestedType: .router,
                confidence: 0.40
            ))
            Log.debug("Generated router signal (0.40) for infrastructure classification", category: .behavior)
            
        case .server:
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .behavior,
                suggestedType: .nas,
                confidence: 0.35
            ))
            Log.debug("Generated NAS signal (0.35) for server classification", category: .behavior)
            
        case .iot:
            if isEveningPeak(profile.peakHours) {
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .behavior,
                    suggestedType: .smartTV,
                    confidence: 0.35
                ))
                Log.debug("Generated smartTV signal (0.35) for IoT with evening peak", category: .behavior)
            } else {
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .behavior,
                    suggestedType: .hub,
                    confidence: 0.30
                ))
                Log.debug("Generated hub signal (0.30) for IoT classification", category: .behavior)
            }
            
        case .workstation:
            if isBusinessHoursPeak(profile.peakHours) {
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .behavior,
                    suggestedType: .computer,
                    confidence: 0.35
                ))
                Log.debug("Generated computer signal (0.35) for workstation with business hours", category: .behavior)
            } else if isEveningPeak(profile.peakHours) {
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .behavior,
                    suggestedType: .smartTV,
                    confidence: 0.35
                ))
                Log.debug("Generated smartTV signal (0.35) for workstation with evening peak", category: .behavior)
            } else {
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .behavior,
                    suggestedType: .computer,
                    confidence: 0.30
                ))
                Log.debug("Generated computer signal (0.30) for workstation classification", category: .behavior)
            }
            
        case .portable:
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .behavior,
                suggestedType: .computer,
                confidence: 0.30
            ))
            Log.debug("Generated computer signal (0.30) for portable classification", category: .behavior)
            
        case .mobile:
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .behavior,
                suggestedType: .phone,
                confidence: 0.30
            ))
            Log.debug("Generated phone signal (0.30) for mobile classification", category: .behavior)
            
        case .guest:
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .behavior,
                suggestedType: .phone,
                confidence: 0.25
            ))
            Log.debug("Generated phone signal (0.25) for guest classification", category: .behavior)
            
        case .unknown:
            Log.debug("No signals generated for unknown classification", category: .behavior)
        }
        
        return signals
    }
    
    /// Generate signals directly from a device ID, updating classification first.
    /// - Parameter deviceId: Unique device identifier
    /// - Returns: Array of signals for the DeviceTypeInferenceEngine
    public func generateSignals(for deviceId: String) async -> [DeviceTypeInferenceEngine.Signal] {
        let storageId = normalizeDeviceId(deviceId)

        // Update classification first (also updates access time)
        await updateClassification(for: deviceId)

        // Get updated profile and generate signals
        guard let profile = profileCache[storageId] else {
            return []
        }

        return generateSignals(from: profile)
    }
    
    /// Clear all stored behavior profiles from memory and database.
    public func clearAllProfiles() async {
        profileCache.removeAll()
        lastAccessTime.removeAll()
        pendingRecords.removeAll()
        
        // Note: This does not delete records from database
        // Use pruneOldRecords to manage database records
        
        Log.info("Cleared all in-memory behavior profiles", category: .behavior)
    }

    /// Remove the behavior profile for a specific device.
    /// - Parameter deviceId: Unique device identifier
    public func removeProfile(for deviceId: String) async {
        let storageId = normalizeDeviceId(deviceId)
        profileCache.removeValue(forKey: storageId)
        lastAccessTime.removeValue(forKey: storageId)
        
        // Remove from database
        do {
            try await presenceRepository.deleteRecords(mac: storageId)
            Log.debug("Removed behavior profile and records for \(storageId)", category: .behavior)
        } catch {
            Log.error("Failed to delete database records for \(storageId): \(error)", category: .behavior)
        }
    }
    
    /// Get the total number of tracked devices in memory cache.
    public var trackedDeviceCount: Int {
        profileCache.count
    }
    
    /// Flush any pending presence records to the database.
    public func flushPendingRecords() async {
        guard !pendingRecords.isEmpty else { return }
        
        let recordsToWrite = pendingRecords
        pendingRecords.removeAll()
        
        do {
            try await presenceRepository.recordPresenceBatch(recordsToWrite)
            Log.debug("Flushed \(recordsToWrite.count) presence records to database", category: .behavior)
        } catch {
            Log.error("Failed to flush presence records to database: \(error)", category: .behavior)
            // Re-queue failed records
            pendingRecords.append(contentsOf: recordsToWrite)
        }
    }
    
    /// Prune old presence records from the database.
    /// - Parameter days: Number of days of history to retain (default: 30)
    /// - Returns: Number of records pruned
    @discardableResult
    public func pruneOldRecords(retentionDays: Int = 30) async -> Int {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        
        do {
            let pruned = try await presenceRepository.pruneOldRecords(olderThan: cutoffDate)
            Log.info("Pruned \(pruned) presence records older than \(retentionDays) days", category: .behavior)
            return pruned
        } catch {
            Log.error("Failed to prune old presence records: \(error)", category: .behavior)
            return 0
        }
    }
    
    /// Get presence history for a device from the database.
    /// - Parameters:
    ///   - deviceId: Device identifier
    ///   - since: Optional date to filter history (nil for all history)
    /// - Returns: Array of presence records
    public func getPresenceHistory(for deviceId: String, since: Date? = nil) async -> [PresenceRecord] {
        let storageId = normalizeDeviceId(deviceId)
        
        do {
            return try await presenceRepository.fetchHistory(mac: storageId, since: since)
        } catch {
            Log.error("Failed to fetch presence history for \(storageId): \(error)", category: .behavior)
            return []
        }
    }
    
    /// Get uptime statistics for a device from the database.
    /// - Parameters:
    ///   - deviceId: Device identifier
    ///   - since: Optional date to calculate stats from (nil for all time)
    /// - Returns: Uptime statistics
    public func getUptimeStats(for deviceId: String, since: Date? = nil) async -> UptimeStats {
        let storageId = normalizeDeviceId(deviceId)
        
        do {
            return try await presenceRepository.calculateUptimeStats(mac: storageId, since: since)
        } catch {
            Log.error("Failed to calculate uptime stats for \(storageId): \(error)", category: .behavior)
            return UptimeStats()
        }
    }
    
    /// Get all devices seen in a time range.
    /// - Parameters:
    ///   - start: Start date
    ///   - end: End date
    /// - Returns: Array of MAC addresses
    public func getDevicesSeenBetween(start: Date, end: Date) async -> [String] {
        do {
            return try await presenceRepository.fetchDevicesSeenBetween(start: start, end: end)
        } catch {
            Log.error("Failed to fetch devices seen between dates: \(error)", category: .behavior)
            return []
        }
    }
    
    // MARK: - Private Helpers
    
    /// Build a behavior profile from presence history records.
    private func buildProfile(from history: [PresenceRecord]) -> DeviceBehaviorProfile {
        guard let firstRecord = history.min(by: { $0.timestamp < $1.timestamp }),
              let lastRecord = history.max(by: { $0.timestamp < $1.timestamp }) else {
            return DeviceBehaviorProfile()
        }
        
        // Take most recent records for in-memory cache
        let recentHistory = Array(history.suffix(Self.maxPresenceRecordsInMemory))
        
        let profile = DeviceBehaviorProfile(
            classification: .unknown,
            presenceHistory: recentHistory,
            averageUptimePercent: 0,
            isAlwaysOn: false,
            isIntermittent: false,
            hasDailyPattern: false,
            peakHours: [],
            consistentServices: [],
            firstObserved: firstRecord.timestamp,
            lastObserved: lastRecord.timestamp,
            observationCount: history.count
        )
        
        return profile
    }
    
    /// Calculate the uptime percentage from presence history.
    private func calculateUptimePercent(from history: [PresenceRecord]) -> Double {
        guard !history.isEmpty else { return 0.0 }
        
        let onlineCount = history.filter { $0.isOnline }.count
        return (Double(onlineCount) / Double(history.count)) * 100.0
    }
    
    /// Calculate peak activity hours (0-23) from presence history.
    private func calculatePeakHours(from history: [PresenceRecord]) -> [Int] {
        guard !history.isEmpty else { return [] }
        
        var hourCounts: [Int: Int] = [:]
        let calendar = Calendar.current
        
        for record in history where record.isOnline {
            let hour = calendar.component(.hour, from: record.timestamp)
            hourCounts[hour, default: 0] += 1
        }
        
        guard !hourCounts.isEmpty else { return [] }
        
        let maxCount = hourCounts.values.max() ?? 0
        guard maxCount > 0 else { return [] }
        
        let threshold = maxCount / 2
        let peakHours = hourCounts
            .filter { $0.value >= threshold }
            .map { $0.key }
            .sorted()
        
        return peakHours
    }
    
    /// Detect if the device has a daily usage pattern.
    private func detectDailyPattern(from history: [PresenceRecord], peakHours: [Int]) -> Bool {
        guard peakHours.count >= 2 && peakHours.count <= 16 else {
            return false
        }
        
        var gaps = 0
        for i in 1..<peakHours.count {
            let diff = peakHours[i] - peakHours[i-1]
            if diff > 1 {
                gaps += 1
            }
        }
        
        return gaps <= 2
    }
    
    /// Classify behavior based on metrics.
    private func classifyBehavior(
        uptimePercent: Double,
        hasDailyPattern: Bool,
        observationCount: Int,
        peakHours: [Int]
    ) -> BehaviorClassification {
        guard observationCount >= Self.minObservationsForClassification else {
            return .unknown
        }
        
        if uptimePercent >= UptimeThreshold.infrastructure {
            return .infrastructure
        } else if uptimePercent >= UptimeThreshold.iot {
            return hasDailyPattern ? .server : .iot
        } else if uptimePercent >= UptimeThreshold.workstation {
            return hasDailyPattern ? .workstation : .portable
        } else if uptimePercent >= UptimeThreshold.portable {
            return hasDailyPattern ? .portable : .mobile
        } else if uptimePercent >= UptimeThreshold.mobile {
            return .mobile
        } else {
            return .guest
        }
    }
    
    /// Update the list of consistently available services.
    private func updateConsistentServices(
        existing: [String],
        newServices: [String],
        history: [PresenceRecord]
    ) -> [String] {
        var serviceCounts: [String: Int] = [:]
        let onlineRecords = history.filter { $0.isOnline }
        
        for record in onlineRecords {
            for service in record.availableServices {
                serviceCounts[service, default: 0] += 1
            }
        }
        
        let threshold = max(1, (onlineRecords.count * 80) / 100)
        let consistent = serviceCounts
            .filter { $0.value >= threshold }
            .map { $0.key }
            .sorted()
        
        return consistent
    }
    
    /// Check if peak hours are primarily during business hours (9-17).
    private func isBusinessHoursPeak(_ peakHours: [Int]) -> Bool {
        guard !peakHours.isEmpty else { return false }
        
        let businessHours = Set(9...17)
        let peakSet = Set(peakHours)
        let businessPeakCount = peakSet.intersection(businessHours).count
        
        return businessPeakCount > peakHours.count / 2
    }
    
    /// Check if peak hours are primarily during evening hours (18-23).
    private func isEveningPeak(_ peakHours: [Int]) -> Bool {
        guard !peakHours.isEmpty else { return false }

        let eveningHours = Set(18...23)
        let peakSet = Set(peakHours)
        let eveningPeakCount = peakSet.intersection(eveningHours).count

        return eveningPeakCount > peakHours.count / 2
    }

    // MARK: - Device ID Normalization and Hashing

    /// Normalize and optionally hash a device ID for storage.
    private func normalizeDeviceId(_ deviceId: String) -> String {
        let normalized = deviceId.uppercased()

        guard hashDeviceIds else {
            return normalized
        }

        if hashSalt.isEmpty {
            hashSalt = generateSalt()
        }

        let saltedId = hashSalt + normalized
        let hash = SHA256.hash(data: Data(saltedId.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Generate a random salt for hashing device IDs.
    private func generateSalt() -> String {
        let bytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - LRU Eviction

    /// Evict least recently used profiles if we exceed the maximum.
    private func evictLeastRecentlyUsedIfNeeded() {
        guard profileCache.count > Self.maxProfilesInMemory else { return }

        let countToEvict = profileCache.count - Self.maxProfilesInMemory

        let sortedByAccess = lastAccessTime.sorted { $0.value < $1.value }

        for (deviceId, _) in sortedByAccess.prefix(countToEvict) {
            profileCache.removeValue(forKey: deviceId)
            lastAccessTime.removeValue(forKey: deviceId)
            Log.debug("Evicted LRU profile from cache: \(deviceId)", category: .behavior)
        }

        Log.info("Evicted \(countToEvict) profiles from cache due to LRU limit", category: .behavior)
    }

    // MARK: - Database Loading
    
    /// Load known device profiles from the database into cache.
    private func loadProfilesFromDatabase() async {
        guard !isLoaded else { return }
        
        // Load a sampling of recent devices to warm the cache
        let recentDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        
        do {
            let recentDevices = try await presenceRepository.fetchDevicesSeenBetween(start: recentDate, end: Date())
            
            for mac in recentDevices.prefix(Self.maxProfilesInMemory) {
                let history = try await presenceRepository.fetchHistory(mac: mac, since: recentDate)
                if !history.isEmpty {
                    let profile = buildProfile(from: history)
                    profileCache[mac] = profile
                    lastAccessTime[mac] = Date()
                }
            }
            
            isLoaded = true
            Log.info("Loaded \(profileCache.count) behavior profiles from database", category: .behavior)
        } catch {
            Log.error("Failed to load profiles from database: \(error)", category: .behavior)
            isLoaded = true
        }
    }
    
    // MARK: - Legacy JSON Migration
    
    /// Migrate data from legacy JSON file to database if it exists.
    private func migrateFromJsonIfNeeded() async {
        guard let fileURL = legacyProfilesFileURL() else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        
        Log.info("Found legacy behavior_profiles.json, migrating to database...", category: .behavior)
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let persistedData = try decoder.decode(LegacyPersistedBehaviorData.self, from: data)
            
            // Migrate each profile's presence history to database
            var migratedCount = 0
            for (mac, profile) in persistedData.profiles {
                for record in profile.presenceHistory {
                    try await presenceRepository.recordPresence(
                        mac: mac,
                        isOnline: record.isOnline,
                        ip: record.ipAddress,
                        services: record.availableServices,
                        timestamp: record.timestamp
                    )
                }
                migratedCount += 1
            }
            
            // Preserve hash settings
            hashSalt = persistedData.hashSalt
            hashDeviceIds = persistedData.hashDeviceIds
            
            // Remove legacy file after successful migration
            try FileManager.default.removeItem(at: fileURL)
            
            Log.info("Migrated \(migratedCount) behavior profiles from JSON to database, removed legacy file", category: .behavior)
        } catch {
            Log.error("Failed to migrate legacy behavior profiles: \(error)", category: .behavior)
        }
    }
    
    /// Get the URL for the legacy profiles storage file.
    private func legacyProfilesFileURL() -> URL? {
        guard let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        let lanLensDir = appSupportURL.appendingPathComponent("LanLens", isDirectory: true)
        return lanLensDir.appendingPathComponent("behavior_profiles.json")
    }
}

// MARK: - Legacy Persistence Data Structure

/// Data structure for reading legacy JSON profiles (for migration only).
private struct LegacyPersistedBehaviorData: Codable {
    let profiles: [String: DeviceBehaviorProfile]
    let lastAccessTime: [String: Date]
    let hashSalt: String
    let hashDeviceIds: Bool
}
