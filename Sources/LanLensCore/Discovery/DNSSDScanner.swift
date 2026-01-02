import Foundation
import Network

/// Uses dns-sd command-line tool for reliable mDNS/Bonjour discovery
public actor DNSSDScanner {
    public static let shared = DNSSDScanner()

    private var runningProcesses: [Process] = []
    private var discoveredServices: [String: DNSSDService] = [:]
    private var isRunning = false

    public typealias ServiceHandler = @Sendable (DNSSDService) -> Void
    private var onServiceDiscovered: ServiceHandler?

    private init() {}

    public struct DNSSDService: Sendable, Hashable {
        public let name: String
        public let type: String
        public let domain: String
        public let hostName: String?
        public let ip: String?
        public let port: Int?
        public let txtRecords: [String: String]

        public var fullType: String {
            "\(type).\(domain)"
        }
    }

    /// Service types to browse (same as MDNSListener for consistency)
    public static let smartServiceTypes: [String] = [
        "_hap._tcp",              // HomeKit Accessory Protocol
        "_homekit._tcp",          // HomeKit
        "_airplay._tcp",          // AirPlay
        "_raop._tcp",             // Remote Audio Output Protocol
        "_googlecast._tcp",       // Google Cast
        "_spotify-connect._tcp",  // Spotify Connect
        "_sonos._tcp",            // Sonos
        "_http._tcp",             // Generic HTTP
        "_https._tcp",            // Generic HTTPS
        "_ssh._tcp",              // SSH
        "_smb._tcp",              // SMB
        "_afpovertcp._tcp",       // AFP
        "_printer._tcp",          // Printers
        "_ipp._tcp",              // IPP
        "_scanner._tcp",          // Scanners
        "_mqtt._tcp",             // MQTT
        "_hue._tcp",              // Philips Hue
        "_bond._tcp",             // Bond Home
        "_leap._tcp",             // Lutron
        "_ecobee._tcp",           // Ecobee
        "_nest._tcp",             // Nest
        "_amzn-wplay._tcp",       // Amazon
        "_alexa._tcp",            // Alexa
        "_dacp._tcp",             // DACP
        "_touch-able._tcp",       // Apple Remote
        "_companion-link._tcp",   // Companion Link
        "_device-info._tcp",      // Device Info
    ]

    /// Browse for services using dns-sd command
    public func browse(serviceTypes: [String]? = nil, duration: TimeInterval = 5.0, onDiscovered: @escaping ServiceHandler) async {
        guard !isRunning else { return }
        isRunning = true
        onServiceDiscovered = onDiscovered
        discoveredServices.removeAll()

        let types = serviceTypes ?? Self.smartServiceTypes

        // Run dns-sd -B for each service type concurrently
        await withTaskGroup(of: Void.self) { group in
            for serviceType in types {
                group.addTask { [self] in
                    await self.browseServiceType(serviceType, duration: duration)
                }
            }
        }

        isRunning = false
    }

    /// Quick browse - get results fast
    public func quickBrowse(duration: TimeInterval = 3.0) async -> [DNSSDService] {
        // Use actor-isolated collection via wrapper
        let collector = ServiceCollector()

        await browse(duration: duration) { service in
            Task { @MainActor in
                await collector.add(service)
            }
        }

        return await collector.getAll()
    }

    /// Stop all running dns-sd processes
    public func stop() {
        isRunning = false
        for process in runningProcesses {
            if process.isRunning {
                process.terminate()
            }
        }
        runningProcesses.removeAll()
        onServiceDiscovered = nil
    }

    private func browseServiceType(_ serviceType: String, duration: TimeInterval) async {
        // First, browse for instances of this service type
        let browseOutput = await runDNSSD(["-B", serviceType, "local."], timeout: duration)
        let instances = parseBrowseOutput(browseOutput, serviceType: serviceType)

        // Then resolve each instance to get IP and port
        for instance in instances {
            if let resolved = await resolveService(name: instance.name, type: serviceType) {
                let key = "\(resolved.name).\(resolved.type)"
                if discoveredServices[key] == nil {
                    discoveredServices[key] = resolved
                    onServiceDiscovered?(resolved)
                }
            }
        }
    }

    private func resolveService(name: String, type: String) async -> DNSSDService? {
        // Check if name contains problematic characters for dns-sd command
        // Include both straight and curly/smart apostrophes and quotes
        let hasProblematicChars = name.contains("'") ||  // straight apostrophe (U+0027)
                                  name.contains("\u{2019}") ||  // right single quote - curly apostrophe
                                  name.contains("\u{2018}") ||  // left single quote
                                  name.contains("\"") || // straight double quote
                                  name.contains("\u{201C}") ||  // left double quote
                                  name.contains("\u{201D}") ||  // right double quote
                                  name.contains("\\")

        Log.info("DNSSDScanner.resolveService: name='\(name)' hasProblematicChars=\(hasProblematicChars)", category: .mdns)

        if hasProblematicChars {
            // Use NWConnection for names with special characters
            Log.info("DNSSDScanner: Using NWConnection for '\(name)' (has special chars)", category: .mdns)
            return await resolveServiceViaNWConnection(name: name, type: type)
        }

        // Try dns-sd -L first for lookup service details
        let lookupOutput = await runDNSSD(["-L", name, type, "local."], timeout: 2.0)

        // If lookup failed or returned no results, fallback to NWConnection
        guard let (hostName, port, txtRecords) = parseLookupOutput(lookupOutput), hostName != nil else {
            Log.debug("dns-sd -L failed for '\(name)', trying NWConnection", category: .mdns)
            return await resolveServiceViaNWConnection(name: name, type: type)
        }

        // dns-sd -G to get IP from hostname
        var ip: String? = nil
        if let hostName = hostName {
            let queryOutput = await runDNSSD(["-G", "v4", hostName], timeout: 2.0)
            ip = parseQueryOutput(queryOutput)
        }

        return DNSSDService(
            name: name,
            type: type,
            domain: "local.",
            hostName: hostName,
            ip: ip,
            port: port,
            txtRecords: txtRecords
        )
    }

    /// Resolve service using NWConnection (handles special characters in names)
    private func resolveServiceViaNWConnection(name: String, type: String) async -> DNSSDService? {
        Log.debug("NWConnection: Resolving '\(name)' type '\(type)'", category: .mdns)

        let endpoint = NWEndpoint.service(name: name, type: type, domain: "local.", interface: nil)
        let connection = NWConnection(to: endpoint, using: .tcp)

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<(ip: String?, port: Int?, hostname: String?), Never>) in
            // Use nonisolated(unsafe) for the mutable flag variable
            // This is safe because we synchronize access via NSLock
            nonisolated(unsafe) var resumed = false
            let lock = NSLock()

            connection.stateUpdateHandler = { state in
                lock.lock()
                guard !resumed else {
                    lock.unlock()
                    return
                }

                switch state {
                case .ready:
                    // Try to get the resolved IP from the path's gateways or local/remote endpoints
                    if let path = connection.currentPath {
                        // Check remoteEndpoint
                        if let remoteEndpoint = path.remoteEndpoint {
                            switch remoteEndpoint {
                            case .hostPort(let host, let port):
                                var ip: String? = nil
                                var hostname: String? = nil

                                switch host {
                                case .ipv4(let addr):
                                    // Strip interface suffix (e.g., "192.168.0.31%en0" -> "192.168.0.31")
                                    let addrStr = "\(addr)"
                                    var cleanedAddr: String
                                    if let percentIndex = addrStr.firstIndex(of: "%") {
                                        cleanedAddr = String(addrStr[..<percentIndex])
                                    } else {
                                        cleanedAddr = addrStr
                                    }
                                    // Validate the IP - filter multicast, loopback, etc.
                                    if IPAddressValidator.isValidDeviceIP(cleanedAddr) {
                                        ip = cleanedAddr
                                    } else if let reason = IPAddressValidator.invalidReason(for: cleanedAddr) {
                                        Log.debug("NWConnection: Filtered invalid IPv4: \(cleanedAddr) (\(reason))", category: .mdns)
                                    }
                                case .ipv6(let addr):
                                    var addrStr = "\(addr)"
                                    // Strip interface suffix
                                    if let percentIndex = addrStr.firstIndex(of: "%") {
                                        addrStr = String(addrStr[..<percentIndex])
                                    }
                                    // Validate the IP - handles loopback and multicast
                                    if IPAddressValidator.isValidDeviceIP(addrStr) {
                                        // Still skip link-local IPv6 for device identification, prefer IPv4
                                        if IPAddressValidator.isLinkLocalIPv6(addrStr) {
                                            Log.debug("NWConnection: Got link-local IPv6, will try hostname lookup", category: .mdns)
                                        } else {
                                            ip = addrStr
                                        }
                                    } else if let reason = IPAddressValidator.invalidReason(for: addrStr) {
                                        Log.debug("NWConnection: Filtered invalid IPv6: \(addrStr) (\(reason))", category: .mdns)
                                    }
                                case .name(let name, _):
                                    hostname = name
                                @unknown default:
                                    break
                                }

                                Log.debug("NWConnection: Got host=\(host) ip=\(ip ?? "nil") hostname=\(hostname ?? "nil") port=\(port.rawValue)", category: .mdns)

                                resumed = true
                                lock.unlock()
                                connection.cancel()
                                continuation.resume(returning: (ip, Int(port.rawValue), hostname))
                                return

                            default:
                                Log.debug("NWConnection: remoteEndpoint is not hostPort: \(remoteEndpoint)", category: .mdns)
                            }
                        }
                    }

                    Log.debug("NWConnection: Ready but no usable endpoint for '\(name)'", category: .mdns)
                    resumed = true
                    lock.unlock()
                    connection.cancel()
                    continuation.resume(returning: (nil, nil, nil))

                case .failed(let error):
                    Log.debug("NWConnection: Failed for '\(name)': \(error)", category: .mdns)
                    resumed = true
                    lock.unlock()
                    continuation.resume(returning: (nil, nil, nil))

                case .cancelled:
                    resumed = true
                    lock.unlock()
                    continuation.resume(returning: (nil, nil, nil))

                case .waiting(let error):
                    Log.debug("NWConnection: Waiting for '\(name)': \(error)", category: .mdns)
                    lock.unlock()

                default:
                    lock.unlock()
                }
            }

            connection.start(queue: .global(qos: .utility))

            // Timeout after 3 seconds
            DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
                lock.lock()
                if !resumed {
                    Log.debug("NWConnection: Timeout for '\(name)'", category: .mdns)
                    resumed = true
                    lock.unlock()
                    connection.cancel()
                    continuation.resume(returning: (nil, nil, nil))
                } else {
                    lock.unlock()
                }
            }
        }

        // If we got a hostname but no IP, try to resolve it via dns-sd -G
        var finalIP = result.ip
        if finalIP == nil, let hostname = result.hostname {
            Log.debug("NWConnection: Resolving hostname '\(hostname)' to IP", category: .mdns)
            let queryOutput = await runDNSSD(["-G", "v4", hostname], timeout: 2.0)
            finalIP = parseQueryOutput(queryOutput)
            Log.debug("NWConnection: Resolved '\(hostname)' to IP: \(finalIP ?? "nil")", category: .mdns)
        }

        // If still no IP, try to derive hostname from service name and resolve
        // e.g., "Mara's MacBook Air" -> "Maras-MacBook-Air.local"
        if finalIP == nil {
            let derivedHostname = deriveHostnameFromServiceName(name)
            Log.debug("NWConnection: Trying derived hostname '\(derivedHostname)' for '\(name)'", category: .mdns)
            let queryOutput = await runDNSSD(["-G", "v4", derivedHostname], timeout: 2.0)
            finalIP = parseQueryOutput(queryOutput)
            if finalIP != nil {
                Log.info("NWConnection: Resolved derived hostname '\(derivedHostname)' to IP: \(finalIP!)", category: .mdns)
            }
        }

        Log.info("NWConnection: Final result for '\(name)': ip=\(finalIP ?? "nil") port=\(result.port.map { String($0) } ?? "nil")", category: .mdns)

        return DNSSDService(
            name: name,
            type: type,
            domain: "local.",
            hostName: result.hostname,
            ip: finalIP,
            port: result.port,
            txtRecords: [:]
        )
    }

    private func runDNSSD(_ args: [String], timeout: TimeInterval) async -> String {
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/dns-sd")
            process.arguments = args

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            // Use nonisolated(unsafe) for the mutable output variable
            // This is safe because we synchronize access via process.waitUntilExit()
            nonisolated(unsafe) var output = ""
            let lock = NSLock()

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if let str = String(data: data, encoding: .utf8) {
                    lock.lock()
                    output += str
                    lock.unlock()
                }
            }

            do {
                try process.run()

                // dns-sd runs until killed, so we set a timeout
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if process.isRunning {
                        process.terminate()
                    }
                }

                process.waitUntilExit()
                pipe.fileHandleForReading.readabilityHandler = nil

                // Read any remaining data
                if let remaining = try? pipe.fileHandleForReading.readToEnd(),
                   let str = String(data: remaining, encoding: .utf8) {
                    lock.lock()
                    output += str
                    lock.unlock()
                }

                lock.lock()
                let result = output
                lock.unlock()
                continuation.resume(returning: result)
            } catch {
                continuation.resume(returning: "")
            }
        }
    }

    /// Parse dns-sd -B output
    /// Format: Timestamp  A/R    Flags  if Domain  Service Type  Instance Name
    private func parseBrowseOutput(_ output: String, serviceType: String) -> [(name: String, domain: String)] {
        var results: [(name: String, domain: String)] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            // Skip header lines and empty lines
            guard !line.isEmpty,
                  !line.contains("Browsing for"),
                  !line.contains("DATE:"),
                  !line.contains("Timestamp"),
                  line.contains("Add") || line.contains("Rmv") else {
                continue
            }

            // Parse the line - format varies but instance name is at the end
            // Example: "12:34:56.789  Add        2   4 local.               _http._tcp.          My Device"
            let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

            // Need at least: timestamp, action, flags, interface, domain, type, name
            guard components.count >= 7 else { continue }

            // Instance name is everything after the service type
            if let typeIndex = components.firstIndex(where: { $0.contains(serviceType) || $0.contains("_tcp.") || $0.contains("_udp.") }) {
                let nameComponents = components[(typeIndex + 1)...]
                let name = nameComponents.joined(separator: " ")
                if !name.isEmpty {
                    results.append((name: name, domain: "local."))
                }
            }
        }

        return results
    }

    /// Parse dns-sd -L output
    /// Returns: (hostname, port, txtRecords)
    private func parseLookupOutput(_ output: String) -> (String?, Int?, [String: String])? {
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            // Look for the resolution line
            // Format: "12:34:56.789  MyDevice._http._tcp.local. can be reached at mydevice.local.:80 (interface 4)"
            if line.contains("can be reached at") {
                // Extract hostname and port
                if let reachRange = line.range(of: "can be reached at ") {
                    let afterReach = String(line[reachRange.upperBound...])
                    // Format: "hostname.local.:port (interface X)"
                    let parts = afterReach.components(separatedBy: " ")
                    if let hostPort = parts.first {
                        // Split hostname:port
                        let hostPortParts = hostPort.components(separatedBy: ":")
                        if hostPortParts.count >= 2 {
                            let host = hostPortParts[0]
                            let portStr = hostPortParts[1].trimmingCharacters(in: CharacterSet(charactersIn: "0123456789").inverted)
                            let port = Int(portStr)
                            return (host, port, [:])
                        }
                    }
                }
            }
        }

        return nil
    }

    /// Derive a hostname from a service name
    /// e.g., "Mara's MacBook Air" -> "Maras-MacBook-Air.local"
    /// This is how macOS typically converts display names to hostnames
    private func deriveHostnameFromServiceName(_ name: String) -> String {
        var hostname = name

        // Handle prefixed names like "0E5F46A40FBE@Ovidiu's MacBook Pro"
        if let atIndex = hostname.firstIndex(of: "@") {
            hostname = String(hostname[hostname.index(after: atIndex)...])
        }

        // Remove apostrophes (both straight and curly)
        hostname = hostname.replacingOccurrences(of: "'", with: "")
        hostname = hostname.replacingOccurrences(of: "\u{2019}", with: "")
        hostname = hostname.replacingOccurrences(of: "\u{2018}", with: "")

        // Replace spaces with hyphens
        hostname = hostname.replacingOccurrences(of: " ", with: "-")

        // Remove any other special characters that aren't alphanumeric or hyphen
        hostname = hostname.filter { $0.isLetter || $0.isNumber || $0 == "-" }

        // Add .local suffix
        if !hostname.hasSuffix(".local") {
            hostname += ".local"
        }

        return hostname
    }

    /// Parse dns-sd -G output to get IP address
    private func parseQueryOutput(_ output: String) -> String? {
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            // Look for A record response - actual format from dns-sd -G v4:
            // "Timestamp     A/R  Flags         IF  Hostname                               Address                                      TTL"
            // "14:57:04.161  Add  40000002      14  Ovidius-MacBook-Pro.local.             192.168.0.31                                 4500"
            // The IP address is in the second-to-last column before TTL

            // Skip header line and empty lines
            if line.contains("Add") && !line.contains("Timestamp") && !line.contains("A/R") {
                let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                // Format: [Timestamp, Add, Flags, IF, Hostname, Address, TTL]
                // Minimum 6 components needed, IP is at index count-2 (before TTL)
                if components.count >= 6 {
                    // Try second-to-last column (before TTL)
                    let potentialIP = components[components.count - 2]
                    // Validate it's an IPv4 address pattern
                    if potentialIP.range(of: #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"#, options: .regularExpression) != nil {
                        // Validate it's a valid device IP (not multicast, loopback, etc.)
                        if IPAddressValidator.isValidDeviceIP(potentialIP) {
                            return potentialIP
                        } else if let reason = IPAddressValidator.invalidReason(for: potentialIP) {
                            Log.debug("dns-sd: Filtered invalid IP from query output: \(potentialIP) (\(reason))", category: .mdns)
                        }
                    }
                }
            }

            // Also check for legacy format with "Addr" keyword just in case
            if line.contains("Addr") {
                let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if let addrIndex = components.firstIndex(of: "Addr"),
                   addrIndex + 1 < components.count {
                    let ip = components[addrIndex + 1]
                    if IPAddressValidator.isValidDeviceIP(ip) {
                        return ip
                    } else if let reason = IPAddressValidator.invalidReason(for: ip) {
                        Log.debug("dns-sd: Filtered invalid IP from query output: \(ip) (\(reason))", category: .mdns)
                    }
                }
            }
        }

        return nil
    }
}

