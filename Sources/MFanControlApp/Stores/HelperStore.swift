import AppKit
import Combine
import Foundation
import HelperManagement

@MainActor
final class HelperStore: ObservableObject {
  @Published private(set) var state: HelperInstallationState

  private let controller: HelperInstallationController

  init(
    fileManager: FileManager = .default,
    bundle: Bundle = .main,
    client: HelperXPCClient = HelperXPCClient()
  ) {
    let controller = HelperInstallationController(
      isHelperExecutable: {
        fileManager.isExecutableFile(
          atPath: HelperInstallationDescriptor.installedHelperPath
        )
      },
      packageURL: {
        bundle.url(
          forResource: HelperInstallationDescriptor.packageResourceName,
          withExtension: HelperInstallationDescriptor.packageResourceExtension
        )
      },
      openPackage: { packageURL in
        NSWorkspace.shared.open(packageURL)
      },
      ping: {
        await client.ping()
      }
    )
    self.controller = controller
    self.state = controller.state
  }

  func refresh() async {
    state = await controller.refresh()
  }

  func install() async {
    state = await controller.install()
  }
}
