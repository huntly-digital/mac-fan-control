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
  @Published private(set) var activePreset: FanPreset = .automatic
  @Published private(set) var isApplying = false
  @Published private(set) var errorMessage: String?
  @Published var selectedRPM: [Int: Double] = [:]

  private let client = HelperFanClient()
  private var refreshTask: Task<Void, Never>?
  private var heartbeatTask: Task<Void, Never>?
  private var connected = false

  init() {
    start()
  }

  deinit {
    refreshTask?.cancel()
    heartbeatTask?.cancel()
  }

  var menuTitle: String {
    guard let temperature, connected else { return "MFan" }
    return "\(Int(temperature.cpuMaximumCelsius.rounded()))°C"
  }

  var isConnected: Bool {
    connected
  }

  func apply(fan: Int) {
    guard let rpm = selectedRPM[fan] else { return }
    Task {
      isApplying = true
      defer { isApplying = false }
      if await send(
        .init(command: .setManual, fan: fan, rpm: Int(rpm.rounded())),
        clearErrorOnSuccess: true
      ) {
        activePreset = .manual
      }
    }
  }

  func automatic(fan: Int) {
    Task {
      isApplying = true
      defer { isApplying = false }
      if await send(.init(command: .setAutomatic, fan: fan), clearErrorOnSuccess: true),
        fans.allSatisfy({ $0.mode == .automatic })
      {
        activePreset = .automatic
      }
    }
  }

  func allAutomatic() {
    applyPreset(.automatic, percentage: nil)
  }

  func applyPreset(_ preset: FanPreset, percentage: Int?) {
    guard preset != .manual else { return }
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
        throw response.error ?? ControlError.firmwareRejected
      }
      connected = true
      if clearErrorOnSuccess {
        errorMessage = nil
      }
      if let hardware = response.hardware {
        self.hardware = hardware
      }
      if let fans = response.fans {
        self.fans = fans
        for fan in fans where selectedRPM[fan.index] == nil || fan.mode == .automatic {
          selectedRPM[fan.index] = Double(
            max(fan.minimumRPM, min(fan.targetRPM, fan.maximumRPM))
          )
        }
      }
      if let temperature = response.temperature {
        self.temperature = temperature
      }
      status = hardware?.support == .experimental ? .experimentalM3 : .connected
      return true
    } catch {
      connected = false
      activePreset = .automatic
      temperature = nil
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
}
