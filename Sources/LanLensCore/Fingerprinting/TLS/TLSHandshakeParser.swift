import Foundation

// MARK: - TLS Handshake Parser

/// Parser for TLS handshake messages.
///
/// This parser extracts Server Hello data from TLS handshake records for JA3S fingerprinting.
/// It supports TLS 1.0 through TLS 1.3 handshake formats.
///
/// TLS Record Structure:
/// ```
/// +------------------+
/// | Content Type (1) |
/// +------------------+
/// | Version (2)      |
/// +------------------+
/// | Length (2)       |
/// +------------------+
/// | Fragment (n)     |
/// +------------------+
/// ```
public struct TLSHandshakeParser: Sendable {

    // MARK: - Content Types

    /// TLS record content types
    public enum ContentType: UInt8, Sendable {
        case changeCipherSpec = 20
        case alert = 21
        case handshake = 22
        case applicationData = 23
    }

    // MARK: - Handshake Types

    /// TLS handshake message types
    public enum HandshakeType: UInt8, Sendable {
        case helloRequest = 0
        case clientHello = 1
        case serverHello = 2
        case newSessionTicket = 4
        case endOfEarlyData = 5
        case encryptedExtensions = 8
        case certificate = 11
        case serverKeyExchange = 12
        case certificateRequest = 13
        case serverHelloDone = 14
        case certificateVerify = 15
        case clientKeyExchange = 16
        case finished = 20
        case keyUpdate = 24
        case messageHash = 254
    }

    // MARK: - TLS Extension

    /// Parsed TLS extension
    public struct TLSExtension: Sendable, Equatable {
        /// Extension type (see RFC 8446 Section 4.2)
        public var type: UInt16

        /// Extension data
        public var data: Data

        public init(type: UInt16, data: Data) {
            self.type = type
            self.data = data
        }

        /// Human-readable extension name
        public var name: String {
            ExtensionType.name(for: type)
        }
    }

    // MARK: - Server Hello

    /// Parsed Server Hello message
    public struct ServerHello: Sendable, Equatable {
        /// TLS version from the Server Hello
        /// Note: In TLS 1.3, this is always 0x0303 (TLS 1.2) for compatibility,
        /// and the actual version is in supported_versions extension
        public var tlsVersion: UInt16

        /// 32 bytes of server random
        public var random: Data

        /// Session ID (may be empty in TLS 1.3)
        public var sessionId: Data?

        /// Selected cipher suite
        public var cipherSuite: UInt16

        /// Compression method (always 0 in TLS 1.3)
        public var compressionMethod: UInt8

        /// Server extensions
        public var extensions: [TLSExtension]

        /// Actual TLS version (from supported_versions extension or legacy version)
        public var actualTLSVersion: UInt16 {
            // Check for supported_versions extension (type 43)
            if let supportedVersions = extensions.first(where: { $0.type == 43 }) {
                // In Server Hello, supported_versions contains a single 2-byte version
                if supportedVersions.data.count >= 2 {
                    return UInt16(supportedVersions.data[0]) << 8 | UInt16(supportedVersions.data[1])
                }
            }
            return tlsVersion
        }

        public init(
            tlsVersion: UInt16,
            random: Data,
            sessionId: Data? = nil,
            cipherSuite: UInt16,
            compressionMethod: UInt8,
            extensions: [TLSExtension]
        ) {
            self.tlsVersion = tlsVersion
            self.random = random
            self.sessionId = sessionId
            self.cipherSuite = cipherSuite
            self.compressionMethod = compressionMethod
            self.extensions = extensions
        }
    }

    // MARK: - Parsing Methods

