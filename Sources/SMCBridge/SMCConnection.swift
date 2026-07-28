import Darwin
import Foundation
import IOKit

package final class SMCConnection: SMCTransport, @unchecked Sendable {
  private enum Command: UInt8 {
    case readBytes = 5
    case writeBytes = 6
    case readKeyInfo = 9
  }

  private static let userClientSelector: UInt32 = 2
  private let connection: io_connect_t

  package init() throws {
    guard let matching = IOServiceMatching("AppleSMC") else {
      throw SMCBridgeError.connectionFailed
    }
    let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
    guard service != 0 else {
      throw SMCBridgeError.connectionFailed
    }
    defer { IOObjectRelease(service) }

    var connection: io_connect_t = 0
    let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
    guard result == kIOReturnSuccess else {
      throw Self.mapIOKit(result)
    }
    self.connection = connection
  }

  deinit {
    IOServiceClose(connection)
  }

  package func readKeyInfo(_ key: String) throws -> SMCKeyInfo {
    var input = SMCParamStruct()
    input.key = try Self.fourCharacterCode(key)
    input.data8 = Command.readKeyInfo.rawValue
    let output = try call(input)
    try Self.checkFirmwareResult(output.result)

    return SMCKeyInfo(
      key: key,
      dataSize: output.keyInfo.dataSize,
      dataType: Self.fourCharacterString(output.keyInfo.dataType),
      attributes: output.keyInfo.dataAttributes
    )
  }

  package func readKey(_ key: String) throws -> SMCReadValue {
    let info = try readKeyInfo(key)
    guard info.dataSize <= 32 else { throw SMCBridgeError.malformedData }

    var input = SMCParamStruct()
    input.key = try Self.fourCharacterCode(key)
    input.keyInfo.dataSize = info.dataSize
    input.data8 = Command.readBytes.rawValue
    let output = try call(input)
    try Self.checkFirmwareResult(output.result)

    let bytes = withUnsafeBytes(of: output.bytes) {
      Array($0.prefix(Int(info.dataSize)))
    }
    return SMCReadValue(info: info, bytes: bytes)
  }

  package func writeKey(_ key: String, bytes: [UInt8]) throws {
    let info = try readKeyInfo(key)
    guard bytes.count == Int(info.dataSize), bytes.count <= 32 else {
      throw SMCBridgeError.sizeMismatch
    }

    var input = SMCParamStruct()
    input.key = try Self.fourCharacterCode(key)
    input.keyInfo.dataSize = info.dataSize
    input.data8 = Command.writeBytes.rawValue
    input.bytes = Self.tuple(from: bytes)
    let output = try call(input)
    try Self.checkFirmwareResult(output.result)
  }

  private func call(_ input: SMCParamStruct) throws -> SMCParamStruct {
    var input = input
    var output = SMCParamStruct()
    var outputSize = MemoryLayout<SMCParamStruct>.stride
    let result = IOConnectCallStructMethod(
      connection,
      Self.userClientSelector,
      &input,
      MemoryLayout<SMCParamStruct>.stride,
      &output,
      &outputSize
    )
    guard result == kIOReturnSuccess else {
      throw Self.mapIOKit(result)
    }
    return output
  }

  private static func fourCharacterCode(_ key: String) throws -> UInt32 {
    let bytes = Array(key.utf8)
    guard bytes.count == 4 else { throw SMCBridgeError.invalidKey }
    return bytes.reduce(0) { ($0 << 8) | UInt32($1) }
  }

  private static func fourCharacterString(_ value: UInt32) -> String {
    let bytes = [
      UInt8(truncatingIfNeeded: value >> 24),
      UInt8(truncatingIfNeeded: value >> 16),
      UInt8(truncatingIfNeeded: value >> 8),
      UInt8(truncatingIfNeeded: value),
    ]
    return String(bytes: bytes, encoding: .ascii) ?? "????"
  }

  private static func checkFirmwareResult(_ result: UInt8) throws {
    switch result {
    case 0:
      return
    case 0x84:
      throw SMCBridgeError.keyMissing
    default:
      throw SMCBridgeError.firmwareRejected(result)
    }
  }

  private static func mapIOKit(_ result: kern_return_t) -> SMCBridgeError {
    if result == kIOReturnNotPrivileged {
      return .notPrivileged
    }
    return .ioKit(result)
  }

  private static func tuple(from bytes: [UInt8]) -> SMCParamStruct.Bytes32 {
    let padded = bytes + Array(repeating: 0, count: 32 - bytes.count)
    return (
      padded[0], padded[1], padded[2], padded[3],
      padded[4], padded[5], padded[6], padded[7],
      padded[8], padded[9], padded[10], padded[11],
      padded[12], padded[13], padded[14], padded[15],
      padded[16], padded[17], padded[18], padded[19],
      padded[20], padded[21], padded[22], padded[23],
      padded[24], padded[25], padded[26], padded[27],
      padded[28], padded[29], padded[30], padded[31]
    )
  }
}
