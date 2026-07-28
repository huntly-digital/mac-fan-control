import CryptoKit
import Darwin
import FanProtocol
import Foundation

public struct SMCKeyCapability: Codable, Equatable, Sendable {
  public let key: String
  public let dataType: String
  public let dataSize: UInt32

  public init(key: String, dataType: String, dataSize: UInt32) {
    self.key = key
    self.dataType = dataType
    self.dataSize = dataSize
  }
}

public struct FanCapability: Codable, Equatable, Sendable {
  public let index: Int
  public let actual: SMCKeyCapability?
  public let target: SMCKeyCapability?
  public let minimum: SMCKeyCapability?
  public let maximum: SMCKeyCapability?
  public let mode: SMCKeyCapability?
  public let minimumRPM: Int?
  public let maximumRPM: Int?

  public init(
    index: Int,
    actual: SMCKeyCapability?,
    target: SMCKeyCapability?,
    minimum: SMCKeyCapability?,
    maximum: SMCKeyCapability?,
    mode: SMCKeyCapability?,
    minimumRPM: Int?,
    maximumRPM: Int?
  ) {
    self.index = index
    self.actual = actual
    self.target = target
    self.minimum = minimum
    self.maximum = maximum
    self.mode = mode
    self.minimumRPM = minimumRPM
    self.maximumRPM = maximumRPM
  }
}

public struct HardwareCapabilities: Codable, Equatable, Sendable {
  public let model: String
  public let processor: String
  public let osBuild: String
  public let fanCount: Int
  public let hasFtst: Bool
  public let ftst: SMCKeyCapability?
  public let modeKeyFormat: String?
  public let strategy: ControlStrategy
  public let fans: [FanCapability]

  public init(
    model: String,
    processor: String,
    osBuild: String,
    fanCount: Int,
    hasFtst: Bool,
    ftst: SMCKeyCapability?,
    modeKeyFormat: String?,
    strategy: ControlStrategy,
    fans: [FanCapability]
  ) {
    self.model = model
    self.processor = processor
    self.osBuild = osBuild
    self.fanCount = fanCount
    self.hasFtst = hasFtst
    self.ftst = ftst
    self.modeKeyFormat = modeKeyFormat
    self.strategy = strategy
    self.fans = fans
  }

  public var writeEligibility: WriteEligibility {
    guard Self.isSupportedAppleSilicon(model: model, processor: processor),
      fanCount > 0, fanCount <= 8, fans.count == fanCount, modeKeyFormat != nil,
      strategy != .unsupported
    else {
      return .unsupported
    }
    let sorted = fans.sorted { $0.index < $1.index }
    guard sorted.map(\.index) == Array(0..<fanCount) else { return .unsupported }
    guard sorted.allSatisfy(Self.isConsistentFan) else { return .unsupported }
    if hasFtst {
      guard let ftst, Self.isByteKey(ftst) else { return .unsupported }
    }
    return .validationRequired
  }

  public func fingerprint(minimumOverrides: [Int: Int] = [:]) throws -> String {
    let fanLines = fans.sorted { $0.index < $1.index }.map { fan in
      [
        String(fan.index),
        Self.describe(fan.actual),
        Self.describe(fan.target),
        Self.describe(fan.minimum),
        Self.describe(fan.maximum),
        Self.describe(fan.mode),
        (minimumOverrides[fan.index] ?? fan.minimumRPM).map(String.init) ?? "nil",
        fan.maximumRPM.map(String.init) ?? "nil",
      ].joined(separator: "|")
    }
    let canonical = (
      [
        "schema=1",
        "model=\(model)",
        "fanCount=\(fanCount)",
        "mode=\(modeKeyFormat ?? "nil")",
        "strategy=\(strategy.rawValue)",
        "ftst=\(Self.describe(ftst))",
      ] + fanLines
    ).joined(separator: "\n")
    let digest = SHA256.hash(data: Data(canonical.utf8))
    return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
  }

