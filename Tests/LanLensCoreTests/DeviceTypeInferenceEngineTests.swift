import XCTest
@testable import LanLensCore

/// Tests for DeviceTypeInferenceEngine
/// Tests signal generation from various sources and type inference logic
final class DeviceTypeInferenceEngineTests: XCTestCase {
    
    // MARK: - Signal Source Tests
    
    func testSignalSourceCases() {
        let allCases = DeviceTypeInferenceEngine.SignalSource.allCases
        XCTAssertTrue(allCases.contains(.ssdp))
        XCTAssertTrue(allCases.contains(.mdns))
        XCTAssertTrue(allCases.contains(.port))
        XCTAssertTrue(allCases.contains(.fingerprint))
        XCTAssertTrue(allCases.contains(.upnp))
        XCTAssertTrue(allCases.contains(.hostname))
        XCTAssertTrue(allCases.contains(.mdnsTXT))
        XCTAssertTrue(allCases.contains(.portBanner))
        XCTAssertTrue(allCases.contains(.macAnalysis))
        XCTAssertTrue(allCases.contains(.behavior))
    }
    
    // MARK: - Signal Tests
    
    func testSignalCreation() {
        let signal = DeviceTypeInferenceEngine.Signal(
            source: .ssdp,
            suggestedType: .smartTV,
            confidence: 0.85
        )
        
        XCTAssertEqual(signal.source, .ssdp)
        XCTAssertEqual(signal.suggestedType, .smartTV)
        XCTAssertEqual(signal.confidence, 0.85)
    }
    
    func testSignalConfidenceClamping() {
        // Test upper bound clamping
        let highSignal = DeviceTypeInferenceEngine.Signal(
            source: .mdns,
            suggestedType: .speaker,
            confidence: 1.5
        )
        XCTAssertEqual(highSignal.confidence, 1.0)
        
        // Test lower bound clamping
        let lowSignal = DeviceTypeInferenceEngine.Signal(
            source: .port,
            suggestedType: .printer,
            confidence: -0.5
        )
        XCTAssertEqual(lowSignal.confidence, 0.0)
    }
    
    // MARK: - Infer Tests
    
    func testInferWithEmptySignals() async {
        let engine = DeviceTypeInferenceEngine.shared
        let result = await engine.infer(signals: [])
        XCTAssertEqual(result, .unknown)
    }
    
    func testInferWithSingleSignal() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signal = DeviceTypeInferenceEngine.Signal(
            source: .ssdp,
            suggestedType: .smartTV,
            confidence: 0.9
        )
        
