import Foundation

/// Decodes `Decodable` values from a document produced by ``BinaryEncoder``.
///
/// The decoder and the encoder must use the same endianness and the same date,
/// data, float, and key strategies. Integer widths on the wire are flexible:
/// an `Int8` may be read as an `Int` when the number fits, and a `UInt` may be
/// read as an `Int` when it is not negative and fits.
public final class BinaryDecoder {
    /// Byte order of multi-byte numbers. The default is ``BinaryEndianness/big``.
    public var endianness: BinaryEndianness = .big

    /// How `Date` values are read. The default is ``DateDecodingStrategy/timestamp``.
    public var dateDecodingStrategy: DateDecodingStrategy = .timestamp

    /// How `Data` values are read. The default is ``DataDecodingStrategy/binary``.
    public var dataDecodingStrategy: DataDecodingStrategy = .binary

    /// How NaN, infinities, and their string replacements are read.
    public var nonConformingFloatDecodingStrategy: NonConformingFloatDecodingStrategy = .passThrough

    /// How map keys are matched to coding keys. The default compares the text as written.
    public var keyDecodingStrategy: KeyDecodingStrategy = .useDefaultKeys

    /// Context made available to types while they decode.
    public var userInfo: [CodingUserInfoKey: Any] = [:]

    public init() {}

    /// Decodes a value of `type` from `data`.
    ///
    /// Trailing bytes after the value are an error.
    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let options = Options(self)
        var reader = BinaryReader(data: data, endianness: options.endianness)
        let value = try reader.readValue()
        guard reader.isAtEnd else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "\(reader.remaining) trailing bytes after the encoded value."
                )
            )
        }
        let decoder = _BinaryDecoder(value: value, codingPath: [], options: options)
        return try decoder.unbox(value, as: type, codingPath: [])
    }

    /// Strategies for decoding `Date`.
    public enum DateDecodingStrategy {
        /// A timestamp value written by ``BinaryEncoder/DateEncodingStrategy/timestamp``.
        /// This is the default.
        case timestamp
        /// Let `Date` decode itself from a float64 `timeIntervalSinceReferenceDate`.
        case deferredToDate
        /// A float64 count of seconds since 1970-01-01T00:00:00Z.
        case secondsSince1970
        /// A float64 count of milliseconds since 1970-01-01T00:00:00Z.
        case millisecondsSince1970
        /// An ISO 8601 string.
        case iso8601
        /// Decode the date with a closure.
        case custom((_ decoder: Decoder) throws -> Date)
    }

    /// Strategies for decoding `Data`.
    public enum DataDecodingStrategy {
        /// A binary blob. This is the default.
        case binary
        /// A Base64 string.
        case base64
        /// Let `Data` decode itself from an array of bytes.
        case deferredToData
        /// Decode the bytes with a closure.
        case custom((_ decoder: Decoder) throws -> Data)
    }

    /// Strategies for non-finite floating point values.
    public enum NonConformingFloatDecodingStrategy {
        /// Accept IEEE 754 NaN and infinities. This is the default.
        case passThrough
        /// Throw when a float is NaN or infinite.
        case `throw`
        /// Read the given strings as infinities and NaN.
        case convertFromString(positiveInfinity: String, negativeInfinity: String, nan: String)
    }

    /// Strategies for converting map keys into coding keys.
    public enum KeyDecodingStrategy {
        /// Match keys as they were written.
        case useDefaultKeys
        /// Convert snake_case map keys to camelCase before matching, using the same rules as `JSONDecoder`.
        case convertFromSnakeCase
        /// Convert each map key. The closure receives the coding path, including the key from the document.
        case custom((_ codingPath: [CodingKey]) -> CodingKey)
    }

    struct Options {
        var endianness: BinaryEndianness
        var dateDecodingStrategy: DateDecodingStrategy
        var dataDecodingStrategy: DataDecodingStrategy
        var nonConformingFloatDecodingStrategy: NonConformingFloatDecodingStrategy
        var keyDecodingStrategy: KeyDecodingStrategy
        var userInfo: [CodingUserInfoKey: Any]

        init(_ decoder: BinaryDecoder) {
            endianness = decoder.endianness
            dateDecodingStrategy = decoder.dateDecodingStrategy
            dataDecodingStrategy = decoder.dataDecodingStrategy
            nonConformingFloatDecodingStrategy = decoder.nonConformingFloatDecodingStrategy
            keyDecodingStrategy = decoder.keyDecodingStrategy
            userInfo = decoder.userInfo
        }
    }
}

