import SwiftUI
import LanLensCore

// MARK: - MAC Analysis Card

/// Displays MAC address analysis including OUI vendor, confidence level,
/// age estimation, randomization detection, and virtual machine identification.
struct MACAnalysisCard: View {
    let macAddress: String
    let macAnalysis: MACAnalysisData

    /// Known VM OUI prefixes for VM detection display
    private static let vmOUIs: Set<String> = [
        "00:0C:29", "00:50:56",  // VMware
        "00:1C:42",              // Parallels
        "00:03:FF",              // Microsoft Hyper-V
        "08:00:27",              // VirtualBox
        "52:54:00",              // QEMU/KVM
        "00:16:3E",              // Xen
    ]

    private var isVirtualMachine: Bool {
        Self.vmOUIs.contains(macAnalysis.oui)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(title: "MAC Analysis", icon: "number.circle")

            VStack(alignment: .leading, spacing: 12) {
                // MAC address display with vendor
                MACAddressDisplay(
                    macAddress: macAddress,
                    vendor: macAnalysis.vendor,
                    isVirtualMachine: isVirtualMachine
                )

                // Confidence and age badges row
                BadgesRow(
                    vendorConfidence: macAnalysis.vendorConfidence,
                    ageEstimate: macAnalysis.ageEstimate
                )

                // Randomized MAC warning (if applicable)
                if macAnalysis.isRandomized {
                    RandomizedMACWarning()
                }

                // Vendor categories (if any)
                if !macAnalysis.vendorCategories.isEmpty {
                    VendorCategoriesView(categories: macAnalysis.vendorCategories)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Color.lanLensCard)
        .cornerRadius(10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("MAC analysis card")
    }
}

// MARK: - Card Header

private struct CardHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.lanLensAccent)

            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.lanLensSecondaryText)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}

// MARK: - MAC Address Display

private struct MACAddressDisplay: View {
    let macAddress: String
    let vendor: String?
    let isVirtualMachine: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // MAC address (monospaced, selectable)
            Text(macAddress.uppercased())
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .accessibilityLabel("MAC address: \(macAddress)")

            // Vendor name with optional VM badge
            HStack(spacing: 8) {
                if let vendor = vendor, !vendor.isEmpty {
                    Text(vendor)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.lanLensSecondaryText)
                        .lineLimit(1)
                } else {
                    Text("Unknown Vendor")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.lanLensSecondaryText.opacity(0.7))
                        .italic()
                }

                if isVirtualMachine {
                    VMBadge()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - VM Badge

private struct VMBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 9))
            Text("VM")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(Color.lanLensAccent)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.lanLensAccent.opacity(0.15))
        .cornerRadius(4)
        .accessibilityLabel("Virtual Machine")
    }
}

// MARK: - Badges Row

private struct BadgesRow: View {
    let vendorConfidence: VendorConfidence
    let ageEstimate: OUIAgeEstimate?

    var body: some View {
        HStack(spacing: 8) {
            ConfidenceBadge(confidence: vendorConfidence)

            if let age = ageEstimate, age != .unknown {
                AgeBadge(ageEstimate: age)
            }

            Spacer()
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Confidence Badge

private struct ConfidenceBadge: View {
    let confidence: VendorConfidence

    private var badgeColor: Color {
        switch confidence {
        case .high:
            return Color.lanLensSuccess
        case .medium:
            return Color.lanLensWarning
        case .low:
            return Color.lanLensDanger
        case .randomized:
            return Color.lanLensRandomized
        case .unknown:
            return Color.lanLensSecondaryText
        }
    }

    private var badgeText: String {
        switch confidence {
        case .high:
            return "High Confidence"
        case .medium:
            return "Medium Confidence"
        case .low:
            return "Low Confidence"
        case .randomized:
            return "Randomized"
        case .unknown:
            return "Unknown"
        }
    }

    var body: some View {
        Text(badgeText)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeColor.opacity(0.15))
            .cornerRadius(4)
            .accessibilityLabel("Vendor confidence: \(badgeText)")
    }
}

// MARK: - Age Badge

private struct AgeBadge: View {
    let ageEstimate: OUIAgeEstimate

    private var badgeColor: Color {
        switch ageEstimate {
        case .legacy:
            return Color.lanLensDanger
        case .established:
            return Color.lanLensWarning
        case .modern:
            return Color.lanLensSuccess
        case .recent:
            return Color.lanLensAccent
        case .unknown:
            return Color.lanLensSecondaryText
        }
    }

    private var badgeText: String {
        switch ageEstimate {
        case .legacy:
            return "Legacy"
        case .established:
            return "Established"
        case .modern:
            return "Modern"
        case .recent:
            return "Recent"
        case .unknown:
            return "Unknown"
        }
    }

    private var ageDescription: String {
        switch ageEstimate {
        case .legacy:
            return "Pre-2010"
        case .established:
            return "2010-2015"
        case .modern:
            return "2015-2020"
        case .recent:
            return "2020+"
        case .unknown:
            return ""
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(badgeText)
                .font(.system(size: 9, weight: .semibold))
            if !ageDescription.isEmpty {
                Text("(\(ageDescription))")
                    .font(.system(size: 8))
                    .opacity(0.8)
            }
        }
        .foregroundStyle(badgeColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(badgeColor.opacity(0.15))
        .cornerRadius(4)
        .accessibilityLabel("OUI age estimate: \(badgeText), \(ageDescription)")
    }
}

// MARK: - Randomized MAC Warning

private struct RandomizedMACWarning: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.lanLensRandomized)

            VStack(alignment: .leading, spacing: 2) {
                Text("Randomized MAC Address")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.lanLensRandomized)

                Text("This device uses a privacy-preserving randomized MAC address. The vendor cannot be reliably identified.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.lanLensSecondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.lanLensRandomized.opacity(0.1))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning: This device uses a randomized MAC address for privacy. Vendor identification is not reliable.")
    }
}

