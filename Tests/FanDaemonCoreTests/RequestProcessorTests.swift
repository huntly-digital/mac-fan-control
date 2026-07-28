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

  func testMaxPresetAppliesEachFansExactMaximum() async {
    let controller = PresetFanController(maximumRPMs: [5_349, 5_777])
    let processor = RequestProcessor(controller: controller)

    let result = await processor.handle(
      FanRequest(id: "max", command: .setPreset, percentage: 100)
    )

    XCTAssertTrue(result.response.ok)
    let calls = await controller.calls
    XCTAssertEqual(calls, ["snapshot", "manual:0:5349", "manual:1:5777", "snapshot"])
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

  func testFirstHealthyHelloOwnsControllerAndObserverWritesAreRejected() async {
    let controller = FakeFanController()
    let processor = RequestProcessor(controller: controller)
    let owner = UUID()
    let observer = UUID()

    _ = await processor.handle(
      FanRequest(id: "owner", command: .hello),
      sessionID: owner
    )
    let observerHello = await processor.handle(
      FanRequest(id: "observer", command: .hello),
      sessionID: observer
    )
    let observerWrite = await processor.handle(
      FanRequest(id: "observer-write", command: .setManual, fan: 0, rpm: 3_000),
      sessionID: observer
    )
    let ownerWrite = await processor.handle(
      FanRequest(id: "owner-write", command: .setManual, fan: 0, rpm: 3_000),
      sessionID: owner
    )

    XCTAssertEqual(observerHello.response.controlAccess, .observer)
    XCTAssertEqual(observerWrite.response.error, .controllerBusy)
    XCTAssertTrue(ownerWrite.response.ok)
  }

  func testObserverDisconnectDoesNotRestoreButOwnerDisconnectDoes() async {
    let controller = FakeFanController()
    let processor = RequestProcessor(controller: controller)
    let owner = UUID()
    let observer = UUID()
    _ = await processor.handle(FanRequest(command: .hello), sessionID: owner)
    _ = await processor.handle(FanRequest(command: .hello), sessionID: observer)
    _ = await processor.handle(
      FanRequest(command: .setManual, fan: 0, rpm: 3_000),
      sessionID: owner
    )

    await processor.handleDisconnect(sessionID: observer)
    let observerDisconnectCalls = await controller.calls
    XCTAssertEqual(observerDisconnectCalls.filter { $0 == "all-auto" }.count, 0)

    await processor.handleDisconnect(sessionID: owner)
    let ownerDisconnectCalls = await controller.calls
    XCTAssertEqual(ownerDisconnectCalls.filter { $0 == "all-auto" }.count, 1)
  }

  func testOldOwnerWriteIsRejectedWhileDisconnectRestoreIsInProgress() async {
    let controller = RestoreGateFanController()
    let processor = RequestProcessor(controller: controller)
    let owner = UUID()
    _ = await processor.handle(FanRequest(command: .hello), sessionID: owner)
    _ = await processor.handle(
      FanRequest(command: .setManual, fan: 0, rpm: 3_000),
      sessionID: owner
    )

    let disconnect = Task {
      await processor.handleDisconnect(sessionID: owner)
    }
    await controller.waitUntilRestoreStarted()
    let lateWrite = await processor.handle(
      FanRequest(command: .setManual, fan: 0, rpm: 3_200),
      sessionID: owner
    )
    await controller.finishRestore()
    await disconnect.value

    XCTAssertEqual(lateWrite.response.error, .controllerBusy)
    let calls = await controller.calls
    XCTAssertFalse(calls.contains("manual:0:3200"))
  }

  func testValidationRequiresOwnerAndExplicitConfirmation() async {
    let controller = FakeFanController()
    let processor = RequestProcessor(controller: controller)
    let owner = UUID()
    _ = await processor.handle(FanRequest(command: .hello), sessionID: owner)

    let missingConfirmation = await processor.handle(
      FanRequest(command: .validateHardware),
      sessionID: owner
    )
    let confirmed = await processor.handle(
      FanRequest(command: .validateHardware, validationConfirmed: true),
      sessionID: owner
    )

    XCTAssertEqual(missingConfirmation.response.error, .malformedRequest)
    XCTAssertEqual(confirmed.response.validation?.status, .passed)
  }

  func testPowerDriftReappliesOnceThenRestoresAutomatic() async {
    let controller = FakeFanController()
    let processor = RequestProcessor(controller: controller)
    let owner = UUID()
    _ = await processor.handle(FanRequest(command: .hello), sessionID: owner)
    _ = await processor.handle(
      FanRequest(command: .setManual, fan: 0, rpm: 3_000),
      sessionID: owner
    )

    await processor.handlePowerSourceChanged()
    await processor.handlePowerSourceChanged()

    let calls = await controller.calls
    XCTAssertEqual(calls.filter { $0 == "manual:0:3000" }.count, 2)
    XCTAssertEqual(calls.filter { $0 == "all-auto" }.count, 1)
  }

  func testSecondPowerDriftDuringReapplyPreemptsToAutomatic() async {
    let controller = RestoreGateFanController(
      gateRestore: false,
      gateReapply: true
    )
    let processor = RequestProcessor(controller: controller)
    let owner = UUID()
    _ = await processor.handle(FanRequest(command: .hello), sessionID: owner)
    _ = await processor.handle(
      FanRequest(command: .setManual, fan: 0, rpm: 3_000),
      sessionID: owner
    )

    let firstDrift = Task {
      await processor.handlePowerSourceChanged()
    }
    await controller.waitUntilReapplyStarted()
    await processor.handlePowerSourceChanged()
    await controller.finishReapply()
    await firstDrift.value

    let calls = await controller.calls
    XCTAssertEqual(calls.filter { $0 == "all-auto" }.count, 1)
  }

  func testReturningLastManualFanToAutomaticStopsPowerReapply() async {
    let controller = FakeFanController()
    let processor = RequestProcessor(controller: controller)
    let owner = UUID()
    _ = await processor.handle(FanRequest(command: .hello), sessionID: owner)
    _ = await processor.handle(
      FanRequest(command: .setManual, fan: 0, rpm: 3_000),
      sessionID: owner
    )
    _ = await processor.handle(
      FanRequest(command: .setAutomatic, fan: 0),
      sessionID: owner
    )

    await processor.handlePowerSourceChanged()

    let calls = await controller.calls
    XCTAssertEqual(calls.filter { $0 == "manual:0:3000" }.count, 1)
    XCTAssertEqual(calls.filter { $0 == "all-auto" }.count, 0)
  }

  func testHeartbeatExpiryReleasesLeaseForNextHealthyHello() async {
    let start = Date(timeIntervalSince1970: 10_000)
    let controller = FakeFanController()
    let processor = RequestProcessor(controller: controller, now: { start })
    let first = UUID()
    let next = UUID()
    _ = await processor.handle(FanRequest(command: .hello), sessionID: first)
    _ = await processor.handle(
      FanRequest(command: .setManual, fan: 0, rpm: 3_000),
      sessionID: first
    )

    await processor.tick(at: start.addingTimeInterval(5.1))
    let nextHello = await processor.handle(
      FanRequest(command: .hello),
      sessionID: next
    )

    XCTAssertEqual(nextHello.response.controlAccess, .owner)
  }

  func testDuplicateOwnerHelloDoesNotDisableManualHeartbeatExpiry() async {
    let start = Date(timeIntervalSince1970: 10_000)
    let controller = FakeFanController()
    let processor = RequestProcessor(controller: controller, now: { start })
    let owner = UUID()
    _ = await processor.handle(FanRequest(command: .hello), sessionID: owner)
    _ = await processor.handle(
      FanRequest(command: .setManual, fan: 0, rpm: 3_000),
      sessionID: owner
    )

    _ = await processor.handle(FanRequest(command: .hello), sessionID: owner)
    await processor.tick(at: start.addingTimeInterval(5.1))

    let calls = await controller.calls
    XCTAssertEqual(calls.filter { $0 == "all-auto" }.count, 1)
  }
}

