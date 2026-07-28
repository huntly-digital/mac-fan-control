import Darwin
import FanProtocol
import Foundation
import SMCBridge

public struct ProbeKey: Codable, Equatable, Sendable {
  public let key: String
  public let dataType: String
  public let bytes: [UInt8]

  public init(key: String, dataType: String, bytes: [UInt8]) {
    self.key = key
    self.dataType = dataType
    self.bytes = bytes
  }
}

public struct ProbeReport: Codable, Equatable, Sendable {
  public let hardware: HardwareProfile
  public let keys: [ProbeKey]

  public init(hardware: HardwareProfile, keys: [ProbeKey]) {
    self.hardware = hardware
    self.keys = keys
  }
}

public protocol FanControlling: Sendable {
  func discoverHardware() async throws -> HardwareProfile
  func snapshot() async throws -> [FanSnapshot]
  func temperatureSnapshot() async throws -> TemperatureSnapshot?
  func setManual(fan: Int, rpm: Int) async throws -> FanSnapshot
  func setAutomatic(fan: Int) async throws -> FanSnapshot
  func setAllAutomatic() async throws
}

extension FanControlling {
  public func temperatureSnapshot() async throws -> TemperatureSnapshot? { nil }
}

public actor FanController: FanControlling {
  private let transport: any SMCTransport
  private let isPrivileged: @Sendable () -> Bool
  private let sleep: @Sendable (Duration) async throws -> Void
  private let unlockAttempts: Int
  private let verificationAttempts: Int
  private let temperatureModel: String?

  private var cachedProfile: HardwareProfile?
  private var manualFans: Set<Int> = []
  private var ownsFtst = false

  public init() throws {
    self.transport = try SMCConnection()
    self.isPrivileged = { geteuid() == 0 }
    self.sleep = { duration in try await Task.sleep(for: duration) }
    self.unlockAttempts = 100
    self.verificationAttempts = 100
    self.temperatureModel = nil
  }

  package init(
    transport: any SMCTransport,
    isPrivileged: @escaping @Sendable () -> Bool,
    sleep: @escaping @Sendable (Duration) async throws -> Void,
    unlockAttempts: Int = 100,
    verificationAttempts: Int = 100,
    temperatureModel: String? = nil
  ) {
    self.transport = transport
    self.isPrivileged = isPrivileged
    self.sleep = sleep
    self.unlockAttempts = unlockAttempts
    self.verificationAttempts = verificationAttempts
    self.temperatureModel = temperatureModel
  }

  public func discoverHardware() throws -> HardwareProfile {
    if let cachedProfile { return cachedProfile }
    do {
      let profile = try HardwareProfiler.discover(using: transport)
      cachedProfile = profile
      return profile
    } catch {
      throw map(error)
    }
  }

  public func snapshot() throws -> [FanSnapshot] {
    let profile = try discoverHardware()
    return try (0..<profile.fanCount).map { try snapshot(fan: $0, profile: profile) }
  }

  public func temperatureSnapshot() async throws -> TemperatureSnapshot? {
    let profile = try discoverHardware()
    guard (temperatureModel ?? profile.model) == "Mac15,7" else { return nil }
    guard let cpu = readTemperature(keys: ["TCMz"]) else { return nil }

    return TemperatureSnapshot(
      cpuMaximumCelsius: cpu,
      gpuCelsius: readTemperature(keys: ["TG0D"]),
      batteryCelsius: readTemperature(keys: ["TB0T"]),
      primarySensorName: "CPU Max"
    )
  }

  public func probe() throws -> ProbeReport {
    let profile = try discoverHardware()
    var keys: [ProbeKey] = []
    let candidates =
      (0..<max(profile.fanCount, 1)).flatMap { fan in
        [
          "F\(fan)Ac",
          "F\(fan)Tg",
          "F\(fan)Mn",
          "F\(fan)Mx",
          "F\(fan)Md",
          "F\(fan)md",
        ]
      } + ["Ftst"]

    for key in candidates {
      if let value = try? transport.readKey(key) {
        keys.append(ProbeKey(key: key, dataType: value.info.dataType, bytes: value.bytes))
      }
    }
    return ProbeReport(hardware: profile, keys: keys)
  }

  @discardableResult
  public func setManual(fan: Int, rpm: Int) async throws -> FanSnapshot {
    guard isPrivileged() else { throw ControlError.notPrivileged }
    let profile = try discoverHardware()
    try validateFan(fan, profile: profile)
    guard let modeFormat = profile.modeKeyFormat else {
      throw ControlError.unsupportedHardware
    }

    let before = try snapshot(fan: fan, profile: profile)
    _ = try RPMPolicy.validate(rpm, minimum: before.minimumRPM, maximum: before.maximumRPM)
    let modeKey = key(modeFormat, fan: fan)

    var needsFtstFallback = false
    do {
      try transport.writeKey(modeKey, bytes: [1])
    } catch let bridgeError as SMCBridgeError {
      guard case .firmwareRejected = bridgeError, profile.hasFtst else {
        throw map(bridgeError)
      }
      needsFtstFallback = true
    } catch {
      throw map(error)
    }

    if !needsFtstFallback {
      do {
        try await sleep(.milliseconds(100))
        needsFtstFallback = try transport.readKey(modeKey).bytes.first != 1
      } catch {
        throw map(error)
      }
    }
    if needsFtstFallback {
      guard profile.hasFtst else { throw ControlError.firmwareRejected }
      try await unlockWithFtst(modeKey: modeKey)
    }

    do {
      let targetKey = key("F%dTg", fan: fan)
      let targetInfo = try transport.readKeyInfo(targetKey)
      let bytes = try SMCValueCodec.encodeRPM(Double(rpm), dataType: targetInfo.dataType)
      try transport.writeKey(targetKey, bytes: bytes)
      manualFans.insert(fan)

      for attempt in 0..<max(verificationAttempts, 1) {
        let current = try snapshot(fan: fan, profile: profile)
        if RPMPolicy.isVerified(actual: current.actualRPM, target: rpm) {
          return current
        }
        if attempt + 1 < verificationAttempts {
          try await sleep(.milliseconds(100))
        }
      }
    } catch let error as ControlError {
      try? setAllAutomatic()
      throw error
    } catch {
      try? setAllAutomatic()
      throw map(error)
    }

    try? setAllAutomatic()
    throw ControlError.verificationFailed
  }

  @discardableResult
  public func setAutomatic(fan: Int) throws -> FanSnapshot {
    guard isPrivileged() else { throw ControlError.notPrivileged }
    let profile = try discoverHardware()
    try validateFan(fan, profile: profile)
    guard let modeFormat = profile.modeKeyFormat else {
      throw ControlError.unsupportedHardware
    }

    do {
      try transport.writeKey(key(modeFormat, fan: fan), bytes: [0])
      manualFans.remove(fan)
      if manualFans.isEmpty {
        try resetOwnedFtstIfNeeded()
      }
      return try snapshot(fan: fan, profile: profile)
    } catch {
      throw map(error)
    }
  }

  public func setAllAutomatic() throws {
    guard isPrivileged() else { throw ControlError.notPrivileged }
    let profile = try discoverHardware()
    guard let modeFormat = profile.modeKeyFormat else {
      throw ControlError.unsupportedHardware
    }

    var firstError: Error?
    for fan in 0..<profile.fanCount {
      do {
        try transport.writeKey(key(modeFormat, fan: fan), bytes: [0])
      } catch {
        firstError = firstError ?? error
      }
    }
    manualFans.removeAll()
    do {
      try resetOwnedFtstIfNeeded()
    } catch {
      firstError = firstError ?? error
    }
    if let firstError { throw map(firstError) }
  }

  private func unlockWithFtst(modeKey: String) async throws {
    do {
      let previousFtst = try transport.readKey("Ftst").bytes.first
      try transport.writeKey("Ftst", bytes: [1])
      ownsFtst = previousFtst != 1
      try await sleep(.milliseconds(500))
    } catch {
      try? resetOwnedFtstIfNeeded()
      throw map(error)
    }

    for attempt in 0..<max(unlockAttempts, 1) {
      do {
        try transport.writeKey(modeKey, bytes: [1])
        return
      } catch {
        if attempt + 1 < unlockAttempts {
          do {
            try await sleep(.milliseconds(100))
          } catch {
            try? resetOwnedFtstIfNeeded()
            throw map(error)
          }
        }
      }
    }

    try? resetOwnedFtstIfNeeded()
    throw ControlError.unlockTimedOut
  }

  private func resetOwnedFtstIfNeeded() throws {
    guard ownsFtst else { return }
    defer { ownsFtst = false }
    try transport.writeKey("Ftst", bytes: [0])
  }

  private func snapshot(fan: Int, profile: HardwareProfile) throws -> FanSnapshot {
    try validateFan(fan, profile: profile)
    let actual = try readRPM(key("F%dAc", fan: fan))
    let target = try readRPM(key("F%dTg", fan: fan))
    let minimum = try readRPM(key("F%dMn", fan: fan))
    let maximum = try readRPM(key("F%dMx", fan: fan))
    let mode = try readMode(fan: fan, profile: profile)
    return FanSnapshot(
      index: fan,
      actualRPM: actual,
      targetRPM: target,
      minimumRPM: minimum,
      maximumRPM: maximum,
      mode: mode
    )
  }

  private func readRPM(_ key: String) throws -> Int {
    do {
      let value = try transport.readKey(key)
      return Int(
        try SMCValueCodec.decodeRPM(
          bytes: value.bytes,
          dataType: value.info.dataType
        ).rounded())
    } catch {
      throw map(error)
    }
  }

  private func readTemperature(keys: [String]) -> Double? {
    for key in keys {
      guard let value = try? transport.readKey(key) else { continue }
      if let temperature = try? SMCValueCodec.decodeTemperature(
        bytes: value.bytes,
        dataType: value.info.dataType
      ) {
        return temperature
      }
    }
    return nil
  }

  private func readMode(fan: Int, profile: HardwareProfile) throws -> FanMode {
    guard let modeFormat = profile.modeKeyFormat else { return .unknown }
    let value = try transport.readKey(key(modeFormat, fan: fan)).bytes.first
    switch value {
    case 0: return .automatic
    case 1: return .manual
    case 3: return .system
    default: return .unknown
    }
  }

  private func validateFan(_ fan: Int, profile: HardwareProfile) throws {
    guard fan >= 0, fan < profile.fanCount else {
      throw ControlError.keyMissing
    }
  }

  private func key(_ format: String, fan: Int) -> String {
    String(format: format, fan)
  }

  private func map(_ error: Error) -> ControlError {
    if let controlError = error as? ControlError { return controlError }
    guard let bridgeError = error as? SMCBridgeError else {
      return .firmwareRejected
    }
    switch bridgeError {
    case .keyMissing:
      return .keyMissing
    case .notPrivileged:
      return .notPrivileged
    case .firmwareRejected:
      return .firmwareRejected
    default:
      return .firmwareRejected
    }
  }
}
