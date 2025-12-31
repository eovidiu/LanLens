import SwiftUI
import LanLensCore

// MARK: - mDNS TXT Card

/// Displays parsed mDNS TXT record data for AirPlay, GoogleCast, HomeKit, and RAOP services.
/// Renders collapsible sections per protocol with features displayed as colored pills.
struct MDNSTXTCard: View {
    let mdnsTXT: MDNSTXTData
    
    /// Track which protocol sections are expanded
    @State private var expandedSections: Set<ProtocolType> = []
    
    /// Protocol types for section management
    private enum ProtocolType: Hashable {
        case airplay
        case googleCast
        case homeKit
        case raop
    }
    
    /// Only render if there's actual data to display
    var hasContent: Bool {
        mdnsTXT.airplay != nil ||
        mdnsTXT.googleCast != nil ||
        mdnsTXT.homeKit != nil ||
        mdnsTXT.raop != nil
    }
    
    /// Determine which protocol should be expanded by default (first one with data)
    private var defaultExpandedSection: ProtocolType? {
        if mdnsTXT.airplay != nil { return .airplay }
        if mdnsTXT.googleCast != nil { return .googleCast }
        if mdnsTXT.homeKit != nil { return .homeKit }
        if mdnsTXT.raop != nil { return .raop }
        return nil
    }
    
    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "Discovery Protocols", icon: "antenna.radiowaves.left.and.right")
                
                VStack(alignment: .leading, spacing: 8) {
                    // AirPlay section
                    if let airplay = mdnsTXT.airplay {
                        AirPlaySection(
                            airplay: airplay,
                            isExpanded: expandedSections.contains(.airplay),
                            onToggle: { toggleSection(.airplay) }
                        )
                    }
                    
                    // GoogleCast section
                    if let googleCast = mdnsTXT.googleCast {
                        GoogleCastSection(
                            googleCast: googleCast,
                            isExpanded: expandedSections.contains(.googleCast),
                            onToggle: { toggleSection(.googleCast) }
                        )
                    }
                    
                    // HomeKit section
                    if let homeKit = mdnsTXT.homeKit {
                        HomeKitSection(
                            homeKit: homeKit,
                            isExpanded: expandedSections.contains(.homeKit),
                            onToggle: { toggleSection(.homeKit) }
                        )
                    }
                    
                    // RAOP section
                    if let raop = mdnsTXT.raop {
                        RAOPSection(
                            raop: raop,
                            isExpanded: expandedSections.contains(.raop),
                            onToggle: { toggleSection(.raop) }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .background(Color.lanLensCard)
            .cornerRadius(10)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Discovery protocols card")
            .onAppear {
                // Expand the first section with data by default
                if let defaultSection = defaultExpandedSection {
                    expandedSections.insert(defaultSection)
                }
            }
        }
    }
    
    private func toggleSection(_ section: ProtocolType) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedSections.contains(section) {
                expandedSections.remove(section)
            } else {
                expandedSections.insert(section)
            }
        }
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

// MARK: - Protocol Section Header

private struct ProtocolSectionHeader: View {
    let title: String
    let icon: String
    let iconColor: Color
    let isExpanded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(iconColor)
                
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.lanLensSecondaryText)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(Color.lanLensBackground.opacity(0.5))
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) section")
        .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand")
    }
}

// MARK: - AirPlay Section

private struct AirPlaySection: View {
    let airplay: AirPlayTXTData
    let isExpanded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProtocolSectionHeader(
                title: "AirPlay",
                icon: "airplayaudio",
                iconColor: Color.lanLensAccent,
                isExpanded: isExpanded,
                onToggle: onToggle
            )
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    // Key-value rows
                    if let model = airplay.model, !model.isEmpty {
                        DetailRow(label: "Model", value: model)
                    }
                    if let deviceId = airplay.deviceId, !deviceId.isEmpty {
                        DetailRow(label: "Device ID", value: deviceId)
                    }
                    if let version = airplay.protocolVersion, !version.isEmpty {
                        DetailRow(label: "Version", value: version)
                    }
                    if let sourceVersion = airplay.sourceVersion, !sourceVersion.isEmpty {
                        DetailRow(label: "Source", value: sourceVersion)
                    }
                    if let osBuild = airplay.osBuildVersion, !osBuild.isEmpty {
                        DetailRow(label: "OS Build", value: osBuild)
                    }
                    
                    // Capability pills
                    CapabilityPillsSection(capabilities: airplayCapabilities)
                    
