import FanCore
import FanProtocol
import XCTest

final class PresetPolicyTests: XCTestCase {
  func testApprovedPresetPercentagesRoundToNearestHundred() throws {
    XCTAssertEqual(
      try PresetPolicy.target(minimum: 1_350, maximum: 5_349, percentage: 10),
      1_700
    )
    XCTAssertEqual(
      try PresetPolicy.target(minimum: 1_350, maximum: 5_349, percentage: 30),
      2_500
    )
    XCTAssertEqual(
      try PresetPolicy.target(minimum: 1_350, maximum: 5_349, percentage: 55),
      3_500
    )
  }

  func testOneHundredPercentReturnsExactReportedMaximum() throws {
    XCTAssertEqual(
      try PresetPolicy.target(minimum: 1_350, maximum: 5_349, percentage: 100),
      5_349
    )
  }

  func testPresetRejectsPercentagesOutsideSafeBounds() {
    XCTAssertThrowsError(
      try PresetPolicy.target(minimum: 1_350, maximum: 5_349, percentage: 0)
    ) {
      XCTAssertEqual($0 as? ControlError, .invalidRPM)
    }
    XCTAssertThrowsError(
      try PresetPolicy.target(minimum: 1_350, maximum: 5_349, percentage: 101)
    ) {
      XCTAssertEqual($0 as? ControlError, .invalidRPM)
    }
  }
}
