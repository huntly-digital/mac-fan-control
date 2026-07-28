import Foundation
import Testing
@testable import MFanControlApp

@MainActor
@Suite("Fan presets")
struct FanPresetTests {
  @Test("Visible presets end with fixed Max")
  func visibleOrder() {
    #expect(FanPreset.visible == [.automatic, .quiet, .balanced, .cool, .maximum])
    #expect(FanPreset.maximum.title == "Max")
    #expect(FanPreset.maximum.systemImage == "fanblades.fill")
  }

  @Test("Max always resolves to one hundred percent")
  func fixedMaximumPercentage() {
    let suite = "MFanControlAppTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = PresetStore(defaults: defaults)

    #expect(store.percentage(for: .maximum) == 100)
    store.setPercentage(50, for: .maximum)
    #expect(store.percentage(for: .maximum) == 100)
  }
}
