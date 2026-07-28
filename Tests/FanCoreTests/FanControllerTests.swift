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

    XCTAssertEqual(
      temperature,
      TemperatureSnapshot(
        cpuMaximumCelsius: 57,
        gpuCelsius: nil,
        batteryCelsius: nil,
        primarySensorName: "CPU Max"
      )
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
    XCTAssertEqual(smc.writes.map(\.key), ["F0Md", "F0Tg"])
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

    XCTAssertEqual(smc.writes.map(\.key), ["F0Md", "Ftst", "F0Md", "F0Tg"])
    XCTAssertEqual(smc.writes[1].bytes, [1])
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
    XCTAssertEqual(smc.writes.map(\.key), ["F0Md", "Ftst", "F0Md", "F0Tg"])
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
    XCTAssertEqual(smc.writes.map(\.key), ["F0Md", "Ftst", "F0Md", "F0Tg"])
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

    XCTAssertEqual(Array(smc.writes.suffix(3)).map(\.key), ["F0Md", "F1Md", "Ftst"])
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