final class _BinaryDecoder: Decoder {
    let value: BinaryValue
    var codingPath: [CodingKey]
    let options: BinaryDecoder.Options
    var userInfo: [CodingUserInfoKey: Any] { options.userInfo }

    init(value: BinaryValue, codingPath: [CodingKey], options: BinaryDecoder.Options) {
        self.value = value
        self.codingPath = codingPath
        self.options = options
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case .map(let map) = value.unwrap else {
            throw binaryTypeMismatch(Key.self, value, codingPath)
        }
        return KeyedDecodingContainer(
            _BinaryKeyedDecodingContainer(decoder: self, map: map, codingPath: codingPath)
        )
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard case .array(let array) = value.unwrap else {
            throw binaryTypeMismatch([Any].self, value, codingPath)
        }
        return _BinaryUnkeyedDecodingContainer(decoder: self, array: array, codingPath: codingPath)
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        _BinarySingleValueDecodingContainer(decoder: self)
    }

    func unbox<T: Decodable>(_ value: BinaryValue, as type: T.Type, codingPath: [CodingKey]) throws -> T {
        let value = value.unwrap
        if type == Bool.self { return try unboxBool(value, codingPath: codingPath) as! T }
        if type == String.self { return try unboxString(value, codingPath: codingPath) as! T }
        if type == Double.self { return try unboxDouble(value, codingPath: codingPath) as! T }
        if type == Float.self { return try unboxFloat(value, codingPath: codingPath) as! T }
        if type == Int.self { return try unboxInteger(value, as: Int.self, codingPath: codingPath) as! T }
        if type == Int8.self { return try unboxInteger(value, as: Int8.self, codingPath: codingPath) as! T }
        if type == Int16.self { return try unboxInteger(value, as: Int16.self, codingPath: codingPath) as! T }
        if type == Int32.self { return try unboxInteger(value, as: Int32.self, codingPath: codingPath) as! T }
        if type == Int64.self { return try unboxInteger(value, as: Int64.self, codingPath: codingPath) as! T }
        if type == UInt.self { return try unboxInteger(value, as: UInt.self, codingPath: codingPath) as! T }
        if type == UInt8.self { return try unboxInteger(value, as: UInt8.self, codingPath: codingPath) as! T }
        if type == UInt16.self { return try unboxInteger(value, as: UInt16.self, codingPath: codingPath) as! T }
        if type == UInt32.self { return try unboxInteger(value, as: UInt32.self, codingPath: codingPath) as! T }
        if type == UInt64.self { return try unboxInteger(value, as: UInt64.self, codingPath: codingPath) as! T }
        if type == Date.self { return try unboxDate(value, codingPath: codingPath) as! T }
        if type == Data.self { return try unboxData(value, codingPath: codingPath) as! T }
        if type == URL.self { return try unboxURL(value, codingPath: codingPath) as! T }
        if type == BinaryExtension.self { return try unboxExtension(value, codingPath: codingPath) as! T }
        if let extType = type as? any BinaryExtensible.Type {
            return try unboxExtensible(value, extType: extType, as: type, codingPath: codingPath)
        }

        let nested = _BinaryDecoder(value: value, codingPath: codingPath, options: options)
        return try T(from: nested)
    }

    func unboxBool(_ value: BinaryValue, codingPath: [CodingKey]) throws -> Bool {
        if value.isNull { throw binaryValueNotFound(Bool.self, codingPath) }
        guard case .bool(let flag) = value.unwrap else {
            throw binaryTypeMismatch(Bool.self, value, codingPath)
        }
        return flag
    }

    func unboxString(_ value: BinaryValue, codingPath: [CodingKey]) throws -> String {
        if value.isNull { throw binaryValueNotFound(String.self, codingPath) }
        guard case .string(let string) = value.unwrap else {
            throw binaryTypeMismatch(String.self, value, codingPath)
        }
        return string
    }

