import SwiftUI
import LanLensCore

struct DeviceDetailView: View {
    let device: Device
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var isScanning = false

    /// Get the current device data from appState (refreshes after scan)
    private var currentDevice: Device {
        appState.devices.first { $0.mac == device.mac } ?? device
    }

    var body: some View {
        VStack(spacing: 0) {
            // Compact header with back button only
            CompactHeader(onBack: { dismiss() })

            ScrollView {
                VStack(spacing: 12) {
                    // Hero card with device identity and score
                    DeviceHeroCard(
                        device: currentDevice,
                        displayName: displayName
                    )

                    // Network details
                    NetworkCard(device: currentDevice)

                    // Fingerprint data (if available)
                    if let fingerprint = currentDevice.fingerprint, fingerprint.hasData {
                        FingerprintCard(fingerprint: fingerprint)
                    }

                    // MAC Analysis (if available)
                    if let macAnalysis = currentDevice.macAnalysis {
                        MACAnalysisCard(macAddress: currentDevice.mac, macAnalysis: macAnalysis)
                    }

                    // Security posture (if available)
                    if let securityPosture = currentDevice.securityPosture {
                        SecurityPostureCard(securityPosture: securityPosture)
                    }

                    // Behavior profile (if available)
                    if let behaviorProfile = currentDevice.behaviorProfile {
                        BehaviorProfileCard(behaviorProfile: behaviorProfile)
                    }

                    // Smart signals (only if present)
                    if !currentDevice.smartSignals.isEmpty {
                        SmartSignalsCard(signals: currentDevice.smartSignals)
                    }

                    // Open ports (only if present)
                    if !currentDevice.openPorts.isEmpty {
                        OpenPortsCard(ports: currentDevice.openPorts)
                    }

                    // Port banners (if available)
                    if let portBanners = currentDevice.portBanners {
                        PortBannerCard(portBanners: portBanners)
                    }

                    // mDNS TXT records (if available)
                    if let mdnsTXT = currentDevice.mdnsTXTRecords {
                        MDNSTXTCard(mdnsTXT: mdnsTXT)
                    }

                    // Services (only if present)
                    if !currentDevice.services.isEmpty {
                        ServicesCard(services: currentDevice.services)
                    }

                    // Empty state hint when no ports/services detected
                    if currentDevice.openPorts.isEmpty && currentDevice.services.isEmpty {
                        EmptyStateHint()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }

            // Bottom action bar
            BottomActionBar(
                device: currentDevice,
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
        .background(Color.lanLensBackground)
        .navigationBarBackButtonHidden(true)
    }

    private var displayName: String {
        let dev = currentDevice

        if let label = dev.userLabel, !label.isEmpty {
            return label
        }
        if let hostname = dev.hostname, !hostname.isEmpty {
            return hostname.replacingOccurrences(of: ".local", with: "")
        }
        // Check fingerprint for friendly name (UPnP)
        if let friendlyName = dev.fingerprint?.friendlyName, !friendlyName.isEmpty {
            return friendlyName
        }
        // Check Fingerbank device name - but prefer vendor if Fingerbank returns generic category
        if let fingerbankName = dev.fingerprint?.fingerbankDeviceName, !fingerbankName.isEmpty {
            // Generic category names to skip in favor of vendor
            let genericCategories = [
                "Audio, Imaging or Video Equipment",
                "Generic Android",
                "Generic Apple",
                "Network Device",
                "Unknown",
                "IOT Device"
            ]

            let isGeneric = genericCategories.contains { fingerbankName.lowercased().contains($0.lowercased()) }

            if !isGeneric {
                return fingerbankName
            }
            // Fall through to vendor if generic
        }
        // Check fingerprint for manufacturer + model (UPnP)
        if let manufacturer = dev.fingerprint?.manufacturer {
            if let model = dev.fingerprint?.modelName {
                return "\(manufacturer) \(model)"
            }
            return manufacturer
        }
        if let vendor = dev.vendor, !vendor.isEmpty {
            return "\(vendor) Device"
        }
        // Use Fingerbank name even if generic (better than nothing)
        if let fingerbankName = dev.fingerprint?.fingerbankDeviceName, !fingerbankName.isEmpty {
            return fingerbankName
        }
        return "Network Device"
    }
}

// MARK: - Compact Header

private struct CompactHeader: View {
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Device Hero Card

private struct DeviceHeroCard: View {
    let device: Device
    let displayName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Device identity row
            HStack(spacing: 12) {
                // Large device icon with background
                ZStack {
                    Circle()
                        .fill(Color.lanLensAccent.opacity(0.15))
                        .frame(width: 52, height: 52)

                    DeviceIcon(deviceType: device.deviceType, size: 28)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    // Online status
                    HStack(spacing: 4) {
                        Circle()
                            .fill(device.isOnline ? Color.lanLensSuccess : Color.lanLensDanger)
                            .frame(width: 7, height: 7)
                        Text(device.isOnline ? "Online" : "Offline")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(device.isOnline ? Color.lanLensSuccess : Color.lanLensDanger)
                    }
                }

                Spacer()
            }

            // Capability tags
            CapabilityTags(device: device)
        }
        .padding(14)
        .background(Color.lanLensCard)
        .cornerRadius(10)
    }
}

// MARK: - Capability Tags

private struct CapabilityTags: View {
    let device: Device

    private var tags: [(String, String, Color)] {
        var result: [(String, String, Color)] = []

        // Device type (if known)
        if device.deviceType != .unknown {
            let icon = deviceTypeIcon(device.deviceType)
            result.append((icon, device.deviceType.rawValue.capitalized, Color.lanLensAccent))
        }

        // Services detected
        for service in device.services.prefix(2) {
            let serviceName = serviceDisplayName(service.name)
            result.append(("dot.radiowaves.up.forward", serviceName, Color.lanLensSuccess))
        }

        // Open ports summary
        if !device.openPorts.isEmpty {
            let portCount = device.openPorts.count
            let label = portCount == 1 ? "1 Port Open" : "\(portCount) Ports Open"
            result.append(("network", label, Color.lanLensWarning))
        }

        // Vendor (if no other tags)
        if result.isEmpty {
            if let vendor = device.vendor {
                result.append(("building.2", vendor, Color.lanLensSecondaryText))
            } else {
                result.append(("questionmark.circle", "Unknown Device", Color.lanLensSecondaryText))
            }
        }

        return result
    }

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                HStack(spacing: 4) {
                    Image(systemName: tag.0)
                        .font(.system(size: 10))
                    Text(tag.1)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(tag.2)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(tag.2.opacity(0.15))
                .cornerRadius(6)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel(for: tag.1, at: index))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Device capabilities")
    }

    private func accessibilityLabel(for tagText: String, at index: Int) -> String {
        if tagText.contains("Port") {
            return tagText
        } else if device.services.indices.contains(index - (device.deviceType != .unknown ? 1 : 0)) {
            return "Service: \(tagText)"
        } else if index == 0 && device.deviceType != .unknown {
            return "Device type: \(tagText)"
        } else {
            return tagText
        }
    }

    private func deviceTypeIcon(_ type: DeviceType) -> String {
        switch type {
        case .smartTV: return "tv"
        case .speaker: return "hifispeaker"
        case .camera: return "video"
        case .thermostat: return "thermometer"
        case .light: return "lightbulb"
        case .plug: return "powerplug"
        case .hub: return "house"
        case .printer: return "printer"
        case .nas: return "externaldrive"
        case .computer: return "desktopcomputer"
        case .phone: return "iphone"
        case .tablet: return "ipad"
        case .router: return "wifi.router"
        case .accessPoint: return "wifi"
        case .appliance: return "refrigerator"
        case .unknown: return "questionmark.circle"
        }
    }

    private func serviceDisplayName(_ name: String) -> String {
        // Clean up service names for display
        let cleaned = name
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "._tcp.local.", with: "")
            .replacingOccurrences(of: "._udp.local.", with: "")
            .replacingOccurrences(of: ".local.", with: "")

        // Truncate if too long
        if cleaned.count > 15 {
            return String(cleaned.prefix(12)) + "..."
        }
        return cleaned
    }
}

// MARK: - Flow Layout for Tags

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)

        for (index, subview) in subviews.enumerated() {
            if index < result.positions.count {
                let position = result.positions[index]
                subview.place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
            }
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalHeight = currentY + lineHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

// MARK: - Network Card

private struct NetworkCard: View {
    let device: Device

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(title: "Network", icon: "network")

            VStack(spacing: 0) {
                InfoRow(label: "IP Address", value: device.ip, isFirst: true)
                InfoRow(label: "MAC", value: formatMAC(device.mac))
                if let vendor = device.vendor {
                    InfoRow(label: "Vendor", value: vendor)
                }
                if let hostname = device.hostname {
                    InfoRow(label: "Hostname", value: hostname, isLast: true)
                } else if device.vendor != nil {
                    // Mark vendor as last if no hostname
                    EmptyView()
                } else {
                    // Mark MAC as last if no vendor or hostname
                    EmptyView()
                }
            }
        }
        .background(Color.lanLensCard)
        .cornerRadius(10)
    }

    private func formatMAC(_ mac: String) -> String {
        // Keep MAC as-is but ensure it's uppercase
        mac.uppercased()
    }
}

