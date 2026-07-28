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

  public func handle(_ request: FanRequest) async -> DaemonResult {
    do {
      switch request.command {
      case .hello, .status:
        let profile = try await controller.discoverHardware()
        let fans = try await controller.snapshot()
        let temperature = try? await controller.temperatureSnapshot()
        if request.command == .hello {
          safety.handle(.clientConnected(at: now()))
        }
        return success(request, hardware: profile, fans: fans, temperature: temperature)

      case .heartbeat:
        safety.handle(.heartbeat(at: now()))
        return success(request)

      case .setManual:
        guard let fan = request.fan, let rpm = request.rpm else {
          return failure(request, error: .malformedRequest)
        }
        guard !isThermalEmergency() else {
          return failure(request, error: .thermalEmergency)
        }
        _ = try await controller.setManual(fan: fan, rpm: rpm)
        safety.handle(.manualActivated(at: now()))
        return success(request, fans: try await controller.snapshot())

      case .setPreset:
        guard let percentage = request.percentage else {
          return failure(request, error: .malformedRequest)
        }
        guard !isThermalEmergency() else {
          return failure(request, error: .thermalEmergency)
        }

        let fans = try await controller.snapshot()
        do {
          for fan in fans {
            let target = try PresetPolicy.target(
              minimum: fan.minimumRPM,
              maximum: fan.maximumRPM,
              percentage: percentage
            )
            _ = try await controller.setManual(fan: fan.index, rpm: target)
          }
        } catch {
          try? await controller.setAllAutomatic()
          safety.handle(.automaticRestored)
          throw error
        }
        safety.handle(.manualActivated(at: now()))
        return success(request, fans: try await controller.snapshot())

      case .setAutomatic:
        guard let fan = request.fan else {
          return failure(request, error: .malformedRequest)
        }
        _ = try await controller.setAutomatic(fan: fan)
        return success(request, fans: try await controller.snapshot())

      case .setAllAutomatic:
        try await controller.setAllAutomatic()
        safety.handle(.automaticRestored)
        return success(request, fans: try await controller.snapshot())

      case .shutdown:
        try await controller.setAllAutomatic()
        safety.handle(.automaticRestored)
        return DaemonResult(response: success(request).response, shouldShutdown: true)
      }
    } catch let controlError as ControlError {
      return failure(request, error: controlError)
    } catch {
      return failure(request, error: .firmwareRejected, message: error.localizedDescription)
    }
  }

  public func tick(at date: Date = Date()) async {
    await perform(safety.handle(.timerFired(at: date)))
  }

  public func handleDisconnect() async {
    await perform(safety.handle(.clientDisconnected))
  }

  public func handleSystemWillSleep() async {
    await perform(safety.handle(.systemWillSleep), forceRestore: true)
  }

  public func handleSystemDidWake() {
    safety.handle(.systemDidWake)
  }

  public func handleThermalEmergency() async {
    await perform(safety.handle(.thermalEmergency), forceRestore: true)
  }

  public func restoreForShutdown() async {
    await perform(safety.handle(.shutdown), forceRestore: true)
  }

  private func perform(_ action: SafetyAction, forceRestore: Bool = false) async {
    guard action == .setAllAutomatic || forceRestore else { return }
    do {
      try await controller.setAllAutomatic()
      safety.handle(.automaticRestored)
    } catch {
      safety.handle(.automaticRestoreFailed)
    }
  }

  private func success(
    _ request: FanRequest,
    hardware: HardwareProfile? = nil,
    fans: [FanSnapshot]? = nil,
    temperature: TemperatureSnapshot? = nil
  ) -> DaemonResult {
    DaemonResult(
      response: FanResponse(
        id: request.id,
        ok: true,
        hardware: hardware,
        fans: fans,
        temperature: temperature
      )
    )
  }

  private func failure(
    _ request: FanRequest,
    error: ControlError,
    message: String? = nil
  ) -> DaemonResult {
    DaemonResult(
      response: FanResponse(
        id: request.id,
        ok: false,
        error: error,
        message: message ?? error.localizedDescription
      )
    )
  }
}