// MARK: - Service Classification

// MARK: - Service Collector (Thread-safe helper for quickBrowse)

private actor ServiceCollector {
    private var services: [DNSSDScanner.DNSSDService] = []

    func add(_ service: DNSSDScanner.DNSSDService) {
        services.append(service)
    }

    func getAll() -> [DNSSDScanner.DNSSDService] {
        return services
    }
}

extension DNSSDScanner.DNSSDService {
    /// Infer device type from service type
    public var inferredDeviceType: DeviceType {
        switch type {
        case "_hap._tcp", "_homekit._tcp":
            return .hub
        case "_airplay._tcp", "_raop._tcp":
            return .smartTV
        case "_googlecast._tcp":
            return .smartTV
        case "_spotify-connect._tcp", "_sonos._tcp":
            return .speaker
        case "_printer._tcp", "_ipp._tcp":
            return .printer
        case "_scanner._tcp":
            return .printer
        case "_hue._tcp":
            return .light
        case "_ecobee._tcp", "_nest._tcp":
            return .thermostat
        case "_amzn-wplay._tcp", "_alexa._tcp":
            return .speaker
        case "_ssh._tcp", "_smb._tcp", "_afpovertcp._tcp":
            return .computer
        default:
            return .unknown
        }
    }

    /// Smart signal weight for this service type
    public var smartSignalWeight: Int {
        switch type {
        case "_hap._tcp", "_homekit._tcp":
            return 30
        case "_googlecast._tcp", "_airplay._tcp":
            return 25
        case "_mqtt._tcp":
            return 25
        case "_http._tcp", "_https._tcp":
            return 15
        case "_ssh._tcp":
            return 10
        default:
            return 10
        }
    }
}
