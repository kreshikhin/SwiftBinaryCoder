import Foundation

/// Byte order used by ``BinaryEncoder`` and ``BinaryDecoder``.
///
/// Multi-byte integers and IEEE 754 values are written in this order.
/// The encoder and the decoder must use the same endianness. The default is
/// big-endian, the usual order for a portable binary document.
public enum BinaryEndianness: Sendable {
    /// Least significant byte first.
    case little
    /// Most significant byte first. This is the default.
    case big
}

/// Coding key used for array indexes and for paths passed to custom key strategies.
struct BinaryCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }

    init(index: Int) {
        self.stringValue = "Index \(index)"
        self.intValue = index
    }
}

func binaryCodingPathDescription(_ path: [CodingKey]) -> String {
    if path.isEmpty {
        return "<root>"
    }
    return path.map(\.stringValue).joined(separator: " / ")
}

func binaryTypeMismatch(_ type: Any.Type, _ value: BinaryValue, _ codingPath: [CodingKey]) -> DecodingError {
    DecodingError.typeMismatch(
        type,
        DecodingError.Context(
            codingPath: codingPath,
            debugDescription: "Expected \(type) but found \(value.typeDescription) at \(binaryCodingPathDescription(codingPath))."
        )
    )
}

func binaryValueNotFound(_ type: Any.Type, _ codingPath: [CodingKey]) -> DecodingError {
    DecodingError.valueNotFound(
        type,
        DecodingError.Context(
            codingPath: codingPath,
            debugDescription: "Expected \(type) but found null at \(binaryCodingPathDescription(codingPath))."
        )
    )
}

func binaryDataCorrupted(_ message: String, _ codingPath: [CodingKey]) -> DecodingError {
    DecodingError.dataCorrupted(
        DecodingError.Context(codingPath: codingPath, debugDescription: message)
    )
}
