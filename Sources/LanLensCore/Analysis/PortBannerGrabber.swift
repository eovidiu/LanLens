import Foundation
import Network
@preconcurrency import Dispatch

/// Actor that grabs service banners from common ports for device identification.
/// Uses the Network framework for TCP connections with configurable timeouts.
public actor PortBannerGrabber {
    
    // MARK: - Singleton
    
    public static let shared = PortBannerGrabber()
    
    private init() {}
    
    // MARK: - Configuration

    /// Default timeout for TCP connections in seconds
    private let connectionTimeout: TimeInterval = 5.0

    /// Maximum size for stored banner data (bytes)
    private static let maxBannerSize = 512
    
    /// Ports that we attempt to grab banners from
    private let sshPorts: Set<Int> = [22]
    private let httpPorts: Set<Int> = [80, 8080, 8000, 8888]
    private let httpsPorts: Set<Int> = [443, 8443]
    private let rtspPorts: Set<Int> = [554]
    
    // MARK: - OS Detection
    
    /// Operating system hints derived from SSH banners
    private enum OSHint: String {
        case linux = "Linux"
        case macOS = "macOS"
        case windows = "Windows"
        case freeBSD = "FreeBSD"
        case embedded = "Embedded"
        case unknown = "Unknown"
    }

    // MARK: - Input Validation

    /// Validates an IP address string format using Network framework
    /// - Parameter ip: The IP address string to validate
    /// - Returns: true if valid IPv4 or IPv6 address format
    private func isValidIPAddress(_ ip: String) -> Bool {
        return IPv4Address(ip) != nil || IPv6Address(ip) != nil
    }

    /// Sanitizes an IP address by removing potentially dangerous characters
    /// - Parameter ip: The IP address string to sanitize
    /// - Returns: Sanitized IP address string
    private func sanitizeIP(_ ip: String) -> String {
        // Remove CR/LF characters that could enable header injection
        return ip.replacingOccurrences(of: "\r", with: "")
                 .replacingOccurrences(of: "\n", with: "")
    }

    /// Validates a port number is within valid TCP range
    /// - Parameter port: The port number to validate
    /// - Returns: true if port is in valid range 1-65535
    private func isValidPort(_ port: Int) -> Bool {
        return port >= 1 && port <= 65535
    }

    /// Truncates a banner string to the maximum allowed size
    /// - Parameter banner: The banner string to truncate
    /// - Returns: Truncated banner string
    private func truncateBanner(_ banner: String) -> String {
        if banner.utf8.count <= Self.maxBannerSize {
            return banner
        }
        // Truncate at UTF-8 boundary to avoid corrupting multi-byte characters
        let data = Data(banner.utf8.prefix(Self.maxBannerSize))
        return String(data: data, encoding: .utf8) ?? String(banner.prefix(Self.maxBannerSize))
    }

    // MARK: - Public Methods
    
    /// Grabs banners from common ports on the specified IP address.
    /// - Parameters:
    ///   - ip: The IP address to probe
    ///   - openPorts: List of known open ports to probe (filters to relevant ports)
    /// - Returns: Aggregated banner data from all successful probes
    public func grabBanners(ip: String, openPorts: [Int]) async -> PortBannerData {
        Log.debug("Starting banner grab for \(ip) with \(openPorts.count) open ports", category: .portBanner)

        // Validate and sanitize IP address
        let sanitizedIP = sanitizeIP(ip)
        guard isValidIPAddress(sanitizedIP) else {
            Log.error("Invalid IP address format: \(ip)", category: .portBanner)
            return PortBannerData()
        }

        // Filter to only valid ports
        let validPorts = openPorts.filter { isValidPort($0) }
        if validPorts.count != openPorts.count {
            Log.warning("Filtered out \(openPorts.count - validPorts.count) invalid port(s)", category: .portBanner)
        }

        var sshBanner: SSHBannerInfo?
        var httpBanner: HTTPHeaderInfo?
        var rtspBanner: RTSPBannerInfo?
        var rawBanners: [Int: String] = [:]

        // Grab SSH banner if port 22 is open
        let sshPortsToProbe = validPorts.filter { sshPorts.contains($0) }
        if let port = sshPortsToProbe.first {
            Log.debug("Probing SSH on port \(port) for \(sanitizedIP)", category: .portBanner)
            if let banner = await grabSSHBanner(ip: sanitizedIP, port: port) {
                sshBanner = banner
                rawBanners[port] = truncateBanner(banner.rawBanner)
                Log.info("SSH banner for \(sanitizedIP): \(truncateBanner(banner.rawBanner))", category: .portBanner)
            }
        }

        // Grab HTTP banner from first available HTTP port
        let httpPortsToProbe = validPorts.filter { httpPorts.contains($0) }
        if let port = httpPortsToProbe.first {
            Log.debug("Probing HTTP on port \(port) for \(sanitizedIP)", category: .portBanner)
            if let info = await grabHTTPBanner(ip: sanitizedIP, port: port, useTLS: false) {
                httpBanner = info
                if let server = info.server {
                    rawBanners[port] = truncateBanner(server)
                }
                Log.info("HTTP banner for \(sanitizedIP):\(port): Server=\(info.server ?? "nil")", category: .portBanner)
            }
        }

        // Grab HTTPS banner if no HTTP banner and HTTPS port is open
        if httpBanner == nil {
            let httpsPortsToProbe = validPorts.filter { httpsPorts.contains($0) }
            if let port = httpsPortsToProbe.first {
                Log.debug("Probing HTTPS on port \(port) for \(sanitizedIP)", category: .portBanner)
                if let info = await grabHTTPBanner(ip: sanitizedIP, port: port, useTLS: true) {
                    httpBanner = info
                    if let server = info.server {
                        rawBanners[port] = truncateBanner(server)
                    }
                    Log.info("HTTPS banner for \(sanitizedIP):\(port): Server=\(info.server ?? "nil"), TLS verified=\(info.tlsCertificateVerified)", category: .portBanner)
                }
            }
        }

        // Grab RTSP banner if port 554 is open
        let rtspPortsToProbe = validPorts.filter { rtspPorts.contains($0) }
        if let port = rtspPortsToProbe.first {
            Log.debug("Probing RTSP on port \(port) for \(sanitizedIP)", category: .portBanner)
            if let info = await grabRTSPBanner(ip: sanitizedIP, port: port) {
                rtspBanner = info
                if let server = info.server {
                    rawBanners[port] = truncateBanner(server)
                }
                Log.info("RTSP banner for \(sanitizedIP): Server=\(info.server ?? "nil"), Methods=\(info.methods)", category: .portBanner)
            }
        }

        let result = PortBannerData(
            ssh: sshBanner,
            http: httpBanner,
            rtsp: rtspBanner,
            rawBanners: rawBanners
        )

        Log.debug("Banner grab complete for \(sanitizedIP): SSH=\(sshBanner != nil), HTTP=\(httpBanner != nil), RTSP=\(rtspBanner != nil)", category: .portBanner)

        return result
    }
    
    /// Generates inference signals from port banner data.
    /// - Parameter data: The port banner data to analyze
    /// - Returns: Array of signals for device type inference
    public func generateSignals(from data: PortBannerData) -> [DeviceTypeInferenceEngine.Signal] {
        var signals: [DeviceTypeInferenceEngine.Signal] = []
        
        // SSH banner signals
        if let ssh = data.ssh {
            signals.append(contentsOf: generateSSHSignals(from: ssh))
        }
        
        // HTTP banner signals
        if let http = data.http {
            signals.append(contentsOf: generateHTTPSignals(from: http))
        }
        
        // RTSP banner signals
        if let rtsp = data.rtsp {
            signals.append(contentsOf: generateRTSPSignals(from: rtsp))
        }
        
        Log.debug("Generated \(signals.count) signals from banner data", category: .portBanner)
        
        return signals
    }
    
    // MARK: - SSH Banner Grabbing
    
    private func grabSSHBanner(ip: String, port: Int) async -> SSHBannerInfo? {
        guard let data = await connectAndReceive(ip: ip, port: port, sendData: nil) else {
            return nil
        }
        
        guard let bannerString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        
        // SSH banner format: SSH-protoversion-softwareversion SP comments
        // Example: SSH-2.0-OpenSSH_9.0p1 Ubuntu-3ubuntu0.1
        
        var protocolVersion: String?
        var softwareVersion: String?
        var osHint: String?
        var isNetworkEquipment = false
        var isNAS = false
        
        if bannerString.hasPrefix("SSH-") {
            let parts = bannerString.dropFirst(4).split(separator: "-", maxSplits: 1)
            if parts.count >= 1 {
                protocolVersion = String(parts[0])
            }
            if parts.count >= 2 {
                // Software version might have comments after a space
                let softwareParts = parts[1].split(separator: " ", maxSplits: 1)
                softwareVersion = String(softwareParts[0])
            }
        }
        
        // Detect OS from banner
        osHint = detectOSFromSSHBanner(bannerString)
        
        // Detect network equipment
        let lowerBanner = bannerString.lowercased()
        if lowerBanner.contains("cisco") || lowerBanner.contains("juniper") ||
           lowerBanner.contains("mikrotik") || lowerBanner.contains("ubiquiti") ||
           lowerBanner.contains("routeros") || lowerBanner.contains("edgeos") {
            isNetworkEquipment = true
        }
        
        // Detect NAS devices
        if lowerBanner.contains("synology") || lowerBanner.contains("qnap") ||
           lowerBanner.contains("drobo") || lowerBanner.contains("netgear") ||
           lowerBanner.contains("readynas") || lowerBanner.contains("terramaster") {
            isNAS = true
        }
        
        return SSHBannerInfo(
            rawBanner: bannerString,
            protocolVersion: protocolVersion,
            softwareVersion: softwareVersion,
            osHint: osHint,
            isNetworkEquipment: isNetworkEquipment,
            isNAS: isNAS
        )
    }
    
    private func detectOSFromSSHBanner(_ banner: String) -> String? {
        let lowerBanner = banner.lowercased()
        
        if lowerBanner.contains("ubuntu") || lowerBanner.contains("debian") ||
           lowerBanner.contains("fedora") || lowerBanner.contains("centos") ||
           lowerBanner.contains("redhat") || lowerBanner.contains("linux") {
            return OSHint.linux.rawValue
        }
        
        if lowerBanner.contains("freebsd") || lowerBanner.contains("openbsd") ||
           lowerBanner.contains("netbsd") {
            return OSHint.freeBSD.rawValue
        }
        
        if lowerBanner.contains("dropbear") {
            return OSHint.embedded.rawValue
        }
        
        if lowerBanner.contains("apple") || lowerBanner.contains("macos") ||
           lowerBanner.contains("darwin") {
            return OSHint.macOS.rawValue
        }
        
        if lowerBanner.contains("windows") || lowerBanner.contains("openssh_for_windows") {
            return OSHint.windows.rawValue
        }
        
        return nil
    }
    
    // MARK: - HTTP Banner Grabbing
    
    private func grabHTTPBanner(ip: String, port: Int, useTLS: Bool) async -> HTTPHeaderInfo? {
        let request = "HEAD / HTTP/1.1\r\nHost: \(ip)\r\nConnection: close\r\n\r\n"
        guard let requestData = request.data(using: .utf8) else {
            return nil
        }

        guard let responseData = await connectAndReceive(ip: ip, port: port, sendData: requestData, useTLS: useTLS) else {
            return nil
        }

        guard let responseString = String(data: responseData, encoding: .utf8) else {
            return nil
        }

        var info = parseHTTPResponse(responseString)
        // Track TLS certificate verification status
        // When useTLS is true, we bypass verification for IoT probing (tlsCertificateVerified = false)
        // When useTLS is false, no TLS is used so field is not applicable (defaults to false)
        info.tlsCertificateVerified = false
        if useTLS {
            Log.debug("TLS certificate validation bypassed for IoT device probing on \(ip):\(port)", category: .portBanner)
        }
        return info
    }
    
    private func parseHTTPResponse(_ response: String) -> HTTPHeaderInfo {
        var server: String?
        var poweredBy: String?
        var authenticate: String?
        var contentType: String?
        var detectedFramework: String?
        var isAdminInterface = false
        var isCameraInterface = false
        var isPrinterInterface = false
        var isRouterInterface = false
        var isNASInterface = false
        
        let lines = response.components(separatedBy: "\r\n")
        
        for line in lines {
            let lowerLine = line.lowercased()
            
            if lowerLine.hasPrefix("server:") {
                server = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            } else if lowerLine.hasPrefix("x-powered-by:") {
                poweredBy = String(line.dropFirst(13)).trimmingCharacters(in: .whitespaces)
            } else if lowerLine.hasPrefix("www-authenticate:") {
                authenticate = String(line.dropFirst(17)).trimmingCharacters(in: .whitespaces)
            } else if lowerLine.hasPrefix("content-type:") {
                contentType = String(line.dropFirst(13)).trimmingCharacters(in: .whitespaces)
            }
        }
        
        // Detect device types from server header
        let serverLower = server?.lowercased() ?? ""
        let fullResponse = response.lowercased()
        
        // Camera detection
        if serverLower.contains("hikvision") || serverLower.contains("dahua") ||
           serverLower.contains("axis") || serverLower.contains("foscam") ||
           serverLower.contains("amcrest") || serverLower.contains("reolink") ||
           serverLower.contains("vivotek") || serverLower.contains("geovision") ||
           fullResponse.contains("camera") || fullResponse.contains("ipcam") {
            isCameraInterface = true
        }
        
        // Printer detection
        if serverLower.contains("printer") || serverLower.contains("cups") ||
           serverLower.contains("hp-") || serverLower.contains("canon") ||
           serverLower.contains("epson") || serverLower.contains("brother") ||
           serverLower.contains("xerox") || serverLower.contains("lexmark") ||
           serverLower.contains("ipp") {
            isPrinterInterface = true
        }
        
        // NAS detection
        if serverLower.contains("synology") || serverLower.contains("qnap") ||
           serverLower.contains("dsm") || serverLower.contains("asustor") ||
           serverLower.contains("terramaster") || serverLower.contains("freenas") ||
           serverLower.contains("truenas") || serverLower.contains("unraid") ||
           serverLower.contains("openmediavault") {
            isNASInterface = true
        }
        
        // Router detection
        if serverLower.contains("router") || serverLower.contains("gateway") ||
           serverLower.contains("mikrotik") || serverLower.contains("openwrt") ||
           serverLower.contains("dd-wrt") || serverLower.contains("tomato") ||
           serverLower.contains("asus") || serverLower.contains("netgear") ||
           serverLower.contains("tp-link") || serverLower.contains("linksys") ||
           serverLower.contains("ubiquiti") || serverLower.contains("unifi") {
            isRouterInterface = true
        }
        
        // Admin interface detection
        if fullResponse.contains("admin") || fullResponse.contains("login") ||
           fullResponse.contains("management") || authenticate != nil {
            isAdminInterface = true
        }
        
        // Framework detection
        if let powered = poweredBy?.lowercased() {
            if powered.contains("php") {
                detectedFramework = "PHP"
            } else if powered.contains("asp.net") {
                detectedFramework = "ASP.NET"
            } else if powered.contains("express") {
                detectedFramework = "Express.js"
            }
        }
        
        return HTTPHeaderInfo(
            server: server,
            poweredBy: poweredBy,
            authenticate: authenticate,
            contentType: contentType,
            detectedFramework: detectedFramework,
            isAdminInterface: isAdminInterface,
            isCameraInterface: isCameraInterface,
            isPrinterInterface: isPrinterInterface,
            isRouterInterface: isRouterInterface,
            isNASInterface: isNASInterface,
            tlsCertificateVerified: false
        )
    }
    
    // MARK: - RTSP Banner Grabbing
    
    private func grabRTSPBanner(ip: String, port: Int) async -> RTSPBannerInfo? {
        let request = "OPTIONS rtsp://\(ip):\(port)/ RTSP/1.0\r\nCSeq: 1\r\n\r\n"
        guard let requestData = request.data(using: .utf8) else {
            return nil
        }
        
        guard let responseData = await connectAndReceive(ip: ip, port: port, sendData: requestData) else {
            return nil
        }
        
        guard let responseString = String(data: responseData, encoding: .utf8) else {
            return nil
        }
        
        return parseRTSPResponse(responseString)
    }
    
    private func parseRTSPResponse(_ response: String) -> RTSPBannerInfo {
        var server: String?
        var methods: [String] = []
        var contentBase: String?
        var requiresAuth = false
        var cameraVendor: String?
        
        let lines = response.components(separatedBy: "\r\n")
        
        // Check for 401 Unauthorized
        if let statusLine = lines.first, statusLine.contains("401") {
            requiresAuth = true
        }
        
        for line in lines {
            let lowerLine = line.lowercased()
            
            if lowerLine.hasPrefix("server:") {
                server = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            } else if lowerLine.hasPrefix("public:") {
                let methodsString = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                methods = methodsString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            } else if lowerLine.hasPrefix("content-base:") {
                contentBase = String(line.dropFirst(13)).trimmingCharacters(in: .whitespaces)
            } else if lowerLine.hasPrefix("www-authenticate:") {
                requiresAuth = true
            }
        }
        
        // Detect camera vendor from server header
        let serverLower = server?.lowercased() ?? ""
        
        if serverLower.contains("hikvision") || serverLower.contains("hik-connect") {
            cameraVendor = "Hikvision"
        } else if serverLower.contains("dahua") {
            cameraVendor = "Dahua"
        } else if serverLower.contains("axis") {
            cameraVendor = "Axis"
        } else if serverLower.contains("foscam") {
            cameraVendor = "Foscam"
        } else if serverLower.contains("amcrest") {
            cameraVendor = "Amcrest"
        } else if serverLower.contains("reolink") {
            cameraVendor = "Reolink"
        } else if serverLower.contains("vivotek") {
            cameraVendor = "Vivotek"
        } else if serverLower.contains("geovision") {
            cameraVendor = "GeoVision"
        } else if serverLower.contains("ubiquiti") || serverLower.contains("unifi") {
            cameraVendor = "Ubiquiti"
        } else if serverLower.contains("hanwha") || serverLower.contains("samsung") {
            cameraVendor = "Hanwha/Samsung"
        }
        
        return RTSPBannerInfo(
            server: server,
            methods: methods,
            contentBase: contentBase,
            requiresAuth: requiresAuth,
            cameraVendor: cameraVendor
        )
    }
    
    // MARK: - Signal Generation
    
    private func generateSSHSignals(from ssh: SSHBannerInfo) -> [DeviceTypeInferenceEngine.Signal] {
        var signals: [DeviceTypeInferenceEngine.Signal] = []
        
        // OS-based signals
        if let osHint = ssh.osHint {
            switch osHint {
            case OSHint.macOS.rawValue:
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .portBanner,
                    suggestedType: .computer,
                    confidence: 0.80
                ))
            case OSHint.linux.rawValue:
                // Linux could be a computer, NAS, or server
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .portBanner,
                    suggestedType: .computer,
                    confidence: 0.60
                ))
            case OSHint.windows.rawValue:
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .portBanner,
                    suggestedType: .computer,
                    confidence: 0.75
                ))
            case OSHint.embedded.rawValue:
                // Dropbear typically runs on embedded devices like routers
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .portBanner,
                    suggestedType: .hub,
                    confidence: 0.65
                ))
            case OSHint.freeBSD.rawValue:
                // FreeBSD is common on NAS devices and routers
                signals.append(DeviceTypeInferenceEngine.Signal(
                    source: .portBanner,
                    suggestedType: .nas,
                    confidence: 0.55
                ))
            default:
                break
            }
        }
        
        // Network equipment signal
        if ssh.isNetworkEquipment {
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .portBanner,
                suggestedType: .router,
                confidence: 0.80
            ))
        }
        
        // NAS signal
        if ssh.isNAS {
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .portBanner,
                suggestedType: .nas,
                confidence: 0.85
            ))
        }
        
        return signals
    }
    
    private func generateHTTPSignals(from http: HTTPHeaderInfo) -> [DeviceTypeInferenceEngine.Signal] {
        var signals: [DeviceTypeInferenceEngine.Signal] = []
        let serverLower = http.server?.lowercased() ?? ""
        
        // NAS detection (high confidence)
        if http.isNASInterface || serverLower.contains("synology") ||
           serverLower.contains("qnap") || serverLower.contains("dsm") {
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .portBanner,
                suggestedType: .nas,
                confidence: 0.95
            ))
        }
        
        // Printer detection (high confidence)
        if http.isPrinterInterface || serverLower.contains("printer") ||
           serverLower.contains("cups") {
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .portBanner,
                suggestedType: .printer,
                confidence: 0.90
            ))
        }
        
        // Camera detection (high confidence)
        if http.isCameraInterface || serverLower.contains("hikvision") ||
           serverLower.contains("dahua") || serverLower.contains("axis") ||
           serverLower.contains("foscam") || serverLower.contains("amcrest") ||
           serverLower.contains("reolink") {
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .portBanner,
                suggestedType: .camera,
                confidence: 0.90
            ))
        }
        
        // Router detection
        if http.isRouterInterface {
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .portBanner,
                suggestedType: .router,
                confidence: 0.80
            ))
        }
        
        // Additional server header analysis
        if serverLower.contains("apache") || serverLower.contains("nginx") ||
           serverLower.contains("iis") {
            // Generic web server - could be a computer or server
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .portBanner,
                suggestedType: .computer,
                confidence: 0.50
            ))
        }
        
        // Home automation/hub servers
        if serverLower.contains("home assistant") || serverLower.contains("openhab") ||
           serverLower.contains("domoticz") || serverLower.contains("hubitat") {
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .portBanner,
                suggestedType: .hub,
                confidence: 0.90
            ))
        }
        
        // Plex/media servers
        if serverLower.contains("plex") || serverLower.contains("emby") ||
           serverLower.contains("jellyfin") {
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .portBanner,
                suggestedType: .nas,
                confidence: 0.70
            ))
        }
        
        return signals
    }
    
    private func generateRTSPSignals(from rtsp: RTSPBannerInfo) -> [DeviceTypeInferenceEngine.Signal] {
        var signals: [DeviceTypeInferenceEngine.Signal] = []
        
        // RTSP with DESCRIBE/PLAY support strongly indicates a camera
        let hasStreamingCapabilities = rtsp.methods.contains { method in
            let upperMethod = method.uppercased()
            return upperMethod == "DESCRIBE" || upperMethod == "PLAY" || upperMethod == "SETUP"
        }
        
        if hasStreamingCapabilities {
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .portBanner,
                suggestedType: .camera,
                confidence: 0.85
            ))
        }
        
        // Known camera vendor provides very high confidence
        if rtsp.cameraVendor != nil {
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .portBanner,
                suggestedType: .camera,
                confidence: 0.95
            ))
        }
        
        // RTSP server without streaming methods might be a media device
        if !hasStreamingCapabilities && rtsp.server != nil {
            signals.append(DeviceTypeInferenceEngine.Signal(
                source: .portBanner,
                suggestedType: .smartTV,
                confidence: 0.50
            ))
        }
        
        return signals
    }
    
    // MARK: - Network Connection
    
    /// Connects to a TCP endpoint, optionally sends data, and receives response.
    /// - Parameters:
    ///   - ip: Target IP address
    ///   - port: Target port
    ///   - sendData: Optional data to send after connection
    ///   - useTLS: Whether to use TLS
    /// - Returns: Response data or nil if connection failed
    private func connectAndReceive(ip: String, port: Int, sendData: Data?, useTLS: Bool = false) async -> Data? {
        // Validate port range before casting to UInt16
        guard port >= 1 && port <= 65535 else {
            Log.error("Invalid port number \(port) - must be 1-65535", category: .portBanner)
            return nil
        }

        return await withCheckedContinuation { continuation in
            let host = NWEndpoint.Host(ip)
            let nwPort = NWEndpoint.Port(integerLiteral: UInt16(port))

            let parameters: NWParameters
            if useTLS {
                let tlsOptions = NWProtocolTLS.Options()
                // SECURITY NOTE: Certificate validation is intentionally disabled for IoT device probing.
                // Many IoT devices use self-signed certificates. This allows banner grabbing to succeed
                // but the connection should NOT be trusted for sensitive data transmission.
                // The tlsCertificateVerified field in HTTPHeaderInfo tracks this for observability.
                sec_protocol_options_set_verify_block(
                    tlsOptions.securityProtocolOptions,
                    { _, _, completionHandler in
                        // Accept all certificates for device discovery purposes
                        completionHandler(true)
                    },
                    DispatchQueue.global(qos: .userInitiated)
                )
                parameters = NWParameters(tls: tlsOptions)
            } else {
                parameters = NWParameters.tcp
            }
            
            let connection = NWConnection(host: host, port: nwPort, using: parameters)
            
            var hasResumed = false
            let resumeOnce: (Data?) -> Void = { data in
                guard !hasResumed else { return }
                hasResumed = true
                connection.cancel()
                continuation.resume(returning: data)
            }
            
            // Setup timeout
            let timeoutWorkItem = DispatchWorkItem { [weak connection] in
                connection?.cancel()
                resumeOnce(nil)
            }
            DispatchQueue.global().asyncAfter(
                deadline: .now() + connectionTimeout,
                execute: timeoutWorkItem
            )
            
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let dataToSend = sendData {
                        // Send data then receive
                        connection.send(content: dataToSend, completion: .contentProcessed { error in
                            if error != nil {
                                timeoutWorkItem.cancel()
                                resumeOnce(nil)
                                return
                            }
                            // Receive response
                            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, error in
                                timeoutWorkItem.cancel()
                                if error != nil {
                                    resumeOnce(nil)
                                } else {
                                    resumeOnce(data)
                                }
                            }
                        })
                    } else {
                        // Just receive (e.g., SSH banner)
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, error in
                            timeoutWorkItem.cancel()
                            if error != nil {
                                resumeOnce(nil)
                            } else {
                                resumeOnce(data)
                            }
                        }
                    }
                    
                case .failed, .cancelled:
                    timeoutWorkItem.cancel()
                    resumeOnce(nil)
                    
                default:
                    break
                }
            }
            
            connection.start(queue: DispatchQueue.global(qos: .userInitiated))
        }
    }
}
