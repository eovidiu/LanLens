import Foundation

/// Service for querying the Fingerbank API for device identification
public actor FingerbankService {
    public static let shared = FingerbankService()

    private let baseURL = "https://api.fingerbank.org/api/v2/combinations/interrogate"
    private let session: URLSession
    private let timeout: TimeInterval = 10.0

    // Rate limiting
    private var lastRequestTime: Date?
    private var requestCount = 0
    private var rateLimitResetTime: Date?

    public enum FingerbankError: Error, Sendable {
        case noAPIKey
        case invalidAPIKey
        case rateLimitExceeded(resetAt: Date?)
        case serverError(statusCode: Int)
        case networkError(Error)
        case invalidResponse
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: config)
    }

    /// Query Fingerbank API for device identification
    /// - Parameters:
    ///   - mac: Device MAC address
    ///   - dhcpFingerprint: Optional DHCP fingerprint (option 55 parameter request list)
    ///   - userAgents: Optional list of HTTP user agents observed
    ///   - apiKey: Fingerbank API key
    /// - Returns: Fingerprint data from Fingerbank
    public func interrogate(
        mac: String,
        dhcpFingerprint: String? = nil,
        userAgents: [String]? = nil,
        apiKey: String
    ) async throws -> DeviceFingerprint {
        guard !apiKey.isEmpty else {
            throw FingerbankError.noAPIKey
        }

        // Check rate limiting
        if let resetTime = rateLimitResetTime, Date() < resetTime {
            throw FingerbankError.rateLimitExceeded(resetAt: resetTime)
        }

        // Build request
        guard let url = URL(string: baseURL) else {
            throw FingerbankError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build request body
        var body: [String: Any] = ["mac": mac.uppercased()]
        if let dhcp = dhcpFingerprint, !dhcp.isEmpty {
            body["dhcp_fingerprint"] = dhcp
        }
        if let agents = userAgents, !agents.isEmpty {
            body["user_agents"] = agents
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw FingerbankError.invalidResponse
            }

            // Handle response status
            switch httpResponse.statusCode {
            case 200...299:
                return try parseResponse(data: data)

            case 401:
                throw FingerbankError.invalidAPIKey

            case 429:
                // Rate limited - set reset time to 1 hour from now
                let resetTime = Date().addingTimeInterval(3600)
                rateLimitResetTime = resetTime
                throw FingerbankError.rateLimitExceeded(resetAt: resetTime)

            case 500...599:
                throw FingerbankError.serverError(statusCode: httpResponse.statusCode)

            default:
                throw FingerbankError.serverError(statusCode: httpResponse.statusCode)
            }
        } catch let error as FingerbankError {
            throw error
        } catch {
            throw FingerbankError.networkError(error)
        }
    }

    /// Reset rate limiting (for testing or after manual confirmation)
    public func resetRateLimit() {
        rateLimitResetTime = nil
        requestCount = 0
    }

    // MARK: - Response Parsing

    private func parseResponse(data: Data) throws -> DeviceFingerprint {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FingerbankError.invalidResponse
        }

        // Parse device info
        var deviceName: String?
        var deviceId: Int?
        var parents: [String]?
        var isMobile: Bool?
        var isTablet: Bool?

        if let device = json["device"] as? [String: Any] {
            deviceName = device["name"] as? String
            deviceId = device["id"] as? Int
            isMobile = device["mobile"] as? Bool
            isTablet = device["tablet"] as? Bool

            // Parse parents hierarchy
            if let parentsList = device["parents"] as? [[String: Any]] {
                parents = parentsList.compactMap { $0["name"] as? String }
            }
        }

        // Parse score
        let score = json["score"] as? Int

        // Parse version/OS info
        let version = json["version"] as? String

        // Extract OS from version or device name
        var osName: String?
        var osVersion: String?

        if let ver = version {
            // Version might be like "iOS 17.2" or "Android 14"
            let parts = ver.split(separator: " ", maxSplits: 1)
            if parts.count >= 1 {
                osName = String(parts[0])
            }
            if parts.count >= 2 {
                osVersion = String(parts[1])
            }
        }

        return DeviceFingerprint(
            fingerbankDeviceName: deviceName,
            fingerbankDeviceId: deviceId,
            fingerbankParents: parents,
            fingerbankScore: score,
            operatingSystem: osName,
            osVersion: osVersion ?? version,
            isMobile: isMobile,
            isTablet: isTablet,
            source: .fingerbank,
            timestamp: Date(),
            cacheHit: false
        )
    }
}
