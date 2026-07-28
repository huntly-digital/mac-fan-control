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

      HelperSettingsView(helperStore: helperStore, fanStore: store)
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
        maximumPresetRow
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

  private var maximumPresetRow: some View {
    HStack {
      Label(FanPreset.maximum.title, systemImage: FanPreset.maximum.systemImage)
        .frame(width: 92, alignment: .leading)
      Text("Uses each fan’s reported maximum")
        .foregroundStyle(.secondary)
      Spacer()
      Text("100%")
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
        Picker("Menu bar temperature", selection: $store.primaryTemperatureID) {
          Text("CPU Hotspot").tag("cpu.hotspot")
          Text("CPU Average").tag("cpu.average")
        }
        sensorRow(readingID: "cpu.average", fallbackName: "CPU Average")
        sensorRow(readingID: "cpu.hotspot", fallbackName: "CPU Hotspot")
        sensorRow(readingID: "gpu.average", fallbackName: "GPU Average")
        sensorRow(readingID: "gpu.hotspot", fallbackName: "GPU Hotspot")
        sensorRow(readingID: "battery.temperature", fallbackName: "Battery")
      }
      if let diagnostics = store.temperature?.readings.filter({ $0.role == .individual }),
        !diagnostics.isEmpty
      {
        Section("Diagnostics") {
          DisclosureGroup("Individual allowlisted sensors") {
            ForEach(diagnostics) { reading in
              LabeledContent(reading.label) {
                VStack(alignment: .trailing, spacing: 1) {
                  Text("\(Int(reading.celsius.rounded()))°C")
                    .monospacedDigit()
                  Text(reading.sourceKeys.joined(separator: ", "))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
        }
      }
      Section {
        Text("Only model-validated SMC keys are read. Unknown sensors stay unavailable.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }

  private func sensorRow(readingID: String, fallbackName: String) -> some View {
    let reading = store.temperature?.readings.first { $0.id == readingID }
    return LabeledContent(reading?.label ?? fallbackName) {
      if let reading {
        Text("\(Int(reading.celsius.rounded()))°C")
          .monospacedDigit()
      } else {
        Text("Unavailable")
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct HelperSettingsView: View {
  @ObservedObject var helperStore: HelperStore
  @ObservedObject var fanStore: FanStore
  @State private var confirmingValidation = false

  var body: some View {
    Form {
      Section("Privileged helper") {
        HelperSetupView(store: helperStore)
      }
      if let hardware = fanStore.hardware {
        let presentation = HardwareValidationPresentation.resolve(
          eligibility: hardware.writeEligibility,
          controlAccess: fanStore.controlAccess
        )
        Section("Hardware validation") {
          LabeledContent("Status", value: presentation.title)
          LabeledContent("Fingerprint") {
            Text(String(hardware.capabilityFingerprint.prefix(23)) + "…")
              .font(.caption.monospaced())
              .textSelection(.enabled)
          }
          Text(presentation.message)
            .font(.caption)
            .foregroundStyle(.secondary)
          if let validation = fanStore.validation {
            ProgressView(
              value: Double(validation.completedFans),
              total: Double(max(validation.totalFans, 1))
            )
            Text(validation.message)
              .font(.caption)
          }
          if presentation.canValidate {
            Button("Validate Hardware…") {
              confirmingValidation = true
            }
            .disabled(fanStore.isApplying)
          }
        }
      }
      Section {
        Button("Check Connection") {
          Task { await helperStore.refresh() }
        }
      }
    }
    .formStyle(.grouped)
    .task { await helperStore.refresh() }
    .alert("Validate Apple Silicon fan control?", isPresented: $confirmingValidation) {
      Button("Cancel", role: .cancel) {}
      Button("Validate") {
        fanStore.validateHardware()
      }
    } message: {
      Text(
        "Each fan will briefly run at its baseline minimum plus 500 RPM, then return to Auto. Stop using the Mac if fan behavior is unexpected."
      )
    }
  }
}

private struct GeneralSettingsView: View {
  @AppStorage("showTemperatureInMenuBar") private var showTemperatureInMenuBar = true

  var body: some View {
    Form {
      Section("Menu bar") {
        Toggle("Show selected CPU temperature", isOn: $showTemperatureInMenuBar)
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
      Text(AboutPresentation.productDescription)
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .frame(maxWidth: 400)
      Text(AboutPresentation.statusNote)
        .font(.caption)
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .frame(maxWidth: 400)
      HStack(spacing: 8) {
        Link("View on GitHub", destination: AboutPresentation.repositoryURL)
        Text("·")
          .foregroundStyle(.tertiary)
        Link("Report an Issue", destination: AboutPresentation.issuesURL)
        Text("·")
          .foregroundStyle(.tertiary)
        Link("MIT License", destination: AboutPresentation.licenseURL)
      }
      .font(.caption)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
