import FanProtocol
import XCTest

@testable import MFanControlApp

final class FanPresetReconciliationTests: XCTestCase {
  func testSafetyFallbackReconcilesHighlightedPresetToAutomatic() {
    let fans = [fan(mode: .automatic, targetRPM: 2_000)]

    XCTAssertEqual(
      FanPresetReconciliation.resolve(
        fans: fans,
        current: .cool,
        percentage: 55
      ),
      .automatic
    )
  }

  func testUnprovenManualTargetsClearNamedPresetIdentity() {
    let fans = [fan(mode: .manual, targetRPM: 3_100)]

    XCTAssertEqual(
      FanPresetReconciliation.resolve(
        fans: fans,
        current: .cool,
        percentage: 55
      ),
      .manual
    )
  }

  func testExactManualTargetsPreserveNamedPreset() {
    let fans = [fan(mode: .manual, targetRPM: 3_700)]

    XCTAssertEqual(
      FanPresetReconciliation.resolve(
        fans: fans,
        current: .cool,
        percentage: 55
      ),
      .cool
    )
  }

  private func fan(mode: FanMode, targetRPM: Int) -> FanSnapshot {
    FanSnapshot(
      index: 0,
      actualRPM: targetRPM,
      targetRPM: targetRPM,
      minimumRPM: 2_000,
      maximumRPM: 5_000,
      mode: mode
    )
  }
}
