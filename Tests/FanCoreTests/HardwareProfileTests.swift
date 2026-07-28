import FanProtocol
import XCTest

@testable import FanCore

final class HardwareProfileTests: XCTestCase {
  func testUppercaseModeKeyIsPreferredWhenBothExist() {
    XCTAssertEqual(
      HardwareProfiler.selectModeKey(availableKeys: ["F0md", "F0Md"]),
      "F%dMd"
    )
  }

  func testLowercaseModeKeyIsUsedWhenUppercaseIsMissing() {
    XCTAssertEqual(
      HardwareProfiler.selectModeKey(availableKeys: ["F0md"]),
      "F%dmd"
    )
  }

  func testM3WithFtstUsesBoundedFallbackStrategy() {
    XCTAssertEqual(
      HardwareProfiler.strategy(modeKey: "F%dMd", hasFtst: true),
      .directThenFtst
    )
  }

  func testMissingModeKeyIsUnsupported() {
    XCTAssertEqual(HardwareProfiler.strategy(modeKey: nil, hasFtst: true), .unsupported)
  }
}
