import Darwin

public struct PeerCredentialPolicy: Sendable {
  public let allowedUID: uid_t

  public init(allowedUID: uid_t) {
    self.allowedUID = allowedUID
  }

  public func accepts(peerUID: uid_t) -> Bool {
    peerUID == allowedUID
  }
}
