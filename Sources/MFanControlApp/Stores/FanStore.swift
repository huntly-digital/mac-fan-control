import Combine
import FanProtocol
import Foundation
import HelperManagement

@MainActor
final class FanStore: ObservableObject {
  @Published private(set) var status: DaemonStatus = .notRunning
  @Published private(set) var hardware: HardwareProfile?
  @Published private(set) var fans: [FanSnapshot] = []
  @Published private(set) var temperature: TemperatureSnapshot?
  @Published private(set) var validation: HardwareValidationReport?
  @Published private(set) var controlAccess: ControlAccess?
  @Published private(set) var activePreset: FanPreset = .automatic
  @Published private(set) var isApplying = false
  @Published private(set) var errorMessage: String?
  @Published var selectedRPM: [Int: Double] = [:]
  @Published var primaryTemperatureID: String {
    didSet {
      UserDefaults.standard.set(primaryTemperatureID, forKey: "primaryTemperatureID")
    }
  }

  private let client = HelperFanClient()
  private var refreshTask: Task<Void, Never>?
  private var heartbeatTask: Task<Void, Never>?
  private var connected = false
  private var activePresetPercentage: Int?

  init() {
    primaryTemperatureID =
      UserDefaults.standard.string(forKey: "primaryTemperatureID") ?? "cpu.hotspot"
    start()
  }

  deinit {
    refreshTask?.cancel()
    heartbeatTask?.cancel()
  }

  var menuTitle: String {
    guard let primaryTemperature, connected else { return "MFan" }
    return "\(Int(primaryTemperature.celsius.rounded()))°C"
  }

  var isConnected: Bool {
    connected
  }

  var hasControl: Bool {
    controlAccess != .observer
  }

  var primaryTemperature: TemperatureReading? {
    TemperaturePreference.primary(
      in: temperature,
      selectedID: primaryTemperatureID
    )
  }

  func apply(fan: Int) {
    guard hasControl else {
      errorMessage = ControlError.controllerBusy.localizedDescription
      return
    }
    guard let rpm = selectedRPM[fan] else { return }
    Task {
      isApplying = true
      defer { isApplying = false }
      if await send(
        .init(command: .setManual, fan: fan, rpm: Int(rpm.rounded())),
        clearErrorOnSuccess: true
      ) {
        activePreset = .manual
        activePresetPercentage = nil
      }
    }
  }

  func automatic(fan: Int) {
    guard hasControl else {
      errorMessage = ControlError.controllerBusy.localizedDescription
      return
    }
    Task {
      isApplying = true
      defer { isApplying = false }
      if await send(.init(command: .setAutomatic, fan: fan), clearErrorOnSuccess: true),
        fans.allSatisfy({ $0.mode == .automatic })
      {
        activePreset = .automatic
        activePresetPercentage = nil
      }
    }
  }

  func allAutomatic() {
    applyPreset(.automatic, percentage: nil)
  }

  func applyPreset(_ preset: FanPreset, percentage: Int?) {
    guard preset != .manual else { return }
    guard hasControl else {
      errorMessage = ControlError.controllerBusy.localizedDescription
      return
    }
    Task {
      isApplying = true
      defer { isApplying = false }

      let request: FanRequest
      if preset == .automatic {
        request = .init(command: .setAllAutomatic)
      } else {
        guard let percentage else { return }
        request = .init(command: .setPreset, percentage: percentage)
      }

      if await send(request, clearErrorOnSuccess: true) {
        activePreset = preset
        activePresetPercentage = percentage
      }
    }
  }

  func validateHardware() {
    guard hasControl else {
      errorMessage = ControlError.controllerBusy.localizedDescription
      return
    }
    Task {
      isApplying = true
      defer { isApplying = false }
      validation = HardwareValidationReport(
        status: .running,
        completedFans: 0,
        totalFans: hardware?.fanCount ?? 0,
        message: "Testing each fan and restoring Auto…"
      )
      let succeeded = await send(
        .init(command: .validateHardware, validationConfirmed: true),
        clearErrorOnSuccess: true
      )
      if !succeeded {
        validation = HardwareValidationReport(
          status: .failed,
          completedFans: 0,
          totalFans: hardware?.fanCount ?? 0,
          message: errorMessage ?? "Hardware validation failed."
        )
      }
    }
  }

