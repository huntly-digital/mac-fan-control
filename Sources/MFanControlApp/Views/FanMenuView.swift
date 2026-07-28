import AppKit
import FanProtocol
import SwiftUI

struct FanMenuView: View {
  @ObservedObject var store: FanStore
  @ObservedObject var presetStore: PresetStore
  @ObservedObject var helperStore: HelperStore
  @State private var manualControlsExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      Divider()

      if helperNeedsAttention {
        HelperSetupView(store: helperStore)
      } else if store.status == .notRunning {
        HelperSetupView(store: helperStore)
      } else if store.fans.isEmpty {
        ProgressView("Reading fans…")
          .frame(maxWidth: .infinity, minHeight: 80)
      } else {
        presetPicker

        VStack(spacing: 10) {
          ForEach(store.fans) { fan in
            CompactFanRow(fan: fan)
          }
        }

        Divider()
        DisclosureGroup(isExpanded: $manualControlsExpanded) {
          VStack(spacing: 12) {
            ForEach(store.fans) { fan in
              FanRowView(store: store, fan: fan)
              if fan.index != store.fans.last?.index {
                Divider()
              }
            }
          }
          .padding(.top, 10)
        } label: {
          Label("Manual control", systemImage: "slider.horizontal.3")
            .font(.subheadline.weight(.medium))
        }
      }

      if let error = store.errorMessage {
        Label(error, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }

      Divider()
      footer
    }
    .padding(14)
    .frame(width: 336)
    .task {
      await helperStore.refresh()
    }
  }

  private var helperNeedsAttention: Bool {
    switch helperStore.state {
    case .connected:
      false
    default:
      true
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text("MFanControl")
          .font(.headline)
        if let hardware = store.hardware {
          Text("\(hardware.model) · \(hardware.processor)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        } else {
          Text(store.status.title)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Spacer(minLength: 8)

      if let temperature = store.temperature {
        VStack(alignment: .trailing, spacing: 0) {
          Text("\(Int(temperature.cpuMaximumCelsius.rounded()))°")
            .font(.title2.weight(.semibold))
            .monospacedDigit()
          Text(temperature.primarySensorName)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      } else {
        statusBadge
      }
    }
  }

  private var statusBadge: some View {
    HStack(spacing: 5) {
      Circle()
        .fill(store.status.color)
        .frame(width: 7, height: 7)
      Text(store.status.title)
        .font(.caption)
    }
  }

  private var presetPicker: some View {
    HStack(spacing: 6) {
      ForEach(FanPreset.visible) { preset in
        Button {
          store.applyPreset(preset, percentage: presetStore.percentage(for: preset))
        } label: {
          VStack(spacing: 4) {
            Image(systemName: preset.systemImage)
              .font(.system(size: 14, weight: .semibold))
            Text(preset.title)
              .font(.caption2.weight(.medium))
              .lineLimit(1)
              .minimumScaleFactor(0.75)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(store.activePreset == preset ? Color.accentColor : .primary)
        .background {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
              store.activePreset == preset
                ? Color.accentColor.opacity(0.16)
                : Color.secondary.opacity(0.08)
            )
        }
        .overlay {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(
              store.activePreset == preset
                ? Color.accentColor.opacity(0.4)
                : Color.clear,
              lineWidth: 1
            )
        }
        .disabled(!store.isConnected || store.isApplying)
      }
    }
  }

  private var footer: some View {
    HStack {
      statusBadge
      Spacer()
      SettingsLink {
        Image(systemName: "gearshape")
      }
      .help("Settings")
      Button {
        NSApplication.shared.terminate(nil)
      } label: {
        Image(systemName: "power")
      }
      .help("Quit MFanControl")
      .keyboardShortcut("q")
    }
  }
}

private struct CompactFanRow: View {
  let fan: FanSnapshot

  private var progress: Double {
    guard fan.maximumRPM > fan.minimumRPM else { return 0 }
    return min(
      max(
        Double(fan.actualRPM - fan.minimumRPM)
          / Double(fan.maximumRPM - fan.minimumRPM),
        0
      ),
      1
    )
  }

  var body: some View {
    VStack(spacing: 6) {
      HStack {
        Label("Fan \(fan.index + 1)", systemImage: "fanblades")
          .font(.subheadline.weight(.medium))
        Spacer()
        Text("\(fan.actualRPM) RPM")
          .font(.subheadline.monospacedDigit())
        Text(fan.mode.title)
          .font(.caption2.weight(.medium))
          .foregroundStyle(fan.mode == .manual ? .orange : .secondary)
      }

      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule()
            .fill(Color.secondary.opacity(0.16))
          Capsule()
            .fill(fan.mode == .manual ? Color.orange : Color.accentColor)
            .frame(width: max(4, proxy.size.width * progress))
        }
      }
      .frame(height: 4)

      HStack {
        Text("\(fan.minimumRPM)")
        Spacer()
        Text("\(fan.maximumRPM)")
      }
      .font(.caption2.monospacedDigit())
      .foregroundStyle(.tertiary)
    }
  }
}
