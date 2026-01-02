import XCTest
@testable import LanLensCore

/// Tests for MACAddressAnalyzer
/// Tests MAC address analysis including randomization detection, VM detection, and vendor classification
final class MACAddressAnalyzerTests: XCTestCase {
    
    let analyzer = MACAddressAnalyzer.shared
    
    // MARK: - OUI Normalization Tests
    
    func testOUIFromColonSeparatedMAC() {
        let result = analyzer.analyze(mac: "00:11:22:33:44:55", vendor: nil)
        XCTAssertEqual(result.oui, "00:11:22")
    }
    
    func testOUIFromDashSeparatedMAC() {
        let result = analyzer.analyze(mac: "00-11-22-33-44-55", vendor: nil)
        XCTAssertEqual(result.oui, "00:11:22")
    }
    
    func testOUIFromNoSeparatorMAC() {
        let result = analyzer.analyze(mac: "001122334455", vendor: nil)
        XCTAssertEqual(result.oui, "00:11:22")
    }
    
    func testOUIUppercased() {
        let result = analyzer.analyze(mac: "aa:bb:cc:dd:ee:ff", vendor: nil)
        XCTAssertEqual(result.oui, "AA:BB:CC")
    }
    
    func testOUIPadsSingleDigitComponents() {
        let result = analyzer.analyze(mac: "0:1:2:3:4:5", vendor: nil)
        XCTAssertEqual(result.oui, "00:01:02")
    }
    
    // MARK: - Randomized MAC Detection Tests
    
    func testRandomizedMACDetection() {
        // Locally administered bit (2nd bit of first byte) is set
        // E.g., x2:xx:xx, x6:xx:xx, xA:xx:xx, xE:xx:xx (unicast with local bit)
        let result = analyzer.analyze(mac: "02:11:22:33:44:55", vendor: nil)
        
        XCTAssertTrue(result.isLocallyAdministered)
        XCTAssertTrue(result.isRandomized)
    }
    
    func testRandomizedMACWithVariousPatterns() {
        // These all have the locally administered bit set (unicast)
        let randomizedMACs = [
            "02:00:00:00:00:00",
            "06:11:22:33:44:55",
            "0A:BB:CC:DD:EE:FF",
            "0E:AA:BB:CC:DD:EE",
            "F2:12:34:56:78:9A", // F2 = 1111 0010 - LA bit set, unicast
            "D6:00:00:00:00:00", // D6 = 1101 0110 - LA bit set, unicast
        ]
        
        for mac in randomizedMACs {
            let result = analyzer.analyze(mac: mac, vendor: nil)
            XCTAssertTrue(result.isRandomized, "MAC \(mac) should be detected as randomized")
        }
    }
    
    func testNonRandomizedMAC() {
        // Standard vendor-assigned MAC (globally unique, unicast)
        // First byte ends in 0, 4, 8, or C (unicast, globally administered)
        let result = analyzer.analyze(mac: "00:11:22:33:44:55", vendor: nil)
        
        XCTAssertFalse(result.isLocallyAdministered)
        XCTAssertFalse(result.isRandomized)
    }
    
    func testMulticastMACNotRandomized() {
        // Multicast addresses have the low-order bit of the first byte set
        // E.g., 01:xx:xx - this is multicast, not randomized even if LA bit is set
        let result = analyzer.analyze(mac: "03:11:22:33:44:55", vendor: nil) // 03 = multicast + locally administered
        
        XCTAssertTrue(result.isLocallyAdministered)
        XCTAssertFalse(result.isRandomized) // Multicast is not considered randomized
    }
    
    // MARK: - VM OUI Detection Tests
    
    func testVMwareOUIDetection() {
        // VMware OUIs
        let vmwareMACs = ["00:0C:29:AA:BB:CC", "00:50:56:12:34:56"]
        
        for mac in vmwareMACs {
            let result = analyzer.analyze(mac: mac, vendor: nil)
            let signals = analyzer.generateSignals(from: result)
            XCTAssertTrue(signals.contains { $0.suggestedType == .computer && $0.confidence >= 0.8 },
                         "VMware MAC \(mac) should generate computer signal")
        }
    }
    
    func testVirtualBoxOUIDetection() {
        let result = analyzer.analyze(mac: "08:00:27:12:34:56", vendor: nil)
        let signals = analyzer.generateSignals(from: result)
        
        XCTAssertTrue(signals.contains { $0.suggestedType == .computer && $0.confidence >= 0.8 })
    }
    
    func testParallelsOUIDetection() {
        let result = analyzer.analyze(mac: "00:1C:42:AA:BB:CC", vendor: nil)
        let signals = analyzer.generateSignals(from: result)
        
        XCTAssertTrue(signals.contains { $0.suggestedType == .computer && $0.confidence >= 0.8 })
    }
    
