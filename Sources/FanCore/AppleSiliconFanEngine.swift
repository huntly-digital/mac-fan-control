import FanProtocol
import Foundation
import SMCBridge

final class AppleSiliconFanEngine: @unchecked Sendable {
  private let transport: any SMCTransport
  private let sleep: @Sendable (Duration) async throws -> Void
  private let unlockAttempts: Int
  private let verificationAttempts: Int
  private let recoveryStore: RecoveryStateStore?
  private let approvalStore: HardwareApprovalStore?

  private(set) var runtimeBlockError: ControlError?
  var runtimeBlocked: Bool { runtimeBlockError != nil }
  private var recoveryChecked = false
  private var baselines: [Int: Int] = [:]
  private var manualFans: Set<Int> = []
  private var ownsFtst = false
  private var transitionGeneration: UInt64 = 0

  init(
    transport: any SMCTransport,
    sleep: @escaping @Sendable (Duration) async throws -> Void,
    unlockAttempts: Int,
    verificationAttempts: Int,
    recoveryStore: RecoveryStateStore?,
    approvalStore: HardwareApprovalStore?
  ) {
    self.transport = transport
    self.sleep = sleep
    self.unlockAttempts = unlockAttempts
    self.verificationAttempts = verificationAttempts
    self.recoveryStore = recoveryStore
    self.approvalStore = approvalStore
  }

  @discardableResult
  func prepare(_ capabilities: HardwareCapabilities) -> Bool {
    guard !recoveryChecked else { return false }
    recoveryChecked = true
    let state: RecoveryState
    do {
      guard let loaded = try recoveryStore?.load() else { return false }
      state = loaded
    } catch {
      runtimeBlockError = .capabilityMismatch
      return false
    }
    let fingerprint: String
    do {
      fingerprint = try capabilities.fingerprint(
        minimumOverrides: Dictionary(
          uniqueKeysWithValues: state.fans.map { ($0.index, $0.minimumRPM) }
        )
      )
    } catch {
      runtimeBlockError = .capabilityMismatch
      return false
    }
    guard state.model == capabilities.model,
      state.capabilityFingerprint == fingerprint
    else {
      runtimeBlockError = .capabilityMismatch
      return false
    }

    baselines = Dictionary(uniqueKeysWithValues: state.fans.map { ($0.index, $0.minimumRPM) })
    manualFans = Set(state.fans.map(\.index))
    ownsFtst = state.acquiredFtst
    do {
      try restoreAll(capabilities)
      return true
    } catch {
      runtimeBlockError = .baselineRestoreFailed
      return false
    }
  }

  func snapshot(fan: Int, capabilities: HardwareCapabilities) throws -> FanSnapshot {
    guard let capability = capabilities.fans.first(where: { $0.index == fan }),
      let baseline = baselines[fan] ?? capability.minimumRPM,
      let maximum = capability.maximumRPM
    else {
      throw ControlError.keyMissing
    }
    return FanSnapshot(
      index: fan,
      actualRPM: try readRPM("F\(fan)Ac"),
      targetRPM: try readRPM("F\(fan)Tg"),
      minimumRPM: baseline,
      effectiveMinimumRPM: try readRPM("F\(fan)Mn"),
      maximumRPM: maximum,
      mode: try readMode(fan: fan, capabilities: capabilities)
    )
  }

  func setManual(
    fan: Int,
    rpm: Int,
    capabilities: HardwareCapabilities
  ) async throws -> FanSnapshot {
    if let runtimeBlockError { throw runtimeBlockError }
    let generation = transitionGeneration
    guard let capability = capabilities.fans.first(where: { $0.index == fan }),
      let baseline = baselines[fan] ?? capability.minimumRPM,
      let maximum = capability.maximumRPM,
      let minimumKey = capability.minimum,
      let targetKey = capability.target,
      let modeKey = capability.mode
    else {
      throw ControlError.keyMissing
    }
    _ = try RPMPolicy.validate(rpm, minimum: baseline, maximum: maximum)

    baselines[fan] = baseline
    manualFans.insert(fan)
    do {
      try persistRecovery(capabilities)
      try writeRPM(rpm, key: minimumKey)
      try await acquireManualMode(
        modeKey: modeKey.key,
        capabilities: capabilities,
        generation: generation
      )
      try requireCurrent(generation)
      try writeRPM(rpm, key: targetKey)

      for attempt in 0..<max(verificationAttempts, 1) {
        try requireCurrent(generation)
        let current = try snapshot(fan: fan, capabilities: capabilities)
        if current.effectiveMinimumRPM == rpm,
          current.targetRPM == rpm,
          current.mode == .manual,
          RPMPolicy.isVerified(actual: current.actualRPM, target: rpm)
        {
          return current
        }
        if attempt + 1 < verificationAttempts {
          try await sleep(.milliseconds(100))
          try requireCurrent(generation)
        }
      }
      throw ControlError.verificationFailed
    } catch {
      do {
        try restoreAll(capabilities)
      } catch {
        try blockAndRevoke(capabilities)
        throw ControlError.baselineRestoreFailed
      }
      throw map(error)
    }
  }

