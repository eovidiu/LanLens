import Foundation

/// Protocol for Fingerbank API service
public protocol FingerbankServiceProtocol: Actor {
    /// Query Fingerbank API for device identification
    /// - Parameters:
    ///   - mac: Device MAC address
    ///   - dhcpFingerprint: Optional DHCP fingerprint (option 55 parameter request list)
    ///   - userAgents: Optional list of HTTP user agents observed
    ///   - apiKey: Fingerbank API key
    /// - Returns: Fingerprint data from Fingerbank
    /// - Throws: FingerbankError on failure
    func interrogate(
        mac: String,
        dhcpFingerprint: String?,
        userAgents: [String]?,
        apiKey: String
    ) async throws -> DeviceFingerprint
    
    /// Reset rate limiting (for testing or after manual confirmation)
    func resetRateLimit()
}

// MARK: - Conformance

extension FingerbankService: FingerbankServiceProtocol {}
