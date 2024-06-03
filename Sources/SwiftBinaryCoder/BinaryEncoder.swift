import Foundation

/// Encodes `Encodable` values into a compact binary document.
///
/// A document can hold null, booleans, integers, floats, UTF-8 strings, raw
/// bytes, arrays, maps, timestamps, and extension blobs. Any type that already
/// adopts `Codable` can be encoded without a separate schema.
///
/// ```swift
/// struct Player: Codable {
///     var name: String
///     var score: Int
///     var avatar: Data
/// }
///
/// let data = try BinaryEncoder().encode(player)
/// let copy = try BinaryDecoder().decode(Player.self, from: data)
/// ```
///
/// Integers and collection lengths are stored in the smallest width that fits.
/// `Int` is a signed integer and `UInt` is an unsigned integer. `String` and
/// `Data` stay distinct. `Date` is a timestamp unless a date strategy says
/// otherwise. ``BinaryExtension`` and types that adopt ``BinaryExtensible``
/// are extension blobs.
public final class BinaryEncoder {
    /// Byte order of multi-byte numbers. The default is ``BinaryEndianness/big``.
    public var endianness: BinaryEndianness = .big

    /// How `Date` values are written. The default is ``DateEncodingStrategy/timestamp``.
    public var dateEncodingStrategy: DateEncodingStrategy = .timestamp

    /// How `Data` values are written. The default is ``DataEncodingStrategy/binary``.
    public var dataEncodingStrategy: DataEncodingStrategy = .binary

    /// How NaN and infinities are written. The default keeps the IEEE 754 bits.
    public var nonConformingFloatEncodingStrategy: NonConformingFloatEncodingStrategy = .passThrough

    /// How coding keys are turned into map keys. The default keeps the key text.
    public var keyEncodingStrategy: KeyEncodingStrategy = .useDefaultKeys

    /// Context made available to types while they encode.
    public var userInfo: [CodingUserInfoKey: Any] = [:]

    public init() {}

    /// Returns the binary encoding of `value`.
    public func encode<T: Encodable>(_ value: T) throws -> Data {
        let options = Options(self)
        let encoder = _BinaryEncoder(options: options, codingPath: [])
        let boxed = try encoder.box(value, codingPath: [])
        var writer = BinaryWriter(endianness: options.endianness)
        try writer.write(boxed)
        return writer.data
    }

    /// Strategies for encoding `Date`.
    public enum DateEncodingStrategy {
        /// A timestamp value: float64 seconds since 1970-01-01T00:00:00Z.
        /// This is the default.
        case timestamp
        /// Let `Date` encode itself. That writes `timeIntervalSinceReferenceDate` as a float64.
        case deferredToDate
        /// A float64 count of seconds since 1970-01-01T00:00:00Z.
        case secondsSince1970
        /// A float64 count of milliseconds since 1970-01-01T00:00:00Z.
        case millisecondsSince1970
        /// An ISO 8601 string.
        case iso8601
        /// Encode the date with a closure. An empty closure writes an empty map.
        case custom((_ date: Date, _ encoder: Encoder) throws -> Void)
    }

    /// Strategies for encoding `Data`.
    public enum DataEncodingStrategy {
        /// A binary blob. This is the default.
        case binary
        /// A Base64 string.
        case base64
        /// Let `Data` encode itself. That writes an array of bytes.
        case deferredToData
        /// Encode the bytes with a closure. An empty closure writes an empty map.
        case custom((_ data: Data, _ encoder: Encoder) throws -> Void)
    }

    /// Strategies for values that are not finite.
    public enum NonConformingFloatEncodingStrategy {
        /// Write the IEEE 754 bit pattern, including NaN and infinities. This is the default.
        case passThrough
        /// Throw `EncodingError.invalidValue`.
        case `throw`
        /// Write one of the given strings instead of a float.
        case convertToString(positiveInfinity: String, negativeInfinity: String, nan: String)
    }

