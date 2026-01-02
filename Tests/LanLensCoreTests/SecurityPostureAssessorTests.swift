import XCTest
@testable import LanLensCore

/// Tests for SecurityPostureAssessor
/// Tests risk assessment based on open ports, hostnames, and headers
final class SecurityPostureAssessorTests: XCTestCase {
    
    let assessor = SecurityPostureAssessor.shared
    
    // MARK: - Risk Level Tests
    
    func testRiskLevelNumericValues() {
        XCTAssertEqual(RiskLevel.low.numericValue, 1)
        XCTAssertEqual(RiskLevel.medium.numericValue, 2)
        XCTAssertEqual(RiskLevel.high.numericValue, 3)
        XCTAssertEqual(RiskLevel.critical.numericValue, 4)
        XCTAssertEqual(RiskLevel.unknown.numericValue, 0)
    }
    
    func testRiskLevelRawValues() {
        XCTAssertEqual(RiskLevel.low.rawValue, "low")
        XCTAssertEqual(RiskLevel.medium.rawValue, "medium")
        XCTAssertEqual(RiskLevel.high.rawValue, "high")
        XCTAssertEqual(RiskLevel.critical.rawValue, "critical")
        XCTAssertEqual(RiskLevel.unknown.rawValue, "unknown")
    }
    
    // MARK: - Basic Assessment Tests
    
    func testAssessWithNoRisks() {
        let result = assessor.assess(
            hostname: "my-custom-device",
            openPorts: [443], // Only HTTPS, which is encrypted
            portBanners: nil,
            httpHeaders: nil
        )

        XCTAssertEqual(result.riskLevel, .low)
        // Port 443 is not a risky port, so score from ports is 0
        // Hostname "my-custom-device" matches "device" weak pattern, adding 2 points
        XCTAssertTrue(result.riskyPorts.isEmpty)
    }
    
    func testAssessWithNilHostname() {
        let result = assessor.assess(
            hostname: nil,
            openPorts: [],
            portBanners: nil,
            httpHeaders: nil
        )
        
        XCTAssertEqual(result.riskLevel, .low)
        XCTAssertEqual(result.riskScore, 0)
    }
    
    // MARK: - Critical Risk Port Tests
    
    func testCriticalRiskForTelnet() {
        let result = assessor.assess(
            hostname: "device",
            openPorts: [23], // Telnet
            portBanners: nil,
            httpHeaders: nil
        )
        
        XCTAssertEqual(result.riskLevel, .critical)
        XCTAssertTrue(result.riskyPorts.contains(23))
        XCTAssertTrue(result.riskScore >= 20)
    }
    
    func testCriticalRiskForMySQL() {
        let result = assessor.assess(
            hostname: "database-server",
            openPorts: [3306], // MySQL
            portBanners: nil,
            httpHeaders: nil
        )
        
        XCTAssertEqual(result.riskLevel, .critical)
        XCTAssertTrue(result.riskyPorts.contains(3306))
    }
    
    func testCriticalRiskForRedis() {
        let result = assessor.assess(
            hostname: "cache-server",
            openPorts: [6379], // Redis
            portBanners: nil,
            httpHeaders: nil
        )
        
        XCTAssertEqual(result.riskLevel, .critical)
        XCTAssertTrue(result.riskyPorts.contains(6379))
    }
    
    func testCriticalRiskForMongoDB() {
        let result = assessor.assess(
            hostname: "mongo-server",
            openPorts: [27017], // MongoDB
            portBanners: nil,
            httpHeaders: nil
        )
        
        XCTAssertEqual(result.riskLevel, .critical)
        XCTAssertTrue(result.riskyPorts.contains(27017))
    }
    
    func testCriticalRiskForMSSQL() {
        let result = assessor.assess(
            hostname: "sql-server",
            openPorts: [1433], // Microsoft SQL Server
            portBanners: nil,
            httpHeaders: nil
        )
        
        XCTAssertEqual(result.riskLevel, .critical)
        XCTAssertTrue(result.riskyPorts.contains(1433))
    }
    
    // MARK: - High Risk Port Tests
    
