import SwiftUI
import LanLensCore

// MARK: - Security Posture Card

/// Displays security assessment data for a device including risk level,
/// risk factors, and security indicators (encryption, authentication, web interface).
struct SecurityPostureCard: View {
    let securityPosture: SecurityPostureData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(title: "Security Posture", icon: "shield.lefthalf.filled")

            VStack(alignment: .leading, spacing: 12) {
                // Risk level header with color-coded shield
                RiskLevelHeader(
                    riskLevel: securityPosture.riskLevel,
                    riskScore: securityPosture.riskScore
                )

                // Risk factors list (if any)
                if !securityPosture.riskFactors.isEmpty {
                    RiskFactorsList(riskFactors: securityPosture.riskFactors)
                }

                // Risky ports section (if any)
                if !securityPosture.riskyPorts.isEmpty {
                    RiskyPortsSection(riskyPorts: securityPosture.riskyPorts)
                }

                // Security indicators row
                SecurityIndicatorsRow(
                    usesEncryption: securityPosture.usesEncryption,
                    requiresAuthentication: securityPosture.requiresAuthentication,
                    hasWebInterface: securityPosture.hasWebInterface
                )

                // Firmware warning (if outdated)
                if securityPosture.firmwareOutdated == true {
                    FirmwareWarningRow()
                }

                // Assessment date footer
                AssessmentDateFooter(date: securityPosture.assessmentDate)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Color.lanLensCard)
        .cornerRadius(10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Security posture card")
    }
}

// MARK: - Card Header (matches DeviceDetailView pattern)

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

// MARK: - Risk Level Header

private struct RiskLevelHeader: View {
    let riskLevel: RiskLevel
    let riskScore: Int

    private var riskColor: Color {
        switch riskLevel {
        case .critical:
            return Color.lanLensDanger
        case .high:
            return Color.lanLensDanger.opacity(0.85)
        case .medium:
            return Color.lanLensWarning
        case .low:
            return Color.lanLensSuccess
        case .unknown:
            return Color.lanLensSecondaryText
        }
    }

    private var riskLevelText: String {
        switch riskLevel {
        case .critical: return "Critical Risk"
        case .high: return "High Risk"
        case .medium: return "Medium Risk"
        case .low: return "Low Risk"
        case .unknown: return "Unknown"
        }
    }

