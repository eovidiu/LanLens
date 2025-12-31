import SwiftUI
import LanLensCore

/// Card displaying service banner information gathered from port scanning.
/// Shows protocol-specific details for SSH, HTTP, and RTSP services,
/// plus expandable raw banner data.
struct PortBannerCard: View {
    let portBanners: PortBannerData
    @State private var showRawBanners = false
    @State private var expandedBannerPort: Int?

    /// Only render if there's actual data to display
    var hasContent: Bool {
        portBanners.ssh != nil ||
        portBanners.http != nil ||
        portBanners.rtsp != nil ||
        !portBanners.rawBanners.isEmpty
    }

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Service Banners", icon: "network")

                VStack(alignment: .leading, spacing: 12) {
                    // SSH section
                    if let ssh = portBanners.ssh {
                        SSHBannerSection(ssh: ssh)
                    }

                    // HTTP section
                    if let http = portBanners.http {
                        HTTPBannerSection(http: http)
                    }

                    // RTSP section
                    if let rtsp = portBanners.rtsp {
                        RTSPBannerSection(rtsp: rtsp)
                    }

                    // Raw banners (collapsible)
                    if !portBanners.rawBanners.isEmpty {
                        RawBannersSection(
                            rawBanners: portBanners.rawBanners,
                            isExpanded: $showRawBanners,
                            expandedPort: $expandedBannerPort
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .background(Color.lanLensCard)
            .cornerRadius(12)
        }
    }
}

// MARK: - Card Header (local copy for consistency)

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

// MARK: - SSH Banner Section

private struct SSHBannerSection: View {
    let ssh: SSHBannerInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.lanLensAccent)
                Text("SSH")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                // Device type badges
                if ssh.isNetworkEquipment {
                    BadgePill(text: "Network", color: Color.lanLensWarning)
                }
                if ssh.isNAS {
                    BadgePill(text: "NAS", color: Color.lanLensAccent)
                }
            }

            // Details
            VStack(alignment: .leading, spacing: 4) {
                // Software version
                if let software = ssh.softwareVersion, !software.isEmpty {
                    BannerDetailRow(label: "Software", value: software)
                }

                // OS hint
                if let osHint = ssh.osHint, !osHint.isEmpty {
                    BannerDetailRow(label: "OS", value: osHint)
                }

                // Protocol version
                if let proto = ssh.protocolVersion, !proto.isEmpty {
                    BannerDetailRow(label: "Protocol", value: proto)
                }
            }
        }
        .padding(10)
        .background(Color.lanLensBackground.opacity(0.5))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("SSH service: \(ssh.softwareVersion ?? "unknown version")")
    }
}

// MARK: - HTTP Banner Section

private struct HTTPBannerSection: View {
    let http: HTTPHeaderInfo

    private var interfaceTypes: [(String, Color)] {
        var types: [(String, Color)] = []
        if http.isAdminInterface {
            types.append(("Admin", Color.lanLensWarning))
        }
        if http.isCameraInterface {
            types.append(("Camera", Color.lanLensAccent))
        }
        if http.isRouterInterface {
            types.append(("Router", Color.lanLensWarning))
        }
        if http.isNASInterface {
            types.append(("NAS", Color.lanLensAccent))
        }
        if http.isPrinterInterface {
            types.append(("Printer", Color.lanLensSecondaryText))
        }
        return types
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header with TLS indicator
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.lanLensAccent)
                Text("HTTP")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                // TLS status
                TLSIndicator(verified: http.tlsCertificateVerified)
            }

            // Details
            VStack(alignment: .leading, spacing: 4) {
                // Server header
                if let server = http.server, !server.isEmpty {
                    BannerDetailRow(label: "Server", value: server)
                }

                // Powered by
                if let poweredBy = http.poweredBy, !poweredBy.isEmpty {
                    BannerDetailRow(label: "Powered By", value: poweredBy)
                }

                // Detected framework
                if let framework = http.detectedFramework, !framework.isEmpty {
                    BannerDetailRow(label: "Framework", value: framework)
                }

                // Content type
                if let contentType = http.contentType, !contentType.isEmpty {
                    BannerDetailRow(label: "Content", value: contentType)
                }

                // Authentication header
                if let auth = http.authenticate, !auth.isEmpty {
                    BannerDetailRow(label: "Auth", value: auth)
                }
            }

            // Interface type badges
            if !interfaceTypes.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(interfaceTypes.enumerated()), id: \.offset) { _, typeInfo in
                        BadgePill(text: typeInfo.0, color: typeInfo.1)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.lanLensBackground.opacity(0.5))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("HTTP service: \(http.server ?? "unknown server")")
    }
}

