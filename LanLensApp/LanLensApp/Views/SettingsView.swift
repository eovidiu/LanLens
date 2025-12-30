import SwiftUI
import LanLensCore

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GeneralSettingsSection()
                APIServerSettingsSection(appState: appState, preferences: preferences)
                ScanningSettingsSection(preferences: preferences)
                FingerprintingSettingsSection(preferences: preferences)
                NotificationSettingsSection(preferences: preferences)
                AboutSection(appState: appState)
                Spacer(minLength: 20)
            }
            .padding(16)
        }
        .frame(width: 340)
        .frame(minHeight: 300, maxHeight: 500)
        .background(Color.lanLensBackground)
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.lanLensAccent)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }

            ToolbarItem(placement: .principal) {
                Text("Settings")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - General Settings Section

private struct GeneralSettingsSection: View {
    var body: some View {
        SettingsSectionView(title: "GENERAL") {
            LaunchAtLoginRow()
        }
    }
}

// MARK: - API Server Settings Section

private struct APIServerSettingsSection: View {
    let appState: AppState
    let preferences: UserPreferences

    var body: some View {
        SettingsSectionView(title: "API SERVER") {
            @Bindable var prefs = preferences

            ToggleRow(title: "Enable API Server", isOn: $prefs.apiEnabled)

            if preferences.apiEnabled {
                TextFieldRow(
                    title: "Port",
                    text: Binding(
                        get: { String(preferences.apiPort) },
                        set: { if let val = Int($0) { preferences.apiPort = val } }
                    ),
                    placeholder: "8080"
                )

                TextFieldRow(title: "Host", text: $prefs.apiHost, placeholder: "127.0.0.1")

                ToggleRow(title: "Authentication", isOn: $prefs.apiAuthEnabled)

                if preferences.apiAuthEnabled {
                    SecureFieldRow(title: "Token", text: $prefs.apiToken, placeholder: "Enter token")
                }

                APIStatusRow(isRunning: appState.isAPIRunning, port: preferences.apiPort)
            }
        }
    }
}

// MARK: - Scanning Settings Section

private struct ScanningSettingsSection: View {
    let preferences: UserPreferences

    var body: some View {
        SettingsSectionView(title: "SCANNING") {
            @Bindable var prefs = preferences

            ToggleRow(title: "Auto-scan", isOn: $prefs.autoScanEnabled)

            if preferences.autoScanEnabled {
                PickerRow(
                    title: "Interval",
                    selection: $prefs.autoScanInterval,
                    options: UserPreferences.scanIntervalOptions
                )
            }

            ToggleRow(title: "Passive Discovery", isOn: $prefs.passiveDiscoveryEnabled)
            ToggleRow(title: "Port Scanning", isOn: $prefs.portScanningEnabled)
        }
    }
}

// MARK: - Fingerprinting Settings Section

private struct FingerprintingSettingsSection: View {
    let preferences: UserPreferences

    var body: some View {
        SettingsSectionView(title: "DEVICE FINGERPRINTING") {
            @Bindable var prefs = preferences

            // Info text about UPnP (always enabled)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.lanLensSuccess)

                VStack(alignment: .leading, spacing: 2) {
                    Text("UPnP Fingerprinting")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                    Text("Always enabled for smart devices")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.lanLensSecondaryText)
                }

                Spacer()
            }

            Divider()
                .background(Color.white.opacity(0.1))

            ToggleRow(title: "Enable Fingerbank", isOn: $prefs.fingerbankEnabled)

            if preferences.fingerbankEnabled {
                SecureFieldRow(
                    title: "API Key",
                    text: $prefs.fingerbankAPIKey,
                    placeholder: "Enter Fingerbank key"
                )

                // Link to get API key
                HStack {
                    Spacer()
                    Link(destination: URL(string: "https://fingerbank.org")!) {
                        HStack(spacing: 4) {
                            Text("Get free API key")
                                .font(.system(size: 10))
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 9))
                        }
                        .foregroundStyle(Color.lanLensAccent)
                    }
                }
            }

            // Info about what Fingerbank provides
            if !preferences.fingerbankEnabled {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.lanLensSecondaryText)

                    Text("Fingerbank provides enhanced device identification including OS detection and confidence scores.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.lanLensSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Notification Settings Section

private struct NotificationSettingsSection: View {
    let preferences: UserPreferences

    var body: some View {
        SettingsSectionView(title: "NOTIFICATIONS") {
            @Bindable var prefs = preferences

            ToggleRow(title: "New Device Detected", isOn: $prefs.notifyNewDevices)
            ToggleRow(title: "Device Went Offline", isOn: $prefs.notifyDeviceOffline)
        }
    }
}

// MARK: - About Section

private struct AboutSection: View {
    let appState: AppState

    var body: some View {
        SettingsSectionView(title: "ABOUT") {
            InfoRow(label: "Version", value: "1.0.0")
            InfoRow(label: "Devices Found", value: "\(appState.deviceCount)")
            InfoRow(label: "Smart Devices", value: "\(appState.smartDeviceCount)")
        }
    }
}

// MARK: - Reusable Section View

private struct SettingsSectionView<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.lanLensSecondaryText)

            VStack(spacing: 12) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.lanLensCard)
            .cornerRadius(8)
        }
    }
}

// MARK: - Toggle Row

private struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.white)
        }
        .toggleStyle(.switch)
        .tint(Color.lanLensAccent)
    }
}

// MARK: - Text Field Row

private struct TextFieldRow: View {
    let title: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Color.lanLensSecondaryText)

            Spacer()

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .frame(width: 120)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.lanLensBackground)
                .cornerRadius(4)
        }
    }
}

// MARK: - Secure Field Row

private struct SecureFieldRow: View {
    let title: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Color.lanLensSecondaryText)

            Spacer()

            SecureField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .frame(width: 120)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.lanLensBackground)
                .cornerRadius(4)
        }
    }
}

// MARK: - Picker Row

private struct PickerRow: View {
    let title: String
    @Binding var selection: Int
    let options: [(label: String, minutes: Int)]

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Color.lanLensSecondaryText)

            Spacer()

            Picker("", selection: $selection) {
                ForEach(options, id: \.minutes) { option in
                    Text(option.label).tag(option.minutes)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(.white)
            .frame(width: 120)
        }
    }
}

// MARK: - Info Row

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.lanLensSecondaryText)

            Spacer()

            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - API Status Row

private struct APIStatusRow: View {
    let isRunning: Bool
    let port: Int

    var body: some View {
        HStack {
            Text("Status")
                .font(.system(size: 12))
                .foregroundStyle(Color.lanLensSecondaryText)

            Spacer()

            if isRunning {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.lanLensSuccess)
                        .frame(width: 8, height: 8)
                    Text("Running on port \(port)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.lanLensSuccess)
                }
            } else {
                Text("Stopped")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.lanLensSecondaryText)
            }
        }
    }
}

// MARK: - Launch at Login Row

private struct LaunchAtLoginRow: View {
    var body: some View {
        let service = LaunchAtLoginService.shared

        HStack {
            Text("Launch at Login")
                .font(.system(size: 12))
                .foregroundStyle(.white)

            Spacer()

            switch service.status {
            case .enabled:
                Button("Enabled") {
                    service.isEnabled = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Color.lanLensSuccess)

            case .disabled:
                Button("Enable") {
                    service.isEnabled = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Color.lanLensAccent)

            case .requiresApproval:
                Button("Open Settings") {
                    service.openSystemPreferences()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Color.lanLensWarning)

            default:
                Text(service.status.description)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.lanLensSecondaryText)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AppState())
            .environment(UserPreferences())
    }
}
