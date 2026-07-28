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

public enum WriteEligibility: String, Codable, Sendable {
  case unsupported
  case validationRequired
  case approved
  case blocked
}

public struct HardwareProfile: Codable, Equatable, Sendable {
  public let model: String
  public let processor: String
  public let fanCount: Int
  public let hasFtst: Bool
  public let modeKeyFormat: String?
  public let strategy: ControlStrategy
  public let support: HardwareSupport
  public let writeEligibility: WriteEligibility
  public let capabilityFingerprint: String

  public init(
    model: String,
    processor: String,
    fanCount: Int,
    hasFtst: Bool,
    modeKeyFormat: String?,
    strategy: ControlStrategy,
    support: HardwareSupport,
    writeEligibility: WriteEligibility = .validationRequired,
    capabilityFingerprint: String = ""
  ) {
    self.model = model
    self.processor = processor
    self.fanCount = fanCount
    self.hasFtst = hasFtst
    self.modeKeyFormat = modeKeyFormat
    self.strategy = strategy
    self.support = support
    self.writeEligibility = writeEligibility
    self.capabilityFingerprint = capabilityFingerprint
  }
}

public struct FanSnapshot: Codable, Equatable, Identifiable, Sendable {
  public var id: Int { index }

  public let index: Int
  public let actualRPM: Int
  public let targetRPM: Int
  public let minimumRPM: Int
  public let effectiveMinimumRPM: Int
  public let maximumRPM: Int
  public let mode: FanMode

  public init(
    index: Int,
    actualRPM: Int,
    targetRPM: Int,
    minimumRPM: Int,
    effectiveMinimumRPM: Int? = nil,
    maximumRPM: Int,
    mode: FanMode
  ) {
    self.index = index
    self.actualRPM = actualRPM
    self.targetRPM = targetRPM
    self.minimumRPM = minimumRPM
    self.effectiveMinimumRPM = effectiveMinimumRPM ?? minimumRPM
    self.maximumRPM = maximumRPM
    self.mode = mode
  }
}

public enum TemperatureGroup: String, Codable, CaseIterable, Sendable {
  case cpu
  case gpu
  case battery
  case memory
  case other
}

public enum TemperatureRole: String, Codable, CaseIterable, Sendable {
  case individual
  case average
  case hotspot
}

public struct TemperatureReading: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let label: String
  public let group: TemperatureGroup
  public let role: TemperatureRole
  public let celsius: Double
  public let sampleCount: Int
  public let sourceKeys: [String]

  public init(
    id: String,
    label: String,
    group: TemperatureGroup,
    role: TemperatureRole,
    celsius: Double,
    sampleCount: Int,
    sourceKeys: [String]
  ) {
    self.id = id
    self.label = label
    self.group = group
    self.role = role
    self.celsius = celsius
    self.sampleCount = sampleCount
    self.sourceKeys = sourceKeys
  }
}

public struct TemperatureSnapshot: Codable, Equatable, Sendable {
  public let readings: [TemperatureReading]

  public init(readings: [TemperatureReading]) {
    self.readings = readings
  }

  public func primaryReading(selectedID: String? = nil) -> TemperatureReading? {
    if let selectedID, let selected = readings.first(where: { $0.id == selectedID }) {
      return selected
    }
    return readings.first(where: { $0.id == "cpu.hotspot" })
      ?? readings.first(where: { $0.id == "cpu.average" })
      ?? readings.first(where: { $0.group == .cpu })
  }

  public var cpuMaximumCelsius: Double {
    primaryReading(selectedID: "cpu.hotspot")?.celsius ?? 0
  }

  public var gpuCelsius: Double? {
    readings.first(where: { $0.id == "gpu.hotspot" })?.celsius
      ?? readings.first(where: { $0.group == .gpu })?.celsius
  }

  public var batteryCelsius: Double? {
    readings.first(where: { $0.group == .battery })?.celsius
  }

  public var primarySensorName: String {
    primaryReading()?.label ?? "CPU Hotspot"
  }

  public init(
    cpuMaximumCelsius: Double,
    gpuCelsius: Double? = nil,
    batteryCelsius: Double? = nil,
    primarySensorName: String
  ) {
    var readings = [
      TemperatureReading(
        id: "cpu.hotspot",
        label: primarySensorName,
        group: .cpu,
        role: .hotspot,
        celsius: cpuMaximumCelsius,
        sampleCount: 1,
        sourceKeys: []
      )
    ]
    if let gpuCelsius {
      readings.append(
        TemperatureReading(
          id: "gpu.hotspot",
          label: "GPU Hotspot",
          group: .gpu,
          role: .hotspot,
          celsius: gpuCelsius,
          sampleCount: 1,
          sourceKeys: []
        )
      )
    }
    if let batteryCelsius {
      readings.append(
        TemperatureReading(
          id: "battery.temperature",
          label: "Battery",
          group: .battery,
          role: .individual,
          celsius: batteryCelsius,
          sampleCount: 1,
          sourceKeys: []
        )
      )
    }
    self.readings = readings
  }
}

public enum HardwareValidationStatus: String, Codable, Sendable {
  case idle
  case running
  case passed
  case failed
}

public struct HardwareValidationReport: Codable, Equatable, Sendable {
  public let status: HardwareValidationStatus
  public let completedFans: Int
  public let totalFans: Int
  public let message: String

  public init(
    status: HardwareValidationStatus,
    completedFans: Int,
    totalFans: Int,
    message: String
  ) {
    self.status = status
    self.completedFans = completedFans
    self.totalFans = totalFans
    self.message = message
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
  case hardwareValidationRequired
  case controllerBusy
  case capabilityMismatch
  case baselineRestoreFailed
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
    case .hardwareValidationRequired:
      "Hardware validation is required before fan control can be enabled"
    case .controllerBusy:
      "Another MFanControl instance owns the fan controller"
    case .capabilityMismatch:
      "The detected hardware capability no longer matches the approved profile"
    case .baselineRestoreFailed:
      "The captured hardware fan minimum could not be restored"
    }
  }
}