  public func profile(approved: Bool) throws -> HardwareProfile {
    let shape = writeEligibility
    let eligibility: WriteEligibility
    if shape == .unsupported {
      eligibility = .unsupported
    } else {
      eligibility = approved ? .approved : .validationRequired
    }
    return HardwareProfile(
      model: model,
      processor: processor,
      fanCount: fanCount,
      hasFtst: hasFtst,
      modeKeyFormat: modeKeyFormat,
      strategy: strategy,
      support: shape == .unsupported ? .unsupported : .experimental,
      writeEligibility: eligibility,
      capabilityFingerprint: try fingerprint()
    )
  }

  public func profile(writeEligibility: WriteEligibility) throws -> HardwareProfile {
    HardwareProfile(
      model: model,
      processor: processor,
      fanCount: fanCount,
      hasFtst: hasFtst,
      modeKeyFormat: modeKeyFormat,
      strategy: strategy,
      support: self.writeEligibility == .unsupported ? .unsupported : .experimental,
      writeEligibility: writeEligibility,
      capabilityFingerprint: try fingerprint()
    )
  }

  private static func isConsistentFan(_ fan: FanCapability) -> Bool {
    guard let actual = fan.actual, let target = fan.target, let minimum = fan.minimum,
      let maximum = fan.maximum, let mode = fan.mode,
      let minimumRPM = fan.minimumRPM, let maximumRPM = fan.maximumRPM
    else {
      return false
    }
    guard [actual, target, minimum, maximum].allSatisfy(isRPMKey),
      isByteKey(mode), minimumRPM > 0, maximumRPM >= minimumRPM
    else {
      return false
    }
    let prefix = "F\(fan.index)"
    return [actual, target, minimum, maximum, mode].allSatisfy { $0.key.hasPrefix(prefix) }
  }

  private static func isSupportedAppleSilicon(model: String, processor: String) -> Bool {
    guard processor.localizedCaseInsensitiveContains("Apple") else { return false }
    if model.hasPrefix("MacBookPro18") || model.hasPrefix("MacBookAir10") {
      return true
    }
    guard model.hasPrefix("Mac") else { return false }
    let family = model.dropFirst(3).prefix { $0.isNumber }
    guard let number = Int(family) else { return false }
    return (12...17).contains(number)
  }

  private static func isRPMKey(_ key: SMCKeyCapability) -> Bool {
    switch key.dataType {
    case "flt ": key.dataSize == 4
    case "fpe2": key.dataSize == 2
    default: false
    }
  }

  private static func isByteKey(_ key: SMCKeyCapability) -> Bool {
    key.dataType == "ui8 " && key.dataSize == 1
  }

  private static func describe(_ key: SMCKeyCapability?) -> String {
    guard let key else { return "nil" }
    return "\(key.key):\(key.dataType):\(key.dataSize)"
  }
}

public struct HardwareApproval: Codable, Equatable, Sendable {
  public let model: String
  public let osBuild: String
  public let capabilityFingerprint: String
  public let validatedAt: Date

  public init(
    model: String,
    osBuild: String,
    capabilityFingerprint: String,
    validatedAt: Date
  ) {
    self.model = model
    self.osBuild = osBuild
    self.capabilityFingerprint = capabilityFingerprint
    self.validatedAt = validatedAt
  }
}

private struct HardwareApprovalFile: Codable {
  let schemaVersion: Int
  var approvals: [HardwareApproval]
}

public struct HardwareApprovalStore: Sendable {
  public static let defaultURL = URL(
    fileURLWithPath: "/Library/Application Support/MFanControl/hardware-approvals.json"
  )

  public let url: URL

  public init(url: URL = Self.defaultURL) {
    self.url = url
  }

  public func isApproved(model: String, osBuild: String, fingerprint: String) throws -> Bool {
    try load().contains {
      $0.model == model && $0.osBuild == osBuild && $0.capabilityFingerprint == fingerprint
    }
  }

