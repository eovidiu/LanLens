import Foundation
import CryptoKit

/// Tracks device behavior patterns over time to classify devices by their network presence.
/// Uses accumulated presence observations to determine if a device is infrastructure (always-on),
/// a workstation (daily pattern), portable (intermittent), or a mobile/guest device.
public actor DeviceBehaviorTracker {

    // MARK: - Singleton

    public static let shared = DeviceBehaviorTracker()

    private init() {
        loadProfiles()
    }

    // MARK: - Configuration

    /// Maximum number of presence records to retain per device
    private static let maxPresenceRecords = 100

    /// Minimum observations required before classification is considered reliable
    private static let minObservationsForClassification = 10

    /// Maximum number of device profiles to retain (LRU eviction when exceeded)
    private static let maxProfiles = 1000

    /// Number of updates between automatic persistence
    private static let persistenceInterval = 10

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

    /// Device behavior profiles keyed by device identifier (typically MAC address or hashed ID)
    private var profiles: [String: DeviceBehaviorProfile] = [:]

    /// Tracks last access time for each profile for LRU eviction
    private var lastAccessTime: [String: Date] = [:]

    /// Counter for triggering periodic persistence
    private var updatesSinceLastPersist: Int = 0

    /// Salt for hashing device IDs (persisted with profiles)
    private var hashSalt: String = ""
    
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
    ) {
        let storageId = normalizeDeviceId(deviceId)
        let now = Date()

        // Create new record
        let record = PresenceRecord(
            timestamp: now,
            isOnline: isPresent,
            availableServices: services,
            ipAddress: ipAddress
        )

        // Get or create profile
        var profile = profiles[storageId] ?? DeviceBehaviorProfile(
            firstObserved: now,
            lastObserved: now
        )

        // Update timestamps
        profile.lastObserved = now
        profile.observationCount += 1

        // Add record to history
        profile.presenceHistory.append(record)

        // Trim history if needed
        if profile.presenceHistory.count > Self.maxPresenceRecords {
            let overflow = profile.presenceHistory.count - Self.maxPresenceRecords
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

        // Store updated profile and access time
        profiles[storageId] = profile
        lastAccessTime[storageId] = now

        // Enforce LRU eviction if we exceed max profiles
        evictLeastRecentlyUsedIfNeeded()

        // Periodic persistence
        updatesSinceLastPersist += 1
        if updatesSinceLastPersist >= Self.persistenceInterval {
            persistProfiles()
            updatesSinceLastPersist = 0
        }

        Log.debug("Recorded presence for \(storageId): online=\(isPresent), observations=\(profile.observationCount)", category: .behavior)
    }
    
    /// Get the current behavior profile for a device.
    /// - Parameter deviceId: Unique device identifier
    /// - Returns: The device's behavior profile, or nil if no observations exist
    public func getProfile(for deviceId: String) -> DeviceBehaviorProfile? {
        let storageId = normalizeDeviceId(deviceId)
        if profiles[storageId] != nil {
            lastAccessTime[storageId] = Date()
        }
        return profiles[storageId]
    }
    
    /// Update and return the behavior classification for a device.
    /// Classification is based on accumulated presence data.
    /// - Parameter deviceId: Unique device identifier
    /// - Returns: The updated behavior classification
    @discardableResult
    public func updateClassification(for deviceId: String) -> BehaviorClassification {
        let storageId = normalizeDeviceId(deviceId)

        guard var profile = profiles[storageId] else {
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

        // Store updated profile
        profiles[storageId] = profile

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
            // Infrastructure devices are likely routers, access points, or hubs
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .behavior,
                suggestedType: .router,
                confidence: 0.40
            ))
            Log.debug("Generated router signal (0.40) for infrastructure classification", category: .behavior)
            
        case .server:
            // Server devices are likely NAS or computers running server software
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .behavior,
                suggestedType: .nas,
                confidence: 0.35
            ))
            Log.debug("Generated NAS signal (0.35) for server classification", category: .behavior)
            
        case .iot:
            // IoT devices could be various smart home devices
            // Check peak hours to refine the guess
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
            // Workstations with daily patterns are likely computers
            if isBusinessHoursPeak(profile.peakHours) {
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .behavior,
                    suggestedType: .computer,
                    confidence: 0.35
                ))
                Log.debug("Generated computer signal (0.35) for workstation with business hours", category: .behavior)
            } else if isEveningPeak(profile.peakHours) {
                // Evening usage could be entertainment device
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
            // Portable devices are laptops or tablets
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .behavior,
                suggestedType: .computer,
                confidence: 0.30
            ))
            Log.debug("Generated computer signal (0.30) for portable classification", category: .behavior)
            
        case .mobile:
            // Mobile devices are phones or tablets
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .behavior,
                suggestedType: .phone,
                confidence: 0.30
            ))
            Log.debug("Generated phone signal (0.30) for mobile classification", category: .behavior)
            
        case .guest:
            // Guest devices could be phones or laptops
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .behavior,
                suggestedType: .phone,
                confidence: 0.25
            ))
            Log.debug("Generated phone signal (0.25) for guest classification", category: .behavior)
            
        case .unknown:
            // No signals for unknown classification
            Log.debug("No signals generated for unknown classification", category: .behavior)
        }
        
        return signals
    }
    
    /// Generate signals directly from a device ID, updating classification first.
    /// - Parameter deviceId: Unique device identifier
    /// - Returns: Array of signals for the DeviceTypeInferenceEngine
    public func generateSignals(for deviceId: String) -> [DeviceTypeInferenceEngine.Signal] {
        let storageId = normalizeDeviceId(deviceId)

        // Update classification first (also updates access time)
        updateClassification(for: deviceId)

        // Get updated profile and generate signals
        guard let profile = profiles[storageId] else {
            return []
        }

        return generateSignals(from: profile)
    }
    
    /// Clear all stored behavior profiles.
    /// Useful for testing or resetting the tracker.
    public func clearAllProfiles() {
        profiles.removeAll()
        lastAccessTime.removeAll()
        persistProfiles()
        Log.info("Cleared all behavior profiles", category: .behavior)
    }

    /// Remove the behavior profile for a specific device.
    /// - Parameter deviceId: Unique device identifier
    public func removeProfile(for deviceId: String) {
        let storageId = normalizeDeviceId(deviceId)
        profiles.removeValue(forKey: storageId)
        lastAccessTime.removeValue(forKey: storageId)
        Log.debug("Removed behavior profile for \(storageId)", category: .behavior)
    }
    
    /// Get the total number of tracked devices.
    public var trackedDeviceCount: Int {
        profiles.count
    }
    
    // MARK: - Private Helpers
    
    /// Calculate the uptime percentage from presence history.
    private func calculateUptimePercent(from history: [PresenceRecord]) -> Double {
        guard !history.isEmpty else { return 0.0 }
        
        let onlineCount = history.filter { $0.isOnline }.count
        return (Double(onlineCount) / Double(history.count)) * 100.0
    }
    
    /// Calculate peak activity hours (0-23) from presence history.
    private func calculatePeakHours(from history: [PresenceRecord]) -> [Int] {
        guard !history.isEmpty else { return [] }
        
        // Count online occurrences per hour
        var hourCounts: [Int: Int] = [:]
        let calendar = Calendar.current
        
        for record in history where record.isOnline {
            let hour = calendar.component(.hour, from: record.timestamp)
            hourCounts[hour, default: 0] += 1
        }
        
        guard !hourCounts.isEmpty else { return [] }
        
        // Find the maximum count
        let maxCount = hourCounts.values.max() ?? 0
        guard maxCount > 0 else { return [] }
        
        // Include hours that have at least 50% of max activity
        let threshold = maxCount / 2
        let peakHours = hourCounts
            .filter { $0.value >= threshold }
            .map { $0.key }
            .sorted()
        
        return peakHours
    }
    
    /// Detect if the device has a daily usage pattern.
    private func detectDailyPattern(from history: [PresenceRecord], peakHours: [Int]) -> Bool {
        // Need at least some peak hours to have a pattern
        guard peakHours.count >= 2 && peakHours.count <= 16 else {
            return false
        }
        
        // Check if peak hours form a contiguous block (or two blocks)
        // This indicates a daily pattern vs random access
        var gaps = 0
        for i in 1..<peakHours.count {
            let diff = peakHours[i] - peakHours[i-1]
            if diff > 1 {
                gaps += 1
            }
        }
        
        // Allow up to 2 gaps (e.g., morning + evening usage)
        return gaps <= 2
    }
    
    /// Classify behavior based on metrics.
    private func classifyBehavior(
        uptimePercent: Double,
        hasDailyPattern: Bool,
        observationCount: Int,
        peakHours: [Int]
    ) -> BehaviorClassification {
        // Need minimum observations for reliable classification
        guard observationCount >= Self.minObservationsForClassification else {
            return .unknown
        }
        
        // Classify by uptime thresholds
        if uptimePercent >= UptimeThreshold.infrastructure {
            // Very high uptime - infrastructure or server
            // Differentiate based on services (if available) or default to infrastructure
            return .infrastructure
        } else if uptimePercent >= UptimeThreshold.iot {
            // High uptime but not quite infrastructure
            return hasDailyPattern ? .server : .iot
        } else if uptimePercent >= UptimeThreshold.workstation {
            // Medium uptime with potential patterns
            return hasDailyPattern ? .workstation : .portable
        } else if uptimePercent >= UptimeThreshold.portable {
            // Lower uptime
            return hasDailyPattern ? .portable : .mobile
        } else if uptimePercent >= UptimeThreshold.mobile {
            // Very low uptime
            return .mobile
        } else {
            // Barely seen
            return .guest
        }
    }
    
    /// Update the list of consistently available services.
    private func updateConsistentServices(
        existing: [String],
        newServices: [String],
        history: [PresenceRecord]
    ) -> [String] {
        // Count service occurrences across online records
        var serviceCounts: [String: Int] = [:]
        let onlineRecords = history.filter { $0.isOnline }
        
        for record in onlineRecords {
            for service in record.availableServices {
                serviceCounts[service, default: 0] += 1
            }
        }
        
        // Include services present in at least 80% of online observations
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
        
        // More than half of peak hours are business hours
        return businessPeakCount > peakHours.count / 2
    }
    
    /// Check if peak hours are primarily during evening hours (18-23).
    private func isEveningPeak(_ peakHours: [Int]) -> Bool {
        guard !peakHours.isEmpty else { return false }

        let eveningHours = Set(18...23)
        let peakSet = Set(peakHours)
        let eveningPeakCount = peakSet.intersection(eveningHours).count

        // More than half of peak hours are evening hours
        return eveningPeakCount > peakHours.count / 2
    }

    // MARK: - Device ID Normalization and Hashing

    /// Normalize and optionally hash a device ID for storage.
    /// - Parameter deviceId: Raw device identifier (typically MAC address)
    /// - Returns: Normalized (uppercased) or hashed identifier for storage
    private func normalizeDeviceId(_ deviceId: String) -> String {
        let normalized = deviceId.uppercased()

        guard hashDeviceIds else {
            return normalized
        }

        // Hash with salt for privacy
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
        guard profiles.count > Self.maxProfiles else { return }

        let countToEvict = profiles.count - Self.maxProfiles

        // Sort by last access time (oldest first)
        let sortedByAccess = lastAccessTime.sorted { $0.value < $1.value }

        // Evict the oldest entries
        for (deviceId, _) in sortedByAccess.prefix(countToEvict) {
            profiles.removeValue(forKey: deviceId)
            lastAccessTime.removeValue(forKey: deviceId)
            Log.debug("Evicted LRU profile: \(deviceId)", category: .behavior)
        }

        Log.info("Evicted \(countToEvict) profiles due to LRU limit", category: .behavior)
    }

    // MARK: - Persistence

    /// Get the URL for the profiles storage file.
    private func profilesFileURL() -> URL? {
        guard let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            Log.error("Could not find Application Support directory", category: .behavior)
            return nil
        }

        let lanLensDir = appSupportURL.appendingPathComponent("LanLens", isDirectory: true)

        // Create directory if needed
        do {
            try FileManager.default.createDirectory(
                at: lanLensDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            Log.error("Failed to create LanLens directory: \(error.localizedDescription)", category: .behavior)
            return nil
        }

        return lanLensDir.appendingPathComponent("behavior_profiles.json")
    }

    /// Persist profiles to disk.
    public func persistProfiles() {
        guard let fileURL = profilesFileURL() else {
            Log.warning("Cannot persist profiles: no valid file URL", category: .behavior)
            return
        }

        let persistedData = PersistedBehaviorData(
            profiles: profiles,
            lastAccessTime: lastAccessTime,
            hashSalt: hashSalt,
            hashDeviceIds: hashDeviceIds
        )

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(persistedData)
            try data.write(to: fileURL, options: .atomic)
            Log.debug("Persisted \(profiles.count) behavior profiles to disk", category: .behavior)
        } catch {
            Log.error("Failed to persist profiles: \(error.localizedDescription)", category: .behavior)
        }
    }

    /// Load profiles from disk.
    private func loadProfiles() {
        guard let fileURL = profilesFileURL() else {
            Log.debug("Cannot load profiles: no valid file URL", category: .behavior)
            initializeSaltIfNeeded()
            return
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            Log.debug("No persisted profiles file found, starting fresh", category: .behavior)
            initializeSaltIfNeeded()
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let persistedData = try decoder.decode(PersistedBehaviorData.self, from: data)

            profiles = persistedData.profiles
            lastAccessTime = persistedData.lastAccessTime
            hashSalt = persistedData.hashSalt
            hashDeviceIds = persistedData.hashDeviceIds

            Log.info("Loaded \(profiles.count) behavior profiles from disk", category: .behavior)
        } catch {
            Log.error("Failed to load profiles: \(error.localizedDescription)", category: .behavior)
            initializeSaltIfNeeded()
        }
    }

    /// Initialize the hash salt if not already set.
    private func initializeSaltIfNeeded() {
        if hashSalt.isEmpty {
            hashSalt = generateSalt()
            Log.debug("Generated new hash salt for device ID hashing", category: .behavior)
        }
    }
}

// MARK: - Persistence Data Structure

/// Data structure for persisting behavior profiles to disk.
private struct PersistedBehaviorData: Codable {
    let profiles: [String: DeviceBehaviorProfile]
    let lastAccessTime: [String: Date]
    let hashSalt: String
    let hashDeviceIds: Bool
}
