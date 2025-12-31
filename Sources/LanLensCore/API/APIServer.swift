import Foundation
import Hummingbird
import os

/// REST API server for LanLens
public struct APIServer: Sendable {

    /// Configuration for the API server
    public struct Config: Sendable {
        public let host: String
        public let port: Int
        public let authToken: String?

        public init(host: String = "127.0.0.1", port: Int = 8080, authToken: String? = nil) {
            self.host = host
            self.port = port
            self.authToken = authToken
        }
    }

    private let config: Config
    private let serverState: ServerState

    public init(config: Config = Config()) {
        self.config = config
        self.serverState = ServerState()
    }

    /// Build the router with all routes
    public func buildRouter() -> Router<BasicRequestContext> {
        let router = Router()
        let state = self.serverState

        // Health check - returns detailed server status
        router.get("/health") { _, _ -> Response in
            let uptime = Int(Date().timeIntervalSince(state.startTime))
            let deviceCount = await DiscoveryManager.shared.getDeviceCount()
            let isScanning = await DiscoveryManager.shared.isDiscovering()
            let lastScanTime = state.getLastScanTime()

            let response = HealthResponse(
                status: "healthy",
                version: "1.0.0",
                uptime: uptime,
                deviceCount: deviceCount,
                isScanning: isScanning,
                lastScanTime: lastScanTime
            )
            return try encodeJSON(response)
        }

        // Device endpoints
        router.get("/api/devices") { _, _ -> Response in
            let devices = await DiscoveryManager.shared.getAllDevices()
            return try encodeJSON(devices)
        }

        router.get("/api/devices/smart") { request, _ -> Response in
            let minScoreStr = request.uri.queryParameters.get("minScore") ?? "20"
            let minScore = Int(minScoreStr) ?? 20
            let devices = await DiscoveryManager.shared.getSmartDevices(minScore: minScore)
            return try encodeJSON(devices)
        }

        router.get("/api/devices/:mac") { _, context -> Response in
            guard let mac = context.parameters.get("mac") else {
                return Response(status: .badRequest)
            }
            if let device = await DiscoveryManager.shared.getDevice(mac: mac) {
                return try encodeJSON(device)
            }
            return Response(status: .notFound)
        }

        // Discovery endpoints
        router.get("/api/discover/arp") { _, _ -> Response in
            do {
                let devices = try await DiscoveryManager.shared.getARPDevices()
                state.setLastScanTime(Date())
                return try encodeJSON(devices)
            } catch {
                return Response(
                    status: .internalServerError,
                    headers: [.contentType: "application/json"],
                    body: .init(byteBuffer: ByteBuffer(string: "{\"error\":\"\(error.localizedDescription)\"}"))
                )
            }
        }

        router.post("/api/discover/passive") { request, _ -> Response in
            let durationStr = request.uri.queryParameters.get("duration") ?? "10"
            let duration = Double(durationStr) ?? 10

            // Start discovery and collect results
            let collector = DeviceCollector()

            await DiscoveryManager.shared.startPassiveDiscovery { device, _ in
                Task {
                    await collector.add(device)
                }
            }

            try? await Task.sleep(for: .seconds(duration))
            await DiscoveryManager.shared.stopPassiveDiscovery()

            state.setLastScanTime(Date())
            let devices = await collector.getAll()
            return try encodeJSON(DiscoveryResult(discovered: devices.count, devices: devices))
        }

        router.post("/api/discover/dnssd") { request, _ -> Response in
            let durationStr = request.uri.queryParameters.get("duration") ?? "5"
            let duration = Double(durationStr) ?? 5

            let collector = DeviceCollector()

            await DiscoveryManager.shared.runDNSSDDiscovery(duration: duration) { device, _ in
                Task {
                    await collector.add(device)
                }
            }

            state.setLastScanTime(Date())
            let devices = await collector.getAll()
            return try encodeJSON(DiscoveryResult(discovered: devices.count, devices: devices))
        }

        // Scan endpoints
        router.post("/api/scan/ports/:mac") { _, context -> Response in
            guard let mac = context.parameters.get("mac") else {
                return Response(status: .badRequest)
            }

            if let device = await DiscoveryManager.shared.scanPorts(for: mac) {
                state.setLastScanTime(Date())
                return try encodeJSON(device)
            }
            return Response(status: .notFound)
        }

        router.post("/api/scan/quick") { _, _ -> Response in
            await DiscoveryManager.shared.quickScanAllDevices()
            state.setLastScanTime(Date())
            let devices = await DiscoveryManager.shared.getAllDevices()
            return try encodeJSON(devices)
        }

        router.post("/api/scan/full") { _, _ -> Response in
            await DiscoveryManager.shared.fullScanAllDevices()
            state.setLastScanTime(Date())
            let devices = await DiscoveryManager.shared.getAllDevices()
            return try encodeJSON(devices)
        }

        router.get("/api/scan/nmap-status") { _, _ -> Response in
            let available = await PortScanner.shared.isNmapAvailable()
            return try encodeJSON(["available": available])
        }

        // Tool status
        router.get("/api/tools") { _, _ -> Response in
            let report = await ToolChecker.shared.checkAllTools()
            return try encodeJSON(ToolStatusResponse(
                allRequiredAvailable: report.allRequiredAvailable,
                tools: report.tools.map { tool in
                    ToolInfo(
                        name: tool.name,
                        available: tool.isAvailable,
                        required: tool.isRequired,
                        path: tool.path,
                        installHint: tool.installHint
                    )
                }
            ))
        }

        return router
    }

