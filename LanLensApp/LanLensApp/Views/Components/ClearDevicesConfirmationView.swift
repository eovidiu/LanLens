import SwiftUI

/// A confirmation view for clearing all discovered devices.
/// Designed to work as a popover in menu bar apps (not a sheet, which can dismiss the entire window).
/// Follows macOS HIG for destructive action confirmation dialogs.
struct ClearDevicesConfirmationView: View {
    let deviceCount: Int
    let onConfirm: (Bool) -> Void
    var onCancel: (() -> Void)?

    @State private var preserveLabels = true

    var body: some View {
        VStack(spacing: 16) {
            // Warning icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.lanLensWarning)
                .padding(.top, 4)

            // Title
            Text("Clear All Devices?")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            // Description
            Text("This will remove all \(deviceCount) discovered \(deviceCount == 1 ? "device" : "devices") from LanLens. You can scan again to rediscover devices on your network.")
                .font(.system(size: 12))
                .foregroundStyle(Color.lanLensSecondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

            // Buttons
            HStack(spacing: 12) {
                // Cancel button
                Button {
                    onCancel?()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])

                // Clear button (destructive)
                Button {
                    onConfirm(preserveLabels)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                        Text("Clear Data")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.lanLensDanger)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 280)
        .background(Color.lanLensCard)
    }
}

#Preview {
    ClearDevicesConfirmationView(
        deviceCount: 15,
        onConfirm: { preserveLabels in
            print("Clear confirmed, preserve labels: \(preserveLabels)")
        },
        onCancel: {
            print("Cancelled")
        }
    )
}