    func unboxDouble(_ value: BinaryValue, codingPath: [CodingKey]) throws -> Double {
        switch value.unwrap {
        case .double(let number):
            return try checkNonConforming(number, codingPath: codingPath)
        case .float(let number):
            return try checkNonConforming(Double(number), codingPath: codingPath)
        case .int(let number):
            return Double(number)
        case .uint(let number):
            return Double(number)
        case .string(let token):
            return try double(fromToken: token, codingPath: codingPath)
        case .null:
            throw binaryValueNotFound(Double.self, codingPath)
        default:
            throw binaryTypeMismatch(Double.self, value, codingPath)
        }
    }

    func unboxFloat(_ value: BinaryValue, codingPath: [CodingKey]) throws -> Float {
        switch value.unwrap {
        case .float(let number):
            return try checkNonConforming(number, codingPath: codingPath)
        case .double(let number):
            let narrowed = Float(number)
            if number.isFinite && !narrowed.isFinite {
                throw binaryDataCorrupted("Float64 \(number) does not fit in Float.", codingPath)
            }
            return try checkNonConforming(narrowed, codingPath: codingPath)
        case .int(let number):
            return Float(number)
        case .uint(let number):
            return Float(number)
        case .string(let token):
            return Float(try double(fromToken: token, codingPath: codingPath))
        case .null:
            throw binaryValueNotFound(Float.self, codingPath)
        default:
            throw binaryTypeMismatch(Float.self, value, codingPath)
        }
    }

    func unboxInteger<N: FixedWidthInteger>(_ value: BinaryValue, as type: N.Type, codingPath: [CodingKey]) throws -> N {
        switch value.unwrap {
        case .int(let number):
            guard let exact = N(exactly: number) else {
                throw binaryDataCorrupted("Integer \(number) does not fit in \(N.self).", codingPath)
            }
            return exact
        case .uint(let number):
            guard let exact = N(exactly: number) else {
                throw binaryDataCorrupted("Integer \(number) does not fit in \(N.self).", codingPath)
            }
            return exact
        case .null:
            throw binaryValueNotFound(N.self, codingPath)
        default:
            throw binaryTypeMismatch(N.self, value, codingPath)
        }
    }

    func unboxDate(_ value: BinaryValue, codingPath: [CodingKey]) throws -> Date {
        if value.isNull { throw binaryValueNotFound(Date.self, codingPath) }
        switch options.dateDecodingStrategy {
        case .timestamp:
            guard case .timestamp(let seconds) = value.unwrap else {
                throw binaryTypeMismatch(Date.self, value, codingPath)
            }
            return Date(timeIntervalSince1970: seconds)
        case .secondsSince1970:
            return Date(timeIntervalSince1970: try unboxDouble(value, codingPath: codingPath))
        case .millisecondsSince1970:
            return Date(timeIntervalSince1970: try unboxDouble(value, codingPath: codingPath) / 1000)
        case .iso8601:
            let string = try unboxString(value, codingPath: codingPath)
            guard let date = BinaryDateFormat.date(from: string) else {
                throw binaryDataCorrupted("Invalid ISO 8601 date \"\(string)\".", codingPath)
            }
            return date
        case .deferredToDate:
            return try Date(from: _BinaryDecoder(value: value, codingPath: codingPath, options: options))
        case .custom(let closure):
            return try closure(_BinaryDecoder(value: value, codingPath: codingPath, options: options))
        }
    }

    func unboxData(_ value: BinaryValue, codingPath: [CodingKey]) throws -> Data {
        if value.isNull { throw binaryValueNotFound(Data.self, codingPath) }
        switch options.dataDecodingStrategy {
        case .binary:
            guard case .data(let payload) = value.unwrap else {
                throw binaryTypeMismatch(Data.self, value, codingPath)
            }
            return payload
        case .base64:
            let string = try unboxString(value, codingPath: codingPath)
            guard let payload = Data(base64Encoded: string) else {
                throw binaryDataCorrupted("Invalid Base64 data.", codingPath)
            }
            return payload
        case .deferredToData:
            return try Data(from: _BinaryDecoder(value: value, codingPath: codingPath, options: options))
        case .custom(let closure):
            return try closure(_BinaryDecoder(value: value, codingPath: codingPath, options: options))
        }
    }

