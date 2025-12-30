import Foundation

/// Orchestrates all discovery methods and maintains device list
public actor DiscoveryManager {
    public static let shared = DiscoveryManager()

    private var devices: [String: Device] = [:] // Keyed by MAC address
    private var isRunning = false

    public typealias DeviceUpdateHandler = @Sendable (Device, UpdateType) -> Void
    private var onDeviceUpdate: DeviceUpdateHandler?

    public enum UpdateType: Sendable {
        case discovered
        case updated
        case wentOffline
    }

    private init() {}

    /// Start passive discovery (mDNS + SSDP)
    public func startPassiveDiscovery(onUpdate: @escaping DeviceUpdateHandler) async {
        guard !isRunning else { return }
        isRunning = true
        onDeviceUpdate = onUpdate

        // Start mDNS listener
        await MDNSListener.shared.start { [weak self] service in
            Task { [weak self] in
                await self?.handleMDNSService(service)
            }
        }

        // Start SSDP listener
        await SSDPListener.shared.start { [weak self] device in
            Task { [weak self] in
                await self?.handleSSDPDevice(device)
            }
        }
    }

    /// Stop passive discovery
    public func stopPassiveDiscovery() async {
        isRunning = false
        await MDNSListener.shared.stop()
        await SSDPListener.shared.stop()
        await DNSSDScanner.shared.stop()
        onDeviceUpdate = nil
    }

    /// Run dns-sd based discovery (more reliable than NWBrowser)
    public func runDNSSDDiscovery(duration: TimeInterval = 5.0, onUpdate: @escaping DeviceUpdateHandler) async {
        onDeviceUpdate = onUpdate

        await DNSSDScanner.shared.browse(duration: duration) { [weak self] service in
            Task { [weak self] in
                await self?.handleDNSSDService(service)
            }
        }
    }

    /// Perform active ARP scan of a subnet
    public func scanSubnet(_ subnet: String) async throws -> [Device] {
        let entries = try await ARPScanner.shared.scanSubnet(subnet)
        var scannedDevices: [Device] = []

        for entry in entries {
            let device = await updateOrCreateDevice(
                mac: entry.mac,
                ip: entry.ip,
                source: "ARP scan"
            )
            scannedDevices.append(device)
        }

        return scannedDevices
    }

    /// Get current ARP table without active scanning
    public func getARPDevices() async throws -> [Device] {
        let entries = try await ARPScanner.shared.getARPTable()
        var scannedDevices: [Device] = []

        for entry in entries {
            let device = await updateOrCreateDevice(
                mac: entry.mac,
                ip: entry.ip,
                source: "ARP table"
            )
            scannedDevices.append(device)
        }

        return scannedDevices
    }

    /// Get all known devices
    public func getAllDevices() -> [Device] {
        Array(devices.values).sorted { $0.lastSeen > $1.lastSeen }
    }

    /// Get only devices classified as smart
    public func getSmartDevices(minScore: Int = 20) -> [Device] {
        devices.values.filter { $0.smartScore >= minScore }.sorted { $0.smartScore > $1.smartScore }
    }

    /// Get device by MAC
    public func getDevice(mac: String) -> Device? {
        devices[mac.uppercased()]
    }

    /// Scan ports for a specific device
    public func scanPorts(for mac: String, ports: [UInt16]? = nil) async -> Device? {
        guard var device = devices[mac.uppercased()] else { return nil }

        let result = await PortScanner.shared.scan(ip: device.ip, ports: ports)

        // Update device with scan results
        for portInfo in result.openPorts {
            let port = Port(
                number: Int(portInfo.port),
                protocol: portInfo.transportProtocol == .tcp ? .tcp : .udp,
                state: .open,
                serviceName: portInfo.service,
                banner: portInfo.version
            )

            if !device.openPorts.contains(port) {
                device.openPorts.append(port)
            }

            // Add smart signals for smart-indicating ports
            if portInfo.isSmartIndicator {
                let signal = SmartSignal(
                    type: .openPort,
                    description: "Port \(portInfo.port): \(portInfo.service ?? "open")",
                    weight: portInfo.smartWeight
                )
                if !device.smartSignals.contains(signal) {
                    device.smartSignals.append(signal)
                }
            }

            // Update device type if we can infer it
            if device.deviceType == .unknown && portInfo.inferredDeviceType != .unknown {
                device.deviceType = portInfo.inferredDeviceType
            }
        }

        // Recalculate smart score
        device.smartScore = calculateSmartScore(for: device)

        devices[device.mac] = device
        onDeviceUpdate?(device, .updated)

        return device
    }

    /// Quick port scan all known devices
    public func quickScanAllDevices() async {
        let deviceList = Array(devices.values)

        await withTaskGroup(of: Void.self) { group in
            for device in deviceList {
                group.addTask { [self] in
                    _ = await self.scanPorts(for: device.mac, ports: PortScanner.quickPorts)
                }
            }
        }
    }

    /// Full port scan all known devices
    public func fullScanAllDevices() async {
        let deviceList = Array(devices.values)

        await withTaskGroup(of: Void.self) { group in
            for device in deviceList {
                group.addTask { [self] in
                    _ = await self.scanPorts(for: device.mac)
                }
            }
        }
    }

    // MARK: - Private

    private func handleMDNSService(_ service: MDNSListener.MDNSService) async {
        guard let hostIP = service.hostIP else { return }

        // We need to find the MAC for this IP
        // Check ARP table
        if let entries = try? await ARPScanner.shared.getARPTable() {
            // Clean up IP (might have brackets for IPv6)
            let cleanIP = hostIP.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")

            if let entry = entries.first(where: { $0.ip == cleanIP }) {
                var device = await updateOrCreateDevice(mac: entry.mac, ip: cleanIP, source: "mDNS")

                // Add the service
                let discoveredService = DiscoveredService(
                    name: service.name,
                    type: .mdns,
                    port: service.port,
                    txt: service.txtRecords
                )

                if !device.services.contains(discoveredService) {
                    device.services.append(discoveredService)
                }

                // Add smart signal
                let signal = SmartSignal(
                    type: .mdnsService,
                    description: "mDNS: \(service.type)",
                    weight: service.smartSignalWeight
                )
                if !device.smartSignals.contains(signal) {
                    device.smartSignals.append(signal)
                }

                // Update device type if we can infer it
                if device.deviceType == .unknown {
                    device.deviceType = service.inferredDeviceType
                }

                // Recalculate smart score
                device.smartScore = calculateSmartScore(for: device)

                devices[device.mac] = device
                onDeviceUpdate?(device, .updated)
            }
        }
    }

    private func handleDNSSDService(_ service: DNSSDScanner.DNSSDService) async {
        guard let ip = service.ip else { return }

        // Find MAC for this IP from ARP table
        if let entries = try? await ARPScanner.shared.getARPTable() {
            if let entry = entries.first(where: { $0.ip == ip }) {
                var device = await updateOrCreateDevice(mac: entry.mac, ip: ip, source: "dns-sd")

                // Set hostname if we got one
                if let hostName = service.hostName, device.hostname == nil {
                    device.hostname = hostName
                }

                // Add the service
                let discoveredService = DiscoveredService(
                    name: service.name,
                    type: .mdns,
                    port: service.port,
                    txt: service.txtRecords
                )

                if !device.services.contains(discoveredService) {
                    device.services.append(discoveredService)
                }

                // Add smart signal
                let signal = SmartSignal(
                    type: .mdnsService,
                    description: "mDNS: \(service.type)",
                    weight: service.smartSignalWeight
                )
                if !device.smartSignals.contains(signal) {
                    device.smartSignals.append(signal)
                }

                // Update device type if we can infer it
                if device.deviceType == .unknown {
                    device.deviceType = service.inferredDeviceType
                }

                // Recalculate smart score
                device.smartScore = calculateSmartScore(for: device)

                devices[device.mac] = device
                onDeviceUpdate?(device, .updated)
            }
        }
    }

    private func handleSSDPDevice(_ ssdpDevice: SSDPListener.SSDPDevice) async {
        guard let hostIP = ssdpDevice.hostIP else { return }

        // Find MAC for this IP
        if let entries = try? await ARPScanner.shared.getARPTable() {
            if let entry = entries.first(where: { $0.ip == hostIP }) {
                var device = await updateOrCreateDevice(mac: entry.mac, ip: hostIP, source: "SSDP")

                // Add the service
                let discoveredService = DiscoveredService(
                    name: ssdpDevice.usn,
                    type: .ssdp,
                    port: nil,
                    txt: ["location": ssdpDevice.location, "server": ssdpDevice.server ?? ""]
                )

                if !device.services.contains(discoveredService) {
                    device.services.append(discoveredService)
                }

                // Add smart signal
                let signal = SmartSignal(
                    type: .ssdpService,
                    description: "SSDP: \(ssdpDevice.server ?? "UPnP device")",
                    weight: ssdpDevice.smartSignalWeight
                )
                if !device.smartSignals.contains(signal) {
                    device.smartSignals.append(signal)
                }

                // Update device type if we can infer it
                if device.deviceType == .unknown {
                    device.deviceType = ssdpDevice.inferredDeviceType
                }

                // Recalculate smart score
                device.smartScore = calculateSmartScore(for: device)

                devices[device.mac] = device
                onDeviceUpdate?(device, .updated)

                // Trigger UPnP fingerprinting asynchronously
                let macAddress = device.mac
                let location = ssdpDevice.location
                Task { [weak self] in
                    await self?.fetchUPnPFingerprint(mac: macAddress, locationURL: location)
                }
            }
        }
    }

    /// Fetch UPnP fingerprint for a device
    private func fetchUPnPFingerprint(mac: String, locationURL: String) async {
        guard var device = devices[mac] else { return }

        // Only fetch if we don't already have fingerprint data
        if device.fingerprint != nil { return }

        let fingerprint = await DeviceFingerprintManager.shared.quickFingerprint(
            device: device,
            locationURL: locationURL
        )

        if let fp = fingerprint {
            device.fingerprint = fp

            // Update device type from fingerprint if still unknown
            if device.deviceType == .unknown {
                device.deviceType = inferDeviceType(from: fp)
            }

            // Update hostname from friendly name if not set
            if device.hostname == nil, let friendlyName = fp.friendlyName {
                device.hostname = friendlyName
            }

            devices[mac] = device
            onDeviceUpdate?(device, .updated)
        }
    }

    /// Infer device type from fingerprint data
    private func inferDeviceType(from fingerprint: DeviceFingerprint) -> DeviceType {
        // Check Fingerbank data first
        if let parents = fingerprint.fingerbankParents {
            let combined = parents.joined(separator: " ").lowercased()
            if combined.contains("iphone") || combined.contains("android") || combined.contains("phone") {
                return .phone
            }
            if combined.contains("ipad") || combined.contains("tablet") {
                return .tablet
            }
            if combined.contains("macbook") || combined.contains("imac") || combined.contains("mac") ||
               combined.contains("windows") || combined.contains("laptop") || combined.contains("desktop") {
                return .computer
            }
            if combined.contains("roku") || combined.contains("chromecast") || combined.contains("apple tv") ||
               combined.contains("fire tv") || combined.contains("smart tv") {
                return .smartTV
            }
            if combined.contains("sonos") || combined.contains("speaker") || combined.contains("echo") ||
               combined.contains("homepod") {
                return .speaker
            }
            if combined.contains("camera") || combined.contains("ring") || combined.contains("nest cam") {
                return .camera
            }
            if combined.contains("nest") || combined.contains("thermostat") || combined.contains("ecobee") {
                return .thermostat
            }
            if combined.contains("hue") || combined.contains("light") || combined.contains("lifx") {
                return .light
            }
            if combined.contains("printer") {
                return .printer
            }
            if combined.contains("synology") || combined.contains("qnap") || combined.contains("nas") {
                return .nas
            }
            if combined.contains("router") || combined.contains("gateway") {
                return .router
            }
        }

        // Check UPnP device type
        if let upnpType = fingerprint.upnpDeviceType?.lowercased() {
            if upnpType.contains("mediarenderer") || upnpType.contains("tv") || upnpType.contains("player") {
                return .smartTV
            }
            if upnpType.contains("printer") {
                return .printer
            }
            if upnpType.contains("bridge") || upnpType.contains("hub") {
                return .hub
            }
        }

        // Check manufacturer
        if let manufacturer = fingerprint.manufacturer?.lowercased() {
            if manufacturer.contains("roku") || manufacturer.contains("samsung") || manufacturer.contains("lg") ||
               manufacturer.contains("sony") || manufacturer.contains("vizio") {
                return .smartTV
            }
            if manufacturer.contains("sonos") || manufacturer.contains("bose") {
                return .speaker
            }
            if manufacturer.contains("hp") || manufacturer.contains("canon") || manufacturer.contains("epson") ||
               manufacturer.contains("brother") {
                return .printer
            }
            if manufacturer.contains("philips") && fingerprint.modelName?.lowercased().contains("hue") == true {
                return .hub
            }
        }

        // Check mobile/tablet flags
        if fingerprint.isMobile == true {
            return .phone
        }
        if fingerprint.isTablet == true {
            return .tablet
        }

        return .unknown
    }

    private func updateOrCreateDevice(mac: String, ip: String, source: String) async -> Device {
        let normalizedMAC = mac.uppercased()

        if var existing = devices[normalizedMAC] {
            existing.ip = ip
            existing.lastSeen = Date()
            existing.isOnline = true
            devices[normalizedMAC] = existing
            return existing
        } else {
            // Look up vendor from MAC
            let vendor = MACVendorLookup.shared.lookup(mac: normalizedMAC)

            let device = Device(
                mac: normalizedMAC,
                ip: ip,
                vendor: vendor,
                firstSeen: Date(),
                lastSeen: Date(),
                isOnline: true
            )

            devices[normalizedMAC] = device
            onDeviceUpdate?(device, .discovered)
            return device
        }
    }

    private func calculateSmartScore(for device: Device) -> Int {
        var score = 0

        // Sum up signal weights
        for signal in device.smartSignals {
            score += signal.weight
        }

        // Bonus for having services
        if !device.services.isEmpty {
            score += 5
        }

        // Bonus for open ports (if we've scanned)
        score += device.openPorts.count * 5

        // Cap at 100
        return min(score, 100)
    }
}
