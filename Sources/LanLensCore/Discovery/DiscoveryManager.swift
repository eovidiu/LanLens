import Foundation
import os.log

private let logger = Logger(subsystem: "com.lanlens.core", category: "DiscoveryManager")

// Debug log to file for tracing
private func debugLog(_ message: String) {
    let logPath = "/tmp/lanlens_debug.log"
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logPath) {
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: URL(fileURLWithPath: logPath))
        }
    }
}

/// Orchestrates all discovery methods and maintains device list
public actor DiscoveryManager {
    public static let shared = DiscoveryManager()

    private var devices: [String: Device] = [:] // Keyed by MAC address
    private var isRunning = false

    public typealias DeviceUpdateHandler = @Sendable (Device, UpdateType) -> Void
    private var onDeviceUpdate: DeviceUpdateHandler?

    /// Fingerbank API key for device identification (set from app preferences)
    private var fingerbankAPIKey: String?

    public enum UpdateType: Sendable {
        case discovered
        case updated
        case wentOffline
    }

    private init() {}

    /// Configure Fingerbank API key for device identification
    public func setFingerbankAPIKey(_ key: String?) {
        self.fingerbankAPIKey = key
        debugLog("Fingerbank API key \(key != nil ? "configured" : "cleared")")
    }

    /// Start passive discovery (mDNS + SSDP)
    public func startPassiveDiscovery(onUpdate: @escaping DeviceUpdateHandler) async {
        guard !isRunning else {
            debugLog("Passive discovery already running, skipping")
            return
        }
        debugLog("Starting passive discovery (mDNS + SSDP)...")
        isRunning = true
        onDeviceUpdate = onUpdate

        // Start mDNS listener
        debugLog("Starting mDNS listener...")
        await MDNSListener.shared.start { [weak self] service in
            Task { [weak self] in
                await self?.handleMDNSService(service)
            }
        }

        // Start SSDP listener
        debugLog("Starting SSDP listener...")
        await SSDPListener.shared.start { [weak self] device in
            debugLog("SSDP callback triggered for device at \(device.hostIP ?? "unknown")")
            Task { [weak self] in
                await self?.handleSSDPDevice(device)
            }
        }
        debugLog("Passive discovery started successfully")
    }

    /// Stop passive discovery
    /// Note: onDeviceUpdate is NOT cleared here to allow in-flight fingerprint fetches to complete
    /// Call clearUpdateHandler() when fully done with scanning
    public func stopPassiveDiscovery() async {
        isRunning = false
        await MDNSListener.shared.stop()
        await SSDPListener.shared.stop()
        await DNSSDScanner.shared.stop()
        // Allow a brief moment for in-flight fingerprint fetches to complete
        try? await Task.sleep(for: .milliseconds(500))
    }

    /// Clear the device update handler - call when fully done with scanning
    public func clearUpdateHandler() {
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
        var macAddresses: [String] = []

        for entry in entries {
            let device = await updateOrCreateDevice(
                mac: entry.mac,
                ip: entry.ip,
                source: "ARP table"
            )
            macAddresses.append(device.mac)
        }

        // Fingerprint devices that don't have fingerprint data yet (using Fingerbank MAC lookup)
        if fingerbankAPIKey != nil {
            await fingerprintARPDevices(macAddresses)
        }

        // Return updated devices from internal storage (includes fingerprint data)
        return macAddresses.compactMap { devices[$0] }
    }

    /// Fingerprint ARP devices using Fingerbank MAC lookup (no UPnP location needed)
    private func fingerprintARPDevices(_ macAddresses: [String]) async {
        // Only fingerprint devices that don't already have fingerprint data
        let macsNeedingFingerprint = macAddresses.filter { mac in
            guard let existingDevice = devices[mac] else { return true }
            return existingDevice.fingerprint == nil
        }

        guard !macsNeedingFingerprint.isEmpty else { return }

        debugLog("Fingerprinting \(macsNeedingFingerprint.count) ARP devices via Fingerbank...")

        // Process devices
        for mac in macsNeedingFingerprint {
            await fingerprintDeviceWithFingerbankOnly(mac: mac)
        }
    }

    /// Fingerprint a device using only Fingerbank (MAC lookup, no UPnP)
    private func fingerprintDeviceWithFingerbankOnly(mac: String) async {
        guard var device = devices[mac] else { return }

        // Skip if already has fingerprint
        guard device.fingerprint == nil else { return }

        guard let apiKey = fingerbankAPIKey, !apiKey.isEmpty else { return }

        debugLog("Fingerbank lookup for ARP device: \(mac)")

        let fingerprint = await DeviceFingerprintManager.shared.fingerprintDevice(
            device: device,
            locationURL: nil,  // No UPnP location for ARP-only devices
            fingerbankAPIKey: apiKey
        )

        if let fp = fingerprint {
            debugLog("Fingerbank result for \(mac): \(fp.fingerbankDeviceName ?? "unknown")")

            device.fingerprint = fp

            // Update device type from fingerprint if still unknown
            if device.deviceType == .unknown {
                let inferredType = inferDeviceType(from: fp)
                device.deviceType = inferredType
            }

            devices[mac] = device
            onDeviceUpdate?(device, .updated)
        }
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
        guard let ip = service.ip else {
            logger.debug("DNS-SD: No IP for service \(service.name), skipping")
            return
        }

        logger.info("DNS-SD: Processing service \(service.name) at \(ip)")
        logger.debug("DNS-SD: hostname=\(service.hostName ?? "nil") type=\(service.type)")

        // Find MAC for this IP from ARP table
        if let entries = try? await ARPScanner.shared.getARPTable() {
            if let entry = entries.first(where: { $0.ip == ip }) {
                logger.info("DNS-SD: Found MAC \(entry.mac) for IP \(ip)")
                var device = await updateOrCreateDevice(mac: entry.mac, ip: ip, source: "dns-sd")

                // Set hostname if we got one
                if let hostName = service.hostName, device.hostname == nil {
                    logger.info("DNS-SD: Setting hostname to \(hostName)")
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

                logger.info("DNS-SD: Final device - MAC=\(device.mac) hostname=\(device.hostname ?? "nil") type=\(device.deviceType.rawValue)")

                devices[device.mac] = device
                onDeviceUpdate?(device, .updated)
            } else {
                logger.debug("DNS-SD: No ARP entry found for IP \(ip)")
            }
        }
    }

    private func handleSSDPDevice(_ ssdpDevice: SSDPListener.SSDPDevice) async {
        guard let hostIP = ssdpDevice.hostIP else {
            logger.warning("SSDP: No host IP in SSDP device, skipping")
            debugLog("SSDP: No host IP, skipping")
            return
        }

        logger.info("SSDP: Processing device at \(hostIP)")
        logger.info("SSDP: Server=\(ssdpDevice.server ?? "nil")")
        debugLog("SSDP: Processing \(hostIP) - \(ssdpDevice.server ?? "no server")")

        // Find MAC for this IP
        debugLog("SSDP: Looking up MAC for IP \(hostIP)...")
        if let entries = try? await ARPScanner.shared.getARPTable() {
            debugLog("SSDP: ARP table has \(entries.count) entries")
            if let entry = entries.first(where: { $0.ip == hostIP }) {
                debugLog("SSDP: Found MAC \(entry.mac) for IP \(hostIP)")
                var device = await updateOrCreateDevice(mac: entry.mac, ip: hostIP, source: "SSDP")

                // Add the service with a meaningful name
                // Use ST (search target) or extract from server header, not the raw USN
                let serviceName = ssdpDevice.st ?? extractServiceName(from: ssdpDevice.server) ?? "UPnP Service"
                let discoveredService = DiscoveredService(
                    name: serviceName,
                    type: .ssdp,
                    port: nil,
                    txt: ["location": ssdpDevice.location, "server": ssdpDevice.server ?? ""]
                )

                // Deduplicate by location to avoid duplicate entries for the same service
                let isDuplicate = device.services.contains { existing in
                    existing.type == .ssdp && existing.txt["location"] == ssdpDevice.location
                }
                if !isDuplicate {
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

                // Extract hostname from SSDP server string if not set
                if device.hostname == nil, let server = ssdpDevice.server {
                    let extractedName = extractDeviceName(from: server)
                    debugLog("SSDP: Extracted hostname '\(extractedName ?? "nil")' from server '\(server)'")
                    device.hostname = extractedName
                }

                // Recalculate smart score
                device.smartScore = calculateSmartScore(for: device)

                debugLog("SSDP: Final device - MAC=\(device.mac) hostname=\(device.hostname ?? "nil") type=\(device.deviceType.rawValue) score=\(device.smartScore)")

                devices[device.mac] = device
                onDeviceUpdate?(device, .updated)
                debugLog("SSDP: Called onDeviceUpdate for \(device.mac)")

                // Trigger UPnP fingerprinting asynchronously
                let macAddress = device.mac
                let location = ssdpDevice.location
                debugLog("SSDP: Starting fingerprint for \(macAddress)")
                Task { [weak self] in
                    await self?.fetchUPnPFingerprint(mac: macAddress, locationURL: location)
                }
            } else {
                debugLog("SSDP: NO MAC FOUND for IP \(hostIP) in ARP table!")
                let firstTen = entries.prefix(10).map { $0.ip }.joined(separator: ", ")
                debugLog("SSDP: Available IPs: \(firstTen)...")
            }
        } else {
            debugLog("SSDP: Failed to get ARP table!")
        }
    }

    /// Fetch fingerprint for a device (UPnP + Fingerbank if API key available)
    private func fetchUPnPFingerprint(mac: String, locationURL: String) async {
        guard var device = devices[mac] else {
            logger.debug("Fingerprint: Device \(mac) not found in devices list")
            return
        }

        // Only fetch if we don't already have fingerprint data
        if device.fingerprint != nil {
            logger.debug("Fingerprint: Device \(mac) already has fingerprint, skipping")
            return
        }

        // Capture API key locally to avoid actor isolation issues in logging closures
        let apiKey = self.fingerbankAPIKey
        let hasFingerbankKey = apiKey != nil

        logger.info("Fingerprint: Starting fetch for \(mac) (Fingerbank: \(hasFingerbankKey ? "enabled" : "disabled"))")
        debugLog("Fingerprint: Starting fetch for \(mac) with Fingerbank \(hasFingerbankKey ? "enabled" : "disabled")")

        // Use full fingerprinting if Fingerbank API key is available
        let fingerprint = await DeviceFingerprintManager.shared.fingerprintDevice(
            device: device,
            locationURL: locationURL,
            fingerbankAPIKey: apiKey
        )

        if let fp = fingerprint {
            logger.info("Fingerprint: SUCCESS for \(mac) - friendlyName=\(fp.friendlyName ?? "nil") manufacturer=\(fp.manufacturer ?? "nil") model=\(fp.modelName ?? "nil")")

            device.fingerprint = fp

            // Update device type from fingerprint if still unknown
            if device.deviceType == .unknown {
                let inferredType = inferDeviceType(from: fp)
                logger.info("Fingerprint: Inferred type \(inferredType.rawValue) for \(mac)")
                device.deviceType = inferredType
            }

            // Update hostname from friendly name if not set
            if device.hostname == nil, let friendlyName = fp.friendlyName {
                logger.info("Fingerprint: Setting hostname to '\(friendlyName)' for \(mac)")
                device.hostname = friendlyName
            }

            devices[mac] = device
            onDeviceUpdate?(device, .updated)
        } else {
            logger.warning("Fingerprint: FAILED for \(mac) - no data returned")
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

    /// Extract a device name from SSDP server string
    /// Examples:
    /// - "Linux UPnP/1.0 Sonos/92.0-72090 (ZPS57)" → "Sonos"
    /// - "Roku/9.4.0 UPnP/1.0" → "Roku"
    /// - "Samsung-TV" → "Samsung-TV"
    private func extractDeviceName(from server: String) -> String? {
        let knownBrands = [
            "Sonos", "Roku", "Samsung", "LG", "Sony", "Vizio", "Philips",
            "Bose", "Denon", "Yamaha", "Onkyo", "Pioneer", "Hue", "Ring",
            "Nest", "Ecobee", "Wemo", "TP-Link", "Netgear", "Asus", "Linksys"
        ]

        // Check for known brand names in the server string
        for brand in knownBrands {
            if server.lowercased().contains(brand.lowercased()) {
                return brand
            }
        }

        // Try to extract a meaningful name from the server string
        // Pattern: look for word before "/" that isn't "UPnP" or "Linux"
        let components = server.components(separatedBy: CharacterSet(charactersIn: "/ "))
        for component in components {
            let cleaned = component.trimmingCharacters(in: .whitespaces)
            if !cleaned.isEmpty &&
               cleaned.lowercased() != "upnp" &&
               cleaned.lowercased() != "linux" &&
               cleaned.lowercased() != "http" &&
               !cleaned.contains(".") &&
               cleaned.count > 2 {
                return cleaned
            }
        }

        return nil
    }

    /// Extract a meaningful service name from SSDP server header
    /// Examples:
    /// - "Linux UPnP/1.0 Sonos/92.0-72090 (ZPS57)" → "Sonos Media Player"
    /// - "Roku/9.4.0 UPnP/1.0" → "Roku"
    /// - nil → nil
    private func extractServiceName(from server: String?) -> String? {
        guard let server = server else { return nil }

        // Map known brands to service descriptions
        let serviceMap: [(pattern: String, name: String)] = [
            ("sonos", "Sonos Player"),
            ("roku", "Roku"),
            ("samsung", "Samsung TV"),
            ("lg", "LG TV"),
            ("philips", "Philips"),
            ("hue", "Philips Hue"),
            ("ring", "Ring"),
            ("nest", "Nest"),
            ("wemo", "Wemo"),
            ("streammagic", "StreamMagic"),
            ("dlna", "DLNA"),
            ("mediarenderer", "Media Renderer"),
            ("mediaserver", "Media Server"),
        ]

        let lowerServer = server.lowercased()
        for (pattern, name) in serviceMap {
            if lowerServer.contains(pattern) {
                return name
            }
        }

        // Try to extract first meaningful word
        let components = server.components(separatedBy: CharacterSet(charactersIn: "/ "))
        for component in components {
            let cleaned = component.trimmingCharacters(in: .whitespaces)
            if !cleaned.isEmpty &&
               cleaned.lowercased() != "upnp" &&
               cleaned.lowercased() != "linux" &&
               cleaned.lowercased() != "http" &&
               !cleaned.contains(".") &&
               cleaned.count > 2 {
                return cleaned
            }
        }

        return nil
    }
}