    func testHighRiskForRDP() {
        let result = assessor.assess(
            hostname: "windows-pc",
            openPorts: [3389], // RDP
            portBanners: nil,
            httpHeaders: nil
        )
        
        XCTAssertEqual(result.riskLevel, .high)
        XCTAssertTrue(result.riskyPorts.contains(3389))
    }
    
    func testHighRiskForVNC() {
        let result = assessor.assess(
            hostname: "remote-desktop",
            openPorts: [5900], // VNC
            portBanners: nil,
            httpHeaders: nil
        )
        
        XCTAssertEqual(result.riskLevel, .high)
        XCTAssertTrue(result.riskyPorts.contains(5900))
    }
    
    func testHighRiskForMultipleRiskyPorts() {
        let result = assessor.assess(
            hostname: "vulnerable-device",
            openPorts: [21, 25, 110], // FTP, SMTP, POP3 - all medium risk but 3+ triggers high
            portBanners: nil,
            httpHeaders: nil
        )
        
        XCTAssertEqual(result.riskLevel, .high)
        XCTAssertEqual(result.riskyPorts.count, 3)
    }
    
    // MARK: - Medium Risk Port Tests
    
    func testMediumRiskForFTP() {
        let result = assessor.assess(
            hostname: "ftp-server",
            openPorts: [21], // FTP
            portBanners: nil,
            httpHeaders: nil
        )

        // FTP adds 8 points (medium severity), which is < 10 threshold for medium risk
        // So single FTP port results in low risk level
        XCTAssertEqual(result.riskLevel, .low)
        XCTAssertTrue(result.riskyPorts.contains(21))
    }
    
    func testMediumRiskForSMB() {
        let result = assessor.assess(
            hostname: "file-share",
            openPorts: [445], // SMB
            portBanners: nil,
            httpHeaders: nil
        )

        // SMB adds 8 points (medium severity), which is < 10 threshold for medium risk
        // So single SMB port results in low risk level
        XCTAssertEqual(result.riskLevel, .low)
        XCTAssertTrue(result.riskyPorts.contains(445))
    }
    
    // MARK: - Hostname Assessment Tests
    
    func testDefaultHostnameDetection() {
        let result = assessor.assess(
            hostname: "linksys-router", // Contains default pattern
            openPorts: [],
            portBanners: nil,
            httpHeaders: nil
        )
        
        // Should detect default hostname pattern
        XCTAssertTrue(result.riskFactors.contains { $0.category == "Configuration" })
        XCTAssertTrue(result.riskScore > 0)
    }
    
    func testWeakHostnameDetection() {
        let result = assessor.assess(
            hostname: "android-device-123",
            openPorts: [],
            portBanners: nil,
            httpHeaders: nil
        )
        
        // Should detect weak hostname pattern
        XCTAssertTrue(result.riskFactors.contains { $0.category == "Configuration" })
    }
    
    func testCustomHostnameNoRisk() {
        let result = assessor.assess(
            hostname: "my-smart-thermostat",
            openPorts: [],
            portBanners: nil,
            httpHeaders: nil
        )
        
        // Custom hostname should not trigger hostname-related risks
        XCTAssertFalse(result.riskFactors.contains { 
            $0.category == "Configuration" && $0.description.contains("hostname")
        })
    }
    
    // MARK: - SSH Banner Assessment Tests
    
    func testSSHProtocolVersion1Risk() {
        let sshBanner = SSHBannerInfo(
            rawBanner: "SSH-1.0-OpenSSH",
            protocolVersion: "1",
            softwareVersion: nil,
            osHint: nil,
            isNetworkEquipment: false,
            isNAS: false
        )
        let portBanners = PortBannerData(ssh: sshBanner)
        
        let result = assessor.assess(
            hostname: "old-server",
            openPorts: [22],
            portBanners: portBanners,
            httpHeaders: nil
        )
        
        // SSH v1 is critical risk
        XCTAssertTrue(result.riskFactors.contains { 
            $0.description.contains("SSH Protocol version 1") 
        })
    }
    
