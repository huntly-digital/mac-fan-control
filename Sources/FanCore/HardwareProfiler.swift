import Darwin
import FanProtocol
import Foundation
import SMCBridge

public enum HardwareProfiler {
  public static func selectModeKey(availableKeys: Set<String>) -> String? {
    if availableKeys.contains("F0Md") { return "F%dMd" }
    if availableKeys.contains("F0md") { return "F%dmd" }
    return nil
  }

  public static func strategy(modeKey: String?, hasFtst: Bool) -> ControlStrategy {
    guard modeKey != nil else { return .unsupported }
    return hasFtst ? .directThenFtst : .direct
  }

  package static func discover(using transport: any SMCTransport) throws -> HardwareProfile {
    let fanCountValue = try transport.readKey("FNum")
    let fanCount = Int(try SMCValueCodec.decodeUnsigned(fanCountValue.bytes))
    let keys = Set(["F0Md", "F0md"].filter { (try? transport.readKeyInfo($0)) != nil })
    let modeKey = selectModeKey(availableKeys: keys)
    let hasFtst = (try? transport.readKeyInfo("Ftst")) != nil
    let model = sysctlString("hw.model")
    let processor = sysctlString("machdep.cpu.brand_string")
    let support: HardwareSupport = modeKey == nil ? .unsupported : .experimental

    return HardwareProfile(
      model: model,
      processor: processor,
      fanCount: fanCount,
      hasFtst: hasFtst,
      modeKeyFormat: modeKey,
      strategy: strategy(modeKey: modeKey, hasFtst: hasFtst),
      support: support
    )
  }

  private static func sysctlString(_ name: String) -> String {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "Unknown" }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "Unknown" }
    return String(bytes: buffer.prefix { $0 != 0 }.map(UInt8.init), encoding: .utf8) ?? "Unknown"
  }
}
