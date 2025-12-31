import SwiftUI
import LanLensCore

struct DeviceRowView: View {
    let device: Device
    let showScore: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    init(device: Device, showScore: Bool = true, onTap: @escaping () -> Void) {
        self.device = device
        self.showScore = showScore
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                // Risk indicator border (left side only)
                RiskBorder(riskLevel: device.securityPosture?.riskLevel, isHovered: isHovered)

                // Main content
                HStack(spacing: 12) {
                    // Device icon with behavior badge overlay
                    ZStack(alignment: .bottomTrailing) {
                        DeviceIcon(deviceType: device.deviceType)
                        BehaviorBadge(behaviorProfile: device.behaviorProfile)
                            .offset(x: 4, y: 4)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Text(device.ip)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.lanLensSecondaryText)

                            if let vendor = device.vendor {
                                Text("•")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.lanLensSecondaryText.opacity(0.5))

                                Text(vendor)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.lanLensSecondaryText)
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer()

                    // Security badge (only shows for medium/high/critical risk)
                    SecurityBadge(securityPosture: device.securityPosture)

                    if showScore && device.smartScore > 0 {
                        VStack(alignment: .trailing, spacing: 2) {
                            ScoreIndicator(score: device.smartScore)
                            Text("\(device.smartScore)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.lanLensSecondaryText)
                        }
                    }

                    // Hover chevron indicator
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.lanLensSecondaryText)
                        .opacity(isHovered ? 1 : 0)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovered ? Color.lanLensAccent.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint("Double-tap to view details")
    }

    // MARK: - Background Color

    /// Background color with critical device tinting
    private var backgroundColor: Color {
        let riskLevel = device.securityPosture?.riskLevel

        if riskLevel == .critical {
            // Critical devices get a subtle red background tint
            return isHovered
                ? Color.lanLensDanger.opacity(0.12)
                : Color.lanLensDanger.opacity(0.06)
        }

        // Default background behavior
        return isHovered ? Color.white.opacity(0.08) : Color.lanLensCard
    }

    // MARK: - Accessibility

    /// Accessibility label including risk level information
    private var accessibilityLabelText: String {
        var label = "\(displayName), \(device.ip)"

        if let riskLevel = device.securityPosture?.riskLevel {
            switch riskLevel {
            case .critical:
                label += ", Critical security risk"
            case .high:
                label += ", High security risk"
            case .medium:
                label += ", Medium security risk"
            case .low, .unknown:
                break
            }
        }

        return label
    }

    private var displayName: String {
        let macSuffix = String(device.mac.suffix(5)).replacingOccurrences(of: ":", with: "")

        if let label = device.userLabel, !label.isEmpty {
            return label
        }
        if let hostname = device.hostname, !hostname.isEmpty {
            return hostname.replacingOccurrences(of: ".local", with: "")
        }
        // Check fingerprint for friendly name (UPnP)
        if let friendlyName = device.fingerprint?.friendlyName, !friendlyName.isEmpty {
            return friendlyName
        }
        // Check Fingerbank device name - but prefer vendor if Fingerbank returns generic category
        if let fingerbankName = device.fingerprint?.fingerbankDeviceName, !fingerbankName.isEmpty {
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
                return "\(fingerbankName) (\(macSuffix))"
            }
            // Fall through to vendor if generic
        }
        // Check fingerprint for manufacturer + model (UPnP)
        if let manufacturer = device.fingerprint?.manufacturer {
            if let model = device.fingerprint?.modelName {
                return "\(manufacturer) \(model)"
            }
            return manufacturer
        }
        if let vendor = device.vendor, !vendor.isEmpty {
            return "\(vendor) (\(macSuffix))"
        }
        // Use Fingerbank name even if generic (better than nothing)
        if let fingerbankName = device.fingerprint?.fingerbankDeviceName, !fingerbankName.isEmpty {
            return "\(fingerbankName) (\(macSuffix))"
        }
        if device.deviceType != .unknown {
            return device.deviceType.rawValue.capitalized
        }
        // Last resort: "Device" + MAC suffix
        return "Device (\(macSuffix))"
    }
}

// MARK: - Risk Border

