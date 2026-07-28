import FanProtocol
import XCTest

@testable import FanCore
@testable import SMCBridge

final class FanControllerTests: XCTestCase {
  func testDiscoveryAndSnapshotReadOnlyPath() async throws {
    let smc = FakeSMC.standard()
    let controller = FanController(
      transport: smc,
      isPrivileged: { false },
      sleep: { _ in }
    )

    let profile = try await controller.discoverHardware()
    let fans = try await controller.snapshot()

    XCTAssertEqual(profile.fanCount, 2)
    XCTAssertEqual(profile.modeKeyFormat, "F%dMd")
    XCTAssertTrue(profile.hasFtst)
    XCTAssertEqual(profile.writeEligibility, .approved)
    XCTAssertTrue(profile.capabilityFingerprint.hasPrefix("sha256:"))
    XCTAssertEqual(
      fans,
      [
        FanSnapshot(
          index: 0,
          actualRPM: 2_200,
          targetRPM: 2_500,
          minimumRPM: 2_000,
          maximumRPM: 5_000,
          mode: .automatic
        ),
        FanSnapshot(
          index: 1,
          actualRPM: 2_200,
          targetRPM: 2_500,
          minimumRPM: 2_000,
          maximumRPM: 5_000,
          mode: .automatic
        ),
      ]
    )
    XCTAssertTrue(smc.writes.isEmpty)
  }

  func testProbeIncludesReadOnlyFanTelemetryKeys() async throws {
    let smc = FakeSMC.standard()
    let controller = FanController(
      transport: smc,
      isPrivileged: { false },
      sleep: { _ in }
    )

    let report = try await controller.probe()

    XCTAssertEqual(
      Set(report.keys.map(\.key)),
      [
        "F0Ac", "F0Md", "F0Mn", "F0Mx", "F0Tg",
        "F1Ac", "F1Md", "F1Mn", "F1Mx", "F1Tg",
        "Ftst",
      ]
    )
    XCTAssertTrue(smc.writes.isEmpty)
  }

  func testTemperatureSnapshotReadsOnlyModelAllowlistedKeys() async throws {
    let smc = FakeSMC.standard()
    let controller = FanController(
      transport: smc,
      isPrivileged: { false },
      sleep: { _ in },
      temperatureModel: "Mac15,7"
    )

    let temperature = try await controller.temperatureSnapshot()

    XCTAssertEqual(temperature?.primaryReading()?.id, "cpu.hotspot")
    XCTAssertEqual(temperature?.primaryReading()?.celsius, 57)
    XCTAssertEqual(
      temperature?.readings.first { $0.id == "cpu.hotspot" }?.sourceKeys,
      ["TCMz"]
    )
    XCTAssertTrue(smc.writes.isEmpty)
  }

  func testManualUsesDirectModeThenTargetAndVerifiesActualRPM() async throws {
    let smc = FakeSMC.standard()
    smc.mirrorTargetToActual = true
    let controller = FanController(
      transport: smc,
      isPrivileged: { true },
      sleep: { _ in },
      verificationAttempts: 1
    )

    let snapshot = try await controller.setManual(fan: 0, rpm: 3_000)

    XCTAssertEqual(snapshot.mode, .manual)
    XCTAssertEqual(snapshot.actualRPM, 3_000)
    XCTAssertEqual(snapshot.minimumRPM, 2_000)
    XCTAssertEqual(snapshot.effectiveMinimumRPM, 3_000)
    XCTAssertEqual(smc.writes.map(\.key), ["F0Mn", "F0Md", "F0Tg"])
  }

  func testFirmwareRejectionUsesOnlyDocumentedFtstFallback() async throws {
    let smc = FakeSMC.standard()
    smc.rejectFirstManualModeWrite = true
    smc.mirrorTargetToActual = true
    let controller = FanController(
      transport: smc,
      isPrivileged: { true },
      sleep: { _ in },
      unlockAttempts: 1,
      verificationAttempts: 1
    )

    _ = try await controller.setManual(fan: 0, rpm: 3_000)

    XCTAssertEqual(smc.writes.map(\.key), ["F0Mn", "F0Md", "Ftst", "F0Md", "F0Tg"])
    XCTAssertEqual(smc.writes[2].bytes, [1])
  }

