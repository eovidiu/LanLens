import Foundation

/// Assesses the security posture of discovered network devices.
///
/// The SecurityPostureAssessor evaluates devices based on multiple factors:
/// - Open ports that may expose risky services
/// - Default or weak hostname patterns indicating factory configuration
/// - Known vulnerable service detection from port banners
/// - Missing authentication indicators from HTTP headers
///
/// Risk levels are assigned as follows:
/// - **Critical**: Database ports exposed OR Telnet open
/// - **High**: RDP/VNC exposed OR multiple risky ports (3+)
/// - **Medium**: FTP/SMB exposed OR default hostname detected
/// - **Low**: No risky ports, custom hostname, secure configuration
///
/// ## Usage
/// ```swift
/// let assessor = SecurityPostureAssessor.shared
/// let security = assessor.assess(
///     hostname: "my-router",
///     openPorts: [22, 80, 443],
///     portBanners: bannerData,
///     httpHeaders: headerInfo
/// )
/// print("Risk Level: \(security.riskLevel)")
/// ```
public final class SecurityPostureAssessor: Sendable {
    
    // MARK: - Singleton
    
    /// Shared instance for global access
    public static let shared = SecurityPostureAssessor()
    
    private init() {}
    
    // MARK: - Port Risk Definitions
    
    /// Ports that are considered high-risk when exposed
    private static let riskyPortDefinitions: [Int: (severity: RiskLevel, description: String, remediation: String)] = [
        // Critical - Database exposure
        21: (.medium, "FTP - Unencrypted file transfer protocol", "Disable FTP and use SFTP or SCP for secure file transfers"),
        23: (.critical, "Telnet - Unencrypted remote access with plaintext credentials", "Disable Telnet and use SSH for secure remote access"),
        25: (.medium, "SMTP - Mail server exposed, potential spam relay", "Ensure SMTP authentication is enabled and restrict relay access"),
        110: (.medium, "POP3 - Unencrypted email retrieval", "Use POP3S (port 995) or IMAPS for encrypted email access"),
        135: (.medium, "Windows RPC - Microsoft RPC endpoint mapper", "Block from external access using firewall rules"),
        139: (.medium, "NetBIOS Session - Windows file sharing (legacy)", "Disable NetBIOS over TCP/IP if not needed"),
        445: (.medium, "SMB - Windows file sharing, common attack vector", "Restrict SMB to trusted networks and enable SMB signing"),
        1433: (.critical, "Microsoft SQL Server - Database exposed to network", "Restrict database access to application servers only"),
        1521: (.critical, "Oracle Database - Database listener exposed", "Use firewall rules to restrict access to authorized clients"),
        3306: (.critical, "MySQL - Database exposed to network", "Bind MySQL to localhost and use SSH tunneling for remote access"),
        3389: (.high, "RDP - Remote Desktop Protocol exposed", "Use VPN for RDP access or enable Network Level Authentication"),
        5900: (.high, "VNC - Virtual Network Computing exposed", "Use SSH tunneling for VNC access or restrict to local network"),
        6379: (.critical, "Redis - In-memory database exposed without authentication", "Enable Redis AUTH and bind to localhost"),
        27017: (.critical, "MongoDB - NoSQL database exposed", "Enable authentication and restrict network access"),
    ]
    
    /// Ports that indicate unencrypted services
    private static let unencryptedPorts: Set<Int> = [21, 23, 25, 110, 143, 80]
    
    /// Ports associated with remote desktop services
    private static let remoteDesktopPorts: Set<Int> = [3389, 5900, 5901, 5902]
    
    /// Ports associated with database services
    private static let databasePorts: Set<Int> = [1433, 1521, 3306, 5432, 6379, 27017, 9042, 7000, 7001]
    
    // MARK: - Hostname Pattern Definitions
    
    /// Patterns indicating factory-default hostnames
    private static let defaultHostnamePatterns: [String] = [
        "router", "gateway", "admin", "default", "setup", "wireless",
        "linksys", "netgear", "tp-link", "tplink", "asus", "dlink",
        "belkin", "arris", "motorola", "ubiquiti", "unifi", "mikrotik",
        "openwrt", "dd-wrt", "tomato"
    ]
    
    /// Patterns indicating weak or generic hostnames (factory patterns)
    private static let weakHostnamePatterns: [String] = [
        "desktop-", "laptop-", "android-", "iphone", "ipad",
        "galaxy", "pixel", "oneplus", "huawei-", "xiaomi-",
        "computer", "device", "unknown", "client", "guest"
    ]
    
