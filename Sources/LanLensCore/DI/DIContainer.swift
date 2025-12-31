import Foundation

// MARK: - Dependency Container

/// Thread-safe dependency injection container for LanLens services.
///
/// The container holds references to all major services via their protocol types,
/// enabling testability through dependency injection while maintaining a convenient
/// shared instance for production use.
///
/// ## Usage
///
/// **Production (default)**:
/// ```swift
/// let scanner = await DIContainer.shared.arpScanner
/// ```
///
/// **Testing**:
/// ```swift
/// let mockScanner = MockARPScanner()
/// let container = DIContainer(arpScanner: mockScanner)
/// // inject container into system under test
/// ```
public actor DIContainer {
    
    /// Shared production container with default implementations.
    /// Lazily initializes all services using their concrete singletons.
    public static let shared = DIContainer()
    
    // MARK: - Service Storage
    
    // Discovery services
    private var _arpScanner: (any ARPScannerProtocol)?
    private var _ssdpListener: (any SSDPListenerProtocol)?
    private var _mdnsListener: (any MDNSListenerProtocol)?
    private var _portScanner: (any PortScannerProtocol)?
    
    // Fingerprinting services
    private var _fingerbankService: (any FingerbankServiceProtocol)?
    private var _fingerprintCacheManager: (any FingerprintCacheManagerProtocol)?
    private var _deviceFingerprintManager: (any DeviceFingerprintManagerProtocol)?
    
    // Persistence services
    private var _database: (any DatabaseProtocol)?
    private var _deviceRepository: (any DeviceRepositoryProtocol)?
    private var _deviceStore: (any DeviceStoreProtocol)?
    
    // MARK: - Initialization
    
    /// Initialize with default production implementations.
    /// Services are lazily loaded on first access.
    public init() {
        // All properties initialized to nil - will be lazily populated
    }
    
    /// Initialize with custom implementations for testing.
    ///
    /// Only provided dependencies are set; others remain lazy-loaded from production defaults.
    ///
    /// - Parameters:
    ///   - arpScanner: Custom ARP scanner implementation
    ///   - ssdpListener: Custom SSDP listener implementation
    ///   - mdnsListener: Custom mDNS listener implementation
    ///   - portScanner: Custom port scanner implementation
    ///   - fingerbankService: Custom Fingerbank service implementation
    ///   - fingerprintCacheManager: Custom fingerprint cache manager implementation
    ///   - deviceFingerprintManager: Custom device fingerprint manager implementation
    ///   - database: Custom database implementation
    ///   - deviceRepository: Custom device repository implementation
    ///   - deviceStore: Custom device store implementation
    public init(
        arpScanner: (any ARPScannerProtocol)? = nil,
        ssdpListener: (any SSDPListenerProtocol)? = nil,
        mdnsListener: (any MDNSListenerProtocol)? = nil,
        portScanner: (any PortScannerProtocol)? = nil,
        fingerbankService: (any FingerbankServiceProtocol)? = nil,
        fingerprintCacheManager: (any FingerprintCacheManagerProtocol)? = nil,
        deviceFingerprintManager: (any DeviceFingerprintManagerProtocol)? = nil,
        database: (any DatabaseProtocol)? = nil,
        deviceRepository: (any DeviceRepositoryProtocol)? = nil,
        deviceStore: (any DeviceStoreProtocol)? = nil
    ) {
        self._arpScanner = arpScanner
        self._ssdpListener = ssdpListener
        self._mdnsListener = mdnsListener
        self._portScanner = portScanner
        self._fingerbankService = fingerbankService
        self._fingerprintCacheManager = fingerprintCacheManager
        self._deviceFingerprintManager = deviceFingerprintManager
        self._database = database
        self._deviceRepository = deviceRepository
        self._deviceStore = deviceStore
    }
    
    // MARK: - Discovery Service Accessors
    
    /// Get the ARP scanner service.
    /// Returns the injected implementation or falls back to the production singleton.
    public var arpScanner: any ARPScannerProtocol {
        get {
            if let scanner = _arpScanner {
                return scanner
            }
            let scanner = ARPScanner.shared
            _arpScanner = scanner
            return scanner
        }
    }
    
    /// Get the SSDP listener service.
    /// Returns the injected implementation or falls back to the production singleton.
    public var ssdpListener: any SSDPListenerProtocol {
        get {
            if let listener = _ssdpListener {
                return listener
            }
            let listener = SSDPListener.shared
            _ssdpListener = listener
            return listener
        }
    }
    
    /// Get the mDNS listener service.
    /// Returns the injected implementation or falls back to the production singleton.
    public var mdnsListener: any MDNSListenerProtocol {
        get {
            if let listener = _mdnsListener {
                return listener
            }
            let listener = MDNSListener.shared
            _mdnsListener = listener
            return listener
        }
    }
    
    /// Get the port scanner service.
    /// Returns the injected implementation or falls back to the production singleton.
    public var portScanner: any PortScannerProtocol {
        get {
            if let scanner = _portScanner {
                return scanner
            }
            let scanner = PortScanner.shared
            _portScanner = scanner
            return scanner
        }
    }
    
    // MARK: - Fingerprinting Service Accessors
    
    /// Get the Fingerbank service.
    /// Returns the injected implementation or falls back to the production singleton.
    public var fingerbankService: any FingerbankServiceProtocol {
        get {
            if let service = _fingerbankService {
                return service
            }
            let service = FingerbankService.shared
            _fingerbankService = service
            return service
        }
    }
    
    /// Get the fingerprint cache manager.
    /// Returns the injected implementation or falls back to the production singleton.
    public var fingerprintCacheManager: any FingerprintCacheManagerProtocol {
        get {
            if let manager = _fingerprintCacheManager {
                return manager
            }
            let manager = FingerprintCacheManager.shared
            _fingerprintCacheManager = manager
            return manager
        }
    }
    
    /// Get the device fingerprint manager.
    /// Returns the injected implementation or falls back to the production singleton.
    public var deviceFingerprintManager: any DeviceFingerprintManagerProtocol {
        get {
            if let manager = _deviceFingerprintManager {
                return manager
            }
            let manager = DeviceFingerprintManager.shared
            _deviceFingerprintManager = manager
            return manager
        }
    }
    
    // MARK: - Persistence Service Accessors
    
    /// Get the database service.
    /// Returns the injected implementation or falls back to the production singleton.
    public var database: any DatabaseProtocol {
        get {
            if let db = _database {
                return db
            }
            let db = DatabaseManager.shared
            _database = db
            return db
        }
    }
    
    /// Get the device repository.
    /// Returns the injected implementation or creates a new one with the current database.
    public var deviceRepository: any DeviceRepositoryProtocol {
        get {
            if let repo = _deviceRepository {
                return repo
            }
            let repo = DeviceRepository(database: database)
            _deviceRepository = repo
            return repo
        }
    }
    
    /// Get the device store.
    /// Returns the injected implementation or creates a new one with the current repository.
    public var deviceStore: any DeviceStoreProtocol {
        get {
            if let store = _deviceStore {
                return store
            }
            let store = DeviceStore(repository: deviceRepository)
            _deviceStore = store
            return store
        }
    }
    
    // MARK: - Setters for Testing
    
    /// Replace the ARP scanner with a custom implementation.
    /// Primarily used for testing.
    public func setARPScanner(_ scanner: any ARPScannerProtocol) {
        _arpScanner = scanner
    }
    
    /// Replace the SSDP listener with a custom implementation.
    /// Primarily used for testing.
    public func setSSDPListener(_ listener: any SSDPListenerProtocol) {
        _ssdpListener = listener
    }
    
    /// Replace the mDNS listener with a custom implementation.
    /// Primarily used for testing.
    public func setMDNSListener(_ listener: any MDNSListenerProtocol) {
        _mdnsListener = listener
    }
    
    /// Replace the port scanner with a custom implementation.
    /// Primarily used for testing.
    public func setPortScanner(_ scanner: any PortScannerProtocol) {
        _portScanner = scanner
    }
    
    /// Replace the Fingerbank service with a custom implementation.
    /// Primarily used for testing.
    public func setFingerbankService(_ service: any FingerbankServiceProtocol) {
        _fingerbankService = service
    }
    
    /// Replace the fingerprint cache manager with a custom implementation.
    /// Primarily used for testing.
    public func setFingerprintCacheManager(_ manager: any FingerprintCacheManagerProtocol) {
        _fingerprintCacheManager = manager
    }
    
    /// Replace the device fingerprint manager with a custom implementation.
    /// Primarily used for testing.
    public func setDeviceFingerprintManager(_ manager: any DeviceFingerprintManagerProtocol) {
        _deviceFingerprintManager = manager
    }
    
    /// Replace the database with a custom implementation.
    /// Primarily used for testing.
    public func setDatabase(_ db: any DatabaseProtocol) {
        _database = db
    }
    
    /// Replace the device repository with a custom implementation.
    /// Primarily used for testing.
    public func setDeviceRepository(_ repo: any DeviceRepositoryProtocol) {
        _deviceRepository = repo
    }
    
    /// Replace the device store with a custom implementation.
    /// Primarily used for testing.
    public func setDeviceStore(_ store: any DeviceStoreProtocol) {
        _deviceStore = store
    }
    
    // MARK: - Reset
    
    /// Reset all services to their default implementations.
    /// Useful for testing teardown.
    public func reset() {
        _arpScanner = nil
        _ssdpListener = nil
        _mdnsListener = nil
        _portScanner = nil
        _fingerbankService = nil
        _fingerprintCacheManager = nil
        _deviceFingerprintManager = nil
        _database = nil
        _deviceRepository = nil
        _deviceStore = nil
    }
}

// MARK: - Convenience Extensions

public extension DIContainer {
    /// Create a container configured for testing with an in-memory database.
    /// All persistence-related services will use the in-memory database.
    static func forTesting() throws -> DIContainer {
        let database = try DatabaseManager(inMemory: true)
        let repository = DeviceRepository(database: database)
        let store = DeviceStore(repository: repository)
        
        return DIContainer(
            database: database,
            deviceRepository: repository,
            deviceStore: store
        )
    }
}
