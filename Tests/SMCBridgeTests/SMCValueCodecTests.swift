import XCTest

@testable import SMCBridge

final class SMCValueCodecTests: XCTestCase {
  func testAppleSiliconTemperatureUsesLittleEndianFloat() throws {
    XCTAssertEqual(
      try SMCValueCodec.decodeTemperature(
        bytes: [0x00, 0x00, 0x64, 0x42],
        dataType: "flt "
      ),
      57,
      accuracy: 0.01
    )
  }

  func testAppleSiliconFloatUsesLittleEndianIEEE754() throws {
    let bytes: [UInt8] = [0x00, 0x48, 0x1C, 0x45]

    XCTAssertEqual(try SMCValueCodec.decodeRPM(bytes: bytes, dataType: "flt "), 2_500.5)
    XCTAssertEqual(try SMCValueCodec.encodeRPM(2_500.5, dataType: "flt "), bytes)
  }

  func testFPE2UsesBigEndianFixedPoint() throws {
    let bytes: [UInt8] = [0x1F, 0x42]

    XCTAssertEqual(try SMCValueCodec.decodeRPM(bytes: bytes, dataType: "fpe2"), 2_000.5)
    XCTAssertEqual(try SMCValueCodec.encodeRPM(2_000.5, dataType: "fpe2"), bytes)
  }

  func testUnsignedSMCIntegersUseBigEndian() throws {
    XCTAssertEqual(try SMCValueCodec.decodeUnsigned([0x12, 0x34]), 0x1234)
    XCTAssertEqual(try SMCValueCodec.decodeUnsigned([0x01, 0x23, 0x45, 0x67]), 0x0123_4567)
  }

  func testUnsupportedRPMTypeIsRejected() {
    XCTAssertThrowsError(
      try SMCValueCodec.decodeRPM(bytes: [0, 0, 0, 0], dataType: "sp78")
    ) { error in
      XCTAssertEqual(error as? SMCBridgeError, .unsupportedDataType("sp78"))
    }
  }
}
