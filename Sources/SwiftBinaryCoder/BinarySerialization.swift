import Foundation

struct BinaryWriter {
    var data = Data()
    var endianness: BinaryEndianness
    var codingPath: [CodingKey] = []

    mutating func write(_ value: BinaryValue) throws {
        switch value.unwrap {
        case .null:
            writeUInt8(BinaryTypeTag.null.rawValue)
        case .bool(let flag):
            writeUInt8((flag ? BinaryTypeTag.boolTrue : BinaryTypeTag.boolFalse).rawValue)
        case .int(let number):
            try writeInt(number)
        case .uint(let number):
            try writeUInt(number)
        case .float(let number):
            writeUInt8(BinaryTypeTag.float32.rawValue)
            writeUInt32(number.bitPattern)
        case .double(let number):
            writeUInt8(BinaryTypeTag.float64.rawValue)
            writeUInt64(number.bitPattern)
        case .string(let string):
            try writeString(string)
        case .data(let payload):
            try writeBinary(payload)
        case .array(let array):
            try writeArray(array)
        case .map(let map):
            try writeMap(map)
        case .timestamp(let seconds):
            writeUInt8(BinaryTypeTag.timestamp.rawValue)
            writeUInt64(seconds.bitPattern)
        case .ext(let type, let payload):
            try writeExtension(type: type, data: payload)
        case .slot:
            preconditionFailure("Slots are unwrapped before writing.")
        }
    }

    private mutating func writeInt(_ value: Int64) throws {
        if value >= Int64(Int8.min) && value <= Int64(Int8.max) {
            writeUInt8(BinaryTypeTag.int8.rawValue)
            writeUInt8(UInt8(bitPattern: Int8(value)))
        } else if value >= Int64(Int16.min) && value <= Int64(Int16.max) {
            writeUInt8(BinaryTypeTag.int16.rawValue)
            writeUInt16(UInt16(bitPattern: Int16(value)))
        } else if value >= Int64(Int32.min) && value <= Int64(Int32.max) {
            writeUInt8(BinaryTypeTag.int32.rawValue)
            writeUInt32(UInt32(bitPattern: Int32(value)))
        } else {
            writeUInt8(BinaryTypeTag.int64.rawValue)
            writeUInt64(UInt64(bitPattern: value))
        }
    }

    private mutating func writeUInt(_ value: UInt64) throws {
        if value <= UInt64(UInt8.max) {
            writeUInt8(BinaryTypeTag.uint8.rawValue)
            writeUInt8(UInt8(value))
        } else if value <= UInt64(UInt16.max) {
            writeUInt8(BinaryTypeTag.uint16.rawValue)
            writeUInt16(UInt16(value))
        } else if value <= UInt64(UInt32.max) {
            writeUInt8(BinaryTypeTag.uint32.rawValue)
            writeUInt32(UInt32(value))
        } else {
            writeUInt8(BinaryTypeTag.uint64.rawValue)
            writeUInt64(value)
        }
    }

    private mutating func writeString(_ string: String) throws {
        let bytes = Data(string.utf8)
        switch try countWidth(bytes.count) {
        case .u8(let count):
            writeUInt8(BinaryTypeTag.str8.rawValue)
            writeUInt8(count)
        case .u16(let count):
            writeUInt8(BinaryTypeTag.str16.rawValue)
            writeUInt16(count)
        case .u32(let count):
            writeUInt8(BinaryTypeTag.str32.rawValue)
            writeUInt32(count)
        }
        data.append(bytes)
    }

    private mutating func writeBinary(_ payload: Data) throws {
        switch try countWidth(payload.count) {
        case .u8(let count):
            writeUInt8(BinaryTypeTag.bin8.rawValue)
            writeUInt8(count)
        case .u16(let count):
            writeUInt8(BinaryTypeTag.bin16.rawValue)
            writeUInt16(count)
        case .u32(let count):
            writeUInt8(BinaryTypeTag.bin32.rawValue)
            writeUInt32(count)
        }
        data.append(payload)
    }

    private mutating func writeArray(_ array: BinaryArray) throws {
        switch try countWidth(array.elements.count) {
        case .u8(let count):
            writeUInt8(BinaryTypeTag.array8.rawValue)
            writeUInt8(count)
        case .u16(let count):
            writeUInt8(BinaryTypeTag.array16.rawValue)
            writeUInt16(count)
        case .u32(let count):
            writeUInt8(BinaryTypeTag.array32.rawValue)
            writeUInt32(count)
        }
        for (index, element) in array.elements.enumerated() {
            codingPath.append(BinaryCodingKey(index: index))
            try write(element)
            codingPath.removeLast()
        }
    }

    private mutating func writeMap(_ map: BinaryMap) throws {
        switch try countWidth(map.fields.count) {
        case .u8(let count):
            writeUInt8(BinaryTypeTag.map8.rawValue)
            writeUInt8(count)
        case .u16(let count):
            writeUInt8(BinaryTypeTag.map16.rawValue)
            writeUInt16(count)
        case .u32(let count):
            writeUInt8(BinaryTypeTag.map32.rawValue)
            writeUInt32(count)
        }
        for field in map.fields {
            try write(field.key)
            codingPath.append(BinaryCodingKey(stringValue: mapKeyDescription(field.key)))
            try write(field.value)
            codingPath.removeLast()
        }
    }

    private mutating func writeExtension(type: Int8, data payload: Data) throws {
        switch try countWidth(payload.count) {
        case .u8(let count):
            writeUInt8(BinaryTypeTag.ext8.rawValue)
            writeUInt8(UInt8(bitPattern: type))
            writeUInt8(count)
        case .u16(let count):
            writeUInt8(BinaryTypeTag.ext16.rawValue)
            writeUInt8(UInt8(bitPattern: type))
            writeUInt16(count)
        case .u32(let count):
            writeUInt8(BinaryTypeTag.ext32.rawValue)
            writeUInt8(UInt8(bitPattern: type))
            writeUInt32(count)
        }
        data.append(payload)
    }

    private func mapKeyDescription(_ key: BinaryValue) -> String {
        switch key.unwrap {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .uint(let value): return String(value)
        default: return key.typeDescription
        }
    }

    mutating func writeUInt8(_ value: UInt8) {
        data.append(value)
    }

    mutating func writeUInt16(_ value: UInt16) {
        append(endianness == .big ? value.bigEndian : value.littleEndian)
    }

    mutating func writeUInt32(_ value: UInt32) {
        append(endianness == .big ? value.bigEndian : value.littleEndian)
    }

    mutating func writeUInt64(_ value: UInt64) {
        append(endianness == .big ? value.bigEndian : value.littleEndian)
    }

    private mutating func append<T: FixedWidthInteger>(_ value: T) {
        withUnsafeBytes(of: value) { data.append(contentsOf: $0) }
    }

    private enum CountWidth {
        case u8(UInt8)
        case u16(UInt16)
        case u32(UInt32)
    }

    private func countWidth(_ count: Int) throws -> CountWidth {
        guard count >= 0, count <= Int(UInt32.max) else {
            throw EncodingError.invalidValue(
                count,
                EncodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Length \(count) does not fit in UInt32 at \(binaryCodingPathDescription(codingPath))."
                )
            )
        }
        if count <= Int(UInt8.max) {
            return .u8(UInt8(count))
        }
        if count <= Int(UInt16.max) {
            return .u16(UInt16(count))
        }
        return .u32(UInt32(count))
    }
}
