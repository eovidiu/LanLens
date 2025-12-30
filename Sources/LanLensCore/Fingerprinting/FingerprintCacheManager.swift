import Foundation
import CryptoKit

/// Manages disk caching for device fingerprints
public actor FingerprintCacheManager {
    public static let shared = FingerprintCacheManager()

    private let fileManager = FileManager.default
    private var metadata: CacheMetadata

    // TTL values in seconds
    public static let upnpTTL: TimeInterval = 86400      // 24 hours
    public static let fingerbankTTL: TimeInterval = 604800  // 7 days

    private var cacheBaseURL: URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("LanLens")
            .appendingPathComponent("FingerprintCache")
    }

    private var upnpCacheURL: URL? {
        cacheBaseURL?.appendingPathComponent("upnp")
    }

    private var fingerbankCacheURL: URL? {
        cacheBaseURL?.appendingPathComponent("fingerbank")
    }

    private var metadataURL: URL? {
        cacheBaseURL?.appendingPathComponent("metadata.json")
    }

    private init() {
        self.metadata = CacheMetadata()
        Task {
            await setupCacheDirectories()
            await loadMetadata()
        }
    }

    // MARK: - Setup

    private func setupCacheDirectories() {
        guard let base = cacheBaseURL,
              let upnp = upnpCacheURL,
              let fingerbank = fingerbankCacheURL else {
            return
        }

        do {
            try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: upnp, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: fingerbank, withIntermediateDirectories: true)
        } catch {
            // Silently fail - cache is optional
        }
    }

    private func loadMetadata() {
        guard let url = metadataURL,
              fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode(CacheMetadata.self, from: data) else {
            return
        }
        self.metadata = loaded
    }

    private func saveMetadata() {
        guard let url = metadataURL,
              let data = try? JSONEncoder().encode(metadata) else {
            return
        }
        try? data.write(to: url)
    }

    // MARK: - UPnP Cache

    /// Get cached UPnP fingerprint
    public func getUPnPCache(mac: String, locationURL: String) -> DeviceFingerprint? {
        let key = cacheKey(for: mac, signal: locationURL)
        guard let url = upnpCacheURL?.appendingPathComponent("\(key).json"),
              fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(UPnPCacheEntry.self, from: data) else {
            metadata.upnpStats.misses += 1
            return nil
        }

        // Check expiration
        if entry.isExpired {
            try? fileManager.removeItem(at: url)
            metadata.upnpStats.misses += 1
            return nil
        }

        metadata.upnpStats.hits += 1
        saveMetadata()

        var fingerprint = entry.fingerprint
        fingerprint.cacheHit = true
        return fingerprint
    }

    /// Store UPnP fingerprint in cache
    public func storeUPnPCache(mac: String, locationURL: String, fingerprint: DeviceFingerprint) {
        let key = cacheKey(for: mac, signal: locationURL)
        guard let url = upnpCacheURL?.appendingPathComponent("\(key).json") else {
            return
        }

        let entry = UPnPCacheEntry(
            mac: mac,
            locationURL: locationURL,
            fingerprint: fingerprint,
            ttlSeconds: Self.upnpTTL
        )

        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: url)
            metadata.upnpStats.entries += 1
            saveMetadata()
        }
    }

    // MARK: - Fingerbank Cache

    /// Get cached Fingerbank fingerprint
    public func getFingerbankCache(mac: String, dhcpFingerprint: String?, userAgents: [String]?) -> DeviceFingerprint? {
        let signalHash = fingerbankSignalHash(mac: mac, dhcp: dhcpFingerprint, agents: userAgents)
        let key = cacheKey(for: mac, signal: signalHash)

        guard let url = fingerbankCacheURL?.appendingPathComponent("\(key).json"),
              fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(FingerbankCacheEntry.self, from: data) else {
            metadata.fingerbankStats.misses += 1
            return nil
        }

        // Check expiration
        if entry.isExpired {
            try? fileManager.removeItem(at: url)
            metadata.fingerbankStats.misses += 1
            return nil
        }

        // Check if signals changed (different hash)
        if entry.signalHash != signalHash {
            try? fileManager.removeItem(at: url)
            metadata.fingerbankStats.misses += 1
            return nil
        }

        metadata.fingerbankStats.hits += 1
        saveMetadata()

        var fingerprint = entry.fingerprint
        fingerprint.cacheHit = true
        return fingerprint
    }

    /// Store Fingerbank fingerprint in cache
    public func storeFingerbankCache(mac: String, dhcpFingerprint: String?, userAgents: [String]?, fingerprint: DeviceFingerprint) {
        let signalHash = fingerbankSignalHash(mac: mac, dhcp: dhcpFingerprint, agents: userAgents)
        let key = cacheKey(for: mac, signal: signalHash)

        guard let url = fingerbankCacheURL?.appendingPathComponent("\(key).json") else {
            return
        }

        let entry = FingerbankCacheEntry(
            mac: mac,
            signalHash: signalHash,
            fingerprint: fingerprint,
            ttlSeconds: Self.fingerbankTTL
        )

        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: url)
            metadata.fingerbankStats.entries += 1
            saveMetadata()
        }
    }

    // MARK: - Cache Management

    /// Clear all cached fingerprints
    public func clearAllCache() {
        if let base = cacheBaseURL {
            try? fileManager.removeItem(at: base)
        }
        metadata = CacheMetadata()
        setupCacheDirectories()
        saveMetadata()
    }

    /// Clear cached fingerprint for a specific device
    public func clearCache(for mac: String) {
        guard let upnp = upnpCacheURL,
              let fingerbank = fingerbankCacheURL else {
            return
        }

        // Remove any files matching this MAC
        let macHash = SHA256.hash(data: mac.uppercased().data(using: .utf8)!).prefix(8)
        let prefix = macHash.compactMap { String(format: "%02x", $0) }.joined()

        for dir in [upnp, fingerbank] {
            if let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for file in files {
                    if file.lastPathComponent.hasPrefix(prefix) {
                        try? fileManager.removeItem(at: file)
                    }
                }
            }
        }
    }

    /// Get cache statistics
    public func getStats() -> CacheMetadata {
        return metadata
    }

    // MARK: - Helpers

    private func cacheKey(for mac: String, signal: String) -> String {
        let combined = "\(mac.uppercased()):\(signal)"
        let hash = SHA256.hash(data: combined.data(using: .utf8)!)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func fingerbankSignalHash(mac: String, dhcp: String?, agents: [String]?) -> String {
        var combined = mac.uppercased()
        if let dhcp = dhcp {
            combined += ":\(dhcp)"
        }
        if let agents = agents {
            combined += ":\(agents.sorted().joined(separator: ","))"
        }
        let hash = SHA256.hash(data: combined.data(using: .utf8)!)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
