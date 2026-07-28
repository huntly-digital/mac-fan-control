import FanProtocol
import Foundation

public enum RPMPolicy {
  public static func validate(_ rpm: Int, minimum: Int, maximum: Int) throws -> Int {
    guard rpm > 0, minimum <= rpm, rpm <= maximum else {
      throw ControlError.invalidRPM
    }
    return rpm
  }

  public static func isVerified(actual: Int, target: Int, tolerance: Double = 0.15) -> Bool {
    guard target > 0 else { return false }
    return abs(Double(actual - target)) <= Double(target) * tolerance
  }
}
