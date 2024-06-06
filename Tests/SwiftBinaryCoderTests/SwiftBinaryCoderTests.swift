import Foundation
import XCTest
@testable import SwiftBinaryCoder

final class SwiftBinaryCoderTests: XCTestCase {
    func testScalarBytes() throws {
        XCTAssertEqual(try bytes(false), [0x01])
        XCTAssertEqual(try bytes(true), [0x02])
        XCTAssertEqual(try bytes(Optional<Int>.none), [0x00])
        XCTAssertEqual(try bytes(Int(1)), [0x03, 0x01])
        XCTAssertEqual(try bytes(Int8(-5)), [0x03, 0xFB])
        XCTAssertEqual(try bytes(Int(200)), [0x04, 0x00, 0xC8])
        XCTAssertEqual(try bytes(Int16(0x0102)), [0x04, 0x01, 0x02])
        XCTAssertEqual(try bytes(UInt(1)), [0x07, 0x01])
        XCTAssertEqual(try bytes(UInt8(255)), [0x07, 0xFF])
        XCTAssertEqual(try bytes(UInt(256)), [0x08, 0x01, 0x00])
        XCTAssertEqual(try bytes("A"), [0x0D, 0x01, 0x41])
        XCTAssertEqual(try bytes(""), [0x0D, 0x00])
        XCTAssertEqual(try bytes(Data([0xFF])), [0x10, 0x01, 0xFF])
        XCTAssertEqual(try bytes(Data()), [0x10, 0x00])
        XCTAssertEqual(try bytes([Int]()), [0x13, 0x00])
        XCTAssertEqual(try bytes([String: Int]()), [0x16, 0x00])
        XCTAssertEqual(try bytes(Float(1)), [0x0B, 0x3F, 0x80, 0x00, 0x00])
    }

    func testLittleEndianDiffersAndRoundTrips() throws {
        var big = BinaryEncoder()
        big.endianness = .big
        var little = BinaryEncoder()
        little.endianness = .little

        let bigBytes = try big.encode(Int16(0x0102))
        let littleBytes = try little.encode(Int16(0x0102))
        XCTAssertEqual([UInt8](bigBytes), [0x04, 0x01, 0x02])
        XCTAssertEqual([UInt8](littleBytes), [0x04, 0x02, 0x01])

        var littleDecoder = BinaryDecoder()
        littleDecoder.endianness = .little
        XCTAssertEqual(try littleDecoder.decode(Int16.self, from: littleBytes), 0x0102)
        XCTAssertEqual(try BinaryDecoder().decode(Int.self, from: bigBytes), 0x0102)
    }

    func testIntegerWideningAndOverflow() throws {
        let small = try BinaryEncoder().encode(Int8(4))
        XCTAssertEqual(try BinaryDecoder().decode(Int.self, from: small), 4)
        XCTAssertEqual(try BinaryDecoder().decode(Int64.self, from: small), 4)

        let wide = try BinaryEncoder().encode(Int(200))
        XCTAssertThrowsError(try BinaryDecoder().decode(Int8.self, from: wide))

        let negative = try BinaryEncoder().encode(Int8(-1))
        XCTAssertThrowsError(try BinaryDecoder().decode(UInt8.self, from: negative))

        let huge = try BinaryEncoder().encode(UInt64.max)
        XCTAssertEqual(try BinaryDecoder().decode(UInt64.self, from: huge), .max)
        XCTAssertThrowsError(try BinaryDecoder().decode(Int.self, from: huge))

        let text = try BinaryEncoder().encode("nope")
        XCTAssertThrowsError(try BinaryDecoder().decode(Bool.self, from: text))
        XCTAssertThrowsError(try BinaryDecoder().decode(Int.self, from: try BinaryEncoder().encode(1.5)))
    }

    func testStringDataAndCollections() throws {
        try assertRoundTrip("привет 🙂")
        try assertRoundTrip(Data([0x00, 0xFF, 0x10, 0x80]))
        try assertRoundTrip([1, nil, 2] as [Int?])
        try assertRoundTrip(["a": 1, "b": 2])
        try assertRoundTrip([0: "zero", -4: "neg", 300: "wide"])
        try assertRoundTrip([[1, 2], [3]])

        let long = String(repeating: "x", count: 256)
        let encoded = try BinaryEncoder().encode(long)
        XCTAssertEqual(encoded.first, 0x0E)
        XCTAssertEqual(try BinaryDecoder().decode(String.self, from: encoded), long)
    }

