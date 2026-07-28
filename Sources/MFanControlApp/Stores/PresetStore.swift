import Combine
import Foundation

@MainActor
final class PresetStore: ObservableObject {
  @Published private(set) var quiet: Int
  @Published private(set) var balanced: Int
  @Published private(set) var cool: Int

  private enum Key {
    static let quiet = "preset.quiet.percentage"
    static let balanced = "preset.balanced.percentage"
    static let cool = "preset.cool.percentage"
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    quiet = Self.storedValue(for: Key.quiet, fallback: 10, defaults: defaults)
    balanced = Self.storedValue(for: Key.balanced, fallback: 30, defaults: defaults)
    cool = Self.storedValue(for: Key.cool, fallback: 55, defaults: defaults)
  }

  func percentage(for preset: FanPreset) -> Int? {
    switch preset {
    case .automatic, .manual: nil
    case .quiet: quiet
    case .balanced: balanced
    case .cool: cool
    case .maximum: 100
    }
  }

  func setPercentage(_ value: Int, for preset: FanPreset) {
    let value = min(max(value, 5), 80)
    switch preset {
    case .quiet:
      quiet = value
      defaults.set(value, forKey: Key.quiet)
    case .balanced:
      balanced = value
      defaults.set(value, forKey: Key.balanced)
    case .cool:
      cool = value
      defaults.set(value, forKey: Key.cool)
    case .automatic, .maximum, .manual:
      break
    }
  }

  private static func storedValue(
    for key: String,
    fallback: Int,
    defaults: UserDefaults
  ) -> Int {
    guard defaults.object(forKey: key) != nil else { return fallback }
    return min(max(defaults.integer(forKey: key), 5), 80)
  }
}
