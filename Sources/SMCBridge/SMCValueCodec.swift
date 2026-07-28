import Foundation

public enum SMCValueCodec {
  public static func decodeTemperature(bytes: [UInt8], dataType: String) throws -> Double {
    let value: Double
    switch dataType {
    case "flt ":
      guard bytes.count == 4 else { throw SMCBridgeError.malformedData }
      let bits =
        UInt32(bytes[0])
        | UInt32(bytes[1]) << 8
        | UInt32(bytes[2]) << 16
        | UInt32(bytes[3]) << 24
      value = Double(Float(bitPattern: bits))
    case "sp78":
      guard bytes.count == 2 else { throw SMCBridgeError.malformedData }
      let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
      value = Double(raw) / 256
    default:
      throw SMCBridgeError.unsupportedDataType(dataType)
    }

    guard value.isFinite, (-40...150).contains(value) else {
      throw SMCBridgeError.malformedData
    }
    return value
  }

  public static func decodeRPM(bytes: [UInt8], dataType: String) throws -> Double {
    switch dataType {
    case "flt ":
      guard bytes.count == 4 else { throw SMCBridgeError.malformedData }
      let bits =
        UInt32(bytes[0])
        | UInt32(bytes[1]) << 8
        | UInt32(bytes[2]) << 16
        | UInt32(bytes[3]) << 24
      return Double(Float(bitPattern: bits))
    case "fpe2":
      guard bytes.count == 2 else { throw SMCBridgeError.malformedData }
      let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
      return Double(raw) / 4.0
    default:
      throw SMCBridgeError.unsupportedDataType(dataType)
    }
  }

  public static func encodeRPM(_ value: Double, dataType: String) throws -> [UInt8] {
    switch dataType {
    case "flt ":
      let bits = Float(value).bitPattern
      return [
        UInt8(truncatingIfNeeded: bits),
        UInt8(truncatingIfNeeded: bits >> 8),
        UInt8(truncatingIfNeeded: bits >> 16),
        UInt8(truncatingIfNeeded: bits >> 24),
      ]
    case "fpe2":
      let raw = UInt16((value * 4).rounded())
      return [UInt8(raw >> 8), UInt8(truncatingIfNeeded: raw)]
    default:
      throw SMCBridgeError.unsupportedDataType(dataType)
    }
  }

  public static func decodeUnsigned(_ bytes: [UInt8]) throws -> UInt32 {
    switch bytes.count {
    case 1:
      return UInt32(bytes[0])
    case 2:
      return UInt32(bytes[0]) << 8 | UInt32(bytes[1])
    case 4:
      return UInt32(bytes[0]) << 24
        | UInt32(bytes[1]) << 16
        | UInt32(bytes[2]) << 8
        | UInt32(bytes[3])
    default:
      throw SMCBridgeError.malformedData
    }
  }
}
