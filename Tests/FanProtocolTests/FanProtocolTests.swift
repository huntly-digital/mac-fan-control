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
    let oversized = Data(repeating: 0x20, count: JSONLineCodec.maximumMessageBytes + 1)

    XCTAssertThrowsError(try JSONLineCodec.decode(FanRequest.self, from: oversized)) { error in
      XCTAssertEqual(error as? ProtocolError, .messageTooLarge)
    }
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
}