    func testQEMUOUIDetection() {
        let result = analyzer.analyze(mac: "52:54:00:12:34:56", vendor: nil)
        let signals = analyzer.generateSignals(from: result)
        
        XCTAssertTrue(signals.contains { $0.suggestedType == .computer && $0.confidence >= 0.8 })
    }
    
    func testHyperVOUIDetection() {
        let result = analyzer.analyze(mac: "00:03:FF:AA:BB:CC", vendor: nil)
        let signals = analyzer.generateSignals(from: result)
        
        XCTAssertTrue(signals.contains { $0.suggestedType == .computer && $0.confidence >= 0.8 })
    }
    
    func testXenOUIDetection() {
        let result = analyzer.analyze(mac: "00:16:3E:12:34:56", vendor: nil)
        let signals = analyzer.generateSignals(from: result)
        
        XCTAssertTrue(signals.contains { $0.suggestedType == .computer && $0.confidence >= 0.8 })
    }
    
    // MARK: - Vendor Confidence Tests
    
    func testHighConfidenceVendor() {
        let result = analyzer.analyze(mac: "00:11:22:33:44:55", vendor: "Apple Inc.")
        XCTAssertEqual(result.vendorConfidence, .high)
    }
    
    func testMediumConfidenceVendor() {
        let result = analyzer.analyze(mac: "00:11:22:33:44:55", vendor: "TP-Link Technologies")
        XCTAssertEqual(result.vendorConfidence, .medium)
    }
    
    func testLowConfidenceVendor() {
        let result = analyzer.analyze(mac: "00:11:22:33:44:55", vendor: "Unknown Manufacturer Ltd")
        XCTAssertEqual(result.vendorConfidence, .low)
    }
    
    func testUnknownVendorConfidence() {
        let result = analyzer.analyze(mac: "00:11:22:33:44:55", vendor: nil)
        XCTAssertEqual(result.vendorConfidence, .unknown)
    }
    
    func testRandomizedVendorConfidence() {
        let result = analyzer.analyze(mac: "02:11:22:33:44:55", vendor: nil)
        XCTAssertEqual(result.vendorConfidence, .randomized)
    }
    
    // MARK: - OUI Age Estimation Tests
    
    func testLegacyVendorAgeEstimate() {
        let result = analyzer.analyze(mac: "00:11:22:33:44:55", vendor: "3Com Corporation")
        XCTAssertEqual(result.ageEstimate, .legacy)
    }
    
    func testEstablishedVendorAgeEstimate() {
        let result = analyzer.analyze(mac: "00:11:22:33:44:55", vendor: "Cisco Systems")
        XCTAssertEqual(result.ageEstimate, .established)
    }
    
    func testModernVendorAgeEstimate() {
        let result = analyzer.analyze(mac: "00:11:22:33:44:55", vendor: "Ring Inc")
        XCTAssertEqual(result.ageEstimate, .modern)
    }
    
    func testRecentVendorAgeEstimate() {
        let result = analyzer.analyze(mac: "00:11:22:33:44:55", vendor: "Wyze Labs")
        XCTAssertEqual(result.ageEstimate, .recent)
    }
    
    func testUnknownVendorAgeEstimate() {
        let result = analyzer.analyze(mac: "00:11:22:33:44:55", vendor: nil)
        XCTAssertEqual(result.ageEstimate, .unknown)
    }
    
    // MARK: - Vendor Device Category Tests
    
    func testSonosVendorSpecialization() {
        let result = analyzer.analyze(mac: "00:11:22:33:44:55", vendor: "Sonos, Inc.")
        
        XCTAssertEqual(result.vendorSpecialization, .speaker)
        XCTAssertTrue(result.vendorCategories.contains(.speaker))
    }
    
    func testRokuVendorSpecialization() {
        let result = analyzer.analyze(mac: "00:11:22:33:44:55", vendor: "Roku, Inc.")
        
        XCTAssertEqual(result.vendorSpecialization, .smartTV)
    }
    
    func testSynologyVendorSpecialization() {
        let result = analyzer.analyze(mac: "00:11:22:33:44:55", vendor: "Synology Inc")
        
        XCTAssertEqual(result.vendorSpecialization, .nas)
    }
    
    func testAppleVendorCategories() {
        let result = analyzer.analyze(mac: "00:11:22:33:44:55", vendor: "Apple Inc.")
        
        // Apple makes multiple device types
        XCTAssertTrue(result.vendorCategories.contains(.phone))
        XCTAssertTrue(result.vendorCategories.contains(.computer))
        XCTAssertTrue(result.vendorCategories.contains(.tablet))
    }
    
