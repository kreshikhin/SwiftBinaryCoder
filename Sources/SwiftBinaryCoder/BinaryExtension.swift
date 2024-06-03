import Foundation

/// A typed binary blob.
///
/// This is the Codable form of an extension value: an application type code
/// plus a raw payload. ``BinaryEncoder`` writes it as an `ext` value, and
/// ``BinaryDecoder`` reads an `ext` value back into this type.
///
/// Adopt ``BinaryExtensible`` instead when a Swift type owns a single fixed type code.
public struct BinaryExtension: Hashable, Codable, Sendable {
    /// Application-defined type code. Any `Int8`, including negative values, is available.
    public var type: Int8
    /// Raw payload. It is not required to be valid UTF-8.
    public var data: Data

    public init(type: Int8, data: Data) {
        self.type = type
        self.data = data
    }
}

/// A Codable type that ``BinaryEncoder`` stores as an extension payload.
///
/// ``binaryExtType`` is the type code written on the wire. ``BinaryEncoder``
/// uses `binaryExtData` instead of the type's normal `encode(to:)`.
/// ``BinaryDecoder`` rebuilds the value with ``init(binaryExtData:)`` when the
/// payload is an extension with the same type code.
public protocol BinaryExtensible {
    static var binaryExtType: Int8 { get }
    var binaryExtData: Data { get }
    init(binaryExtData: Data) throws
}
