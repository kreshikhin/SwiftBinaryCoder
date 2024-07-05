# Data

[Home](Home.md)

`Data` is a raw byte blob. The default strategy, `.binary`, uses the binary tags so a blob stays distinct from a [string](Strings.md) even when the bytes happen to be text.

| Byte length | Tag | Length field |
| --- | --- | --- |
| 0...255 | `10` | 1 byte |
| 256...65535 | `11` | 2 bytes |
| 65536...4294967295 | `12` | 4 bytes |

```swift
try BinaryEncoder().encode(Data())
// 10 00

try BinaryEncoder().encode(Data([0xFF]))
// 10 01 FF

try BinaryEncoder().encode(Data([0x00, 0x01, 0xFF]))
// 10 03 00 01 FF
```

256 bytes use bin16. Big-endian length:

```text
11 01 00
   AB AB AB ...    256 payload bytes
```

The decoder, with `.binary`, accepts only a binary tag. A string of the same bytes is a type mismatch.

## Base64

`.base64` writes `Data.base64EncodedString()` as a normal string. `Data([0x00, 0x01, 0xFF])` is the string `AAH/`:

```swift
var encoder = BinaryEncoder()
encoder.dataEncodingStrategy = .base64
try encoder.encode(Data([0x00, 0x01, 0xFF]))
```

```text
0D 04 41 41 48 2F
```

The matching decoder strategy is `.base64`. It rejects a string that is not Base64.

## Deferred to `Data`

`.deferredToData` lets `Data` encode itself. That implementation writes an unkeyed container of `UInt8`, so the document is an array of unsigned integers:

```swift
var encoder = BinaryEncoder()
encoder.dataEncodingStrategy = .deferredToData
try encoder.encode(Data([0x00, 0x01, 0xFF]))
```

```text
13 03
   07 00
   07 01
   07 FF
```

`13 03` is an array of three values. Each `07` is uint8. Decode with `.deferredToData`.

## Custom

`.custom` receives the `Data` and an `Encoder`. The closure writes whatever container it wants. A closure that writes nothing produces an empty map, `16 00`.