  func setAutomatic(fan: Int, capabilities: HardwareCapabilities) throws -> FanSnapshot {
    if let runtimeBlockError { throw runtimeBlockError }
    transitionGeneration &+= 1
    guard let baseline = baselines[fan] else {
      try writeMode(.automatic, fan: fan, capabilities: capabilities)
      return try snapshot(fan: fan, capabilities: capabilities)
    }
    do {
      try writeMode(.automatic, fan: fan, capabilities: capabilities)
      try writeRPM(baseline, key: requiredFan(fan, capabilities: capabilities).minimum)
      try verifyRestored(fan: fan, baseline: baseline, capabilities: capabilities)
      baselines.removeValue(forKey: fan)
      manualFans.remove(fan)
      if manualFans.isEmpty {
        try resetOwnedFtstIfNeeded()
      }
      try persistRecovery(capabilities)
      return try snapshot(fan: fan, capabilities: capabilities)
    } catch {
      try blockAndRevoke(capabilities)
      throw ControlError.baselineRestoreFailed
    }
  }

  func restoreAll(_ capabilities: HardwareCapabilities) throws {
    if let runtimeBlockError { throw runtimeBlockError }
    transitionGeneration &+= 1
    var firstError: Error?
    for fan in 0..<capabilities.fanCount {
      do {
        try writeMode(.automatic, fan: fan, capabilities: capabilities)
      } catch {
        firstError = firstError ?? error
      }
    }
    for (fan, baseline) in baselines.sorted(by: { $0.key < $1.key }) {
      do {
        try writeRPM(baseline, key: requiredFan(fan, capabilities: capabilities).minimum)
      } catch {
        firstError = firstError ?? error
      }
    }
    for (fan, baseline) in baselines.sorted(by: { $0.key < $1.key }) {
      do {
        try verifyRestored(fan: fan, baseline: baseline, capabilities: capabilities)
      } catch {
        firstError = firstError ?? error
      }
    }
    do {
      try resetOwnedFtstIfNeeded()
    } catch {
      firstError = firstError ?? error
    }
    if firstError != nil {
      try blockAndRevoke(capabilities)
      throw ControlError.baselineRestoreFailed
    }
    baselines.removeAll()
    manualFans.removeAll()
    try recoveryStore?.delete()
  }

  private func acquireManualMode(
    modeKey: String,
    capabilities: HardwareCapabilities,
    generation: UInt64
  ) async throws {
    try requireCurrent(generation)
    var needsFtstFallback = false
    do {
      try transport.writeKey(modeKey, bytes: [1])
    } catch let bridgeError as SMCBridgeError {
      guard case .firmwareRejected = bridgeError, capabilities.hasFtst else {
        throw bridgeError
      }
      needsFtstFallback = true
    }
    if !needsFtstFallback {
      try await sleep(.milliseconds(100))
      try requireCurrent(generation)
      needsFtstFallback = try transport.readKey(modeKey).bytes.first != 1
    }
    guard needsFtstFallback else { return }
    guard capabilities.hasFtst else { throw ControlError.firmwareRejected }
    try await unlockWithFtst(
      modeKey: modeKey,
      capabilities: capabilities,
      generation: generation
    )
  }

