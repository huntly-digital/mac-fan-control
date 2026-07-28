import Foundation

public enum FanCommand: String, Codable, Sendable {
  case hello
  case status
  case setManual
  case setPreset
  case setAutomatic
  case setAllAutomatic
  case heartbeat
  case shutdown
}

public struct FanRequest: Codable, Equatable, Sendable {
  public let id: String
  public let command: FanCommand
  public let fan: Int?
  public let rpm: Int?
  public let percentage: Int?

  public init(
    id: String = UUID().uuidString,
    command: FanCommand,
    fan: Int? = nil,
    rpm: Int? = nil,
    percentage: Int? = nil
  ) {
    self.id = id
    self.command = command
    self.fan = fan
    self.rpm = rpm
    self.percentage = percentage
  }
}

public struct FanResponse: Codable, Equatable, Sendable {
  public let id: String
  public let ok: Bool
  public let error: ControlError?
  public let message: String?
  public let hardware: HardwareProfile?
  public let fans: [FanSnapshot]?
  public let temperature: TemperatureSnapshot?

  public init(
    id: String,
    ok: Bool,
    error: ControlError? = nil,
    message: String? = nil,
    hardware: HardwareProfile? = nil,
    fans: [FanSnapshot]? = nil,
    temperature: TemperatureSnapshot? = nil
  ) {
    self.id = id
    self.ok = ok
    self.error = error
    self.message = message
    self.hardware = hardware
    self.fans = fans
    self.temperature = temperature
  }
}