    // MARK: - Public Assessment Method
    
    /// Assess the security posture of a device based on available information.
    ///
    /// - Parameters:
    ///   - hostname: The device hostname (may be nil for unknown devices)
    ///   - openPorts: Array of open TCP ports discovered on the device
    ///   - portBanners: Optional banner data from port probing
    ///   - httpHeaders: Optional HTTP header information from web interface
    /// - Returns: A SecurityPostureData struct containing the complete assessment
    public func assess(
        hostname: String?,
        openPorts: [Int],
        portBanners: PortBannerData?,
        httpHeaders: HTTPHeaderInfo?
    ) -> SecurityPostureData {
        Log.debug("Assessing security posture for hostname: \(hostname ?? "unknown") with \(openPorts.count) open ports", category: .security)
        
        var riskFactors: [RiskFactor] = []
        var riskyPorts: [Int] = []
        var totalScore = 0
        
        // Analyze open ports
        let portAssessment = assessOpenPorts(openPorts)
        riskFactors.append(contentsOf: portAssessment.factors)
        riskyPorts = portAssessment.riskyPorts
        totalScore += portAssessment.score
        
        // Analyze hostname
        let hostnameAssessment = assessHostname(hostname)
        riskFactors.append(contentsOf: hostnameAssessment.factors)
        totalScore += hostnameAssessment.score
        
        // Analyze port banners for vulnerabilities
        if let banners = portBanners {
            let bannerAssessment = assessPortBanners(banners)
            riskFactors.append(contentsOf: bannerAssessment.factors)
            totalScore += bannerAssessment.score
        }
        
        // Analyze HTTP headers for authentication and encryption
        let webInterfaceInfo = assessHTTPHeaders(httpHeaders, openPorts: openPorts)
        riskFactors.append(contentsOf: webInterfaceInfo.factors)
        totalScore += webInterfaceInfo.score
        
        // Calculate overall risk level
        let riskLevel = calculateRiskLevel(
            score: totalScore,
            riskFactors: riskFactors,
            riskyPorts: riskyPorts
        )
        
        // Determine encryption and authentication status
        let usesEncryption = determineEncryptionStatus(openPorts: openPorts, httpHeaders: httpHeaders)
        let requiresAuth = httpHeaders?.authenticate != nil || httpHeaders?.isAdminInterface == true
        let hasWebInterface = httpHeaders != nil || openPorts.contains(where: { [80, 443, 8080, 8443].contains($0) })
        
        // Cap score at 100
        let finalScore = min(totalScore, 100)
        
        Log.info("Security assessment complete: risk=\(riskLevel.rawValue) score=\(finalScore) factors=\(riskFactors.count)", category: .security)
        
        return SecurityPostureData(
            riskLevel: riskLevel,
            riskScore: finalScore,
            riskFactors: riskFactors,
            riskyPorts: riskyPorts,
            hasWebInterface: hasWebInterface,
            requiresAuthentication: requiresAuth,
            usesEncryption: usesEncryption,
            firmwareOutdated: nil, // Would require version comparison data
            assessmentDate: Date()
        )
    }
    
    // MARK: - Port Assessment
    
    private struct PortAssessmentResult {
        let factors: [RiskFactor]
        let riskyPorts: [Int]
        let score: Int
    }
    
    /// Analyze open ports for security risks
    private func assessOpenPorts(_ ports: [Int]) -> PortAssessmentResult {
        var factors: [RiskFactor] = []
        var riskyPorts: [Int] = []
        var score = 0
        
        for port in ports {
            if let definition = Self.riskyPortDefinitions[port] {
                riskyPorts.append(port)
                
                let contribution: Int
                switch definition.severity {
                case .critical: contribution = 25
                case .high: contribution = 15
                case .medium: contribution = 8
                case .low: contribution = 3
                case .unknown: contribution = 1
                }
                
                score += contribution
                
                factors.append(RiskFactor(
                    category: "Open Port",
                    description: "Port \(port): \(definition.description)",
                    severity: definition.severity,
                    scoreContribution: contribution,
                    remediation: definition.remediation
                ))
                
                Log.debug("Risky port detected: \(port) - \(definition.severity.rawValue)", category: .security)
            }
        }
        
        // Additional risk for multiple risky ports
        if riskyPorts.count >= 3 {
            let multiplePortsFactor = RiskFactor(
                category: "Attack Surface",
                description: "Multiple risky ports exposed (\(riskyPorts.count) ports)",
                severity: .high,
                scoreContribution: 10,
                remediation: "Review all exposed services and disable unnecessary ones"
            )
            factors.append(multiplePortsFactor)
            score += 10
            Log.debug("Multiple risky ports warning: \(riskyPorts.count) ports", category: .security)
        }
        
        // Check for database exposure
        let exposedDatabases = Set(ports).intersection(Self.databasePorts)
        if exposedDatabases.count > 1 {
            let dbFactor = RiskFactor(
                category: "Database Exposure",
                description: "Multiple database ports exposed (\(exposedDatabases.count) databases)",
                severity: .critical,
                scoreContribution: 15,
                remediation: "Restrict database access to application servers using firewall rules"
            )
            factors.append(dbFactor)
            score += 15
        }
        
        return PortAssessmentResult(factors: factors, riskyPorts: riskyPorts, score: score)
    }
    
