import Foundation

public enum SafetyState: Equatable, Sendable {
  case automatic
  case connected
  case manual
  case returningAutomatic
  case fault
}

public enum SafetyEvent: Equatable, Sendable {
  case clientConnected(at: Date)
  case manualActivated(at: Date)
  case heartbeat(at: Date)
  case timerFired(at: Date)
  case clientDisconnected
  case systemWillSleep
  case systemDidWake
  case thermalEmergency
  case shutdown
  case automaticRestored
  case automaticRestoreFailed
}

public enum SafetyAction: Equatable, Sendable {
  case none
  case setAllAutomatic
}

public struct SafetyStateMachine: Sendable {
  public private(set) var state: SafetyState = .automatic
  private let heartbeatTimeout: TimeInterval
  private var lastHeartbeat: Date?

  public init(heartbeatTimeout: TimeInterval = 5) {
    self.heartbeatTimeout = heartbeatTimeout
  }

  @discardableResult
  public mutating func handle(_ event: SafetyEvent) -> SafetyAction {
    switch event {
    case .clientConnected(let date):
      lastHeartbeat = date
      state = .connected
    case .manualActivated(let date), .heartbeat(let date):
      lastHeartbeat = date
      if case .manualActivated = event {
        state = .manual
      }
    case .timerFired(let date):
      guard state == .manual, let lastHeartbeat,
        date.timeIntervalSince(lastHeartbeat) > heartbeatTimeout
      else { return .none }
      state = .returningAutomatic
      return .setAllAutomatic
    case .clientDisconnected, .systemWillSleep, .thermalEmergency, .shutdown:
      guard state == .manual || state == .connected else {
        state = .automatic
        return .none
      }
      state = .returningAutomatic
      return .setAllAutomatic
    case .systemDidWake:
      state = .automatic
    case .automaticRestored:
      state = .automatic
    case .automaticRestoreFailed:
      state = .fault
    }
    return .none
  }
}
