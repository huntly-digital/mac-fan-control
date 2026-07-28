enum FanMenuContentPresentation: Equatable {
  case helperSetup
  case loadingFans
  case controls

  static func resolve(
    isFanClientConnected: Bool,
    helperPingConnected: Bool,
    hasFans: Bool
  ) -> Self {
    if isFanClientConnected {
      return hasFans ? .controls : .loadingFans
    }
    return helperPingConnected ? .loadingFans : .helperSetup
  }
}
