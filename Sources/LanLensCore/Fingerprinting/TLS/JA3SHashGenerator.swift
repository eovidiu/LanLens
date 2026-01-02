import Foundation
import CryptoKit

// MARK: - JA3S Fingerprint

/// JA3S fingerprint from TLS Server Hello.
///
/// JA3S is the server-side counterpart to JA3, capturing the TLS Server Hello response.
/// The fingerprint format is: `SSLVersion,Cipher,Extensions`
///
/// Example: "771,49195,65281-35" (TLS 1.2, ECDHE_RSA_WITH_AES_128_GCM_SHA256, extensions)
/// This gets hashed to MD5 to create the JA3S hash.
///
/// Reference: https://github.com/salesforce/ja3
public struct JA3SFingerprint: Codable, Sendable, Hashable, Equatable {

    /// TLS version from Server Hello (e.g., 771 = TLS 1.2, 772 = TLS 1.3)
    public let sslVersion: UInt16

    /// Selected cipher suite from Server Hello
    public let cipher: UInt16

    /// Server extensions (sorted by type)
    public let extensions: [UInt16]

    /// Raw JA3S string before hashing (format: "SSLVersion,Cipher,Extensions")
    public var rawString: String {
        let extensionString = extensions.map { String($0) }.joined(separator: "-")
        return "\(sslVersion),\(cipher),\(extensionString)"
    }

    /// MD5 hash of JA3S string (lowercase hex)
    public var hash: String {
        JA3SHashGenerator.computeMD5Hash(rawString)
    }

    /// Human-readable TLS version string
    public var tlsVersionString: String {
        TLSVersion.name(for: sslVersion)
    }

    /// Human-readable cipher suite name (if known)
    public var cipherName: String {
        CipherSuite.name(for: cipher)
    }

    public init(sslVersion: UInt16, cipher: UInt16, extensions: [UInt16]) {
        self.sslVersion = sslVersion
        self.cipher = cipher
        self.extensions = extensions
    }
}

// MARK: - TLS Version Constants

/// TLS version constants and utilities
public enum TLSVersion {
    public static let ssl30: UInt16 = 0x0300  // 768
    public static let tls10: UInt16 = 0x0301  // 769
    public static let tls11: UInt16 = 0x0302  // 770
    public static let tls12: UInt16 = 0x0303  // 771
    public static let tls13: UInt16 = 0x0304  // 772

    /// Get human-readable name for TLS version
    public static func name(for version: UInt16) -> String {
        switch version {
        case ssl30: return "SSL 3.0"
        case tls10: return "TLS 1.0"
        case tls11: return "TLS 1.1"
        case tls12: return "TLS 1.2"
        case tls13: return "TLS 1.3"
        default: return "Unknown (0x\(String(format: "%04X", version)))"
        }
    }

    /// Check if version is considered secure (TLS 1.2+)
    public static func isSecure(_ version: UInt16) -> Bool {
        version >= tls12
    }
}

// MARK: - Cipher Suite Constants

/// Common cipher suite constants and utilities
public enum CipherSuite {
    // TLS 1.3 cipher suites
    public static let tls13_aes_128_gcm_sha256: UInt16 = 0x1301
    public static let tls13_aes_256_gcm_sha384: UInt16 = 0x1302
    public static let tls13_chacha20_poly1305_sha256: UInt16 = 0x1303

    // TLS 1.2 ECDHE cipher suites
    public static let tls_ecdhe_rsa_with_aes_128_gcm_sha256: UInt16 = 0xC02F
    public static let tls_ecdhe_rsa_with_aes_256_gcm_sha384: UInt16 = 0xC030
    public static let tls_ecdhe_ecdsa_with_aes_128_gcm_sha256: UInt16 = 0xC02B
    public static let tls_ecdhe_ecdsa_with_aes_256_gcm_sha384: UInt16 = 0xC02C

    // Legacy cipher suites (for identification, not recommended)
    public static let tls_rsa_with_aes_128_gcm_sha256: UInt16 = 0x009C
    public static let tls_rsa_with_aes_256_gcm_sha384: UInt16 = 0x009D

