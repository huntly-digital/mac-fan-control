import Foundation
import HelperProtocol

public enum HelperPingError: Error, Equatable, Sendable {
  case interrupted
  case invalidated
  case cancelled
}

public enum HelperConnectionIssue: Equatable, Sendable {
  case interrupted
  case invalidated
  case timedOut
  case failed(String)
}

public enum HelperConnectionState: Equatable, Sendable {
  case connected(protocolVersion: String)
  case disconnected(HelperConnectionIssue)
}

public struct HelperXPCClient: Sendable {
  public typealias PingOperation = @Sendable (Duration) async throws -> String

  private let operation: PingOperation

  public init(operation: @escaping PingOperation) {
    self.operation = operation
  }

  public init() {
    self.operation = { _ in
      try await PrivilegedXPCPingOperation.call()
    }
  }

  public func ping(timeout: Duration = .seconds(2)) async -> HelperConnectionState {
    do {
      let version = try await withThrowingTaskGroup(of: String.self) { group in
        group.addTask {
          try await operation(timeout)
        }
        group.addTask {
          try await Task.sleep(for: timeout)
          throw TimeoutError()
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else {
          throw HelperPingError.cancelled
        }
        return result
      }
      return .connected(protocolVersion: version)
    } catch is TimeoutError {
      return .disconnected(.timedOut)
    } catch HelperPingError.interrupted {
      return .disconnected(.interrupted)
    } catch HelperPingError.invalidated {
      return .disconnected(.invalidated)
    } catch {
      return .disconnected(.failed(error.localizedDescription))
    }
  }
}

private struct TimeoutError: Error {}

private enum PrivilegedXPCPingOperation {
  static func call() async throws -> String {
    let attempt = XPCPingAttempt()
    return try await withTaskCancellationHandler {
      try await attempt.start()
    } onCancel: {
      attempt.cancel()
    }
  }
}

private final class XPCPingAttempt: @unchecked Sendable {
  private let lock = NSLock()
  private var connection: NSXPCConnection?
  private var continuation: CheckedContinuation<String, Error>?
  private var finished = false

  func start() async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      let connection = NSXPCConnection(
        machServiceName: HelperServiceDescriptor.machServiceName,
        options: .privileged
      )
      connection.remoteObjectInterface = NSXPCInterface(with: HelperXPCProtocol.self)
      connection.interruptionHandler = { [weak self] in
        self?.finish(.failure(HelperPingError.interrupted))
      }
      connection.invalidationHandler = { [weak self] in
        self?.finish(.failure(HelperPingError.invalidated))
      }

      lock.withLock {
        self.connection = connection
        self.continuation = continuation
      }

      connection.resume()
      let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
        self?.finish(.failure(error))
      }
      guard let helper = proxy as? HelperXPCProtocol else {
        finish(.failure(HelperPingError.invalidated))
        return
      }
      helper.ping { [weak self] version in
        self?.finish(.success(version))
      }
    }
  }

  func cancel() {
    finish(.failure(HelperPingError.cancelled))
  }

  private func finish(_ result: Result<String, Error>) {
    let resources: (CheckedContinuation<String, Error>, NSXPCConnection)? = lock.withLock {
      guard !finished, let continuation, let connection else { return nil }
      finished = true
      self.continuation = nil
      self.connection = nil
      return (continuation, connection)
    }
    guard let (continuation, connection) = resources else { return }
    connection.interruptionHandler = nil
    connection.invalidationHandler = nil
    connection.invalidate()
    continuation.resume(with: result)
  }
}
