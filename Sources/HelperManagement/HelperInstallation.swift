import Foundation
import HelperProtocol

public enum HelperInstallationDescriptor {
  public static let installedHelperPath =
    "/Library/PrivilegedHelperTools/io.clover.mfancontrol.helper"
  public static let packageResourceName = "MFanControlHelper"
  public static let packageResourceExtension = "pkg"
}

public enum HelperInstallationState: Equatable, Sendable {
  case notInstalled
  case waitingForInstaller
  case connected(protocolVersion: String)
  case updateRequired(installedVersion: String, requiredVersion: String)
  case unavailable(HelperConnectionIssue)
  case packageMissing
  case failed(String)
}

@MainActor
public final class HelperInstallationController {
  public typealias ExecutableCheck = @MainActor () -> Bool
  public typealias PackageURLProvider = @MainActor () -> URL?
  public typealias PackageOpener = @MainActor (URL) throws -> Bool
  public typealias PingOperation = @MainActor () async -> HelperConnectionState

  private let isHelperExecutable: ExecutableCheck
  private let packageURL: PackageURLProvider
  private let openPackage: PackageOpener
  private let ping: PingOperation

  public private(set) var state: HelperInstallationState = .notInstalled

  public init(
    isHelperExecutable: @escaping ExecutableCheck,
    packageURL: @escaping PackageURLProvider,
    openPackage: @escaping PackageOpener,
    ping: @escaping PingOperation
  ) {
    self.isHelperExecutable = isHelperExecutable
    self.packageURL = packageURL
    self.openPackage = openPackage
    self.ping = ping
  }

  @discardableResult
  public func refresh() async -> HelperInstallationState {
    guard isHelperExecutable() else {
      state = .notInstalled
      return state
    }

    switch await ping() {
    case .connected(let protocolVersion):
      if protocolVersion == HelperServiceDescriptor.protocolVersion {
        state = .connected(protocolVersion: protocolVersion)
      } else {
        state = .updateRequired(
          installedVersion: protocolVersion,
          requiredVersion: HelperServiceDescriptor.protocolVersion
        )
      }
    case .disconnected(let issue):
      state = .unavailable(issue)
    }
    return state
  }

  @discardableResult
  public func install() async -> HelperInstallationState {
    guard let packageURL = packageURL() else {
      state = .packageMissing
      return state
    }

    do {
      guard try openPackage(packageURL) else {
        state = .failed("macOS could not open the helper installer.")
        return state
      }
      state = .waitingForInstaller
    } catch {
      state = .failed(error.localizedDescription)
    }
    return state
  }
}
