import FanProtocol
import Foundation
import XCTest

@testable import FanCore

final class CapabilityAndPersistenceTests: XCTestCase {
  func testFingerprintIsStableForEquivalentFanOrdering() throws {
    let first = HardwareCapabilities.fixture(fans: [.fixture(index: 1), .fixture(index: 0)])
    let second = HardwareCapabilities.fixture(fans: [.fixture(index: 0), .fixture(index: 1)])

    XCTAssertEqual(try first.fingerprint(), try second.fingerprint())
    XCTAssertTrue(try first.fingerprint().hasPrefix("sha256:"))
  }

  func testCapabilityAssessmentRejectsMissingRequiredKey() {
    var fan = FanCapability.fixture(index: 0)
    fan = FanCapability(
      index: fan.index,
      actual: fan.actual,
      target: fan.target,
      minimum: fan.minimum,
      maximum: fan.maximum,
      mode: nil,
      minimumRPM: fan.minimumRPM,
      maximumRPM: fan.maximumRPM
    )

    XCTAssertEqual(
      HardwareCapabilities.fixture(fans: [fan]).writeEligibility,
      .unsupported
    )
  }

  func testCapabilityAssessmentRejectsWrongRPMDataType() {
    let invalid = SMCKeyCapability(key: "F0Mn", dataType: "ui16", dataSize: 2)
    let source = FanCapability.fixture(index: 0)
    let fan = FanCapability(
      index: 0,
      actual: source.actual,
      target: source.target,
      minimum: invalid,
      maximum: source.maximum,
      mode: source.mode,
      minimumRPM: source.minimumRPM,
      maximumRPM: source.maximumRPM
    )

    XCTAssertEqual(
      HardwareCapabilities.fixture(fans: [fan]).writeEligibility,
      .unsupported
    )
  }

  func testCapabilityAssessmentRejectsIntelAndUnknownFutureModels() {
    let fans = [FanCapability.fixture(index: 0)]
    let intel = HardwareCapabilities(
      model: "MacPro7,1",
      processor: "Intel Xeon W",
      osBuild: "25A123",
      fanCount: 1,
      hasFtst: true,
      ftst: .init(key: "Ftst", dataType: "ui8 ", dataSize: 1),
      modeKeyFormat: "F%dMd",
      strategy: .directThenFtst,
      fans: fans
    )
    let future = HardwareCapabilities(
      model: "Mac18,1",
      processor: "Apple M6",
      osBuild: "25A123",
      fanCount: 1,
      hasFtst: true,
      ftst: .init(key: "Ftst", dataType: "ui8 ", dataSize: 1),
      modeKeyFormat: "F%dMd",
      strategy: .directThenFtst,
      fans: fans
    )

    XCTAssertEqual(intel.writeEligibility, .unsupported)
    XCTAssertEqual(future.writeEligibility, .unsupported)
  }

  func testApprovalRequiresExactModelBuildAndFingerprint() throws {
    let directory = temporaryDirectory()
    let store = HardwareApprovalStore(
      url: directory.appendingPathComponent("hardware-approvals.json")
    )
    let approval = HardwareApproval(
      model: "Mac15,7",
      osBuild: "25A123",
      capabilityFingerprint: "sha256:one",
      validatedAt: Date(timeIntervalSince1970: 100)
    )

    try store.approve(approval)

    XCTAssertTrue(try store.isApproved(
      model: "Mac15,7",
      osBuild: "25A123",
      fingerprint: "sha256:one"
    ))
    XCTAssertFalse(try store.isApproved(
      model: "Mac15,7",
      osBuild: "25A124",
      fingerprint: "sha256:one"
    ))
    XCTAssertFalse(try store.isApproved(
      model: "Mac15,7",
      osBuild: "25A123",
      fingerprint: "sha256:two"
    ))
  }

  func testApprovalFileIsPrivateAndContainsNoDeviceIdentifier() throws {
    let directory = temporaryDirectory()
    let url = directory.appendingPathComponent("hardware-approvals.json")
    let store = HardwareApprovalStore(url: url)

    try store.approve(
      HardwareApproval(
        model: "Mac16,1",
        osBuild: "25A123",
        capabilityFingerprint: "sha256:private",
        validatedAt: Date(timeIntervalSince1970: 100)
      )
    )

    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    XCTAssertFalse(String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("serial"))
  }

  func testModelBuildRevocationRemovesApprovalEvenWhenFingerprintChanged() throws {
    let directory = temporaryDirectory()
    let store = HardwareApprovalStore(
      url: directory.appendingPathComponent("hardware-approvals.json")
    )
    try store.approve(
      HardwareApproval(
        model: "Mac15,7",
        osBuild: "25A123",
        capabilityFingerprint: "sha256:baseline",
        validatedAt: Date(timeIntervalSince1970: 100)
      )
    )

    try store.revoke(model: "Mac15,7", osBuild: "25A123")

    XCTAssertFalse(try store.isApproved(
      model: "Mac15,7",
      osBuild: "25A123",
      fingerprint: "sha256:baseline"
    ))
  }

  func testRecoveryJournalRoundTripsAndDeletesOnlyExplicitly() throws {
    let directory = temporaryDirectory()
    let url = directory.appendingPathComponent("recovery-state.json")
    let store = RecoveryStateStore(url: url)
    let state = RecoveryState(
      model: "Mac15,7",
      capabilityFingerprint: "sha256:recovery",
      fans: [
        FanBaseline(index: 0, minimumRPM: 1_350),
        FanBaseline(index: 1, minimumRPM: 1_458),
      ],
      acquiredFtst: true,
      createdAt: Date(timeIntervalSince1970: 100)
    )

    try store.save(state)

    XCTAssertEqual(try store.load(), state)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    try store.delete()
    XCTAssertNil(try store.load())
  }

  private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("mfan-tests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }
}

extension SMCKeyCapability {
  fileprivate static func rpm(_ key: String) -> Self {
    .init(key: key, dataType: "flt ", dataSize: 4)
  }
}

extension FanCapability {
  fileprivate static func fixture(index: Int) -> Self {
    .init(
      index: index,
      actual: .rpm("F\(index)Ac"),
      target: .rpm("F\(index)Tg"),
      minimum: .rpm("F\(index)Mn"),
      maximum: .rpm("F\(index)Mx"),
      mode: .init(key: "F\(index)Md", dataType: "ui8 ", dataSize: 1),
      minimumRPM: 1_350 + index,
      maximumRPM: 5_349 + index
    )
  }
}

extension HardwareCapabilities {
  fileprivate static func fixture(fans: [FanCapability]) -> Self {
    .init(
      model: "Mac15,7",
      processor: "Apple M3 Pro",
      osBuild: "25A123",
      fanCount: fans.count,
      hasFtst: true,
      ftst: .init(key: "Ftst", dataType: "ui8 ", dataSize: 1),
      modeKeyFormat: "F%dMd",
      strategy: .directThenFtst,
      fans: fans
    )
  }
}
