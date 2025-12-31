import Foundation
import Security

/// Protocol for secure credential and sensitive data storage
///
/// Implementations must be thread-safe and handle concurrent access appropriately.
public protocol SecureStorage: Sendable {
    /// Store a string value securely
    /// - Parameters:
    ///   - key: Unique identifier for the value
    ///   - value: The string to store
    /// - Throws: `SecureStorageError` if storage fails
    func store(key: String, value: String) throws
    
    /// Retrieve a previously stored string value
    /// - Parameter key: The identifier used when storing
    /// - Returns: The stored value, or `nil` if not found
    /// - Throws: `SecureStorageError` if retrieval fails (except for not found)
    func retrieve(key: String) throws -> String?
    
    /// Delete a stored value
    /// - Parameter key: The identifier of the value to delete
    /// - Throws: `SecureStorageError` if deletion fails
    func delete(key: String) throws
}

// MARK: - Errors

/// Errors that can occur during secure storage operations
public enum SecureStorageError: Error, Sendable {
    /// Failed to encode data for storage
    case encodingFailed
    /// Failed to decode retrieved data
    case decodingFailed
    /// Keychain operation failed with the given status
    case keychainError(status: OSStatus)
    /// Generic operation failure
    case operationFailed(String)
    
    /// Human-readable description of the error
    public var localizedDescription: String {
        switch self {
        case .encodingFailed:
            return "Failed to encode data for secure storage"
        case .decodingFailed:
            return "Failed to decode data from secure storage"
        case .keychainError(let status):
            return "Keychain error: \(SecureStorageError.keychainErrorMessage(for: status))"
        case .operationFailed(let message):
            return message
        }
    }
    
    /// Get a human-readable message for a keychain status code
    private static func keychainErrorMessage(for status: OSStatus) -> String {
        switch status {
        case errSecDuplicateItem:
            return "Item already exists"
        case errSecItemNotFound:
            return "Item not found"
        case errSecAuthFailed:
            return "Authentication failed"
        case errSecUserCanceled:
            return "User canceled"
        case errSecNotAvailable:
            return "Keychain not available"
        case errSecInteractionNotAllowed:
            return "User interaction not allowed"
        default:
            return "Unknown error (\(status))"
        }
    }
}

// MARK: - Keychain Implementation

/// Keychain-backed secure storage implementation
///
/// Uses macOS Keychain Services to store sensitive data securely.
/// Thread-safe through use of internal locking mechanism.
public final class KeychainStorage: SecureStorage, @unchecked Sendable {
    
    /// Shared singleton instance
    public static let shared = KeychainStorage()
    
    /// Service identifier for keychain items
    private let service: String
    
    /// Access group for shared keychain access (optional)
    private let accessGroup: String?
    
    /// Lock for thread-safe operations
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    /// Create a KeychainStorage with custom service identifier
    /// - Parameters:
    ///   - service: Service identifier for keychain items (default: app bundle identifier)
    ///   - accessGroup: Optional access group for shared keychain access
    public init(service: String = "com.lanlens.app", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }
    
    // MARK: - SecureStorage Implementation
    
    /// Store a string value in the keychain
    public func store(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw SecureStorageError.encodingFailed
        }
        
        lock.lock()
        defer { lock.unlock() }
        
        // Build the query for finding existing item
        var query = baseQuery(for: key)
        
        // First, try to delete any existing item
        SecItemDelete(query as CFDictionary)
        
        // Add the data to store
        query[kSecValueData as String] = data
        
        // Set accessibility - available when device is unlocked
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw SecureStorageError.keychainError(status: status)
        }
    }
    
    /// Retrieve a string value from the keychain
    public func retrieve(key: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let string = String(data: data, encoding: .utf8) else {
                throw SecureStorageError.decodingFailed
            }
            return string
            
        case errSecItemNotFound:
            return nil
            
        default:
            throw SecureStorageError.keychainError(status: status)
        }
    }
    
    /// Delete a value from the keychain
    public func delete(key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let query = baseQuery(for: key)
        let status = SecItemDelete(query as CFDictionary)
        
        // Success or item not found are both acceptable
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStorageError.keychainError(status: status)
        }
    }
    
    // MARK: - Extended Operations
    
    /// Check if a key exists in the keychain
    /// - Parameter key: The key to check
    /// - Returns: `true` if the key exists
    public func exists(key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let query = baseQuery(for: key)
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Store data (not just strings) in the keychain
    /// - Parameters:
    ///   - key: Unique identifier
    ///   - data: The data to store
    public func storeData(key: String, data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        
        var query = baseQuery(for: key)
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw SecureStorageError.keychainError(status: status)
        }
    }
    
    /// Retrieve data from the keychain
    /// - Parameter key: The key to retrieve
    /// - Returns: The stored data, or `nil` if not found
    public func retrieveData(key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw SecureStorageError.decodingFailed
            }
            return data
            
        case errSecItemNotFound:
            return nil
            
        default:
            throw SecureStorageError.keychainError(status: status)
        }
    }
    
    /// Delete all items for this service
    public func deleteAll() throws {
        lock.lock()
        defer { lock.unlock() }
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStorageError.keychainError(status: status)
        }
    }
    
    // MARK: - Private Helpers
    
    /// Build the base query dictionary for a given key
    private func baseQuery(for key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        return query
    }
}

// MARK: - In-Memory Implementation (for testing)

/// In-memory secure storage for testing purposes
///
/// This implementation stores values in memory and should NOT be used in production.
/// It's marked as `@unchecked Sendable` because access is synchronized with a lock.
public final class InMemorySecureStorage: SecureStorage, @unchecked Sendable {
    
    private var storage: [String: String] = [:]
    private let lock = NSLock()
    
    public init() {}
    
    public func store(key: String, value: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = value
    }
    
    public func retrieve(key: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }
    
    public func delete(key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }
    
    /// Clear all stored values
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }
}