  func testFtstFallbackRetriesManualWriteWhileModeRemainsSystem() async throws {
    let smc = FakeSMC.standard()
    smc.setValue(key: "F0Md", bytes: [3])
    smc.rejectFirstManualModeWrite = true
    smc.transitionModeToAutomaticOnFtst = false
    smc.mirrorTargetToActual = true
    let controller = FanController(
      transport: smc,
      isPrivileged: { true },
      sleep: { _ in },
      unlockAttempts: 1,
      verificationAttempts: 1
    )

    let snapshot = try await controller.setManual(fan: 0, rpm: 3_000)

    XCTAssertEqual(snapshot.mode, .manual)
    XCTAssertEqual(snapshot.actualRPM, 3_000)
    XCTAssertEqual(smc.writes.map(\.key), ["F0Mn", "F0Md", "Ftst", "F0Md", "F0Tg"])
  }

  func testAcceptedDirectWriteFallsBackWhenSystemModeImmediatelyReturns() async throws {
    let smc = FakeSMC.standard()
    smc.setValue(key: "F0Md", bytes: [3])
    smc.revertSuccessfulManualModeWriteToSystemOnce = true
    smc.transitionModeToAutomaticOnFtst = false
    smc.mirrorTargetToActual = true
    let controller = FanController(
      transport: smc,
      isPrivileged: { true },
      sleep: { _ in },
      unlockAttempts: 1,
      verificationAttempts: 1
    )

    let snapshot = try await controller.setManual(fan: 0, rpm: 3_000)

    XCTAssertEqual(snapshot.mode, .manual)
    XCTAssertEqual(smc.writes.map(\.key), ["F0Mn", "F0Md", "Ftst", "F0Md", "F0Tg"])
  }

  func testInvalidRPMDoesNotWriteAnySMCKey() async {
    let smc = FakeSMC.standard()
    let controller = FanController(
      transport: smc,
      isPrivileged: { true },
      sleep: { _ in }
    )

    do {
      _ = try await controller.setManual(fan: 0, rpm: 1_900)
      XCTFail("Expected invalidRPM")
    } catch {
      XCTAssertEqual(error as? ControlError, .invalidRPM)
    }
    XCTAssertTrue(smc.writes.isEmpty)
  }

  func testVerificationFailureReturnsAllFansToAutomaticAndClearsOwnedFtst() async {
    let smc = FakeSMC.standard()
    smc.rejectFirstManualModeWrite = true
    let controller = FanController(
      transport: smc,
      isPrivileged: { true },
      sleep: { _ in },
      unlockAttempts: 1,
      verificationAttempts: 1
    )

    do {
      _ = try await controller.setManual(fan: 0, rpm: 3_000)
      XCTFail("Expected verificationFailed")
    } catch {
      XCTAssertEqual(error as? ControlError, .verificationFailed)
    }

    XCTAssertEqual(
      Array(smc.writes.suffix(4)).map(\.key),
      ["F0Md", "F1Md", "F0Mn", "Ftst"]
    )
    XCTAssertEqual(smc.writes.last?.bytes, [0])
  }

  func testExistingFtstOwnershipIsNotClaimedOrCleared() async throws {
    let smc = FakeSMC.standard()
    smc.setValue(key: "Ftst", bytes: [1])
    smc.rejectFirstManualModeWrite = true
    smc.mirrorTargetToActual = true
    let controller = FanController(
      transport: smc,
      isPrivileged: { true },
      sleep: { _ in },
      unlockAttempts: 1,
      verificationAttempts: 1
    )

    _ = try await controller.setManual(fan: 0, rpm: 3_000)
    _ = try await controller.setAutomatic(fan: 0)

    XCTAssertFalse(smc.writes.contains { $0.key == "Ftst" && $0.bytes == [0] })
  }

  func testAutomaticRestoresCapturedMinimumBeforeDeletingJournal() async throws {
    let smc = FakeSMC.standard()
    smc.mirrorTargetToActual = true
    let recoveryURL = temporaryDirectory().appendingPathComponent("recovery-state.json")
    let controller = FanController(
      transport: smc,
      isPrivileged: { true },
      sleep: { _ in },
      verificationAttempts: 1,
      recoveryStore: RecoveryStateStore(url: recoveryURL)
    )

    _ = try await controller.setManual(fan: 0, rpm: 3_000)
    _ = try await controller.setAutomatic(fan: 0)

    XCTAssertEqual(Array(smc.writes.suffix(2)).map(\.key), ["F0Md", "F0Mn"])
    XCTAssertEqual(try SMCValueCodec.decodeRPM(
      bytes: smc.writes.last!.bytes,
      dataType: "flt "
    ), 2_000)
    XCTAssertFalse(FileManager.default.fileExists(atPath: recoveryURL.path))
  }

