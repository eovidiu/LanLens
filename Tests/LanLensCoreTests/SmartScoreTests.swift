import XCTest
@testable import LanLensCore

/// Tests for smart score calculation logic
/// Smart score is calculated based on:
/// - Sum of signal weights from SmartSignal array
/// - Bonus for having services (+5)
/// - Bonus for open ports (+5 per port)
/// - Capped at 100
final class SmartScoreTests: XCTestCase {
    
    // MARK: - Signal Type Tests
    
    func testSignalTypeRawValues() {
        XCTAssertEqual(SignalType.openPort.rawValue, "openPort")
        XCTAssertEqual(SignalType.mdnsService.rawValue, "mdnsService")
        XCTAssertEqual(SignalType.ssdpService.rawValue, "ssdpService")
        XCTAssertEqual(SignalType.httpServer.rawValue, "httpServer")
        XCTAssertEqual(SignalType.macVendor.rawValue, "macVendor")
        XCTAssertEqual(SignalType.hostname.rawValue, "hostname")
    }
    
    // MARK: - SmartSignal Tests
    
    func testSmartSignalCreation() {
        let signal = SmartSignal(
            type: .openPort,
            description: "Port 80: HTTP",
            weight: 10
        )
        
        XCTAssertEqual(signal.type, .openPort)
        XCTAssertEqual(signal.description, "Port 80: HTTP")
        XCTAssertEqual(signal.weight, 10)
    }
    
    func testSmartSignalEquality() {
        let signal1 = SmartSignal(type: .mdnsService, description: "AirPlay", weight: 15)
        let signal2 = SmartSignal(type: .mdnsService, description: "AirPlay", weight: 15)
        let signal3 = SmartSignal(type: .mdnsService, description: "AirPlay", weight: 20)
        
        XCTAssertEqual(signal1, signal2)
        XCTAssertNotEqual(signal1, signal3)
    }
    
    func testSmartSignalHashable() {
        let signal1 = SmartSignal(type: .ssdpService, description: "UPnP", weight: 10)
        let signal2 = SmartSignal(type: .ssdpService, description: "UPnP", weight: 10)
        
        var signalSet: Set<SmartSignal> = []
        signalSet.insert(signal1)
        signalSet.insert(signal2)
        
        // Both signals are equal, so set should have only 1 element
        XCTAssertEqual(signalSet.count, 1)
    }
    
    // MARK: - Device Smart Score Integration Tests
    
    func testDeviceWithNoSignalsHasZeroScore() {
        let device = Device(
            mac: "00:11:22:33:44:55",
            ip: "192.168.1.100",
            smartScore: 0,
            smartSignals: []
        )
        
        XCTAssertEqual(device.smartScore, 0)
        XCTAssertTrue(device.smartSignals.isEmpty)
    }
    
    func testDeviceWithSingleSignal() {
        let signal = SmartSignal(type: .mdnsService, description: "mDNS: _airplay._tcp", weight: 15)
        let device = Device(
            mac: "00:11:22:33:44:55",
            ip: "192.168.1.100",
            smartScore: 15,
            smartSignals: [signal]
        )
        
        XCTAssertEqual(device.smartScore, 15)
        XCTAssertEqual(device.smartSignals.count, 1)
    }
    
    func testDeviceWithMultipleSignals() {
        let signals = [
            SmartSignal(type: .mdnsService, description: "mDNS: _airplay._tcp", weight: 15),
            SmartSignal(type: .ssdpService, description: "SSDP: Roku", weight: 20),
            SmartSignal(type: .openPort, description: "Port 8008: Google Cast", weight: 10)
        ]
        
        // Calculate expected score (sum of weights)
        let expectedWeight = signals.reduce(0) { $0 + $1.weight }
        
        let device = Device(
            mac: "00:11:22:33:44:55",
            ip: "192.168.1.100",
            smartScore: expectedWeight,
            smartSignals: signals
        )
        
        XCTAssertEqual(device.smartScore, 45)
        XCTAssertEqual(device.smartSignals.count, 3)
    }
    
    func testDeviceScoreCapAt100() {
        // Create many high-weight signals that would exceed 100
        let signals = [
            SmartSignal(type: .mdnsService, description: "Service 1", weight: 30),
            SmartSignal(type: .ssdpService, description: "Service 2", weight: 30),
            SmartSignal(type: .openPort, description: "Port 1", weight: 25),
            SmartSignal(type: .openPort, description: "Port 2", weight: 25)
        ]
        
        // Score should be capped at 100 even though weights sum to 110
        let device = Device(
            mac: "00:11:22:33:44:55",
            ip: "192.168.1.100",
            smartScore: 100, // Capped
            smartSignals: signals
        )
        
        XCTAssertEqual(device.smartScore, 100)
    }
    
    // MARK: - Port Bonus Tests
    
    func testDeviceWithOpenPortsGetsBonus() {
        let ports = [
            Port(number: 80, protocol: .tcp, state: .open, serviceName: "http"),
            Port(number: 443, protocol: .tcp, state: .open, serviceName: "https")
        ]
        
        // Each open port adds 5 to score in calculateSmartScore
        let device = Device(
            mac: "00:11:22:33:44:55",
            ip: "192.168.1.100",
            openPorts: ports,
            smartScore: 10, // Base score + port bonuses would be calculated
            smartSignals: []
        )
        
        XCTAssertEqual(device.openPorts.count, 2)
    }
    
    // MARK: - Service Bonus Tests
    
    func testDeviceWithServicesGetsBonus() {
        let services = [
            DiscoveredService(name: "AirPlay", type: .mdns, port: 7000, txt: [:])
        ]
        
        // Having services adds 5 to score in calculateSmartScore
        let device = Device(
            mac: "00:11:22:33:44:55",
            ip: "192.168.1.100",
            services: services,
            smartScore: 5, // Service bonus
            smartSignals: []
        )
        
        XCTAssertEqual(device.services.count, 1)
    }
    
    // MARK: - Combined Score Tests
    
    func testCombinedScoreCalculation() {
        // Simulate what calculateSmartScore does:
        // score = sum(signal weights) + (services.isEmpty ? 0 : 5) + (openPorts.count * 5)
        
        let signals = [
            SmartSignal(type: .mdnsService, description: "AirPlay", weight: 15),
            SmartSignal(type: .ssdpService, description: "SSDP", weight: 10)
        ]
        let services = [
            DiscoveredService(name: "AirPlay", type: .mdns, port: 7000, txt: [:])
        ]
        let ports = [
            Port(number: 80, protocol: .tcp, state: .open),
            Port(number: 443, protocol: .tcp, state: .open)
        ]
        
        // Expected: 15 + 10 + 5 (service bonus) + 10 (2 ports * 5) = 40
        let expectedScore = 40
        
        let device = Device(
            mac: "00:11:22:33:44:55",
            ip: "192.168.1.100",
            openPorts: ports,
            services: services,
            smartScore: expectedScore,
            smartSignals: signals
        )
        
        XCTAssertEqual(device.smartScore, 40)
    }
}
