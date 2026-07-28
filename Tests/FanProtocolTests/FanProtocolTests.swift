import XCTest

@testable import FanProtocol

final class FanProtocolTests: XCTestCase {
  func testRequestRoundTripsAsOneJSONLine() throws {
    let request = FanRequest(id: "request-1", command: .setManual, fan: 1, rpm: 3_200)

    let encoded = try JSONLineCodec.encode(request)
    XCTAssertEqual(encoded.last, 0x0A)
    XCTAssertEqual(try JSONLineCodec.decode(FanRequest.self, from: encoded), request)
  }

  func testDecoderRejectsMessagesLargerThanFourKiB() {
    let oversized = Data(repeating: 0x20, count: JSONLineCodec.maximumRequestBytes + 1)

    XCTAssertThrowsError(
      try JSONLineCodec.decode(
        FanRequest.self,
        from: oversized,
        maximumBytes: JSONLineCodec.maximumRequestBytes
      )
    ) { error in
      XCTAssertEqual(error as? ProtocolError, .messageTooLarge)
    }
  }

  func testTelemetryResponsesHaveASeparateBoundedEnvelope() {
    XCTAssertEqual(JSONLineCodec.maximumRequestBytes, 4_096)
    XCTAssertEqual(JSONLineCodec.maximumMessageBytes, 32_768)
  }

  func testSocketPathIsScopedToUID() {
    XCTAssertEqual(SocketAddress.path(for: 501), "/var/run/mfancontrol-501.sock")
  }

  func testFanModeUsesDistinctUserFacingTitles() {
    XCTAssertEqual(FanMode.automatic.title, "Auto")
    XCTAssertEqual(FanMode.manual.title, "Manual")
    XCTAssertEqual(FanMode.system.title, "System")
    XCTAssertEqual(FanMode.unknown.title, "Unknown")
  }

  func testProtocolV4RequestCarriesOnlyExplicitValidationConfirmation() throws {
    let request = FanRequest(
      id: "validation-1",
      command: .validateHardware,
      validationConfirmed: true
    )

    let encoded = try JSONLineCodec.encode(request)
    let decoded = try JSONLineCodec.decode(FanRequest.self, from: encoded)

    XCTAssertEqual(decoded, request)
    XCTAssertTrue(decoded.validationConfirmed)
  }

  func testFanSnapshotKeepsBaselineSeparateFromTemporaryFloor() {
    let fan = FanSnapshot(
      index: 0,
      actualRPM: 3_200,
      targetRPM: 3_200,
      minimumRPM: 1_350,
      effectiveMinimumRPM: 3_200,
      maximumRPM: 5_349,
      mode: .manual
    )

    XCTAssertEqual(fan.minimumRPM, 1_350)
    XCTAssertEqual(fan.effectiveMinimumRPM, 3_200)
  }

  func testTemperatureSnapshotSelectsStableMetricWithSafetyFallbacks() {
    let readings = [
      TemperatureReading(
        id: "cpu.average",
        label: "CPU Average",
        group: .cpu,
        role: .average,
        celsius: 61,
        sampleCount: 4,
        sourceKeys: ["Tp01", "Tp05", "Tp09", "Tp0D"]
      ),
      TemperatureReading(
        id: "cpu.hotspot",
        label: "CPU Hotspot",
        group: .cpu,
        role: .hotspot,
        celsius: 73,
        sampleCount: 4,
        sourceKeys: ["Tp01", "Tp05", "Tp09", "Tp0D"]
      ),
    ]
    let snapshot = TemperatureSnapshot(readings: readings)

    XCTAssertEqual(snapshot.primaryReading(selectedID: "missing")?.id, "cpu.hotspot")
    XCTAssertEqual(snapshot.primaryReading(selectedID: "cpu.average")?.celsius, 61)
  }

  func testHardwareProfileCarriesBoundedWriteEligibility() {
    let profile = HardwareProfile(
      model: "Mac15,7",
      processor: "Apple M3 Pro",
      fanCount: 2,
      hasFtst: true,
      modeKeyFormat: "F%dMd",
      strategy: .directThenFtst,
      support: .experimental,
      writeEligibility: .validationRequired,
      capabilityFingerprint: "sha256:abc"
    )

    XCTAssertEqual(profile.writeEligibility, .validationRequired)
    XCTAssertEqual(profile.capabilityFingerprint, "sha256:abc")
  }

  func testValidationReportRoundTripsInResponse() throws {
    let report = HardwareValidationReport(
      status: .passed,
      completedFans: 2,
      totalFans: 2,
      message: "Hardware validation passed."
    )
    let response = FanResponse(id: "response-1", ok: true, validation: report)

    let data = try JSONLineCodec.encode(response)

    XCTAssertEqual(
      try JSONLineCodec.decode(FanResponse.self, from: data).validation,
      report
    )
  }

  func testNewControlErrorsRemainBoundedAndSerializable() throws {
    let errors: [ControlError] = [
      .hardwareValidationRequired,
      .controllerBusy,
      .capabilityMismatch,
      .baselineRestoreFailed,
    ]

    for error in errors {
      let data = try JSONEncoder().encode(error)
      XCTAssertEqual(try JSONDecoder().decode(ControlError.self, from: data), error)
    }
  }
}