  func testProductionApprovalGateRejectsWriteBeforeValidation() async {
    let smc = FakeSMC.standard()
    let directory = temporaryDirectory()
    let controller = FanController(
      transport: smc,
      isPrivileged: { true },
      sleep: { _ in },
      requiresApproval: true,
      approvalStore: HardwareApprovalStore(
        url: directory.appendingPathComponent("approvals.json")
      ),
      recoveryStore: RecoveryStateStore(
        url: directory.appendingPathComponent("recovery.json")
      )
    )

    do {
      _ = try await controller.setManual(fan: 0, rpm: 3_000)
      XCTFail("Expected validation gate")
    } catch {
      XCTAssertEqual(error as? ControlError, .hardwareValidationRequired)
    }
    XCTAssertTrue(smc.writes.isEmpty)
  }

  func testValidationExercisesEveryFanAndPersistsExactApproval() async throws {
    let smc = FakeSMC.standard()
    smc.mirrorTargetToActual = true
    let directory = temporaryDirectory()
    let approvalStore = HardwareApprovalStore(
      url: directory.appendingPathComponent("approvals.json")
    )
    let controller = FanController(
      transport: smc,
      isPrivileged: { true },
      sleep: { _ in },
      verificationAttempts: 1,
      requiresApproval: true,
      approvalStore: approvalStore,
      recoveryStore: RecoveryStateStore(
        url: directory.appendingPathComponent("recovery.json")
      ),
      hardwareModel: "Mac15,7",
      processorName: "Apple M3 Pro",
      osBuild: "25A123"
    )

    let report = try await controller.validateHardware()
    let profile = try await controller.discoverHardware()

    XCTAssertEqual(report.status, .passed)
    XCTAssertEqual(report.completedFans, 2)
    XCTAssertEqual(profile.writeEligibility, .approved)
    XCTAssertTrue(try approvalStore.isApproved(
      model: "Mac15,7",
      osBuild: "25A123",
      fingerprint: profile.capabilityFingerprint
    ))
  }

  func testMatchingStartupJournalRestoresBaselineBeforeTelemetry() async throws {
    let smc = FakeSMC.standard()
    let directory = temporaryDirectory()
    let recoveryStore = RecoveryStateStore(
      url: directory.appendingPathComponent("recovery.json")
    )
    let capabilities = try HardwareProfiler.inspect(
      using: smc,
      model: "Mac15,7",
      processor: "Apple M3 Pro",
      osBuild: "25A123"
    )
    smc.setValue(key: "F0Md", bytes: [1])
    smc.setRPM(key: "F0Mn", rpm: 3_000)
    try recoveryStore.save(
      RecoveryState(
        model: "Mac15,7",
        capabilityFingerprint: try capabilities.fingerprint(),
        fans: [FanBaseline(index: 0, minimumRPM: 2_000)],
        acquiredFtst: false,
        createdAt: Date()
      )
    )
    let controller = FanController(
      transport: smc,
      isPrivileged: { true },
      sleep: { _ in },
      recoveryStore: recoveryStore,
      hardwareModel: "Mac15,7",
      processorName: "Apple M3 Pro",
      osBuild: "25A123"
    )

    _ = try await controller.discoverHardware()

    XCTAssertEqual(Array(smc.writes.prefix(3)).map(\.key), ["F0Md", "F1Md", "F0Mn"])
    XCTAssertFalse(FileManager.default.fileExists(atPath: recoveryStore.url.path))
  }

  func testFingerprintMismatchBlocksWritesWithoutGuessingRecovery() async throws {
    let smc = FakeSMC.standard()
    let directory = temporaryDirectory()
    let recoveryStore = RecoveryStateStore(
      url: directory.appendingPathComponent("recovery.json")
    )
    try recoveryStore.save(
      RecoveryState(
        model: "Mac15,7",
        capabilityFingerprint: "sha256:stale",
        fans: [FanBaseline(index: 0, minimumRPM: 2_000)],
        acquiredFtst: false,
        createdAt: Date()
      )
    )
    let controller = FanController(
      transport: smc,
      isPrivileged: { true },
      sleep: { _ in },
      recoveryStore: recoveryStore,
      hardwareModel: "Mac15,7",
      processorName: "Apple M3 Pro",
      osBuild: "25A123"
    )

    let profile = try await controller.discoverHardware()
    XCTAssertEqual(profile.writeEligibility, .blocked)
    XCTAssertTrue(smc.writes.isEmpty)
    do {
      _ = try await controller.setManual(fan: 0, rpm: 3_000)
      XCTFail("Expected capability mismatch")
    } catch {
      XCTAssertEqual(error as? ControlError, .capabilityMismatch)
    }
    XCTAssertTrue(smc.writes.isEmpty)
  }

