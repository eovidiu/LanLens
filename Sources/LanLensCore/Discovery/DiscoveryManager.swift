import Foundation

/// Orchestrates all discovery methods and maintains device list
/// Uses DeviceStore as the single source of truth for device data
public actor DiscoveryManager {
    public static let shared = DiscoveryManager()

    /// The backing store for all device data - single source of truth
    private let deviceStore: DeviceStore

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

    private init() {
        self.deviceStore = DeviceStore()
    }

    /// Initialize with a custom DeviceStore (for testing)
    public init(deviceStore: DeviceStore) {
        self.deviceStore = deviceStore
    }

    /// Load persisted devices from storage
    /// Call this on app startup to restore previous device data
    public func loadPersistedDevices() async {
        do {
            try await deviceStore.load()
            Log.info("Loaded persisted devices from storage", category: .discovery)
        } catch {
            Log.error("Failed to load persisted devices: \(error.localizedDescription)", category: .discovery)
        }
    }

    /// Get the underlying device store (for direct access when needed)
    public func getDeviceStore() -> DeviceStore {
        deviceStore
    }

    /// Configure Fingerbank API key for device identification
    public func setFingerbankAPIKey(_ key: String?) {
        self.fingerbankAPIKey = key
        Log.info("Fingerbank API key \(key != nil ? "configured" : "cleared")", category: .discovery)
    }

    /// Start passive discovery (mDNS + SSDP)
    public func startPassiveDiscovery(onUpdate: @escaping DeviceUpdateHandler) async {
        guard !isRunning else {
            Log.debug("Passive discovery already running, skipping", category: .discovery)
            return
        }
        Log.info("Starting passive discovery (mDNS + SSDP)...", category: .discovery)
        isRunning = true
        onDeviceUpdate = onUpdate

        // Broadcast scan started event via WebSocket
        Task {
            await WebSocketManager.shared.broadcastScanStarted(scanType: "passive")
        }

        // Start mDNS listener
        Log.debug("Starting mDNS listener...", category: .mdns)
        await MDNSListener.shared.start { [weak self] service in
            Task { [weak self] in
                await self?.handleMDNSService(service)
            }
        }

        // Start SSDP listener
        Log.debug("Starting SSDP listener...", category: .ssdp)
        await SSDPListener.shared.start { [weak self] device in
            Log.debug("SSDP callback triggered for device at \(device.hostIP ?? "unknown")", category: .ssdp)
            Task { [weak self] in
                await self?.handleSSDPDevice(device)
            }
        }
        Log.info("Passive discovery started successfully", category: .discovery)
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

        // Broadcast scan completed event via WebSocket
        let deviceCount = await deviceStore.getDeviceCount()
        Task {
            await WebSocketManager.shared.broadcastScanCompleted(scanType: "passive", deviceCount: deviceCount)
        }
    }

    /// Clear the device update handler - call when fully done with scanning
    public func clearUpdateHandler() {
        onDeviceUpdate = nil
    }

    /// Run dns-sd based discovery (more reliable than NWBrowser)
    public func runDNSSDDiscovery(duration: TimeInterval = 5.0, onUpdate: @escaping DeviceUpdateHandler) async {
        onDeviceUpdate = onUpdate

        // Broadcast scan started via WebSocket
        Task {
            await WebSocketManager.shared.broadcastScanStarted(scanType: "dnssd")
        }

        await DNSSDScanner.shared.browse(duration: duration) { [weak self] service in
            Task { [weak self] in
                await self?.handleDNSSDService(service)
            }
        }

        // Broadcast scan completed via WebSocket
        let deviceCount = await deviceStore.getDeviceCount()
        Task {
            await WebSocketManager.shared.broadcastScanCompleted(scanType: "dnssd", deviceCount: deviceCount)
        }
    }

    /// Perform active ARP scan of a subnet
    /// - Parameters:
    ///   - subnet: Subnet in CIDR notation (e.g., "192.168.1.0/24")
    ///   - interface: Optional interface to scan on (e.g., "en0")
    public func scanSubnet(_ subnet: String, interface: String? = nil) async throws -> [Device] {
        // Broadcast scan started via WebSocket
        Task {
            await WebSocketManager.shared.broadcastScanStarted(scanType: "arp")
        }

        let entries = try await ARPScanner.shared.scanSubnet(subnet, interface: interface)
        var scannedDevices: [Device] = []

        for entry in entries {
            var device = await updateOrCreateDevice(
                mac: entry.mac,
                ip: entry.ip,
                source: "ARP scan"
            )
            // Tag device with source interface and subnet
            device.sourceInterface = entry.interface ?? interface
            device.subnet = subnet
            try? await deviceStore.addOrUpdate(device: device)
            scannedDevices.append(device)
        }

        // Broadcast scan completed via WebSocket
        let deviceCount = scannedDevices.count
        Task {
            await WebSocketManager.shared.broadcastScanCompleted(scanType: "arp", deviceCount: deviceCount)
        }

        return scannedDevices
    }

    /// Scan all selected network interfaces
    /// - Parameter selectedInterfaceIds: Set of interface IDs to scan. If empty, scans all active interfaces.
    /// - Returns: All devices discovered across all interfaces
    public func scanAllSelectedInterfaces(selectedInterfaceIds: Set<String> = []) async throws -> [Device] {
        let interfaces = await NetworkInterfaceManager.shared.getSelectedInterfaces(selectedIds: selectedInterfaceIds)

        guard !interfaces.isEmpty else {
            Log.warning("No active interfaces available for scanning", category: .discovery)
            return []
        }

        Log.info("Scanning \(interfaces.count) interface(s): \(interfaces.map { $0.id }.joined(separator: ", "))", category: .discovery)

        var allDevices: [Device] = []

        // Scan each interface sequentially to avoid ARP table confusion
        for interface in interfaces {
            let subnet = interface.cidr
            Log.info("Scanning interface \(interface.id) (\(interface.name)): \(subnet)", category: .discovery)

            do {
                let entries = try await ARPScanner.shared.scanSubnet(subnet, interface: interface.id)

                for entry in entries {
                    var device = await updateOrCreateDevice(
                        mac: entry.mac,
                        ip: entry.ip,
                        source: "ARP scan (\(interface.name))"
                    )
                    // Tag device with source interface and subnet
                    device.sourceInterface = interface.id
                    device.subnet = subnet
                    try? await deviceStore.addOrUpdate(device: device)
                    allDevices.append(device)
                }

                Log.info("Found \(entries.count) devices on \(interface.id)", category: .discovery)
            } catch {
                Log.error("Failed to scan interface \(interface.id): \(error.localizedDescription)", category: .discovery)
                // Continue with other interfaces
            }
        }

        // Fingerprint new devices
        if fingerbankAPIKey != nil {
            let macs = allDevices.map { $0.mac }
            await fingerprintARPDevices(macs)
        }

        return allDevices
    }

    /// Get current ARP table without active scanning
    /// - Parameter interface: Optional interface to filter results
    public func getARPDevices(interface: String? = nil) async throws -> [Device] {
        let entries = try await ARPScanner.shared.getARPTable(interface: interface)
        var macAddresses: [String] = []

        for entry in entries {
            var device = await updateOrCreateDevice(
                mac: entry.mac,
                ip: entry.ip,
                source: "ARP table"
            )
            // Tag device with source interface if available
            if let iface = entry.interface {
                device.sourceInterface = iface
                try? await deviceStore.addOrUpdate(device: device)
            }
            macAddresses.append(device.mac)
        }

        // Fingerprint devices that don't have fingerprint data yet (using Fingerbank MAC lookup)
        if fingerbankAPIKey != nil {
            await fingerprintARPDevices(macAddresses)
        }

        // Return updated devices from store (includes fingerprint data)
        var result: [Device] = []
        for mac in macAddresses {
            if let device = await deviceStore.getDevice(mac: mac) {
                result.append(device)
            }
        }
        return result
    }

    /// Get devices by interface
    public func getDevices(forInterface interfaceId: String) async -> [Device] {
        await deviceStore.getDevices(matching: { $0.sourceInterface == interfaceId })
    }

    /// Get devices by subnet
    public func getDevices(forSubnet subnet: String) async -> [Device] {
        await deviceStore.getDevices(matching: { $0.subnet == subnet })
    }

    /// Fingerprint ARP devices using Fingerbank MAC lookup (no UPnP location needed)
    private func fingerprintARPDevices(_ macAddresses: [String]) async {
        // Only fingerprint devices that don't already have fingerprint data
        var macsNeedingFingerprint: [String] = []
        for mac in macAddresses {
            if let existingDevice = await deviceStore.getDevice(mac: mac) {
                if existingDevice.fingerprint == nil {
                    macsNeedingFingerprint.append(mac)
                }
            } else {
                macsNeedingFingerprint.append(mac)
            }
        }

        guard !macsNeedingFingerprint.isEmpty else { return }

        Log.info("Fingerprinting \(macsNeedingFingerprint.count) ARP devices via Fingerbank...", category: .fingerprinting)

        // Process devices
        for mac in macsNeedingFingerprint {
            await fingerprintDeviceWithFingerbankOnly(mac: mac)
        }
    }

    /// Fingerprint a device using only Fingerbank (MAC lookup, no UPnP)
    private func fingerprintDeviceWithFingerbankOnly(mac: String) async {
        guard var device = await deviceStore.getDevice(mac: mac) else { return }

        // Skip if already has fingerprint
        guard device.fingerprint == nil else { return }

        guard let apiKey = fingerbankAPIKey, !apiKey.isEmpty else { return }

        Log.debug("Fingerbank lookup for ARP device: \(mac)", category: .fingerprinting)

        let fingerprint = await DeviceFingerprintManager.shared.fingerprintDevice(
            device: device,
            locationURL: nil,  // No UPnP location for ARP-only devices
            fingerbankAPIKey: apiKey
        )

        if let fp = fingerprint {
            Log.info("Fingerbank result for \(mac): \(fp.fingerbankDeviceName ?? "unknown")", category: .fingerprinting)

            device.fingerprint = fp

            // Update device type from fingerprint if still unknown
            if device.deviceType == .unknown {
                let inferredType = inferDeviceType(from: fp)
                device.deviceType = inferredType
            }

            try? await deviceStore.addOrUpdate(device: device)
            onDeviceUpdate?(device, .updated)

            // Broadcast device updated via WebSocket
            let deviceToSend = device
            Task {
                await WebSocketManager.shared.broadcastDeviceUpdated(deviceToSend)
            }
        }
    }

    /// Get all known devices
    public func getAllDevices() async -> [Device] {
        await deviceStore.getDevices()
    }

    /// Get only devices classified as smart
    public func getSmartDevices(minScore: Int = 20) async -> [Device] {
        await deviceStore.getDevices(matching: { $0.smartScore >= minScore })
            .sorted { $0.smartScore > $1.smartScore }
    }

    /// Get device by MAC
    public func getDevice(mac: String) async -> Device? {
        await deviceStore.getDevice(mac: mac)
    }

    /// Check if passive discovery is currently running
    public func isDiscovering() -> Bool {
        isRunning
    }

    /// Get total device count
    public func getDeviceCount() async -> Int {
        await deviceStore.getDeviceCount()
    }

    /// Scan ports for a specific device
    public func scanPorts(for mac: String, ports: [UInt16]? = nil) async -> Device? {
        guard var device = await deviceStore.getDevice(mac: mac.uppercased()) else { return nil }

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

        // Grab port banners for enhanced inference
        if !result.openPorts.isEmpty {
            let openPortNumbers = result.openPorts.map { Int($0.port) }
            let bannerData = await PortBannerGrabber.shared.grabBanners(ip: device.ip, openPorts: openPortNumbers)

            // Store banner data if we got any useful information
            if bannerData.ssh != nil || bannerData.http != nil || bannerData.rtsp != nil {
                device.portBanners = bannerData
                Log.info("Grabbed port banners for \(device.mac): SSH=\(bannerData.ssh != nil), HTTP=\(bannerData.http != nil), RTSP=\(bannerData.rtsp != nil)", category: .portBanner)

                // Re-evaluate device type with enhanced data if still unknown
                if device.deviceType == .unknown {
                    let (inferredType, _) = await DeviceTypeInferenceEngine.shared.inferTypeWithEnhancedData(
                        signals: [],
                        mdnsTXTData: device.mdnsTXTRecords,
                        portBannerData: device.portBanners,
                        macAnalysisData: device.macAnalysis
                    )
                    if inferredType != .unknown {
                        device.deviceType = inferredType
                        Log.debug("Updated device type to \(inferredType.rawValue) from port banner analysis", category: .portBanner)
                    }
                }
            }
        }

        // Assess security posture now that we have port and banner data
        let openPortNumbers = device.openPorts.map { $0.number }
        let securityPosture = SecurityPostureAssessor.shared.assess(
            hostname: device.hostname,
            openPorts: openPortNumbers,
            portBanners: device.portBanners,
            httpHeaders: device.portBanners?.http
        )
        device.securityPosture = securityPosture
        Log.info("Security posture assessed for \(device.mac): risk=\(securityPosture.riskLevel.rawValue) score=\(securityPosture.riskScore)", category: .security)

        // Recalculate smart score
        device.smartScore = calculateSmartScore(for: device)

        try? await deviceStore.addOrUpdate(device: device)
        onDeviceUpdate?(device, .updated)

        // Broadcast device updated via WebSocket
        let deviceToSend = device
        Task {
            await WebSocketManager.shared.broadcastDeviceUpdated(deviceToSend)
        }

        return device
    }

    /// Quick port scan all known devices
    public func quickScanAllDevices() async {
        let deviceList = await deviceStore.getDevices()

        // Broadcast scan started via WebSocket
        Task {
            await WebSocketManager.shared.broadcastScanStarted(scanType: "quickPorts")
        }

        await withTaskGroup(of: Void.self) { group in
            for device in deviceList {
                group.addTask { [self] in
                    _ = await self.scanPorts(for: device.mac, ports: PortScanner.quickPorts)
                }
            }
        }

        // Broadcast scan completed via WebSocket
        let deviceCount = await deviceStore.getDeviceCount()
        Task {
            await WebSocketManager.shared.broadcastScanCompleted(scanType: "quickPorts", deviceCount: deviceCount)
        }
    }

    /// Full port scan all known devices
    public func fullScanAllDevices() async {
        let deviceList = await deviceStore.getDevices()

        // Broadcast scan started via WebSocket
        Task {
            await WebSocketManager.shared.broadcastScanStarted(scanType: "fullPorts")
        }

        await withTaskGroup(of: Void.self) { group in
            for device in deviceList {
                group.addTask { [self] in
                    _ = await self.scanPorts(for: device.mac)
                }
            }
        }

        // Broadcast scan completed via WebSocket
        let deviceCount = await deviceStore.getDeviceCount()
        Task {
            await WebSocketManager.shared.broadcastScanCompleted(scanType: "fullPorts", deviceCount: deviceCount)
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
                var device = await updateOrCreateDevice(mac: entry.mac, ip: cleanIP, source: "mDNS", services: [service.type])

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

                // Analyze mDNS TXT records for enhanced inference
                if !service.txtRecords.isEmpty {
                    let txtAnalysis = await MDNSTXTRecordAnalyzer.shared.analyze(
                        serviceType: service.type,
                        txtRecords: service.txtRecords
                    )
                    // Merge with existing mDNS TXT data
                    device.mdnsTXTRecords = mergeMDNSTXTData(existing: device.mdnsTXTRecords, new: txtAnalysis)
                    Log.debug("Analyzed mDNS TXT for \(device.mac): service=\(service.type)", category: .mdnsTXT)
                }

                // Update device type using enhanced inference if we have analyzer data
                if device.deviceType == .unknown {
                    if device.mdnsTXTRecords != nil || device.portBanners != nil || device.macAnalysis != nil {
                        let (inferredType, _) = await DeviceTypeInferenceEngine.shared.inferTypeWithEnhancedData(
                            signals: [],
                            mdnsTXTData: device.mdnsTXTRecords,
                            portBannerData: device.portBanners,
                            macAnalysisData: device.macAnalysis
                        )
                        if inferredType != .unknown {
                            device.deviceType = inferredType
                        } else {
                            device.deviceType = service.inferredDeviceType
                        }
                    } else {
                        device.deviceType = service.inferredDeviceType
                    }
                }

                // Recalculate smart score
                device.smartScore = calculateSmartScore(for: device)

                try? await deviceStore.addOrUpdate(device: device)
                onDeviceUpdate?(device, .updated)

                // Broadcast device updated via WebSocket
                let deviceToSend = device
                Task {
                    await WebSocketManager.shared.broadcastDeviceUpdated(deviceToSend)
                }
            }
        }
    }

    private func handleDNSSDService(_ service: DNSSDScanner.DNSSDService) async {
        guard let ip = service.ip else {
            Log.debug("DNS-SD: No IP for service \(service.name), skipping", category: .discovery)
            return
        }

        Log.info("DNS-SD: Processing service \(service.name) at \(ip)", category: .discovery)
        Log.debug("DNS-SD: hostname=\(service.hostName ?? "nil") type=\(service.type)", category: .discovery)

        // Find MAC for this IP from ARP table
        if let entries = try? await ARPScanner.shared.getARPTable() {
            if let entry = entries.first(where: { $0.ip == ip }) {
                Log.info("DNS-SD: Found MAC \(entry.mac) for IP \(ip)", category: .discovery)
                var device = await updateOrCreateDevice(mac: entry.mac, ip: ip, source: "dns-sd", services: [service.type])

                // Set hostname if we got one
                if let hostName = service.hostName, device.hostname == nil {
                    Log.debug("DNS-SD: Setting hostname to \(hostName)", category: .discovery)
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

                // Analyze mDNS TXT records for enhanced inference
                if !service.txtRecords.isEmpty {
                    let txtAnalysis = await MDNSTXTRecordAnalyzer.shared.analyze(
                        serviceType: service.type,
                        txtRecords: service.txtRecords
                    )
                    device.mdnsTXTRecords = mergeMDNSTXTData(existing: device.mdnsTXTRecords, new: txtAnalysis)
                    Log.debug("Analyzed DNS-SD TXT for \(device.mac): service=\(service.type)", category: .mdnsTXT)
                }

                // Update device type using enhanced inference if we have analyzer data
                if device.deviceType == .unknown {
                    if device.mdnsTXTRecords != nil || device.portBanners != nil || device.macAnalysis != nil {
                        let (inferredType, _) = await DeviceTypeInferenceEngine.shared.inferTypeWithEnhancedData(
                            signals: [],
                            mdnsTXTData: device.mdnsTXTRecords,
                            portBannerData: device.portBanners,
                            macAnalysisData: device.macAnalysis
                        )
                        if inferredType != .unknown {
                            device.deviceType = inferredType
                        } else {
                            device.deviceType = service.inferredDeviceType
                        }
                    } else {
                        device.deviceType = service.inferredDeviceType
                    }
                }

                // Recalculate smart score
                device.smartScore = calculateSmartScore(for: device)

                Log.info("DNS-SD: Final device - MAC=\(device.mac) hostname=\(device.hostname ?? "nil") type=\(device.deviceType.rawValue)", category: .discovery)

                try? await deviceStore.addOrUpdate(device: device)
                onDeviceUpdate?(device, .updated)

                // Broadcast device updated via WebSocket
                let deviceToSend = device
                Task {
                    await WebSocketManager.shared.broadcastDeviceUpdated(deviceToSend)
                }
            } else {
                Log.debug("DNS-SD: No ARP entry found for IP \(ip)", category: .discovery)
            }
        }
    }

    private func handleSSDPDevice(_ ssdpDevice: SSDPListener.SSDPDevice) async {
        guard let hostIP = ssdpDevice.hostIP else {
            Log.warning("SSDP: No host IP in SSDP device, skipping", category: .ssdp)
            return
        }

        Log.info("SSDP: Processing device at \(hostIP)", category: .ssdp)
        Log.debug("SSDP: Server=\(ssdpDevice.server ?? "nil")", category: .ssdp)

        // Find MAC for this IP
        Log.debug("SSDP: Looking up MAC for IP \(hostIP)...", category: .ssdp)
        if let entries = try? await ARPScanner.shared.getARPTable() {
            Log.debug("SSDP: ARP table has \(entries.count) entries", category: .ssdp)
            if let entry = entries.first(where: { $0.ip == hostIP }) {
                Log.debug("SSDP: Found MAC \(entry.mac) for IP \(hostIP)", category: .ssdp)
                // Extract service name for behavior tracking
                let serviceName = ssdpDevice.st ?? extractServiceName(from: ssdpDevice.server) ?? "UPnP Service"
                var device = await updateOrCreateDevice(mac: entry.mac, ip: hostIP, source: "SSDP", services: [serviceName])

                // Add the service with a meaningful name
                // Use ST (search target) or extract from server header, not the raw USN
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
                    Log.debug("SSDP: Extracted hostname '\(extractedName ?? "nil")' from server '\(server)'", category: .ssdp)
                    device.hostname = extractedName
                }

                // Recalculate smart score
                device.smartScore = calculateSmartScore(for: device)

                Log.info("SSDP: Final device - MAC=\(device.mac) hostname=\(device.hostname ?? "nil") type=\(device.deviceType.rawValue) score=\(device.smartScore)", category: .ssdp)

                try? await deviceStore.addOrUpdate(device: device)
                onDeviceUpdate?(device, .updated)
                Log.debug("SSDP: Called onDeviceUpdate for \(device.mac)", category: .ssdp)

                // Broadcast device updated via WebSocket
                let deviceToSend = device
                Task {
                    await WebSocketManager.shared.broadcastDeviceUpdated(deviceToSend)
                }

                // Trigger UPnP fingerprinting asynchronously
                let macAddress = device.mac
                let location = ssdpDevice.location
                Log.debug("SSDP: Starting fingerprint for \(macAddress)", category: .fingerprinting)
                Task { [weak self] in
                    await self?.fetchUPnPFingerprint(mac: macAddress, locationURL: location)
                }
            } else {
                Log.warning("SSDP: NO MAC FOUND for IP \(hostIP) in ARP table!", category: .ssdp)
                let firstTen = entries.prefix(10).map { $0.ip }.joined(separator: ", ")
                Log.debug("SSDP: Available IPs: \(firstTen)...", category: .ssdp)
            }
        } else {
            Log.error("SSDP: Failed to get ARP table!", category: .ssdp)
        }
    }

    /// Fetch fingerprint for a device (UPnP + Fingerbank if API key available)
    private func fetchUPnPFingerprint(mac: String, locationURL: String) async {
        guard var device = await deviceStore.getDevice(mac: mac) else {
            Log.debug("Fingerprint: Device \(mac) not found in device store", category: .fingerprinting)
            return
        }

        // Only fetch if we don't already have fingerprint data
        if device.fingerprint != nil {
            Log.debug("Fingerprint: Device \(mac) already has fingerprint, skipping", category: .fingerprinting)
            return
        }

        // Capture API key locally to avoid actor isolation issues in logging closures
        let apiKey = self.fingerbankAPIKey
        let hasFingerbankKey = apiKey != nil

        Log.info("Fingerprint: Starting fetch for \(mac) (Fingerbank: \(hasFingerbankKey ? "enabled" : "disabled"))", category: .fingerprinting)

        // Use full fingerprinting if Fingerbank API key is available
        let fingerprint = await DeviceFingerprintManager.shared.fingerprintDevice(
            device: device,
            locationURL: locationURL,
            fingerbankAPIKey: apiKey
        )

        if let fp = fingerprint {
            Log.info("Fingerprint: SUCCESS for \(mac) - friendlyName=\(fp.friendlyName ?? "nil") manufacturer=\(fp.manufacturer ?? "nil") model=\(fp.modelName ?? "nil")", category: .fingerprinting)

            device.fingerprint = fp

            // Update device type from fingerprint if still unknown
            if device.deviceType == .unknown {
                let inferredType = inferDeviceType(from: fp)
                Log.debug("Fingerprint: Inferred type \(inferredType.rawValue) for \(mac)", category: .fingerprinting)
                device.deviceType = inferredType
            }

            // Update hostname from friendly name if not set
            if device.hostname == nil, let friendlyName = fp.friendlyName {
                Log.debug("Fingerprint: Setting hostname to '\(friendlyName)' for \(mac)", category: .fingerprinting)
                device.hostname = friendlyName
            }

            try? await deviceStore.addOrUpdate(device: device)
            onDeviceUpdate?(device, .updated)

            // Broadcast device updated via WebSocket
            let deviceToSend = device
            Task {
                await WebSocketManager.shared.broadcastDeviceUpdated(deviceToSend)
            }
        } else {
            Log.warning("Fingerprint: FAILED for \(mac) - no data returned", category: .fingerprinting)
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

    private func updateOrCreateDevice(mac: String, ip: String, source: String, services: [String] = []) async -> Device {
        let normalizedMAC = mac.uppercased()

        if var existing = await deviceStore.getDevice(mac: normalizedMAC) {
            existing.ip = ip
            existing.lastSeen = Date()
            existing.isOnline = true

            // Backfill MAC analysis if missing (for devices discovered before this feature)
            if existing.macAnalysis == nil {
                let macAnalysis = MACAddressAnalyzer.shared.analyze(mac: normalizedMAC, vendor: existing.vendor)
                existing.macAnalysis = macAnalysis
                Log.debug("Backfilled MAC analysis for \(normalizedMAC)", category: .macAnalysis)
            }

            // Record presence for behavior tracking
            await DeviceBehaviorTracker.shared.recordPresence(
                for: normalizedMAC,
                isPresent: true,
                services: services,
                ipAddress: ip
            )

            // Retrieve and store updated behavior profile
            if let profile = await DeviceBehaviorTracker.shared.getProfile(for: normalizedMAC) {
                existing.behaviorProfile = profile
                Log.debug("Updated behavior profile for \(normalizedMAC): classification=\(profile.classification.rawValue)", category: .behavior)
            }

            // Note: Caller is responsible for calling deviceStore.addOrUpdate after modifying
            return existing
        } else {
            // Look up vendor from MAC
            let vendor = MACVendorLookup.shared.lookup(mac: normalizedMAC)

            // Analyze MAC address for enhanced inference
            let macAnalysis = MACAddressAnalyzer.shared.analyze(mac: normalizedMAC, vendor: vendor)
            Log.debug("MAC analysis for \(normalizedMAC): randomized=\(macAnalysis.isRandomized), vendor=\(vendor ?? "nil")", category: .macAnalysis)

            var device = Device(
                mac: normalizedMAC,
                ip: ip,
                vendor: vendor,
                firstSeen: Date(),
                lastSeen: Date(),
                isOnline: true,
                macAnalysis: macAnalysis
            )

            // If MAC analysis gives us a strong device type hint, use it
            if device.deviceType == .unknown, let specialization = macAnalysis.vendorSpecialization {
                if macAnalysis.vendorConfidence == .high {
                    device.deviceType = specialization
                    Log.debug("Set device type to \(specialization.rawValue) from MAC vendor specialization", category: .macAnalysis)
                }
            }

            // Record initial presence for behavior tracking
            await DeviceBehaviorTracker.shared.recordPresence(
                for: normalizedMAC,
                isPresent: true,
                services: services,
                ipAddress: ip
            )

            // Initialize behavior profile
            if let profile = await DeviceBehaviorTracker.shared.getProfile(for: normalizedMAC) {
                device.behaviorProfile = profile
                Log.debug("Initialized behavior profile for \(normalizedMAC)", category: .behavior)
            }

            // Save to store - this is a new device
            try? await deviceStore.addOrUpdate(device: device)
            onDeviceUpdate?(device, .discovered)

            // Broadcast device discovered via WebSocket
            let deviceToSend = device
            Task {
                await WebSocketManager.shared.broadcastDeviceDiscovered(deviceToSend)
            }
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

    // MARK: - Enhanced Analyzer Helpers

    /// Merge new mDNS TXT data with existing data, preserving both.
    /// Each service type's data is merged individually.
    private func mergeMDNSTXTData(existing: MDNSTXTData?, new: MDNSTXTData) -> MDNSTXTData {
        guard var merged = existing else {
            return new
        }

        // Merge AirPlay data (prefer new if both exist)
        if let newAirplay = new.airplay {
            merged.airplay = newAirplay
        }

        // Merge Google Cast data (prefer new if both exist)
        if let newGoogleCast = new.googleCast {
            merged.googleCast = newGoogleCast
        }

        // Merge HomeKit data (prefer new if both exist)
        if let newHomeKit = new.homeKit {
            merged.homeKit = newHomeKit
        }

        // Merge RAOP data (prefer new if both exist)
        if let newRaop = new.raop {
            merged.raop = newRaop
        }

        // Merge raw records (combine all service types)
        for (serviceType, records) in new.rawRecords {
            merged.rawRecords[serviceType] = records
        }

        return merged
    }
}
