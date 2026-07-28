import FanProtocol
import XCTest

@testable import MFanControlApp

final class HardwareValidationPresentationTests: XCTestCase {
  func testObserverGetsReadOnlyPresentation() {
    let presentation = HardwareValidationPresentation.resolve(
      eligibility: .approved,
      controlAccess: .observer
    )

    XCTAssertEqual(presentation.title, "Read-only session")
    XCTAssertFalse(presentation.canValidate)
  }

  func testValidationRequiredExplainsExplicitHardwareGate() {
    let presentation = HardwareValidationPresentation.resolve(
      eligibility: .validationRequired,
      controlAccess: .owner
    )

    XCTAssertEqual(presentation.title, "Hardware validation required")
    XCTAssertTrue(presentation.canValidate)
  }

  func testPrimaryTemperaturePreferenceUsesSelectedMetricThenHotspot() {
    let snapshot = TemperatureSnapshot(
      readings: [
        TemperatureReading(
          id: "cpu.average",
          label: "CPU Average",
          group: .cpu,
          role: .average,
          celsius: 61,
          sampleCount: 2,
          sourceKeys: ["A", "B"]
        ),
        TemperatureReading(
          id: "cpu.hotspot",
          label: "CPU Hotspot",
          group: .cpu,
          role: .hotspot,
          celsius: 73,
          sampleCount: 2,
          sourceKeys: ["A", "B"]
        ),
      ]
    )

    XCTAssertEqual(
      TemperaturePreference.primary(in: snapshot, selectedID: "cpu.average")?.celsius,
      61
    )
    XCTAssertEqual(
      TemperaturePreference.primary(in: snapshot, selectedID: "missing")?.celsius,
      73
    )
  }
}