  private func start() {
    refreshTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        await self.refresh()
        try? await Task.sleep(for: .seconds(1))
      }
    }
    heartbeatTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(2))
        guard let self, self.connected else { continue }
        _ = await self.send(.init(command: .heartbeat), updateVisibleState: false)
      }
    }
  }

  private func refresh() async {
    let command: FanCommand = connected ? .status : .hello
    _ = await send(.init(command: command))
  }

  @discardableResult
  private func send(
    _ request: FanRequest,
    updateVisibleState: Bool = true,
    clearErrorOnSuccess: Bool = false
  ) async -> Bool {
    do {
      let response = try await client.request(request)
      guard response.ok else {
        connected = true
        controlAccess = response.controlAccess ?? controlAccess
        if response.error == .controllerBusy {
          controlAccess = .observer
        }
        if updateVisibleState {
          errorMessage =
            response.message
            ?? response.error?.localizedDescription
            ?? ControlError.firmwareRejected.localizedDescription
        }
        return false
      }
      connected = true
      controlAccess = response.controlAccess ?? controlAccess
      if clearErrorOnSuccess {
        errorMessage = nil
      }
      if let hardware = response.hardware {
        self.hardware = hardware
      }
      if let fans = response.fans {
        self.fans = fans
        reconcileActivePreset(with: fans)
        for fan in fans where selectedRPM[fan.index] == nil || fan.mode == .automatic {
          selectedRPM[fan.index] = Double(
            max(fan.minimumRPM, min(fan.targetRPM, fan.maximumRPM))
          )
        }
      }
      if let temperature = response.temperature {
        self.temperature = temperature
      }
      if let validation = response.validation {
        self.validation = validation
      }
      status = hardware?.support == .experimental ? .experimentalM3 : .connected
      return true
    } catch {
      connected = false
      activePreset = .automatic
      activePresetPercentage = nil
      temperature = nil
      controlAccess = nil
      if updateVisibleState {
        fans = []
        hardware = nil
        let controlError = error as? ControlError
        status =
          controlError == .daemonUnavailable
          ? .notRunning
          : .error(error.localizedDescription)
        errorMessage = controlError == .daemonUnavailable ? nil : error.localizedDescription
      }
      return false
    }
  }

  private func reconcileActivePreset(with fans: [FanSnapshot]) {
    let reconciled = FanPresetReconciliation.resolve(
      fans: fans,
      current: activePreset,
      percentage: activePresetPercentage
    )
    activePreset = reconciled
    if reconciled == .automatic || reconciled == .manual {
      activePresetPercentage = nil
    }
  }
}

enum FanPresetReconciliation {
  static func resolve(
    fans: [FanSnapshot],
    current: FanPreset,
    percentage: Int?
  ) -> FanPreset {
    guard !fans.isEmpty else { return current }
    if fans.allSatisfy({ $0.mode == .automatic || $0.mode == .system }) {
      return .automatic
    }
    guard current != .automatic, current != .manual,
      let percentage,
      fans.allSatisfy({ $0.mode == .manual }),
      fans.allSatisfy({
        presetTarget(
          minimum: $0.minimumRPM,
          maximum: $0.maximumRPM,
          percentage: percentage
        ) == $0.targetRPM
      })
    else {
      return .manual
    }
    return current
  }

  private static func presetTarget(
    minimum: Int,
    maximum: Int,
    percentage: Int
  ) -> Int? {
    guard (1...100).contains(percentage), maximum > minimum else { return nil }
    if percentage == 100 { return maximum }
    let raw = Double(minimum) + (Double(percentage) / 100) * Double(maximum - minimum)
    let rounded = Int((raw / 100).rounded()) * 100
    return min(max(rounded, minimum), maximum)
  }
}
