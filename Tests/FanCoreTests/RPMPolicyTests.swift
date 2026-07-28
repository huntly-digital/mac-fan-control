import FanProtocol
import XCTest

@testable import FanCore

final class RPMPolicyTests: XCTestCase {
  func testRPMInsideReportedRangeIsAccepted() throws {
    XCTAssertEqual(try RPMPolicy.validate(2_500, minimum: 2_000, maximum: 5_000), 2_500)
  }

  func testZeroBelowMinimumAndAboveMaximumAreRejected() {
    for rpm in [0, 1_900, 5_100] {
      XCTAssertThrowsError(
        try RPMPolicy.validate(rpm, minimum: 2_000, maximum: 5_000)
      ) { error in
        XCTAssertEqual(error as? ControlError, .invalidRPM)
      }
    }
  }

  func testVerificationUsesFifteenPercentTolerance() {
    XCTAssertTrue(RPMPolicy.isVerified(actual: 2_550, target: 3_000))
    XCTAssertFalse(RPMPolicy.isVerified(actual: 2_549, target: 3_000))
  }
}