    func unboxURL(_ value: BinaryValue, codingPath: [CodingKey]) throws -> URL {
        let string = try unboxString(value, codingPath: codingPath)
        guard let url = URL(string: string) else {
            throw binaryDataCorrupted("Invalid URL \"\(string)\".", codingPath)
        }
        return url
    }

    func unboxExtension(_ value: BinaryValue, codingPath: [CodingKey]) throws -> BinaryExtension {
        if value.isNull { throw binaryValueNotFound(BinaryExtension.self, codingPath) }
        guard case .ext(let type, let payload) = value.unwrap else {
            throw binaryTypeMismatch(BinaryExtension.self, value, codingPath)
        }
        return BinaryExtension(type: type, data: payload)
    }

    func unboxExtensible<T: Decodable>(
        _ value: BinaryValue,
        extType: any BinaryExtensible.Type,
        as type: T.Type,
        codingPath: [CodingKey]
    ) throws -> T {
        if value.isNull { throw binaryValueNotFound(type, codingPath) }
        guard case .ext(let code, let payload) = value.unwrap else {
            throw binaryTypeMismatch(type, value, codingPath)
        }
        guard code == extType.binaryExtType else {
            throw binaryDataCorrupted(
                "Extension type \(code) does not match \(extType) type \(extType.binaryExtType).",
                codingPath
            )
        }
        let instance = try extType.init(binaryExtData: payload)
        guard let typed = instance as? T else {
            throw binaryTypeMismatch(type, value, codingPath)
        }
        return typed
    }

    private func checkNonConforming(_ value: Double, codingPath: [CodingKey]) throws -> Double {
        guard !value.isFinite else { return value }
        switch options.nonConformingFloatDecodingStrategy {
        case .passThrough, .convertFromString:
            return value
        case .throw:
            throw binaryDataCorrupted("Non-finite float \(value) is not allowed.", codingPath)
        }
    }

    private func checkNonConforming(_ value: Float, codingPath: [CodingKey]) throws -> Float {
        guard !value.isFinite else { return value }
        switch options.nonConformingFloatDecodingStrategy {
        case .passThrough, .convertFromString:
            return value
        case .throw:
            throw binaryDataCorrupted("Non-finite float \(value) is not allowed.", codingPath)
        }
    }

    private func double(fromToken token: String, codingPath: [CodingKey]) throws -> Double {
        guard case .convertFromString(let positive, let negative, let nan) = options.nonConformingFloatDecodingStrategy else {
            throw binaryTypeMismatch(Double.self, .string(token), codingPath)
        }
        if token == positive { return .infinity }
        if token == negative { return -.infinity }
        if token == nan { return .nan }
        throw binaryDataCorrupted("Unexpected float token \"\(token)\".", codingPath)
    }
}

