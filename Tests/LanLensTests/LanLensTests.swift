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