// MARK: - TLS Indicator

private struct TLSIndicator: View {
    let verified: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: verified ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 9))
            Text(verified ? "TLS" : "Insecure")
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(verified ? Color.lanLensSuccess : Color.lanLensWarning)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background((verified ? Color.lanLensSuccess : Color.lanLensWarning).opacity(0.15))
        .cornerRadius(4)
        .accessibilityLabel(verified ? "TLS certificate verified" : "Insecure connection")
    }
}

// MARK: - RTSP Banner Section

private struct RTSPBannerSection: View {
    let rtsp: RTSPBannerInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: "video.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.lanLensAccent)
                Text("RTSP")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                // Auth required indicator
                if rtsp.requiresAuth {
                    HStack(spacing: 4) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 9))
                        Text("Auth Required")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(Color.lanLensWarning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.lanLensWarning.opacity(0.15))
                    .cornerRadius(4)
                }
            }

            // Details
            VStack(alignment: .leading, spacing: 4) {
                // Server
                if let server = rtsp.server, !server.isEmpty {
                    BannerDetailRow(label: "Server", value: server)
                }

                // Camera vendor
                if let vendor = rtsp.cameraVendor, !vendor.isEmpty {
                    BannerDetailRow(label: "Vendor", value: vendor)
                }

                // Content base URL
                if let contentBase = rtsp.contentBase, !contentBase.isEmpty {
                    BannerDetailRow(label: "Stream", value: contentBase)
                }

                // Supported methods
                if !rtsp.methods.isEmpty {
                    BannerDetailRow(
                        label: "Methods",
                        value: rtsp.methods.joined(separator: ", ")
                    )
                }
            }
        }
        .padding(10)
        .background(Color.lanLensBackground.opacity(0.5))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("RTSP streaming service\(rtsp.cameraVendor.map { ", vendor: \($0)" } ?? "")")
    }
}

// MARK: - Raw Banners Section (Collapsible)

private struct RawBannersSection: View {
    let rawBanners: [Int: String]
    @Binding var isExpanded: Bool
    @Binding var expandedPort: Int?

    private var sortedPorts: [Int] {
        rawBanners.keys.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Collapsible header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.lanLensSecondaryText)
                    Text("Raw Banners")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.lanLensSecondaryText)

                    Text("(\(rawBanners.count))")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.lanLensSecondaryText.opacity(0.7))

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.lanLensSecondaryText)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Raw banners, \(rawBanners.count) items")
            .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand")

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sortedPorts, id: \.self) { port in
                        RawBannerRow(
                            port: port,
                            banner: rawBanners[port] ?? "",
                            isExpanded: expandedPort == port,
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    if expandedPort == port {
                                        expandedPort = nil
                                    } else {
                                        expandedPort = port
                                    }
                                }
                            }
                        )
                    }
                }
                .padding(10)
                .background(Color.lanLensBackground.opacity(0.5))
                .cornerRadius(8)
            }
        }
    }
}

// MARK: - Raw Banner Row

private struct RawBannerRow: View {
    let port: Int
    let banner: String
    let isExpanded: Bool
    let onToggle: () -> Void