struct _BinaryKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let decoder: _BinaryDecoder
    let codingPath: [CodingKey]
    private let strings: [String: BinaryValue]
    private let ints: [Int64: BinaryValue]
    private let uints: [UInt64: BinaryValue]
    private let ordered: [MapKey]

    private enum MapKey {
        case string(String)
        case int(Int64)
        case uint(UInt64)
    }

    init(decoder: _BinaryDecoder, map: BinaryMap, codingPath: [CodingKey]) {
        self.decoder = decoder
        self.codingPath = codingPath

        var strings: [String: BinaryValue] = [:]
        var ints: [Int64: BinaryValue] = [:]
        var uints: [UInt64: BinaryValue] = [:]
        var ordered: [MapKey] = []

        for field in map.fields {
            switch field.key.unwrap {
            case .string(let raw):
                let converted = Self.convert(raw, codingPath: codingPath, strategy: decoder.options.keyDecodingStrategy)
                if strings[converted] == nil {
                    ordered.append(.string(converted))
                }
                strings[converted] = field.value
            case .int(let number):
                if ints[number] == nil {
                    ordered.append(.int(number))
                }
                ints[number] = field.value
            case .uint(let number):
                if uints[number] == nil {
                    ordered.append(.uint(number))
                }
                uints[number] = field.value
            default:
                break
            }
        }

        self.strings = strings
        self.ints = ints
        self.uints = uints
        self.ordered = ordered
    }

    var allKeys: [Key] {
        ordered.compactMap { candidate in
            switch candidate {
            case .string(let string):
                return Key(stringValue: string)
            case .int(let number):
                if let intValue = Int(exactly: number), let key = Key(intValue: intValue) {
                    return key
                }
                return Key(stringValue: String(number))
            case .uint(let number):
                if let intValue = Int(exactly: number), let key = Key(intValue: intValue) {
                    return key
                }
                return Key(stringValue: String(number))
            }
        }
    }

    func contains(_ key: Key) -> Bool {
        value(for: key) != nil
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        guard let stored = value(for: key) else {
            throw missing(key)
        }
        return stored.isNull
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try decodeValue(type, forKey: key) }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { try decodeValue(type, forKey: key) }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try decodeValue(type, forKey: key) }
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try decodeValue(type, forKey: key) }
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try decodeValue(type, forKey: key) }
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try decodeValue(type, forKey: key) }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try decodeValue(type, forKey: key) }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try decodeValue(type, forKey: key) }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try decodeValue(type, forKey: key) }
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try decodeValue(type, forKey: key) }
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try decodeValue(type, forKey: key) }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try decodeValue(type, forKey: key) }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try decodeValue(type, forKey: key) }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try decodeValue(type, forKey: key) }
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T { try decodeValue(type, forKey: key) }

    func decodeIfPresent(_ type: Bool.Type, forKey key: Key) throws -> Bool? { try decodeIfPresentValue(type, forKey: key) }
    func decodeIfPresent(_ type: String.Type, forKey key: Key) throws -> String? { try decodeIfPresentValue(type, forKey: key) }
    func decodeIfPresent(_ type: Double.Type, forKey key: Key) throws -> Double? { try decodeIfPresentValue(type, forKey: key) }
    func decodeIfPresent(_ type: Float.Type, forKey key: Key) throws -> Float? { try decodeIfPresentValue(type, forKey: key) }
    func decodeIfPresent(_ type: Int.Type, forKey key: Key) throws -> Int? { try decodeIfPresentValue(type, forKey: key) }
    func decodeIfPresent(_ type: Int8.Type, forKey key: Key) throws -> Int8? { try decodeIfPresentValue(type, forKey: key) }
    func decodeIfPresent(_ type: Int16.Type, forKey key: Key) throws -> Int16? { try decodeIfPresentValue(type, forKey: key) }
    func decodeIfPresent(_ type: Int32.Type, forKey key: Key) throws -> Int32? { try decodeIfPresentValue(type, forKey: key) }
    func decodeIfPresent(_ type: Int64.Type, forKey key: Key) throws -> Int64? { try decodeIfPresentValue(type, forKey: key) }
    func decodeIfPresent(_ type: UInt.Type, forKey key: Key) throws -> UInt? { try decodeIfPresentValue(type, forKey: key) }
    func decodeIfPresent(_ type: UInt8.Type, forKey key: Key) throws -> UInt8? { try decodeIfPresentValue(type, forKey: key) }
    func decodeIfPresent(_ type: UInt16.Type, forKey key: Key) throws -> UInt16? { try decodeIfPresentValue(type, forKey: key) }
    func decodeIfPresent(_ type: UInt32.Type, forKey key: Key) throws -> UInt32? { try decodeIfPresentValue(type, forKey: key) }
    func decodeIfPresent(_ type: UInt64.Type, forKey key: Key) throws -> UInt64? { try decodeIfPresentValue(type, forKey: key) }
    func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? { try decodeIfPresentValue(type, forKey: key) }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type,
        forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        let stored = try storedValue(for: key)
        guard case .map(let map) = stored.unwrap else {
            throw binaryTypeMismatch(NestedKey.self, stored, codingPath + [key])
        }
        return KeyedDecodingContainer(
            _BinaryKeyedDecodingContainer<NestedKey>(
                decoder: decoder,
                map: map,
                codingPath: codingPath + [key]
            )
        )
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        let stored = try storedValue(for: key)
        guard case .array(let array) = stored.unwrap else {
            throw binaryTypeMismatch([Any].self, stored, codingPath + [key])
        }
        return _BinaryUnkeyedDecodingContainer(
            decoder: decoder,
            array: array,
            codingPath: codingPath + [key]
        )
    }

    func superDecoder() throws -> Decoder {
        try decoderForKey(BinaryCodingKey(stringValue: "super"))
    }

    func superDecoder(forKey key: Key) throws -> Decoder {
        try decoderForKey(key)
    }

    private func decodeValue<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let stored = try storedValue(for: key)
        return try decoder.unbox(stored, as: type, codingPath: codingPath + [key])
    }

    private func decodeIfPresentValue<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
        guard let stored = value(for: key) else { return nil }
        if stored.isNull { return nil }
        return try decoder.unbox(stored, as: type, codingPath: codingPath + [key])
    }

    private func storedValue(for key: CodingKey) throws -> BinaryValue {
        guard let stored = value(for: key) else {
            throw missing(key)
        }
        return stored
    }

    private func decoderForKey(_ key: CodingKey) throws -> Decoder {
        let stored = try storedValue(for: key)
        return _BinaryDecoder(value: stored, codingPath: codingPath + [key], options: decoder.options)
    }

    private func missing(_ key: CodingKey) -> DecodingError {
        DecodingError.keyNotFound(
            key,
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "No value associated with key \(key.stringValue)."
            )
        )
    }

    private func value(for key: CodingKey) -> BinaryValue? {
        if let intValue = key.intValue {
            if let stored = ints[Int64(intValue)] {
                return stored
            }
            if intValue >= 0, let stored = uints[UInt64(intValue)] {
                return stored
            }
        }
        if let stored = strings[key.stringValue] {
            return stored
        }
        if let parsed = Int64(key.stringValue), let stored = ints[parsed] {
            return stored
        }
        if key.stringValue.first != "-",
           let parsed = UInt64(key.stringValue),
           let stored = uints[parsed] {
            return stored
        }
        return nil
    }

    private static func convert(
        _ raw: String,
        codingPath: [CodingKey],
        strategy: BinaryDecoder.KeyDecodingStrategy
    ) -> String {
        switch strategy {
        case .useDefaultKeys:
            return raw
        case .convertFromSnakeCase:
            return KeyTransform.snakeToCamel(raw)
        case .custom(let transform):
            return transform(codingPath + [BinaryCodingKey(stringValue: raw)]).stringValue
        }
    }
}