// MARK: - Fingerprint Card

private struct FingerprintCard: View {
    let fingerprint: DeviceFingerprint

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(title: "Device Identity", icon: "person.text.rectangle")

            VStack(spacing: 0) {
                // Fingerbank device name (if available)
                if let deviceName = fingerprint.fingerbankDeviceName {
                    InfoRow(label: "Device", value: deviceName, isFirst: true)
                }

                // Friendly name from UPnP
                if let friendlyName = fingerprint.friendlyName {
                    InfoRow(label: "Name", value: friendlyName, isFirst: fingerprint.fingerbankDeviceName == nil)
                }

                // Manufacturer
                if let manufacturer = fingerprint.manufacturer {
                    InfoRow(label: "Manufacturer", value: manufacturer)
                }

                // Model
                if let modelName = fingerprint.modelName {
                    InfoRow(label: "Model", value: modelName)
                }

                // Model number
                if let modelNumber = fingerprint.modelNumber {
                    InfoRow(label: "Model #", value: modelNumber)
                }

                // OS/Version
                if let os = fingerprint.operatingSystem {
                    let displayValue = fingerprint.osVersion != nil ? "\(os) \(fingerprint.osVersion!)" : os
                    InfoRow(label: "OS", value: displayValue)
                } else if let osVersion = fingerprint.osVersion {
                    InfoRow(label: "OS", value: osVersion)
                }

                // Fingerbank confidence score
                if let score = fingerprint.fingerbankScore {
                    HStack {
                        Text("Confidence")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.lanLensSecondaryText)

                        Spacer()

                        HStack(spacing: 4) {
                            // Progress bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.lanLensBackground)
                                        .frame(height: 4)

                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(scoreColor(score))
                                        .frame(width: geo.size.width * CGFloat(score) / 100.0, height: 4)
                                }
                            }
                            .frame(width: 50, height: 4)

                            Text("\(score)%")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(scoreColor(score))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }

