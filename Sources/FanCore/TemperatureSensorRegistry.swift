import FanProtocol
import Foundation

public enum TemperatureSensorRegistry {
  private struct Sensor: Sendable {
    let key: String
    let label: String
    let group: TemperatureGroup
  }

  public static func allowlistedKeys(model: String) -> Set<String> {
    Set(sensors(model: model).map(\.key))
  }

  public static func snapshot(
    model: String,
    sample: (String) -> Double?
  ) -> TemperatureSnapshot? {
    let valid = sensors(model: model).compactMap { sensor -> (Sensor, Double)? in
      guard let value = sample(sensor.key), value.isFinite, (-40...150).contains(value)
      else {
        return nil
      }
      return (sensor, value)
    }
    guard !valid.isEmpty else { return nil }

    var readings = valid.map { sensor, value in
      TemperatureReading(
        id: "sensor.\(sensor.key)",
        label: sensor.label,
        group: sensor.group,
        role: .individual,
        celsius: value,
        sampleCount: 1,
        sourceKeys: [sensor.key]
      )
    }

    readings.append(contentsOf: aggregate(group: .cpu, label: "CPU", valid: valid))
    readings.append(contentsOf: aggregate(group: .gpu, label: "GPU", valid: valid))

    if let battery = valid.first(where: { $0.0.group == .battery }) {
      readings.append(
        TemperatureReading(
          id: "battery.temperature",
          label: "Battery",
          group: .battery,
          role: .individual,
          celsius: battery.1,
          sampleCount: 1,
          sourceKeys: [battery.0.key]
        )
      )
    }
    return TemperatureSnapshot(readings: readings)
  }

  private static func aggregate(
    group: TemperatureGroup,
    label: String,
    valid: [(Sensor, Double)]
  ) -> [TemperatureReading] {
    let sample = valid.filter { $0.0.group == group }
    guard !sample.isEmpty else { return [] }
    let sourceKeys = sample.map { $0.0.key }
    let values = sample.map(\.1)
    return [
      TemperatureReading(
        id: "\(group.rawValue).average",
        label: "\(label) Average",
        group: group,
        role: .average,
        celsius: values.reduce(0, +) / Double(values.count),
        sampleCount: values.count,
        sourceKeys: sourceKeys
      ),
      TemperatureReading(
        id: "\(group.rawValue).hotspot",
        label: "\(label) Hotspot",
        group: group,
        role: .hotspot,
        celsius: values.max()!,
        sampleCount: values.count,
        sourceKeys: sourceKeys
      ),
    ]
  }

  private static func sensors(model: String) -> [Sensor] {
    let generation: [Sensor]
    if model.hasPrefix("Mac12") || model.hasPrefix("MacBookPro18")
      || model.hasPrefix("MacBookAir10")
    {
      generation = make(
        cpu: ["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"],
        gpu: ["Tg05", "Tg0D", "Tg0L", "Tg0T"],
        memory: []
      )
    } else if model.hasPrefix("Mac13") {
      generation = make(
        cpu: ["Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"],
        gpu: ["Tg0f", "Tg0j"],
        memory: []
      )
    } else if model.hasPrefix("Mac14") || model.hasPrefix("Mac15") {
      generation = make(
        cpu: [
          "Te05", "Te0L", "Te0P", "Te0S",
          "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E",
          "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E",
        ],
        gpu: ["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"],
        memory: []
      )
    } else if model.hasPrefix("Mac16") {
      generation = make(
        cpu: ["Te05", "Te0S", "Te09", "Te0H", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"],
        gpu: ["Tg1U", "Tg1k", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"],
        memory: ["Tm0p", "Tm1p", "Tm2p"]
      )
    } else if model.hasPrefix("Mac17") {
      generation = make(
        cpu: ["Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K", "Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"],
        gpu: ["Tg0U", "Tg0X", "Tg0d", "Tg0g", "Tg0j", "Tg1Y", "Tg1c", "Tg1g"],
        memory: []
      )
    } else {
      generation = []
    }

    let crossPlatform = make(
      cpu: ["TC0D", "TC0E", "TC0F", "TC0H", "TC0P", "TCAD", "TCMz"],
      gpu: ["TG0D"],
      memory: []
    ) + [
      Sensor(key: "TB1T", label: "Battery TB1T", group: .battery),
      Sensor(key: "TB0T", label: "Battery TB0T", group: .battery),
    ]
    var seen: Set<String> = []
    return (generation + crossPlatform).filter { seen.insert($0.key).inserted }
  }

  private static func make(
    cpu: [String],
    gpu: [String],
    memory: [String]
  ) -> [Sensor] {
    cpu.map { Sensor(key: $0, label: "CPU \($0)", group: .cpu) }
      + gpu.map { Sensor(key: $0, label: "GPU \($0)", group: .gpu) }
      + memory.map { Sensor(key: $0, label: "Memory \($0)", group: .memory) }
  }
}
