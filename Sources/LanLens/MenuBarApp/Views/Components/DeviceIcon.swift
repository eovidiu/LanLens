import SwiftUI
import LanLensCore

struct DeviceIcon: View {
    let deviceType: DeviceType
    var size: CGFloat = 24
    var color: Color = .lanLensAccent

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size * 0.7))
            .frame(width: size, height: size)
            .foregroundStyle(color)
            .accessibilityLabel(deviceType.rawValue)
    }

    private var symbolName: String {
        switch deviceType {
        case .smartTV:
            return "tv.fill"
        case .speaker:
            return "hifispeaker.fill"
        case .camera:
            return "video.fill"
        case .thermostat:
            return "thermometer.medium"
        case .light:
            return "lightbulb.fill"
        case .plug:
            return "powerplug.fill"
        case .hub:
            return "homekit"
        case .printer:
            return "printer.fill"
        case .nas:
            return "externaldrive.fill"
        case .computer:
            return "desktopcomputer"
        case .phone:
            return "iphone"
        case .tablet:
            return "ipad"
        case .router:
            return "wifi.router.fill"
        case .accessPoint:
            return "wifi"
        case .appliance:
            return "house.fill"
        case .unknown:
            return "questionmark.circle"
        }
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 16) {
        ForEach(DeviceType.allCases, id: \.self) { type in
            VStack {
                DeviceIcon(deviceType: type)
                Text(type.rawValue)
                    .font(.caption2)
            }
        }
    }
    .padding()
    .background(Color.lanLensBackground)
}
