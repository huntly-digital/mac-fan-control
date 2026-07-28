import Darwin
import FanProtocol
import Foundation

public enum DaemonServerError: Error, LocalizedError, Sendable {
  case socketCreation(Int32)
  case bind(Int32)
  case listen(Int32)
  case accept(Int32)
  case socketPathTooLong

  public var errorDescription: String? {
    switch self {
    case .socketCreation(let code): "socket() failed: \(String(cString: strerror(code)))"
    case .bind(let code): "bind() failed: \(String(cString: strerror(code)))"
    case .listen(let code): "listen() failed: \(String(cString: strerror(code)))"
    case .accept(let code): "accept() failed: \(String(cString: strerror(code)))"
    case .socketPathTooLong: "Unix socket path is too long"
    }
  }
}

public final class DaemonServer: @unchecked Sendable {
  public let socketPath: String

  private let policy: PeerCredentialPolicy
  private let processor: RequestProcessor
  private let stateLock = NSLock()
  private var listener: Int32 = -1
  private var stopping = false

  public init(
    allowedUID: uid_t,
    processor: RequestProcessor,
    socketPath: String? = nil
  ) {
    self.policy = PeerCredentialPolicy(allowedUID: allowedUID)
    self.processor = processor
    self.socketPath = socketPath ?? SocketAddress.path(for: allowedUID)
  }

  deinit {
    requestStop()
  }

  public func run() async throws {
    let fd = try setupListener()
    let monitor = Task { [processor] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }
        await processor.tick()
      }
    }
    defer {
      monitor.cancel()
      requestStop()
      socketPath.withCString { _ = Darwin.unlink($0) }
    }

    try await Task.detached { [self] in
      while !isStopping {
        let client = Darwin.accept(fd, nil, nil)
        if client < 0 {
          let code = errno
          if isStopping { return }
          if code == EINTR { continue }
          throw DaemonServerError.accept(code)
        }
        await handleClient(client)
      }
    }.value
  }

  public func requestStop() {
    let fd: Int32 = stateLock.withLock {
      if stopping { return -1 }
      stopping = true
      let fd = listener
      listener = -1
      return fd
    }
    guard fd >= 0 else { return }
    _ = Darwin.shutdown(fd, SHUT_RDWR)
    _ = Darwin.close(fd)
  }

  private var isStopping: Bool {
    stateLock.withLock { stopping }
  }

  private func setupListener() throws -> Int32 {
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw DaemonServerError.socketCreation(errno) }

    do {
      var address = sockaddr_un()
      let pathBytes = Array(socketPath.utf8)
      guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
        throw DaemonServerError.socketPathTooLong
      }
      address.sun_family = sa_family_t(AF_UNIX)
      address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
      withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        buffer.initializeMemory(as: UInt8.self, repeating: 0)
        buffer.copyBytes(from: pathBytes)
      }

      socketPath.withCString { _ = Darwin.unlink($0) }
      let bindResult = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
      }
      guard bindResult == 0 else { throw DaemonServerError.bind(errno) }
      guard Darwin.chmod(socketPath, 0o600) == 0 else {
        throw DaemonServerError.bind(errno)
      }
      guard Darwin.chown(socketPath, policy.allowedUID, gid_t.max) == 0 else {
        throw DaemonServerError.bind(errno)
      }
      guard Darwin.listen(fd, 1) == 0 else { throw DaemonServerError.listen(errno) }

      stateLock.withLock {
        listener = fd
        stopping = false
      }
      return fd
    } catch {
      _ = Darwin.close(fd)
      socketPath.withCString { _ = Darwin.unlink($0) }
      throw error
    }
  }

  private func handleClient(_ fd: Int32) async {
    defer { _ = Darwin.close(fd) }

    var peerUID: uid_t = 0
    var peerGID: gid_t = 0
    guard getpeereid(fd, &peerUID, &peerGID) == 0, policy.accepts(peerUID: peerUID) else {
      return
    }

    await runAuthorizedClient(fd)
    await processor.handleDisconnect()
  }

  private func runAuthorizedClient(_ fd: Int32) async {
    var buffer = Data()
    var chunk = [UInt8](repeating: 0, count: 1_024)

    while !isStopping {
      let count = Darwin.read(fd, &chunk, chunk.count)
      if count == 0 { return }
      if count < 0 {
        if errno == EINTR { continue }
        return
      }
      buffer.append(contentsOf: chunk.prefix(count))

      while let newline = buffer.firstIndex(of: 0x0A) {
        let frame = Data(buffer[...newline])
        buffer.removeSubrange(...newline)
        guard frame.count <= JSONLineCodec.maximumMessageBytes + 1 else { return }

        let result: DaemonResult
        do {
          let request = try JSONLineCodec.decode(FanRequest.self, from: frame)
          result = await processor.handle(request)
        } catch {
          result = DaemonResult(
            response: FanResponse(
              id: "",
              ok: false,
              error: .malformedRequest,
              message: ControlError.malformedRequest.localizedDescription
            )
          )
        }

        guard let response = try? JSONLineCodec.encode(result.response),
          writeAll(response, to: fd)
        else { return }

        if result.shouldShutdown {
          requestStop()
          return
        }
      }

      if buffer.count > JSONLineCodec.maximumMessageBytes {
        return
      }
    }
  }

  private func writeAll(_ data: Data, to fd: Int32) -> Bool {
    data.withUnsafeBytes { rawBuffer in
      guard let base = rawBuffer.baseAddress else { return true }
      var offset = 0
      while offset < rawBuffer.count {
        let written = Darwin.write(fd, base.advanced(by: offset), rawBuffer.count - offset)
        if written < 0 {
          if errno == EINTR { continue }
          return false
        }
        offset += written
      }
      return true
    }
  }
}
