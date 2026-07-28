import Darwin
import FanProtocol
import Foundation

actor UnixSocketClient {
  private let socketPath: String
  private var descriptor: Int32 = -1
  private var receiveBuffer = Data()

  init(uid: uid_t = getuid()) {
    self.socketPath = SocketAddress.path(for: uid)
  }

  deinit {
    if descriptor >= 0 {
      _ = Darwin.close(descriptor)
    }
  }

  func request(_ request: FanRequest) throws -> FanResponse {
    do {
      try connectIfNeeded()
      let data = try JSONLineCodec.encode(
        request,
        maximumBytes: JSONLineCodec.maximumRequestBytes
      )
      guard writeAll(data) else { throw ControlError.daemonUnavailable }
      let frame = try readFrame()
      let response = try JSONLineCodec.decode(FanResponse.self, from: frame)
      guard response.id == request.id else { throw ControlError.malformedRequest }
      return response
    } catch let error as ControlError {
      disconnect()
      throw error
    } catch {
      disconnect()
      throw ControlError.daemonUnavailable
    }
  }

  func disconnect() {
    guard descriptor >= 0 else { return }
    _ = Darwin.close(descriptor)
    descriptor = -1
    receiveBuffer.removeAll(keepingCapacity: true)
  }

  private func connectIfNeeded() throws {
    guard descriptor < 0 else { return }
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw ControlError.daemonUnavailable }

    var address = sockaddr_un()
    let bytes = Array(socketPath.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
      _ = Darwin.close(fd)
      throw ControlError.daemonUnavailable
    }
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
      buffer.initializeMemory(as: UInt8.self, repeating: 0)
      buffer.copyBytes(from: bytes)
    }

    let result = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard result == 0 else {
      _ = Darwin.close(fd)
      throw ControlError.daemonUnavailable
    }
    descriptor = fd
  }

  private func writeAll(_ data: Data) -> Bool {
    data.withUnsafeBytes { rawBuffer in
      guard let base = rawBuffer.baseAddress else { return true }
      var offset = 0
      while offset < rawBuffer.count {
        let written = Darwin.write(
          descriptor,
          base.advanced(by: offset),
          rawBuffer.count - offset
        )
        if written < 0 {
          if errno == EINTR { continue }
          return false
        }
        offset += written
      }
      return true
    }
  }

  private func readFrame() throws -> Data {
    var chunk = [UInt8](repeating: 0, count: 1_024)
    while true {
      if let newline = receiveBuffer.firstIndex(of: 0x0A) {
        let frame = Data(receiveBuffer[...newline])
        receiveBuffer.removeSubrange(...newline)
        guard frame.count <= JSONLineCodec.maximumMessageBytes + 1 else {
          throw ProtocolError.messageTooLarge
        }
        return frame
      }
      guard receiveBuffer.count <= JSONLineCodec.maximumMessageBytes else {
        throw ProtocolError.messageTooLarge
      }

      let count = Darwin.read(descriptor, &chunk, chunk.count)
      if count == 0 { throw ControlError.daemonUnavailable }
      if count < 0 {
        if errno == EINTR { continue }
        throw ControlError.daemonUnavailable
      }
      receiveBuffer.append(contentsOf: chunk.prefix(count))
    }
  }
}
