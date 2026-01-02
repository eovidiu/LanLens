import XCTest
@testable import LanLensCore

/// Tests for ExportService
/// Tests JSON and CSV export formats
final class ExportServiceTests: XCTestCase {
    
    // MARK: - ExportFormat Tests
    
    func testExportFormatFileExtensions() {
        XCTAssertEqual(ExportFormat.json.fileExtension, "json")
        XCTAssertEqual(ExportFormat.csv.fileExtension, "csv")
    }
    
    func testExportFormatMimeTypes() {
        XCTAssertEqual(ExportFormat.json.mimeType, "application/json")
        XCTAssertEqual(ExportFormat.csv.mimeType, "text/csv")
    }
    
    func testExportFormatDisplayNames() {
        XCTAssertEqual(ExportFormat.json.displayName, "JSON")
        XCTAssertEqual(ExportFormat.csv.displayName, "CSV")
    }
    
    func testExportFormatAllCases() {
        let allCases = ExportFormat.allCases
        XCTAssertEqual(allCases.count, 2)
        XCTAssertTrue(allCases.contains(.json))
        XCTAssertTrue(allCases.contains(.csv))
    }
    
    // MARK: - JSON Export Tests
    
    func testExportSingleDeviceAsJSON() async throws {
        let service = ExportService.shared
        let device = createTestDevice(mac: "00:11:22:33:44:55", ip: "192.168.1.100")
        
        let data = try await service.exportDevices([device], format: .json)
        
        XCTAssertFalse(data.isEmpty)
        
        // Parse JSON and verify structure
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertNotNil(json?["exportDate"])
        XCTAssertEqual(json?["deviceCount"] as? Int, 1)
        
        let devices = json?["devices"] as? [[String: Any]]
        XCTAssertEqual(devices?.count, 1)
        XCTAssertEqual(devices?.first?["mac"] as? String, "00:11:22:33:44:55")
    }
    
    func testExportMultipleDevicesAsJSON() async throws {
        let service = ExportService.shared
        let devices = [
            createTestDevice(mac: "00:11:22:33:44:55", ip: "192.168.1.100"),
            createTestDevice(mac: "AA:BB:CC:DD:EE:FF", ip: "192.168.1.101"),
            createTestDevice(mac: "11:22:33:44:55:66", ip: "192.168.1.102")
        ]
        
        let data = try await service.exportDevices(devices, format: .json)
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["deviceCount"] as? Int, 3)
        