    func testStructMapIsKeyedNotPositional() throws {
        struct Pair: Codable, Equatable {
            var x: Int8
            var name: String
        }
        let value = Pair(x: 7, name: "ab")
        XCTAssertEqual(
            try bytes(value),
            [0x16, 0x02, 0x0D, 0x01, 0x78, 0x03, 0x07, 0x0D, 0x04, 0x6E, 0x61, 0x6D, 0x65, 0x0D, 0x02, 0x61, 0x62]
        )

        // name, then x. Decoding still finds fields by key.
        let reversed: [UInt8] = [
            0x16, 0x02,
            0x0D, 0x04, 0x6E, 0x61, 0x6D, 0x65, 0x0D, 0x02, 0x61, 0x62,
            0x0D, 0x01, 0x78, 0x03, 0x07,
        ]
        XCTAssertEqual(try BinaryDecoder().decode(Pair.self, from: Data(reversed)), value)
    }

    func testNestedModelsEnumsAndCommonFoundationTypes() throws {
        struct Address: Codable, Equatable {
            var city: String
            var zip: Int
        }
        struct User: Codable, Equatable {
            var name: String
            var address: Address
            var tags: [String]
            var subtitle: String?
        }
        try assertRoundTrip(User(name: "Ada", address: Address(city: "London", zip: 1), tags: ["a"], subtitle: nil))
        try assertRoundTrip(User(name: "Ada", address: Address(city: "London", zip: 1), tags: [], subtitle: "x"))

        try assertRoundTrip(Event.started)
        try assertRoundTrip(Event.message("hi"))
        try assertRoundTrip(Event.moved(x: 3, y: -1))
        try assertRoundTrip(Color.blue)
        try assertRoundTrip(Code.b)

        let id = UUID(uuidString: "123E4567-E89B-12D3-A456-426614174000")!
        let document = Document(
            id: id,
            title: "Notes",
            count: 3,
            ratio: 1.25,
            payload: Data([9, 8, 7]),
            link: URL(string: "https://example.com/a b")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            score: Decimal(string: "-12.50")!
        )
        try assertRoundTrip(document)
    }

