import SwiftUI
import LanLensCore

struct DeviceDetailView: View {
    let device: Device
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var isScanning = false
    @State private var userLabel: String = ""
    @State private var isEditingLabel = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SmartScoreSectionView(smartScore: device.smartScore)
                NetworkSectionView(device: device)
                SmartSignalsSectionView(signals: device.smartSignals)
                OpenPortsSectionView(ports: device.openPorts)
                ServicesSectionView(services: device.services)
                Spacer(minLength: 20)
            }
            .padding(16)
        }
        .frame(width: 340)
        .frame(minHeight: 300, maxHeight: 500)
        .background(Color.lanLensBackground)
        .navigationTitle(displayName)
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
                HStack(spacing: 8) {
                    DeviceIcon(deviceType: device.deviceType, size: 20)
                    Text(displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            DeviceDetailBottomBar(
                device: device,
                isScanning: isScanning,
                onRescan: {
                    Task {
                        isScanning = true
                        await appState.scanPorts(for: device)
                        isScanning = false
                    }
                }
            )
        }
        .onAppear {
            userLabel = device.userLabel ?? ""
        }
    }

    private var displayName: String {
        if let label = device.userLabel, !label.isEmpty {
            return label
        }
        if let hostname = device.hostname, !hostname.isEmpty {
            return hostname.replacingOccurrences(of: ".local", with: "")
        }
        return device.deviceType.rawValue
    }
}

// MARK: - Smart Score Section

private struct SmartScoreSectionView: View {
    let smartScore: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Smart Score")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.lanLensSecondaryText)

            HStack(spacing: 12) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.lanLensCard)
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.lanLensAccent)
                            .frame(width: geometry.size.width * CGFloat(smartScore) / 100, height: 8)
                    }
                }
                .frame(height: 8)

                Text("\(smartScore)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                +
                Text("/100")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.lanLensSecondaryText)
            }
        }
        .padding(12)
        .background(Color.lanLensCard)
        .cornerRadius(8)
    }
}

// MARK: - Network Section

private struct NetworkSectionView: View {
    let device: Device

    var body: some View {
        DetailSectionView(title: "NETWORK") {
            InfoRowView(label: "IP Address", value: device.ip)
            InfoRowView(label: "MAC Address", value: device.mac)
            if let vendor = device.vendor {
                InfoRowView(label: "Vendor", value: vendor)
            }
            if let hostname = device.hostname {
                InfoRowView(label: "Hostname", value: hostname)
            }
        }
    }
}

// MARK: - Smart Signals Section

private struct SmartSignalsSectionView: View {
    let signals: [SmartSignal]

    var body: some View {
        if !signals.isEmpty {
            DetailSectionView(title: "SMART SIGNALS") {
                // Use enumerated for stable indexing when signals might have duplicate descriptions
                ForEach(Array(signals.enumerated()), id: \.offset) { index, signal in
                    HStack {
                        Circle()
                            .fill(Color.lanLensAccent)
                            .frame(width: 6, height: 6)

                        Text(signal.description)
                            .font(.system(size: 12))
                            .foregroundStyle(.white)

                        Spacer()

                        Text("+\(signal.weight)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.lanLensSuccess)
                    }
                }
            }
        }
    }
}

// MARK: - Open Ports Section

private struct OpenPortsSectionView: View {
    let ports: [LanLensCore.Port]

    var body: some View {
        if !ports.isEmpty {
            DetailSectionView(title: "OPEN PORTS") {
                // Use composite key: port number + protocol for unique identification
                ForEach(ports, id: \.uniqueID) { port in
                    HStack {
                        Text("\(port.number)/\(port.protocol.rawValue)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white)

                        Spacer()

                        if let serviceName = port.serviceName {
                            Text(serviceName)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.lanLensSecondaryText)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Services Section

private struct ServicesSectionView: View {
    let services: [DiscoveredService]

    var body: some View {
        if !services.isEmpty {
            DetailSectionView(title: "SERVICES") {
                // Use enumerated for stable indexing when service names might not be unique
                ForEach(Array(services.enumerated()), id: \.offset) { index, service in
                    HStack {
                        Text(service.name)
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer()

                        Text(service.type.rawValue)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.lanLensSecondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.lanLensCard)
                            .cornerRadius(4)
                    }
                }
            }
        }
    }
}

// MARK: - Reusable Section View

private struct DetailSectionView<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.lanLensSecondaryText)

            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.lanLensCard)
            .cornerRadius(8)
        }
    }
}

// MARK: - Info Row View

private struct InfoRowView: View {
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
                .textSelection(.enabled)
        }
    }
}

// MARK: - Bottom Bar

private struct DeviceDetailBottomBar: View {
    let device: Device
    let isScanning: Bool
    let onRescan: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onRescan) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                    Text("Rescan")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.lanLensAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.lanLensCard)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(isScanning)
            .opacity(isScanning ? 0.6 : 1)
            .keyboardShortcut("r", modifiers: .command)

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(device.isOnline ? Color.lanLensSuccess : Color.lanLensDanger)
                    .frame(width: 8, height: 8)

                Text(device.isOnline ? "Online" : "Offline")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.lanLensSecondaryText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.lanLensBackground)
    }
}

// MARK: - OpenPort Unique ID Extension

private extension LanLensCore.Port {
    /// Unique identifier combining port number and protocol
    var uniqueID: String {
        "\(number)-\(`protocol`.rawValue)"
    }
}

#Preview {
    NavigationStack {
        DeviceDetailView(
            device: Device(
                mac: "AA:BB:CC:DD:EE:FF",
                ip: "192.168.1.45",
                hostname: "LivingRoomTV.local",
                vendor: "Samsung",
                firstSeen: Date(),
                lastSeen: Date(),
                isOnline: true,
                smartScore: 85,
                deviceType: .smartTV
            )
        )
        .environment(AppState())
    }
}