struct _BinaryUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    let decoder: _BinaryDecoder
    let array: BinaryArray
    var codingPath: [CodingKey]
    var currentIndex = 0

    var count: Int? { array.elements.count }
    var isAtEnd: Bool { currentIndex >= array.elements.count }

    mutating func decodeNil() throws -> Bool {
        let stored = try peek()
        if stored.isNull {
            currentIndex += 1
            return true
        }
        return false
    }

    mutating func decode(_ type: Bool.Type) throws -> Bool { try decodeValue(type) }
    mutating func decode(_ type: String.Type) throws -> String { try decodeValue(type) }
    mutating func decode(_ type: Double.Type) throws -> Double { try decodeValue(type) }
    mutating func decode(_ type: Float.Type) throws -> Float { try decodeValue(type) }
    mutating func decode(_ type: Int.Type) throws -> Int { try decodeValue(type) }
    mutating func decode(_ type: Int8.Type) throws -> Int8 { try decodeValue(type) }
    mutating func decode(_ type: Int16.Type) throws -> Int16 { try decodeValue(type) }
    mutating func decode(_ type: Int32.Type) throws -> Int32 { try decodeValue(type) }
    mutating func decode(_ type: Int64.Type) throws -> Int64 { try decodeValue(type) }
    mutating func decode(_ type: UInt.Type) throws -> UInt { try decodeValue(type) }
    mutating func decode(_ type: UInt8.Type) throws -> UInt8 { try decodeValue(type) }
    mutating func decode(_ type: UInt16.Type) throws -> UInt16 { try decodeValue(type) }
    mutating func decode(_ type: UInt32.Type) throws -> UInt32 { try decodeValue(type) }
    mutating func decode(_ type: UInt64.Type) throws -> UInt64 { try decodeValue(type) }
    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T { try decodeValue(type) }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type
    ) throws -> KeyedDecodingContainer<NestedKey> {
        let stored = try consume()
        guard case .map(let map) = stored.unwrap else {
            throw binaryTypeMismatch(NestedKey.self, stored, codingPath + [BinaryCodingKey(index: currentIndex - 1)])
        }
        return KeyedDecodingContainer(
            _BinaryKeyedDecodingContainer<NestedKey>(
                decoder: decoder,
                map: map,
                codingPath: codingPath + [BinaryCodingKey(index: currentIndex - 1)]
            )
        )
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        let stored = try consume()
        guard case .array(let nested) = stored.unwrap else {
            throw binaryTypeMismatch([Any].self, stored, codingPath + [BinaryCodingKey(index: currentIndex - 1)])
        }
        return _BinaryUnkeyedDecodingContainer(
            decoder: decoder,
            array: nested,
            codingPath: codingPath + [BinaryCodingKey(index: currentIndex - 1)]
        )
    }

    mutating func superDecoder() throws -> Decoder {
        let stored = try consume()
        return _BinaryDecoder(
            value: stored,
            codingPath: codingPath + [BinaryCodingKey(index: currentIndex - 1)],
            options: decoder.options
        )
    }

    private mutating func decodeValue<T: Decodable>(_ type: T.Type) throws -> T {
        let stored = try peek()
        let decoded = try decoder.unbox(
            stored,
            as: type,
            codingPath: codingPath + [BinaryCodingKey(index: currentIndex)]
        )
        currentIndex += 1
        return decoded
    }

    private func peek() throws -> BinaryValue {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(
                Any.self,
                DecodingError.Context(
                    codingPath: codingPath + [BinaryCodingKey(index: currentIndex)],
                    debugDescription: "Unkeyed container is at end."
                )
            )
        }
        return array.elements[currentIndex]
    }

    private mutating func consume() throws -> BinaryValue {
        let stored = try peek()
        currentIndex += 1
        return stored
    }
}

