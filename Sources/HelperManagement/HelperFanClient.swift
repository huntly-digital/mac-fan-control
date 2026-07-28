import FanProtocol
import Foundation
import HelperProtocol

public struct HelperFanClient: Sendable {
  public typealias Operation =
    @Sendable (FanRequest, Duration) async throws -> FanResponse

  private let operation: Operation

  public init(operation: @escaping Operation) {
    self.operation = operation
  }

  public init() {
    let session = HelperFanXPCSession()
    self.operation = { request, timeout in
      try await session.request(request, timeout: timeout)
    }
  }

  public func request(
    _ request: FanRequest,
    timeout: Duration? = nil
  ) async throws -> FanResponse {
    let response = try await operation(request, timeout ?? Self.timeout(for: request.command))
    guard response.id == request.id else {
      throw ControlError.malformedRequest
    }
    return response
  }

  public static func timeout(for command: FanCommand) -> Duration {
    switch command {
    case .hello, .status, .heartbeat:
      return .seconds(3)
    case .setManual:
      return .seconds(30)
    case .setAutomatic, .setAllAutomatic, .shutdown:
      return .seconds(30)
    case .setPreset, .validateHardware:
      return .seconds(240)
    }
  }
}

private final class HelperFanXPCSession: @unchecked Sendable {
  private let lock = NSLock()
  private var connection: NSXPCConnection?

  func request(_ request: FanRequest, timeout: Duration) async throws -> FanResponse {
    let requestData = try JSONLineCodec.encode(
      request,
      maximumBytes: JSONLineCodec.maximumRequestBytes
    )
    let connection = connectionForRequest()

    return try await withCheckedThrowingContinuation { continuation in
      let attempt = HelperFanRequestAttempt(
        continuation: continuation,
        timeout: timeout
      )
      let proxy = connection.remoteObjectProxyWithErrorHandler { error in
        attempt.finish(.failure(error))
      }
      guard let helper = proxy as? HelperXPCProtocol else {
        attempt.finish(.failure(ControlError.daemonUnavailable))
        return
      }
      helper.performFanRequest(requestData) { data, error in
        if let error {
          attempt.finish(.failure(error))
          return
        }
        guard let data else {
          attempt.finish(.failure(ControlError.daemonUnavailable))
          return
        }
        do {
          let response = try JSONLineCodec.decode(FanResponse.self, from: data)
          attempt.finish(.success(response))
        } catch {
          attempt.finish(.failure(error))
        }
      }
    }
  }

  private func connectionForRequest() -> NSXPCConnection {
    lock.withLock {
      if let connection {
        return connection
      }

      let newConnection = NSXPCConnection(
        machServiceName: HelperServiceDescriptor.machServiceName,
        options: .privileged
      )
      newConnection.remoteObjectInterface = NSXPCInterface(with: HelperXPCProtocol.self)
      newConnection.interruptionHandler = { [weak self, weak newConnection] in
        guard let newConnection else { return }
        self?.discard(newConnection)
      }
      newConnection.invalidationHandler = { [weak self, weak newConnection] in
        guard let newConnection else { return }
        self?.discard(newConnection)
      }
      newConnection.activate()
      connection = newConnection
      return newConnection
    }
  }

  private func discard(_ discarded: NSXPCConnection) {
    lock.withLock {
      guard connection === discarded else { return }
      connection = nil
    }
  }
}

private final class HelperFanRequestAttempt: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<FanResponse, Error>?
  private var timeoutTask: Task<Void, Never>?

  init(
    continuation: CheckedContinuation<FanResponse, Error>,
    timeout: Duration
  ) {
    self.continuation = continuation
    self.timeoutTask = Task { [weak self] in
      try? await Task.sleep(for: timeout)
      self?.finish(.failure(ControlError.daemonUnavailable))
    }
  }

  func finish(_ result: Result<FanResponse, Error>) {
    let continuation: CheckedContinuation<FanResponse, Error>? = lock.withLock {
      guard let continuation = self.continuation else { return nil }
      self.continuation = nil
      timeoutTask?.cancel()
      timeoutTask = nil
      return continuation
    }
    continuation?.resume(with: result)
  }
}
