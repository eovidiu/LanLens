import SwiftUI
import LanLensCore
import os.log

private let appLogger = Logger(subsystem: "com.lanlens.app", category: "AppLaunch")

@main
struct LanLensMenuBarApp: App {
    @State private var appState = AppState()
    @State private var preferences = UserPreferences()
    @State private var backgroundScanner: BackgroundScanner?
    @State private var hasInitialized = false

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        appLogger.info("LanLensMenuBarApp init called")
    }

    var body: some Scene {
        let _ = appLogger.info("LanLensMenuBarApp body evaluated, icon: \(menuBarIcon)")
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

// MARK: - App Delegate for Right-Click Menu

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Find the existing status item and add right-click support
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.setupRightClickMenu()
        }
    }

    private func setupRightClickMenu() {
        // Monitor for right-clicks on status bar area
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseUp) { [weak self] event in
            // Check if click is in menu bar area (top 24 points of screen)
            if let screen = NSScreen.main {
                let menuBarHeight: CGFloat = 24
                let clickY = event.locationInWindow.y
                let screenHeight = screen.frame.height

                // If clicking in menu bar area, show quit menu
                if clickY >= screenHeight - menuBarHeight {
                    self?.showQuitMenu(at: event.locationInWindow)
                    return nil // Consume the event
                }
            }
            return event
        }
    }

    private func showQuitMenu(at point: NSPoint) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit LanLens", action: #selector(quitApp), keyEquivalent: "q")
        menu.items.first?.target = self

        // Position menu near click
        if let screen = NSScreen.main {
            let menuLocation = NSPoint(x: point.x, y: screen.frame.height - 24)
            menu.popUp(positioning: nil, at: menuLocation, in: nil)
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