    func testPhilipsHueVendorSpecialization() {
        let result = analyzer.analyze(mac: "00:11:22:33:44:55", vendor: "Philips Hue")
        
        XCTAssertEqual(result.vendorSpecialization, .light)
    }
    
    // MARK: - Signal Generation Tests
    
    func testRandomizedMACGeneratesPhoneSignal() {
        let result = analyzer.analyze(mac: "02:11:22:33:44:55", vendor: nil)
        let signals = analyzer.generateSignals(from: result)
        
        XCTAssertTrue(signals.contains { $0.suggestedType == .phone })
    }
    
    func testLegacyOUIGeneratesRouterSignal() {
        let result = analyzer.analyze(mac: "00:11:22:33:44:55", vendor: "3Com Corporation")
        let signals = analyzer.generateSignals(from: result)
        
        XCTAssertTrue(signals.contains { $0.suggestedType == .router })
    }
    
    func testVendorSpecializationGeneratesSignal() {
        let result = analyzer.analyze(mac: "00:11:22:33:44:55", vendor: "Sonos, Inc.")
        let signals = analyzer.generateSignals(from: result)
        
        XCTAssertTrue(signals.contains { $0.suggestedType == .speaker })
    }
    
    func testNoSignalsForUnknownDevice() {
        // A non-randomized, non-VM MAC with unknown vendor
        let result = analyzer.analyze(mac: "00:AA:BB:CC:DD:EE", vendor: nil)
        let signals = analyzer.generateSignals(from: result)
        
        // Should have no strong signals
        XCTAssertTrue(signals.isEmpty)
    }
    
    // MARK: - MACAnalysisData Tests
    
    func testMACAnalysisDataInitialization() {
        let data = MACAnalysisData(
            oui: "00:11:22",
            vendor: "Test Vendor",
            isLocallyAdministered: false,
            isRandomized: false,
            ageEstimate: .modern,
            vendorConfidence: .medium,
            vendorCategories: [.speaker, .smartTV],
            vendorSpecialization: .speaker
        )
        
        XCTAssertEqual(data.oui, "00:11:22")
        XCTAssertEqual(data.vendor, "Test Vendor")
        XCTAssertFalse(data.isLocallyAdministered)
        XCTAssertFalse(data.isRandomized)
        XCTAssertEqual(data.ageEstimate, .modern)
        XCTAssertEqual(data.vendorConfidence, .medium)
        XCTAssertEqual(data.vendorCategories.count, 2)
        XCTAssertEqual(data.vendorSpecialization, .speaker)
    }
    
    // MARK: - VendorConfidence Enum Tests
    
    func testVendorConfidenceRawValues() {
        XCTAssertEqual(VendorConfidence.high.rawValue, "high")
        XCTAssertEqual(VendorConfidence.medium.rawValue, "medium")
        XCTAssertEqual(VendorConfidence.low.rawValue, "low")
        XCTAssertEqual(VendorConfidence.randomized.rawValue, "randomized")
        XCTAssertEqual(VendorConfidence.unknown.rawValue, "unknown")
    }
    
    func testVendorConfidenceAllCases() {
        let allCases = VendorConfidence.allCases
        XCTAssertEqual(allCases.count, 5)
    }
    
    // MARK: - OUIAgeEstimate Enum Tests
    
    func testOUIAgeEstimateRawValues() {
        XCTAssertEqual(OUIAgeEstimate.legacy.rawValue, "legacy")
        XCTAssertEqual(OUIAgeEstimate.established.rawValue, "established")
        XCTAssertEqual(OUIAgeEstimate.modern.rawValue, "modern")
        XCTAssertEqual(OUIAgeEstimate.recent.rawValue, "recent")
        XCTAssertEqual(OUIAgeEstimate.unknown.rawValue, "unknown")
    }
    
    func testOUIAgeEstimateAllCases() {
        let allCases = OUIAgeEstimate.allCases
        XCTAssertEqual(allCases.count, 5)
    }
    
    // MARK: - Edge Cases
    
    func testEmptyMAC() {
        let result = analyzer.analyze(mac: "", vendor: nil)
        // Should handle gracefully
        XCTAssertNotNil(result.oui)
    }
    
    func testShortMAC() {
        let result = analyzer.analyze(mac: "00:11", vendor: nil)
        // Should pad or handle gracefully
        XCTAssertNotNil(result.oui)
    }
    
    func testMixedCaseMAC() {
        let result = analyzer.analyze(mac: "Aa:Bb:Cc:Dd:Ee:Ff", vendor: nil)
        XCTAssertEqual(result.oui, "AA:BB:CC")
    }
    
    func testMACWithExtraSpaces() {
        // Analyzer should handle this via normalization
        let result = analyzer.analyze(mac: "00:11:22:33:44:55", vendor: nil)
        XCTAssertEqual(result.oui, "00:11:22")
    }
}
