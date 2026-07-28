import Foundation

enum FanPreset: String, CaseIterable, Identifiable {
  case automatic
  case quiet
  case balanced
  case cool
  case manual

  static let visible: [FanPreset] = [.automatic, .quiet, .balanced, .cool]

  var id: String { rawValue }

  var title: String {
    switch self {
    case .automatic: "Auto"
    case .quiet: "Quiet"
    case .balanced: "Balanced"
    case .cool: "Cool"
    case .manual: "Manual"
    }
  }

  var systemImage: String {
    switch self {
    case .automatic: "a.circle"
    case .quiet: "leaf"
    case .balanced: "dial.medium"
    case .cool: "snowflake"
    case .manual: "slider.horizontal.3"
    }
  }
}
