import Foundation
import SwiftUI
import LanLensCore
import os.log

private let logger = Logger(subsystem: "com.lanlens.app", category: "AppState")

@Observable
@MainActor
final class AppState {
    // MARK: - Published State

    private(set) var devices: [Device] = [] {
        didSet {
            updateFilteredDevicesCache()
        }
    }
    private(set) var isScanning = false
    private(set) var isAPIRunning = false
    private(set) var lastScanTime: Date?
    private(set) var scanError: String?
    var selectedDevice: Device?

    // MARK: - Cached Filtered Arrays (Performance Optimization)

    /// Cached smart devices array - updated when devices changes
    private(set) var smartDevices: [Device] = []

    /// Cached other devices array - updated when devices changes
    private(set) var otherDevices: [Device] = []

    var deviceCount: Int {
        devices.count
    }

    var smartDeviceCount: Int {
        smartDevices.count
    }

    // MARK: - Private State

    private var apiServer: APIServer?
    private var apiServerTask: Task<Void, Never>?
    private var passiveDiscoveryActive = false
    private var currentScanTask: Task<Void, Never>?

    // MARK: - Debouncing State (Prevents unbounded task spawning)

    private var pendingUpdates: [(Device, DiscoveryManager.UpdateType)] = []
    private var debounceTask: Task<Void, Never>?
    private let debounceInterval: Duration = .milliseconds(100)

    // MARK: - Initialization

    init() {}

    // MARK: - Filtered Cache Management

    private func updateFilteredDevicesCache() {
        smartDevices = devices.filter { $0.smartScore >= 20 }
        otherDevices = devices.filter { $0.smartScore < 20 }
    }

    // MARK: - Discovery Methods

    func startPassiveDiscovery() {
        guard !passiveDiscoveryActive else {
            logger.debug("Passive discovery already active, skipping")
            return
        }

        logger.info("Starting passive discovery")
        isScanning = true
        passiveDiscoveryActive = true
        scanError = nil

        Task {
            await DiscoveryManager.shared.startPassiveDiscovery { [weak self] device, updateType in
                Task { @MainActor [weak self] in
                    self?.queueDeviceUpdate(device, type: updateType)
                }
            }
        }
    }

    func stopDiscovery() {
        logger.info("Stopping passive discovery")
        passiveDiscoveryActive = false

        Task {
            await DiscoveryManager.shared.stopPassiveDiscovery()
            await DiscoveryManager.shared.clearUpdateHandler()
            await MainActor.run {
                self.isScanning = false
            }
        }
    }

    /// Immediately stops any ongoing scan operation.
    func stopScanning() {
        logger.info("Stop scanning requested - cancelling all operations")

        // Cancel the current scan task
        currentScanTask?.cancel()
        currentScanTask = nil

        // Cancel pending debounce
        debounceTask?.cancel()
        debounceTask = nil
        let pendingCount = pendingUpdates.count
        pendingUpdates.removeAll()
        if pendingCount > 0 {
            logger.debug("Cleared \(pendingCount) pending device updates")
        }

        // Stop passive discovery if active
        passiveDiscoveryActive = false

        Task {
            await DiscoveryManager.shared.stopPassiveDiscovery()
            await DiscoveryManager.shared.clearUpdateHandler()
        }

        isScanning = false
        logger.info("Scanning stopped")
    }

    func runQuickScan(fingerbankAPIKey: String? = nil) async {
        // Cancel any existing scan
        currentScanTask?.cancel()

        // Create a new scan task that we can cancel
        currentScanTask = Task { @MainActor [weak self] in
            await self?.performQuickScan(fingerbankAPIKey: fingerbankAPIKey)
        }

        // Wait for it to complete (or be cancelled)
        await currentScanTask?.value
    }

