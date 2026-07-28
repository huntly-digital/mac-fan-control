import FanProtocol
import HelperManagement
import Testing

@Suite("Helper fan client")
struct HelperFanClientTests {
  @Test("returns the response for the matching request")
  func matchingResponse() async throws {
    let client = HelperFanClient(operation: { request, _ in
      FanResponse(id: request.id, ok: true)
    })
    let request = FanRequest(id: "status-1", command: .status)

    #expect(try await client.request(request).id == request.id)
  }

  @Test("rejects a response belonging to another request")
  func mismatchedResponse() async {
    let client = HelperFanClient(operation: { _, _ in
      FanResponse(id: "other", ok: true)
    })

    await #expect(throws: ControlError.malformedRequest) {
      try await client.request(FanRequest(id: "expected", command: .status))
    }
  }

  @Test("long-running writes outlive the ten-second engine verification window")
  func commandSpecificTimeouts() {
    #expect(HelperFanClient.timeout(for: .status) == .seconds(3))
    #expect(HelperFanClient.timeout(for: .setManual) == .seconds(30))
    #expect(HelperFanClient.timeout(for: .setPreset) == .seconds(240))
    #expect(HelperFanClient.timeout(for: .validateHardware) == .seconds(240))
  }
}
