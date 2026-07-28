import FanProtocol
import SwiftUI

struct FanRowView: View {
  @ObservedObject var store: FanStore
  let fan: FanSnapshot

  private var rpm: Binding<Double> {
    Binding(
      get: { store.selectedRPM[fan.index] ?? Double(fan.targetRPM) },
      set: { store.selectedRPM[fan.index] = $0 }
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Fan \(fan.index + 1)")
          .font(.subheadline.weight(.semibold))
        Spacer()
        Text("\(fan.actualRPM) RPM")
          .monospacedDigit()
        Text(fan.mode.title)
          .font(.caption.weight(.medium))
          .foregroundStyle(fan.mode == .manual ? .orange : .secondary)
      }

      HStack {
        Text("\(fan.minimumRPM)")
        Slider(
          value: rpm,
          in: Double(fan.minimumRPM)...Double(fan.maximumRPM),
          step: 100
        )
        Text("\(fan.maximumRPM)")
      }
      .font(.caption)
      .foregroundStyle(.secondary)

      HStack {
        Text("\(Int(rpm.wrappedValue.rounded())) RPM")
          .font(.caption.monospacedDigit())
        Spacer()
        Button("Auto") {
          store.automatic(fan: fan.index)
        }
        Button("Apply") {
          store.apply(fan: fan.index)
        }
        .buttonStyle(.borderedProminent)
      }
    }
  }
}
