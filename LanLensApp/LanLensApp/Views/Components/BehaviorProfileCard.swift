import SwiftUI
import LanLensCore

// MARK: - Behavior Profile Card

/// Displays device behavioral profile including classification, uptime, activity patterns,
/// and observation metadata. Follows established card patterns from DeviceDetailView.
struct BehaviorProfileCard: View {
    let behaviorProfile: DeviceBehaviorProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(title: "Behavior Profile", icon: "chart.line.uptrend.xyaxis")

            VStack(alignment: .leading, spacing: 16) {
                // Classification and uptime row
                HStack(alignment: .top, spacing: 16) {
                    ClassificationDisplay(classification: behaviorProfile.classification)

                    Spacer()

                    UptimeIndicator(uptimePercent: behaviorProfile.averageUptimePercent)
                }

                // Behavioral summary
                BehaviorSummaryView(profile: behaviorProfile)

                // Activity pattern section
                if !behaviorProfile.peakHours.isEmpty || behaviorProfile.hasDailyPattern {
                    ActivityPatternSection(
                        peakHours: behaviorProfile.peakHours,
                        hasDailyPattern: behaviorProfile.hasDailyPattern
                    )
                }

                // Observation metadata
                ObservationMetadataView(
                    firstObserved: behaviorProfile.firstObserved,
                    lastObserved: behaviorProfile.lastObserved,
                    observationCount: behaviorProfile.observationCount
                )

                // Consistent services
                if !behaviorProfile.consistentServices.isEmpty {
                    ConsistentServicesView(services: behaviorProfile.consistentServices)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Color.lanLensCard)
        .cornerRadius(10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Behavior profile card")
    }
}

// MARK: - Card Header (Matches DeviceDetailView pattern)

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

// MARK: - Classification Display

private struct ClassificationDisplay: View {
    let classification: BehaviorClassification

    private var icon: String {
        switch classification {
        case .infrastructure: return "network"
        case .server: return "server.rack"
        case .iot: return "sensor"
        case .workstation: return "desktopcomputer"
        case .portable: return "laptopcomputer"
        case .mobile: return "iphone"
        case .guest: return "person.badge.clock"
        case .unknown: return "questionmark.circle"
        }
    }

    private var displayName: String {
        switch classification {
        case .infrastructure: return "Infrastructure"
        case .server: return "Server"
        case .iot: return "IoT Device"
        case .workstation: return "Workstation"
        case .portable: return "Portable"
        case .mobile: return "Mobile"
        case .guest: return "Guest"
        case .unknown: return "Unknown"
        }
    }

    private var iconColor: Color {
        switch classification {
        case .infrastructure, .server: return .lanLensAccent
        case .iot: return .lanLensSuccess
        case .workstation, .portable: return .lanLensWarning
        case .mobile, .guest: return .lanLensSecondaryText
        case .unknown: return .lanLensSecondaryText
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Classification")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.lanLensSecondaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Classification: \(displayName)")
    }
}

// MARK: - Uptime Indicator

private struct UptimeIndicator: View {
    let uptimePercent: Double

    private var uptimeColor: Color {
        if uptimePercent >= 90 {
            return .lanLensSuccess
        } else if uptimePercent >= 50 {
            return .lanLensWarning
        } else {
            return .lanLensDanger
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.lanLensBackground, lineWidth: 4)
                    .frame(width: 48, height: 48)

                // Progress circle
                Circle()
                    .trim(from: 0, to: CGFloat(min(uptimePercent, 100)) / 100)
                    .stroke(uptimeColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(-90))

                // Percentage text
                Text("\(Int(uptimePercent))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }

            Text("Avg. Uptime")
                .font(.system(size: 9))
                .foregroundStyle(Color.lanLensSecondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Average uptime: \(Int(uptimePercent)) percent")
    }
}

// MARK: - Behavior Summary

private struct BehaviorSummaryView: View {
    let profile: DeviceBehaviorProfile

    private var summaryText: String {
        var parts: [String] = []

        if profile.isAlwaysOn {
            parts.append("Always-on device")
        } else if profile.isIntermittent {
            parts.append("Intermittent presence")
        }

        if profile.hasDailyPattern {
            parts.append("daily pattern detected")
        }

        if parts.isEmpty {
            return "Behavioral data being collected"
        }

        return parts.joined(separator: ", ").prefix(1).uppercased() + parts.joined(separator: ", ").dropFirst()
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: profile.isAlwaysOn ? "checkmark.circle.fill" : "info.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(profile.isAlwaysOn ? Color.lanLensSuccess : Color.lanLensSecondaryText)

            Text(summaryText)
                .font(.system(size: 11))
                .foregroundStyle(Color.lanLensSecondaryText)

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Behavior summary: \(summaryText)")
    }
}

// MARK: - Activity Pattern Section

private struct ActivityPatternSection: View {
    let peakHours: [Int]
    let hasDailyPattern: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.lanLensAccent)
                Text("Activity Pattern")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.lanLensSecondaryText)
            }

