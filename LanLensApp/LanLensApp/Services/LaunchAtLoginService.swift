import Foundation
import AppKit
import ServiceManagement

@MainActor
final class LaunchAtLoginService {
    static let shared = LaunchAtLoginService()

    private init() {}

    var isEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            } else {
                return false
            }
        }
        set {
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    print("Failed to \(newValue ? "enable" : "disable") launch at login: \(error)")
                }
            }
        }
    }

    var status: LaunchAtLoginStatus {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .notRegistered:
                return .disabled
            case .enabled:
                return .enabled
            case .requiresApproval:
                return .requiresApproval
            case .notFound:
                return .notFound
            @unknown default:
                return .unknown
            }
        } else {
            return .unsupported
        }
    }

    func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum LaunchAtLoginStatus {
    case enabled
    case disabled
    case requiresApproval
    case notFound
    case unsupported
    case unknown

    var description: String {
        switch self {
        case .enabled:
            return "Enabled"
        case .disabled:
            return "Disabled"
        case .requiresApproval:
            return "Requires approval in System Settings"
        case .notFound:
            return "App not found"
        case .unsupported:
            return "Not supported on this macOS version"
        case .unknown:
            return "Unknown"
        }
    }
}