    /// Internal implementation of quick scan with cancellation checkpoints.
    /// - Parameter fingerbankAPIKey: Optional Fingerbank API key for device identification
    private func performQuickScan(fingerbankAPIKey: String? = nil) async {
        Log.info("Starting quick scan", category: .state)
        logger.info("Starting quick scan")
        isScanning = true
        scanError = nil

        // Configure Fingerbank API key if provided
        if let key = fingerbankAPIKey, !key.isEmpty {
            await DiscoveryManager.shared.setFingerbankAPIKey(key)
            Log.debug("Fingerbank API key configured", category: .state)
        }

        // Checkpoint: Check if cancelled before ARP scan
        guard !Task.isCancelled else {
            logger.info("Quick scan cancelled before ARP")
            return
        }

        do {
            // Read ARP table first
            logger.debug("Reading ARP table...")
            let arpDevices = try await DiscoveryManager.shared.getARPDevices()
            logger.info("ARP scan found \(arpDevices.count) devices")
            applyDevicesUpdate(arpDevices)
        } catch {
            logger.error("ARP scan failed: \(error.localizedDescription)")
            scanError = "ARP scan failed: \(error.localizedDescription)"
        }

        // Checkpoint: Check if cancelled before passive discovery
        guard !Task.isCancelled else {
            logger.info("Quick scan cancelled after ARP")
            isScanning = false
            return
        }

        // Start passive discovery (SSDP + mDNS) to detect smart devices
        Log.debug("About to call startPassiveDiscovery...", category: .state)
        logger.debug("Starting passive discovery (SSDP + mDNS)...")
        await DiscoveryManager.shared.startPassiveDiscovery { [weak self] device, updateType in
            Log.debug("Device update callback: \(device.ip) - \(device.hostname ?? "no hostname")", category: .state)
            Task { @MainActor [weak self] in
                self?.queueDeviceUpdate(device, type: updateType)
            }
        }
        Log.debug("startPassiveDiscovery returned", category: .state)

        // Checkpoint: Check if cancelled before DNS-SD
        guard !Task.isCancelled else {
            logger.info("Quick scan cancelled after passive discovery")
            await DiscoveryManager.shared.stopPassiveDiscovery()
            isScanning = false
            return
        }

        // Run dns-sd discovery with debounced callback
        logger.debug("Starting DNS-SD discovery (5 seconds)...")
        await DiscoveryManager.shared.runDNSSDDiscovery(duration: 5) { [weak self] device, updateType in
            Task { @MainActor [weak self] in
                self?.queueDeviceUpdate(device, type: updateType)
            }
        }

        // Checkpoint: Check if cancelled after DNS-SD
        guard !Task.isCancelled else {
            logger.info("Quick scan cancelled after DNS-SD")
            await DiscoveryManager.shared.stopPassiveDiscovery()
            isScanning = false
            return
        }

        // Stop passive discovery
        await DiscoveryManager.shared.stopPassiveDiscovery()

        logger.debug("DNS-SD discovery completed")

        await refreshDevices()

        // Clear the update handler now that we're done
        await DiscoveryManager.shared.clearUpdateHandler()

        lastScanTime = Date()
        isScanning = false
        logger.info("Quick scan completed - total devices: \(self.devices.count)")
    }

    func runFullScan() async {
        // Cancel any existing scan
        currentScanTask?.cancel()

        // Create a new scan task that we can cancel
        currentScanTask = Task { @MainActor [weak self] in
            await self?.performFullScan()
        }

        // Wait for it to complete (or be cancelled)
        await currentScanTask?.value
    }

    /// Internal implementation of full scan with cancellation checkpoints.
    private func performFullScan() async {
        logger.info("Starting full scan")
        isScanning = true
        scanError = nil

        // Checkpoint: Check if cancelled before ARP
        guard !Task.isCancelled else {
            logger.info("Full scan cancelled before ARP")
            return
        }

        do {
            // Start with ARP
            logger.debug("Reading ARP table...")
            let arpDevices = try await DiscoveryManager.shared.getARPDevices()
            logger.info("ARP scan found \(arpDevices.count) devices")
            applyDevicesUpdate(arpDevices)
        } catch {
            logger.error("ARP scan failed: \(error.localizedDescription)")
            scanError = "ARP scan failed: \(error.localizedDescription)"
        }

        // Checkpoint: Check if cancelled before passive discovery
        guard !Task.isCancelled else {
            logger.info("Full scan cancelled after ARP")
            isScanning = false
            return
        }

        // Run passive discovery briefly with debounced callback
        logger.debug("Starting passive discovery...")
        await DiscoveryManager.shared.startPassiveDiscovery { [weak self] device, updateType in
            Task { @MainActor [weak self] in
                self?.queueDeviceUpdate(device, type: updateType)
            }
        }

        // Checkpoint: Check if cancelled before DNS-SD
        guard !Task.isCancelled else {
            logger.info("Full scan cancelled before DNS-SD")
            await DiscoveryManager.shared.stopPassiveDiscovery()
            isScanning = false
            return
        }

        // Run dns-sd discovery with debounced callback
        logger.debug("Starting DNS-SD discovery (5 seconds)...")
        await DiscoveryManager.shared.runDNSSDDiscovery(duration: 5) { [weak self] device, updateType in
            Task { @MainActor [weak self] in
                self?.queueDeviceUpdate(device, type: updateType)
            }
        }
        logger.debug("DNS-SD discovery completed")

        // Stop passive discovery
        logger.debug("Stopping passive discovery...")
        await DiscoveryManager.shared.stopPassiveDiscovery()

        // Checkpoint: Check if cancelled before port scan
        guard !Task.isCancelled else {
            logger.info("Full scan cancelled before port scan")
            isScanning = false
            return
        }

        // Run full port scan on all devices
        logger.info("Starting port scan on \(self.devices.count) devices...")
        await DiscoveryManager.shared.fullScanAllDevices()

        // Checkpoint: Check if cancelled after port scan
        guard !Task.isCancelled else {
            logger.info("Full scan cancelled after port scan")
            isScanning = false
            return
        }

        logger.debug("Port scan completed")

        await refreshDevices()

        // Clear the update handler now that we're done
        await DiscoveryManager.shared.clearUpdateHandler()

        lastScanTime = Date()
        isScanning = false
        logger.info("Full scan completed - total devices: \(self.devices.count)")
    }

