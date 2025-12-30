import Foundation

/// Port scanner using nmap (when available) or fallback to socket-based scanning
public actor PortScanner {
    public static let shared = PortScanner()

    private init() {}

    /// Common ports to scan for smart devices
    public static let smartDevicePorts: [UInt16] = [
        22,     // SSH
        80,     // HTTP
        443,    // HTTPS
        548,    // AFP
        554,    // RTSP (cameras)
        1400,   // Sonos
        1883,   // MQTT
        3000,   // Various web apps
        3478,   // STUN/TURN
        3689,   // DAAP (iTunes)
        5000,   // UPnP, Synology
        5001,   // Synology SSL
        5353,   // mDNS
        6466,   // SSDP
        7000,   // AirPlay
        8008,   // Google Cast
        8009,   // Google Cast
        8080,   // HTTP alt
        8123,   // Home Assistant
        8443,   // HTTPS alt
        8883,   // MQTT SSL
        9000,   // Portainer, PHP-FPM
        9090,   // Prometheus
        9100,   // Printer
        49152,  // UPnP
        49153,  // UPnP
        49154,  // UPnP
    ]

    /// Quick common ports for fast scans
    public static let quickPorts: [UInt16] = [
        22, 80, 443, 554, 1883, 5000, 7000, 8008, 8080, 8123
    ]

    public struct ScanResult: Sendable {
        public let ip: String
        public let openPorts: [PortInfo]
        public let scanDuration: TimeInterval
    }

    public struct PortInfo: Sendable, Hashable {
        public let port: UInt16
        public let transportProtocol: TransportProto
        public let service: String?
        public let version: String?

        public enum TransportProto: String, Sendable {
            case tcp
            case udp
        }
    }

    /// Check if nmap is available
    public func isNmapAvailable() async -> Bool {
        return await getNmapPath() != nil
    }

    /// Get nmap path if available
    private func getNmapPath() async -> String? {
        let paths = ["/opt/homebrew/bin/nmap", "/usr/local/bin/nmap", "/usr/bin/nmap"]
        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Scan a single host for open ports
    public func scan(ip: String, ports: [UInt16]? = nil, useNmap: Bool = true) async -> ScanResult {
        let portsToScan = ports ?? Self.smartDevicePorts
        let startTime = Date()

        // Try nmap first if available and requested
        if useNmap, let nmapPath = await getNmapPath() {
            if let result = await scanWithNmap(ip: ip, ports: portsToScan, nmapPath: nmapPath) {
                return ScanResult(
                    ip: ip,
                    openPorts: result,
                    scanDuration: Date().timeIntervalSince(startTime)
                )
            }
        }

        // Fallback to socket-based scanning
        let result = await scanWithSockets(ip: ip, ports: portsToScan)
        return ScanResult(
            ip: ip,
            openPorts: result,
            scanDuration: Date().timeIntervalSince(startTime)
        )
    }

    /// Quick scan for common smart device ports
    public func quickScan(ip: String) async -> ScanResult {
        return await scan(ip: ip, ports: Self.quickPorts, useNmap: false)
    }

    /// Scan multiple hosts in parallel
    public func scanHosts(_ ips: [String], ports: [UInt16]? = nil) async -> [String: ScanResult] {
        var results: [String: ScanResult] = [:]

        await withTaskGroup(of: (String, ScanResult).self) { group in
            for ip in ips {
                group.addTask {
                    let result = await self.scan(ip: ip, ports: ports)
                    return (ip, result)
                }
            }

            for await (ip, result) in group {
                results[ip] = result
            }
        }

        return results
    }

    // MARK: - Nmap-based scanning

    private func scanWithNmap(ip: String, ports: [UInt16], nmapPath: String) async -> [PortInfo]? {
        let portList = ports.map { String($0) }.joined(separator: ",")

        // Use -sV for service detection, -T4 for faster timing
        let args = ["-sT", "-sV", "--version-light", "-T4", "-p", portList, ip]

        do {
            let result = try await ShellExecutor.shared.execute(
                path: nmapPath,
                arguments: args,
                timeout: 60.0
            )
            if result.succeeded {
                return parseNmapOutput(result.stdout)
            }
            return nil
        } catch {
            return nil
        }
    }

    private func parseNmapOutput(_ output: String) -> [PortInfo] {
        var ports: [PortInfo] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            // Parse port lines like: "80/tcp   open  http    Apache httpd"
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            guard trimmed.contains("/tcp") || trimmed.contains("/udp"),
                  trimmed.contains("open") else {
                continue
            }

            let components = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard components.count >= 3 else { continue }

            // First component is port/protocol
            let portProto = components[0].components(separatedBy: "/")
            guard portProto.count == 2,
                  let portNum = UInt16(portProto[0]) else {
                continue
            }

            let proto: PortInfo.TransportProto = portProto[1] == "udp" ? .udp : .tcp

            // Service name is typically the 3rd component (after port and state)
            let service = components.count > 2 ? components[2] : nil

            // Version info is everything after service
            var version: String? = nil
            if components.count > 3 {
                version = components[3...].joined(separator: " ")
            }

            ports.append(PortInfo(
                port: portNum,
                transportProtocol: proto,
                service: service,
                version: version
            ))
        }

        return ports
    }

    // MARK: - Socket-based scanning (fallback)

    private func scanWithSockets(ip: String, ports: [UInt16]) async -> [PortInfo] {
        var openPorts: [PortInfo] = []

        await withTaskGroup(of: PortInfo?.self) { group in
            for port in ports {
                group.addTask {
                    if await self.isPortOpen(ip: ip, port: port) {
                        return PortInfo(
                            port: port,
                            transportProtocol: .tcp,
                            service: Self.guessService(port: port),
                            version: nil
                        )
                    }
                    return nil
                }
            }

            for await result in group {
                if let portInfo = result {
                    openPorts.append(portInfo)
                }
            }
        }

        return openPorts.sorted { $0.port < $1.port }
    }

    private func isPortOpen(ip: String, port: UInt16) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = port.bigEndian
                addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)

                guard inet_pton(AF_INET, ip, &addr.sin_addr) == 1 else {
                    continuation.resume(returning: false)
                    return
                }

                let sock = socket(AF_INET, SOCK_STREAM, 0)
                guard sock >= 0 else {
                    continuation.resume(returning: false)
                    return
                }

                // Set socket timeout
                var timeout = timeval(tv_sec: 1, tv_usec: 0)
                setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

                // Try to connect
                var result: Int32 = -1
                withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        result = connect(sock, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }

                close(sock)
                continuation.resume(returning: result == 0)
            }
        }
    }

    /// Guess service name from port number
    public static func guessService(port: UInt16) -> String? {
        switch port {
        case 22: return "ssh"
        case 23: return "telnet"
        case 80: return "http"
        case 443: return "https"
        case 445: return "smb"
        case 548: return "afp"
        case 554: return "rtsp"
        case 1400: return "sonos"
        case 1883: return "mqtt"
        case 3000: return "http"
        case 3689: return "daap"
        case 5000: return "upnp"
        case 5001: return "upnp-ssl"
        case 5353: return "mdns"
        case 7000: return "airplay"
        case 8008: return "googlecast"
        case 8009: return "googlecast"
        case 8080: return "http-alt"
        case 8123: return "homeassistant"
        case 8443: return "https-alt"
        case 8883: return "mqtt-ssl"
        case 9000: return "http"
        case 9090: return "prometheus"
        case 9100: return "printing"
        case 32400: return "plex"
        case 49152...49160: return "upnp"
        default: return nil
        }
    }
}