  private func unlockWithFtst(
    modeKey: String,
    capabilities: HardwareCapabilities,
    generation: UInt64
  ) async throws {
    try requireCurrent(generation)
    let previous = try transport.readKey("Ftst").bytes.first
    ownsFtst = previous != 1
    try persistRecovery(capabilities)
    try transport.writeKey("Ftst", bytes: [1])
    try await sleep(.milliseconds(500))
    try requireCurrent(generation)

    for attempt in 0..<max(unlockAttempts, 1) {
      try requireCurrent(generation)
      do {
        try transport.writeKey(modeKey, bytes: [1])
        return
      } catch {
        if attempt + 1 < unlockAttempts {
          try await sleep(.milliseconds(100))
          try requireCurrent(generation)
        }
      }
    }
    throw ControlError.unlockTimedOut
  }

  private func persistRecovery(_ capabilities: HardwareCapabilities) throws {
    guard let recoveryStore else { return }
    if baselines.isEmpty {
      try recoveryStore.delete()
      return
    }
    try recoveryStore.save(
      RecoveryState(
        model: capabilities.model,
        capabilityFingerprint: try capabilities.fingerprint(),
        fans: baselines.sorted(by: { $0.key < $1.key }).map {
          FanBaseline(index: $0.key, minimumRPM: $0.value)
        },
        acquiredFtst: ownsFtst,
        createdAt: Date()
      )
    )
  }

  private func verifyRestored(
    fan: Int,
    baseline: Int,
    capabilities: HardwareCapabilities
  ) throws {
    let mode = try readMode(fan: fan, capabilities: capabilities)
    guard mode == .automatic || mode == .system,
      try readRPM("F\(fan)Mn") == baseline
    else {
      throw ControlError.baselineRestoreFailed
    }
  }

  private func requiredFan(
    _ fan: Int,
    capabilities: HardwareCapabilities
  ) throws -> (minimum: SMCKeyCapability, mode: SMCKeyCapability) {
    guard let capability = capabilities.fans.first(where: { $0.index == fan }),
      let minimum = capability.minimum, let mode = capability.mode
    else {
      throw ControlError.keyMissing
    }
    return (minimum, mode)
  }

  private func writeMode(
    _ mode: FanMode,
    fan: Int,
    capabilities: HardwareCapabilities
  ) throws {
    let value: UInt8
    switch mode {
    case .automatic: value = 0
    case .manual: value = 1
    case .system: value = 3
    case .unknown: throw ControlError.firmwareRejected
    }
    try transport.writeKey(
      requiredFan(fan, capabilities: capabilities).mode.key,
      bytes: [value]
    )
  }

  private func writeRPM(_ rpm: Int, key: SMCKeyCapability) throws {
    try transport.writeKey(
      key.key,
      bytes: try SMCValueCodec.encodeRPM(Double(rpm), dataType: key.dataType)
    )
  }

  private func readRPM(_ key: String) throws -> Int {
    let value = try transport.readKey(key)
    return Int(try SMCValueCodec.decodeRPM(
      bytes: value.bytes,
      dataType: value.info.dataType
    ).rounded())
  }

  private func readMode(
    fan: Int,
    capabilities: HardwareCapabilities
  ) throws -> FanMode {
    guard let key = capabilities.fans.first(where: { $0.index == fan })?.mode?.key else {
      return .unknown
    }
    switch try transport.readKey(key).bytes.first {
    case 0: return .automatic
    case 1: return .manual
    case 3: return .system
    default: return .unknown
    }
  }

  private func resetOwnedFtstIfNeeded() throws {
    guard ownsFtst else { return }
    try transport.writeKey("Ftst", bytes: [0])
    guard try transport.readKey("Ftst").bytes.first == 0 else {
      throw ControlError.baselineRestoreFailed
    }
    ownsFtst = false
  }

  private func requireCurrent(_ generation: UInt64) throws {
    guard generation == transitionGeneration else {
      throw ControlError.verificationFailed
    }
  }

  private func blockAndRevoke(_ capabilities: HardwareCapabilities) throws {
    runtimeBlockError = .baselineRestoreFailed
    guard let approvalStore else { return }
    try approvalStore.revoke(
      model: capabilities.model,
      osBuild: capabilities.osBuild
    )
  }

  private func map(_ error: Error) -> ControlError {
    if let error = error as? ControlError { return error }
    guard let error = error as? SMCBridgeError else { return .firmwareRejected }
    switch error {
    case .keyMissing: return .keyMissing
    case .notPrivileged: return .notPrivileged
    case .firmwareRejected: return .firmwareRejected
    default: return .firmwareRejected
    }
  }
}
