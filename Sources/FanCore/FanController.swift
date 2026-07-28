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
  func validateHardware() async throws -> HardwareValidationReport
}

extension FanControlling {
  public func temperatureSnapshot() async throws -> TemperatureSnapshot? { nil }
  public func validateHardware() async throws -> HardwareValidationReport {
    throw ControlError.unsupportedHardware
  }
}

public actor FanController: FanControlling {
  private let transport: any SMCTransport
  private let isPrivileged: @Sendable () -> Bool
  private let temperatureModel: String?
  private let hardwareModel: String?
  private let processorName: String?
  private let osBuild: String?
  private let requiresApproval: Bool
  private let approvalStore: HardwareApprovalStore?
  private let engine: AppleSiliconFanEngine

  private var cachedProfile: HardwareProfile?
  private var cachedCapabilities: HardwareCapabilities?
  private var controlEpoch: UInt64 = 0

  public init() throws {
    let transport = try SMCConnection()
    let approvalStore = HardwareApprovalStore()
    self.transport = transport
    self.isPrivileged = { geteuid() == 0 }
    self.temperatureModel = nil
    self.hardwareModel = nil
    self.processorName = nil
    self.osBuild = nil
    self.requiresApproval = true
    self.approvalStore = approvalStore
    self.engine = AppleSiliconFanEngine(
      transport: transport,
      sleep: { duration in try await Task.sleep(for: duration) },
      unlockAttempts: 100,
      verificationAttempts: 100,
      recoveryStore: RecoveryStateStore(),
      approvalStore: approvalStore
    )
  }

  package init(
    transport: any SMCTransport,
    isPrivileged: @escaping @Sendable () -> Bool,
    sleep: @escaping @Sendable (Duration) async throws -> Void,
    unlockAttempts: Int = 100,
    verificationAttempts: Int = 100,
    temperatureModel: String? = nil,
    requiresApproval: Bool = false,
    approvalStore: HardwareApprovalStore? = nil,
    recoveryStore: RecoveryStateStore? = nil,
    hardwareModel: String? = nil,
    processorName: String? = nil,
    osBuild: String? = nil
  ) {
    self.transport = transport
    self.isPrivileged = isPrivileged
    self.temperatureModel = temperatureModel
    self.hardwareModel = hardwareModel
    self.processorName = processorName
    self.osBuild = osBuild
    self.requiresApproval = requiresApproval
    self.approvalStore = approvalStore
    self.engine = AppleSiliconFanEngine(
      transport: transport,
      sleep: sleep,
      unlockAttempts: unlockAttempts,
      verificationAttempts: verificationAttempts,
      recoveryStore: recoveryStore,
      approvalStore: approvalStore
    )
  }

  public func discoverHardware() throws -> HardwareProfile {
    if let cachedProfile { return cachedProfile }
    do {
      var capabilities = try HardwareProfiler.inspect(
        using: transport,
        model: hardwareModel,
        processor: processorName,
        osBuild: osBuild
      )
      if engine.prepare(capabilities) {
        capabilities = try HardwareProfiler.inspect(
          using: transport,
          model: hardwareModel,
          processor: processorName,
          osBuild: osBuild
        )
      }
      let fingerprint = try capabilities.fingerprint()
      let approved: Bool
      if requiresApproval {
        approved = try approvalStore?.isApproved(
          model: capabilities.model,
          osBuild: capabilities.osBuild,
          fingerprint: fingerprint
        ) ?? false
      } else {
        approved = true
      }
      let eligibility: WriteEligibility
      if engine.runtimeBlocked {
        eligibility = .blocked
      } else if capabilities.writeEligibility == .unsupported {
        eligibility = .unsupported
      } else {
        eligibility = approved ? .approved : .validationRequired
      }
      let profile = try capabilities.profile(writeEligibility: eligibility)
      cachedCapabilities = capabilities
      cachedProfile = profile
      return profile
    } catch {
      throw map(error)
    }
  }

  public func snapshot() throws -> [FanSnapshot] {
    let profile = try discoverHardware()
    let capabilities = try capabilities()
    return try (0..<profile.fanCount).map {
      try engine.snapshot(fan: $0, capabilities: capabilities)
    }
  }

  public func temperatureSnapshot() async throws -> TemperatureSnapshot? {
    let profile = try discoverHardware()
    return TemperatureSensorRegistry.snapshot(model: temperatureModel ?? profile.model) {
      readTemperature(keys: [$0])
    }
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
    try requireWriteApproval(profile)
    do {
      return try await engine.setManual(
        fan: fan,
        rpm: rpm,
        capabilities: capabilities()
      )
    } catch {
      if engine.runtimeBlocked { cachedProfile = nil }
      throw error
    }
  }

  @discardableResult
  public func setAutomatic(fan: Int) throws -> FanSnapshot {
    guard isPrivileged() else { throw ControlError.notPrivileged }
    let profile = try discoverHardware()
    try validateFan(fan, profile: profile)
    controlEpoch &+= 1
    do {
      return try engine.setAutomatic(fan: fan, capabilities: capabilities())
    } catch {
      if engine.runtimeBlocked { cachedProfile = nil }
      throw error
    }
  }

  public func setAllAutomatic() throws {
    guard isPrivileged() else { throw ControlError.notPrivileged }
    _ = try discoverHardware()
    controlEpoch &+= 1
    do {
      try engine.restoreAll(capabilities())
    } catch {
      if engine.runtimeBlocked { cachedProfile = nil }
      throw error
    }
  }

  public func validateHardware() async throws -> HardwareValidationReport {
    guard isPrivileged() else { throw ControlError.notPrivileged }
    let profile = try discoverHardware()
    guard profile.writeEligibility != .unsupported else {
      throw ControlError.unsupportedHardware
    }
    guard profile.writeEligibility != .blocked else {
      throw engine.runtimeBlockError ?? ControlError.baselineRestoreFailed
    }
    let capabilities = try capabilities()
    let validationEpoch = controlEpoch
    var completed = 0
    do {
      for fan in capabilities.fans.sorted(by: { $0.index < $1.index }) {
        guard validationEpoch == controlEpoch else {
          throw ControlError.verificationFailed
        }
        guard let minimum = fan.minimumRPM, let maximum = fan.maximumRPM else {
          throw ControlError.capabilityMismatch
        }
        let target = min(maximum, minimum + 500)
        _ = try await engine.setManual(
          fan: fan.index,
          rpm: target,
          capabilities: capabilities
        )
        guard validationEpoch == controlEpoch else {
          throw ControlError.verificationFailed
        }
        _ = try engine.setAutomatic(fan: fan.index, capabilities: capabilities)
        completed += 1
      }
      try engine.restoreAll(capabilities)
      guard let approvalStore else { throw ControlError.firmwareRejected }
      try approvalStore.approve(
        HardwareApproval(
          model: capabilities.model,
          osBuild: capabilities.osBuild,
          capabilityFingerprint: try capabilities.fingerprint(),
          validatedAt: Date()
        )
      )
      cachedProfile = nil
      return HardwareValidationReport(
        status: .passed,
        completedFans: completed,
        totalFans: capabilities.fanCount,
        message: "Hardware validation passed."
      )
    } catch {
      try? engine.restoreAll(capabilities)
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

  private func capabilities() throws -> HardwareCapabilities {
    guard let cachedCapabilities else { throw ControlError.capabilityMismatch }
    return cachedCapabilities
  }

  private func requireWriteApproval(_ profile: HardwareProfile) throws {
    switch profile.writeEligibility {
    case .approved:
      return
    case .validationRequired:
      throw ControlError.hardwareValidationRequired
    case .blocked:
      throw engine.runtimeBlockError ?? ControlError.baselineRestoreFailed
    case .unsupported:
      throw ControlError.unsupportedHardware
    }
  }

  private func validateFan(_ fan: Int, profile: HardwareProfile) throws {
    guard fan >= 0, fan < profile.fanCount else {
      throw ControlError.keyMissing
    }
  }

  private func map(_ error: Error) -> ControlError {
    if let controlError = error as? ControlError { return controlError }
    if error is DecodingError { return .capabilityMismatch }
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
