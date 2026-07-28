import FanCore
import XCTest

final class HardwareTests: XCTestCase {
  func testReadOnlyDiscoveryFindsAtLeastOneFan() async throws {
    guard ProcessInfo.processInfo.environment["MFAN_HARDWARE_TESTS"] == "1" else {
      throw XCTSkip("Set MFAN_HARDWARE_TESTS=1 to run read-only hardware tests")
    }

    let controller = try FanController()
    let profile = try await controller.discoverHardware()
    let fans = try await controller.snapshot()

    XCTAssertGreaterThan(profile.fanCount, 0)
    XCTAssertEqual(fans.count, profile.fanCount)
  }
}
