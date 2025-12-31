import Foundation

// MARK: - Device Store Protocol

/// Protocol for the combined in-memory and persistent device store
public protocol DeviceStoreProtocol: Sendable {
    /// Get all devices (from cache)
    func getDevices() async -> [Device]
    
    /// Get a specific device by MAC address
    func getDevice(mac: String) async -> Device?
    
    /// Add or update a device
    func addOrUpdate(device: Device) async throws
    
    /// Add or update multiple devices
    func addOrUpdateAll(devices: [Device]) async throws
    
    /// Remove a device by MAC address
    func remove(mac: String) async throws
    
    /// Remove all devices
    func removeAll() async throws
    
    /// Sync in-memory cache with persistent storage
    func sync() async throws
    
    /// Load devices from persistent storage into cache
    func load() async throws
    
    /// Mark all devices as offline
    func markAllOffline() async throws
}

// MARK: - Device Store

/// Actor-based device store combining in-memory cache with persistent storage
/// Provides thread-safe access to device data with automatic persistence
public actor DeviceStore: DeviceStoreProtocol {
    
    // MARK: - Properties
    
    /// In-memory cache of devices, keyed by MAC address
    private var cache: [String: Device] = [:]
    
    /// Repository for persistent storage
    private let repository: DeviceRepositoryProtocol
    
    /// Whether the cache has been loaded from disk
    private var isLoaded: Bool = false
    
    /// Pending changes that need to be synced
    private var pendingChanges: Set<String> = []
    
    /// Whether auto-sync is enabled
    private var autoSyncEnabled: Bool = true
    
    // MARK: - Initialization
    
    /// Initialize with a repository (defaults to GRDB-based repository)
    public init(repository: DeviceRepositoryProtocol? = nil) {
        self.repository = repository ?? DeviceRepository()
    }
    
    /// Initialize with an in-memory only store (for testing)
    public init(inMemory: Bool) throws {
        if inMemory {
            let db = try DatabaseManager(inMemory: true)
            self.repository = DeviceRepository(database: db)
        } else {
            self.repository = DeviceRepository()
        }
    }
    
    // MARK: - Configuration
    
    /// Enable or disable automatic syncing to persistent storage
    public func setAutoSync(enabled: Bool) {
        autoSyncEnabled = enabled
    }
    
    // MARK: - Read Operations
    
    public func getDevices() async -> [Device] {
        await ensureLoaded()
        return Array(cache.values).sorted { $0.lastSeen > $1.lastSeen }
    }
    
    public func getDevice(mac: String) async -> Device? {
        await ensureLoaded()
        return cache[mac.uppercased()]
    }
    
    /// Get count of devices
    public func getDeviceCount() async -> Int {
        await ensureLoaded()
        return cache.count
    }
    
    /// Get count of online devices
    public func getOnlineDeviceCount() async -> Int {
        await ensureLoaded()
        return cache.values.filter { $0.isOnline }.count
    }
    
    // MARK: - Write Operations
    
    public func addOrUpdate(device: Device) async throws {
        await ensureLoaded()
        
        let mac = device.mac.uppercased()
        
        // Merge with existing device if present
        if let existing = cache[mac] {
            var merged = device
            merged = mergeDevices(existing: existing, new: merged)
            cache[mac] = merged
        } else {
            cache[mac] = device
        }
        
        pendingChanges.insert(mac)
        
        if autoSyncEnabled {
            try await syncSingle(mac: mac)
        }
    }
    
    public func addOrUpdateAll(devices: [Device]) async throws {
        await ensureLoaded()
        
        for device in devices {
            let mac = device.mac.uppercased()
            
            if let existing = cache[mac] {
                var merged = device
                merged = mergeDevices(existing: existing, new: merged)
                cache[mac] = merged
            } else {
                cache[mac] = device
            }
            
            pendingChanges.insert(mac)
        }
        
        if autoSyncEnabled {
            try await sync()
        }
    }
    
    public func remove(mac: String) async throws {
        await ensureLoaded()
        
        let normalizedMac = mac.uppercased()
        cache.removeValue(forKey: normalizedMac)
        pendingChanges.remove(normalizedMac)
        
        try await repository.delete(mac: normalizedMac)
    }
    
    public func removeAll() async throws {
        cache.removeAll()
        pendingChanges.removeAll()
        try await repository.deleteAll()
    }
    
    // MARK: - Sync Operations
    
    public func sync() async throws {
        guard !pendingChanges.isEmpty else { return }
        
        let devicesToSync = pendingChanges.compactMap { cache[$0] }
        try await repository.saveAll(devices: devicesToSync)
        pendingChanges.removeAll()
    }
    
    public func load() async throws {
        let devices = try await repository.fetchAll()
        cache = Dictionary(uniqueKeysWithValues: devices.map { ($0.mac, $0) })
        isLoaded = true
        pendingChanges.removeAll()
    }
    
    public func markAllOffline() async throws {
        await ensureLoaded()
        
        for mac in cache.keys {
            cache[mac]?.isOnline = false
            pendingChanges.insert(mac)
        }
        
        // Batch update in database
        try await repository.markAllOffline()
        pendingChanges.removeAll()
    }
    
    // MARK: - Private Helpers
    
    /// Ensure the cache is loaded from persistent storage
    private func ensureLoaded() async {
        guard !isLoaded else { return }
        
        do {
            try await load()
        } catch {
            // Log error but continue with empty cache
            print("[DeviceStore] Failed to load from disk: \(error)")
            isLoaded = true
        }
    }
    
    /// Sync a single device to persistent storage
    private func syncSingle(mac: String) async throws {
        guard let device = cache[mac] else { return }
        try await repository.save(device: device)
        pendingChanges.remove(mac)
    }
    
    /// Merge two devices, preserving historical data from existing and updates from new
    private func mergeDevices(existing: Device, new: Device) -> Device {
        var merged = new
        
        // Preserve first seen date
        merged = Device(
            id: existing.id,  // Keep original UUID
            mac: existing.mac,
            ip: new.ip,
            hostname: new.hostname ?? existing.hostname,
            vendor: new.vendor ?? existing.vendor,
            firstSeen: existing.firstSeen,  // Always preserve first seen
            lastSeen: new.lastSeen,
            isOnline: new.isOnline,
            openPorts: new.openPorts.isEmpty ? existing.openPorts : new.openPorts,
            services: new.services.isEmpty ? existing.services : new.services,
            httpInfo: new.httpInfo ?? existing.httpInfo,
            smartScore: max(new.smartScore, existing.smartScore),
            smartSignals: new.smartSignals.isEmpty ? existing.smartSignals : new.smartSignals,
            deviceType: new.deviceType == .unknown ? existing.deviceType : new.deviceType,
            userLabel: new.userLabel ?? existing.userLabel,  // Preserve user customizations
            fingerprint: new.fingerprint ?? existing.fingerprint
        )
        
        return merged
    }
    
    // MARK: - Query Operations
    
    /// Get devices matching a filter
    public func getDevices(matching filter: @Sendable (Device) -> Bool) async -> [Device] {
        await ensureLoaded()
        return cache.values.filter(filter).sorted { $0.lastSeen > $1.lastSeen }
    }
    
    /// Get online devices
    public func getOnlineDevices() async -> [Device] {
        await getDevices(matching: { $0.isOnline })
    }
    
    /// Get devices by type
    public func getDevices(ofType type: DeviceType) async -> [Device] {
        await getDevices(matching: { $0.deviceType == type })
    }
    
    /// Get devices seen in the last N seconds
    public func getRecentDevices(within seconds: TimeInterval) async -> [Device] {
        let cutoff = Date().addingTimeInterval(-seconds)
        return await getDevices(matching: { $0.lastSeen >= cutoff })
    }
}

// MARK: - Convenience Extensions

public extension DeviceStore {
    /// Update a device's user label
    func updateUserLabel(mac: String, label: String?) async throws {
        guard var device = await getDevice(mac: mac) else { return }
        device.userLabel = label
        try await addOrUpdate(device: device)
    }
    
    /// Update a device's type
    func updateDeviceType(mac: String, type: DeviceType) async throws {
        guard var device = await getDevice(mac: mac) else { return }
        device.deviceType = type
        try await addOrUpdate(device: device)
    }
}
