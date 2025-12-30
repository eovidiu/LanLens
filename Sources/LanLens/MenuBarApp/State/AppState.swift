import Foundation
import SwiftUI
import LanLensCore

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
        guard !passiveDiscoveryActive else { return }

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
        passiveDiscoveryActive = false

        Task {
            await DiscoveryManager.shared.stopPassiveDiscovery()
            await MainActor.run {
                self.isScanning = false
            }
        }
    }

    func runQuickScan() async {
        isScanning = true
        scanError = nil

        print("Starting quick scan")

        do {
            // Read ARP table first
            print("Reading ARP table...")
            let arpDevices = try await DiscoveryManager.shared.getARPDevices()
            print("ARP scan found \(arpDevices.count) devices")
            applyDevicesUpdate(arpDevices)
        } catch {
            scanError = "ARP scan failed: \(error.localizedDescription)"
        }

        // Start passive discovery (SSDP + mDNS) to detect smart devices
        print("Starting passive discovery (SSDP + mDNS)...")
        await DiscoveryManager.shared.startPassiveDiscovery { [weak self] device, updateType in
            Task { @MainActor [weak self] in
                self?.queueDeviceUpdate(device, type: updateType)
            }
        }

        // Run dns-sd discovery with debounced callback
        print("Starting DNS-SD discovery (5 seconds)...")
        await DiscoveryManager.shared.runDNSSDDiscovery(duration: 5) { [weak self] device, updateType in
            Task { @MainActor [weak self] in
                self?.queueDeviceUpdate(device, type: updateType)
            }
        }

        // Stop passive discovery after DNS-SD completes
        await DiscoveryManager.shared.stopPassiveDiscovery()

        await refreshDevices()
        lastScanTime = Date()
        isScanning = false
    }

    func runFullScan() async {
        isScanning = true
        scanError = nil

        do {
            // Start with ARP
            let arpDevices = try await DiscoveryManager.shared.getARPDevices()
            applyDevicesUpdate(arpDevices)
        } catch {
            scanError = "ARP scan failed: \(error.localizedDescription)"
        }

        // Run passive discovery briefly with debounced callback
        await DiscoveryManager.shared.startPassiveDiscovery { [weak self] device, updateType in
            Task { @MainActor [weak self] in
                self?.queueDeviceUpdate(device, type: updateType)
            }
        }

        // Run dns-sd discovery with debounced callback
        await DiscoveryManager.shared.runDNSSDDiscovery(duration: 5) { [weak self] device, updateType in
            Task { @MainActor [weak self] in
                self?.queueDeviceUpdate(device, type: updateType)
            }
        }

        // Stop passive discovery
        await DiscoveryManager.shared.stopPassiveDiscovery()

        // Run full port scan on all devices
        await DiscoveryManager.shared.fullScanAllDevices()

        await refreshDevices()
        lastScanTime = Date()
        isScanning = false
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

        // Use a continuation to properly track server startup
        apiServerTask = Task.detached(priority: .utility) { [weak self] in
            do {
                // Signal that we're about to start
                await MainActor.run {
                    self?.isAPIRunning = true
                }

                try await server.run()

                // Server stopped gracefully
                await MainActor.run {
                    self?.isAPIRunning = false
                    self?.apiServer = nil
                }
            } catch {
                // Server failed - clean up state
                await MainActor.run {
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

        withAnimation(.easeInOut(duration: 0.2)) {
            for (device, type) in updates {
                applyDeviceUpdate(device, type: type)
            }
        }
    }

    // MARK: - Private Helpers

    private func applyDeviceUpdate(_ device: Device, type: DiscoveryManager.UpdateType) {
        switch type {
        case .discovered:
            if !devices.contains(where: { $0.mac == device.mac }) {
                devices.append(device)
                devices.sort { $0.smartScore > $1.smartScore }
            }
        case .updated:
            if let index = devices.firstIndex(where: { $0.mac == device.mac }) {
                devices[index] = device
            } else {
                devices.append(device)
                devices.sort { $0.smartScore > $1.smartScore }
            }
        case .wentOffline:
            if let index = devices.firstIndex(where: { $0.mac == device.mac }) {
                devices[index] = device
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
