import Foundation

public enum HelperServiceDescriptor {
  public static let machServiceName = "io.clover.mfancontrol.helper"
  public static let daemonPlistName = "io.clover.mfancontrol.helper.plist"
  public static let protocolVersion = "4"
}

public enum HelperXPCError {
  public static let errorDomain = "io.clover.mfancontrol.helper.xpc"
}

@objc public protocol HelperXPCProtocol {
  func ping(withReply reply: @escaping (String) -> Void)
  func performFanRequest(
    _ requestData: Data,
    withReply reply: @escaping (Data?, NSError?) -> Void
  )
}
