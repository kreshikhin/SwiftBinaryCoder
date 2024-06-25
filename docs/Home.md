# SwiftBinaryCoder

`BinaryEncoder` writes one Swift value as a self-describing binary document. `BinaryDecoder` reads that document back into any compatible `Decodable` type. There is no separate schema: a `Codable` type uses the same keyed, unkeyed, and single-value containers as `JSONEncoder`.

A document is exactly one value. Bytes after that value are rejected. The default byte order is big-endian, and the encoder and decoder must use the same endianness and the same date, data, float, and key strategies.

This is the library document, not a WAV, TIFF, JPEG, or BMP file. Those layouts are independent examples in the test suite.

## Tags

Every value starts with one tag byte.

| Tag | Value | Payload |
| --- | --- | --- |
| `00` | null | nothing |
| `01` | false | nothing |
| `02` | true | nothing |
| `03` `04` `05` `06` | int8, int16, int32, int64 | signed integer |
| `07` `08` `09` `0A` | uint8, uint16, uint32, uint64 | unsigned integer |
| `0B` | float32 | 4 bytes, IEEE 754 |
| `0C` | float64 | 8 bytes, IEEE 754 |
| `0D` `0E` `0F` | str8, str16, str32 | length, then UTF-8 |
| `10` `11` `12` | bin8, bin16, bin32 | length, then raw bytes |
| `13` `14` `15` | array8, array16, array32 | count, then values |
| `16` `17` `18` | map8, map16, map32 | count, then key/value pairs |
| `19` | timestamp | float64 seconds since 1970-01-01T00:00:00Z |
| `1A` `1B` `1C` | ext8, ext16, ext32 | int8 type, length, then bytes |

Integers and lengths use the smallest width that fits. A length of 0...255 uses the 8-bit form, 256...65535 the 16-bit form, and anything larger the 32-bit form. Multi-byte numbers, including those lengths, use the encoder's endianness. The tag itself is always one byte.

Map keys are full values. A struct field is a string key. An integer coding key whose `stringValue` is the decimal text of its `intValue` is written as an integer.

## A struct, in hex

```swift
struct Player: Codable {
    var name: String
    var score: Int
    var avatar: Data
}

let player = Player(name: "Ada", score: 7, avatar: Data([0x01, 0x02]))
let data = try BinaryEncoder().encode(player)
```

```text
16 03
   0D 04 6E 61 6D 65          "name"
   0D 03 41 64 61             "Ada"
   0D 05 73 63 6F 72 65       "score"
   03 07                      7
   0D 06 61 76 61 74 61 72    "avatar"
   10 02 01 02                Data([0x01, 0x02])
```

`16 03` is a map of three pairs. `03 07` is a signed int8 because 7 fits in one byte. The avatar is a binary blob, not a string. The same bytes are decoded with `BinaryDecoder().decode(Player.self, from: data)`.

## Pages

| Page | What it covers |
| --- | --- |
| [Null](Null.md) | `nil` and `encodeNil` |
| [Booleans](Booleans.md) | `Bool` |
| [Integers](Integers.md) | signed and unsigned widths |
| [Floating point](Floating-Point.md) | `Float`, `Double`, NaN, and infinities |
| [Strings](Strings.md) | UTF-8 text |
| [Data](Data.md) | raw bytes, Base64, and byte arrays |
| [Arrays](Arrays.md) | arrays and unkeyed containers |
| [Maps](Maps.md) | structs, dictionaries, and integer keys |
| [Dates](Dates.md) | timestamps and the other date strategies |
| [Extensions](Extensions.md) | `BinaryExtension` and `BinaryExtensible` |
| [Optionals](Optionals.md) | omitted keys, null, and `Optional` |
| [Enums](Enums.md) | cases, associated values, and raw values |
| [URL](URL.md) | absolute URL strings |
| [UUID](UUID.md) | the canonical UUID string |
| [Decimal](Decimal.md) | Foundation's decimal encoding |
| [Nested values](Nested-Values.md) | a struct that contains a struct and an array |
| [Classes](Classes.md) | `superEncoder` |
| [Strategies](Strategies.md) | endianness, keys, and the switches that change the bytes |
