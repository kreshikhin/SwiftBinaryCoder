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

    func testWriteAndReadBMP() throws {
        // Row-major, top to bottom. BMP stores rows bottom to top, in BGR order.
        let image = BMPImage(
            width: 2,
            height: 2,
            pixelsPerMeter: 2_835,
            pixels: [
                BMPImage.Pixel(blue: 255, green: 0, red: 0),
                BMPImage.Pixel(blue: 0, green: 0, red: 255),
                BMPImage.Pixel(blue: 0, green: 255, red: 0),
                BMPImage.Pixel(blue: 255, green: 255, red: 255),
            ]
        )

        let file = image.bmpData()
        let read = try BMPImage(bmpData: file)

        XCTAssertEqual(read, image)
        XCTAssertEqual(file.prefix(2), Data("BM".utf8))
        XCTAssertEqual(file.count, 14 + 40 + 16)
        XCTAssertEqual(read.pixels.count, Int(read.width) * Int(read.height))
        XCTAssertThrowsError(try BMPImage(bmpData: Data(file.prefix(30))))

        try assertCoderRoundTrip(image, endianness: .little)
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

// MARK: - BMP

/// 24-bit uncompressed BMP. Rows are bottom-up and padded to a multiple of four bytes.
private struct BMPImage: Codable, Equatable {
    var width: Int32
    var height: Int32
    var pixelsPerMeter: Int32
    var pixels: [Pixel]

    struct Pixel: Codable, Equatable {
        var blue: UInt8
        var green: UInt8
        var red: UInt8
    }

    func bmpData() -> Data {
        let rowStride = ((Int(width) * 3 + 3) / 4) * 4
        var raster = Data(count: rowStride * Int(height))
        for y in 0..<Int(height) {
            let sourceRow = Int(height) - 1 - y
            for x in 0..<Int(width) {
                let pixel = pixels[sourceRow * Int(width) + x]
                let offset = y * rowStride + x * 3
                raster[offset] = pixel.blue
                raster[offset + 1] = pixel.green
                raster[offset + 2] = pixel.red
            }
        }

        var data = Data()
        data.appendASCII("BM")
        data.appendU32(UInt32(14 + 40 + raster.count), littleEndian: true)
        data.appendU16(0, littleEndian: true)
        data.appendU16(0, littleEndian: true)
        data.appendU32(54, littleEndian: true)
        data.appendU32(40, littleEndian: true)
        data.appendI32(width, littleEndian: true)
        data.appendI32(height, littleEndian: true)
        data.appendU16(1, littleEndian: true)
        data.appendU16(24, littleEndian: true)
        data.appendU32(0, littleEndian: true)
        data.appendU32(UInt32(raster.count), littleEndian: true)
        data.appendI32(pixelsPerMeter, littleEndian: true)
        data.appendI32(pixelsPerMeter, littleEndian: true)
        data.appendU32(0, littleEndian: true)
        data.appendU32(0, littleEndian: true)
        data.append(raster)
        return data
    }

    init(width: Int32, height: Int32, pixelsPerMeter: Int32, pixels: [Pixel]) {
        self.width = width
        self.height = height
        self.pixelsPerMeter = pixelsPerMeter
        self.pixels = pixels
    }

    init(bmpData data: Data) throws {
        var cursor = BinaryCursor(data: data, littleEndian: true)
        guard try cursor.ascii(2) == "BM" else { throw FormatReadError("BMP file does not start with BM.") }
        _ = try cursor.u32()
        _ = try cursor.u16()
        _ = try cursor.u16()
        let pixelOffset = Int(try cursor.u32())
        let headerSize = try cursor.u32()
        guard headerSize >= 40 else { throw FormatReadError("BMP info header is too small.") }
        let width = try cursor.i32()
        let height = try cursor.i32()
        _ = try cursor.u16()
        let bitCount = try cursor.u16()
        let compression = try cursor.u32()
        _ = try cursor.u32()
        let pixelsPerMeter = try cursor.i32()
        _ = try cursor.i32()
        guard bitCount == 24, compression == 0, width > 0, height > 0 else {
            throw FormatReadError("Only uncompressed 24-bit BMP images are read here.")
        }
        guard pixelOffset <= data.count else { throw FormatReadError("BMP pixel offset is past the end of the file.") }

        let rowStride = ((Int(width) * 3 + 3) / 4) * 4
        var pixels: [Pixel] = []
        pixels.reserveCapacity(Int(width * height))
        for y in 0..<Int(height) {
            let sourceRow = Int(height) - 1 - y
            let rowStart = pixelOffset + sourceRow * rowStride
            guard rowStart + Int(width) * 3 <= data.count else { throw FormatReadError("BMP raster is truncated.") }
            for x in 0..<Int(width) {
                let offset = rowStart + x * 3
                pixels.append(Pixel(blue: data[offset], green: data[offset + 1], red: data[offset + 2]))
            }
        }
        self.width = width
        self.height = height
        self.pixelsPerMeter = pixelsPerMeter
        self.pixels = pixels
    }
}

// MARK: - TIFF

/// Baseline TIFF: an 8-byte header, one IFD, and a single 8-bit strip.
private struct TIFFImage: Codable, Equatable {
    var littleEndian: Bool
    var width: UInt32
    var height: UInt32
    var bitsPerSample: UInt16
    var compression: UInt16
    var photometric: UInt16
    var samplesPerPixel: UInt16
    var pixels: Data

    func tiffData() -> Data {
        let stripOffset: UInt32 = 122
        var data = Data()
        data.append(contentsOf: littleEndian ? [0x49, 0x49] : [0x4D, 0x4D])
        data.appendU16(42, littleEndian: littleEndian)
        data.appendU32(8, littleEndian: littleEndian)
        data.appendU16(9, littleEndian: littleEndian)
        appendField(256, type: 4, value: width, to: &data)
        appendField(257, type: 4, value: height, to: &data)
        appendField(258, type: 3, value: UInt32(bitsPerSample), to: &data)
        appendField(259, type: 3, value: UInt32(compression), to: &data)
        appendField(262, type: 3, value: UInt32(photometric), to: &data)
        appendField(273, type: 4, value: stripOffset, to: &data)
        appendField(277, type: 3, value: UInt32(samplesPerPixel), to: &data)
        appendField(278, type: 4, value: height, to: &data)
        appendField(279, type: 4, value: UInt32(pixels.count), to: &data)
        data.appendU32(0, littleEndian: littleEndian)
        data.append(pixels)
        return data
    }

    init(
        littleEndian: Bool,
        width: UInt32,
        height: UInt32,
        bitsPerSample: UInt16,
        compression: UInt16,
        photometric: UInt16,
        samplesPerPixel: UInt16,
        pixels: Data
    ) {
        self.littleEndian = littleEndian
        self.width = width
        self.height = height
        self.bitsPerSample = bitsPerSample
        self.compression = compression
        self.photometric = photometric
        self.samplesPerPixel = samplesPerPixel
        self.pixels = pixels
    }

    init(tiffData data: Data) throws {
        guard data.count >= 8 else { throw FormatReadError("TIFF header is truncated.") }
        let littleEndian: Bool
        switch (data[0], data[1]) {
        case (0x49, 0x49): littleEndian = true
        case (0x4D, 0x4D): littleEndian = false
        default: throw FormatReadError("TIFF byte order is neither II nor MM.")
        }
        var cursor = BinaryCursor(data: data, littleEndian: littleEndian)
        _ = try cursor.bytes(2)
        guard try cursor.u16() == 42 else { throw FormatReadError("TIFF magic is not 42.") }
        let ifdOffset = Int(try cursor.u32())
        guard ifdOffset + 2 <= data.count else { throw FormatReadError("TIFF IFD offset is past the end of the file.") }
        cursor.index = ifdOffset
        let count = Int(try cursor.u16())
        var fields: [UInt16: UInt32] = [:]
        for _ in 0..<count {
            let tag = try cursor.u16()
            let type = try cursor.u16()
            _ = try cursor.u32()
            let raw = try cursor.u32()
            let value = type == 3 ? (littleEndian ? raw & 0xFFFF : raw >> 16) : raw
            fields[tag] = value
        }
        guard
            let width = fields[256],
            let height = fields[257],
            let bits = fields[258],
            let compression = fields[259],
            let photometric = fields[262],
            let samples = fields[277],
            let stripOffset = fields[273],
            let stripCount = fields[279]
        else {
            throw FormatReadError("TIFF IFD is missing an image field.")
        }
        let start = Int(stripOffset)
        let end = start + Int(stripCount)
        guard end <= data.count else { throw FormatReadError("TIFF strip is past the end of the file.") }
        self.littleEndian = littleEndian
        self.width = width
        self.height = height
        self.bitsPerSample = UInt16(bits)
        self.compression = UInt16(compression)
        self.photometric = UInt16(photometric)
        self.samplesPerPixel = UInt16(samples)
        self.pixels = data.subdata(in: start..<end)
    }

    private func appendField(_ tag: UInt16, type: UInt16, value: UInt32, to data: inout Data) {
        let stored = type == 3 && !littleEndian ? value << 16 : value
        data.appendU16(tag, littleEndian: littleEndian)
        data.appendU16(type, littleEndian: littleEndian)
        data.appendU32(1, littleEndian: littleEndian)
        data.appendU32(stored, littleEndian: littleEndian)
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