            if hasDailyPattern {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.lanLensSuccess)
                    Text("Daily pattern detected")
                        .font(.system(size: 11))
                        .foregroundStyle(.white)
                }
            }

            if !peakHours.isEmpty {
                PeakHoursView(hours: peakHours)
            }
        }
        .padding(10)
        .background(Color.lanLensBackground)
        .cornerRadius(8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Activity pattern section")
    }
}

// MARK: - Peak Hours Visualization

private struct PeakHoursView: View {
    let hours: [Int]

    private var formattedHours: String {
        let sortedHours = hours.sorted()
        let formatted = sortedHours.map { hour -> String in
            if hour == 0 { return "12 AM" }
            if hour < 12 { return "\(hour) AM" }
            if hour == 12 { return "12 PM" }
            return "\(hour - 12) PM"
        }
        return formatted.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Peak Hours")
                .font(.system(size: 10))
                .foregroundStyle(Color.lanLensSecondaryText)

            // Simple hour blocks visualization
            HStack(spacing: 2) {
                ForEach(0..<24, id: \.self) { hour in
                    Rectangle()
                        .fill(hours.contains(hour) ? Color.lanLensAccent : Color.lanLensSecondaryText.opacity(0.2))
                        .frame(width: 8, height: hours.contains(hour) ? 16 : 8)
                        .cornerRadius(2)
                }
            }

            Text(formattedHours)
                .font(.system(size: 10))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Peak activity hours: \(formattedHours)")
    }
}

// MARK: - Observation Metadata

private struct ObservationMetadataView: View {
    let firstObserved: Date
    let lastObserved: Date
    let observationCount: Int

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    private var relativeDateFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }

    var body: some View {
        VStack(spacing: 6) {
            MetadataRow(
                label: "First seen",
                value: dateFormatter.string(from: firstObserved)
            )
            MetadataRow(
                label: "Last seen",
                value: relativeDateFormatter.localizedString(for: lastObserved, relativeTo: Date())
            )
            MetadataRow(
                label: "Observations",
                value: "\(observationCount)"
            )
        }
        .accessibilityElement(children: .contain)
    }
}

private struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.lanLensSecondaryText)

            Spacer()

            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Consistent Services

private struct ConsistentServicesView: View {
    let services: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.lanLensSuccess)
                Text("Consistent Services")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.lanLensSecondaryText)
            }

            ServiceTagsFlowLayout(services: services)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Consistent services: \(services.joined(separator: ", "))")
    }
}

private struct ServiceTagsFlowLayout: View {
    let services: [String]

    var body: some View {
        // Simple horizontal scroll for services since FlowLayout is private to DeviceDetailView
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(services, id: \.self) { service in
                    Text(service)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.lanLensSuccess)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.lanLensSuccess.opacity(0.15))
                        .cornerRadius(4)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Always-On Server") {
    BehaviorProfileCard(
        behaviorProfile: DeviceBehaviorProfile(
            classification: .server,
            presenceHistory: [],
            averageUptimePercent: 99.5,
            isAlwaysOn: true,
            isIntermittent: false,
            hasDailyPattern: false,
            peakHours: [],
            consistentServices: ["SSH", "HTTP", "SMB"],
            firstObserved: Date().addingTimeInterval(-86400 * 30),
            lastObserved: Date(),
            observationCount: 720
        )
    )
    .padding()
    .background(Color.lanLensBackground)
}

#Preview("Workstation with Pattern") {
    BehaviorProfileCard(
        behaviorProfile: DeviceBehaviorProfile(
            classification: .workstation,
            presenceHistory: [],
            averageUptimePercent: 45.0,
            isAlwaysOn: false,
            isIntermittent: false,
            hasDailyPattern: true,
            peakHours: [9, 10, 11, 12, 13, 14, 15, 16, 17],
            consistentServices: ["AirPlay", "Screen Sharing"],
            firstObserved: Date().addingTimeInterval(-86400 * 7),
            lastObserved: Date().addingTimeInterval(-3600),
            observationCount: 42
        )
    )
    .padding()
    .background(Color.lanLensBackground)
}

#Preview("Mobile Device") {
    BehaviorProfileCard(
        behaviorProfile: DeviceBehaviorProfile(
            classification: .mobile,
            presenceHistory: [],
            averageUptimePercent: 15.0,
            isAlwaysOn: false,
            isIntermittent: true,
            hasDailyPattern: false,
            peakHours: [19, 20, 21, 22],
            consistentServices: [],
            firstObserved: Date().addingTimeInterval(-86400 * 3),
            lastObserved: Date().addingTimeInterval(-7200),
            observationCount: 8
        )
    )
    .padding()
    .background(Color.lanLensBackground)
}