private actor RestoreGateFanController: FanControlling {
  private(set) var calls: [String] = []
  private let gateRestore: Bool
  private let gateReapply: Bool
  private var manualCallCount = 0
  private var restoreStarted = false
  private var restoreWaiter: CheckedContinuation<Void, Never>?
  private var restoreFinisher: CheckedContinuation<Void, Never>?
  private var reapplyStarted = false
  private var reapplyWaiter: CheckedContinuation<Void, Never>?
  private var reapplyFinisher: CheckedContinuation<Void, Never>?

  init(gateRestore: Bool = true, gateReapply: Bool = false) {
    self.gateRestore = gateRestore
    self.gateReapply = gateReapply
  }

  func discoverHardware() async throws -> HardwareProfile {
    HardwareProfile(
      model: "Mac15,7",
      processor: "Apple M3 Pro",
      fanCount: 1,
      hasFtst: true,
      modeKeyFormat: "F%dMd",
      strategy: .directThenFtst,
      support: .experimental
    )
  }

  func snapshot() async throws -> [FanSnapshot] {
    [fan(mode: .manual, actual: 3_000)]
  }

  func setManual(fan: Int, rpm: Int) async throws -> FanSnapshot {
    manualCallCount += 1
    calls.append("manual:\(fan):\(rpm)")
    if gateReapply, manualCallCount > 1 {
      reapplyStarted = true
      reapplyWaiter?.resume()
      reapplyWaiter = nil
      await withCheckedContinuation { continuation in
        reapplyFinisher = continuation
      }
    }
    return self.fan(mode: .manual, actual: rpm)
  }

  func setAutomatic(fan: Int) async throws -> FanSnapshot {
    self.fan(mode: .automatic, actual: 2_000)
  }

  func setAllAutomatic() async throws {
    calls.append("all-auto")
    restoreStarted = true
    restoreWaiter?.resume()
    restoreWaiter = nil
    if gateRestore {
      await withCheckedContinuation { continuation in
        restoreFinisher = continuation
      }
    }
  }

  func validateHardware() async throws -> HardwareValidationReport {
    HardwareValidationReport(
      status: .passed,
      completedFans: 1,
      totalFans: 1,
      message: "passed"
    )
  }

  func waitUntilRestoreStarted() async {
    guard !restoreStarted else { return }
    await withCheckedContinuation { continuation in
      restoreWaiter = continuation
    }
  }

  func finishRestore() {
    restoreFinisher?.resume()
    restoreFinisher = nil
  }

  func waitUntilReapplyStarted() async {
    guard !reapplyStarted else { return }
    await withCheckedContinuation { continuation in
      reapplyWaiter = continuation
    }
  }

  func finishReapply() {
    reapplyFinisher?.resume()
    reapplyFinisher = nil
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

private actor PresetFanController: FanControlling {
  private(set) var calls: [String] = []
  private let failingFan: Int?
  private let maximumRPMs: [Int]

  init(
    failingFan: Int? = nil,
    maximumRPMs: [Int] = [5_000, 6_000]
  ) {
    self.failingFan = failingFan
    self.maximumRPMs = maximumRPMs
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
        maximumRPM: maximumRPMs[0],
        mode: .automatic
      ),
      FanSnapshot(
        index: 1,
        actualRPM: 2_200,
        targetRPM: 2_200,
        minimumRPM: 2_000,
        maximumRPM: maximumRPMs[1],
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
      maximumRPM: maximumRPMs[fan],
      mode: .manual
    )
  }

  func setAutomatic(fan: Int) async throws -> FanSnapshot {
    FanSnapshot(
      index: fan,
      actualRPM: 2_000,
      targetRPM: 2_000,
      minimumRPM: 2_000,
      maximumRPM: maximumRPMs[fan],
      mode: .automatic
    )
  }

  func setAllAutomatic() async throws {
    calls.append("all-auto")
  }

  func validateHardware() async throws -> HardwareValidationReport {
    calls.append("validate")
    return HardwareValidationReport(
      status: .passed,
      completedFans: 2,
      totalFans: 2,
      message: "passed"
    )
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

  func validateHardware() async throws -> HardwareValidationReport {
    calls.append("validate")
    return HardwareValidationReport(
      status: .passed,
      completedFans: 1,
      totalFans: 1,
      message: "passed"
    )
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