    func testDateAndDataStrategies() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000.5)
        let stamp = try bytes(date)
        XCTAssertEqual(stamp.first, 0x19)
        try assertRoundTrip(date)

        var secondsEncoder = BinaryEncoder()
        secondsEncoder.dateEncodingStrategy = .secondsSince1970
        var secondsDecoder = BinaryDecoder()
        secondsDecoder.dateDecodingStrategy = .secondsSince1970
        let seconds = try secondsEncoder.encode(date)
        XCTAssertEqual(seconds.first, 0x0C)
        XCTAssertEqual(try secondsDecoder.decode(Date.self, from: seconds), date)

        var milliEncoder = BinaryEncoder()
        milliEncoder.dateEncodingStrategy = .millisecondsSince1970
        var milliDecoder = BinaryDecoder()
        milliDecoder.dateDecodingStrategy = .millisecondsSince1970
        XCTAssertEqual(try milliDecoder.decode(Date.self, from: try milliEncoder.encode(date)), date)

        var isoEncoder = BinaryEncoder()
        isoEncoder.dateEncodingStrategy = .iso8601
        var isoDecoder = BinaryDecoder()
        isoDecoder.dateDecodingStrategy = .iso8601
        let whole = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(try isoDecoder.decode(Date.self, from: try isoEncoder.encode(whole)), whole)

        var deferredEncoder = BinaryEncoder()
        deferredEncoder.dateEncodingStrategy = .deferredToDate
        var deferredDecoder = BinaryDecoder()
        deferredDecoder.dateDecodingStrategy = .deferredToDate
        XCTAssertEqual(try deferredDecoder.decode(Date.self, from: try deferredEncoder.encode(date)), date)

        var customEncoder = BinaryEncoder()
        customEncoder.dateEncodingStrategy = .custom { value, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Int64(value.timeIntervalSince1970))
        }
        var customDecoder = BinaryDecoder()
        customDecoder.dateDecodingStrategy = .custom { decoder in
            let seconds = try decoder.singleValueContainer().decode(Int64.self)
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        }
        XCTAssertEqual(
            try customDecoder.decode(Date.self, from: try customEncoder.encode(whole)).timeIntervalSince1970,
            whole.timeIntervalSince1970
        )

        let payload = Data([0x00, 0x01, 0xFF])
        XCTAssertEqual(try bytes(payload).first, 0x10)
        try assertRoundTrip(payload)

        var base64Encoder = BinaryEncoder()
        base64Encoder.dataEncodingStrategy = .base64
        var base64Decoder = BinaryDecoder()
        base64Decoder.dataDecodingStrategy = .base64
        XCTAssertEqual(try base64Decoder.decode(Data.self, from: try base64Encoder.encode(payload)), payload)

        var deferredDataEncoder = BinaryEncoder()
        deferredDataEncoder.dataEncodingStrategy = .deferredToData
        var deferredDataDecoder = BinaryDecoder()
        deferredDataDecoder.dataDecodingStrategy = .deferredToData
        let deferredData = try deferredDataEncoder.encode(payload)
        XCTAssertEqual(deferredData.first, 0x13)
        XCTAssertEqual(try deferredDataDecoder.decode(Data.self, from: deferredData), payload)
    }

    func testExtensionTypes() throws {
        let ext = BinaryExtension(type: 7, data: Data([1, 2, 3]))
        XCTAssertEqual(try bytes(ext), [0x1A, 0x07, 0x03, 0x01, 0x02, 0x03])
        try assertRoundTrip(ext)

        let token = Token(raw: 9)
        XCTAssertEqual(try bytes(token).first, 0x1A)
        try assertRoundTrip(token)
        XCTAssertThrowsError(try BinaryDecoder().decode(Token.self, from: try BinaryEncoder().encode(BinaryExtension(type: 1, data: Data([9])))))
    }

    func testSnakeCaseMatchesJSONEncoder() throws {
        struct Keys: Codable, Equatable {
            var simpleOneTwo: Int = 1
            var myURLProperty: Int = 2
            var myURL: Int = 3
            var fromA: Int = 4
            var _oneTwoThree_: Int = 5
            var already_snake: Int = 6
            var userName: Int = 7
            var id: Int = 8
        }
        let value = Keys()
        var binary = BinaryEncoder()
        binary.keyEncodingStrategy = .convertToSnakeCase
        var json = JSONEncoder()
        json.keyEncodingStrategy = .convertToSnakeCase
        json.outputFormatting = [.sortedKeys]

        let binaryKeys = try BinaryDecoder().decode([String: Int].self, from: try binary.encode(value))
        let jsonKeys = try JSONDecoder().decode([String: Int].self, from: try json.encode(value))
        XCTAssertEqual(binaryKeys, jsonKeys)

        struct Round: Codable, Equatable {
            var userName: String
            var simpleOneTwo: Int
            var _oneTwoThree_: Int
            var id: Int
        }
        var decoder = BinaryDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let round = Round(userName: "a", simpleOneTwo: 2, _oneTwoThree_: 3, id: 4)
        XCTAssertEqual(try decoder.decode(Round.self, from: try binary.encode(round)), round)
    }

    func testFloatsOptionalsInheritanceAndUserInfo() throws {
        try assertRoundTrip(Double(1.25))
        XCTAssertEqual(try BinaryDecoder().decode(Float.self, from: try BinaryEncoder().encode(Double(1.5))), 1.5)

        var negativeZero = -0.0
        let decodedZero = try BinaryDecoder().decode(Double.self, from: try BinaryEncoder().encode(negativeZero))
        XCTAssertEqual(decodedZero.bitPattern, negativeZero.bitPattern)

        let nan = Double.nan
        XCTAssertTrue(try BinaryDecoder().decode(Double.self, from: try BinaryEncoder().encode(nan)).isNaN)

        var strict = BinaryEncoder()
        strict.nonConformingFloatEncodingStrategy = .throw
        struct Outer: Encodable {
            var inner: Inner
            struct Inner: Encodable { var value: Double }
        }
        XCTAssertThrowsError(try strict.encode(Outer(inner: Outer.Inner(value: .infinity)))) { error in
            guard case EncodingError.invalidValue(_, let context) = error else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertEqual(context.codingPath.map(\.stringValue), ["inner", "value"])
        }

        struct OptionalFields: Codable, Equatable {
            var required: Int
            var note: String?
        }
        XCTAssertEqual(
            try BinaryDecoder().decode(OptionalFields.self, from: try BinaryEncoder().encode(OptionalFields(required: 1, note: nil))),
            OptionalFields(required: 1, note: nil)
        )

        struct Manual: Codable, Equatable {
            var kept: Int?
            var dropped: Int?
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeIfPresent(kept, forKey: .kept)
                try container.encodeIfPresent(dropped, forKey: .dropped)
            }
        }
        let manual = try BinaryEncoder().encode(Manual(kept: 5, dropped: nil))
        struct Probe: Decodable {
            var keys: Set<String>
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: BinaryCodingKey.self)
                keys = Set(container.allKeys.map(\.stringValue))
            }
        }
        XCTAssertEqual(try BinaryDecoder().decode(Probe.self, from: manual).keys, ["kept"])

        let child = Child(a: 4, b: "dog")
        let decodedChild = try BinaryDecoder().decode(Child.self, from: try BinaryEncoder().encode(child))
        XCTAssertEqual(decodedChild.a, 4)
        XCTAssertEqual(decodedChild.b, "dog")

        struct Carrier: Codable, Equatable {
            var value: String
            static let prefixKey = CodingUserInfoKey(rawValue: "prefix")!
            init(value: String) { self.value = value }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let prefix = decoder.userInfo[Self.prefixKey] as? String ?? ""
                value = prefix + (try container.decode(String.self, forKey: .value))
            }
        }
        var encoder = BinaryEncoder()
        var decoder = BinaryDecoder()
        decoder.userInfo[Carrier.prefixKey] = "id:"
        XCTAssertEqual(try decoder.decode(Carrier.self, from: try encoder.encode(Carrier(value: "7"))), Carrier(value: "id:7"))
    }

    func testCorruptPayloads() throws {
        XCTAssertThrowsError(try BinaryDecoder().decode(Int.self, from: Data()))
        var extra = try BinaryEncoder().encode(Int(1))
        extra.append(0x00)
        XCTAssertThrowsError(try BinaryDecoder().decode(Int.self, from: extra))
        XCTAssertThrowsError(try BinaryDecoder().decode(String.self, from: Data([0x0D, 0x01, 0xFF])))
        XCTAssertThrowsError(try BinaryDecoder().decode(Int.self, from: Data([0x7F])))
        XCTAssertThrowsError(try BinaryDecoder().decode(Int.self, from: Data([0x04, 0x01])))

        struct NeedsName: Decodable {
            var name: String
        }
        XCTAssertThrowsError(try BinaryDecoder().decode(NeedsName.self, from: try BinaryEncoder().encode(Empty()))) { error in
            guard case DecodingError.keyNotFound(let key, _) = error else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertEqual(key.stringValue, "name")
        }
        XCTAssertThrowsError(try BinaryDecoder().decode(Int.self, from: try BinaryEncoder().encode(Optional<Int>.none)))
    }

    private func bytes<T: Encodable>(_ value: T) throws -> [UInt8] {
        [UInt8](try BinaryEncoder().encode(value))
    }

    private func assertRoundTrip<T: Codable & Equatable>(
        _ value: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let decoded = try BinaryDecoder().decode(T.self, from: try BinaryEncoder().encode(value))
        XCTAssertEqual(decoded, value, file: file, line: line)
    }
}

