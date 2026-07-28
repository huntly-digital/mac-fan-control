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
    try inspect(using: transport).profile(approved: false)
  }

  package static func inspect(
    using transport: any SMCTransport,
    model: String? = nil,
    processor: String? = nil,
    osBuild: String? = nil
  ) throws -> HardwareCapabilities {
    let fanCountValue = try transport.readKey("FNum")
    let fanCount = Int(try SMCValueCodec.decodeUnsigned(fanCountValue.bytes))
    let keys = Set(["F0Md", "F0md"].filter { (try? transport.readKeyInfo($0)) != nil })
    let modeKey = selectModeKey(availableKeys: keys)
    let ftst = capability("Ftst", transport: transport)
    let hasFtst = ftst != nil
    let strategy = strategy(modeKey: modeKey, hasFtst: hasFtst)
    let fans = (0..<fanCount).map { fan in
      let minimumKey = "F\(fan)Mn"
      let maximumKey = "F\(fan)Mx"
      return FanCapability(
        index: fan,
        actual: capability("F\(fan)Ac", transport: transport),
        target: capability("F\(fan)Tg", transport: transport),
        minimum: capability(minimumKey, transport: transport),
        maximum: capability(maximumKey, transport: transport),
        mode: modeKey.flatMap {
          capability(String(format: $0, fan), transport: transport)
        },
        minimumRPM: readRPM(minimumKey, transport: transport),
        maximumRPM: readRPM(maximumKey, transport: transport)
      )
    }

    return HardwareCapabilities(
      model: model ?? sysctlString("hw.model"),
      processor: processor ?? sysctlString("machdep.cpu.brand_string"),
      osBuild: osBuild ?? sysctlString("kern.osversion"),
      fanCount: fanCount,
      hasFtst: hasFtst,
      ftst: ftst,
      modeKeyFormat: modeKey,
      strategy: strategy,
      fans: fans
    )
  }

  private static func capability(
    _ key: String,
    transport: any SMCTransport
  ) -> SMCKeyCapability? {
    guard let info = try? transport.readKeyInfo(key) else { return nil }
    return SMCKeyCapability(
      key: key,
      dataType: info.dataType,
      dataSize: info.dataSize
    )
  }

  private static func readRPM(_ key: String, transport: any SMCTransport) -> Int? {
    guard let value = try? transport.readKey(key),
      let rpm = try? SMCValueCodec.decodeRPM(
        bytes: value.bytes,
        dataType: value.info.dataType
      ),
      rpm.isFinite
    else {
      return nil
    }
    return Int(rpm.rounded())
  }

  private static func sysctlString(_ name: String) -> String {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "Unknown" }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "Unknown" }
    return String(bytes: buffer.prefix { $0 != 0 }.map(UInt8.init), encoding: .utf8) ?? "Unknown"
  }
}
