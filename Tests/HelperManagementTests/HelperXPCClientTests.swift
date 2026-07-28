import Foundation
import HelperManagement
import Testing

@Suite("Helper XPC client")
struct HelperXPCClientTests {
  @Test("successful ping reports the helper protocol version")
  func successfulPing() async {
    let client = HelperXPCClient { _ in "1" }

    #expect(await client.ping() == .connected(protocolVersion: "1"))
  }

  @Test(
    "XPC lifecycle failures remain distinguishable",
    arguments: [
      (HelperPingError.interrupted, HelperConnectionIssue.interrupted),
      (HelperPingError.invalidated, HelperConnectionIssue.invalidated),
    ]
  )
  func lifecycleFailure(
    error: HelperPingError,
    expected: HelperConnectionIssue
  ) async {
    let client = HelperXPCClient { _ in throw error }

    #expect(await client.ping() == .disconnected(expected))
  }

  @Test("a helper that does not reply is timed out")
  func timeout() async {
    let client = HelperXPCClient { _ in
      try await Task.sleep(for: .seconds(1))
      return "late"
    }

    #expect(
      await client.ping(timeout: .milliseconds(5))
        == .disconnected(.timedOut)
    )
  }
}
