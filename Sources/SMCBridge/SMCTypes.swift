import Foundation
import IOKit

public enum SMCBridgeError: Error, Equatable, Sendable {
  case connectionFailed
  case invalidKey
  case keyMissing
  case notPrivileged
  case firmwareRejected(UInt8)
  case sizeMismatch
  case unsupportedDataType(String)
  case malformedData
  case ioKit(Int32)
}

extension SMCBridgeError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .connectionFailed: "Could not open AppleSMC"
    case .invalidKey: "SMC keys must contain exactly four ASCII bytes"
    case .keyMissing: "SMC key not found"
    case .notPrivileged: "SMC write requires root privileges"
    case .firmwareRejected(let code):
      "SMC firmware rejected the command (0x\(String(code, radix: 16)))"
    case .sizeMismatch: "SMC value size does not match key metadata"
    case .unsupportedDataType(let type): "Unsupported SMC data type: \(type)"
    case .malformedData: "SMC returned malformed data"
    case .ioKit(let code): "IOKit error: 0x\(String(UInt32(bitPattern: code), radix: 16))"
    }
  }
}

public struct SMCKeyInfo: Equatable, Sendable {
  public let key: String
  public let dataSize: UInt32
  public let dataType: String
  public let attributes: UInt8

  public init(key: String, dataSize: UInt32, dataType: String, attributes: UInt8) {
    self.key = key
    self.dataSize = dataSize
    self.dataType = dataType
    self.attributes = attributes
  }
}

public struct SMCReadValue: Equatable, Sendable {
  public let info: SMCKeyInfo
  public let bytes: [UInt8]

  public init(info: SMCKeyInfo, bytes: [UInt8]) {
    self.info = info
    self.bytes = bytes
  }
}

public struct SMCParamStruct {
  public typealias Bytes32 = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
  )

  public struct Version {
    public var major: UInt8 = 0
    public var minor: UInt8 = 0
    public var build: UInt8 = 0
    public var reserved: UInt8 = 0
    public var release: UInt16 = 0
    public init() {}
  }

  public struct PLimitData {
    public var version: UInt16 = 0
    public var length: UInt16 = 0
    public var cpuPLimit: UInt32 = 0
    public var gpuPLimit: UInt32 = 0
    public var memPLimit: UInt32 = 0
    public init() {}
  }

  public struct KeyInfo {
    public var dataSize: UInt32 = 0
    public var dataType: UInt32 = 0
    public var dataAttributes: UInt8 = 0
    public init() {}
  }

  public var key: UInt32 = 0
  public var vers = Version()
  public var pLimitData = PLimitData()
  public var keyInfo = KeyInfo()
  public var padding: UInt16 = 0
  public var result: UInt8 = 0
  public var status: UInt8 = 0
  public var data8: UInt8 = 0
  public var data32: UInt32 = 0
  public var bytes: Bytes32 = (
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  )

  public init() {}
}

package protocol SMCTransport: Sendable {
  func readKeyInfo(_ key: String) throws -> SMCKeyInfo
  func readKey(_ key: String) throws -> SMCReadValue
  func writeKey(_ key: String, bytes: [UInt8]) throws
}
