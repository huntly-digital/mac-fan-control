import HelperProtocol
import Testing

@Suite("Helper XPC protocol")
struct HelperProtocolTests {
  @Test("uses a stable privileged Mach service identity")
  func stableServiceIdentity() {
    #expect(HelperServiceDescriptor.machServiceName == "io.clover.mfancontrol.helper")
    #expect(HelperServiceDescriptor.daemonPlistName == "io.clover.mfancontrol.helper.plist")
  }

  @Test("fan request transport uses protocol version three")
  func fanRequestProtocolVersion() {
    #expect(HelperServiceDescriptor.protocolVersion == "3")
  }
}
