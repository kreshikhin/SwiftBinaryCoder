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

let player = Player(name: "Ada", score: 7, avatar: Data([0x01, 0x02]))
let data = try BinaryEncoder().encode(player)
let copy = try BinaryDecoder().decode(Player.self, from: data)
```

`data` is one map of three fields. The default byte order is big-endian:

```text
16 03
   0D 04 6E 61 6D 65          "name"
   0D 03 41 64 61             "Ada"
   0D 05 73 63 6F 72 65       "score"
   03 07                      7
   0D 06 61 76 61 74 61 72    "avatar"
   10 02 01 02                Data([0x01, 0x02])
```

Each value kind has its own page, with the same kind of hex dump, in the [wiki](docs/Home.md).

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