    /// Strategies for converting coding keys into map keys.
    public enum KeyEncodingStrategy {
        /// Use `CodingKey.stringValue` unchanged. Integer coding keys are written as integers.
        case useDefaultKeys
        /// Convert camelCase keys to snake_case, using the same rules as `JSONEncoder`.
        case convertToSnakeCase
        /// Replace the key about to be written. The closure receives the full coding path.
        case custom((_ codingPath: [CodingKey]) -> CodingKey)
    }

    struct Options {
        var endianness: BinaryEndianness
        var dateEncodingStrategy: DateEncodingStrategy
        var dataEncodingStrategy: DataEncodingStrategy
        var nonConformingFloatEncodingStrategy: NonConformingFloatEncodingStrategy
        var keyEncodingStrategy: KeyEncodingStrategy
        var userInfo: [CodingUserInfoKey: Any]

        init(_ encoder: BinaryEncoder) {
            endianness = encoder.endianness
            dateEncodingStrategy = encoder.dateEncodingStrategy
            dataEncodingStrategy = encoder.dataEncodingStrategy
            nonConformingFloatEncodingStrategy = encoder.nonConformingFloatEncodingStrategy
            keyEncodingStrategy = encoder.keyEncodingStrategy
            userInfo = encoder.userInfo
        }
    }
}

enum BinaryDateFormat {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        fractional.timeZone = TimeZone(secondsFromGMT: 0)
        if let date = fractional.date(from: string) {
            return date
        }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        basic.timeZone = TimeZone(secondsFromGMT: 0)
        return basic.date(from: string)
    }
}

final class _BinaryEncoder: Encoder {
    var codingPath: [CodingKey]
    let options: BinaryEncoder.Options
    var userInfo: [CodingUserInfoKey: Any] { options.userInfo }
    private(set) var storage: [BinaryValue] = []
    private var didClaimContainer = false
    let slot: BinarySlot?

    init(options: BinaryEncoder.Options, codingPath: [CodingKey], slot: BinarySlot? = nil) {
        self.options = options
        self.codingPath = codingPath
        self.slot = slot
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        let map = BinaryMap()
        openContainer(.map(map))
        return KeyedEncodingContainer(
            _BinaryKeyedEncodingContainer(encoder: self, map: map, codingPath: codingPath)
        )
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        let array = BinaryArray()
        openContainer(.array(array))
        return _BinaryUnkeyedEncodingContainer(encoder: self, array: array, codingPath: codingPath)
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        precondition(
            !didClaimContainer,
            "Attempted to encode a value with multiple containers at \(binaryCodingPathDescription(codingPath))."
        )
        didClaimContainer = true
        return _BinarySingleValueEncodingContainer(encoder: self)
    }

    func openContainer(_ value: BinaryValue) {
        precondition(
            !didClaimContainer,
            "Attempted to encode a value with multiple containers at \(binaryCodingPathDescription(codingPath))."
        )
        didClaimContainer = true
        store(value)
    }

    func store(_ value: BinaryValue) {
        precondition(
            storage.isEmpty,
            "Attempted to encode multiple values in one container at \(binaryCodingPathDescription(codingPath))."
        )
        storage.append(value)
        slot?.value = value
    }