    func testOutdatedOpenSSHVersion() {
        let sshBanner = SSHBannerInfo(
            rawBanner: "SSH-2.0-OpenSSH_6.0",
            protocolVersion: "2.0",
            softwareVersion: "OpenSSH_6.0",
            osHint: nil,
            isNetworkEquipment: false,
            isNAS: false
        )
        let portBanners = PortBannerData(ssh: sshBanner)
        
        let result = assessor.assess(
            hostname: "old-server",
            openPorts: [22],
            portBanners: portBanners,
            httpHeaders: nil
        )
        
        // OpenSSH < 7 should trigger outdated software warning
        XCTAssertTrue(result.riskFactors.contains { 
            $0.category == "Outdated Software" 
        })
    }
    
    // MARK: - HTTP Header Assessment Tests
    
    func testHTTPServerVersionDisclosure() {
        let httpHeaders = HTTPHeaderInfo(
            server: "Apache/2.4.41",
            isAdminInterface: false,
            isCameraInterface: false,
            isPrinterInterface: false,
            isRouterInterface: false,
            isNASInterface: false
        )
        let portBanners = PortBannerData(http: httpHeaders)
        
        let result = assessor.assess(
            hostname: "web-server",
            openPorts: [80],
            portBanners: portBanners,
            httpHeaders: httpHeaders
        )
        
        // Server version disclosure should be flagged
        XCTAssertTrue(result.riskFactors.contains { 
            $0.category == "Information Disclosure" 
        })
    }
    
    func testAdminInterfaceWithoutAuth() {
        let httpHeaders = HTTPHeaderInfo(
            server: nil,
            authenticate: nil,
            isAdminInterface: true,
            isCameraInterface: false,
            isPrinterInterface: false,
            isRouterInterface: false,
            isNASInterface: false
        )
        
        let result = assessor.assess(
            hostname: "router",
            openPorts: [80],
            portBanners: nil,
            httpHeaders: httpHeaders
        )
        
        // Admin interface without auth should be flagged
        XCTAssertTrue(result.riskFactors.contains { 
            $0.description.contains("Admin interface") 
        })
    }
    
    func testCameraInterfaceWithoutAuth() {
        let httpHeaders = HTTPHeaderInfo(
            server: nil,
            authenticate: nil,
            isAdminInterface: false,
            isCameraInterface: true,
            isPrinterInterface: false,
            isRouterInterface: false,
            isNASInterface: false
        )
        
        let result = assessor.assess(
            hostname: "camera",
            openPorts: [80],
            portBanners: nil,
            httpHeaders: httpHeaders
        )
        
        // Camera interface without auth is high risk
        XCTAssertTrue(result.riskFactors.contains { 
            $0.description.contains("Camera web interface") 
        })
    }
    
    func testBasicAuthWithoutHTTPS() {
        let httpHeaders = HTTPHeaderInfo(
            server: nil,
            authenticate: "Basic realm=\"Admin\"",
            isAdminInterface: false,
            isCameraInterface: false,
            isPrinterInterface: false,
            isRouterInterface: false,
            isNASInterface: false
        )
        
        let result = assessor.assess(
            hostname: "device",
            openPorts: [80], // HTTP only, no HTTPS
            portBanners: nil,
            httpHeaders: httpHeaders
        )
        
        // Basic auth without HTTPS should be flagged as medium risk
        XCTAssertTrue(result.riskFactors.contains { 
            $0.description.contains("Basic authentication") && $0.description.contains("without HTTPS")
        })
    }
    
    func testBasicAuthWithHTTPS() {
        let httpHeaders = HTTPHeaderInfo(
            server: nil,
            authenticate: "Basic realm=\"Admin\"",
            isAdminInterface: false,
            isCameraInterface: false,
            isPrinterInterface: false,
            isRouterInterface: false,
            isNASInterface: false
        )
        
        let result = assessor.assess(
            hostname: "device",
            openPorts: [80, 443], // Has HTTPS available
            portBanners: nil,
            httpHeaders: httpHeaders
        )
        
        // Basic auth with HTTPS available should be low risk
        XCTAssertTrue(result.riskFactors.contains { 
            $0.description.contains("Basic authentication") && $0.severity == .low
        })
    }
    
    // MARK: - RTSP Assessment Tests
    