  func testCorruptRecoveryJournalPermanentlyBlocksRuntimeWrites() async throws {
    let smc = FakeSMC.standard()
    let directory = temporaryDirectory()
    let url = directory.appendingPathComponent("recovery.json")
    try Data("{not-json".utf8).write(to: url)
    let controller = FanController(
      transport: smc,
      isPrivileged: { true },
      sleep: { _ in },
      recoveryStore: RecoveryStateStore(url: url),
      hardwareModel: "Mac15,7",
      processorName: "Apple M3 Pro",
      osBuild: "25A123"
    )

    let first = try await controller.discoverHardware()
    let second = try await controller.discoverHardware()

    XCTAssertEqual(first.writeEligibility, .blocked)
    XCTAssertEqual(second.writeEligibility, .blocked)
    do {
      _ = try await controller.setManual(fan: 0, rpm: 3_000)
      XCTFail("Expected capability mismatch")
    } catch {
      XCTAssertEqual(error as? ControlError, .capabilityMismatch)
    }
    XCTAssertTrue(smc.writes.isEmpty)
  }

  func testFailedBaselineRestoreRevokesApprovalAndBlocksRuntime() async throws {
    let smc = FakeSMC.standard()
    smc.mirrorTargetToActual = true
    let directory = temporaryDirectory()
    let approvalStore = HardwareApprovalStore(
      url: directory.appendingPathComponent("approvals.json")
    )
    let capabilities = try HardwareProfiler.inspect(
      using: smc,
      model: "Mac15,7",
      processor: "Apple M3 Pro",
      osBuild: "25A123"
    )
    let fingerprint = try capabilities.fingerprint()
    try approvalStore.approve(
      HardwareApproval(
        model: "Mac15,7",
        osBuild: "25A123",
        capabilityFingerprint: fingerprint,
        validatedAt: Date()
      )
    )
    let controller = FanController(
      transport: smc,
      isPrivileged: { true },
      sleep: { _ in },
      verificationAttempts: 1,
      requiresApproval: true,
      approvalStore: approvalStore,
      recoveryStore: RecoveryStateStore(
        url: directory.appendingPathComponent("recovery.json")
      ),
      hardwareModel: "Mac15,7",
      processorName: "Apple M3 Pro",
      osBuild: "25A123"
    )
    _ = try await controller.setManual(fan: 0, rpm: 3_000)
    smc.rejectBaselineRestore = true

    do {
      _ = try await controller.setAutomatic(fan: 0)
      XCTFail("Expected baselineRestoreFailed")
    } catch {
      XCTAssertEqual(error as? ControlError, .baselineRestoreFailed)
    }
    XCTAssertFalse(try approvalStore.isApproved(
      model: "Mac15,7",
      osBuild: "25A123",
      fingerprint: fingerprint
    ))
  }

  func testSafetyRestoreCancelsAnInFlightManualTransitionBeforeTargetWrite() async throws {
    let smc = FakeSMC.standard()
    smc.mirrorTargetToActual = true
    let gate = AsyncSleepGate()
    let controller = FanController(
      transport: smc,
      isPrivileged: { true },
      sleep: { _ in await gate.pause() },
      verificationAttempts: 1
    )

    let manual = Task {
      try await controller.setManual(fan: 0, rpm: 3_000)
    }
    await gate.waitUntilPaused()
    try await controller.setAllAutomatic()
    await gate.resume()

    do {
      _ = try await manual.value
      XCTFail("Expected the stale transition to be cancelled")
    } catch {
      XCTAssertEqual(error as? ControlError, .verificationFailed)
    }
    XCTAssertFalse(smc.writes.contains { $0.key == "F0Tg" })
    XCTAssertEqual(try smc.readKey("F0Md").bytes.first, 0)
    XCTAssertEqual(
      Int(try SMCValueCodec.decodeRPM(
        bytes: smc.readKey("F0Mn").bytes,
        dataType: "flt "
      )),
      2_000
    )
  }