    // MARK: - Hostname Assessment
    
    private struct HostnameAssessmentResult {
        let factors: [RiskFactor]
        let score: Int
    }
    
    /// Analyze hostname for security concerns
    private func assessHostname(_ hostname: String?) -> HostnameAssessmentResult {
        guard let hostname = hostname, !hostname.isEmpty else {
            return HostnameAssessmentResult(factors: [], score: 0)
        }

        // Sanitize hostname to prevent injection in descriptions
        let sanitizedHostname = sanitizeHostname(hostname)

        var factors: [RiskFactor] = []
        var score = 0
        let lowerHostname = sanitizedHostname.lowercased()

        // Check for default/factory hostnames
        for pattern in Self.defaultHostnamePatterns {
            if lowerHostname.contains(pattern) {
                let factor = RiskFactor(
                    category: "Configuration",
                    description: "Default hostname detected: '\(sanitizedHostname)' contains '\(pattern)'",
                    severity: .medium,
                    scoreContribution: 5,
                    remediation: "Change the device hostname to a unique, non-descriptive name"
                )
                factors.append(factor)
                score += 5
                Log.debug("Default hostname pattern detected: \(pattern) in \(sanitizedHostname)", category: .security)
                break // Only count once
            }
        }

        // Check for weak/generic hostname patterns
        for pattern in Self.weakHostnamePatterns {
            if lowerHostname.hasPrefix(pattern) || lowerHostname.contains(pattern) {
                // Skip if already flagged as default
                if factors.isEmpty {
                    let factor = RiskFactor(
                        category: "Configuration",
                        description: "Weak hostname pattern: '\(sanitizedHostname)' appears to be factory-generated",
                        severity: .low,
                        scoreContribution: 2,
                        remediation: "Consider using a custom hostname for easier device identification"
                    )
                    factors.append(factor)
                    score += 2
                    Log.debug("Weak hostname pattern detected: \(pattern) in \(sanitizedHostname)", category: .security)
                }
                break
            }
        }

        return HostnameAssessmentResult(factors: factors, score: score)
    }
    
    // MARK: - Port Banner Assessment
    
    private struct BannerAssessmentResult {
        let factors: [RiskFactor]
        let score: Int
    }
    
    /// Analyze port banners for vulnerability indicators
    private func assessPortBanners(_ banners: PortBannerData) -> BannerAssessmentResult {
        var factors: [RiskFactor] = []
        var score = 0
        
        // Check SSH banner for outdated versions
        if let ssh = banners.ssh {
            let sshFactors = assessSSHBanner(ssh)
            factors.append(contentsOf: sshFactors.factors)
            score += sshFactors.score
        }
        
        // Check HTTP banner for vulnerable servers
        if let http = banners.http {
            let httpFactors = assessHTTPBanner(http)
            factors.append(contentsOf: httpFactors.factors)
            score += httpFactors.score
        }
        
        // RTSP without auth is a concern
        if let rtsp = banners.rtsp, !rtsp.requiresAuth {
            let factor = RiskFactor(
                category: "Authentication",
                description: "RTSP stream accessible without authentication",
                severity: .high,
                scoreContribution: 12,
                remediation: "Enable authentication on the camera/streaming device"
            )
            factors.append(factor)
            score += 12
            Log.debug("RTSP without authentication detected", category: .security)
        }
        
        return BannerAssessmentResult(factors: factors, score: score)
    }
    
