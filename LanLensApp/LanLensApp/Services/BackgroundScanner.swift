import Foundation

/// Background scanner that performs periodic network scans with energy awareness.
///
/// Features:
/// - Configurable scan intervals
/// - Thermal state monitoring (skips scans when device is hot)
/// - Low priority QoS to minimize energy impact
/// - App Nap friendly
@MainActor
final class BackgroundScanner {
    private var scanTask: Task<Void, Never>?
    private var isRunning = false

    private weak var appState: AppState?
    private weak var preferences: UserPreferences?

    /// Minimum delay when thermal state is elevated (seconds)
    private let thermalThrottleDelay: Duration = .seconds(60)

    /// Delay when auto-scan is disabled but we're still checking
    private let disabledCheckDelay: Duration = .seconds(10)

    init(appState: AppState, preferences: UserPreferences) {
        self.appState = appState
        self.preferences = preferences
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Use utility QoS for background work - energy efficient
        scanTask = Task(priority: .utility) { [weak self] in
            await self?.runScanLoop()
        }
    }

    func stop() {
        isRunning = false
        scanTask?.cancel()
        scanTask = nil
    }

    private func runScanLoop() async {
        while isRunning && !Task.isCancelled {
            guard let preferences = preferences,
                  let appState = appState,
                  preferences.autoScanEnabled else {
                // Wait a bit before checking again if auto-scan is disabled
                try? await Task.sleep(for: disabledCheckDelay)
                continue
            }

            // Check thermal state before scanning
            if shouldThrottleDueToThermalState() {
                try? await Task.sleep(for: thermalThrottleDelay)
                continue
            }

            // Run a quick scan
            await appState.runQuickScan()

            // Start passive discovery if enabled
            if preferences.passiveDiscoveryEnabled {
                appState.startPassiveDiscovery()

                // Let it run for 10 seconds
                try? await Task.sleep(for: .seconds(10))

                appState.stopDiscovery()
            }

            // Wait for the configured interval
            let intervalSeconds = preferences.autoScanIntervalSeconds
            try? await Task.sleep(for: .seconds(intervalSeconds))
        }
    }

    /// Checks if scanning should be throttled due to thermal conditions.
    ///
    /// Returns `true` when the system is under thermal pressure (critical or serious state),
    /// indicating that background work should be deferred to reduce heat generation.
    private func shouldThrottleDueToThermalState() -> Bool {
        let thermalState = ProcessInfo.processInfo.thermalState

        switch thermalState {
        case .critical:
            // System is in critical thermal state - defer all non-essential work
            print("BackgroundScanner: Deferring scan due to critical thermal state")
            return true

        case .serious:
            // System is getting hot - reduce scan frequency
            print("BackgroundScanner: Deferring scan due to serious thermal state")
            return true

        case .fair:
            // Slightly elevated but acceptable
            return false

        case .nominal:
            // Normal operating temperature
            return false

        @unknown default:
            // Unknown state - proceed with caution
            return false
        }
    }

    deinit {
        scanTask?.cancel()
    }
}
