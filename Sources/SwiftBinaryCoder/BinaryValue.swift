import Foundation

/// Tags for the binary Codable format.
///
/// A value is null, a boolean, a signed or unsigned integer, float32, float64,
/// a UTF-8 string, raw bytes, an array, a map, a timestamp, or a typed
/// extension blob. Lengths use the smallest of 8, 16, or 32 bits that fits,
/// and integers use the smallest width that fits. Multi-byte numbers use
/// the endianness selected on the encoder. The default is big-endian.
///
/// ```
/// 0x00        null
/// 0x01        false
/// 0x02        true
/// 0x03..0x06  int8 / int16 / int32 / int64
/// 0x07..0x0A  uint8 / uint16 / uint32 / uint64
/// 0x0B        float32
/// 0x0C        float64
/// 0x0D..0x0F  str8 / str16 / str32          length + UTF-8
/// 0x10..0x12  bin8 / bin16 / bin32          length + bytes
/// 0x13..0x15  array8 / array16 / array32    count + values
/// 0x16..0x18  map8 / map16 / map32          count + (key, value) pairs
/// 0x19        timestamp                     float64 seconds since 1970
/// 0x1A..0x1C  ext8 / ext16 / ext32          int8 type + length + bytes
/// ```
///
/// Map keys are themselves values. Keyed containers write a string, or an
/// integer when the coding key is an integer key.
enum BinaryTypeTag: UInt8 {
    case null = 0x00
    case boolFalse = 0x01
    case boolTrue = 0x02

    case int8 = 0x03
    case int16 = 0x04
    case int32 = 0x05
    case int64 = 0x06

    case uint8 = 0x07
    case uint16 = 0x08
    case uint32 = 0x09
    case uint64 = 0x0A

    case float32 = 0x0B
    case float64 = 0x0C

    case str8 = 0x0D
    case str16 = 0x0E
    case str32 = 0x0F

    case bin8 = 0x10
    case bin16 = 0x11
    case bin32 = 0x12

    case array8 = 0x13
    case array16 = 0x14
    case array32 = 0x15

    case map8 = 0x16
    case map16 = 0x17
    case map32 = 0x18

    case timestamp = 0x19

    case ext8 = 0x1A
    case ext16 = 0x1B
    case ext32 = 0x1C
}

/// Filled by a nested encoder after `superEncoder()` inserts it into the parent.
final class BinarySlot {
    var value: BinaryValue

    init(_ value: BinaryValue = .map(BinaryMap())) {
        self.value = value
    }
}

final class BinaryArray {
    var elements: [BinaryValue] = []
}

final class BinaryMap {
    struct Field {
        var key: BinaryValue
        var value: BinaryValue
    }

    private(set) var fields: [Field] = []

    func set(key: BinaryValue, value: BinaryValue) {
        if let index = fields.firstIndex(where: { Self.sameKey($0.key, key) }) {
            fields[index].value = value
        } else {
            fields.append(Field(key: key, value: value))
        }
    }

    static func sameKey(_ lhs: BinaryValue, _ rhs: BinaryValue) -> Bool {
        switch (lhs.unwrap, rhs.unwrap) {
        case (.string(let left), .string(let right)):
            return left == right
        case (.int(let left), .int(let right)):
            return left == right
        case (.uint(let left), .uint(let right)):
            return left == right
        case (.int(let left), .uint(let right)):
            return left >= 0 && UInt64(left) == right
        case (.uint(let left), .int(let right)):
            return right >= 0 && left == UInt64(right)
        default:
            return false
        }
    }
}

enum BinaryValue {
    case null
    case bool(Bool)
    /// Signed integer. The writer stores the narrowest signed width that fits.
    case int(Int64)
    /// Unsigned integer. The writer stores the narrowest unsigned width that fits.
    case uint(UInt64)
    case float(Float)
    case double(Double)
    case string(String)
    case data(Data)
    case array(BinaryArray)
    case map(BinaryMap)
    /// Seconds since 1970-01-01T00:00:00Z.
    case timestamp(Double)
    case ext(type: Int8, data: Data)
    case slot(BinarySlot)

    var isNull: Bool {
        if case .null = unwrap { return true }
        return false
    }

    var unwrap: BinaryValue {
        var current = self
        while case .slot(let slot) = current {
            current = slot.value
        }
        return current
    }

    var typeDescription: String {
        switch unwrap {
        case .null: return "null"
        case .bool: return "bool"
        case .int: return "int"
        case .uint: return "uint"
        case .float: return "float32"
        case .double: return "float64"
        case .string: return "string"
        case .data: return "binary"
        case .array: return "array"
        case .map: return "map"
        case .timestamp: return "timestamp"
        case .ext: return "ext"
        case .slot: return "slot"
        }
    }
}
