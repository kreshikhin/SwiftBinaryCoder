import Foundation
import XCTest
@testable import SwiftBinaryCoder

/// Examples of the usual container layout for four file formats.
///
/// Each example builds a small document, writes the bytes the format itself
/// uses, reads those bytes back, and also stores the same value with
/// ``BinaryEncoder``. The library document is a separate encoding: a `.wav`
/// file is not a `BinaryEncoder` payload.
final class TypicalBinaryFormatTests: XCTestCase {
    func testWriteAndReadWave() throws {
        let wave = WaveFile(
            format: WaveFile.Format(
                audioFormat: 1,
                channels: 2,
                sampleRate: 44_100,
                byteRate: 176_400,
                blockAlign: 4,
                bitsPerSample: 16
            ),
            samples: [0, 8_000, -8_000, 16_000, -16_000, 32_000]
        )

        let file = wave.waveData()
        let read = try WaveFile(waveData: file)

        XCTAssertEqual(read, wave)
        XCTAssertEqual(read.format.audioFormat, 1)
        XCTAssertEqual(read.format.channels, 2)
        XCTAssertEqual(read.format.sampleRate, 44_100)
        XCTAssertEqual(
            read.format.byteRate,
            read.format.sampleRate * UInt32(read.format.blockAlign)
        )
        XCTAssertEqual(read.format.blockAlign, read.format.channels * read.format.bitsPerSample / 8)
        XCTAssertEqual(read.samples.count, 6)
        XCTAssertEqual(file.prefix(4), Data("RIFF".utf8))
        XCTAssertEqual(file.dropFirst(8).prefix(4), Data("WAVE".utf8))
        XCTAssertThrowsError(try WaveFile(waveData: Data(file.prefix(20))))

        try assertCoderRoundTrip(wave, endianness: .little)
    }
}

// MARK: - WAVE

/// PCM WAVE: a RIFF container, a 16-byte `fmt ` chunk, and little-endian samples.
private struct WaveFile: Codable, Equatable {
    var format: Format
    var samples: [Int16]

    struct Format: Codable, Equatable {
        var audioFormat: UInt16
        var channels: UInt16
        var sampleRate: UInt32
        var byteRate: UInt32
        var blockAlign: UInt16
        var bitsPerSample: UInt16
    }

    func waveData() -> Data {
        let pcm = samples.littleEndianPCM()
        var data = Data()
        data.appendASCII("RIFF")
        data.appendU32(UInt32(36 + pcm.count), littleEndian: true)
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendU32(16, littleEndian: true)
        data.appendU16(format.audioFormat, littleEndian: true)
        data.appendU16(format.channels, littleEndian: true)
        data.appendU32(format.sampleRate, littleEndian: true)
        data.appendU32(format.byteRate, littleEndian: true)
        data.appendU16(format.blockAlign, littleEndian: true)
        data.appendU16(format.bitsPerSample, littleEndian: true)
        data.appendASCII("data")
        data.appendU32(UInt32(pcm.count), littleEndian: true)
        data.append(pcm)
        return data
    }

    init(format: Format, samples: [Int16]) {
        self.format = format
        self.samples = samples
    }

    init(waveData data: Data) throws {
        var cursor = BinaryCursor(data: data, littleEndian: true)
        guard try cursor.ascii(4) == "RIFF" else { throw FormatReadError("WAVE file does not start with RIFF.") }
        _ = try cursor.u32()
        guard try cursor.ascii(4) == "WAVE" else { throw FormatReadError("RIFF format is not WAVE.") }

        var format: Format?
        var samples: [Int16]?
        while !cursor.isAtEnd {
            let chunkID = try cursor.ascii(4)
            let chunkSize = Int(try cursor.u32())
            let payload = try cursor.bytes(chunkSize)
            if chunkSize % 2 == 1, !cursor.isAtEnd {
                _ = try cursor.u8()
            }
            switch chunkID {
            case "fmt ":
                guard payload.count >= 16 else { throw FormatReadError("fmt chunk is shorter than 16 bytes.") }
                var fmt = BinaryCursor(data: payload, littleEndian: true)
                format = Format(
                    audioFormat: try fmt.u16(),
                    channels: try fmt.u16(),
                    sampleRate: try fmt.u32(),
                    byteRate: try fmt.u32(),
                    blockAlign: try fmt.u16(),
                    bitsPerSample: try fmt.u16()
                )
            case "data":
                guard payload.count % 2 == 0 else { throw FormatReadError("PCM payload is not a whole number of samples.") }
                samples = try payload.int16Samples()
            default:
                break
            }
        }
        guard let format, let samples else { throw FormatReadError("WAVE file is missing fmt or data.") }
        self.format = format
        self.samples = samples
    }
}

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

private func required<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else { throw FormatReadError(message) }
    return value
}

private func assertCoderRoundTrip<T: Codable & Equatable>(
    _ value: T,
    endianness: BinaryEndianness,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let encoder = BinaryEncoder()
    encoder.endianness = endianness
    let decoder = BinaryDecoder()
    decoder.endianness = endianness
    let encoded = try encoder.encode(value)
    let decoded = try decoder.decode(T.self, from: encoded)
    XCTAssertEqual(decoded, value, file: file, line: line)
}