  public func approve(_ approval: HardwareApproval) throws {
    var approvals = try load().filter {
      !($0.model == approval.model && $0.osBuild == approval.osBuild)
    }
    approvals.append(approval)
    try AtomicPrivateJSON.write(
      HardwareApprovalFile(schemaVersion: 1, approvals: approvals),
      to: url
    )
  }

  public func revoke(model: String, osBuild: String, fingerprint: String) throws {
    let approvals = try load().filter {
      !($0.model == model && $0.osBuild == osBuild
        && $0.capabilityFingerprint == fingerprint)
    }
    try AtomicPrivateJSON.write(
      HardwareApprovalFile(schemaVersion: 1, approvals: approvals),
      to: url
    )
  }

  public func revoke(model: String, osBuild: String) throws {
    let approvals = try load().filter {
      !($0.model == model && $0.osBuild == osBuild)
    }
    try AtomicPrivateJSON.write(
      HardwareApprovalFile(schemaVersion: 1, approvals: approvals),
      to: url
    )
  }

  private func load() throws -> [HardwareApproval] {
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let file = try decoder.decode(
      HardwareApprovalFile.self,
      from: Data(contentsOf: url)
    )
    guard file.schemaVersion == 1 else { throw ControlError.capabilityMismatch }
    return file.approvals
  }
}

public struct FanBaseline: Codable, Equatable, Sendable {
  public let index: Int
  public let minimumRPM: Int

  public init(index: Int, minimumRPM: Int) {
    self.index = index
    self.minimumRPM = minimumRPM
  }
}

public struct RecoveryState: Codable, Equatable, Sendable {
  public let model: String
  public let capabilityFingerprint: String
  public let fans: [FanBaseline]
  public let acquiredFtst: Bool
  public let createdAt: Date

  public init(
    model: String,
    capabilityFingerprint: String,
    fans: [FanBaseline],
    acquiredFtst: Bool,
    createdAt: Date
  ) {
    self.model = model
    self.capabilityFingerprint = capabilityFingerprint
    self.fans = fans
    self.acquiredFtst = acquiredFtst
    self.createdAt = createdAt
  }
}

public struct RecoveryStateStore: Sendable {
  public static let defaultURL = URL(
    fileURLWithPath: "/Library/Application Support/MFanControl/recovery-state.json"
  )

  public let url: URL

  public init(url: URL = Self.defaultURL) {
    self.url = url
  }

  public func load() throws -> RecoveryState? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(RecoveryState.self, from: Data(contentsOf: url))
  }

  public func save(_ state: RecoveryState) throws {
    try AtomicPrivateJSON.write(state, to: url)
  }

  public func delete() throws {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    try FileManager.default.removeItem(at: url)
  }
}

private enum AtomicPrivateJSON {
  static func write<Value: Encodable>(_ value: Value, to url: URL) throws {
    let manager = FileManager.default
    let directory = url.deletingLastPathComponent()
    try manager.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
    let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }

    var writeError: Error?
    data.withUnsafeBytes { rawBuffer in
      guard let base = rawBuffer.baseAddress else { return }
      var written = 0
      while written < rawBuffer.count {
        let count = Darwin.write(descriptor, base.advanced(by: written), rawBuffer.count - written)
        if count <= 0 {
          writeError = CocoaError(.fileWriteUnknown)
          return
        }
        written += count
      }
    }
    if fsync(descriptor) != 0, writeError == nil {
      writeError = CocoaError(.fileWriteUnknown)
    }
    close(descriptor)
    if let writeError {
      try? manager.removeItem(at: temporary)
      throw writeError
    }
    guard rename(temporary.path, url.path) == 0 else {
      try? manager.removeItem(at: temporary)
      throw CocoaError(.fileWriteUnknown)
    }
    guard chmod(url.path, S_IRUSR | S_IWUSR) == 0 else {
      throw CocoaError(.fileWriteNoPermission)
    }
    let directoryDescriptor = open(directory.path, O_RDONLY)
    if directoryDescriptor >= 0 {
      _ = fsync(directoryDescriptor)
      close(directoryDescriptor)
    }
  }
}