private struct Empty: Codable {}

private struct Document: Codable, Equatable {
    var id: UUID
    var title: String
    var count: Int
    var ratio: Double
    var payload: Data
    var link: URL
    var createdAt: Date
    var score: Decimal
}

private enum Event: Codable, Equatable {
    case started
    case message(String)
    case moved(x: Int, y: Int)
}

private enum Color: String, Codable, Equatable {
    case red
    case blue
}

private enum Code: Int, Codable, Equatable {
    case a = 3
    case b = 9
}

private struct Token: Codable, BinaryExtensible, Equatable {
    var raw: UInt8

    static var binaryExtType: Int8 { 7 }

    init(raw: UInt8) {
        self.raw = raw
    }

    init(binaryExtData: Data) throws {
        guard let byte = binaryExtData.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Empty token."))
        }
        raw = byte
    }

    var binaryExtData: Data { Data([raw]) }
}

private class Base: Codable {
    var a: Int

    init(a: Int) {
        self.a = a
    }

    enum CodingKeys: String, CodingKey { case a }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        a = try container.decode(Int.self, forKey: .a)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(a, forKey: .a)
    }
}

private final class Child: Base {
    var b: String

    init(a: Int, b: String) {
        self.b = b
        super.init(a: a)
    }

    enum ChildKeys: String, CodingKey { case b }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ChildKeys.self)
        b = try container.decode(String.self, forKey: .b)
        try super.init(from: container.superDecoder())
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ChildKeys.self)
        try container.encode(b, forKey: .b)
        try super.encode(to: container.superEncoder())
    }
}
