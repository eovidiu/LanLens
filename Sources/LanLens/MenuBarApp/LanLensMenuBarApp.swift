import SwiftUI
import LanLensCore

@main
struct LanLensMenuBarApp: App {
    @State private var appState = AppState()
    @State private var preferences = UserPreferences()
    @State private var backgroundScanner: BackgroundScanner?
    @State private var hasInitialized = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
                .environment(preferences)
                .preferredColorScheme(.dark)
                .task {
                    await initializeServicesIfNeeded()
                }
        } label: {
            Label("LanLens", systemImage: menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: String {
        if appState.isScanning {
            return "magnifyingglass.circle.fill"
        } else if appState.isAPIRunning {
            return "magnifyingglass.circle"
        } else {
            return "magnifyingglass"
        }
    }

    @MainActor
    private func initializeServicesIfNeeded() async {
        guard !hasInitialized else { return }
        hasInitialized = true

        // Request notification authorization
        await NotificationService.shared.requestAuthorization()

        // Initialize known devices for notification comparison
        await NotificationService.shared.initializeKnownDevices(from: appState.devices)

        // Start background scanner if auto-scan is enabled
        if preferences.autoScanEnabled {
            let scanner = BackgroundScanner(appState: appState, preferences: preferences)
            backgroundScanner = scanner
            scanner.start()
        }

        // Start API server if enabled
        if preferences.apiEnabled && preferences.isValidAPIConfiguration {
            let token = preferences.apiAuthEnabled ? preferences.apiToken : nil
            await appState.startAPIServer(
                port: preferences.apiPort,
                host: preferences.apiHost,
                token: token
            )
        }
    }
}
