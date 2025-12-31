import SwiftUI
import LanLensCore

/// A subtle overlay badge indicating device behavior classification.
/// Designed to overlay the bottom-right corner of a DeviceIcon.
struct BehaviorBadge: View {
    let behaviorProfile: DeviceBehaviorProfile?

    /// Badge diameter
    private let badgeSize: CGFloat = 16
    /// Icon size within the badge
    private let iconSize: CGFloat = 10
    /// Green dot indicator size
    private let dotSize: CGFloat = 5

    var body: some View {
        if let profile = behaviorProfile,
           profile.classification != .unknown {
            ZStack(alignment: .bottomTrailing) {
                // Badge background
                Circle()
                    .fill(Color.lanLensCard)
                    .frame(width: badgeSize, height: badgeSize)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.lanLensBackground, lineWidth: 1)
                    )

                // Classification icon
                Image(systemName: symbolName(for: profile.classification))
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(iconColor(for: profile.classification))
                    .frame(width: badgeSize, height: badgeSize)

                // Always-on indicator (green dot)
                if profile.isAlwaysOn {
                    Circle()
                        .fill(Color.lanLensSuccess)
                        .frame(width: dotSize, height: dotSize)
                        .offset(x: 2, y: 2)
                }
            }
            .tooltip(tooltipText(for: profile))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(for: profile))
        }
    }

    // MARK: - Tooltip

    /// Generates tooltip text for the behavior badge.
    private func tooltipText(for profile: DeviceBehaviorProfile) -> String {
        var lines: [String] = []

        // Line 1: Classification name
        lines.append(classificationLabel(for: profile.classification))

        // Line 2: Always-on status (if applicable)
        if profile.isAlwaysOn {
            lines.append("Always-on device")
        }

        // Line 3: Uptime percentage (if greater than 0)
        if profile.averageUptimePercent > 0 {
            let uptimeFormatted = String(format: "%.0f", profile.averageUptimePercent)
            lines.append("\(uptimeFormatted)% uptime")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Symbol Mapping

    private func symbolName(for classification: BehaviorClassification) -> String {
        switch classification {
        case .infrastructure:
            return "server.rack"
        case .server:
            return "externaldrive.fill.badge.checkmark"
        case .iot:
            return "sensor.fill"
        case .workstation:
            return "desktopcomputer"
        case .portable:
            return "laptopcomputer"
        case .mobile:
            return "iphone"
        case .guest:
            return "clock.badge.questionmark"
        case .unknown:
            return "questionmark"
        }
    }

    // MARK: - Icon Color

    private func iconColor(for classification: BehaviorClassification) -> Color {
        switch classification {
        case .infrastructure, .server:
            return Color.lanLensAccent
        case .iot:
            return Color.lanLensSuccess
        case .workstation, .portable:
            return Color.lanLensSecondaryText
        case .mobile:
            return Color.lanLensSecondaryText
        case .guest:
            return Color.lanLensWarning
        case .unknown:
            return Color.lanLensSecondaryText
        }
    }

    // MARK: - Accessibility

    private func accessibilityLabel(for profile: DeviceBehaviorProfile) -> String {
        var label = classificationLabel(for: profile.classification)
        if profile.isAlwaysOn {
            label += ", always on"
        }
        return label
    }

    private func classificationLabel(for classification: BehaviorClassification) -> String {
        switch classification {
        case .infrastructure:
            return "Infrastructure device"
        case .server:
            return "Server"
        case .iot:
            return "IoT device"
        case .workstation:
            return "Workstation"
        case .portable:
            return "Portable device"
        case .mobile:
            return "Mobile device"
        case .guest:
            return "Guest device"
        case .unknown:
            return "Unknown device type"
        }
    }
}

// MARK: - Preview

#Preview("All Classifications") {
    let classifications: [BehaviorClassification] = [
        .infrastructure, .server, .iot, .workstation,
        .portable, .mobile, .guest, .unknown
    ]

    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 20) {
        ForEach(classifications, id: \.self) { classification in
            VStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    // Simulated device icon
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.lanLensCard)
                        .frame(width: 48, height: 48)

                    BehaviorBadge(
                        behaviorProfile: DeviceBehaviorProfile(
                            classification: classification,
                            isAlwaysOn: classification == .infrastructure
                                || classification == .server
                                || classification == .iot
                        )
                    )
                    .offset(x: 4, y: 4)
                }

                Text(classification.rawValue)
                    .font(.caption2)
                    .foregroundStyle(Color.lanLensSecondaryText)
            }
        }
    }
    .padding()
    .background(Color.lanLensBackground)
}

#Preview("Nil Profile") {
    VStack {
        Text("No badge when profile is nil:")
            .foregroundStyle(.white)

        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.lanLensCard)
                .frame(width: 48, height: 48)

            BehaviorBadge(behaviorProfile: nil)
                .offset(x: 4, y: 4)
        }
    }
    .padding()
    .background(Color.lanLensBackground)
}
