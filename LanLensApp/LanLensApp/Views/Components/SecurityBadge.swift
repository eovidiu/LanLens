import SwiftUI
import LanLensCore

/// A security indicator badge that displays risk level for network devices.
/// Only visible for medium, high, and critical risk levels to avoid visual clutter.
struct SecurityBadge: View {
    let securityPosture: SecurityPostureData?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        if let posture = securityPosture, shouldShow(posture.riskLevel) {
            Image(systemName: "shield.fill")
                .font(.system(size: 14))
                .foregroundStyle(color(for: posture.riskLevel))
                .scaleEffect(isPulsing && posture.riskLevel == .critical ? 1.1 : 1.0)
                .opacity(isPulsing && posture.riskLevel == .critical ? 0.8 : 1.0)
                .animation(pulseAnimation(for: posture.riskLevel), value: isPulsing)
                .onAppear {
                    if posture.riskLevel == .critical && !reduceMotion {
                        isPulsing = true
                    }
                }
                .onDisappear {
                    isPulsing = false
                }
                .tooltip(tooltipText(for: posture))
                .accessibilityLabel(accessibilityLabel(for: posture))
                .accessibilityHint("Security risk indicator")
        }
    }

    // MARK: - Private Methods

    /// Generates tooltip text based on risk level and score.
    private func tooltipText(for posture: SecurityPostureData) -> String {
        let riskLabel: String
        let secondLine: String
        let issueCount = posture.riskFactors.count

        switch posture.riskLevel {
        case .critical:
            riskLabel = "Critical Risk"
            secondLine = issueCount == 1
                ? "1 security issue found"
                : "\(issueCount) security issues found"
        case .high:
            riskLabel = "High Risk"
            secondLine = "Review security settings"
        case .medium:
            riskLabel = "Medium Risk"
            secondLine = "Some improvements possible"
        case .low:
            riskLabel = "Low Risk"
            secondLine = "Device appears secure"
        case .unknown:
            riskLabel = "Unknown Risk"
            secondLine = "Security status unavailable"
        }

        return "\(riskLabel) (\(posture.riskScore)/100)\n\(secondLine)"
    }

    /// Determines if the badge should be visible for the given risk level.
    /// Low and unknown risk levels are hidden to reduce visual noise.
    private func shouldShow(_ riskLevel: RiskLevel) -> Bool {
        switch riskLevel {
        case .medium, .high, .critical:
            return true
        case .low, .unknown:
            return false
        }
    }

    /// Returns the appropriate color for each risk level.
    private func color(for riskLevel: RiskLevel) -> Color {
        switch riskLevel {
        case .critical:
            return .lanLensDanger
        case .high:
            return .lanLensWarning
        case .medium:
            // Blend between warning (orange) and success (green) for medium risk
            return Color(red: 0xDD/255, green: 0xC0/255, blue: 0x30/255)
        case .low, .unknown:
            return .clear
        }
    }

    /// Returns the appropriate animation for the risk level, respecting accessibility settings.
    private func pulseAnimation(for riskLevel: RiskLevel) -> Animation? {
        guard riskLevel == .critical && !reduceMotion else {
            return nil
        }
        return .easeInOut(duration: 0.8)
            .repeatForever(autoreverses: true)
    }

    /// Generates an accessibility label describing the security status.
    private func accessibilityLabel(for posture: SecurityPostureData) -> String {
        let levelDescription: String
        switch posture.riskLevel {
        case .critical:
            levelDescription = "Critical security risk"
        case .high:
            levelDescription = "High security risk"
        case .medium:
            levelDescription = "Medium security risk"
        case .low:
            levelDescription = "Low security risk"
        case .unknown:
            levelDescription = "Unknown security status"
        }

        if posture.riskScore > 0 {
            return "\(levelDescription), risk score \(posture.riskScore) out of 100"
        }
        return levelDescription
    }
}

#Preview {
    VStack(spacing: 16) {
        // Preview all risk levels
        HStack(spacing: 20) {
            VStack {
                SecurityBadge(securityPosture: SecurityPostureData(
                    riskLevel: .critical,
                    riskScore: 90
                ))
                Text("Critical")
                    .font(.caption)
                    .foregroundStyle(Color.lanLensSecondaryText)
            }

            VStack {
                SecurityBadge(securityPosture: SecurityPostureData(
                    riskLevel: .high,
                    riskScore: 70
                ))
                Text("High")
                    .font(.caption)
                    .foregroundStyle(Color.lanLensSecondaryText)
            }

            VStack {
                SecurityBadge(securityPosture: SecurityPostureData(
                    riskLevel: .medium,
                    riskScore: 45
                ))
                Text("Medium")
                    .font(.caption)
                    .foregroundStyle(Color.lanLensSecondaryText)
            }

            VStack {
                SecurityBadge(securityPosture: SecurityPostureData(
                    riskLevel: .low,
                    riskScore: 15
                ))
                Text("Low (hidden)")
                    .font(.caption)
                    .foregroundStyle(Color.lanLensSecondaryText)
            }

            VStack {
                SecurityBadge(securityPosture: nil)
                Text("nil (hidden)")
                    .font(.caption)
                    .foregroundStyle(Color.lanLensSecondaryText)
            }
        }

        Divider()

        // Preview in context (simulating DeviceRowView placement)
        HStack(spacing: 12) {
            Image(systemName: "tv.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.lanLensAccent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Living Room TV")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)

                Text("192.168.1.45 • Samsung")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.lanLensSecondaryText)
            }

            Spacer()

            SecurityBadge(securityPosture: SecurityPostureData(
                riskLevel: .high,
                riskScore: 65
            ))

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { index in
                        Circle()
                            .fill(index < 4 ? Color.lanLensAccent : Color.gray.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
                Text("85")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.lanLensSecondaryText)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.lanLensCard)
        )
    }
    .padding()
    .background(Color.lanLensBackground)
}
