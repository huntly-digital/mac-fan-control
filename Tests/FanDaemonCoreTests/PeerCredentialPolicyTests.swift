import XCTest

@testable import FanDaemonCore

final class PeerCredentialPolicyTests: XCTestCase {
  func testOnlyConfiguredUIDIsAccepted() {
    let policy = PeerCredentialPolicy(allowedUID: 501)

    XCTAssertTrue(policy.accepts(peerUID: 501))
    XCTAssertFalse(policy.accepts(peerUID: 0))
    XCTAssertFalse(policy.accepts(peerUID: 502))
  }
}