    private var shieldIcon: String {
        switch riskLevel {
        case .critical, .high:
            return "shield.lefthalf.filled.trianglebadge.exclamationmark"
        case .medium:
            return "shield.lefthalf.filled.badge.checkmark"
        case .low:
            return "shield.lefthalf.filled.badge.checkmark"
        case .unknown:
            return "shield.lefthalf.filled"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Large color-coded shield
            ZStack {
                Circle()
                    .fill(riskColor.opacity(0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: shieldIcon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(riskColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(riskLevelText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(riskColor)

                Text("Risk Score: \(riskScore)/100")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.lanLensSecondaryText)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(riskLevelText), risk score \(riskScore) out of 100")
    }
}

// MARK: - Risk Factors List

private struct RiskFactorsList: View {
    let riskFactors: [RiskFactor]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Risk Factors")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.lanLensSecondaryText)

            VStack(spacing: 6) {
                ForEach(Array(riskFactors.enumerated()), id: \.offset) { _, factor in
                    RiskFactorRow(factor: factor)
                }
            }
        }
    }
}

private struct RiskFactorRow: View {
    let factor: RiskFactor

    private var severityColor: Color {
        switch factor.severity {
        case .critical:
            return Color.lanLensDanger
        case .high:
            return Color.lanLensDanger.opacity(0.85)
        case .medium:
            return Color.lanLensWarning
        case .low:
            return Color.lanLensSuccess
        case .unknown:
            return Color.lanLensSecondaryText
        }
    }

    private var severityText: String {
        factor.severity.rawValue.capitalized
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Severity badge
            Text(severityText)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(severityColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(severityColor.opacity(0.15))
                .cornerRadius(4)
                .frame(width: 56, alignment: .center)

            // Description
            VStack(alignment: .leading, spacing: 2) {
                Text(factor.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let remediation = factor.remediation {
                    Text(remediation)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.lanLensSecondaryText)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.lanLensBackground.opacity(0.5))
        .cornerRadius(6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(severityText) risk: \(factor.description)")
    }
}

// MARK: - Risky Ports Section

private struct RiskyPortsSection: View {
    let riskyPorts: [Int]

    /// Port severity classification with service names
    struct PortInfo {
        let port: Int
        let serviceName: String
        let severity: PortSeverity
    }

    enum PortSeverity {
        case critical
        case high
        case medium
        case low

        var color: Color {
            switch self {
            case .critical:
                return Color.lanLensDanger
            case .high:
                return Color.lanLensDanger.opacity(0.85)
            case .medium:
                return Color.lanLensWarning
            case .low:
                return Color.lanLensSuccess
            }
        }
    }

    /// Maps port numbers to severity and service names
    private static let portDatabase: [Int: (String, PortSeverity)] = [
        // Critical severity
        23: ("Telnet", .critical),
        1433: ("MSSQL", .critical),
        3306: ("MySQL", .critical),
        3389: ("RDP", .critical),
        // High severity
        21: ("FTP", .high),
        139: ("NetBIOS", .high),
        445: ("SMB", .high),
        554: ("RTSP", .high),
        5900: ("VNC", .high),
        // Medium severity
        80: ("HTTP", .medium),
        8080: ("HTTP-Alt", .medium),
        // Low severity
        8443: ("HTTPS-Alt", .low)
    ]

    private var portInfoList: [PortInfo] {
        riskyPorts.map { port in
            if let (serviceName, severity) = Self.portDatabase[port] {
                return PortInfo(port: port, serviceName: serviceName, severity: severity)
            } else {
                // Unknown risky port defaults to medium severity
                return PortInfo(port: port, serviceName: "Unknown", severity: .medium)
            }
        }
        .sorted { lhs, rhs in
            // Sort by severity (critical first), then by port number
            let severityOrder: [PortSeverity] = [.critical, .high, .medium, .low]
            let lhsIndex = severityOrder.firstIndex(of: lhs.severity) ?? 3
            let rhsIndex = severityOrder.firstIndex(of: rhs.severity) ?? 3
            if lhsIndex != rhsIndex {
                return lhsIndex < rhsIndex
            }
            return lhs.port < rhs.port
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Risky Open Ports")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.lanLensSecondaryText)

            FlowLayout(spacing: 6) {
                ForEach(portInfoList, id: \.port) { info in
                    RiskyPortPill(portInfo: info)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Risky open ports section with \(riskyPorts.count) ports")
    }
}

private struct RiskyPortPill: View {
    let portInfo: RiskyPortsSection.PortInfo

    var body: some View {
        HStack(spacing: 4) {
            Text("\(portInfo.port)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
            Text(portInfo.serviceName)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(portInfo.severity.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(portInfo.severity.color.opacity(0.15))
        .cornerRadius(6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Port \(portInfo.port), \(portInfo.serviceName), \(severityLabel)")
    }

    private var severityLabel: String {
        switch portInfo.severity {
        case .critical: return "critical severity"
        case .high: return "high severity"
        case .medium: return "medium severity"
        case .low: return "low severity"
        }
    }
}

// MARK: - Flow Layout for Risky Ports

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

// MARK: - Security Indicators Row

private struct SecurityIndicatorsRow: View {
    let usesEncryption: Bool
    let requiresAuthentication: Bool
    let hasWebInterface: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Security Indicators")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.lanLensSecondaryText)

            HStack(spacing: 12) {
                SecurityIndicatorPill(
                    icon: usesEncryption ? "lock.fill" : "lock.open.fill",
                    label: usesEncryption ? "Encrypted" : "Unencrypted",
                    isPositive: usesEncryption
                )

                SecurityIndicatorPill(
                    icon: requiresAuthentication ? "person.badge.key.fill" : "person.badge.key",
                    label: requiresAuthentication ? "Auth Required" : "No Auth",
                    isPositive: requiresAuthentication
                )

                SecurityIndicatorPill(
                    icon: "globe",
                    label: hasWebInterface ? "Web UI" : "No Web UI",
                    isPositive: !hasWebInterface
                )
            }
        }
    }
}

private struct SecurityIndicatorPill: View {
    let icon: String
    let label: String
    let isPositive: Bool

    private var indicatorColor: Color {
        isPositive ? Color.lanLensSuccess : Color.lanLensWarning
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(label)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(indicatorColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(indicatorColor.opacity(0.15))
        .cornerRadius(6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(isPositive ? "secure" : "may need attention")")
    }
}

// MARK: - Firmware Warning Row

private struct FirmwareWarningRow: View {
    var body: some View {
        HStack(spacing: 12) {
            // Warning icon in circle
            ZStack {
                Circle()
                    .fill(Color.lanLensWarning.opacity(0.15))
                    .frame(width: 32, height: 32)

                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.lanLensWarning)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Firmware May Be Outdated")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.lanLensWarning)

                Text("Check manufacturer for updates")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.lanLensSecondaryText)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.lanLensSecondaryText.opacity(0.6))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.lanLensWarning.opacity(0.08))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Firmware may be outdated. Check manufacturer for updates.")
        .accessibilityHint("Tap to learn more about firmware updates")
    }
}

// MARK: - Assessment Date Footer

private struct AssessmentDateFooter: View {
    let date: Date

    private var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        HStack {
            Spacer()
            Text("Assessed \(formattedDate)")
                .font(.system(size: 10))
                .foregroundStyle(Color.lanLensSecondaryText.opacity(0.7))
        }
        .accessibilityLabel("Security assessment performed \(formattedDate)")
    }
}

// MARK: - Preview

#Preview("Low Risk") {
    SecurityPostureCard(
        securityPosture: SecurityPostureData(
            riskLevel: .low,
            riskScore: 15,
            riskFactors: [],
            riskyPorts: [],
            hasWebInterface: false,
            requiresAuthentication: true,
            usesEncryption: true,
            firmwareOutdated: false,
            assessmentDate: Date()
        )
    )
    .padding()
    .background(Color.lanLensBackground)
}

#Preview("Medium Risk") {
    SecurityPostureCard(
        securityPosture: SecurityPostureData(
            riskLevel: .medium,
            riskScore: 45,
            riskFactors: [
                RiskFactor(
                    category: "Network",
                    description: "Device exposes management interface on port 80",
                    severity: .medium,
                    scoreContribution: 20,
                    remediation: "Enable HTTPS on port 443"
                ),
                RiskFactor(
                    category: "Authentication",
                    description: "Default credentials may be in use",
                    severity: .medium,
                    scoreContribution: 25,
                    remediation: "Change default password"
                )
            ],
            riskyPorts: [80, 23],
            hasWebInterface: true,
            requiresAuthentication: true,
            usesEncryption: false,
            firmwareOutdated: nil,
            assessmentDate: Date().addingTimeInterval(-3600)
        )
    )
    .padding()
    .background(Color.lanLensBackground)
}

#Preview("High Risk") {
    SecurityPostureCard(
        securityPosture: SecurityPostureData(
            riskLevel: .high,
            riskScore: 72,
            riskFactors: [
                RiskFactor(
                    category: "Telnet",
                    description: "Telnet port 23 is open - unencrypted access",
                    severity: .high,
                    scoreContribution: 30,
                    remediation: "Disable Telnet, use SSH"
                ),
                RiskFactor(
                    category: "Authentication",
                    description: "No authentication required for web interface",
                    severity: .high,
                    scoreContribution: 25,
                    remediation: "Enable authentication"
                ),
                RiskFactor(
                    category: "Firmware",
                    description: "Firmware appears outdated",
                    severity: .medium,
                    scoreContribution: 17,
                    remediation: "Update firmware"
                )
            ],
            riskyPorts: [23, 80, 21],
            hasWebInterface: true,
            requiresAuthentication: false,
            usesEncryption: false,
            firmwareOutdated: true,
            assessmentDate: Date().addingTimeInterval(-86400)
        )
    )
    .padding()
    .background(Color.lanLensBackground)
}

#Preview("Critical Risk") {
    SecurityPostureCard(
        securityPosture: SecurityPostureData(
            riskLevel: .critical,
            riskScore: 92,
            riskFactors: [
                RiskFactor(
                    category: "Exposure",
                    description: "Device responds to unauthenticated RTSP streams",
                    severity: .critical,
                    scoreContribution: 40,
                    remediation: "Enable RTSP authentication"
                ),
                RiskFactor(
                    category: "Telnet",
                    description: "Telnet with default credentials detected",
                    severity: .critical,
                    scoreContribution: 35,
                    remediation: "Disable Telnet immediately"
                ),
                RiskFactor(
                    category: "Web",
                    description: "Admin panel accessible without login",
                    severity: .high,
                    scoreContribution: 17,
                    remediation: "Enable admin authentication"
                )
            ],
            riskyPorts: [23, 554, 80, 8080],
            hasWebInterface: true,
            requiresAuthentication: false,
            usesEncryption: false,
            firmwareOutdated: true,
            assessmentDate: Date().addingTimeInterval(-7200)
        )
    )
    .padding()
    .background(Color.lanLensBackground)
}
