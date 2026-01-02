import Foundation
import Network
import Security

// MARK: - TLS Fingerprint Prober

/// Actor that probes devices with HTTPS ports to capture Server Hello fingerprints.
///
/// This prober uses Network.framework's NWConnection with TLS to establish connections
/// to devices and capture TLS handshake information for JA3S fingerprinting.
///
/// Usage:
/// ```swift
/// let prober = TLSFingerprintProber.shared
/// let result = await prober.probe(host: "192.168.1.100", port: 443)
/// if let fingerprint = result.ja3sFingerprint {
///     print("JA3S: \(fingerprint.hash)")
/// }
/// ```
public actor TLSFingerprintProber {

    // MARK: - Singleton

    /// Shared instance for global access
    public static let shared = TLSFingerprintProber()

    // MARK: - Types

    /// Result of a TLS probe
    public struct ProbeResult: Sendable {
        /// Host that was probed
        public var host: String

        /// Port that was probed
        public var port: UInt16

        /// JA3S fingerprint from Server Hello (if captured)
        public var ja3sFingerprint: JA3SFingerprint?

        /// Server certificate information (if available)
        public var serverCertificate: ServerCertificateInfo?

        /// Negotiated TLS version
        public var tlsVersion: UInt16?

        /// Negotiated cipher suite
        public var cipherSuite: UInt16?

        /// Error if probe failed
        public var error: ProbeError?

        /// When the probe was performed
        public var probedAt: Date

        /// Whether the probe was successful
        public var isSuccess: Bool {
            error == nil && (ja3sFingerprint != nil || cipherSuite != nil)
        }

        public init(
            host: String,
            port: UInt16,
            ja3sFingerprint: JA3SFingerprint? = nil,
            serverCertificate: ServerCertificateInfo? = nil,
            tlsVersion: UInt16? = nil,
            cipherSuite: UInt16? = nil,
            error: ProbeError? = nil,
            probedAt: Date = Date()
        ) {
            self.host = host
            self.port = port
            self.ja3sFingerprint = ja3sFingerprint
            self.serverCertificate = serverCertificate
            self.tlsVersion = tlsVersion
            self.cipherSuite = cipherSuite
            self.error = error
            self.probedAt = probedAt
        }
    }

    /// Errors that can occur during TLS probing
    public enum ProbeError: Error, Sendable, CustomStringConvertible {
        case connectionFailed(String)
        case timeout
        case tlsHandshakeFailed(String)
        case parseError(String)
        case cancelled
        case noTLSInfo

        public var description: String {
            switch self {
            case .connectionFailed(let reason):
                return "Connection failed: \(reason)"
            case .timeout:
                return "Connection timed out"
            case .tlsHandshakeFailed(let reason):
                return "TLS handshake failed: \(reason)"
            case .parseError(let reason):
                return "Parse error: \(reason)"
            case .cancelled:
                return "Probe cancelled"
            case .noTLSInfo:
                return "No TLS information available"
            }
        }
    }

    /// Basic certificate information extracted from TLS handshake
    public struct ServerCertificateInfo: Codable, Sendable, Equatable {
        /// Common Name from the certificate subject
        public var commonName: String?

        /// Organization from the certificate subject
        public var organization: String?

        /// Issuer Common Name
        public var issuer: String?

        /// Certificate validity start
        public var validFrom: Date?

        /// Certificate validity end
        public var validTo: Date?

        /// Subject Alternative Names (if available)
        public var subjectAltNames: [String]?

        public init(
            commonName: String? = nil,
            organization: String? = nil,
            issuer: String? = nil,
            validFrom: Date? = nil,
            validTo: Date? = nil,
            subjectAltNames: [String]? = nil
        ) {
            self.commonName = commonName
            self.organization = organization
            self.issuer = issuer
            self.validFrom = validFrom
            self.validTo = validTo
            self.subjectAltNames = subjectAltNames
        }

        /// Whether the certificate is currently valid
        public var isValid: Bool {
            guard let from = validFrom, let to = validTo else { return false }
            let now = Date()
            return now >= from && now <= to
        }
    }

    // MARK: - Configuration

    /// Common HTTPS ports to probe
    public static let commonHTTPSPorts: [UInt16] = [443, 8443, 8080, 9443]

    /// Default timeout for probing
    public static let defaultTimeout: TimeInterval = 5.0

    /// Maximum concurrent probes
    private let maxConcurrentProbes = 10

    // MARK: - Properties

    /// Queue for TLS operations
    private let queue = DispatchQueue(label: "com.lanlens.tls.prober", qos: .utility)

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Interface

    /// Probe a device's HTTPS port to capture TLS fingerprint.
    ///
    /// - Parameters:
    ///   - host: IP address or hostname
    ///   - port: Port number (default 443)
    ///   - timeout: Connection timeout in seconds
    /// - Returns: Probe result with fingerprint data
    public func probe(
        host: String,
        port: UInt16 = 443,
        timeout: TimeInterval = defaultTimeout
    ) async -> ProbeResult {
        Log.debug("Probing TLS: \(host):\(port)", category: .tls)

        return await withCheckedContinuation { continuation in
            performProbe(host: host, port: port, timeout: timeout) { result in
                continuation.resume(returning: result)
            }
        }
    }

    /// Probe multiple ports on a device.
    ///
    /// - Parameters:
    ///   - host: IP address or hostname
    ///   - ports: Ports to probe
    ///   - timeout: Timeout per connection
    /// - Returns: Array of probe results
    public func probeMultiple(
        host: String,
        ports: [UInt16],
        timeout: TimeInterval = defaultTimeout
    ) async -> [ProbeResult] {
        await withTaskGroup(of: ProbeResult.self) { group in
            for port in ports {
                group.addTask {
                    await self.probe(host: host, port: port, timeout: timeout)
                }
            }

            var results: [ProbeResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    /// Probe common HTTPS ports on a device.
    ///
    /// - Parameters:
    ///   - host: IP address or hostname
    ///   - timeout: Timeout per connection
    /// - Returns: Array of successful probe results
    public func probeCommonPorts(
        host: String,
        timeout: TimeInterval = defaultTimeout
    ) async -> [ProbeResult] {
        let results = await probeMultiple(host: host, ports: Self.commonHTTPSPorts, timeout: timeout)
        return results.filter { $0.isSuccess }
    }

    // MARK: - Private Implementation

    private func performProbe(
        host: String,
        port: UInt16,
        timeout: TimeInterval,
        completion: @escaping @Sendable (ProbeResult) -> Void
    ) {
        // Create endpoint
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )

        // Configure TLS with insecure options to accept any certificate
        // (we're fingerprinting, not validating)
        let tlsOptions = NWProtocolTLS.Options()

        // Disable certificate verification for fingerprinting purposes
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, _, completionHandler in
                // Accept all certificates - we're just fingerprinting
                completionHandler(true)
            },
            queue
        )

        // Set minimum TLS version to TLS 1.2 (TLS 1.0/1.1 are deprecated)
        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv12
        )

        // Create parameters with TLS
        let parameters = NWParameters(tls: tlsOptions)
        parameters.allowLocalEndpointReuse = true

        // Create connection
        let connection = NWConnection(to: endpoint, using: parameters)

        // Track state
        var hasCompleted = false
        let completionLock = NSLock()

        func complete(with result: ProbeResult) {
            completionLock.lock()
            defer { completionLock.unlock() }

            guard !hasCompleted else { return }
            hasCompleted = true

            connection.cancel()
            completion(result)
        }

        // Set timeout
        queue.asyncAfter(deadline: .now() + timeout) {
            complete(with: ProbeResult(
                host: host,
                port: port,
                error: .timeout
            ))
        }

        // Handle state changes
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }

            switch state {
            case .ready:
                // Connection established, extract TLS info
                Log.debug("TLS connection ready: \(host):\(port)", category: .tls)

                let result = self.extractTLSInfo(from: connection, host: host, port: port)
                complete(with: result)

            case .failed(let error):
                Log.debug("TLS connection failed: \(host):\(port) - \(error)", category: .tls)
                complete(with: ProbeResult(
                    host: host,
                    port: port,
                    error: .connectionFailed(error.localizedDescription)
                ))

            case .cancelled:
                complete(with: ProbeResult(
                    host: host,
                    port: port,
                    error: .cancelled
                ))

            case .waiting(let error):
                Log.debug("TLS connection waiting: \(host):\(port) - \(error)", category: .tls)

            default:
                break
            }
        }

        // Start connection
        connection.start(queue: queue)
    }

    /// Extract TLS info from a connection - nonisolated to be called from dispatch callback
    nonisolated private func extractTLSInfo(
        from connection: NWConnection,
        host: String,
        port: UInt16
    ) -> ProbeResult {
        // Get security protocol metadata
        guard let secProtocol = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else {
            Log.warning("No TLS metadata available for \(host):\(port)", category: .tls)
            return ProbeResult(host: host, port: port, error: .noTLSInfo)
        }

        // Extract negotiated TLS version and cipher
        let securityMetadata = secProtocol.securityProtocolMetadata

        var tlsVersion: UInt16?
        var cipherSuite: UInt16?
        var serverCertInfo: ServerCertificateInfo?

        // Get TLS version
        let negotiatedVersion = sec_protocol_metadata_get_negotiated_tls_protocol_version(securityMetadata)
        tlsVersion = tlsVersionToUInt16(negotiatedVersion)

        // Get cipher suite
        let negotiatedCipherSuite = sec_protocol_metadata_get_negotiated_tls_ciphersuite(securityMetadata)
        cipherSuite = UInt16(negotiatedCipherSuite.rawValue)

        // Extract certificate info using sec_protocol_metadata_access_peer_certificate_chain
        serverCertInfo = extractCertificateInfo(from: securityMetadata)

        // Build JA3S fingerprint from available data
        // Note: Network.framework doesn't expose raw Server Hello, so we construct
        // a fingerprint from the negotiated parameters
        var ja3sFingerprint: JA3SFingerprint?
        if let version = tlsVersion, let cipher = cipherSuite {
            // We don't have access to extensions through Network.framework,
            // so we create a fingerprint with empty extensions
            ja3sFingerprint = JA3SHashGenerator.generate(
                sslVersion: version,
                cipher: cipher,
                extensions: []
            )
        }

        Log.info("TLS probe success: \(host):\(port) - \(TLSVersion.name(for: tlsVersion ?? 0)), cipher=\(cipherSuite.map { String($0) } ?? "unknown")", category: .tls)

        return ProbeResult(
            host: host,
            port: port,
            ja3sFingerprint: ja3sFingerprint,
            serverCertificate: serverCertInfo,
            tlsVersion: tlsVersion,
            cipherSuite: cipherSuite
        )
    }

    nonisolated private func tlsVersionToUInt16(_ version: tls_protocol_version_t) -> UInt16 {
        switch version {
        case .TLSv10: return TLSVersion.tls10
        case .TLSv11: return TLSVersion.tls11
        case .TLSv12: return TLSVersion.tls12
        case .TLSv13: return TLSVersion.tls13
        case .DTLSv10: return 0xFEFF  // DTLS 1.0
        case .DTLSv12: return 0xFEFD  // DTLS 1.2
        @unknown default: return 0
        }
    }

    nonisolated private func extractCertificateInfo(from metadata: sec_protocol_metadata_t) -> ServerCertificateInfo? {
        var certificateInfo: ServerCertificateInfo?

        // Use sec_protocol_metadata_access_peer_certificate_chain to get certificates
        sec_protocol_metadata_access_peer_certificate_chain(metadata) { certificate in
            // Only process the first certificate (server cert)
            guard certificateInfo == nil else { return }

            // Convert sec_certificate_t to SecCertificate
            let secCertificate = sec_certificate_copy_ref(certificate).takeRetainedValue()

            var info = ServerCertificateInfo()

            // Get subject summary (usually the CN)
            if let summary = SecCertificateCopySubjectSummary(secCertificate) as String? {
                info.commonName = summary
            }

            // Try to get more detailed info via key lookup
            info = self.parseBasicCertificateFields(from: secCertificate, existingInfo: info)

            certificateInfo = info
        }

        return certificateInfo
    }

    nonisolated private func parseBasicCertificateFields(
        from certificate: SecCertificate,
        existingInfo: ServerCertificateInfo
    ) -> ServerCertificateInfo {
        var info = existingInfo

        // Get common values via OID lookup
        let keys: [CFString] = [
            kSecOIDOrganizationName,
            kSecOIDCommonName
        ]

        if let values = SecCertificateCopyValues(certificate, keys as CFArray, nil) as? [String: Any] {
            // Extract organization
            if let orgDict = values[kSecOIDOrganizationName as String] as? [String: Any],
               let orgValue = orgDict[kSecPropertyKeyValue as String] {
                if let orgArray = orgValue as? [String], let org = orgArray.first {
                    info.organization = org
                } else if let org = orgValue as? String {
                    info.organization = org
                }
            }

            // Common name might be more detailed here
            if let cnDict = values[kSecOIDCommonName as String] as? [String: Any],
               let cnValue = cnDict[kSecPropertyKeyValue as String] as? String {
                info.commonName = cnValue
            }
        }

        return info
    }
}

// MARK: - ProbeResult Extensions

extension TLSFingerprintProber.ProbeResult: CustomStringConvertible {
    public var description: String {
        if let error = error {
            return "TLSProbe(\(host):\(port)) failed: \(error)"
        }
        let version = tlsVersion.map { TLSVersion.name(for: $0) } ?? "unknown"
        let hash = ja3sFingerprint?.hash ?? "none"
        return "TLSProbe(\(host):\(port)) success: \(version), JA3S=\(hash.prefix(16))..."
    }
}