        let exportedDevices = json?["devices"] as? [[String: Any]]
        XCTAssertEqual(exportedDevices?.count, 3)
    }
    
    func testExportEmptyDevicesAsJSON() async throws {
        let service = ExportService.shared
        
        let data = try await service.exportDevices([], format: .json)
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["deviceCount"] as? Int, 0)
        
        let devices = json?["devices"] as? [[String: Any]]
        XCTAssertEqual(devices?.count, 0)
    }
    
    func testJSONExportContainsAllFields() async throws {
        let service = ExportService.shared
        let device = Device(
            mac: "00:11:22:33:44:55",
            ip: "192.168.1.100",
            hostname: "test-device",
            vendor: "Test Vendor",
            firstSeen: Date(),
            lastSeen: Date(),
            isOnline: true,
            smartScore: 75,
            deviceType: .smartTV,
            userLabel: "Living Room TV"
        )
        
        let data = try await service.exportDevices([device], format: .json)
        let jsonString = String(data: data, encoding: .utf8)
        
        // Check that key fields are present in JSON
        XCTAssertTrue(jsonString?.contains("\"mac\"") ?? false)
        XCTAssertTrue(jsonString?.contains("\"ip\"") ?? false)
        XCTAssertTrue(jsonString?.contains("\"hostname\"") ?? false)
        XCTAssertTrue(jsonString?.contains("\"vendor\"") ?? false)
        XCTAssertTrue(jsonString?.contains("\"smartScore\"") ?? false)
        XCTAssertTrue(jsonString?.contains("\"deviceType\"") ?? false)
        XCTAssertTrue(jsonString?.contains("\"isOnline\"") ?? false)
    }
    
    // MARK: - CSV Export Tests
    
    func testExportSingleDeviceAsCSV() async throws {
        let service = ExportService.shared
        let device = createTestDevice(mac: "00:11:22:33:44:55", ip: "192.168.1.100")
        
        let data = try await service.exportDevices([device], format: .csv)
        let csvString = String(data: data, encoding: .utf8)!
        
        XCTAssertFalse(csvString.isEmpty)
        
        // Check header row
        let lines = csvString.components(separatedBy: "\n")
        XCTAssertTrue(lines.count >= 2) // Header + at least one data row
        
        let header = lines[0]
        XCTAssertTrue(header.contains("MAC"))
        XCTAssertTrue(header.contains("IP"))
        XCTAssertTrue(header.contains("Hostname"))
        XCTAssertTrue(header.contains("Vendor"))
        XCTAssertTrue(header.contains("Type"))
        XCTAssertTrue(header.contains("SmartScore"))
    }
    
    func testExportMultipleDevicesAsCSV() async throws {
        let service = ExportService.shared
        let devices = [
            createTestDevice(mac: "00:11:22:33:44:55", ip: "192.168.1.100"),
            createTestDevice(mac: "AA:BB:CC:DD:EE:FF", ip: "192.168.1.101")
        ]
        
        let data = try await service.exportDevices(devices, format: .csv)
        let csvString = String(data: data, encoding: .utf8)!
        
        let lines = csvString.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 3) // Header + 2 data rows
    }
    
    func testCSVHeaderFormat() async throws {
        let service = ExportService.shared
        let device = createTestDevice(mac: "00:11:22:33:44:55", ip: "192.168.1.100")
        
        let data = try await service.exportDevices([device], format: .csv)
        let csvString = String(data: data, encoding: .utf8)!
        
        let expectedHeader = "MAC,IP,Hostname,Vendor,Type,Label,SmartScore,FirstSeen,LastSeen,Online"
        let lines = csvString.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], expectedHeader)
    }
    
    func testCSVDataRow() async throws {
        let service = ExportService.shared
        let device = Device(
            mac: "00:11:22:33:44:55",
            ip: "192.168.1.100",
            hostname: "test-device",
            vendor: "Apple",
            smartScore: 50,
            deviceType: .computer,
            userLabel: "My Mac"
        )
        
        let data = try await service.exportDevices([device], format: .csv)
        let csvString = String(data: data, encoding: .utf8)!
        
        let lines = csvString.components(separatedBy: "\n")
        let dataRow = lines[1]
        
        XCTAssertTrue(dataRow.contains("00:11:22:33:44:55"))
        XCTAssertTrue(dataRow.contains("192.168.1.100"))
        XCTAssertTrue(dataRow.contains("test-device"))
        XCTAssertTrue(dataRow.contains("Apple"))
        XCTAssertTrue(dataRow.contains("computer"))
        XCTAssertTrue(dataRow.contains("My Mac"))
        XCTAssertTrue(dataRow.contains("50"))
    }
    
    // MARK: - CSV Escaping Tests
    
    func testCSVEscapingCommas() async throws {
        let service = ExportService.shared
        let device = Device(
            mac: "00:11:22:33:44:55",
            ip: "192.168.1.100",
            hostname: "device,with,commas",
            smartScore: 0,
            deviceType: .unknown
        )
        
        let data = try await service.exportDevices([device], format: .csv)
        let csvString = String(data: data, encoding: .utf8)!
        
        // Hostname with commas should be quoted
        XCTAssertTrue(csvString.contains("\"device,with,commas\""))
    }
    
    func testCSVEscapingQuotes() async throws {
        let service = ExportService.shared
        let device = Device(
            mac: "00:11:22:33:44:55",
            ip: "192.168.1.100",
            smartScore: 0,
            deviceType: .unknown,
            userLabel: "My \"Special\" Device"
        )
        
        let data = try await service.exportDevices([device], format: .csv)
        let csvString = String(data: data, encoding: .utf8)!
        
        // Quotes should be escaped as double quotes
        XCTAssertTrue(csvString.contains("\"My \"\"Special\"\" Device\""))
    }
    
    func testCSVEscapingNewlines() async throws {
        let service = ExportService.shared
        let device = Device(
            mac: "00:11:22:33:44:55",
            ip: "192.168.1.100",
            hostname: "device\nwith\nnewlines",
            smartScore: 0,
            deviceType: .unknown
        )
        
        let data = try await service.exportDevices([device], format: .csv)
        let csvString = String(data: data, encoding: .utf8)!
        
        // Hostname with newlines should be quoted
        XCTAssertTrue(csvString.contains("\"device\nwith\nnewlines\""))
    }
    
    func testCSVNoEscapingNeeded() async throws {
        let service = ExportService.shared
        let device = Device(
            mac: "00:11:22:33:44:55",
            ip: "192.168.1.100",
            hostname: "simple-hostname",
            smartScore: 0,
            deviceType: .unknown
        )
        
        let data = try await service.exportDevices([device], format: .csv)
        let csvString = String(data: data, encoding: .utf8)!
        
        // Simple hostname should not be quoted
        XCTAssertTrue(csvString.contains(",simple-hostname,"))
    }
    
    // MARK: - ExportToFile Tests
    
    func testExportToFileNoDevicesError() async {
        let service = ExportService.shared
        let tempDir = FileManager.default.temporaryDirectory
        
        do {
            _ = try await service.exportToFile([], format: .json, directory: tempDir)
            XCTFail("Should have thrown noDevices error")
        } catch let error as ExportError {
            if case .noDevices = error {
                // Expected error
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testExportToFileCreatesFile() async throws {
        let service = ExportService.shared
        let device = createTestDevice(mac: "00:11:22:33:44:55", ip: "192.168.1.100")
        let tempDir = FileManager.default.temporaryDirectory
        
        let fileURL = try await service.exportToFile([device], format: .json, directory: tempDir)
        
        // Verify file was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        
        // Verify file extension
        XCTAssertEqual(fileURL.pathExtension, "json")
        
        // Cleanup
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    func testExportToFileCSVFormat() async throws {
        let service = ExportService.shared
        let device = createTestDevice(mac: "00:11:22:33:44:55", ip: "192.168.1.100")
        let tempDir = FileManager.default.temporaryDirectory
        
        let fileURL = try await service.exportToFile([device], format: .csv, directory: tempDir)
        
        // Verify file extension
        XCTAssertEqual(fileURL.pathExtension, "csv")
        
        // Verify content can be read
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("MAC"))
        
        // Cleanup
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    // MARK: - ExportError Tests
    
    func testExportErrorDescriptions() {
        let encodingError = ExportError.encodingFailed("Test encoding error")
        XCTAssertTrue(encodingError.localizedDescription.contains("encoding"))
        
        let writeError = ExportError.fileWriteFailed("Test write error")
        XCTAssertTrue(writeError.localizedDescription.contains("write"))
        
        let directoryError = ExportError.invalidDirectory
        XCTAssertTrue(directoryError.localizedDescription.contains("directory"))
        
        let noDevicesError = ExportError.noDevices
        XCTAssertTrue(noDevicesError.localizedDescription.contains("devices"))
    }
    
    // MARK: - Date Formatting Tests
    
    func testJSONExportDateFormat() async throws {
        let service = ExportService.shared
        let device = createTestDevice(mac: "00:11:22:33:44:55", ip: "192.168.1.100")
        
        let data = try await service.exportDevices([device], format: .json)
        let jsonString = String(data: data, encoding: .utf8)!
        
        // ISO 8601 format check - should contain date pattern
        XCTAssertTrue(jsonString.contains("T")) // ISO 8601 date-time separator
    }
    
    func testCSVExportDateFormat() async throws {
        let service = ExportService.shared
        let device = createTestDevice(mac: "00:11:22:33:44:55", ip: "192.168.1.100")
        
        let data = try await service.exportDevices([device], format: .csv)
        let csvString = String(data: data, encoding: .utf8)!
        
        // ISO 8601 format check
        XCTAssertTrue(csvString.contains("T")) // ISO 8601 date-time separator
    }
    
    // MARK: - Device Type Export Tests
    
    func testAllDeviceTypesExport() async throws {
        let service = ExportService.shared
        var devices: [Device] = []
        
        // Create a device for each type
        for (index, deviceType) in DeviceType.allCases.enumerated() {
            let mac = String(format: "00:11:22:33:44:%02X", index)
            var device = createTestDevice(mac: mac, ip: "192.168.1.\(100 + index)")
            device.deviceType = deviceType
            devices.append(device)
        }
        
        let data = try await service.exportDevices(devices, format: .json)
        let jsonString = String(data: data, encoding: .utf8)!
        
        // Verify all device types are represented
        for deviceType in DeviceType.allCases {
            XCTAssertTrue(jsonString.contains(deviceType.rawValue), "Missing device type: \(deviceType.rawValue)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestDevice(mac: String, ip: String) -> Device {
        Device(
            mac: mac,
            ip: ip,
            hostname: nil,
            vendor: nil,
            firstSeen: Date(),
            lastSeen: Date(),
            isOnline: true,
            smartScore: 0,
            deviceType: .unknown
        )
    }
}
