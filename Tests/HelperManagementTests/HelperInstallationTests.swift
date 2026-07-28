import Foundation
import HelperManagement
import HelperProtocol
import Testing

@MainActor
@Suite("Helper installation")
struct HelperInstallationTests {
  @Test("reports not installed when the privileged executable is absent")
  func notInstalled() async {
    let dependencies = FakeInstallationDependencies()
    dependencies.isHelperExecutable = false
    let controller = dependencies.makeController()

    #expect(await controller.refresh() == .notInstalled)
    #expect(dependencies.pingCount == 0)
  }

  @Test("requires a successful XPC ping before reporting connected")
  func connected() async {
    let dependencies = FakeInstallationDependencies()
    dependencies.isHelperExecutable = true
    dependencies.connectionState = .connected(
      protocolVersion: HelperServiceDescriptor.protocolVersion
    )
    let controller = dependencies.makeController()

    #expect(
      await controller.refresh()
        == .connected(protocolVersion: HelperServiceDescriptor.protocolVersion)
    )
    #expect(dependencies.pingCount == 1)
  }

  @Test("requires the bundled helper protocol version")
  func updateRequired() async {
    let dependencies = FakeInstallationDependencies()
    dependencies.isHelperExecutable = true
    dependencies.connectionState = .connected(protocolVersion: "2")
    let controller = dependencies.makeController()

    #expect(
      await controller.refresh()
        == .updateRequired(
          installedVersion: "2",
          requiredVersion: HelperServiceDescriptor.protocolVersion
        )
    )
  }

  @Test("reports an unavailable installed helper with the XPC issue")
  func unavailable() async {
    let dependencies = FakeInstallationDependencies()
    dependencies.isHelperExecutable = true
    dependencies.connectionState = .disconnected(.timedOut)
    let controller = dependencies.makeController()

    #expect(await controller.refresh() == .unavailable(.timedOut))
  }

  @Test("opens the bundled package and waits for Installer")
  func opensInstaller() async {
    let dependencies = FakeInstallationDependencies()
    dependencies.packageURL = URL(fileURLWithPath: "/tmp/MFanControlHelper.pkg")
    let controller = dependencies.makeController()

    #expect(await controller.install() == .waitingForInstaller)
    #expect(dependencies.openedURL == dependencies.packageURL)
  }

  @Test("reports a missing bundled package")
  func packageMissing() async {
    let dependencies = FakeInstallationDependencies()
    dependencies.packageURL = nil
    let controller = dependencies.makeController()

    #expect(await controller.install() == .packageMissing)
    #expect(dependencies.openedURL == nil)
  }

  @Test("reports when macOS refuses to open Installer")
  func installerRefused() async {
    let dependencies = FakeInstallationDependencies()
    dependencies.packageURL = URL(fileURLWithPath: "/tmp/MFanControlHelper.pkg")
    dependencies.openResult = false
    let controller = dependencies.makeController()

    #expect(
      await controller.install()
        == .failed("macOS could not open the helper installer.")
    )
  }

  @Test("reports package opener errors")
  func installerError() async {
    let dependencies = FakeInstallationDependencies()
    dependencies.packageURL = URL(fileURLWithPath: "/tmp/MFanControlHelper.pkg")
    dependencies.openError = TestError.openFailed
    let controller = dependencies.makeController()

    #expect(await controller.install() == .failed("Open failed"))
  }
}

@MainActor
private final class FakeInstallationDependencies {
  var isHelperExecutable = false
  var packageURL: URL?
  var connectionState: HelperConnectionState = .disconnected(.invalidated)
  var openResult = true
  var openError: Error?

  private(set) var openedURL: URL?
  private(set) var pingCount = 0

  func makeController() -> HelperInstallationController {
    HelperInstallationController(
      isHelperExecutable: { [weak self] in
        self?.isHelperExecutable ?? false
      },
      packageURL: { [weak self] in
        self?.packageURL
      },
      openPackage: { [weak self] url in
        guard let self else { return false }
        self.openedURL = url
        if let openError {
          throw openError
        }
        return openResult
      },
      ping: { [weak self] in
        guard let self else { return .disconnected(.cancelledForTest) }
        self.pingCount += 1
        return self.connectionState
      }
    )
  }
}

private enum TestError: LocalizedError {
  case openFailed

  var errorDescription: String? {
    "Open failed"
  }
}

private extension HelperConnectionIssue {
  static var cancelledForTest: Self {
    .failed("Test dependency released")
  }
}