    private var truncatedBanner: String {
        let cleaned = banner
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count > 40 {
            return String(cleaned.prefix(40)) + "..."
        }
        return cleaned
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    // Port badge
                    Text("\(port)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.lanLensAccent.opacity(0.3))
                        .cornerRadius(4)

                    // Truncated or full banner
                    Text(isExpanded ? "" : truncatedBanner)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.lanLensSecondaryText)
                        .lineLimit(1)

                    Spacer()

                    if banner.count > 40 {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.lanLensSecondaryText)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Full banner (expanded)
            if isExpanded {
                Text(banner)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.lanLensSecondaryText)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(4)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Port \(port) banner")
        .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand full banner")
    }
}

// MARK: - Helper Views

private struct BannerDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.lanLensSecondaryText)
                .frame(width: 60, alignment: .leading)

            Text(value)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .textSelection(.enabled)

            Spacer()
        }
    }
}

private struct BadgePill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .cornerRadius(4)
    }
}

// MARK: - Preview

#Preview("Full Banner Data") {
    ScrollView {
        VStack(spacing: 16) {
            PortBannerCard(
                portBanners: PortBannerData(
                    ssh: SSHBannerInfo(
                        rawBanner: "SSH-2.0-OpenSSH_8.9p1 Ubuntu-3ubuntu0.4",
                        protocolVersion: "2.0",
                        softwareVersion: "OpenSSH_8.9p1",
                        osHint: "Ubuntu",
                        isNetworkEquipment: false,
                        isNAS: false
                    ),
                    http: HTTPHeaderInfo(
                        server: "nginx/1.24.0",
                        poweredBy: "PHP/8.2",
                        authenticate: nil,
                        contentType: "text/html; charset=UTF-8",
                        detectedFramework: "Laravel",
                        isAdminInterface: true,
                        isCameraInterface: false,
                        isPrinterInterface: false,
                        isRouterInterface: false,
                        isNASInterface: false,
                        tlsCertificateVerified: true
                    ),
                    rtsp: RTSPBannerInfo(
                        server: "Hikvision-Webs",
                        methods: ["OPTIONS", "DESCRIBE", "SETUP", "PLAY"],
                        requiresAuth: true,
                        cameraVendor: "Hikvision"
                    ),
                    rawBanners: [
                        22: "SSH-2.0-OpenSSH_8.9p1 Ubuntu-3ubuntu0.4",
                        80: "HTTP/1.1 200 OK\r\nServer: nginx/1.24.0\r\nX-Powered-By: PHP/8.2",
                        554: "RTSP/1.0 200 OK\r\nServer: Hikvision-Webs"
                    ]
                )
            )
        }
        .padding(16)
    }
    .frame(width: 360, height: 600)
    .background(Color.lanLensBackground)
}

#Preview("SSH Only") {
    PortBannerCard(
        portBanners: PortBannerData(
            ssh: SSHBannerInfo(
                rawBanner: "SSH-2.0-dropbear_2022.83",
                protocolVersion: "2.0",
                softwareVersion: "dropbear_2022.83",
                osHint: nil,
                isNetworkEquipment: true,
                isNAS: false
            ),
            http: nil,
            rtsp: nil,
            rawBanners: [:]
        )
    )
    .padding(16)
    .background(Color.lanLensBackground)
}

#Preview("HTTP Insecure") {
    PortBannerCard(
        portBanners: PortBannerData(
            ssh: nil,
            http: HTTPHeaderInfo(
                server: "lighttpd/1.4.67",
                poweredBy: nil,
                authenticate: "Basic realm=\"Admin\"",
                contentType: nil,
                detectedFramework: nil,
                isAdminInterface: true,
                isCameraInterface: true,
                isPrinterInterface: false,
                isRouterInterface: false,
                isNASInterface: false,
                tlsCertificateVerified: false
            ),
            rtsp: nil,
            rawBanners: [:]
        )
    )
    .padding(16)
    .background(Color.lanLensBackground)
}

#Preview("Empty Data") {
    PortBannerCard(
        portBanners: PortBannerData(
            ssh: nil,
            http: nil,
            rtsp: nil,
            rawBanners: [:]
        )
    )
    .padding(16)
    .background(Color.lanLensBackground)
}