    /// Start the API server (blocking)
    public func run() async throws {
        var router = buildRouter()

        // Add auth middleware if configured
        if let token = config.authToken {
            router.middlewares.add(AuthMiddleware(token: token))
        }

        let app = Application(
            router: router,
            configuration: .init(address: .hostname(config.host, port: config.port))
        )

        print("Starting API server on http://\(config.host):\(config.port)")
        if config.authToken != nil {
            print("Authentication enabled - use Bearer token or ?token= query parameter")
        }

        try await app.runService()
    }
}

// MARK: - Server State

/// Tracks server state across requests (thread-safe)
final class ServerState: Sendable {
    let startTime: Date

    private let _lastScanTime: OSAllocatedUnfairLock<Date?>

    init() {
        self.startTime = Date()
        self._lastScanTime = OSAllocatedUnfairLock(initialState: nil)
    }

    func getLastScanTime() -> Date? {
        _lastScanTime.withLock { $0 }
    }

    func setLastScanTime(_ date: Date) {
        _lastScanTime.withLock { $0 = date }
    }
}

// MARK: - Response Models

/// Health check response
struct HealthResponse: Codable, Sendable {
    let status: String
    let version: String
    let uptime: Int
    let deviceCount: Int
    let isScanning: Bool
    let lastScanTime: Date?
}

struct DiscoveryResult: Codable, Sendable {
    let discovered: Int
    let devices: [Device]
}

struct ToolStatusResponse: Codable, Sendable {
    let allRequiredAvailable: Bool
    let tools: [ToolInfo]
}

struct ToolInfo: Codable, Sendable {
    let name: String
    let available: Bool
    let required: Bool
    let path: String?
    let installHint: String?
}

// MARK: - Device Collector (Thread-safe)

private actor DeviceCollector {
    private var devices: [Device] = []

    func add(_ device: Device) {
        if !devices.contains(where: { $0.mac == device.mac }) {
            devices.append(device)
        }
    }

    func getAll() -> [Device] {
        return devices
    }
}

// MARK: - Auth Middleware

struct AuthMiddleware: RouterMiddleware {
    typealias Context = BasicRequestContext

    let token: String

    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        // Check for Authorization header
        if let authHeader = request.headers[.authorization],
           authHeader == "Bearer \(token)" {
            return try await next(request, context)
        }

        // Check for token query parameter (for simple testing)
        if request.uri.queryParameters.get("token") == token {
            return try await next(request, context)
        }

        return Response(
            status: .unauthorized,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(string: "{\"error\":\"unauthorized\"}"))
        )
    }
}

// MARK: - JSON Encoding Helper

private func encodeJSON<T: Encodable>(_ value: T) throws -> Response {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    return Response(
        status: .ok,
        headers: [.contentType: "application/json"],
        body: .init(byteBuffer: ByteBuffer(data: data))
    )
}
