import Testing
@testable import MFanControlApp

@Suite("About presentation")
struct AboutPresentationTests {
  @Test("Uses accurate product and experimental status copy")
  func copy() {
    #expect(
      AboutPresentation.productDescription
        == "A source-only, safety-first menu bar utility for fan telemetry and bounded fixed-RPM control on Apple Silicon Macs."
    )
    #expect(
      AboutPresentation.statusNote
        == "Experimental software — validate support on your exact Mac before enabling manual control."
    )
  }

  @Test("Uses Huntly Digital GitHub destinations")
  func links() {
    #expect(
      AboutPresentation.repositoryURL.absoluteString
        == "https://github.com/huntly-digital/mac-fan-control"
    )
    #expect(
      AboutPresentation.issuesURL.absoluteString
        == "https://github.com/huntly-digital/mac-fan-control/issues"
    )
    #expect(
      AboutPresentation.licenseURL.absoluteString
        == "https://github.com/huntly-digital/mac-fan-control/blob/main/LICENSE"
    )
  }
}