    /// Parse a Server Hello from raw TLS record data.
    ///
    /// - Parameter data: Raw TLS record data (starting with record header)
    /// - Returns: Parsed Server Hello, or nil if parsing fails
    public static func parseServerHello(from data: Data) -> ServerHello? {
        guard data.count >= 5 else {
            Log.debug("TLS record too short: \(data.count) bytes", category: .tls)
            return nil
        }

        var offset = 0

        // TLS Record Header
        let contentType = data[offset]
        offset += 1

        guard contentType == ContentType.handshake.rawValue else {
            Log.debug("Not a handshake record: content type \(contentType)", category: .tls)
            return nil
        }

        // Record version (2 bytes) - skip, we use handshake version
        offset += 2

        // Record length (2 bytes)
        let recordLength = Int(data[offset]) << 8 | Int(data[offset + 1])
        offset += 2

        guard data.count >= offset + recordLength else {
            Log.debug("TLS record truncated: expected \(recordLength) bytes, have \(data.count - offset)", category: .tls)
            return nil
        }

        // Handshake Header
        guard data.count > offset else { return nil }
        let handshakeType = data[offset]
        offset += 1

        guard handshakeType == HandshakeType.serverHello.rawValue else {
            Log.debug("Not a Server Hello: handshake type \(handshakeType)", category: .tls)
            return nil
        }

        // Handshake length (3 bytes)
        guard data.count >= offset + 3 else { return nil }
        let handshakeLength = Int(data[offset]) << 16 | Int(data[offset + 1]) << 8 | Int(data[offset + 2])
        offset += 3

        guard data.count >= offset + handshakeLength else {
            Log.debug("Server Hello truncated: expected \(handshakeLength) bytes", category: .tls)
            return nil
        }

        // Server Hello Content
        // Version (2 bytes)
        guard data.count >= offset + 2 else { return nil }
        let tlsVersion = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
        offset += 2

        // Random (32 bytes)
        guard data.count >= offset + 32 else { return nil }
        let random = data[offset..<offset + 32]
        offset += 32

        // Session ID Length (1 byte)
        guard data.count > offset else { return nil }
        let sessionIdLength = Int(data[offset])
        offset += 1

        // Session ID (variable)
        var sessionId: Data?
        if sessionIdLength > 0 {
            guard data.count >= offset + sessionIdLength else { return nil }
            sessionId = data[offset..<offset + sessionIdLength]
            offset += sessionIdLength
        }

        // Cipher Suite (2 bytes)
        guard data.count >= offset + 2 else { return nil }
        let cipherSuite = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
        offset += 2

        // Compression Method (1 byte)
        guard data.count > offset else { return nil }
        let compressionMethod = data[offset]
        offset += 1

        // Extensions (if present)
        var extensions: [TLSExtension] = []

        // Check if there are extensions
        if data.count >= offset + 2 {
            let extensionsLength = Int(data[offset]) << 8 | Int(data[offset + 1])
            offset += 2

            if extensionsLength > 0 && data.count >= offset + extensionsLength {
                extensions = parseExtensions(from: data, offset: offset, length: extensionsLength)
            }
        }

        return ServerHello(
            tlsVersion: tlsVersion,
            random: Data(random),
            sessionId: sessionId.map { Data($0) },
            cipherSuite: cipherSuite,
            compressionMethod: compressionMethod,
            extensions: extensions
        )
    }

    /// Extract extensions from Server Hello data.
    ///
    /// - Parameters:
    ///   - data: Full TLS record data
    ///   - offset: Starting offset of extensions data
    ///   - length: Total length of extensions data
    /// - Returns: Array of parsed extensions
    public static func extractExtensions(from data: Data, offset: Int, length: Int) -> [TLSExtension] {
        parseExtensions(from: data, offset: offset, length: length)
    }

    // MARK: - Private Helpers

