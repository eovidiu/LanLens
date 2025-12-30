import Foundation
import SwiftUI

@Observable
@MainActor
final class UserPreferences {
    // MARK: - Keys

    private enum Keys {
        static let launchAtLogin = "LanLens.launchAtLogin"
        static let showInMenuBar = "LanLens.showInMenuBar"
        static let apiEnabled = "LanLens.apiEnabled"
        static let apiPort = "LanLens.apiPort"
        static let apiHost = "LanLens.apiHost"
        static let apiAuthEnabled = "LanLens.apiAuthEnabled"
        static let apiToken = "LanLens.apiToken"
        static let autoScanEnabled = "LanLens.autoScanEnabled"
        static let autoScanInterval = "LanLens.autoScanInterval"
        static let passiveDiscoveryEnabled = "LanLens.passiveDiscoveryEnabled"
        static let portScanningEnabled = "LanLens.portScanningEnabled"
        static let notifyNewDevices = "LanLens.notifyNewDevices"
        static let notifyDeviceOffline = "LanLens.notifyDeviceOffline"
    }

    // MARK: - Defaults

    private enum Defaults {
        static let launchAtLogin = false
        static let showInMenuBar = true
        static let apiEnabled = false
        static let apiPort = 8080
        static let apiHost = "127.0.0.1"
        static let apiAuthEnabled = false
        static let apiToken = ""
        static let autoScanEnabled = true
        static let autoScanInterval = 5 // minutes
        static let passiveDiscoveryEnabled = true
        static let portScanningEnabled = true
        static let notifyNewDevices = true
        static let notifyDeviceOffline = false
    }

    // MARK: - UserDefaults Instance

    private let defaults = UserDefaults.standard

    // MARK: - Backing Storage (to avoid didSet recursion)

    private var _apiPort: Int
    private var _autoScanInterval: Int

    // MARK: - General Settings

    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    var showInMenuBar: Bool {
        didSet { defaults.set(showInMenuBar, forKey: Keys.showInMenuBar) }
    }

    // MARK: - API Server Settings

    var apiEnabled: Bool {
        didSet { defaults.set(apiEnabled, forKey: Keys.apiEnabled) }
    }

    /// Port number for the API server (1-65535).
    /// Values outside this range are clamped.
    var apiPort: Int {
        get { _apiPort }
        set {
            // Clamp value before storing to avoid didSet recursion
            _apiPort = max(1, min(65535, newValue))
            defaults.set(_apiPort, forKey: Keys.apiPort)
        }
    }

    var apiHost: String {
        didSet { defaults.set(apiHost, forKey: Keys.apiHost) }
    }

    var apiAuthEnabled: Bool {
        didSet { defaults.set(apiAuthEnabled, forKey: Keys.apiAuthEnabled) }
    }

    /// API authentication token.
    ///
    /// - Warning: This token is stored in UserDefaults, which is NOT secure storage.
    ///   UserDefaults data is stored in plaintext plist files that can be accessed
    ///   by anyone with disk access. For production use with sensitive tokens,
    ///   consider using Keychain Services instead.
    ///
    /// - Note: The user explicitly requested UserDefaults storage for simplicity.
    ///   This is acceptable for local development/testing but should be reviewed
    ///   for production deployment.
    var apiToken: String {
        didSet { defaults.set(apiToken, forKey: Keys.apiToken) }
    }

    // MARK: - Scanning Settings

    var autoScanEnabled: Bool {
        didSet { defaults.set(autoScanEnabled, forKey: Keys.autoScanEnabled) }
    }

    /// Auto-scan interval in minutes (minimum 1 minute).
    /// Values less than 1 are clamped to 1.
    var autoScanInterval: Int {
        get { _autoScanInterval }
        set {
            // Clamp value before storing to avoid didSet recursion
            _autoScanInterval = max(1, newValue)
            defaults.set(_autoScanInterval, forKey: Keys.autoScanInterval)
        }
    }

    var passiveDiscoveryEnabled: Bool {
        didSet { defaults.set(passiveDiscoveryEnabled, forKey: Keys.passiveDiscoveryEnabled) }
    }

