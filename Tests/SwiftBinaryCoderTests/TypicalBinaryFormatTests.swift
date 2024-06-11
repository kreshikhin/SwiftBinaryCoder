import Foundation
import XCTest
@testable import SwiftBinaryCoder

// MARK: - Bytes

private struct FormatReadError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

private struct BinaryCursor {
    var data: Data
    var index = 0
    var littleEndian: Bool

    var isAtEnd: Bool { index >= data.count }

    mutating func u8() throws -> UInt8 {
        guard index < data.count else { throw FormatReadError("Unexpected end of file.") }
        let byte = data[index]
        index += 1
        return byte
    }

    mutating func u16() throws -> UInt16 {
        try read(UInt16.self)
    }

    mutating func u32() throws -> UInt32 {
        try read(UInt32.self)
    }

    mutating func i32() throws -> Int32 {
        Int32(bitPattern: try read(UInt32.self))
    }

    mutating func bytes(_ count: Int) throws -> Data {
        guard count >= 0, index + count <= data.count else { throw FormatReadError("Unexpected end of file.") }
        let slice = data.subdata(in: index..<(index + count))
        index += count
        return slice
    }

    mutating func ascii(_ count: Int) throws -> String {
        let bytes = try self.bytes(count)
        guard let string = String(data: bytes, encoding: .utf8) else {
            throw FormatReadError("Field is not ASCII text.")
        }
        return string
    }

    private mutating func read<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        let size = MemoryLayout<T>.size
        guard index + size <= data.count else { throw FormatReadError("Unexpected end of file.") }
        var raw = T()
        _ = withUnsafeMutableBytes(of: &raw) { destination in
            data.copyBytes(to: destination, from: index..<(index + size))
        }
        index += size
        return littleEndian ? T(littleEndian: raw) : T(bigEndian: raw)
    }
}

private extension Data {
    mutating func appendU16(_ value: UInt16, littleEndian: Bool) {
        appendInteger(value, littleEndian: littleEndian)
    }

    mutating func appendU32(_ value: UInt32, littleEndian: Bool) {
        appendInteger(value, littleEndian: littleEndian)
    }

    mutating func appendI32(_ value: Int32, littleEndian: Bool) {
        appendInteger(value, littleEndian: littleEndian)
    }

    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    private mutating func appendInteger<T: FixedWidthInteger>(_ value: T, littleEndian: Bool) {
        let stored: T = littleEndian ? value.littleEndian : value.bigEndian
        Swift.withUnsafeBytes(of: stored) { append(contentsOf: $0) }
    }
}

private extension Array where Element == Int16 {
    func littleEndianPCM() -> Data {
        var data = Data(capacity: count * 2)
        for sample in self {
            data.appendU16(UInt16(bitPattern: sample), littleEndian: true)
        }
        return data
    }
}

private extension Data {
    func int16Samples() throws -> [Int16] {
        var cursor = BinaryCursor(data: self, littleEndian: true)
        var samples: [Int16] = []
        samples.reserveCapacity(count / 2)
        while !cursor.isAtEnd {
            samples.append(Int16(bitPattern: try cursor.u16()))
        }
        return samples
    }
}
