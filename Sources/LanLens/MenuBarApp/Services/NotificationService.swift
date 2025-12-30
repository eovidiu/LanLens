import Foundation
import UserNotifications
import LanLensCore

/// Actor-based notification service for device alerts.
///
/// Using `actor` instead of `@MainActor final class` ensures proper
/// thread-safety without blocking the main thread for notification operations.
///
/// Note: This service gracefully handles environments where notifications
/// aren't available (e.g., SPM executables without proper bundle setup).
actor NotificationService {
    static let shared = NotificationService()

    private var isAuthorized = false
    private var isAvailable = false
    private var knownDeviceMACs: Set<String> = []

    // Delegate wrapper for UNUserNotificationCenterDelegate
    private let delegateWrapper = NotificationDelegateWrapper()

    private init() {}

    func requestAuthorization() async {
        // Check if we have a valid bundle identifier (required for notifications)
        guard Bundle.main.bundleIdentifier != nil else {
            print("NotificationService: Notifications unavailable - no bundle identifier")
            isAvailable = false
            return
        }

        do {
            let center = UNUserNotificationCenter.current()

            // Set delegate on main thread as required by UNUserNotificationCenter
            await MainActor.run {
                center.delegate = delegateWrapper
            }

            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            isAvailable = true

            if granted {
                print("Notification authorization granted")
            } else {
                print("Notification authorization denied")
            }
        } catch {
            print("Notification authorization error: \(error)")
            isAvailable = false
        }
    }

    func checkAuthorizationStatus() async -> Bool {
        guard isAvailable else { return false }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
        return isAuthorized
    }

    func initializeKnownDevices(from devices: [Device]) {
        knownDeviceMACs = Set(devices.map { $0.mac })
    }

    func checkForNewDevice(_ device: Device, notifyEnabled: Bool) async {
        guard isAvailable, notifyEnabled, isAuthorized else { return }

        if !knownDeviceMACs.contains(device.mac) {
            knownDeviceMACs.insert(device.mac)
            await sendNewDeviceNotification(device)
        }
    }

    func checkDeviceWentOffline(_ device: Device, notifyEnabled: Bool) async {
        guard isAvailable, notifyEnabled, isAuthorized else { return }

        if !device.isOnline {
            await sendDeviceOfflineNotification(device)
        }
    }

    private func sendNewDeviceNotification(_ device: Device) async {
        let content = UNMutableNotificationContent()
        content.title = "New Device Detected"
        content.body = "\(deviceDisplayName(device)) joined the network"
        content.sound = .default
        content.categoryIdentifier = "NEW_DEVICE"

        let request = UNNotificationRequest(
            identifier: "new-device-\(device.mac)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to send notification: \(error)")
        }
    }

    private func sendDeviceOfflineNotification(_ device: Device) async {
        let content = UNMutableNotificationContent()
        content.title = "Device Offline"
        content.body = "\(deviceDisplayName(device)) is no longer reachable"
        content.sound = .default
        content.categoryIdentifier = "DEVICE_OFFLINE"

        let request = UNNotificationRequest(
            identifier: "offline-\(device.mac)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to send notification: \(error)")
        }
    }

    private func deviceDisplayName(_ device: Device) -> String {
        if let label = device.userLabel, !label.isEmpty {
            return label
        }
        if let hostname = device.hostname, !hostname.isEmpty {
            return hostname.replacingOccurrences(of: ".local", with: "")
        }
        if let vendor = device.vendor {
            return "\(vendor) device"
        }
        return device.ip
    }
}

// MARK: - UNUserNotificationCenterDelegate Wrapper

/// Separate class to handle UNUserNotificationCenterDelegate since actors can't
/// directly conform to @objc protocols.
private final class NotificationDelegateWrapper: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show notification even when app is in foreground
        return [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Handle notification tap - could navigate to device detail
        let identifier = response.notification.request.identifier
        print("Notification tapped: \(identifier)")
    }
}
