import SwiftUI
import LanLensCore

struct DeviceListView: View {
    let title: String
    let devices: [Device]
    let showScores: Bool
    let emptyMessage: String
    let onDeviceTap: (Device) -> Void

    init(
        title: String,
        devices: [Device],
        showScores: Bool = true,
        emptyMessage: String = "No devices found",
        onDeviceTap: @escaping (Device) -> Void
    ) {
        self.title = title
        self.devices = devices
        self.showScores = showScores
        self.emptyMessage = emptyMessage
        self.onDeviceTap = onDeviceTap
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.lanLensSecondaryText)

                Text("(\(devices.count))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.lanLensSecondaryText.opacity(0.7))

                Spacer()
            }
            .padding(.horizontal, 12)

            if devices.isEmpty {
                // Empty state
                HStack {
                    Spacer()
                    Text(emptyMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.lanLensSecondaryText.opacity(0.7))
                    Spacer()
                }
                .padding(.vertical, 16)
            } else {
                // Device rows
                VStack(spacing: 6) {
                    ForEach(devices) { device in
                        DeviceRowView(
                            device: device,
                            showScore: showScores,
                            onTap: { onDeviceTap(device) }
                        )
                    }
                }
            }
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            DeviceListView(
                title: "Smart Devices",
                devices: [
                    Device(
                        mac: "AA:BB:CC:DD:EE:FF",
                        ip: "192.168.1.45",
                        hostname: "LivingRoomTV",
                        vendor: "Samsung",
                        firstSeen: Date(),
                        lastSeen: Date(),
                        isOnline: true,
                        smartScore: 85,
                        deviceType: .smartTV
                    ),
                    Device(
                        mac: "11:22:33:44:55:66",
                        ip: "192.168.1.52",
                        hostname: "SonosOne",
                        vendor: "Sonos",
                        firstSeen: Date(),
                        lastSeen: Date(),
                        isOnline: true,
                        smartScore: 95,
                        deviceType: .speaker
                    )
                ],
                onDeviceTap: { _ in }
            )

            DeviceListView(
                title: "Other Devices",
                devices: [],
                showScores: false,
                emptyMessage: "No other devices",
                onDeviceTap: { _ in }
            )
        }
        .padding()
    }
    .background(Color.lanLensBackground)
}