struct _BinarySingleValueDecodingContainer: SingleValueDecodingContainer {
    let decoder: _BinaryDecoder
    var codingPath: [CodingKey] { decoder.codingPath }

    func decodeNil() -> Bool {
        decoder.value.unwrap.isNull
    }

    func decode(_ type: Bool.Type) throws -> Bool { try decoder.unboxBool(decoder.value, codingPath: codingPath) }
    func decode(_ type: String.Type) throws -> String { try decoder.unboxString(decoder.value, codingPath: codingPath) }
    func decode(_ type: Double.Type) throws -> Double { try decoder.unboxDouble(decoder.value, codingPath: codingPath) }
    func decode(_ type: Float.Type) throws -> Float { try decoder.unboxFloat(decoder.value, codingPath: codingPath) }
    func decode(_ type: Int.Type) throws -> Int { try decoder.unboxInteger(decoder.value, as: Int.self, codingPath: codingPath) }
    func decode(_ type: Int8.Type) throws -> Int8 { try decoder.unboxInteger(decoder.value, as: Int8.self, codingPath: codingPath) }
    func decode(_ type: Int16.Type) throws -> Int16 { try decoder.unboxInteger(decoder.value, as: Int16.self, codingPath: codingPath) }
    func decode(_ type: Int32.Type) throws -> Int32 { try decoder.unboxInteger(decoder.value, as: Int32.self, codingPath: codingPath) }
    func decode(_ type: Int64.Type) throws -> Int64 { try decoder.unboxInteger(decoder.value, as: Int64.self, codingPath: codingPath) }
    func decode(_ type: UInt.Type) throws -> UInt { try decoder.unboxInteger(decoder.value, as: UInt.self, codingPath: codingPath) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try decoder.unboxInteger(decoder.value, as: UInt8.self, codingPath: codingPath) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try decoder.unboxInteger(decoder.value, as: UInt16.self, codingPath: codingPath) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try decoder.unboxInteger(decoder.value, as: UInt32.self, codingPath: codingPath) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try decoder.unboxInteger(decoder.value, as: UInt64.self, codingPath: codingPath) }
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try decoder.unbox(decoder.value, as: type, codingPath: codingPath)
    }
}
