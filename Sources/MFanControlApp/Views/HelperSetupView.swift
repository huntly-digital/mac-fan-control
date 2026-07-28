import HelperManagement
import SwiftUI

struct HelperSetupView: View {
  @ObservedObject var store: HelperStore

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      switch store.state {
      case .notInstalled:
        status(
          title: "Helper is not installed",
          message: "Install the local helper once with the standard macOS Installer.",
          symbol: "shield",
          color: .secondary
        )
        Button("Install Helper") {
          Task { await store.install() }
        }
        .buttonStyle(.borderedProminent)

      case .waitingForInstaller:
        status(
          title: "Finish in Installer",
          message: "Complete the administrator prompt, then check the connection.",
          symbol: "exclamationmark.shield",
          color: .orange
        )
        Button("Check Again") {
          Task { await store.refresh() }
        }
        .buttonStyle(.borderedProminent)

      case .connected(let version):
        status(
          title: "Helper connected",
          message: "Secure service protocol v\(version).",
          symbol: "checkmark.shield",
          color: .green
        )

      case .updateRequired(let installed, let required):
        status(
          title: "Helper update required",
          message: "Installed protocol v\(installed); this app requires v\(required).",
          symbol: "arrow.triangle.2.circlepath.circle",
          color: .orange
        )
        Button("Install Updated Helper") {
          Task { await store.install() }
        }
        .buttonStyle(.borderedProminent)

      case .unavailable(let issue):
        status(
          title: "Helper is installed but unavailable",
          message: issue.message,
          symbol: "exclamationmark.shield",
          color: .orange
        )
        Button("Check Again") {
          Task { await store.refresh() }
        }

      case .packageMissing:
      status(
          title: "Installer package is missing",
          message: "Rebuild MFanControl so its local helper package is embedded.",
          symbol: "xmark.shield",
          color: .red
      )

      case .failed(let message):
        status(
          title: "Could not open Installer",
          message: message,
          symbol: "xmark.shield",
          color: .red
        )
        Button("Try Again") {
          Task { await store.install() }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func status(
    title: String,
    message: String,
    symbol: String,
    color: Color
  ) -> some View {
    HStack(alignment: .top, spacing: 9) {
      Image(systemName: symbol)
        .foregroundStyle(color)
        .font(.title3)
        .frame(width: 22)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.subheadline.weight(.semibold))
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

private extension HelperConnectionIssue {
  var message: String {
    switch self {
    case .interrupted: "The XPC connection was interrupted."
    case .invalidated: "macOS rejected or invalidated the XPC connection."
    case .timedOut: "The helper did not reply in time."
    case .failed(let message): message
    }
  }
}
