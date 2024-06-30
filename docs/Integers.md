# Integers

[Home](Home.md)

`Int`, `Int8`, `Int16`, `Int32`, and `Int64` are signed. `UInt`, `UInt8`, `UInt16`, `UInt32`, and `UInt64` are unsigned. The writer then picks the narrowest width that can hold the number, so the Swift type and the tag are not the same thing: `Int(1)` and `Int8(1)` are both int8.

The tag is one byte. The payload is 1, 2, 4, or 8 bytes in the encoder's endianness. The default is big-endian. Little-endian swaps the payload and leaves the tag where it is.

## Signed widths

| Range | Tag | Width |
| --- | --- | --- |
| -128...127 | `03` | int8 |
| -32768...32767 | `04` | int16 |
| -2147483648...2147483647 | `05` | int32 |
| everything else in `Int64` | `06` | int64 |

```swift
try BinaryEncoder().encode(Int(1))        // 03 01
try BinaryEncoder().encode(Int8(-5))      // 03 FB
try BinaryEncoder().encode(Int(127))      // 03 7F
try BinaryEncoder().encode(Int(-128))     // 03 80
try BinaryEncoder().encode(Int(128))      // 04 00 80
try BinaryEncoder().encode(Int(-129))     // 04 FF 7F
try BinaryEncoder().encode(Int(200))      // 04 00 C8
try BinaryEncoder().encode(Int(32767))    // 04 7F FF
try BinaryEncoder().encode(Int(32768))    // 05 00 00 80 00
try BinaryEncoder().encode(Int(Int32.max))                 // 05 7F FF FF FF
try BinaryEncoder().encode(Int64(Int64(Int32.max) + 1))    // 06 00 00 00 00 80 00 00 00
try BinaryEncoder().encode(Int64.min)                     // 06 80 00 00 00 00 00 00 00
```

`Int16(0x0102)` shows the endianness switch on its own:

```swift
var big = BinaryEncoder()
big.endianness = .big
try big.encode(Int16(0x0102))
// 04 01 02

var little = BinaryEncoder()
little.endianness = .little
try little.encode(Int16(0x0102))
// 04 02 01
```

The decoder must use the same endianness. A big-endian document read as little-endian returns `0x0201`.

## Unsigned widths

| Range | Tag | Width |
| --- | --- | --- |
| 0...255 | `07` | uint8 |
| 256...65535 | `08` | uint16 |
| 65536...4294967295 | `09` | uint32 |
| everything larger | `0A` | uint64 |

```swift
try BinaryEncoder().encode(UInt(1))          // 07 01
try BinaryEncoder().encode(UInt8(255))       // 07 FF
try BinaryEncoder().encode(UInt(256))        // 08 01 00
try BinaryEncoder().encode(UInt(65535))      // 08 FF FF
try BinaryEncoder().encode(UInt(65536))      // 09 00 01 00 00
try BinaryEncoder().encode(UInt(UInt32.max)) // 09 FF FF FF FF
try BinaryEncoder().encode(UInt64(UInt64(UInt32.max) + 1))
// 0A 00 00 00 01 00 00 00 00
try BinaryEncoder().encode(UInt64.max)
// 0A FF FF FF FF FF FF FF FF
```

`UInt(1)` and `Int(1)` are different documents (`07 01` and `03 01`) even though both numbers are 1.

## Decoding

Any signed or unsigned width decodes into any integer type that can hold the number exactly. `Int8(4)` decodes as `Int` and as `Int64`. `Int(200)` does not decode as `Int8`. `Int8(-1)` does not decode as `UInt8`. `UInt64.max` does not decode as `Int`.

A float, a string, or null is not coerced into an integer. `1.5` decoded as `Int` throws a type mismatch, and null throws `valueNotFound`.

An integer can be decoded as `Float` or `Double`. See [Floating point](Floating-Point.md).