                    // Feature pills (if any)
                    if !airplay.features.isEmpty {
                        FeaturePillsSection(title: "Features", features: airplayFeatureStrings)
                    }
                }
                .padding(10)
                .background(Color.lanLensBackground.opacity(0.3))
                .cornerRadius(6)
                .padding(.top, 4)
            }
        }
        .accessibilityElement(children: .contain)
    }
    
    private var airplayCapabilities: [(String, Color, Bool)] {
        [
            ("AirPlay 2", Color.lanLensSuccess, airplay.supportsAirPlay2),
            ("Screen Mirroring", Color.lanLensAccent, airplay.supportsScreenMirroring),
            ("Audio Only", Color.lanLensWarning, airplay.isAudioOnly)
        ].filter { $0.2 }
    }
    
    private var airplayFeatureStrings: [String] {
        airplay.features.compactMap { feature -> String? in
            switch feature {
            case .video: return "Video"
            case .photo: return "Photo"
            case .screen: return "Screen"
            case .audio: return "Audio"
            case .carPlay: return "CarPlay"
            case .hudSupported: return "HUD"
            case .supportsVolume: return "Volume"
            case .supportsHKPairing: return "HK Pair"
            case .mfiCert: return "MFi"
            case .unknown: return nil
            default: return nil
            }
        }
    }
}

// MARK: - GoogleCast Section

private struct GoogleCastSection: View {
    let googleCast: GoogleCastTXTData
    let isExpanded: Bool
    let onToggle: () -> Void
    
    /// Google blue color (#4285F4)
    private let googleBlue = Color(red: 0x42/255, green: 0x85/255, blue: 0xF4/255)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProtocolSectionHeader(
                title: "Google Cast",
                icon: "tv.and.mediabox",
                iconColor: googleBlue,
                isExpanded: isExpanded,
                onToggle: onToggle
            )
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    // Key-value rows
                    if let friendlyName = googleCast.friendlyName, !friendlyName.isEmpty {
                        DetailRow(label: "Name", value: friendlyName)
                    }
                    if let modelName = googleCast.modelName, !modelName.isEmpty {
                        DetailRow(label: "Model", value: modelName)
                    }
                    if let firmware = googleCast.firmwareVersion, !firmware.isEmpty {
                        DetailRow(label: "Firmware", value: firmware)
                    }
                    if let id = googleCast.id, !id.isEmpty {
                        DetailRow(label: "Device ID", value: id)
                    }
                    if let castVersion = googleCast.castVersion {
                        DetailRow(label: "Cast Version", value: "\(castVersion)")
                    }
                    
                    // Capability pills
                    CapabilityPillsSection(capabilities: googleCastCapabilities)
                }
                .padding(10)
                .background(Color.lanLensBackground.opacity(0.3))
                .cornerRadius(6)
                .padding(.top, 4)
            }
        }
        .accessibilityElement(children: .contain)
    }
    
    private var googleCastCapabilities: [(String, Color, Bool)] {
        [
            ("Built-in", googleBlue, googleCast.isBuiltIn),
            ("Groups", Color.lanLensSuccess, googleCast.supportsGroups)
        ].filter { $0.2 }
    }
}

// MARK: - HomeKit Section

private struct HomeKitSection: View {
    let homeKit: HomeKitTXTData
    let isExpanded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProtocolSectionHeader(
                title: "HomeKit",
                icon: "homekit",
                iconColor: Color.lanLensWarning,
                isExpanded: isExpanded,
                onToggle: onToggle
            )
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    // Key-value rows
                    if let category = homeKit.category {
                        DetailRow(label: "Category", value: category.displayName)
                    }
                    if let modelName = homeKit.modelName, !modelName.isEmpty {
                        DetailRow(label: "Model", value: modelName)
                    }
                    if let deviceId = homeKit.deviceId, !deviceId.isEmpty {
                        DetailRow(label: "Device ID", value: deviceId)
                    }
                    if let version = homeKit.protocolVersion, !version.isEmpty {
                        DetailRow(label: "Version", value: version)
                    }
                    if let configNum = homeKit.configurationNumber {
                        DetailRow(label: "Config #", value: "\(configNum)")
                    }
                    
                    // Status pills
                    CapabilityPillsSection(capabilities: homeKitCapabilities)
                }
                .padding(10)
                .background(Color.lanLensBackground.opacity(0.3))
                .cornerRadius(6)
                .padding(.top, 4)
            }
        }
        .accessibilityElement(children: .contain)
    }
    
    private var homeKitCapabilities: [(String, Color, Bool)] {
        [
            ("Paired", Color.lanLensSuccess, homeKit.isPaired),
            ("IP", Color.lanLensAccent, homeKit.supportsIP),
            ("BLE", Color.lanLensWarning, homeKit.supportsBLE)
        ].filter { $0.2 }
    }
}

// MARK: - RAOP Section

private struct RAOPSection: View {
    let raop: RAOPTXTData
    let isExpanded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProtocolSectionHeader(
                title: "RAOP (AirPlay Audio)",
                icon: "hifispeaker.fill",
                iconColor: Color.lanLensSuccess,
                isExpanded: isExpanded,
                onToggle: onToggle
            )
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    // Key-value rows
                    if let model = raop.model, !model.isEmpty {
                        DetailRow(label: "Model", value: model)
                    }
                    if let version = raop.protocolVersion, !version.isEmpty {
                        DetailRow(label: "Version", value: version)
                    }
                    if let audioFormats = raop.audioFormats, !audioFormats.isEmpty {
                        DetailRow(label: "Audio Formats", value: audioFormats)
                    }
                    if let compression = raop.compressionTypes, !compression.isEmpty {
                        DetailRow(label: "Compression", value: compression)
                    }
                    if let encryption = raop.encryptionTypes, !encryption.isEmpty {
                        DetailRow(label: "Encryption", value: encryption)
                    }
                    if let transport = raop.transportProtocols, !transport.isEmpty {
                        DetailRow(label: "Transport", value: transport)
                    }
                    
