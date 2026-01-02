import SwiftUI
import LanLensCore

enum NavigationDestination: Hashable {
    case deviceDetail(Device)
    case settings
}

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(UserPreferences.self) private var preferences

    @State private var navigationPath = NavigationPath()
    @State private var isOtherDevicesExpanded = true

    var body: some View {
        NavigationStack(path: $navigationPath) {
            MainContentView(
                appState: appState,
                preferences: preferences,
                navigationPath: $navigationPath,
                isOtherDevicesExpanded: $isOtherDevicesExpanded
            )
            .navigationDestination(for: NavigationDestination.self) { destination in
                switch destination {
                case .deviceDetail(let device):
                    DeviceDetailView(device: device)
                        .environment(appState)
                case .settings:
                    SettingsView()
                        .environment(appState)
                        .environment(preferences)
                }
            }
        }
        .frame(width: 360)
        .frame(minHeight: 400, maxHeight: 700)
        .background(Color.lanLensBackground)
        .contextMenu {
            Button("Quit Lan Lens") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

// MARK: - Main Content View

private struct MainContentView: View {
    let appState: AppState
    let preferences: UserPreferences
    @Binding var navigationPath: NavigationPath
    @Binding var isOtherDevicesExpanded: Bool

    /// Count of devices with medium or higher security risk
    private var issueCount: Int {
        appState.devices.filter { device in
            guard let posture = device.securityPosture else { return false }
            return posture.riskLevel.numericValue >= 2 // medium or higher
        }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(onSettingsTap: {
                navigationPath.append(NavigationDestination.settings)
            })

            Divider()
                .background(Color.white.opacity(0.1))

            NetworkSummaryHeader(
                totalDevices: appState.devices.count,
                smartDevices: appState.smartDevices.count,
                issueCount: issueCount,
                onIssueTap: {
                    // TODO: Implement issue filtering/navigation
                }
            )

            ScrollView {
                VStack(spacing: 16) {
                    DeviceListView(
                        title: "Smart Devices",
                        devices: appState.smartDevices,
                        showScores: true,
                        emptyMessage: "No smart devices detected",
                        onDeviceTap: { device in
                            navigationPath.append(NavigationDestination.deviceDetail(device))
                        }
                    )

                    OtherDevicesSectionView(
                        devices: appState.otherDevices,
                        isExpanded: $isOtherDevicesExpanded,
                        onDeviceTap: { device in
                            navigationPath.append(NavigationDestination.deviceDetail(device))
                        }
                    )
                }
                .padding(.vertical, 12)
            }

            Divider()
                .background(Color.white.opacity(0.1))

            BottomBarView(
                appState: appState,
                preferences: preferences
            )
        }
    }
}

// MARK: - Header View

private struct HeaderView: View {
    let onSettingsTap: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.lanLensAccent)

            Text("Lan Lens")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            Button(action: onSettingsTap) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.lanLensSecondaryText)
            }
            .buttonStyle(.plain)
            .help("Settings")
            .keyboardShortcut(",", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Network Summary Header

private struct NetworkSummaryHeader: View {
    let totalDevices: Int
    let smartDevices: Int
    let issueCount: Int
    let onIssueTap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Devices section
            SummaryItem(
                value: totalDevices,
                label: "Devices",
                valueColor: .white
            )

            SummaryDivider()

            // Smart section
            SummaryItem(
                value: smartDevices,
                label: "Smart",
                valueColor: .lanLensAccent
            )

            SummaryDivider()

            // Issues section (tappable)
            Button(action: onIssueTap) {
                IssuesSummaryItem(
                    issueCount: issueCount
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.lanLensCard.opacity(0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summaryAccessibilityLabel)
    }

    private var summaryAccessibilityLabel: String {
        let issueText = issueCount == 1 ? "issue" : "issues"
        return "\(totalDevices) devices, \(smartDevices) smart, \(issueCount) \(issueText)"
    }
}

// MARK: - Summary Item

private struct SummaryItem: View {
    let value: Int
    let label: String
    let valueColor: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(valueColor)

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.lanLensSecondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Issues Summary Item

private struct IssuesSummaryItem: View {
    let issueCount: Int

    @State private var isHovered = false

    private var issueColor: Color {
        issueCount > 0 ? .lanLensWarning : .lanLensSuccess
    }

    var body: some View {
        HStack(spacing: 4) {
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Text("\(issueCount)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(issueColor)

                    if issueCount > 0 {
                        Circle()
                            .fill(issueColor)
                            .frame(width: 6, height: 6)
                    }
                }

                Text("Issues")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.lanLensSecondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(issueCount == 0 ? "No security issues" : "\(issueCount) security issues detected")
        .accessibilityHint("Tap to view devices with security issues")
    }
}

// MARK: - Summary Divider

private struct SummaryDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 1, height: 28)
            .padding(.horizontal, 8)
    }
}

// MARK: - Other Devices Section

private struct OtherDevicesSectionView: View {
    let devices: [Device]
    @Binding var isExpanded: Bool
    let onDeviceTap: (Device) -> Void

    @State private var isHeaderHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("OTHER DEVICES")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isHeaderHovered ? Color.white.opacity(0.9) : Color.lanLensSecondaryText)

                    Text("(\(devices.count))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isHeaderHovered ? Color.white.opacity(0.7) : Color.lanLensSecondaryText.opacity(0.7))

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isHeaderHovered ? Color.white.opacity(0.9) : Color.lanLensSecondaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHeaderHovered ? Color.white.opacity(0.06) : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHeaderHovered = hovering
                }
            }

            if isExpanded {
                if devices.isEmpty {
                    HStack {
                        Spacer()
                        Text("No other devices")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.lanLensSecondaryText.opacity(0.7))
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else {
                    VStack(spacing: 6) {
                        ForEach(devices) { device in
                            DeviceRowView(
                                device: device,
                                showScore: false,
                                onTap: { onDeviceTap(device) }
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Bottom Bar View

private struct BottomBarView: View {
    let appState: AppState
    let preferences: UserPreferences

    var body: some View {
        HStack(spacing: 12) {
            ScanButton(
                isScanning: appState.isScanning,
                onScan: {
                    Task {
                        let apiKey = preferences.fingerbankEnabled ? preferences.fingerbankAPIKey : nil
                        await appState.runQuickScan(fingerbankAPIKey: apiKey)
                    }
                },
                onStop: {
                    appState.stopScanning()
                }
            )

            Spacer()

            StatusIndicator(
                isAPIRunning: appState.isAPIRunning,
                isScanning: appState.isScanning
            )

            MoreMenu(
                appState: appState,
                preferences: preferences
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Scan Button

private struct ScanButton: View {
    let isScanning: Bool
    let onScan: () -> Void
    let onStop: () -> Void

    var body: some View {
        if isScanning {
            Button(action: onStop) {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .semibold))

                    Text("Stop")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.lanLensDanger)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        } else {
            Button(action: onScan) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))

                    Text("Scan Now")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.lanLensAccent)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: .command)
        }
    }
}

// MARK: - More Menu

private struct MoreMenu: View {
    let appState: AppState
    let preferences: UserPreferences

    @State private var isHovered = false
    @State private var showMenu = false
    @State private var showClearConfirmation = false

    var body: some View {
        Button {
            showMenu = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.white.opacity(0.25) : Color.white.opacity(0.12))
                    .frame(width: 36, height: 28)

                Text("•••")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .offset(y: -2)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .help("More options")
        .accessibilityLabel("More options menu")
        .accessibilityHint("Opens menu with Full Scan, API Server, and Quit options")
        .popover(isPresented: $showMenu, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                MenuButton(title: "Full Scan", icon: "antenna.radiowaves.left.and.right") {
                    showMenu = false
                    Task {
                        await appState.runFullScan()
                    }
                }
                .disabled(appState.isScanning)

                Divider()
                    .padding(.vertical, 4)

                if appState.isAPIRunning {
                    MenuButton(title: "Stop API Server", icon: "stop.circle") {
                        showMenu = false
                        appState.stopAPIServer()
                    }
                } else {
                    MenuButton(title: "Start API Server", icon: "play.circle") {
                        showMenu = false
                        Task {
                            let token = preferences.apiAuthEnabled ? preferences.apiToken : nil
                            await appState.startAPIServer(
                                port: preferences.apiPort,
                                host: preferences.apiHost,
                                token: token
                            )
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 4)

                MenuButton(
                    title: "Clear Data",
                    icon: "trash",
                    isDestructive: true
                ) {
                    showMenu = false
                    // Small delay to let the menu close before showing confirmation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showClearConfirmation = true
                    }
                }
                .disabled(appState.deviceCount == 0)

                Divider()
                    .padding(.vertical, 4)

                MenuButton(title: "Quit Lan Lens", icon: "xmark.circle", shortcut: "⌘Q") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(8)
            .frame(width: 180)
        }
        .popover(isPresented: $showClearConfirmation, arrowEdge: .bottom) {
            ClearDevicesConfirmationView(
                deviceCount: appState.deviceCount,
                onConfirm: { preserveLabels in
                    showClearConfirmation = false
                    Task {
                        await appState.clearAllDevices(preserveLabels: preserveLabels)
                    }
                },
                onCancel: {
                    showClearConfirmation = false
                }
            )
        }
    }
}

// MARK: - Menu Button

private struct MenuButton: View {
    let title: String
    let icon: String
    var shortcut: String? = nil
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    private var textColor: Color {
        if !isEnabled {
            return .secondary
        }
        return isDestructive ? Color.lanLensDanger : .primary
    }

    private var hoverColor: Color {
        isDestructive ? Color.lanLensDanger.opacity(0.2) : Color.accentColor.opacity(0.2)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                    .foregroundColor(textColor)

                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(textColor)

                Spacer()

                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered && isEnabled ? hoverColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    MenuBarView()
        .environment(AppState())
        .environment(UserPreferences())
}