                // Source indicator
                HStack {
                    Text("Source")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.lanLensSecondaryText)

                    Spacer()

                    HStack(spacing: 4) {
                        sourceIcon(fingerprint.source)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.lanLensAccent)
                        Text(sourceText(fingerprint.source))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.lanLensSecondaryText)

                        if fingerprint.cacheHit {
                            Text("(cached)")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.lanLensSecondaryText.opacity(0.7))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(Color.lanLensCard)
        .cornerRadius(10)
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 {
            return Color.lanLensSuccess
        } else if score >= 50 {
            return Color.lanLensWarning
        } else {
            return Color.lanLensDanger
        }
    }

    @ViewBuilder
    private func sourceIcon(_ source: FingerprintSource) -> some View {
        switch source {
        case .upnp:
            Image(systemName: "antenna.radiowaves.left.and.right")
        case .fingerbank:
            Image(systemName: "server.rack")
        case .both:
            Image(systemName: "checkmark.seal.fill")
        case .none:
            Image(systemName: "questionmark.circle")
        }
    }

    private func sourceText(_ source: FingerprintSource) -> String {
        switch source {
        case .upnp: return "UPnP"
        case .fingerbank: return "Fingerbank"
        case .both: return "UPnP + Fingerbank"
        case .none: return "Unknown"
        }
    }
}

// MARK: - Smart Signals Card

private struct SmartSignalsCard: View {
    let signals: [SmartSignal]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(title: "Smart Signals", icon: "sparkles")

