import FanCore
import FanProtocol
import XCTest

@testable import FanDaemonCore

final class RequestProcessorTests: XCTestCase {
  func testMalformedManualRequestIsRejectedWithoutTouchingController() async {
    let controller = FakeFanController()
    let processor = RequestProcessor(controller: controller)

    let result = await processor.handle(
      FanRequest(id: "bad", command: .setManual, fan: 0, rpm: nil)
    )

    XCTAssertEqual(result.response.error, .malformedRequest)
    let malformedCalls = await controller.calls
    XCTAssertTrue(malformedCalls.isEmpty)
  }

  func testManualRequestReturnsFreshSnapshot() async {
    let controller = FakeFanController()
    let processor = RequestProcessor(controller: controller)

    let result = await processor.handle(
      FanRequest(id: "manual", command: .setManual, fan: 0, rpm: 3_000)
    )

    XCTAssertTrue(result.response.ok)
    XCTAssertEqual(result.response.fans?.first?.actualRPM, 3_000)
    let manualCalls = await controller.calls
    XCTAssertEqual(manualCalls, ["manual:0:3000", "snapshot"])
  }

  func testHeartbeatTimeoutAndDisconnectRestoreAutomaticMode() async {
    let start = Date(timeIntervalSince1970: 10_000)
    let controller = FakeFanController()
    let processor = RequestProcessor(controller: controller, now: { start })
    _ = await processor.handle(
      FanRequest(id: "manual", command: .setManual, fan: 0, rpm: 3_000)
    )

    await processor.tick(at: start.addingTimeInterval(5.1))
    await processor.handleDisconnect()

    let timeoutCalls = await controller.calls
    XCTAssertEqual(timeoutCalls.filter { $0 == "all-auto" }.count, 1)
  }

  func testShutdownRestoresAutomaticAndStopsServer() async {
    let controller = FakeFanController()
    let processor = RequestProcessor(controller: controller)

    let result = await processor.handle(FanRequest(id: "shutdown", command: .shutdown))

    XCTAssertTrue(result.shouldShutdown)
    let shutdownCalls = await controller.calls
    XCTAssertEqual(shutdownCalls, ["all-auto"])
  }

  func testManualIsRejectedDuringExistingThermalEmergency() async {
    let controller = FakeFanController()
    let processor = RequestProcessor(
      controller: controller,
      isThermalEmergency: { true }
    )

    let result = await processor.handle(
      FanRequest(id: "hot", command: .setManual, fan: 0, rpm: 3_000)
    )

    XCTAssertEqual(result.response.error, .thermalEmergency)
    let thermalCalls = await controller.calls
    XCTAssertTrue(thermalCalls.isEmpty)
  }

  func testPresetAppliesCalculatedTargetsToEveryFan() async {
    let controller = PresetFanController()
    let processor = RequestProcessor(controller: controller)

    let result = await processor.handle(
      FanRequest(id: "balanced", command: .setPreset, percentage: 30)
    )

    XCTAssertTrue(result.response.ok)
    let calls = await controller.calls
    XCTAssertEqual(calls, ["snapshot", "manual:0:2900", "manual:1:3200", "snapshot"])
  }

  func testPresetFailureRollsEveryFanBackToAutomatic() async {
    let controller = PresetFanController(failingFan: 1)
    let processor = RequestProcessor(controller: controller)

    let result = await processor.handle(
      FanRequest(id: "cool", command: .setPreset, percentage: 55)
    )

    XCTAssertFalse(result.response.ok)
    let calls = await controller.calls
    XCTAssertEqual(calls, ["snapshot", "manual:0:3700", "manual:1:4200", "all-auto"])
  }
}

private actor PresetFanController: FanControlling {
  private(set) var calls: [String] = []
  private let failingFan: Int?

  init(failingFan: Int? = nil) {
    self.failingFan = failingFan
  }

  func discoverHardware() async throws -> HardwareProfile {
    HardwareProfile(
      model: "Mac15,7",
      processor: "Apple M3 Pro",
      fanCount: 2,
      hasFtst: true,
      modeKeyFormat: "F%dMd",
      strategy: .directThenFtst,
      support: .experimental
    )
  }

  func snapshot() async throws -> [FanSnapshot] {
    calls.append("snapshot")
    return [
      FanSnapshot(
        index: 0,
        actualRPM: 2_000,
        targetRPM: 2_000,
        minimumRPM: 2_000,
        maximumRPM: 5_000,
        mode: .automatic
      ),
      FanSnapshot(
        index: 1,
        actualRPM: 2_200,
        targetRPM: 2_200,
        minimumRPM: 2_000,
        maximumRPM: 6_000,
        mode: .automatic
      ),
    ]
  }

  func setManual(fan: Int, rpm: Int) async throws -> FanSnapshot {
    calls.append("manual:\(fan):\(rpm)")
    if fan == failingFan {
      throw ControlError.verificationFailed
    }
    return FanSnapshot(
      index: fan,
      actualRPM: rpm,
      targetRPM: rpm,
      minimumRPM: 2_000,
      maximumRPM: fan == 0 ? 5_000 : 6_000,
      mode: .manual
    )
  }

  func setAutomatic(fan: Int) async throws -> FanSnapshot {
    FanSnapshot(
      index: fan,
      actualRPM: 2_000,
      targetRPM: 2_000,
      minimumRPM: 2_000,
      maximumRPM: fan == 0 ? 5_000 : 6_000,
      mode: .automatic
    )
  }

  func setAllAutomatic() async throws {
    calls.append("all-auto")
  }
}

private actor FakeFanController: FanControlling {
  private(set) var calls: [String] = []

  private let profile = HardwareProfile(
    model: "Mac15,7",
    processor: "Apple M3 Pro",
    fanCount: 1,
    hasFtst: true,
    modeKeyFormat: "F%dMd",
    strategy: .directThenFtst,
    support: .experimental
  )

  func discoverHardware() async throws -> HardwareProfile {
    calls.append("profile")
    return profile
  }

  func snapshot() async throws -> [FanSnapshot] {
    calls.append("snapshot")
    return [fan(mode: .manual, actual: 3_000)]
  }

  func setManual(fan: Int, rpm: Int) async throws -> FanSnapshot {
    calls.append("manual:\(fan):\(rpm)")
    return self.fan(mode: .manual, actual: rpm)
  }

  func setAutomatic(fan: Int) async throws -> FanSnapshot {
    calls.append("auto:\(fan)")
    return self.fan(mode: .automatic, actual: 2_000)
  }

  func setAllAutomatic() async throws {
    calls.append("all-auto")
  }

  private func fan(mode: FanMode, actual: Int) -> FanSnapshot {
    FanSnapshot(
      index: 0,
      actualRPM: actual,
      targetRPM: actual,
      minimumRPM: 2_000,
      maximumRPM: 5_000,
      mode: mode
    )
  }
}
