import Foundation
import Network

/// Listens for SSDP (Simple Service Discovery Protocol) announcements
/// Used by UPnP devices to advertise themselves
public actor SSDPListener {
    public static let shared = SSDPListener()

    private static let multicastGroup = "239.255.255.250"
    private static let ssdpPort: UInt16 = 1900

    private var listener: NWListener?
    private var connection: NWConnection?
    private var discoveredDevices: [String: SSDPDevice] = [:]
    private var isRunning = false

    public typealias DeviceHandler = @Sendable (SSDPDevice) -> Void
    private var onDeviceDiscovered: DeviceHandler?

    private init() {}

    public struct SSDPDevice: Sendable {
        public let usn: String           // Unique Service Name
        public let location: String      // URL to device description
        public let server: String?       // Server header
        public let st: String?           // Search Target
        public let hostIP: String?       // Extracted from location
        public let headers: [String: String]

        public init(usn: String, location: String, server: String?, st: String?, hostIP: String?, headers: [String: String]) {
            self.usn = usn
            self.location = location
            self.server = server
            self.st = st
            self.hostIP = hostIP
            self.headers = headers
        }
    }

    /// Start listening for SSDP announcements
    public func start(onDiscovered: @escaping DeviceHandler) {
        guard !isRunning else { return }
        isRunning = true
        onDeviceDiscovered = onDiscovered

        // Start passive listening
        startListening()

        // Also send M-SEARCH to discover existing devices
        Task {
            await sendMSearch()
        }
    }

    /// Stop listening
    public func stop() {
        isRunning = false
        listener?.cancel()
        listener = nil
        connection?.cancel()
        connection = nil
        onDeviceDiscovered = nil
    }

    /// Get all discovered devices
    public func getDiscoveredDevices() -> [SSDPDevice] {
        Array(discoveredDevices.values)
    }

    /// Send M-SEARCH to discover devices
    public func sendMSearch() async {
        let searchMessage = """
        M-SEARCH * HTTP/1.1\r
        HOST: \(Self.multicastGroup):\(Self.ssdpPort)\r
        MAN: "ssdp:discover"\r
        MX: 3\r
        ST: ssdp:all\r
        \r

        """

        // Create UDP connection to multicast group
        let host = NWEndpoint.Host(Self.multicastGroup)
        let port = NWEndpoint.Port(rawValue: Self.ssdpPort)!

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        let connection = NWConnection(host: host, port: port, using: params)

        connection.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                switch state {
                case .ready:
                    if let data = searchMessage.data(using: .utf8) {
                        connection.send(content: data, completion: .contentProcessed { _ in })
                    }

                    // Receive responses
                    await self?.receiveResponses(on: connection)
                default:
                    break
                }
            }
        }

        connection.start(queue: .global(qos: .utility))
        self.connection = connection

        // Let it run for a few seconds to collect responses
        try? await Task.sleep(for: .seconds(5))
    }

    private func startListening() {
        do {
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true

            // Join multicast group
            if let multicast = try? NWMulticastGroup(for: [
                .hostPort(host: NWEndpoint.Host(Self.multicastGroup), port: NWEndpoint.Port(rawValue: Self.ssdpPort)!)
            ]) {
                let group = NWConnectionGroup(with: multicast, using: params)

                group.setReceiveHandler(maximumMessageSize: 2048, rejectOversizedMessages: true) { [weak self] message, content, isComplete in
                    Task { [weak self] in
                        if let content = content, let text = String(data: content, encoding: .utf8) {
                            await self?.handleSSDPMessage(text, from: nil)
                        }
                    }
                }

                group.stateUpdateHandler = { state in
                    // Handle state changes if needed
                }

                group.start(queue: .global(qos: .utility))
            }
        } catch {
            print("Failed to start SSDP listener: \(error)")
        }
    }

    private func receiveResponses(on connection: NWConnection) async {
        // Keep receiving for a while
        for _ in 0..<50 {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 2048) { [weak self] content, _, _, error in
                    if let content = content, let text = String(data: content, encoding: .utf8) {
                        Task { [weak self] in
                            await self?.handleSSDPMessage(text, from: nil)
                        }
                    }
                    continuation.resume()
                }
            }

            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func handleSSDPMessage(_ message: String, from endpoint: NWEndpoint?) {
        // Parse SSDP headers
        var headers: [String: String] = [:]
        let lines = message.components(separatedBy: "\r\n")

        for line in lines {
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces).uppercased()
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        guard let location = headers["LOCATION"],
              let usn = headers["USN"] else {
            return
        }

        // Extract IP from location URL
        var hostIP: String? = nil
        if let url = URL(string: location), let host = url.host {
            hostIP = host
        }

        let device = SSDPDevice(
            usn: usn,
            location: location,
            server: headers["SERVER"],
            st: headers["ST"],
            hostIP: hostIP,
            headers: headers
        )

        if discoveredDevices[usn] == nil {
            print("[SSDP] New device discovered:")
            print("[SSDP]   - USN: \(usn)")
            print("[SSDP]   - Location: \(location)")
            print("[SSDP]   - Server: \(headers["SERVER"] ?? "unknown")")
            print("[SSDP]   - Host IP: \(hostIP ?? "unknown")")
            discoveredDevices[usn] = device
            onDeviceDiscovered?(device)
        }
    }
}

// MARK: - Device Classification

extension SSDPListener.SSDPDevice {
    /// Infer device type from SSDP data
    public var inferredDeviceType: DeviceType {
        let serverLower = server?.lowercased() ?? ""
        let usnLower = usn.lowercased()
        let stLower = st?.lowercased() ?? ""

        if serverLower.contains("roku") {
            return .smartTV
        }
        if serverLower.contains("samsung") || serverLower.contains("lg") || serverLower.contains("sony") {
            return .smartTV
        }
        if serverLower.contains("sonos") || usnLower.contains("sonos") {
            return .speaker
        }
        if serverLower.contains("philips-hue") || usnLower.contains("hue") {
            return .hub
        }
        if stLower.contains("printer") || serverLower.contains("printer") {
            return .printer
        }
        if stLower.contains("mediaserver") || stLower.contains("mediarenderer") {
            return .smartTV
        }
        if serverLower.contains("synology") || serverLower.contains("qnap") {
            return .nas
        }

        return .unknown
    }

    /// Smart signal weight
    public var smartSignalWeight: Int {
        // SSDP presence is a strong indicator of a smart device
        20
    }
}
