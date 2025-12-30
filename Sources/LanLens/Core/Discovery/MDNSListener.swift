import Foundation
import Network

/// Listens for mDNS/Bonjour service advertisements
public actor MDNSListener {
    public static let shared = MDNSListener()

    private var browsers: [NWBrowser] = []
    private var discoveredServices: [String: MDNSService] = [:]
    private var isRunning = false

    public typealias ServiceHandler = @Sendable (MDNSService) -> Void
    private var onServiceDiscovered: ServiceHandler?

    private init() {}

    public struct MDNSService: Sendable {
        public let name: String
        public let type: String
        public let domain: String
        public let hostIP: String?
        public let port: Int?
        public let txtRecords: [String: String]

        public var fullType: String {
            "\(type).\(domain)"
        }
    }

    /// Common smart device service types to browse
    public static let smartServiceTypes: [String] = [
        "_hap._tcp",              // HomeKit Accessory Protocol
        "_homekit._tcp",          // HomeKit
        "_airplay._tcp",          // AirPlay
        "_raop._tcp",             // Remote Audio Output Protocol (AirPlay audio)
        "_googlecast._tcp",       // Google Cast / Chromecast
        "_spotify-connect._tcp",  // Spotify Connect
        "_sonos._tcp",            // Sonos
        "_http._tcp",             // Generic HTTP (many smart devices)
        "_https._tcp",            // Generic HTTPS
        "_ssh._tcp",              // SSH
        "_smb._tcp",              // SMB file sharing
        "_afpovertcp._tcp",       // AFP (Apple File Protocol)
        "_printer._tcp",          // Printers
        "_ipp._tcp",              // Internet Printing Protocol
        "_scanner._tcp",          // Scanners
        "_mqtt._tcp",             // MQTT (IoT messaging)
        "_coap._udp",             // CoAP (IoT protocol)
        "_hue._tcp",              // Philips Hue
        "_bond._tcp",             // Bond Home (fans, shades)
        "_leap._tcp",             // Lutron
        "_ecobee._tcp",           // Ecobee thermostats
        "_nest._tcp",             // Nest devices
        "_amzn-wplay._tcp",       // Amazon devices
        "_alexa._tcp",            // Alexa
        "_dacp._tcp",             // Digital Audio Control Protocol
        "_touch-able._tcp",       // Apple Remote
        "_companion-link._tcp",   // Apple Companion
        "_sleep-proxy._udp",      // Sleep Proxy
        "_device-info._tcp",      // Device info
    ]

    /// Start browsing for services
    public func start(serviceTypes: [String]? = nil, onDiscovered: @escaping ServiceHandler) async {
        guard !isRunning else {
            print("[mDNS] Already running, skipping start")
            return
        }
        print("[mDNS] Starting mDNS browser...")
        isRunning = true
        onServiceDiscovered = onDiscovered

        let types = serviceTypes ?? Self.smartServiceTypes
        print("[mDNS] Browsing for \(types.count) service types...")

        for serviceType in types {
            startBrowser(for: serviceType)
        }
        print("[mDNS] All browsers started")
    }

    /// Stop all browsers
    public func stop() {
        isRunning = false
        for browser in browsers {
            browser.cancel()
        }
        browsers.removeAll()
        onServiceDiscovered = nil
    }

    /// Get all discovered services
    public func getDiscoveredServices() -> [MDNSService] {
        Array(discoveredServices.values)
    }

    private func startBrowser(for serviceType: String) {
        let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: "local.")
        let browser = NWBrowser(for: descriptor, using: .tcp)

        browser.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                await self?.handleBrowserState(state, type: serviceType)
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, changes in
            Task { [weak self] in
                await self?.handleBrowseResults(results, changes: changes, type: serviceType)
            }
        }

        browser.start(queue: .global(qos: .utility))
        browsers.append(browser)
    }

    private func handleBrowserState(_ state: NWBrowser.State, type: String) {
        switch state {
        case .ready:
            break // Browsing
        case .failed(let error):
            print("mDNS browser failed for \(type): \(error)")
        case .cancelled:
            break
        default:
            break
        }
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>, type: String) {
        for result in results {
            switch result.endpoint {
            case .service(let name, let serviceType, let domain, _):
                let key = "\(name).\(serviceType).\(domain)"

                if discoveredServices[key] == nil {
                    // Resolve to get more details
                    Task {
                        await resolveService(name: name, type: serviceType, domain: domain)
                    }
                }
            default:
                break
            }
        }
    }

    private func resolveService(name: String, type: String, domain: String) async {
        // Use NWConnection to resolve the service
        let endpoint = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)
        let connection = NWConnection(to: endpoint, using: .tcp)

        // Quick timeout - we just want to resolve, not connect
        let resolveTask = Task { () -> (String?, Int?) in
            await withCheckedContinuation { continuation in
                var resumed = false

                connection.stateUpdateHandler = { state in
                    guard !resumed else { return }

                    switch state {
                    case .ready:
                        if let endpoint = connection.currentPath?.remoteEndpoint {
                            switch endpoint {
                            case .hostPort(let host, let port):
                                resumed = true
                                continuation.resume(returning: (host.debugDescription, Int(port.rawValue)))
                            default:
                                break
                            }
                        }
                        connection.cancel()
                    case .failed, .cancelled:
                        if !resumed {
                            resumed = true
                            continuation.resume(returning: (nil, nil))
                        }
                    default:
                        break
                    }
                }

                connection.start(queue: .global(qos: .utility))

                // Timeout after 2 seconds
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    if !resumed {
                        resumed = true
                        connection.cancel()
                        continuation.resume(returning: (nil, nil))
                    }
                }
            }
        }

        let (hostIP, port) = await resolveTask.value

        let service = MDNSService(
            name: name,
            type: type,
            domain: domain,
            hostIP: hostIP,
            port: port,
            txtRecords: [:] // TXT records would require dns-sd command for full parsing
        )

        let key = "\(name).\(type).\(domain)"
        discoveredServices[key] = service
        onServiceDiscovered?(service)
    }
}

// MARK: - Service Classification

extension MDNSListener.MDNSService {
    /// Infer device type from service type
    public var inferredDeviceType: DeviceType {
        switch type {
        case "_hap._tcp", "_homekit._tcp":
            return .hub // Could be various HomeKit devices
        case "_airplay._tcp", "_raop._tcp":
            return .smartTV // Usually Apple TV or speakers
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
            return 30 // Definitely smart
        case "_googlecast._tcp", "_airplay._tcp":
            return 25
        case "_mqtt._tcp", "_coap._udp":
            return 25 // IoT protocols
        case "_http._tcp", "_https._tcp":
            return 15 // Many things have HTTP
        case "_ssh._tcp":
            return 10
        default:
            return 10
        }
    }
}