    func box<T: Encodable>(_ value: T, codingPath: [CodingKey]) throws -> BinaryValue {
        if let direct = try directValue(value, codingPath: codingPath) {
            return direct
        }
        let nested = _BinaryEncoder(options: options, codingPath: codingPath)
        try value.encode(to: nested)
        guard let stored = nested.storage.first else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "\(T.self) did not encode any values at \(binaryCodingPathDescription(codingPath))."
                )
            )
        }
        return stored
    }

    private func directValue<T: Encodable>(_ value: T, codingPath: [CodingKey]) throws -> BinaryValue? {
        if T.self == Bool.self { return .bool(value as! Bool) }
        if T.self == String.self { return .string(value as! String) }
        if T.self == Int.self { return .int(Int64(value as! Int)) }
        if T.self == Int8.self { return .int(Int64(value as! Int8)) }
        if T.self == Int16.self { return .int(Int64(value as! Int16)) }
        if T.self == Int32.self { return .int(Int64(value as! Int32)) }
        if T.self == Int64.self { return .int(value as! Int64) }
        if T.self == UInt.self { return .uint(UInt64(value as! UInt)) }
        if T.self == UInt8.self { return .uint(UInt64(value as! UInt8)) }
        if T.self == UInt16.self { return .uint(UInt64(value as! UInt16)) }
        if T.self == UInt32.self { return .uint(UInt64(value as! UInt32)) }
        if T.self == UInt64.self { return .uint(value as! UInt64) }
        if T.self == Float.self { return try boxFloat(value as! Float, codingPath: codingPath) }
        if T.self == Double.self { return try boxDouble(value as! Double, codingPath: codingPath) }
        if T.self == Date.self { return try boxDate(value as! Date, codingPath: codingPath) }
        if T.self == Data.self { return try boxData(value as! Data, codingPath: codingPath) }
        if T.self == URL.self { return .string((value as! URL).absoluteString) }
        if T.self == BinaryExtension.self {
            let ext = value as! BinaryExtension
            return .ext(type: ext.type, data: ext.data)
        }
        if let packed = value as? any BinaryExtensible {
            return binaryExtValue(packed)
        }
        return nil
    }

    private func binaryExtValue<T: BinaryExtensible>(_ value: T) -> BinaryValue {
        .ext(type: T.binaryExtType, data: value.binaryExtData)
    }

    func boxFloat(_ value: Float, codingPath: [CodingKey]) throws -> BinaryValue {
        switch options.nonConformingFloatEncodingStrategy {
        case .passThrough:
            return .float(value)
        case .throw:
            guard value.isFinite else {
                throw EncodingError.invalidValue(
                    value,
                    EncodingError.Context(
                        codingPath: codingPath,
                        debugDescription: "Unable to encode non-finite Float \(value)."
                    )
                )
            }
            return .float(value)
        case .convertToString(let positive, let negative, let nan):
            if value.isNaN { return .string(nan) }
            if value == .infinity { return .string(positive) }
            if value == -.infinity { return .string(negative) }
            return .float(value)
        }
    }

    func boxDouble(_ value: Double, codingPath: [CodingKey]) throws -> BinaryValue {
        switch options.nonConformingFloatEncodingStrategy {
        case .passThrough:
            return .double(value)
        case .throw:
            guard value.isFinite else {
                throw EncodingError.invalidValue(
                    value,
                    EncodingError.Context(
                        codingPath: codingPath,
                        debugDescription: "Unable to encode non-finite Double \(value)."
                    )
                )
            }
            return .double(value)
        case .convertToString(let positive, let negative, let nan):
            if value.isNaN { return .string(nan) }
            if value == .infinity { return .string(positive) }
            if value == -.infinity { return .string(negative) }
            return .double(value)
        }
    }

    func boxDate(_ date: Date, codingPath: [CodingKey]) throws -> BinaryValue {
        switch options.dateEncodingStrategy {
        case .timestamp:
            return .timestamp(date.timeIntervalSince1970)
        case .secondsSince1970:
            return .double(date.timeIntervalSince1970)
        case .millisecondsSince1970:
            return .double(date.timeIntervalSince1970 * 1000)
        case .iso8601:
            return .string(BinaryDateFormat.string(from: date))
        case .deferredToDate:
            return try encodeNested(codingPath: codingPath, allowEmpty: false) { encoder in
                try date.encode(to: encoder)
            }
        case .custom(let closure):
            return try encodeNested(codingPath: codingPath, allowEmpty: true) { encoder in
                try closure(date, encoder)
            }
        }
    }

    func boxData(_ data: Data, codingPath: [CodingKey]) throws -> BinaryValue {
        switch options.dataEncodingStrategy {
        case .binary:
            return .data(data)
        case .base64:
            return .string(data.base64EncodedString())
        case .deferredToData:
            return try encodeNested(codingPath: codingPath, allowEmpty: false) { encoder in
                try data.encode(to: encoder)
            }
        case .custom(let closure):
            return try encodeNested(codingPath: codingPath, allowEmpty: true) { encoder in
                try closure(data, encoder)
            }
        }
    }

    private func encodeNested(
        codingPath: [CodingKey],
        allowEmpty: Bool,
        _ body: (_BinaryEncoder) throws -> Void
    ) throws -> BinaryValue {
        let nested = _BinaryEncoder(options: options, codingPath: codingPath)
        try body(nested)
        if let stored = nested.storage.first {
            return stored
        }
        if allowEmpty {
            return .map(BinaryMap())
        }
        throw EncodingError.invalidValue(
            nested,
            EncodingError.Context(
                codingPath: codingPath,
                debugDescription: "Encoding closure did not encode any values at \(binaryCodingPathDescription(codingPath))."
            )
        )
    }
}

