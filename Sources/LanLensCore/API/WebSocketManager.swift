import Foundation
import HummingbirdWebSocket
import NIOWebSocket

/// Events that can be broadcast to WebSocket clients
public enum WebSocketEvent: Sendable {
    case deviceDiscovered(Device)
    case deviceUpdated(Device)
    case deviceOffline(Device)
    case scanStarted(scanType: String)
    case scanCompleted(scanType: String, deviceCount: Int)

    /// JSON representation of the event
    var jsonPayload: String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data: Data
            switch self {
            case .deviceDiscovered(let device):
                data = try encoder.encode(WebSocketMessage(
                    type: "deviceDiscovered",
                    payload: device
                ))
            case .deviceUpdated(let device):
                data = try encoder.encode(WebSocketMessage(
                    type: "deviceUpdated",
                    payload: device
                ))
            case .deviceOffline(let device):
                data = try encoder.encode(WebSocketMessage(
                    type: "deviceOffline",
                    payload: device
                ))
            case .scanStarted(let scanType):
                data = try encoder.encode(WebSocketMessage(
                    type: "scanStarted",
                    payload: ScanEventPayload(scanType: scanType, deviceCount: nil)
                ))
            case .scanCompleted(let scanType, let deviceCount):
                data = try encoder.encode(WebSocketMessage(
                    type: "scanCompleted",
                    payload: ScanEventPayload(scanType: scanType, deviceCount: deviceCount)
                ))
            }
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            Log.error("Failed to encode WebSocket event: \(error)", category: .websocket)
            return "{\"type\":\"error\",\"message\":\"encoding failed\"}"
        }
    }
}

/// Generic WebSocket message wrapper
private struct WebSocketMessage<T: Encodable & Sendable>: Encodable, Sendable {
    let type: String
    let payload: T
    let timestamp: Date

    init(type: String, payload: T) {
        self.type = type
        self.payload = payload
        self.timestamp = Date()
    }
}

/// Payload for scan events
private struct ScanEventPayload: Codable, Sendable {
    let scanType: String
    let deviceCount: Int?
}

/// Manages WebSocket connections and broadcasts events to all connected clients
public actor WebSocketManager {
    /// Shared singleton instance
    public static let shared = WebSocketManager()

    /// Connected WebSocket clients keyed by UUID
    private var connections: [UUID: WebSocketConnection] = [:]

    /// Optional auth token for securing WebSocket connections
    private var authToken: String?

    private init() {}

    /// Configure auth token for secured connections
    public func setAuthToken(_ token: String?) {
        self.authToken = token
        Log.info("WebSocket auth \(token != nil ? "enabled" : "disabled")", category: .websocket)
    }

    /// Add a new WebSocket connection with authentication check
    /// - Parameters:
    ///   - outbound: The WebSocket outbound writer
    ///   - providedToken: Token provided by the client for authentication
    /// - Returns: Connection UUID if authenticated, nil if auth failed
    public func addConnection(
        outbound: WebSocketOutboundWriter,
        providedToken: String?
    ) -> UUID? {
        // Validate auth if token is configured
        if let requiredToken = authToken {
            guard let provided = providedToken, provided == requiredToken else {
                Log.warning("WebSocket connection rejected: invalid or missing token", category: .websocket)
                return nil
            }
        }

        let id = UUID()
        connections[id] = WebSocketConnection(id: id, outbound: outbound)
        Log.info("WebSocket client connected: \(id.uuidString) (total: \(connections.count))", category: .websocket)
        return id
    }

    /// Add a WebSocket connection directly (auth already validated)
    /// - Parameters:
    ///   - id: The connection UUID
    ///   - outbound: The WebSocket outbound writer
    public func addConnectionDirect(id: UUID, outbound: WebSocketOutboundWriter) {
        connections[id] = WebSocketConnection(id: id, outbound: outbound)
        Log.info("WebSocket client connected: \(id.uuidString) (total: \(connections.count))", category: .websocket)
    }

    /// Remove a WebSocket connection
    public func removeConnection(id: UUID) {
        connections.removeValue(forKey: id)
        Log.info("WebSocket client disconnected: \(id.uuidString) (total: \(connections.count))", category: .websocket)
    }

    /// Broadcast an event to all connected clients
    public func broadcast(_ event: WebSocketEvent) async {
        guard !connections.isEmpty else { return }

        let payload = event.jsonPayload
        Log.debug("Broadcasting to \(connections.count) clients: \(event)", category: .websocket)

        var disconnectedIds: [UUID] = []

        for (id, connection) in connections {
            do {
                try await connection.outbound.write(.text(payload))
            } catch {
                Log.warning("Failed to send to client \(id): \(error)", category: .websocket)
                disconnectedIds.append(id)
            }
        }

        // Clean up failed connections
        for id in disconnectedIds {
            connections.removeValue(forKey: id)
        }
    }

    /// Get current connection count
    public var connectionCount: Int {
        connections.count
    }

    /// Broadcast device discovered event (convenience method)
    public func broadcastDeviceDiscovered(_ device: Device) async {
        await broadcast(.deviceDiscovered(device))
    }

    /// Broadcast device updated event (convenience method)
    public func broadcastDeviceUpdated(_ device: Device) async {
        await broadcast(.deviceUpdated(device))
    }

    /// Broadcast device offline event (convenience method)
    public func broadcastDeviceOffline(_ device: Device) async {
        await broadcast(.deviceOffline(device))
    }

    /// Broadcast scan started event (convenience method)
    public func broadcastScanStarted(scanType: String) async {
        await broadcast(.scanStarted(scanType: scanType))
    }

    /// Broadcast scan completed event (convenience method)
    public func broadcastScanCompleted(scanType: String, deviceCount: Int) async {
        await broadcast(.scanCompleted(scanType: scanType, deviceCount: deviceCount))
    }
}

/// Represents a single WebSocket connection
private struct WebSocketConnection: Sendable {
    let id: UUID
    let outbound: WebSocketOutboundWriter
    let connectedAt: Date

    init(id: UUID, outbound: WebSocketOutboundWriter) {
        self.id = id
        self.outbound = outbound
        self.connectedAt = Date()
    }
}