    var portScanningEnabled: Bool {
        didSet { defaults.set(portScanningEnabled, forKey: Keys.portScanningEnabled) }
    }

    // MARK: - Notification Settings

    var notifyNewDevices: Bool {
        didSet { defaults.set(notifyNewDevices, forKey: Keys.notifyNewDevices) }
    }

    var notifyDeviceOffline: Bool {
        didSet { defaults.set(notifyDeviceOffline, forKey: Keys.notifyDeviceOffline) }
    }

    // MARK: - Computed Properties

    var autoScanIntervalSeconds: Int {
        autoScanInterval * 60
    }

    var isValidAPIConfiguration: Bool {
        guard apiPort > 0 && apiPort <= 65535 else { return false }
        guard !apiHost.isEmpty else { return false }
        if apiAuthEnabled && apiToken.isEmpty { return false }
        return true
    }

    // MARK: - Initialization

    init() {
        // Load values from UserDefaults with fallback to defaults
        // Use backing storage for validated properties
        self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? Defaults.launchAtLogin
        self.showInMenuBar = defaults.object(forKey: Keys.showInMenuBar) as? Bool ?? Defaults.showInMenuBar
        self.apiEnabled = defaults.object(forKey: Keys.apiEnabled) as? Bool ?? Defaults.apiEnabled

        // Initialize backing storage with validation
        let storedPort = defaults.object(forKey: Keys.apiPort) as? Int ?? Defaults.apiPort
        self._apiPort = max(1, min(65535, storedPort))

        self.apiHost = defaults.string(forKey: Keys.apiHost) ?? Defaults.apiHost
        self.apiAuthEnabled = defaults.object(forKey: Keys.apiAuthEnabled) as? Bool ?? Defaults.apiAuthEnabled
        self.apiToken = defaults.string(forKey: Keys.apiToken) ?? Defaults.apiToken
        self.autoScanEnabled = defaults.object(forKey: Keys.autoScanEnabled) as? Bool ?? Defaults.autoScanEnabled

        // Initialize backing storage with validation
        let storedInterval = defaults.object(forKey: Keys.autoScanInterval) as? Int ?? Defaults.autoScanInterval
        self._autoScanInterval = max(1, storedInterval)

        self.passiveDiscoveryEnabled = defaults.object(forKey: Keys.passiveDiscoveryEnabled) as? Bool ?? Defaults.passiveDiscoveryEnabled
        self.portScanningEnabled = defaults.object(forKey: Keys.portScanningEnabled) as? Bool ?? Defaults.portScanningEnabled
        self.notifyNewDevices = defaults.object(forKey: Keys.notifyNewDevices) as? Bool ?? Defaults.notifyNewDevices
        self.notifyDeviceOffline = defaults.object(forKey: Keys.notifyDeviceOffline) as? Bool ?? Defaults.notifyDeviceOffline
    }

    // MARK: - Reset

    func resetToDefaults() {
        launchAtLogin = Defaults.launchAtLogin
        showInMenuBar = Defaults.showInMenuBar
        apiEnabled = Defaults.apiEnabled
        apiPort = Defaults.apiPort
        apiHost = Defaults.apiHost
        apiAuthEnabled = Defaults.apiAuthEnabled
        apiToken = Defaults.apiToken
        autoScanEnabled = Defaults.autoScanEnabled
        autoScanInterval = Defaults.autoScanInterval
        passiveDiscoveryEnabled = Defaults.passiveDiscoveryEnabled
        portScanningEnabled = Defaults.portScanningEnabled
        notifyNewDevices = Defaults.notifyNewDevices
        notifyDeviceOffline = Defaults.notifyDeviceOffline
    }
}

// MARK: - Scan Interval Options

extension UserPreferences {
    static let scanIntervalOptions: [(label: String, minutes: Int)] = [
        ("1 minute", 1),
        ("2 minutes", 2),
        ("5 minutes", 5),
        ("10 minutes", 10),
        ("15 minutes", 15),
        ("30 minutes", 30),
        ("1 hour", 60)
    ]
}
