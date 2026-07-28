import FanProtocol
import Foundation

public enum PresetPolicy {
  public static func target(
    minimum: Int,
    maximum: Int,
    percentage: Int
  ) throws -> Int {
    guard percentage >= 1, percentage <= 100, maximum > minimum else {
      throw ControlError.invalidRPM
    }

    let raw = Double(minimum) + (Double(percentage) / 100) * Double(maximum - minimum)
    let rounded = Int((raw / 100).rounded()) * 100
    return min(max(rounded, minimum), maximum)
  }
}