// MARK: - Vendor Categories View

private struct VendorCategoriesView: View {
    let categories: [DeviceType]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Vendor Device Types")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.lanLensSecondaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(categories, id: \.self) { deviceType in
                        DeviceCategoryPill(deviceType: deviceType)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Vendor typically makes: \(categories.map { $0.rawValue }.joined(separator: ", "))")
    }
}

private struct DeviceCategoryPill: View {
    let deviceType: DeviceType

    private var displayName: String {
        switch deviceType {
        case .smartTV: return "Smart TV"
        case .speaker: return "Speaker"
        case .camera: return "Camera"
        case .thermostat: return "Thermostat"
        case .light: return "Light"
        case .plug: return "Plug"
        case .hub: return "Hub"
        case .printer: return "Printer"
        case .nas: return "NAS"
        case .computer: return "Computer"
        case .phone: return "Phone"
        case .tablet: return "Tablet"
        case .router: return "Router"
        case .accessPoint: return "Access Point"
        case .appliance: return "Appliance"
        case .unknown: return "Unknown"
        }
    }

    var body: some View {
        Text(displayName)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(Color.lanLensAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.lanLensAccent.opacity(0.15))
            .cornerRadius(4)
    }
}

// MARK: - Preview

#Preview("High Confidence Vendor") {
    MACAnalysisCard(
        macAddress: "AA:BB:CC:DD:EE:FF",
        macAnalysis: MACAnalysisData(
            oui: "AA:BB:CC",
            vendor: "Apple, Inc.",
            isLocallyAdministered: false,
            isRandomized: false,
            ageEstimate: .established,
            vendorConfidence: .high,
            vendorCategories: [.phone, .tablet, .computer, .smartTV],
            vendorSpecialization: nil
        )
    )
    .padding()
    .background(Color.lanLensBackground)
}

#Preview("Randomized MAC") {
    MACAnalysisCard(
        macAddress: "DA:A1:19:FF:AA:BB",
        macAnalysis: MACAnalysisData(
            oui: "DA:A1:19",
            vendor: nil,
            isLocallyAdministered: true,
            isRandomized: true,
            ageEstimate: nil,
            vendorConfidence: .randomized,
            vendorCategories: [],
            vendorSpecialization: nil
        )
    )
    .padding()
    .background(Color.lanLensBackground)
}

#Preview("Virtual Machine") {
    MACAnalysisCard(
        macAddress: "00:0C:29:12:34:56",
        macAnalysis: MACAnalysisData(
            oui: "00:0C:29",
            vendor: "VMware, Inc.",
            isLocallyAdministered: false,
            isRandomized: false,
            ageEstimate: .established,
            vendorConfidence: .medium,
            vendorCategories: [.computer],
            vendorSpecialization: nil
        )
    )
    .padding()
    .background(Color.lanLensBackground)
}

#Preview("Legacy Device") {
    MACAnalysisCard(
        macAddress: "00:60:97:AA:BB:CC",
        macAnalysis: MACAnalysisData(
            oui: "00:60:97",
            vendor: "3Com Corporation",
            isLocallyAdministered: false,
            isRandomized: false,
            ageEstimate: .legacy,
            vendorConfidence: .low,
            vendorCategories: [.router],
            vendorSpecialization: nil
        )
    )
    .padding()
    .background(Color.lanLensBackground)
}

#Preview("IoT Device - Recent") {
    MACAnalysisCard(
        macAddress: "D8:F1:5B:AA:BB:CC",
        macAnalysis: MACAnalysisData(
            oui: "D8:F1:5B",
            vendor: "Wyze Labs Inc",
            isLocallyAdministered: false,
            isRandomized: false,
            ageEstimate: .recent,
            vendorConfidence: .medium,
            vendorCategories: [.camera, .plug, .light],
            vendorSpecialization: .camera
        )
    )
    .padding()
    .background(Color.lanLensBackground)
}

#Preview("Unknown Vendor") {
    MACAnalysisCard(
        macAddress: "12:34:56:78:9A:BC",
        macAnalysis: MACAnalysisData(
            oui: "12:34:56",
            vendor: nil,
            isLocallyAdministered: false,
            isRandomized: false,
            ageEstimate: nil,
            vendorConfidence: .unknown,
            vendorCategories: [],
            vendorSpecialization: nil
        )
    )
    .padding()
    .background(Color.lanLensBackground)
}
