import SwiftUI

struct StatusIndicator: View {
    let isAPIRunning: Bool
    let isScanning: Bool

    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 6) {
            if isScanning {
                Circle()
                    .fill(Color.lanLensAccent)
                    .frame(width: 8, height: 8)
                    .scaleEffect(isPulsing ? 1.2 : 0.8)
                    .opacity(isPulsing ? 1 : 0.6)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true),
                        value: isPulsing
                    )
                    .onAppear { isPulsing = true }
                    .onDisappear { isPulsing = false }

                Text("Scanning...")
                    .font(.caption)
                    .foregroundStyle(Color.lanLensSecondaryText)
            } else if isAPIRunning {
                Circle()
                    .fill(Color.lanLensSuccess)
                    .frame(width: 8, height: 8)

                Text("API: Running")
                    .font(.caption)
                    .foregroundStyle(Color.lanLensSecondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: 20) {
        StatusIndicator(isAPIRunning: false, isScanning: false)
        StatusIndicator(isAPIRunning: true, isScanning: false)
        StatusIndicator(isAPIRunning: true, isScanning: true)
        StatusIndicator(isAPIRunning: false, isScanning: true)
    }
    .padding()
    .background(Color.lanLensBackground)
}
