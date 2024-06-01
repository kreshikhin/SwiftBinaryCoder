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

struct BinaryReader {
    let data: Data
    var index = 0
    var endianness: BinaryEndianness
    var codingPath: [CodingKey] = []

    var isAtEnd: Bool { index >= data.count }
    var remaining: Int { data.count - index }

    mutating func readValue() throws -> BinaryValue {
        let rawTag = try readUInt8()
        guard let tag = BinaryTypeTag(rawValue: rawTag) else {
            throw corrupted("Unknown type tag 0x\(String(rawTag, radix: 16)).")
        }

        switch tag {
        case .null:
            return .null
        case .boolFalse:
            return .bool(false)
        case .boolTrue:
            return .bool(true)
        case .int8:
            return .int(Int64(Int8(bitPattern: try readUInt8())))
        case .int16:
            return .int(Int64(Int16(bitPattern: try readUInt16())))
        case .int32:
            return .int(Int64(Int32(bitPattern: try readUInt32())))
        case .int64:
            return .int(Int64(bitPattern: try readUInt64()))
        case .uint8:
            return .uint(UInt64(try readUInt8()))
        case .uint16:
            return .uint(UInt64(try readUInt16()))
        case .uint32:
            return .uint(UInt64(try readUInt32()))
        case .uint64:
            return .uint(try readUInt64())
        case .float32:
            return .float(Float(bitPattern: try readUInt32()))
        case .float64:
            return .double(Double(bitPattern: try readUInt64()))
        case .str8:
            return .string(try readString(.u8))
        case .str16:
            return .string(try readString(.u16))
        case .str32:
            return .string(try readString(.u32))
        case .bin8:
            return .data(try readBlob(.u8))
        case .bin16:
            return .data(try readBlob(.u16))
        case .bin32:
            return .data(try readBlob(.u32))
        case .array8:
            return try readArray(.u8)
        case .array16:
            return try readArray(.u16)
        case .array32:
            return try readArray(.u32)
        case .map8:
            return try readMap(.u8)
        case .map16:
            return try readMap(.u16)
        case .map32:
            return try readMap(.u32)
        case .timestamp:
            return .timestamp(Double(bitPattern: try readUInt64()))
        case .ext8:
            return try readExtension(.u8)
        case .ext16:
            return try readExtension(.u16)
        case .ext32:
            return try readExtension(.u32)
        }
    }

    private mutating func readArray(_ size: CountSize) throws -> BinaryValue {
        let count = try readCount(size)
        let array = BinaryArray()
        array.elements.reserveCapacity(count)
        for elementIndex in 0..<count {
            codingPath.append(BinaryCodingKey(index: elementIndex))
            array.elements.append(try readValue())
            codingPath.removeLast()
        }
        return .array(array)
    }

    private mutating func readMap(_ size: CountSize) throws -> BinaryValue {
        let count = try readCount(size)
        let map = BinaryMap()
        for _ in 0..<count {
            let key = try readValue()
            let pathKey = BinaryCodingKey(stringValue: mapKeyDescription(key))
            codingPath.append(pathKey)
            let value = try readValue()
            codingPath.removeLast()
            map.set(key: key, value: value)
        }
        return .map(map)
    }

    private mutating func readExtension(_ size: CountSize) throws -> BinaryValue {
        let type = Int8(bitPattern: try readUInt8())
        let payload = try readBlob(size)
        return .ext(type: type, data: payload)
    }

    private func mapKeyDescription(_ key: BinaryValue) -> String {
        switch key.unwrap {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .uint(let value): return String(value)
        default: return key.typeDescription
        }
    }

    private mutating func readString(_ size: CountSize) throws -> String {
        let bytes = try readBlob(size)
        guard let string = String(data: bytes, encoding: .utf8) else {
            throw corrupted("String is not valid UTF-8.")
        }
        return string
    }

    private mutating func readBlob(_ size: CountSize) throws -> Data {
        let count = try readCount(size)
        guard count <= remaining else {
            throw corrupted("Unexpected end of binary data.")
        }
        let start = index
        index += count
        return data.subdata(in: start..<index)
    }

    private enum CountSize {
        case u8, u16, u32
    }

    private mutating func readCount(_ size: CountSize) throws -> Int {
        let raw: UInt64
        switch size {
        case .u8:
            raw = UInt64(try readUInt8())
        case .u16:
            raw = UInt64(try readUInt16())
        case .u32:
            raw = UInt64(try readUInt32())
        }
        guard raw <= UInt64(remaining) else {
            throw corrupted("Length \(raw) exceeds the \(remaining) remaining bytes.")
        }
        return Int(raw)
    }

    mutating func readUInt8() throws -> UInt8 {
        guard index < data.count else {
            throw corrupted("Unexpected end of binary data.")
        }
        let byte = data[index]
        index += 1
        return byte
    }

    mutating func readUInt16() throws -> UInt16 {
        let raw = try readRaw(UInt16.self)
        return endianness == .big ? UInt16(bigEndian: raw) : UInt16(littleEndian: raw)
    }

    mutating func readUInt32() throws -> UInt32 {
        let raw = try readRaw(UInt32.self)
        return endianness == .big ? UInt32(bigEndian: raw) : UInt32(littleEndian: raw)
    }

    mutating func readUInt64() throws -> UInt64 {
        let raw = try readRaw(UInt64.self)
        return endianness == .big ? UInt64(bigEndian: raw) : UInt64(littleEndian: raw)
    }

    private mutating func readRaw<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        let size = MemoryLayout<T>.size
        guard remaining >= size else {
            throw corrupted("Unexpected end of binary data.")
        }
        var value = T()
        _ = withUnsafeMutableBytes(of: &value) { destination in
            data.copyBytes(to: destination, from: index..<(index + size))
        }
        index += size
        return value
    }

    private func corrupted(_ message: String) -> DecodingError {
        DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "\(message) At \(binaryCodingPathDescription(codingPath))."
            )
        )
    }
}
