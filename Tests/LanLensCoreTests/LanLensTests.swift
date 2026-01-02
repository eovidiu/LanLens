import XCTest
@testable import LanLensCore

final class LanLensTests: XCTestCase {
    func testMACVendorLookup() {
        let vendor = MACVendorLookup.shared.lookup(mac: "00:03:93:12:34:56")
        XCTAssertEqual(vendor, "Apple")
    }

    func testMACVendorLookupUnknown() {
        let vendor = MACVendorLookup.shared.lookup(mac: "FF:FF:FF:12:34:56")
        XCTAssertNil(vendor)
    }
}

// MARK: - DeviceStore Tests

final class DeviceStoreTests: XCTestCase {
    var deviceStore: DeviceStore!
    var tempDatabasePath: String!

    override func setUp() async throws {
        // Use a temporary file-based database (WAL mode doesn't work with :memory:)
        tempDatabasePath = NSTemporaryDirectory() + "lanlens_test_\(UUID().uuidString).sqlite"
        let db = try DatabaseManager(path: tempDatabasePath)
        let repository = DeviceRepository(database: db)
        deviceStore = DeviceStore(repository: repository)
    }

    override func tearDown() async throws {
        // Clean up temp database
        if let path = tempDatabasePath {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: path + "-wal")
            try? FileManager.default.removeItem(atPath: path + "-shm")
        }
    }

    func testAddAndGetDevice() async throws {
        let device = Device(
            mac: "AA:BB:CC:DD:EE:FF",
            ip: "192.168.1.100",
            hostname: "test-device",
            vendor: "Test Vendor"
        )

        try await deviceStore.addOrUpdate(device: device)

        let retrieved = await deviceStore.getDevice(mac: "AA:BB:CC:DD:EE:FF")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.mac, "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(retrieved?.ip, "192.168.1.100")
        XCTAssertEqual(retrieved?.hostname, "test-device")
    }

    func testGetAllDevices() async throws {
        let device1 = Device(mac: "11:22:33:44:55:66", ip: "192.168.1.1")
        let device2 = Device(mac: "AA:BB:CC:DD:EE:FF", ip: "192.168.1.2")

        try await deviceStore.addOrUpdate(device: device1)
        try await deviceStore.addOrUpdate(device: device2)

        let devices = await deviceStore.getDevices()
        XCTAssertEqual(devices.count, 2)
    }

    func testDeviceMergePreservesFirstSeen() async throws {
        let originalDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let device1 = Device(
            mac: "AA:BB:CC:DD:EE:FF",
            ip: "192.168.1.100",
            firstSeen: originalDate,
            lastSeen: originalDate
        )

        try await deviceStore.addOrUpdate(device: device1)

        // Update with new data
        let device2 = Device(
            mac: "AA:BB:CC:DD:EE:FF",
            ip: "192.168.1.101", // IP changed
            hostname: "new-hostname",
            firstSeen: Date(), // This should be ignored
            lastSeen: Date()
        )

        try await deviceStore.addOrUpdate(device: device2)

        let merged = await deviceStore.getDevice(mac: "AA:BB:CC:DD:EE:FF")
        XCTAssertNotNil(merged)
        // First seen should be preserved
        if let mergedDevice = merged {
            XCTAssertEqual(mergedDevice.firstSeen.timeIntervalSince1970, originalDate.timeIntervalSince1970, accuracy: 1.0)
            // IP should be updated
            XCTAssertEqual(mergedDevice.ip, "192.168.1.101")
            // Hostname should be set
            XCTAssertEqual(mergedDevice.hostname, "new-hostname")
        }
    }

    func testDeviceCount() async throws {
        let initialCount = await deviceStore.getDeviceCount()
        XCTAssertEqual(initialCount, 0)

        let device = Device(mac: "AA:BB:CC:DD:EE:FF", ip: "192.168.1.100")
        try await deviceStore.addOrUpdate(device: device)

        let finalCount = await deviceStore.getDeviceCount()
        XCTAssertEqual(finalCount, 1)
    }

    func testRemoveDevice() async throws {
        let device = Device(mac: "AA:BB:CC:DD:EE:FF", ip: "192.168.1.100")
        try await deviceStore.addOrUpdate(device: device)

        let countAfterAdd = await deviceStore.getDeviceCount()
        XCTAssertEqual(countAfterAdd, 1)

        try await deviceStore.remove(mac: "AA:BB:CC:DD:EE:FF")

        let countAfterRemove = await deviceStore.getDeviceCount()
        XCTAssertEqual(countAfterRemove, 0)

        let removedDevice = await deviceStore.getDevice(mac: "AA:BB:CC:DD:EE:FF")
        XCTAssertNil(removedDevice)
    }
}
