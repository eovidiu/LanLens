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
