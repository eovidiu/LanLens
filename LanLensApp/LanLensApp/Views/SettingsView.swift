import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LanLensCore

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header matching DeviceDetailView style
            SettingsHeader(onBack: { dismiss() })

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GeneralSettingsSection()
                    APIServerSettingsSection(appState: appState, preferences: preferences)
                    ScanningSettingsSection(preferences: preferences)
                    NetworkInterfacesSettingsSection(preferences: preferences)
                    FingerprintingSettingsSection(preferences: preferences)
                    NotificationSettingsSection(preferences: preferences)
                    ExportSection(appState: appState)
                    AboutSection(appState: appState)
                    Spacer(minLength: 20)
                }
                .padding(16)
            }
        }
        .frame(width: 340)
        .frame(minHeight: 300, maxHeight: 500)
        .background(Color.lanLensBackground)
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - Settings Header

private struct SettingsHeader: View {
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color.lanLensAccent)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            Text("Settings")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            // Invisible spacer to center the title
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                Text("Back")
                    .font(.system(size: 13, weight: .medium))
            }
            .opacity(0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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

// MARK: - Network Interfaces Settings Section

private struct NetworkInterfacesSettingsSection: View {
    let preferences: UserPreferences
    @State private var availableInterfaces: [NetworkInterfaceManager.NetworkInterface] = []
    @State private var isLoading = true

    var body: some View {
        SettingsSectionView(title: "NETWORK INTERFACES") {
            @Bindable var prefs = preferences

            ToggleRow(title: "Multi-Interface Scanning", isOn: $prefs.multiInterfaceScanEnabled)

            if preferences.multiInterfaceScanEnabled {
                Divider()
                    .background(Color.white.opacity(0.1))

                if isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Loading interfaces...")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.lanLensSecondaryText)
                    }
                } else if availableInterfaces.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.lanLensWarning)
                        Text("No active network interfaces found")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.lanLensSecondaryText)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select interfaces to scan:")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.lanLensSecondaryText)

                        ForEach(availableInterfaces) { iface in
                            NetworkInterfaceRow(
                                interface: iface,
                                isSelected: preferences.isNetworkInterfaceSelected(iface.id),
                                onToggle: {
                                    preferences.toggleNetworkInterface(iface.id)
                                }
                            )
                        }
                    }

                    // Info text
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.lanLensSecondaryText)
                        Text("Deselect all to scan all active interfaces automatically.")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.lanLensSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                }

                // Refresh button
                HStack {
                    Spacer()
                    Button {
                        Task {
                            await refreshInterfaces()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                            Text("Refresh")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(Color.lanLensAccent)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.lanLensSecondaryText)
                    Text("Enable to scan multiple network interfaces (VLANs) simultaneously.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.lanLensSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task {
            if preferences.multiInterfaceScanEnabled {
                await refreshInterfaces()
            }
        }
        .onChange(of: preferences.multiInterfaceScanEnabled) { _, newValue in
            if newValue {
                Task {
                    await refreshInterfaces()
                }
            }
        }
    }

    private func refreshInterfaces() async {
        isLoading = true
        let interfaces = await NetworkInterfaceManager.shared.getAvailableInterfaces()
        await MainActor.run {
            availableInterfaces = interfaces
            isLoading = false
        }
    }
}

// MARK: - Network Interface Row

private struct NetworkInterfaceRow: View {
    let interface: NetworkInterfaceManager.NetworkInterface
    let isSelected: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                // Checkbox
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Color.lanLensAccent : Color.lanLensSecondaryText)

                // Interface info
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(interface.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)

                        Text("(\(interface.id))")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.lanLensSecondaryText)

                        if interface.isActive {
                            Circle()
                                .fill(Color.lanLensSuccess)
                                .frame(width: 6, height: 6)
                        } else {
                            Circle()
                                .fill(Color.lanLensSecondaryText)
                                .frame(width: 6, height: 6)
                        }
                    }

                    Text("\(interface.ipAddress) - \(interface.cidr)")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.lanLensSecondaryText)
                }

                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isHovered ? Color.white.opacity(0.05) : Color.clear)
            .cornerRadius(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
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

// MARK: - Export Section

private struct ExportSection: View {
    let appState: AppState
    @State private var isExporting = false
    @State private var showFormatPicker = false
    @State private var exportMessage: String?
    @State private var isSuccess = false

    var body: some View {
        SettingsSectionView(title: "DATA EXPORT") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export Device Inventory")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                    Text("\(appState.deviceCount) devices available")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.lanLensSecondaryText)
                }

                Spacer()

                if isExporting {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 60)
                } else {
                    Button {
                        showFormatPicker = true
                    } label: {
                        Text("Export")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(appState.deviceCount > 0 ? Color.lanLensAccent : Color.lanLensSecondaryText)
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.deviceCount == 0)
                    .popover(isPresented: $showFormatPicker, arrowEdge: .bottom) {
                        ExportFormatPicker(
                            onSelect: { format in
                                showFormatPicker = false
                                Task {
                                    await performExport(format: format)
                                }
                            },
                            onCancel: {
                                showFormatPicker = false
                            }
                        )
                    }
                }
            }

            // Status message
            if let message = exportMessage {
                HStack(spacing: 6) {
                    Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(isSuccess ? Color.lanLensSuccess : Color.lanLensWarning)
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(isSuccess ? Color.lanLensSuccess : Color.lanLensWarning)
                    Spacer()
                }
                .transition(.opacity)
            }
        }
    }

    private func performExport(format: ExportFormat) async {
        isExporting = true
        exportMessage = nil

        // Create save panel
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = format == .json ? [.json] : [.commaSeparatedText]
        savePanel.nameFieldStringValue = "lanlens-export.\(format.fileExtension)"
        savePanel.title = "Export Device Inventory"
        savePanel.message = "Choose where to save the \(format.displayName) export file"

        let response = await savePanel.beginSheetModal(for: NSApp.keyWindow ?? NSApp.windows.first!)

        if response == .OK, let url = savePanel.url {
            do {
                let devices = appState.devices
                let data = try await ExportService.shared.exportDevices(devices, format: format)
                try data.write(to: url, options: .atomic)

                await MainActor.run {
                    isSuccess = true
                    exportMessage = "Exported \(devices.count) devices"
                    clearMessageAfterDelay()
                }
            } catch {
                await MainActor.run {
                    isSuccess = false
                    exportMessage = "Export failed: \(error.localizedDescription)"
                    clearMessageAfterDelay()
                }
            }
        }

        isExporting = false
    }

    private func clearMessageAfterDelay() {
        Task {
            try? await Task.sleep(for: .seconds(5))
            await MainActor.run {
                withAnimation {
                    exportMessage = nil
                }
            }
        }
    }
}

// MARK: - Export Format Picker

private struct ExportFormatPicker: View {
    let onSelect: (ExportFormat) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Select Format")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.lanLensSecondaryText)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            ForEach(ExportFormat.allCases, id: \.rawValue) { format in
                Button {
                    onSelect(format)
                } label: {
                    HStack {
                        Image(systemName: format == .json ? "curlybraces" : "tablecells")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.lanLensAccent)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(format.displayName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white)
                            Text(format == .json ? "Full device data" : "Spreadsheet compatible")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.lanLensSecondaryText)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if format != ExportFormat.allCases.last {
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 12)
                }
            }
        }
        .frame(width: 180)
        .padding(.bottom, 8)
        .background(Color.lanLensCard)
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