// MARK: - Port to Smart Signal

extension PortScanner.PortInfo {
    /// Determine if this port indicates a smart device
    public var isSmartIndicator: Bool {
        switch port {
        case 554: return true   // RTSP - cameras
        case 1400: return true  // Sonos
        case 1883: return true  // MQTT - IoT
        case 7000: return true  // AirPlay
        case 8008, 8009: return true  // Google Cast
        case 8123: return true  // Home Assistant
        case 8883: return true  // MQTT SSL
        case 32400: return true // Plex
        default: return false
        }
    }

    /// Smart signal weight for this port
    public var smartWeight: Int {
        switch port {
        case 554: return 20   // RTSP - likely camera
        case 1400: return 25  // Sonos
        case 1883, 8883: return 25  // MQTT - definitely IoT
        case 7000: return 20  // AirPlay
        case 8008, 8009: return 20  // Google Cast
        case 8123: return 30  // Home Assistant
        case 32400: return 15 // Plex
        case 80, 443: return 5  // Web interface
        case 22: return 5     // SSH accessible
        default: return 0
        }
    }

    /// Inferred device type from this port
    public var inferredDeviceType: DeviceType {
        switch port {
        case 554: return .camera
        case 1400: return .speaker
        case 7000: return .smartTV
        case 8008, 8009: return .smartTV
        case 8123: return .hub
        case 32400: return .computer
        case 9100: return .printer
        default: return .unknown
        }
    }
}
