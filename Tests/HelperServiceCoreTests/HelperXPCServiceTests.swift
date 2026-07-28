import FanProtocol
import Foundation
import HelperProtocol
import HelperServiceCore
import Testing

@Suite("Helper XPC endpoint")
struct HelperXPCServiceTests {
  @Test("ping reports the shared protocol version")
  func pingReportsProtocolVersion() {
    let service = HelperXPCService { request in
      FanResponse(id: request.id, ok: true)
    }
    var receivedVersion: String?

    service.ping { version in
      receivedVersion = version
    }

    #expect(receivedVersion == "4")
  }

  @Test("forwards a bounded fan request and encodes its response")
  func forwardsFanRequest() async throws {
    let service = HelperXPCService { request in
      FanResponse(id: request.id, ok: true)
    }
    let request = FanRequest(id: "status-1", command: .status)
    let requestData = try JSONLineCodec.encode(request)

    let result = await withCheckedContinuation {
      (continuation: CheckedContinuation<(Data?, NSError?), Never>) in
      service.performFanRequest(requestData) { data, error in
        continuation.resume(returning: (data, error))
      }
    }

    #expect(result.1 == nil)
    let response = try #require(result.0)
    #expect(try JSONLineCodec.decode(FanResponse.self, from: response).id == request.id)
  }

  @Test("rejects malformed fan request payloads")
  func rejectsMalformedRequest() async {
    let service = HelperXPCService { request in
      FanResponse(id: request.id, ok: true)
    }

    let result = await withCheckedContinuation {
      (continuation: CheckedContinuation<(Data?, NSError?), Never>) in
      service.performFanRequest(Data("not-json".utf8)) { data, error in
        continuation.resume(returning: (data, error))
      }
    }

    #expect(result.0 == nil)
    #expect(result.1?.domain == HelperXPCError.errorDomain)
  }

  @Test("builds a same-team requirement for the app bundle")
  func signingRequirement() {
    #expect(
      HelperClientRequirement.make(teamIdentifier: "D8QMW9MD44")
        == "identifier \"io.clover.mfancontrol\" and anchor apple generic "
          + "and certificate leaf[subject.OU] = \"D8QMW9MD44\""
    )
  }

  @Test("closing a ping-only connection does not trigger fan fallback")
  func pingDisconnectDoesNotAffectFans() async throws {
    let disconnects = AsyncCounter()
    let service = HelperXPCService(
      handler: { request in FanResponse(id: request.id, ok: true) },
      disconnectHandler: { await disconnects.increment() }
    )

    service.connectionInvalidated()
    try await Task.sleep(for: .milliseconds(10))

    #expect(await disconnects.value == 0)
  }

  @Test("closing an established fan session triggers fan fallback")
  func fanSessionDisconnectTriggersFallback() async throws {
    let disconnects = AsyncCounter()
    let service = HelperXPCService(
      handler: { request in FanResponse(id: request.id, ok: true) },
      disconnectHandler: { await disconnects.increment() }
    )
    let hello = try JSONLineCodec.encode(
      FanRequest(id: "hello-1", command: .hello)
    )
    await withCheckedContinuation {
      (continuation: CheckedContinuation<Void, Never>) in
      service.performFanRequest(hello) { _, _ in
        continuation.resume()
      }
    }

    service.connectionInvalidated()
    try await Task.sleep(for: .milliseconds(10))

    #expect(await disconnects.value == 1)
  }
}

private actor AsyncCounter {
  private(set) var value = 0

  func increment() {
    value += 1
  }
}
