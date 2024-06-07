# SwiftBinaryCoder

Encode and decode Swift `Codable` values as a compact binary document.

A document can hold null, booleans, signed and unsigned integers, float32, float64, UTF-8 strings, raw bytes, arrays, maps, timestamps, and typed extension blobs. Integers and lengths use the smallest width that fits, and multi-byte numbers are big-endian by default.

```swift
import SwiftBinaryCoder

struct Player: Codable {
    var name: String
    var score: Int
    var avatar: Data
}

let data = try BinaryEncoder().encode(player)
let copy = try BinaryDecoder().decode(Player.self, from: data)
```

`String` and `Data` stay distinct. `Date` is a timestamp (`float64` seconds since 1970) unless you pick another date strategy. `BinaryExtension` and types that adopt `BinaryExtensible` are extension blobs: a type code plus raw bytes.

```swift
struct Token: Codable, BinaryExtensible {
    var raw: UInt8
    static var binaryExtType: Int8 { 7 }
    var binaryExtData: Data { Data([raw]) }
    init(raw: UInt8) { self.raw = raw }
    init(binaryExtData: Data) throws { raw = binaryExtData.first ?? 0 }
}
```

Encoder and decoder must agree on endianness and on the date, data, float, and key strategies. Key strategies match `JSONEncoder`: `.useDefaultKeys`, `.convertToSnakeCase`, and `.convertFromSnakeCase`.