        let result = await engine.infer(signals: [signal])
        XCTAssertEqual(result, .smartTV)
    }
    
    func testInferWithMultipleAgreingSignals() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = [
            DeviceTypeInferenceEngine.Signal(source: .ssdp, suggestedType: .smartTV, confidence: 0.8),
            DeviceTypeInferenceEngine.Signal(source: .mdns, suggestedType: .smartTV, confidence: 0.7),
            DeviceTypeInferenceEngine.Signal(source: .port, suggestedType: .smartTV, confidence: 0.6)
        ]
        
        let result = await engine.infer(signals: signals)
        XCTAssertEqual(result, .smartTV)
    }
    
    func testInferWithConflictingSignals() async {
        let engine = DeviceTypeInferenceEngine.shared
        // High confidence fingerprint signal should win
        let signals = [
            DeviceTypeInferenceEngine.Signal(source: .port, suggestedType: .computer, confidence: 0.5),
            DeviceTypeInferenceEngine.Signal(source: .fingerprint, suggestedType: .speaker, confidence: 0.95)
        ]
        
        let result = await engine.infer(signals: signals)
        // Fingerprint has higher source weight (0.9) and higher confidence
        XCTAssertEqual(result, .speaker)
    }
    
    func testInferIgnoresUnknownTypeSignals() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = [
            DeviceTypeInferenceEngine.Signal(source: .ssdp, suggestedType: .unknown, confidence: 0.9),
            DeviceTypeInferenceEngine.Signal(source: .mdns, suggestedType: .printer, confidence: 0.7)
        ]
        
        let result = await engine.infer(signals: signals)
        XCTAssertEqual(result, .printer)
    }
    
    // MARK: - SSDP Header Signal Tests
    
    func testSignalsFromSSDPHeadersRoku() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = await engine.signalsFromSSDPHeaders(
            server: "Roku/9.4.0 UPnP/1.0",
            usn: nil,
            st: nil
        )
        
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == .smartTV && $0.confidence >= 0.9 })
    }
    
    func testSignalsFromSSDPHeadersSonos() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = await engine.signalsFromSSDPHeaders(
            server: "Linux UPnP/1.0 Sonos/92.0-72090",
            usn: "uuid:sonos-123",
            st: nil
        )
        
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == .speaker })
    }
    
    func testSignalsFromSSDPHeadersPhilipsHue() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = await engine.signalsFromSSDPHeaders(
            server: "Philips-Hue/1.0",
            usn: "uuid:hue-bridge",
            st: nil
        )
        
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == .hub })
    }
    
    func testSignalsFromSSDPHeadersPrinter() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = await engine.signalsFromSSDPHeaders(
            server: nil,
            usn: nil,
            st: "urn:schemas-upnp-org:device:Printer:1"
        )
        
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == .printer })
    }
    
    func testSignalsFromSSDPHeadersSynology() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = await engine.signalsFromSSDPHeaders(
            server: "Synology/DSM",
            usn: nil,
            st: nil
        )
        
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == .nas })
    }
    
    func testSignalsFromSSDPHeadersNoMatch() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = await engine.signalsFromSSDPHeaders(
            server: "Unknown Device",
            usn: nil,
            st: nil
        )
        
        XCTAssertTrue(signals.isEmpty)
    }
    
    // MARK: - mDNS Service Type Signal Tests
    
    func testSignalsFromMDNSServiceTypeHomeKit() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = await engine.signalsFromMDNSServiceType("_hap._tcp")
        
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == .hub })
    }
    
    func testSignalsFromMDNSServiceTypeAirPlay() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = await engine.signalsFromMDNSServiceType("_airplay._tcp")
        
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == .smartTV })
    }
    
    func testSignalsFromMDNSServiceTypeGoogleCast() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = await engine.signalsFromMDNSServiceType("_googlecast._tcp")
        
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == .smartTV })
    }
    
    func testSignalsFromMDNSServiceTypePrinter() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = await engine.signalsFromMDNSServiceType("_printer._tcp")
        
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == .printer && $0.confidence >= 0.9 })
    }
    
    func testSignalsFromMDNSServiceTypeSpotify() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = await engine.signalsFromMDNSServiceType("_spotify-connect._tcp")
        
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == .speaker })
    }
    
    func testSignalsFromMDNSServiceTypeUnknown() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = await engine.signalsFromMDNSServiceType("_unknown._tcp")
        
        XCTAssertTrue(signals.isEmpty)
    }
    
    // MARK: - Port Signal Tests
    
    func testSignalsFromPortRTSP() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = await engine.signalsFromPort(554)
        
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == .camera })
    }
    
    func testSignalsFromPortSonos() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = await engine.signalsFromPort(1400)
        
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == .speaker })
    }
    
    func testSignalsFromPortGoogleCast() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = await engine.signalsFromPort(8008)
        
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == .smartTV })
    }
    
    func testSignalsFromPortPrinting() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = await engine.signalsFromPort(9100)
        
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == .printer })
    }
    
    func testSignalsFromPortHomeAssistant() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = await engine.signalsFromPort(8123)
        
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == .hub })
    }
    
    func testSignalsFromPortUnknown() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = await engine.signalsFromPort(12345)
        
        XCTAssertTrue(signals.isEmpty)
    }
    
    // MARK: - Hostname Signal Tests
    
    func testSignalsFromHostnameiPhone() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = await engine.signalsFromHostname("Johns-iPhone")
        
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == .phone })
    }
    
    func testSignalsFromHostnameiPad() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = await engine.signalsFromHostname("Marys-iPad")
        
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == .tablet })
    }
    
    func testSignalsFromHostnameMacBook() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = await engine.signalsFromHostname("Johns-MacBook-Pro")
        
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == .computer })
    }
    
    func testSignalsFromHostnameAppleTV() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = await engine.signalsFromHostname("Living-Room-Apple-TV")
        
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == .smartTV })
    }
    
    func testSignalsFromHostnameHomePod() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = await engine.signalsFromHostname("Kitchen-HomePod")
        
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == .speaker })
    }
    
    func testSignalsFromHostnamePrinter() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = await engine.signalsFromHostname("HP-LaserJet-Pro")
        
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == .printer })
    }
    
    func testSignalsFromHostnameNAS() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = await engine.signalsFromHostname("synology-nas-01")
        
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == .nas })
    }
    
    func testSignalsFromHostnameUnknown() async {
        let engine = DeviceTypeInferenceEngine.shared
        let signals = await engine.signalsFromHostname("random-device-123")
        
        XCTAssertTrue(signals.isEmpty)
    }
    
    // MARK: - Fingerprint Signal Tests

    func testSignalsFromFingerprintiPhone() async {
        let engine = DeviceTypeInferenceEngine.shared
        let fingerprint = DeviceFingerprint(
            fingerbankParents: ["Apple", "Apple iPhone", "Apple iPhone 15 Pro"],
            source: .fingerbank,
            timestamp: Date()
        )

        let signals = await engine.signalsFromFingerprint(fingerprint)
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == DeviceType.phone })
    }

    func testSignalsFromFingerprintRoku() async {
        let engine = DeviceTypeInferenceEngine.shared
        let fingerprint = DeviceFingerprint(
            fingerbankParents: ["Roku", "Roku Streaming Player"],
            source: .fingerbank,
            timestamp: Date()
        )

        let signals = await engine.signalsFromFingerprint(fingerprint)
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == DeviceType.smartTV })
    }

    func testSignalsFromFingerprintSonos() async {
        let engine = DeviceTypeInferenceEngine.shared
        let fingerprint = DeviceFingerprint(
            manufacturer: "Sonos, Inc.",
            source: .upnp,
            timestamp: Date()
        )

        let signals = await engine.signalsFromFingerprint(fingerprint)
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == DeviceType.speaker })
    }

    func testSignalsFromFingerprintMobile() async {
        let engine = DeviceTypeInferenceEngine.shared
        let fingerprint = DeviceFingerprint(
            isMobile: true,
            source: .fingerbank,
            timestamp: Date()
        )

        let signals = await engine.signalsFromFingerprint(fingerprint)
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == DeviceType.phone })
    }

    func testSignalsFromFingerprintTablet() async {
        let engine = DeviceTypeInferenceEngine.shared
        let fingerprint = DeviceFingerprint(
            isTablet: true,
            source: .fingerbank,
            timestamp: Date()
        )

        let signals = await engine.signalsFromFingerprint(fingerprint)
        XCTAssertFalse(signals.isEmpty)
        XCTAssertTrue(signals.contains { $0.suggestedType == DeviceType.tablet })
    }
    
    // MARK: - InferFromAllSources Tests
    
    func testInferFromAllSourcesCombined() async {
        let engine = DeviceTypeInferenceEngine.shared
        
        let result = await engine.inferFromAllSources(
            ssdpServer: "Roku/9.4.0",
            mdnsServiceTypes: ["_airplay._tcp"],
            openPorts: [7000],
            hostname: "Living-Room-Roku"
        )
        
        // Multiple signals pointing to smartTV
        XCTAssertEqual(result, .smartTV)
    }
    
    func testInferFromAllSourcesEmpty() async {
        let engine = DeviceTypeInferenceEngine.shared
        
        let result = await engine.inferFromAllSources()
        XCTAssertEqual(result, .unknown)
    }
}