    private static func parseExtensions(from data: Data, offset: Int, length: Int) -> [TLSExtension] {
        var extensions: [TLSExtension] = []
        var currentOffset = offset
        let endOffset = offset + length

        while currentOffset + 4 <= endOffset && currentOffset + 4 <= data.count {
            // Extension type (2 bytes)
            let extensionType = UInt16(data[currentOffset]) << 8 | UInt16(data[currentOffset + 1])
            currentOffset += 2

            // Extension length (2 bytes)
            let extensionLength = Int(data[currentOffset]) << 8 | Int(data[currentOffset + 1])
            currentOffset += 2

            // Extension data
            guard currentOffset + extensionLength <= data.count else { break }

            let extensionData: Data
            if extensionLength > 0 {
                extensionData = data[currentOffset..<currentOffset + extensionLength]
            } else {
                extensionData = Data()
            }

            extensions.append(TLSExtension(type: extensionType, data: Data(extensionData)))
            currentOffset += extensionLength
        }

        return extensions
    }
}

// MARK: - Extension Types

/// Common TLS extension types (RFC 8446)
public enum ExtensionType {
    public static let serverName: UInt16 = 0
    public static let maxFragmentLength: UInt16 = 1
    public static let statusRequest: UInt16 = 5
    public static let supportedGroups: UInt16 = 10
    public static let signatureAlgorithms: UInt16 = 13
    public static let useSrtp: UInt16 = 14
    public static let heartbeat: UInt16 = 15
    public static let alpn: UInt16 = 16
    public static let signedCertTimestamp: UInt16 = 18
    public static let clientCertificateType: UInt16 = 19
    public static let serverCertificateType: UInt16 = 20
    public static let padding: UInt16 = 21
    public static let encryptThenMac: UInt16 = 22
    public static let extendedMasterSecret: UInt16 = 23
    public static let sessionTicket: UInt16 = 35
    public static let preSharedKey: UInt16 = 41
    public static let earlyData: UInt16 = 42
    public static let supportedVersions: UInt16 = 43
    public static let cookie: UInt16 = 44
    public static let pskKeyExchangeModes: UInt16 = 45
    public static let certificateAuthorities: UInt16 = 47
    public static let oidFilters: UInt16 = 48
    public static let postHandshakeAuth: UInt16 = 49
    public static let signatureAlgorithmsCert: UInt16 = 50
    public static let keyShare: UInt16 = 51
    public static let renegotiationInfo: UInt16 = 65281

    /// Get human-readable name for extension type
    public static func name(for type: UInt16) -> String {
        switch type {
        case serverName: return "server_name"
        case maxFragmentLength: return "max_fragment_length"
        case statusRequest: return "status_request"
        case supportedGroups: return "supported_groups"
        case signatureAlgorithms: return "signature_algorithms"
        case useSrtp: return "use_srtp"
        case heartbeat: return "heartbeat"
        case alpn: return "application_layer_protocol_negotiation"
        case signedCertTimestamp: return "signed_certificate_timestamp"
        case clientCertificateType: return "client_certificate_type"
        case serverCertificateType: return "server_certificate_type"
        case padding: return "padding"
        case encryptThenMac: return "encrypt_then_mac"
        case extendedMasterSecret: return "extended_master_secret"
        case sessionTicket: return "session_ticket"
        case preSharedKey: return "pre_shared_key"
        case earlyData: return "early_data"
        case supportedVersions: return "supported_versions"
        case cookie: return "cookie"
        case pskKeyExchangeModes: return "psk_key_exchange_modes"
        case certificateAuthorities: return "certificate_authorities"
        case oidFilters: return "oid_filters"
        case postHandshakeAuth: return "post_handshake_auth"
        case signatureAlgorithmsCert: return "signature_algorithms_cert"
        case keyShare: return "key_share"
        case renegotiationInfo: return "renegotiation_info"
        default: return "extension_\(type)"
        }
    }
}

// MARK: - Server Hello Description

extension TLSHandshakeParser.ServerHello: CustomStringConvertible {
    public var description: String {
        let version = TLSVersion.name(for: actualTLSVersion)
        let cipher = CipherSuite.name(for: cipherSuite)
        return "ServerHello(\(version), \(cipher), \(extensions.count) extensions)"
    }
}
