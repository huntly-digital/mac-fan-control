import Foundation

public enum ProtocolError: Error, Equatable, Sendable {
  case messageTooLarge
  case invalidJSON
}

public enum JSONLineCodec {
  public static let maximumRequestBytes = 4_096
  public static let maximumMessageBytes = 32_768

  public static func encode<T: Encodable>(
    _ value: T,
    maximumBytes: Int = maximumMessageBytes
  ) throws -> Data {
    var data = try JSONEncoder().encode(value)
    guard data.count <= maximumBytes else {
      throw ProtocolError.messageTooLarge
    }
    data.append(0x0A)
    return data
  }

  public static func decode<T: Decodable>(
    _ type: T.Type,
    from framedData: Data,
    maximumBytes: Int = maximumMessageBytes
  ) throws -> T {
    var data = framedData
    if data.last == 0x0A {
      data.removeLast()
    }
    guard data.count <= maximumBytes else {
      throw ProtocolError.messageTooLarge
    }
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      throw ProtocolError.invalidJSON
    }
  }
}

public enum SocketAddress {
  public static func path(for uid: uid_t) -> String {
    "/var/run/mfancontrol-\(uid).sock"
  }
}
