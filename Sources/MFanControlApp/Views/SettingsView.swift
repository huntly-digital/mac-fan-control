import FanProtocol
import HelperManagement
import SwiftUI

struct SettingsView: View {
  @ObservedObject var store: FanStore
  @ObservedObject var presetStore: PresetStore
  @ObservedObject var helperStore: HelperStore

  var body: some View {
    TabView {
      PresetSettingsView(store: store, presetStore: presetStore)
        .tabItem { Label("Presets", systemImage: "dial.medium") }

      SensorSettingsView(store: store)
        .tabItem { Label("Sensors", systemImage: "thermometer.medium") }

      HelperSettingsView(store: helperStore)
        .tabItem { Label("Helper", systemImage: "shield") }

      GeneralSettingsView()
        .tabItem { Label("General", systemImage: "gearshape") }

      AboutSettingsView()
        .tabItem { Label("About", systemImage: "info.circle") }
    }
    .padding(20)
    .frame(width: 520, height: 360)
  }
}

private struct PresetSettingsView: View {
  @ObservedObject var store: FanStore
  @ObservedObject var presetStore: PresetStore

  var body: some View {
    Form {
      Section {
        Text("Each preset uses a fixed point inside every fan’s reported RPM range.")
          .font(.caption)
          .foregroundStyle(.secondary)

        presetRow(.quiet)
        presetRow(.balanced)
        presetRow(.cool)
      } header: {
        Text("Fan speed")
      }

      if !store.fans.isEmpty {
        Section("Current hardware preview") {
          ForEach(store.fans) { fan in
            LabeledContent("Fan \(fan.index + 1)") {
              Text("\(fan.minimumRPM)–\(fan.maximumRPM) RPM")
                .monospacedDigit()
            }
          }
        }
      }
    }
    .formStyle(.grouped)
  }

  private func presetRow(_ preset: FanPreset) -> some View {
    let value = presetStore.percentage(for: preset) ?? 0
    return HStack {
      Label(preset.title, systemImage: preset.systemImage)
        .frame(width: 92, alignment: .leading)
      Slider(
        value: Binding(
          get: { Double(presetStore.percentage(for: preset) ?? value) },
          set: { presetStore.setPercentage(Int($0.rounded()), for: preset) }
        ),
        in: 5...80,
        step: 5
      )
      Text("\(presetStore.percentage(for: preset) ?? value)%")
        .monospacedDigit()
        .frame(width: 38, alignment: .trailing)
    }
  }
}

private struct SensorSettingsView: View {
  @ObservedObject var store: FanStore

  var body: some View {
    Form {
      Section("Temperature sensors") {
        sensorRow(
          name: store.temperature?.primarySensorName ?? "CPU Max",
          value: store.temperature?.cpuMaximumCelsius
        )
        sensorRow(name: "GPU", value: store.temperature?.gpuCelsius)
        sensorRow(name: "Battery", value: store.temperature?.batteryCelsius)
      }
      Section {
        Text("Only model-validated SMC keys are read. Unknown sensors stay unavailable.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }

  private func sensorRow(name: String, value: Double?) -> some View {
    LabeledContent(name) {
      if let value {
        Text("\(Int(value.rounded()))°C")
          .monospacedDigit()
      } else {
        Text("Unavailable")
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct HelperSettingsView: View {
  @ObservedObject var store: HelperStore

  var body: some View {
    Form {
      Section("Privileged helper") {
        HelperSetupView(store: store)
      }
      Section {
        Button("Check Connection") {
          Task { await store.refresh() }
        }
      }
    }
    .formStyle(.grouped)
    .task { await store.refresh() }
  }
}

private struct GeneralSettingsView: View {
  @AppStorage("showTemperatureInMenuBar") private var showTemperatureInMenuBar = true

  var body: some View {
    Form {
      Section("Menu bar") {
        Toggle("Show CPU temperature", isOn: $showTemperatureInMenuBar)
      }
      Section("Safety") {
        Label("Return all fans to Auto when the helper disconnects", systemImage: "checkmark.shield")
        Label("Disable manual control during thermal pressure", systemImage: "checkmark.shield")
      }
    }
    .formStyle(.grouped)
  }
}

private struct AboutSettingsView: View {
  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
  }

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "fanblades")
        .font(.system(size: 44))
        .foregroundStyle(.tint)
      Text("MFanControl")
        .font(.title2.weight(.semibold))
      Text("Version \(version)")
        .foregroundStyle(.secondary)
      Text("Open-source, source-only fan control for Apple Silicon. Experimental hardware support.")
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .frame(maxWidth: 360)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
