import FanProtocol
import XCTest

@testable import FanCore

final class TemperatureSensorRegistryTests: XCTestCase {
  func testRegistrySelectsGenerationSpecificAllowlistsForM1ThroughM5() {
    XCTAssertTrue(TemperatureSensorRegistry.allowlistedKeys(model: "Mac12,1").contains("Tp09"))
    XCTAssertTrue(TemperatureSensorRegistry.allowlistedKeys(model: "Mac13,1").contains("Tp1h"))
    XCTAssertTrue(TemperatureSensorRegistry.allowlistedKeys(model: "Mac15,7").contains("Tf04"))
    XCTAssertTrue(TemperatureSensorRegistry.allowlistedKeys(model: "Mac16,1").contains("Tg1U"))
    XCTAssertTrue(TemperatureSensorRegistry.allowlistedKeys(model: "Mac17,1").contains("Tp0u"))
  }

  func testRegistryDerivesAverageAndHotspotFromTheSameValidCPUSample() {
    let samples = ["Tf04": 60.0, "Tf09": 74.0, "Tf0A": 68.0, "Tf0B": 200.0]

    let snapshot = TemperatureSensorRegistry.snapshot(model: "Mac15,7") {
      samples[$0]
    }

    let average = snapshot?.readings.first { $0.id == "cpu.average" }
    let hotspot = snapshot?.readings.first { $0.id == "cpu.hotspot" }
    XCTAssertEqual(try XCTUnwrap(average?.celsius), 67.33333333333333, accuracy: 0.0001)
    XCTAssertEqual(hotspot?.celsius, 74)
    XCTAssertEqual(average?.sourceKeys, ["Tf04", "Tf09", "Tf0A"])
    XCTAssertEqual(hotspot?.sourceKeys, average?.sourceKeys)
    XCTAssertEqual(average?.sampleCount, 3)
  }

  func testRegistryDiscardsMalformedAndOutOfRangeSamples() {
    let samples = ["Tp01": -41.0, "Tp05": .nan, "Tp09": 65.0]

    let snapshot = TemperatureSensorRegistry.snapshot(model: "Mac13,2") {
      samples[$0]
    }

    XCTAssertEqual(snapshot?.readings.first { $0.id == "cpu.average" }?.celsius, 65)
    XCTAssertFalse(snapshot?.readings.contains { $0.sourceKeys.contains("Tp01") } ?? true)
    XCTAssertFalse(snapshot?.readings.contains { $0.sourceKeys.contains("Tp05") } ?? true)
  }

  func testRegistryKeepsBatterySeparateAndIndividualDiagnosticsStable() {
    let samples = ["TC0D": 63.0, "TB1T": 32.0]

    let snapshot = TemperatureSensorRegistry.snapshot(model: "Mac17,1") {
      samples[$0]
    }

    XCTAssertEqual(
      snapshot?.readings.first { $0.id == "battery.temperature" }?.celsius,
      32
    )
    let diagnostic = snapshot?.readings.first { $0.id == "sensor.TC0D" }
    XCTAssertEqual(diagnostic?.role, .individual)
    XCTAssertEqual(diagnostic?.sourceKeys, ["TC0D"])
  }

  func testLargestGenerationDiagnosticsFitBoundedTelemetryEnvelope() throws {
    let snapshot = try XCTUnwrap(
      TemperatureSensorRegistry.snapshot(model: "Mac17,1") { _ in 70 }
    )
    let response = FanResponse(id: "m5", ok: true, temperature: snapshot)

    let encoded = try JSONLineCodec.encode(response)

    XCTAssertLessThanOrEqual(encoded.count - 1, JSONLineCodec.maximumMessageBytes)
    XCTAssertGreaterThan(encoded.count - 1, JSONLineCodec.maximumRequestBytes)
  }
}