  private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("mfan-controller-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }
}

private actor AsyncSleepGate {
  private var paused = false
  private var continuation: CheckedContinuation<Void, Never>?

  func pause() async {
    paused = true
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func waitUntilPaused() async {
    while !paused {
      await Task.yield()
    }
  }

  func resume() {
    continuation?.resume()
    continuation = nil
  }
}

private final class FakeSMC: SMCTransport, @unchecked Sendable {
  struct Write: Equatable {
    let key: String
    let bytes: [UInt8]
  }

  private let lock = NSLock()
  private var values: [String: SMCReadValue]
  private var hasRejectedManualMode = false
  var rejectFirstManualModeWrite = false
  var revertSuccessfulManualModeWriteToSystemOnce = false
  var transitionModeToAutomaticOnFtst = true
  var mirrorTargetToActual = false
  var rejectBaselineRestore = false
  private(set) var writes: [Write] = []

  init(values: [String: SMCReadValue]) {
    self.values = values
  }

  static func standard() -> FakeSMC {
    var values: [String: SMCReadValue] = [:]
    values["FNum"] = value("FNum", type: "ui8 ", bytes: [2])
    values["Ftst"] = value("Ftst", type: "ui8 ", bytes: [0])
    values["TCMz"] = value("TCMz", type: "flt ", bytes: [0x00, 0x00, 0x64, 0x42])
    for fan in 0..<2 {
      values["F\(fan)Md"] = value("F\(fan)Md", type: "ui8 ", bytes: [0])
      values["F\(fan)Ac"] = value("F\(fan)Ac", type: "flt ", bytes: [0x00, 0x80, 0x09, 0x45])
      values["F\(fan)Tg"] = value("F\(fan)Tg", type: "flt ", bytes: [0x00, 0x40, 0x1C, 0x45])
      values["F\(fan)Mn"] = value("F\(fan)Mn", type: "flt ", bytes: [0x00, 0x00, 0xFA, 0x44])
      values["F\(fan)Mx"] = value("F\(fan)Mx", type: "flt ", bytes: [0x00, 0x40, 0x9C, 0x45])
    }
    return FakeSMC(values: values)
  }

  func readKeyInfo(_ key: String) throws -> SMCKeyInfo {
    lock.lock()
    defer { lock.unlock() }
    guard let value = values[key] else { throw SMCBridgeError.keyMissing }
    return value.info
  }

  func readKey(_ key: String) throws -> SMCReadValue {
    lock.lock()
    defer { lock.unlock() }
    guard let value = values[key] else { throw SMCBridgeError.keyMissing }
    return value
  }

  func writeKey(_ key: String, bytes: [UInt8]) throws {
    lock.lock()
    defer { lock.unlock() }
    writes.append(Write(key: key, bytes: bytes))
    guard let current = values[key] else { throw SMCBridgeError.keyMissing }
    if rejectBaselineRestore, key == "F0Mn",
      (try? SMCValueCodec.decodeRPM(bytes: bytes, dataType: current.info.dataType)) == 2_000
    {
      throw SMCBridgeError.firmwareRejected(0x82)
    }

    if rejectFirstManualModeWrite, key == "F0Md", bytes == [1], !hasRejectedManualMode {
      hasRejectedManualMode = true
      throw SMCBridgeError.firmwareRejected(0x82)
    }

    values[key] = SMCReadValue(info: current.info, bytes: bytes)
    if revertSuccessfulManualModeWriteToSystemOnce, key == "F0Md", bytes == [1] {
      revertSuccessfulManualModeWriteToSystemOnce = false
      values[key] = SMCReadValue(info: current.info, bytes: [3])
    }
    if transitionModeToAutomaticOnFtst, key == "Ftst", bytes == [1], let mode = values["F0Md"] {
      values["F0Md"] = SMCReadValue(info: mode.info, bytes: [0])
    }
    if mirrorTargetToActual, key.hasSuffix("Tg") {
      let actualKey = String(key.dropLast(2)) + "Ac"
      if let actual = values[actualKey] {
        values[actualKey] = SMCReadValue(info: actual.info, bytes: bytes)
      }
    }
  }

  func setValue(key: String, bytes: [UInt8]) {
    lock.lock()
    defer { lock.unlock() }
    guard let current = values[key] else { return }
    values[key] = SMCReadValue(info: current.info, bytes: bytes)
  }

  func setRPM(key: String, rpm: Int) {
    lock.lock()
    defer { lock.unlock() }
    guard let current = values[key],
      let bytes = try? SMCValueCodec.encodeRPM(Double(rpm), dataType: current.info.dataType)
    else {
      return
    }
    values[key] = SMCReadValue(info: current.info, bytes: bytes)
  }

  private static func value(_ key: String, type: String, bytes: [UInt8]) -> SMCReadValue {
    SMCReadValue(
      info: SMCKeyInfo(
        key: key,
        dataSize: UInt32(bytes.count),
        dataType: type,
        attributes: 0xC0
      ),
      bytes: bytes
    )
  }
}
