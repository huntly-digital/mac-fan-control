import Testing

@testable import MFanControlApp

@Suite("Fan menu content presentation")
struct FanMenuContentPresentationTests {
  @Test("keeps fan controls visible when the active fan session is connected")
  func connectedFanSessionWinsOverFailedPing() {
    #expect(
      FanMenuContentPresentation.resolve(
        isFanClientConnected: true,
        helperPingConnected: false,
        hasFans: true
      ) == .controls
    )
  }

  @Test("shows helper recovery only when the active fan session is disconnected")
  func disconnectedFanSessionShowsHelperRecovery() {
    #expect(
      FanMenuContentPresentation.resolve(
        isFanClientConnected: false,
        helperPingConnected: false,
        hasFans: false
      ) == .helperSetup
    )
  }

  @Test("shows loading while a connected fan session has no snapshots")
  func connectedSessionWithoutSnapshotsShowsLoading() {
    #expect(
      FanMenuContentPresentation.resolve(
        isFanClientConnected: true,
        helperPingConnected: false,
        hasFans: false
      ) == .loadingFans
    )
  }
}
