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
    @State private var isOtherDevicesExpanded = false

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
        .frame(width: 340)
        .frame(minHeight: 200, maxHeight: 500)
        .background(Color.lanLensBackground)
        .task {
            if appState.devices.isEmpty {
                await appState.runQuickScan()
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

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(onSettingsTap: {
                navigationPath.append(NavigationDestination.settings)
            })

            Divider()
                .background(Color.white.opacity(0.1))

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

            Text("LanLens")
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

// MARK: - Other Devices Section

private struct OtherDevicesSectionView: View {
    let devices: [Device]
    @Binding var isExpanded: Bool
    let onDeviceTap: (Device) -> Void

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
                        .foregroundStyle(Color.lanLensSecondaryText)

                    Text("(\(devices.count))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.lanLensSecondaryText.opacity(0.7))

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.lanLensSecondaryText)
                }
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
                        await appState.runQuickScan()
                    }
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

    var body: some View {
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
        .disabled(isScanning)
        .opacity(isScanning ? 0.6 : 1)
        .keyboardShortcut("r", modifiers: .command)
    }
}

// MARK: - More Menu

private struct MoreMenu: View {
    let appState: AppState
    let preferences: UserPreferences

    var body: some View {
        Menu {
            Button("Full Scan") {
                Task {
                    await appState.runFullScan()
                }
            }
            .disabled(appState.isScanning)

            Divider()

            if appState.isAPIRunning {
                Button("Stop API Server") {
                    appState.stopAPIServer()
                }
            } else {
                Button("Start API Server") {
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

            Button("Quit LanLens") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14))
                .foregroundStyle(Color.lanLensSecondaryText)
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }
}

#Preview {
    MenuBarView()
        .environment(AppState())
        .environment(UserPreferences())
}