/// A colored left border indicating security risk level.
/// Only visible for medium, high, and critical risk devices.
private struct RiskBorder: View {
    let riskLevel: RiskLevel?
    let isHovered: Bool

    /// Border width in points
    private let borderWidth: CGFloat = 3

    /// Corner radius for left side only (top-left and bottom-left)
    private let cornerRadius: CGFloat = 8

    var body: some View {
        if let level = riskLevel, shouldShowBorder(for: level) {
            // Custom shape for left-side-only rounded corners
            UnevenRoundedRectangle(
                topLeadingRadius: cornerRadius,
                bottomLeadingRadius: cornerRadius,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
            .fill(borderColor(for: level))
            .frame(width: borderWidth)
        }
    }

    /// Determines if border should be shown for the given risk level.
    /// Only medium, high, and critical risk levels display a border.
    private func shouldShowBorder(for level: RiskLevel) -> Bool {
        switch level {
        case .medium, .high, .critical:
            return true
        case .low, .unknown:
            return false
        }
    }

    /// Returns the appropriate border color for each risk level.
    /// Brightens slightly (+0.1 opacity) on hover.
    private func borderColor(for level: RiskLevel) -> Color {
        let hoverBoost: CGFloat = isHovered ? 0.1 : 0

        switch level {
        case .critical:
            return Color.lanLensDanger.opacity(1.0)
        case .high:
            return Color.lanLensDanger.opacity(0.75 + hoverBoost)
        case .medium:
            return Color.lanLensWarning.opacity(1.0)
        case .low, .unknown:
            return .clear
        }
    }
}

#Preview("Risk Indicator Borders") {
    VStack(spacing: 8) {
        // Critical risk device
        DeviceRowView(
            device: Device(
                mac: "AA:BB:CC:DD:EE:01",
                ip: "192.168.1.100",
                hostname: "Compromised-IoT.local",
                vendor: "Generic",
                firstSeen: Date(),
                lastSeen: Date(),
                isOnline: true,
                smartScore: 25,
                deviceType: .appliance,
                securityPosture: SecurityPostureData(
                    riskLevel: .critical,
                    riskScore: 95
                )
            ),
            onTap: {}
        )

        // High risk device
        DeviceRowView(
            device: Device(
                mac: "AA:BB:CC:DD:EE:02",
                ip: "192.168.1.101",
                hostname: "OldRouter.local",
                vendor: "Netgear",
                firstSeen: Date(),
                lastSeen: Date(),
                isOnline: true,
                smartScore: 45,
                deviceType: .router,
                securityPosture: SecurityPostureData(
                    riskLevel: .high,
                    riskScore: 75
                )
            ),
            onTap: {}
        )

        // Medium risk device
        DeviceRowView(
            device: Device(
                mac: "AA:BB:CC:DD:EE:03",
                ip: "192.168.1.102",
                hostname: "SmartTV.local",
                vendor: "Samsung",
                firstSeen: Date(),
                lastSeen: Date(),
                isOnline: true,
                smartScore: 65,
                deviceType: .smartTV,
                securityPosture: SecurityPostureData(
                    riskLevel: .medium,
                    riskScore: 45
                )
            ),
            onTap: {}
        )

        // Low risk device (no border)
        DeviceRowView(
            device: Device(
                mac: "AA:BB:CC:DD:EE:04",
                ip: "192.168.1.103",
                hostname: "MacBook.local",
                vendor: "Apple",
                firstSeen: Date(),
                lastSeen: Date(),
                isOnline: true,
                smartScore: 90,
                deviceType: .computer,
                securityPosture: SecurityPostureData(
                    riskLevel: .low,
                    riskScore: 10
                )
            ),
            onTap: {}
        )

        // No security posture (no border)
        DeviceRowView(
            device: Device(
                mac: "AA:BB:CC:DD:EE:05",
                ip: "192.168.1.104",
                vendor: "Unknown",
                firstSeen: Date(),
                lastSeen: Date(),
                isOnline: true,
                smartScore: 0,
                deviceType: .unknown
            ),
            showScore: false,
            onTap: {}
        )
    }
    .padding()
    .background(Color.lanLensBackground)
}