    /// Analyze SSH banner for security issues
    private func assessSSHBanner(_ ssh: SSHBannerInfo) -> BannerAssessmentResult {
        var factors: [RiskFactor] = []
        var score = 0
        let bannerLower = ssh.rawBanner.lowercased()
        
        // Check for SSH protocol version 1 (deprecated and insecure)
        if ssh.protocolVersion == "1" || ssh.protocolVersion == "1.0" {
            let factor = RiskFactor(
                category: "Encryption",
                description: "SSH Protocol version 1 is deprecated and insecure",
                severity: .critical,
                scoreContribution: 20,
                remediation: "Upgrade to SSH protocol version 2 or replace the device"
            )
            factors.append(factor)
            score += 20
        }
        
        // Check for very old OpenSSH versions (pre-7.0 are known vulnerable)
        if let version = ssh.softwareVersion {
            if let match = version.range(of: "OpenSSH_(\\d+)", options: .regularExpression) {
                let versionStr = String(version[match])
                if let majorVersion = Int(versionStr.replacingOccurrences(of: "OpenSSH_", with: "").components(separatedBy: ".").first ?? "") {
                    if majorVersion < 7 {
                        let factor = RiskFactor(
                            category: "Outdated Software",
                            description: "Outdated SSH version (\(version)) with known vulnerabilities",
                            severity: .high,
                            scoreContribution: 10,
                            remediation: "Update SSH server to the latest version"
                        )
                        factors.append(factor)
                        score += 10
                    }
                }
            }
        }
        
        // Check for Dropbear (common on embedded devices, may have limited security)
        if bannerLower.contains("dropbear") {
            // Not necessarily insecure, but worth noting
            Log.debug("Dropbear SSH detected - embedded device", category: .security)
        }
        
        return BannerAssessmentResult(factors: factors, score: score)
    }
    
    /// Analyze HTTP banner for security issues
    private func assessHTTPBanner(_ http: HTTPHeaderInfo) -> BannerAssessmentResult {
        var factors: [RiskFactor] = []
        var score = 0
        
        if let server = http.server {
            let serverLower = server.lowercased()
            
            // Check for very old Apache versions
            if serverLower.contains("apache/1.") {
                let factor = RiskFactor(
                    category: "Outdated Software",
                    description: "Apache 1.x is end-of-life and has known vulnerabilities",
                    severity: .high,
                    scoreContribution: 12,
                    remediation: "Upgrade to Apache 2.4.x or newer"
                )
                factors.append(factor)
                score += 12
            }
            
            // Check for IIS 6 or older
            if serverLower.contains("iis/6") || serverLower.contains("iis/5") {
                let factor = RiskFactor(
                    category: "Outdated Software",
                    description: "IIS 6 or older is end-of-life and has critical vulnerabilities",
                    severity: .critical,
                    scoreContribution: 18,
                    remediation: "Upgrade to a supported version of Windows Server and IIS"
                )
                factors.append(factor)
                score += 18
            }
            
            // Server header disclosure (information leakage)
            if server.contains("/") {
                // Contains version number
                let factor = RiskFactor(
                    category: "Information Disclosure",
                    description: "Server version exposed in headers: \(server)",
                    severity: .low,
                    scoreContribution: 2,
                    remediation: "Configure server to hide version information in headers"
                )
                factors.append(factor)
                score += 2
            }
        }
        
        // X-Powered-By header disclosure
        if let poweredBy = http.poweredBy {
            let factor = RiskFactor(
                category: "Information Disclosure",
                description: "Technology stack exposed: \(poweredBy)",
                severity: .low,
                scoreContribution: 2,
                remediation: "Remove X-Powered-By header from server configuration"
            )
            factors.append(factor)
            score += 2
        }
        
        return BannerAssessmentResult(factors: factors, score: score)
    }
    
    // MARK: - HTTP Header Assessment

    /// HTTPS ports that provide TLS encryption
    private static let httpsPorts: Set<Int> = [443, 8443]

