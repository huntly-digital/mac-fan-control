import Foundation

public enum FanMode: String, Codable, CaseIterable, Sendable {
  case automatic
  case manual
  case system
  case unknown

  public var title: String {
    switch self {
    case .automatic: "Auto"
    case .manual: "Manual"
    case .system: "System"
    case .unknown: "Unknown"
    }
  }
}

public enum ControlStrategy: String, Codable, Sendable {
  case direct
  case directThenFtst
  case unsupported
}

public enum HardwareSupport: String, Codable, Sendable {
  case verified
  case experimental
  case unsupported
}

public struct HardwareProfile: Codable, Equatable, Sendable {
  public let model: String
  public let processor: String
  public let fanCount: Int
  public let hasFtst: Bool
  public let modeKeyFormat: String?
  public let strategy: ControlStrategy
  public let support: HardwareSupport

  public init(
    model: String,
    processor: String,
    fanCount: Int,
    hasFtst: Bool,
    modeKeyFormat: String?,
    strategy: ControlStrategy,
    support: HardwareSupport
  ) {
    self.model = model
    self.processor = processor
    self.fanCount = fanCount
    self.hasFtst = hasFtst
    self.modeKeyFormat = modeKeyFormat
    self.strategy = strategy
    self.support = support
  }
}

public struct FanSnapshot: Codable, Equatable, Identifiable, Sendable {
  public var id: Int { index }

  public let index: Int
  public let actualRPM: Int
  public let targetRPM: Int
  public let minimumRPM: Int
  public let maximumRPM: Int
  public let mode: FanMode

  public init(
    index: Int,
    actualRPM: Int,
    targetRPM: Int,
    minimumRPM: Int,
    maximumRPM: Int,
    mode: FanMode
  ) {
    self.index = index
    self.actualRPM = actualRPM
    self.targetRPM = targetRPM
    self.minimumRPM = minimumRPM
    self.maximumRPM = maximumRPM
    self.mode = mode
  }
}

public struct TemperatureSnapshot: Codable, Equatable, Sendable {
  public let cpuMaximumCelsius: Double
  public let gpuCelsius: Double?
  public let batteryCelsius: Double?
  public let primarySensorName: String

  public init(
    cpuMaximumCelsius: Double,
    gpuCelsius: Double? = nil,
    batteryCelsius: Double? = nil,
    primarySensorName: String
  ) {
    self.cpuMaximumCelsius = cpuMaximumCelsius
    self.gpuCelsius = gpuCelsius
    self.batteryCelsius = batteryCelsius
    self.primarySensorName = primarySensorName
  }
}

public enum ControlError: String, Codable, Error, Equatable, Sendable {
  case keyMissing
  case notPrivileged
  case firmwareRejected
  case unlockTimedOut
  case invalidRPM
  case verificationFailed
  case thermalEmergency
  case unsupportedHardware
  case unauthorizedPeer
  case malformedRequest
  case daemonUnavailable
}

extension ControlError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .keyMissing: "Required SMC key is missing"
    case .notPrivileged: "Root privileges are required"
    case .firmwareRejected: "The SMC firmware rejected the command"
    case .unlockTimedOut: "Timed out waiting for the documented Ftst unlock"
    case .invalidRPM: "RPM must be inside the reported minimum and maximum"
    case .verificationFailed: "The fan did not reach the requested RPM"
    case .thermalEmergency: "Manual control is disabled during thermal pressure"
    case .unsupportedHardware: "This hardware does not expose a supported fan mode key"
    case .unauthorizedPeer: "The socket peer UID is not allowed"
    case .malformedRequest: "The daemon request is malformed"
    case .daemonUnavailable: "The fan control daemon is not running"
    }
  }
}