                    // Audio quality pills
                    CapabilityPillsSection(capabilities: raopCapabilities)
                }
                .padding(10)
                .background(Color.lanLensBackground.opacity(0.3))
                .cornerRadius(6)
                .padding(.top, 4)
            }
        }
        .accessibilityElement(children: .contain)
    }
    
    private var raopCapabilities: [(String, Color, Bool)] {
        [
            ("Lossless", Color.lanLensSuccess, raop.supportsLossless),
            ("Hi-Res", Color.lanLensAccent, raop.supportsHighResolution)
        ].filter { $0.2 }
    }
}

// MARK: - Helper Views

private struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.lanLensSecondaryText)
                .frame(width: 70, alignment: .leading)
            
            Text(value)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .textSelection(.enabled)
            
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

private struct CapabilityPillsSection: View {
    let capabilities: [(String, Color, Bool)]
    
    var body: some View {
        if !capabilities.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(capabilities.indices, id: \.self) { index in
                    let cap = capabilities[index]
                    CapabilityPill(text: cap.0, color: cap.1)
                }
            }
        }
    }
}

private struct CapabilityPill: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .cornerRadius(4)
            .accessibilityLabel(text)
    }
}

private struct FeaturePillsSection: View {
    let title: String
    let features: [String]
    
    var body: some View {
        if !features.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.lanLensSecondaryText)
                
                FlowLayout(spacing: 6) {
                    ForEach(features, id: \.self) { feature in
                        Text(feature)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.lanLensSecondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.lanLensSecondaryText.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
            }
        }
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    
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

// MARK: - Preview

#Preview("All Protocols") {
    ScrollView {
        VStack(spacing: 16) {
            MDNSTXTCard(
                mdnsTXT: MDNSTXTData(
                    airplay: AirPlayTXTData(
                        model: "AppleTV6,2",
                        features: [.video, .audio, .screen, .photo],
                        deviceId: "AA:BB:CC:DD:EE:FF",
                        protocolVersion: "1.1",
                        sourceVersion: "670.10.9",
                        osBuildVersion: "21K69",
                        supportsAirPlay2: true,
                        supportsScreenMirroring: true,
                        isAudioOnly: false
                    ),
                    googleCast: GoogleCastTXTData(
                        id: "abc123def456",
                        modelName: "Chromecast Ultra",
                        friendlyName: "Living Room TV",
                        firmwareVersion: "1.56.281235",
                        castVersion: 2,
                        isBuiltIn: false,
                        supportsGroups: true
                    ),
                    homeKit: HomeKitTXTData(
                        category: .appleTv,
                        configurationNumber: 42,
                        protocolVersion: "1.1",
                        deviceId: "11:22:33:44:55:66",
                        modelName: "Apple TV 4K",
                        isPaired: true,
                        supportsIP: true,
                        supportsBLE: false
                    ),
                    raop: RAOPTXTData(
                        audioFormats: "0,1,2,3",
                        compressionTypes: "0,1",
                        encryptionTypes: "0,1,4",
                        transportProtocols: "UDP",
                        protocolVersion: "65536",
                        model: "AppleTV6,2",
                        supportsLossless: true,
                        supportsHighResolution: true
                    )
                )
            )
        }
        .padding(16)
    }
    .frame(width: 360, height: 600)
    .background(Color.lanLensBackground)
}

#Preview("AirPlay Only") {
    MDNSTXTCard(
        mdnsTXT: MDNSTXTData(
            airplay: AirPlayTXTData(
                model: "HomePod,1",
                features: [.audio, .supportsVolume],
                deviceId: "11:22:33:44:55:66",
                protocolVersion: "1.0",
                supportsAirPlay2: true,
                supportsScreenMirroring: false,
                isAudioOnly: true
            )
        )
    )
    .padding(16)
    .background(Color.lanLensBackground)
}

#Preview("HomeKit Sensor") {
    MDNSTXTCard(
        mdnsTXT: MDNSTXTData(
            homeKit: HomeKitTXTData(
                category: .sensor,
                configurationNumber: 5,
                protocolVersion: "1.1",
                deviceId: "AA:BB:CC:DD:EE:FF",
                modelName: "Eve Motion",
                isPaired: true,
                supportsIP: true,
                supportsBLE: true
            )
        )
    )
    .padding(16)
    .background(Color.lanLensBackground)
}

#Preview("Empty Data") {
    MDNSTXTCard(
        mdnsTXT: MDNSTXTData()
    )
    .padding(16)
    .background(Color.lanLensBackground)
}