    /// Analyze HTTP headers for authentication and security
    private func assessHTTPHeaders(_ headers: HTTPHeaderInfo?, openPorts: [Int]) -> BannerAssessmentResult {
        guard let headers = headers else {
            return BannerAssessmentResult(factors: [], score: 0)
        }

        var factors: [RiskFactor] = []
        var score = 0

        // Check if HTTPS is available on this device
        let hasHTTPS = !Set(openPorts).intersection(Self.httpsPorts).isEmpty

        // Admin interface without apparent authentication
        if headers.isAdminInterface && headers.authenticate == nil {
            let factor = RiskFactor(
                category: "Authentication",
                description: "Admin interface may lack authentication",
                severity: .medium,
                scoreContribution: 8,
                remediation: "Enable authentication on the admin interface"
            )
            factors.append(factor)
            score += 8
            Log.debug("Admin interface without clear authentication detected", category: .security)
        }

        // Camera interface specific warnings
        if headers.isCameraInterface && headers.authenticate == nil {
            let factor = RiskFactor(
                category: "Authentication",
                description: "Camera web interface may be accessible without authentication",
                severity: .high,
                scoreContribution: 10,
                remediation: "Enable authentication on the camera interface"
            )
            factors.append(factor)
            score += 10
        }

        // Basic authentication assessment - severity depends on HTTPS availability
        if let auth = headers.authenticate?.lowercased(), auth.contains("basic") {
            if hasHTTPS {
                // Basic auth over HTTPS is acceptable but worth noting
                let factor = RiskFactor(
                    category: "Authentication",
                    description: "Basic authentication in use (acceptable over HTTPS/TLS)",
                    severity: .low,
                    scoreContribution: 1,
                    remediation: "Basic auth is secure over HTTPS; consider OAuth for enhanced security"
                )
                factors.append(factor)
                score += 1
                Log.debug("Basic auth detected with HTTPS available - acceptable", category: .security)
            } else {
                // Basic auth without HTTPS is a security risk
                let factor = RiskFactor(
                    category: "Authentication",
                    description: "Basic authentication in use without HTTPS (credentials sent in cleartext)",
                    severity: .medium,
                    scoreContribution: 6,
                    remediation: "Enable HTTPS or switch to Digest/OAuth authentication"
                )
                factors.append(factor)
                score += 6
                Log.debug("Basic auth detected WITHOUT HTTPS - credentials at risk", category: .security)
            }
        }

        return BannerAssessmentResult(factors: factors, score: score)
    }
    
    // MARK: - Risk Level Calculation
    
    /// Calculate overall risk level based on collected data
    private func calculateRiskLevel(
        score: Int,
        riskFactors: [RiskFactor],
        riskyPorts: [Int]
    ) -> RiskLevel {
        // Check for any critical factors first
        if riskFactors.contains(where: { $0.severity == .critical }) {
            return .critical
        }
        
        // Database ports exposed = critical
        if !Set(riskyPorts).intersection(Self.databasePorts).isEmpty {
            return .critical
        }
        
        // Telnet exposed = critical
        if riskyPorts.contains(23) {
            return .critical
        }
        
        // RDP or VNC exposed, or multiple high severity factors = high
        if !Set(riskyPorts).intersection(Self.remoteDesktopPorts).isEmpty {
            return .high
        }
        
        let highSeverityCount = riskFactors.filter { $0.severity == .high }.count
        if highSeverityCount >= 2 {
            return .high
        }
        
        // Multiple risky ports = high
        if riskyPorts.count >= 3 {
            return .high
        }
        
        // Score-based assessment for medium and low
        if score >= 25 {
            return .high
        }
        
        if score >= 10 {
            return .medium
        }
        
        if score > 0 {
            return .low
        }
        
        return .low // No issues found = low risk
    }
    
    // MARK: - Helper Methods

    /// Sanitize hostname to prevent injection attacks in risk factor descriptions.
    /// Truncates to 63 characters (DNS label limit) and removes control/special characters.
    private func sanitizeHostname(_ hostname: String) -> String {
        let truncated = String(hostname.prefix(63))
        return truncated.filter { char in
            char.isLetter || char.isNumber || char == "-" || char == "." || char == "_"
        }
    }

    /// Determine if the device uses encryption based on available ports
    private func determineEncryptionStatus(openPorts: [Int], httpHeaders: HTTPHeaderInfo?) -> Bool {
        // Check for encrypted port variants
        let encryptedPorts: Set<Int> = [22, 443, 465, 587, 993, 995, 8443]
        let hasEncryptedPorts = !Set(openPorts).intersection(encryptedPorts).isEmpty
        
        // HTTPS available
        let hasHTTPS = openPorts.contains(443) || openPorts.contains(8443)
        
        // If only unencrypted ports and no encrypted alternatives
        let hasOnlyUnencrypted = Set(openPorts).isSubset(of: Self.unencryptedPorts)
        
        return hasEncryptedPorts || hasHTTPS || !hasOnlyUnencrypted
    }
}