struct _BinaryKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let encoder: _BinaryEncoder
    let map: BinaryMap
    var codingPath: [CodingKey]

    func storedKey(for key: Key) -> BinaryValue {
        switch encoder.options.keyEncodingStrategy {
        case .useDefaultKeys:
            if let intValue = key.intValue, key.stringValue == String(intValue) {
                return .int(Int64(intValue))
            }
            return .string(key.stringValue)
        case .convertToSnakeCase:
            return .string(KeyTransform.camelToSnake(key.stringValue))
        case .custom(let transform):
            return .string(transform(codingPath + [key]).stringValue)
        }
    }

    mutating func encodeNil(forKey key: Key) throws {
        map.set(key: storedKey(for: key), value: .null)
    }

    mutating func encode(_ value: Bool, forKey key: Key) throws { try encodeValue(value, forKey: key) }
    mutating func encode(_ value: String, forKey key: Key) throws { try encodeValue(value, forKey: key) }
    mutating func encode(_ value: Double, forKey key: Key) throws { try encodeValue(value, forKey: key) }
    mutating func encode(_ value: Float, forKey key: Key) throws { try encodeValue(value, forKey: key) }
    mutating func encode(_ value: Int, forKey key: Key) throws { try encodeValue(value, forKey: key) }
    mutating func encode(_ value: Int8, forKey key: Key) throws { try encodeValue(value, forKey: key) }
    mutating func encode(_ value: Int16, forKey key: Key) throws { try encodeValue(value, forKey: key) }
    mutating func encode(_ value: Int32, forKey key: Key) throws { try encodeValue(value, forKey: key) }
    mutating func encode(_ value: Int64, forKey key: Key) throws { try encodeValue(value, forKey: key) }
    mutating func encode(_ value: UInt, forKey key: Key) throws { try encodeValue(value, forKey: key) }
    mutating func encode(_ value: UInt8, forKey key: Key) throws { try encodeValue(value, forKey: key) }
    mutating func encode(_ value: UInt16, forKey key: Key) throws { try encodeValue(value, forKey: key) }
    mutating func encode(_ value: UInt32, forKey key: Key) throws { try encodeValue(value, forKey: key) }
    mutating func encode(_ value: UInt64, forKey key: Key) throws { try encodeValue(value, forKey: key) }
    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws { try encodeValue(value, forKey: key) }

    mutating func encodeIfPresent(_ value: Bool?, forKey key: Key) throws { try encodeIfPresentValue(value, forKey: key) }
    mutating func encodeIfPresent(_ value: String?, forKey key: Key) throws { try encodeIfPresentValue(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Double?, forKey key: Key) throws { try encodeIfPresentValue(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Float?, forKey key: Key) throws { try encodeIfPresentValue(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Int?, forKey key: Key) throws { try encodeIfPresentValue(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Int8?, forKey key: Key) throws { try encodeIfPresentValue(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Int16?, forKey key: Key) throws { try encodeIfPresentValue(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Int32?, forKey key: Key) throws { try encodeIfPresentValue(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Int64?, forKey key: Key) throws { try encodeIfPresentValue(value, forKey: key) }
    mutating func encodeIfPresent(_ value: UInt?, forKey key: Key) throws { try encodeIfPresentValue(value, forKey: key) }
    mutating func encodeIfPresent(_ value: UInt8?, forKey key: Key) throws { try encodeIfPresentValue(value, forKey: key) }
    mutating func encodeIfPresent(_ value: UInt16?, forKey key: Key) throws { try encodeIfPresentValue(value, forKey: key) }
    mutating func encodeIfPresent(_ value: UInt32?, forKey key: Key) throws { try encodeIfPresentValue(value, forKey: key) }
    mutating func encodeIfPresent(_ value: UInt64?, forKey key: Key) throws { try encodeIfPresentValue(value, forKey: key) }
    mutating func encodeIfPresent<T: Encodable>(_ value: T?, forKey key: Key) throws { try encodeIfPresentValue(value, forKey: key) }

    private mutating func encodeValue<T: Encodable>(_ value: T, forKey key: Key) throws {
        let boxed = try encoder.box(value, codingPath: codingPath + [key])
        map.set(key: storedKey(for: key), value: boxed)
    }

    private mutating func encodeIfPresentValue<T: Encodable>(_ value: T?, forKey key: Key) throws {
        guard let value else { return }
        try encodeValue(value, forKey: key)
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type,
        forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
        let nested = BinaryMap()
        map.set(key: storedKey(for: key), value: .map(nested))
        return KeyedEncodingContainer(
            _BinaryKeyedEncodingContainer<NestedKey>(
                encoder: encoder,
                map: nested,
                codingPath: codingPath + [key]
            )
        )
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        let nested = BinaryArray()
        map.set(key: storedKey(for: key), value: .array(nested))
        return _BinaryUnkeyedEncodingContainer(
            encoder: encoder,
            array: nested,
            codingPath: codingPath + [key]
        )
    }

    func superEncoder() -> Encoder {
        let pathKey = BinaryCodingKey(stringValue: "super")
        return referencingEncoder(storedKey: storedSuperKey(pathKey: pathKey), pathKey: pathKey)
    }

    func superEncoder(forKey key: Key) -> Encoder {
        referencingEncoder(storedKey: storedKey(for: key), pathKey: key)
    }

    /// Writes the superclass under `"super"` even when that string is not one of `Key`'s cases.
    private func storedSuperKey(pathKey: BinaryCodingKey) -> BinaryValue {
        switch encoder.options.keyEncodingStrategy {
        case .useDefaultKeys:
            return .string("super")
        case .convertToSnakeCase:
            return .string(KeyTransform.camelToSnake("super"))
        case .custom(let transform):
            return .string(transform(codingPath + [pathKey]).stringValue)
        }
    }

    private func referencingEncoder(storedKey: BinaryValue, pathKey: CodingKey) -> Encoder {
        let slot = BinarySlot(.map(BinaryMap()))
        map.set(key: storedKey, value: .slot(slot))
        return _BinaryEncoder(options: encoder.options, codingPath: codingPath + [pathKey], slot: slot)
    }
}

struct _BinaryUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    let encoder: _BinaryEncoder
    let array: BinaryArray
    var codingPath: [CodingKey]

    var count: Int { array.elements.count }

    mutating func encodeNil() throws {
        array.elements.append(.null)
    }

    mutating func encode(_ value: Bool) throws { try encodeValue(value) }
    mutating func encode(_ value: String) throws { try encodeValue(value) }
    mutating func encode(_ value: Double) throws { try encodeValue(value) }
    mutating func encode(_ value: Float) throws { try encodeValue(value) }
    mutating func encode(_ value: Int) throws { try encodeValue(value) }
    mutating func encode(_ value: Int8) throws { try encodeValue(value) }
    mutating func encode(_ value: Int16) throws { try encodeValue(value) }
    mutating func encode(_ value: Int32) throws { try encodeValue(value) }
    mutating func encode(_ value: Int64) throws { try encodeValue(value) }
    mutating func encode(_ value: UInt) throws { try encodeValue(value) }
    mutating func encode(_ value: UInt8) throws { try encodeValue(value) }
    mutating func encode(_ value: UInt16) throws { try encodeValue(value) }
    mutating func encode(_ value: UInt32) throws { try encodeValue(value) }
    mutating func encode(_ value: UInt64) throws { try encodeValue(value) }
    mutating func encode<T: Encodable>(_ value: T) throws { try encodeValue(value) }

    private mutating func encodeValue<T: Encodable>(_ value: T) throws {
        let index = array.elements.count
        let boxed = try encoder.box(value, codingPath: codingPath + [BinaryCodingKey(index: index)])
        array.elements.append(boxed)
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type
    ) -> KeyedEncodingContainer<NestedKey> {
        let nested = BinaryMap()
        let index = array.elements.count
        array.elements.append(.map(nested))
        return KeyedEncodingContainer(
            _BinaryKeyedEncodingContainer<NestedKey>(
                encoder: encoder,
                map: nested,
                codingPath: codingPath + [BinaryCodingKey(index: index)]
            )
        )
    }

    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let nested = BinaryArray()
        let index = array.elements.count
        array.elements.append(.array(nested))
        return _BinaryUnkeyedEncodingContainer(
            encoder: encoder,
            array: nested,
            codingPath: codingPath + [BinaryCodingKey(index: index)]
        )
    }

    func superEncoder() -> Encoder {
        let slot = BinarySlot(.map(BinaryMap()))
        let index = array.elements.count
        array.elements.append(.slot(slot))
        return _BinaryEncoder(
            options: encoder.options,
            codingPath: codingPath + [BinaryCodingKey(index: index)],
            slot: slot
        )
    }
}

struct _BinarySingleValueEncodingContainer: SingleValueEncodingContainer {
    let encoder: _BinaryEncoder
    var codingPath: [CodingKey] { encoder.codingPath }

    mutating func encodeNil() throws {
        encoder.store(.null)
    }

    mutating func encode(_ value: Bool) throws { try encodeValue(value) }
    mutating func encode(_ value: String) throws { try encodeValue(value) }
    mutating func encode(_ value: Double) throws { try encodeValue(value) }
    mutating func encode(_ value: Float) throws { try encodeValue(value) }
    mutating func encode(_ value: Int) throws { try encodeValue(value) }
    mutating func encode(_ value: Int8) throws { try encodeValue(value) }
    mutating func encode(_ value: Int16) throws { try encodeValue(value) }
    mutating func encode(_ value: Int32) throws { try encodeValue(value) }
    mutating func encode(_ value: Int64) throws { try encodeValue(value) }
    mutating func encode(_ value: UInt) throws { try encodeValue(value) }
    mutating func encode(_ value: UInt8) throws { try encodeValue(value) }
    mutating func encode(_ value: UInt16) throws { try encodeValue(value) }
    mutating func encode(_ value: UInt32) throws { try encodeValue(value) }
    mutating func encode(_ value: UInt64) throws { try encodeValue(value) }
    mutating func encode<T: Encodable>(_ value: T) throws { try encodeValue(value) }

    private mutating func encodeValue<T: Encodable>(_ value: T) throws {
        encoder.store(try encoder.box(value, codingPath: encoder.codingPath))
    }
}