    /// Get human-readable name for cipher suite
    public static func name(for cipher: UInt16) -> String {
        switch cipher {
        // TLS 1.3
        case tls13_aes_128_gcm_sha256:
            return "TLS_AES_128_GCM_SHA256"
        case tls13_aes_256_gcm_sha384:
            return "TLS_AES_256_GCM_SHA384"
        case tls13_chacha20_poly1305_sha256:
            return "TLS_CHACHA20_POLY1305_SHA256"

        // TLS 1.2 ECDHE
        case tls_ecdhe_rsa_with_aes_128_gcm_sha256:
            return "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
        case tls_ecdhe_rsa_with_aes_256_gcm_sha384:
            return "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
        case tls_ecdhe_ecdsa_with_aes_128_gcm_sha256:
            return "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"
        case tls_ecdhe_ecdsa_with_aes_256_gcm_sha384:
            return "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384"

        // RSA (legacy)
        case tls_rsa_with_aes_128_gcm_sha256:
            return "TLS_RSA_WITH_AES_128_GCM_SHA256"
        case tls_rsa_with_aes_256_gcm_sha384:
            return "TLS_RSA_WITH_AES_256_GCM_SHA384"

        default:
            return "0x\(String(format: "%04X", cipher))"
        }
    }

    /// Check if cipher is considered secure
    public static func isSecure(_ cipher: UInt16) -> Bool {
        // TLS 1.3 ciphers are all secure
        if cipher >= 0x1301 && cipher <= 0x1305 {
            return true
        }
        // ECDHE with AES-GCM
        let secureCiphers: Set<UInt16> = [
            tls_ecdhe_rsa_with_aes_128_gcm_sha256,
            tls_ecdhe_rsa_with_aes_256_gcm_sha384,
            tls_ecdhe_ecdsa_with_aes_128_gcm_sha256,
            tls_ecdhe_ecdsa_with_aes_256_gcm_sha384
        ]
        return secureCiphers.contains(cipher)
    }
}

// MARK: - JA3S Hash Generator

/// Generator for JA3S fingerprints from TLS Server Hello data.
///
/// JA3S provides a method to fingerprint TLS servers based on their Server Hello response.
/// This can help identify the TLS implementation (nginx, OpenSSL, Go, etc.) running on a device.
public struct JA3SHashGenerator: Sendable {

    /// Generate JA3S fingerprint from Server Hello components.
    ///
    /// - Parameters:
    ///   - sslVersion: TLS version from Server Hello
    ///   - cipher: Selected cipher suite
    ///   - extensions: Server extensions (will be sorted)
    /// - Returns: JA3S fingerprint with raw string and MD5 hash
    public static func generate(
        sslVersion: UInt16,
        cipher: UInt16,
        extensions: [UInt16]
    ) -> JA3SFingerprint {
        // Sort extensions for consistent fingerprinting
        let sortedExtensions = extensions.sorted()
        return JA3SFingerprint(
            sslVersion: sslVersion,
            cipher: cipher,
            extensions: sortedExtensions
        )
    }

    /// Parse Server Hello bytes and generate fingerprint.
    ///
    /// This method accepts raw TLS record data containing a Server Hello message
    /// and extracts the components needed for JA3S fingerprinting.
    ///
    /// - Parameter data: Raw TLS record data containing Server Hello
    /// - Returns: JA3S fingerprint if parsing succeeds, nil otherwise
    public static func parseServerHello(_ data: Data) -> JA3SFingerprint? {
        guard let serverHello = TLSHandshakeParser.parseServerHello(from: data) else {
            return nil
        }

        let extensionTypes = serverHello.extensions.map { $0.type }

        return generate(
            sslVersion: serverHello.tlsVersion,
            cipher: serverHello.cipherSuite,
            extensions: extensionTypes
        )
    }

    /// Compute MD5 hash of a JA3S raw string.
    ///
    /// - Parameter rawString: JA3S raw string (SSLVersion,Cipher,Extensions)
    /// - Returns: Lowercase hex-encoded MD5 hash
    public static func computeMD5Hash(_ rawString: String) -> String {
        let data = Data(rawString.utf8)
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Validate if a string looks like a JA3S hash (32 hex characters).
    ///
    /// - Parameter hash: String to validate
    /// - Returns: True if the string appears to be a valid JA3S hash
    public static func isValidJA3SHash(_ hash: String) -> Bool {
        guard hash.count == 32 else { return false }
        let hexChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return hash.unicodeScalars.allSatisfy { hexChars.contains($0) }
    }
}

// MARK: - JA3S Fingerprint Description

extension JA3SFingerprint: CustomStringConvertible {
    public var description: String {
        "\(tlsVersionString), \(cipherName), \(extensions.count) extensions -> \(hash)"
    }
}
