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
            HStack(spacing: 12) {
                DeviceIcon(deviceType: device.deviceType)

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
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.lanLensCard)
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
        .accessibilityLabel("\(displayName), \(device.ip)")
        .accessibilityHint("Double-tap to view details")
    }

    private var displayName: String {
        if let label = device.userLabel, !label.isEmpty {
            return label
        }
        if let hostname = device.hostname, !hostname.isEmpty {
            return hostname.replacingOccurrences(of: ".local", with: "")
        }
        if let vendor = device.vendor, !vendor.isEmpty {
            // Use vendor + last 4 chars of MAC for uniqueness
            let macSuffix = String(device.mac.suffix(5)).replacingOccurrences(of: ":", with: "")
            return "\(vendor) (\(macSuffix))"
        }
        if device.deviceType != .unknown {
            return device.deviceType.rawValue.capitalized
        }
        // Last resort: "Device" + last 4 chars of MAC
        let macSuffix = String(device.mac.suffix(5)).replacingOccurrences(of: ":", with: "")
        return "Device (\(macSuffix))"
    }
}

#Preview {
    VStack(spacing: 8) {
        DeviceRowView(
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
            ),
            onTap: {}
        )

        DeviceRowView(
            device: Device(
                mac: "11:22:33:44:55:66",
                ip: "192.168.1.10",
                vendor: "Apple",
                firstSeen: Date(),
                lastSeen: Date(),
                isOnline: true,
                smartScore: 0,
                deviceType: .computer
            ),
            showScore: false,
            onTap: {}
        )
    }
    .padding()
    .background(Color.lanLensBackground)
}
