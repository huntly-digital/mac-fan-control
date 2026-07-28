import FanCore
import FanProtocol
import Foundation

public struct DaemonResult: Equatable, Sendable {
  public let response: FanResponse
  public let shouldShutdown: Bool

  public init(response: FanResponse, shouldShutdown: Bool = false) {
    self.response = response
    self.shouldShutdown = shouldShutdown
  }
}

public actor RequestProcessor {
  private let controller: any FanControlling
  private let now: @Sendable () -> Date
  private let isThermalEmergency: @Sendable () -> Bool
  private var safety = SafetyStateMachine()
  private var ownerSession: UUID?
  private var powerReapplyUsed = false
  private var intendedTargets: [Int: Int] = [:]
  private var writeInFlight = false
  private var safetyRestoreInProgress = false
  private var powerReapplyInProgress = false

  public init(
    controller: any FanControlling,
    now: @escaping @Sendable () -> Date = Date.init,
    isThermalEmergency: @escaping @Sendable () -> Bool = {
      switch ProcessInfo.processInfo.thermalState {
      case .serious, .critical: true
      default: false
      }
    }
  ) {
    self.controller = controller
    self.now = now
    self.isThermalEmergency = isThermalEmergency
  }

  public func handle(_ request: FanRequest, sessionID: UUID? = nil) async -> DaemonResult {
    do {
      let ownerCommand = isOwnerCommand(request.command)
      if ownerCommand, safetyRestoreInProgress {
        return failure(request, error: .controllerBusy, sessionID: sessionID)
      }
      if let sessionID, ownerCommand, ownerSession != sessionID {
        return failure(request, error: .controllerBusy, sessionID: sessionID)
      }
      if ownerCommand, writeInFlight {
        return failure(request, error: .controllerBusy, sessionID: sessionID)
      }
      if ownerCommand { writeInFlight = true }
      defer {
        if ownerCommand { writeInFlight = false }
      }
      switch request.command {
      case .hello, .status:
        let profile = try await controller.discoverHardware()
        let fans = try await controller.snapshot()
        let temperature = try? await controller.temperatureSnapshot()
        if request.command == .hello {
          let acquiredLease: Bool
          if let sessionID, ownerSession == nil {
            ownerSession = sessionID
            acquiredLease = true
          } else {
            acquiredLease = sessionID == nil && safety.state == .automatic
          }
          if acquiredLease {
            safety.handle(.clientConnected(at: now()))
          }
        }
        return success(
          request,
          hardware: profile,
          fans: fans,
          temperature: temperature,
          sessionID: sessionID
        )

      case .heartbeat:
        if sessionID == nil || ownerSession == sessionID {
          safety.handle(.heartbeat(at: now()))
        }
        return success(request, sessionID: sessionID)

      case .setManual:
        guard let fan = request.fan, let rpm = request.rpm else {
          return failure(request, error: .malformedRequest)
        }
        guard !isThermalEmergency() else {
          return failure(request, error: .thermalEmergency)
        }
        _ = try await controller.setManual(fan: fan, rpm: rpm)
        safety.handle(.manualActivated(at: now()))
        intendedTargets[fan] = rpm
        powerReapplyUsed = false
        return success(request, fans: try await controller.snapshot(), sessionID: sessionID)

      case .setPreset:
        guard let percentage = request.percentage else {
          return failure(request, error: .malformedRequest)
        }
        guard !isThermalEmergency() else {
          return failure(request, error: .thermalEmergency)
        }

        let fans = try await controller.snapshot()
        var targets: [Int: Int] = [:]
        do {
          for fan in fans {
            let target = try PresetPolicy.target(
              minimum: fan.minimumRPM,
              maximum: fan.maximumRPM,
              percentage: percentage
            )
            _ = try await controller.setManual(fan: fan.index, rpm: target)
            targets[fan.index] = target
          }
        } catch {
          try? await controller.setAllAutomatic()
          safety.handle(.automaticRestored)
          intendedTargets.removeAll()
          throw error
        }
        safety.handle(.manualActivated(at: now()))
        intendedTargets = targets
        powerReapplyUsed = false
        return success(request, fans: try await controller.snapshot(), sessionID: sessionID)

      case .setAutomatic:
        guard let fan = request.fan else {
          return failure(request, error: .malformedRequest)
        }
        _ = try await controller.setAutomatic(fan: fan)
        intendedTargets.removeValue(forKey: fan)
        if intendedTargets.isEmpty {
          safety.handle(.automaticRestored)
          powerReapplyUsed = false
        }
        return success(request, fans: try await controller.snapshot(), sessionID: sessionID)

      case .setAllAutomatic:
        try await controller.setAllAutomatic()
        safety.handle(.automaticRestored)
        intendedTargets.removeAll()
        powerReapplyUsed = false
        return success(request, fans: try await controller.snapshot(), sessionID: sessionID)

      case .shutdown:
        await performSafetyRestore(safety.handle(.shutdown), forceRestore: true)
        return DaemonResult(
          response: success(request, sessionID: sessionID).response,
          shouldShutdown: true
        )

      case .validateHardware:
        guard request.validationConfirmed else {
          return failure(request, error: .malformedRequest)
        }
        guard !isThermalEmergency() else {
          return failure(request, error: .thermalEmergency)
        }
        let validation = try await controller.validateHardware()
        return success(request, validation: validation, sessionID: sessionID)
      }
    } catch let controlError as ControlError {
      if request.command == .setManual || request.command == .setPreset {
        intendedTargets.removeAll()
      }
      return failure(request, error: controlError, sessionID: sessionID)
    } catch {
      if request.command == .setManual || request.command == .setPreset {
        intendedTargets.removeAll()
      }
      return failure(
        request,
        error: .firmwareRejected,
        message: error.localizedDescription,
        sessionID: sessionID
      )
    }
  }

  public func tick(at date: Date = Date()) async {
    let action = safety.handle(.timerFired(at: date))
    if action == .setAllAutomatic {
      await performSafetyRestore(action)
    }
  }

  public func handleDisconnect(sessionID: UUID? = nil) async {
    if let sessionID, ownerSession != sessionID { return }
    let action = safety.handle(.clientDisconnected)
    revokeControlLease()
    if action == .setAllAutomatic {
      await performSafetyRestore(action)
    }
  }

  public func handleSystemWillSleep() async {
    await performSafetyRestore(safety.handle(.systemWillSleep), forceRestore: true)
  }

  public func handleSystemDidWake() {
    safety.handle(.systemDidWake)
  }

  public func handleThermalEmergency() async {
    await performSafetyRestore(safety.handle(.thermalEmergency), forceRestore: true)
  }

  public func restoreForShutdown() async {
    await performSafetyRestore(safety.handle(.shutdown), forceRestore: true)
  }

  public func handlePowerSourceChanged() async {
    guard let powerOwner = ownerSession, safety.state == .manual,
      !safetyRestoreInProgress
    else { return }
    if powerReapplyInProgress {
      await performSafetyRestore(.setAllAutomatic, forceRestore: true)
      return
    }
    guard !writeInFlight else { return }
    writeInFlight = true
    powerReapplyInProgress = true
    defer {
      powerReapplyInProgress = false
      writeInFlight = false
    }
    guard safety.isHeartbeatHealthy(at: now()) else {
      await performSafetyRestore(.setAllAutomatic, forceRestore: true)
      return
    }
    guard !powerReapplyUsed else {
      await performSafetyRestore(.setAllAutomatic, forceRestore: true)
      return
    }
    powerReapplyUsed = true
    do {
      guard !intendedTargets.isEmpty else {
        throw ControlError.verificationFailed
      }
      for (fan, rpm) in intendedTargets.sorted(by: { $0.key < $1.key }) {
        guard ownerSession == powerOwner, !safetyRestoreInProgress else {
          throw ControlError.controllerBusy
        }
        _ = try await controller.setManual(fan: fan, rpm: rpm)
        guard ownerSession == powerOwner, !safetyRestoreInProgress else {
          throw ControlError.controllerBusy
        }
      }
    } catch {
      if ownerSession != nil {
        await performSafetyRestore(.setAllAutomatic, forceRestore: true)
      }
    }
  }

  private func performSafetyRestore(
    _ action: SafetyAction,
    forceRestore: Bool = false
  ) async {
    guard action == .setAllAutomatic || forceRestore else { return }
    revokeControlLease()
    guard !safetyRestoreInProgress else { return }
    safetyRestoreInProgress = true
    do {
      try await controller.setAllAutomatic()
      safety.handle(.automaticRestored)
      safetyRestoreInProgress = false
    } catch {
      safety.handle(.automaticRestoreFailed)
    }
  }

  private func revokeControlLease() {
    ownerSession = nil
    powerReapplyUsed = false
    intendedTargets.removeAll()
  }

  private func success(
    _ request: FanRequest,
    hardware: HardwareProfile? = nil,
    fans: [FanSnapshot]? = nil,
    temperature: TemperatureSnapshot? = nil,
    validation: HardwareValidationReport? = nil,
    sessionID: UUID? = nil
  ) -> DaemonResult {
    DaemonResult(
      response: FanResponse(
        id: request.id,
        ok: true,
        hardware: hardware,
        fans: fans,
        temperature: temperature,
        validation: validation,
        controlAccess: access(for: sessionID)
      )
    )
  }

  private func failure(
    _ request: FanRequest,
    error: ControlError,
    message: String? = nil,
    sessionID: UUID? = nil
  ) -> DaemonResult {
    DaemonResult(
      response: FanResponse(
        id: request.id,
        ok: false,
        error: error,
        message: message ?? error.localizedDescription,
        controlAccess: access(for: sessionID)
      )
    )
  }

  private func access(for sessionID: UUID?) -> ControlAccess? {
    guard let sessionID else { return nil }
    return ownerSession == sessionID ? .owner : .observer
  }

  private func isOwnerCommand(_ command: FanCommand) -> Bool {
    switch command {
    case .setManual, .setPreset, .setAutomatic, .setAllAutomatic, .shutdown,
      .validateHardware:
      return true
    case .hello, .status, .heartbeat:
      return false
    }
  }
}
