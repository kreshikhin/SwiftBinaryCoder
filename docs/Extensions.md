# Extensions

[Home](Home.md)

An extension is an application type code plus a raw payload. The type code is an `Int8`, including negative values, stored as one byte. The length uses the same 8/16/32 split as a binary blob, and that length follows the encoder's endianness.

| Payload length | Tag | Layout |
| --- | --- | --- |
| 0...255 | `1A` | type, uint8 length, bytes |
| 256...65535 | `1B` | type, uint16 length, bytes |
| 65536...4294967295 | `1C` | type, uint32 length, bytes |

`BinaryEncoder` writes an extension for `BinaryExtension` and for any value that adopts `BinaryExtensible`. Both are intercepted before their normal `encode(to:)`.

## `BinaryExtension`

```swift
let value = BinaryExtension(type: 7, data: Data([1, 2, 3]))
try BinaryEncoder().encode(value)
```

```text
1A 07 03 01 02 03
```

`1A` is ext8, `07` is type 7, `03` is the length, and `01 02 03` is the payload.

An empty payload still carries the type:

```text
1A 07 00
```

Type `-1` is the byte `FF`:

```swift
try BinaryEncoder().encode(BinaryExtension(type: -1, data: Data([0xAA])))
// 1A FF 01 AA
```

A 256-byte payload uses ext16. The header is the tag, the type, and a big-endian length:

```text
1B 07 01 00
   01 01 01 ...
```

`BinaryDecoder` reads an extension back into `BinaryExtension` only from an ext tag. Another tag is a type mismatch.

## `BinaryExtensible`

A type with one fixed type code adopts `BinaryExtensible`. The encoder stores `binaryExtType` and `binaryExtData` and does not call `encode(to:)`.

```swift
struct Token: Codable, BinaryExtensible {
    var raw: UInt8

    static var binaryExtType: Int8 { 7 }

    var binaryExtData: Data { Data([raw]) }

    init(raw: UInt8) { self.raw = raw }

    init(binaryExtData: Data) throws {
        raw = binaryExtData.first ?? 0
    }
}

try BinaryEncoder().encode(Token(raw: 9))
```

```text
1A 07 01 09
```

Decoding calls `init(binaryExtData:)` when the tag is an extension and the type code equals `binaryExtType`. A payload whose type code is different throws `DecodingError.dataCorrupted`. `Token` therefore does not decode a `BinaryExtension` of type 1, even when the payload happens to be one byte.