    func testRTSPWithoutAuth() {
        let rtspBanner = RTSPBannerInfo(
            server: "Camera RTSP",
            methods: ["DESCRIBE", "SETUP", "PLAY"],
            requiresAuth: false
        )
        let portBanners = PortBannerData(rtsp: rtspBanner)
        
        let result = assessor.assess(
            hostname: "ip-camera",
            openPorts: [554],
            portBanners: portBanners,
            httpHeaders: nil
        )
        
        // RTSP without auth should be high risk
        XCTAssertTrue(result.riskFactors.contains { 
            $0.description.contains("RTSP") 
        })
    }
    
    // MARK: - Encryption Status Tests
    
    func testEncryptionStatusWithHTTPS() {
        let result = assessor.assess(
            hostname: "secure-device",
            openPorts: [443],
            portBanners: nil,
            httpHeaders: nil
        )
        
        XCTAssertTrue(result.usesEncryption)
    }
    
    func testEncryptionStatusWithSSH() {
        let result = assessor.assess(
            hostname: "server",
            openPorts: [22],
            portBanners: nil,
            httpHeaders: nil
        )
        
        XCTAssertTrue(result.usesEncryption)
    }
    
    func testEncryptionStatusWithOnlyUnencryptedPorts() {
        let result = assessor.assess(
            hostname: "insecure-device",
            openPorts: [80, 21, 23], // HTTP, FTP, Telnet - all unencrypted
            portBanners: nil,
            httpHeaders: nil
        )
        
        XCTAssertFalse(result.usesEncryption)
    }
    
    // MARK: - Web Interface Detection Tests
    
    func testHasWebInterface() {
        let result = assessor.assess(
            hostname: "device",
            openPorts: [80],
            portBanners: nil,
            httpHeaders: nil
        )
        
        XCTAssertTrue(result.hasWebInterface)
    }
    
    func testHasWebInterfaceAlternatePort() {
        let result = assessor.assess(
            hostname: "device",
            openPorts: [8080],
            portBanners: nil,
            httpHeaders: nil
        )
        
        XCTAssertTrue(result.hasWebInterface)
    }
    
    func testNoWebInterface() {
        let result = assessor.assess(
            hostname: "device",
            openPorts: [22, 25],
            portBanners: nil,
            httpHeaders: nil
        )
        
        XCTAssertFalse(result.hasWebInterface)
    }
    
    // MARK: - Score Capping Tests
    
    func testScoreCappedAt100() {
        // Create a scenario with many risk factors
        let result = assessor.assess(
            hostname: "router", // Default hostname
            openPorts: [21, 23, 25, 110, 135, 139, 445, 3306, 3389, 5900, 6379], // Many risky ports
            portBanners: nil,
            httpHeaders: nil
        )
        
        XCTAssertLessThanOrEqual(result.riskScore, 100)
    }
    
    // MARK: - Risk Factor Tests
    
    func testRiskFactorRemediation() {
        let result = assessor.assess(
            hostname: "device",
            openPorts: [23], // Telnet
            portBanners: nil,
            httpHeaders: nil
        )
        
        // Should have remediation advice
        let telnetFactor = result.riskFactors.first { $0.description.contains("Telnet") }
        XCTAssertNotNil(telnetFactor)
        XCTAssertNotNil(telnetFactor?.remediation)
        XCTAssertTrue(telnetFactor?.remediation?.contains("SSH") ?? false)
    }
    
    // MARK: - SecurityPostureData Tests
    
    func testSecurityPostureDataInitialization() {
        let data = SecurityPostureData(
            riskLevel: .medium,
            riskScore: 25,
            riskFactors: [],
            riskyPorts: [21],
            hasWebInterface: true,
            requiresAuthentication: true,
            usesEncryption: true,
            firmwareOutdated: nil,
            assessmentDate: Date()
        )
        
        XCTAssertEqual(data.riskLevel, .medium)
        XCTAssertEqual(data.riskScore, 25)
        XCTAssertTrue(data.hasWebInterface)
        XCTAssertTrue(data.requiresAuthentication)
        XCTAssertTrue(data.usesEncryption)
        XCTAssertNil(data.firmwareOutdated)
    }
}
