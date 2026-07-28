import XCTest

@testable import MFanControlApp

final class MenuBarTemperaturePresentationTests: XCTestCase {
  func testEnabledPreferenceShowsRoundedTemperature() {
    XCTAssertEqual(
      MenuBarTemperaturePresentation.title(
        isEnabled: true,
        celsius: 57.4
      ),
      "57°C"
    )
  }

  func testDisabledPreferenceAndMissingSensorKeepIconOnly() {
    XCTAssertNil(
      MenuBarTemperaturePresentation.title(
        isEnabled: false,
        celsius: 57.4
      )
    )
    XCTAssertNil(
      MenuBarTemperaturePresentation.title(
        isEnabled: true,
        celsius: nil
      )
    )
  }
}