            VStack(spacing: 8) {
                ForEach(Array(signals.enumerated()), id: \.offset) { _, signal in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.lanLensSuccess)

                        Text(signal.description)
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Color.lanLensCard)
        .cornerRadius(10)
    }
}

// MARK: - Open Ports Card

private struct OpenPortsCard: View {
    let ports: [LanLensCore.Port]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(title: "Open Ports", icon: "door.left.hand.open", count: ports.count)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(ports, id: \.uniqueID) { port in
                    PortPill(port: port)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Color.lanLensCard)
        .cornerRadius(10)
    }
}

private struct PortPill: View {
    let port: LanLensCore.Port

    var body: some View {
        VStack(spacing: 2) {
            Text("\(port.number)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)

            if let service = port.serviceName {
                Text(service)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.lanLensSecondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.lanLensBackground)
        .cornerRadius(6)
    }
}

// MARK: - Services Card

private struct ServicesCard: View {
    let services: [DiscoveredService]

    /// Deduplicated services grouped by display name, with combined discovery types
    private var uniqueServices: [(displayName: String, types: [ServiceDiscoveryType])] {
        var grouped: [String: [ServiceDiscoveryType]] = [:]
        for service in services {
            let name = service.displayName
            if grouped[name] != nil {
                if !grouped[name]!.contains(service.type) {
                    grouped[name]!.append(service.type)
                }
            } else {
                grouped[name] = [service.type]
            }
        }
        return grouped.map { (displayName: $0.key, types: $0.value) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(title: "Services", icon: "square.stack.3d.up", count: uniqueServices.count)

            VStack(spacing: 6) {
                ForEach(uniqueServices, id: \.displayName) { service in
                    HStack(spacing: 8) {
                        Image(systemName: serviceIcon(for: service.types.first ?? .mdns))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.lanLensAccent)
                            .frame(width: 16)

                        Text(service.displayName)
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer()

                        // Show all discovery types for this service
                        HStack(spacing: 4) {
                            ForEach(service.types, id: \.self) { type in
                                Text(type.rawValue)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(Color.lanLensSecondaryText)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.lanLensBackground)
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Color.lanLensCard)
        .cornerRadius(10)
    }

    private func serviceIcon(for type: ServiceDiscoveryType) -> String {
        switch type {
        case .mdns: return "bonjour"
        case .ssdp: return "network"
        case .upnp: return "antenna.radiowaves.left.and.right"
        }
    }
}

// MARK: - Empty State Hint

private struct EmptyStateHint: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 20))
                .foregroundStyle(Color.lanLensSecondaryText.opacity(0.5))

            Text("No open ports or services found")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.lanLensSecondaryText)

            Text("Tap Deep Scan to probe for services")
                .font(.system(size: 11))
                .foregroundStyle(Color.lanLensSecondaryText.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color.lanLensCard.opacity(0.5))
        .cornerRadius(10)
    }
}

// MARK: - Reusable Components

private struct CardHeader: View {
    let title: String
    let icon: String
    var count: Int? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.lanLensAccent)

            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.lanLensSecondaryText)

            if let count = count {
                Text("(\(count))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.lanLensSecondaryText.opacity(0.7))
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var isFirst: Bool = false
    var isLast: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.lanLensSecondaryText)

            Spacer()

            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.lanLensBackground.opacity(isFirst || isLast ? 0 : 0))
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
                    .background(Color.white.opacity(0.06))
                    .padding(.leading, 12)
            }
        }
    }
}

// MARK: - Bottom Action Bar

private struct BottomActionBar: View {
    let device: Device
    let isScanning: Bool
    let onRescan: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onRescan) {
                HStack(spacing: 6) {
                    if isScanning {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text(isScanning ? "Scanning..." : "Deep Scan")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.lanLensAccent)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(isScanning)
            .keyboardShortcut("r", modifiers: .command)

            Spacer()

            // Last seen timestamp
            Text(lastSeenText(device.lastSeen))
                .font(.system(size: 10))
                .foregroundStyle(Color.lanLensSecondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.lanLensCard.opacity(0.5))
    }

    private func lastSeenText(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

// MARK: - Port Unique ID Extension

private extension LanLensCore.Port {
    var uniqueID: String {
        "\(number)-\(`protocol`.rawValue)"
    }
}

#Preview {
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
