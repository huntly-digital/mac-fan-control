import Foundation

enum AboutPresentation {
  static let productDescription =
    "A source-only, safety-first menu bar utility for fan telemetry and bounded fixed-RPM control on Apple Silicon Macs."

  static let statusNote =
    "Experimental software — validate support on your exact Mac before enabling manual control."

  static let repositoryURL = URL(string: "https://github.com/huntly-digital/mac-fan-control")!
  static let issuesURL = URL(string: "https://github.com/huntly-digital/mac-fan-control/issues")!
  static let licenseURL = URL(
    string: "https://github.com/huntly-digital/mac-fan-control/blob/main/LICENSE"
  )!
}