    func refreshDevices() async {
        let allDevices = await DiscoveryManager.shared.getAllDevices()
        applyDevicesUpdate(allDevices)
    }

    func scanPorts(for device: Device) async {
        isScanning = true

        _ = await DiscoveryManager.shared.scanPorts(for: device.mac)
        await refreshDevices()

        // Update selected device if it was the one scanned
        if let selected = selectedDevice, selected.mac == device.mac {
            selectedDevice = devices.first { $0.mac == device.mac }
        }

        isScanning = false
    }

    // MARK: - API Server Methods

    /// Starts the API server with proper state management.
    /// The `isAPIRunning` flag is set only after confirming the server has started.
    func startAPIServer(port: Int, host: String, token: String?) async {
        guard !isAPIRunning else { return }

        let config = APIServer.Config(
            host: host,
            port: port,
            authToken: token?.isEmpty == true ? nil : token
        )

        let server = APIServer(config: config)
        apiServer = server

        // Capture self weakly for the detached task
        apiServerTask = Task.detached(priority: .utility) {
            do {
                // Signal that we're about to start
                await MainActor.run { [weak self] in
                    self?.isAPIRunning = true
                }

                try await server.run()

                // Server stopped gracefully
                await MainActor.run { [weak self] in
                    self?.isAPIRunning = false
                    self?.apiServer = nil
                }
            } catch {
                // Server failed - clean up state
                await MainActor.run { [weak self] in
                    self?.isAPIRunning = false
                    self?.apiServer = nil
                }
                print("API Server error: \(error)")
            }
        }

        // Small delay to allow server startup before returning
        try? await Task.sleep(for: .milliseconds(100))
    }

    func stopAPIServer() {
        apiServerTask?.cancel()
        apiServerTask = nil
        apiServer = nil
        isAPIRunning = false
    }

    // MARK: - Debounced Device Updates

    /// Queues a device update with debouncing to prevent unbounded task spawning.
    /// Multiple rapid updates are batched and processed together.
    /// Must be called on MainActor.
    private func queueDeviceUpdate(_ device: Device, type: DiscoveryManager.UpdateType) {
        pendingUpdates.append((device, type))
        let typeString = String(describing: type)
        logger.debug("Queued device update: \(device.ip) (\(typeString))")

        // Cancel existing debounce task
        debounceTask?.cancel()

        // Schedule new debounce task
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: self?.debounceInterval ?? .milliseconds(100))

            guard !Task.isCancelled else { return }
            self?.processPendingUpdates()
        }
    }

    /// Processes all pending device updates in a single batch.
    private func processPendingUpdates() {
        guard !pendingUpdates.isEmpty else { return }

        let updates = pendingUpdates
        pendingUpdates = []
        logger.debug("Processing \(updates.count) batched device updates")

        withAnimation(.easeInOut(duration: 0.2)) {
            for (device, type) in updates {
                applyDeviceUpdate(device, type: type)
            }
        }
    }

    // MARK: - Private Helpers

    private func applyDeviceUpdate(_ device: Device, type: DiscoveryManager.UpdateType) {
        logger.debug("applyDeviceUpdate: \(device.mac) type=\(String(describing: type)) hostname=\(device.hostname ?? "nil") deviceType=\(device.deviceType.rawValue)")

        switch type {
        case .discovered:
            if !devices.contains(where: { $0.mac == device.mac }) {
                devices.append(device)
                devices.sort { $0.smartScore > $1.smartScore }
                logger.debug("  -> Added new device")
            }
        case .updated:
            if let index = devices.firstIndex(where: { $0.mac == device.mac }) {
                let oldDevice = devices[index]
                devices[index] = device
                logger.debug("  -> Updated existing device (old hostname=\(oldDevice.hostname ?? "nil"), new hostname=\(device.hostname ?? "nil"))")
            } else {
                devices.append(device)
                devices.sort { $0.smartScore > $1.smartScore }
                logger.debug("  -> Added as new (was update but not found)")
            }
        case .wentOffline:
            if let index = devices.firstIndex(where: { $0.mac == device.mac }) {
                devices[index] = device
                logger.debug("  -> Marked offline")
            }
        }
    }

    private func applyDevicesUpdate(_ newDevices: [Device]) {
        withAnimation(.easeInOut(duration: 0.2)) {
            for device in newDevices {
                if let index = devices.firstIndex(where: { $0.mac == device.mac }) {
                    devices[index] = device
                } else {
                    devices.append(device)
                }
            }
            devices.sort { $0.smartScore > $1.smartScore }
        }
    }
}
