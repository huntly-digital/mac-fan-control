import Foundation

enum MenuBarTemperaturePresentation {
  static func title(isEnabled: Bool, celsius: Double?) -> String? {
    guard isEnabled, let celsius else { return nil }
    return "\(Int(celsius.rounded()))°C"
  }
}
