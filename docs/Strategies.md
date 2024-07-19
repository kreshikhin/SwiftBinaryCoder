# Strategies

[Home](Home.md)

The bytes of a value depend on more than its Swift type. `BinaryEncoder` and `BinaryDecoder` have to agree on every strategy below. A mismatch is usually a type error, not a silently different number.

## Endianness

`endianness` is `.big` by default. It applies to multi-byte integers, to 16-bit and 32-bit lengths and counts, and to float32, float64, and timestamp payloads. Tags, int8, uint8, 8-bit lengths, and the extension type byte stay single bytes.

```swift
var encoder = BinaryEncoder()
encoder.endianness = .little
try encoder.encode(Int16(0x0102))
// 04 02 01

try encoder.encode(Float(1))
// 0B 00 00 80 3F
```

The big-endian forms are `04 01 02` and `0B 3F 80 00 00`. A 256-byte string is `0E 01 00 ...` in big-endian and `0E 00 01 ...` in little-endian. See [Integers](Integers.md) and [Floating point](Floating-Point.md).

## Keys

`.useDefaultKeys` writes `CodingKey.stringValue`, except that an integer key whose text is the decimal form of its `intValue` is written as an integer. See [Maps](Maps.md).

`.convertToSnakeCase` uses the same camelCase rules as `JSONEncoder`, and it always writes a string. `userName` becomes `user_name`. `myURLProperty` becomes `my_url_property`.

```text
16 02
   0D 09 75 73 65 72 5F 6E 61 6D 65                   user_name
   0D 03 41 64 61                                     "Ada"
   0D 0F 6D 79 5F 75 72 6C 5F 70 72 6F 70 65 72 74 79 my_url_property
   03 02                                              2
```

Decode with `.convertFromSnakeCase`. The reverse of `my_url_property` is `myUrlProperty`, so a property that was declared `myURLProperty` does not round-trip. `userName`, `simpleOneTwo`, and `_oneTwoThree_` do.

`.custom` replaces the key about to be written. The closure receives the full coding path and returns a `CodingKey`. Only `stringValue` is stored. Integer keys become strings too.

The superclass key is the string `super` before the strategy runs, so snake_case leaves it as `super` and a custom closure can rename it. See [Classes](Classes.md).

## Dates

| Strategy | Tag for `Date(timeIntervalSince1970: 1_700_000_000)` | Bytes |
| --- | --- | --- |
| `.timestamp` | `19` | `19 41 D9 54 FC 40 00 00 00` |
| `.secondsSince1970` | `0C` | `0C 41 D9 54 FC 40 00 00 00` |
| `.iso8601` | `0D` | `0D 14` plus `2023-11-14T22:13:20Z` |
| `.deferredToDate` | `0C` | `0C 41 C5 82 14 40 00 00 00` |
| `.custom` writing `Int64` seconds | `05` | `05 65 53 F1 00` |

Milliseconds and the half-second instant are on the [Dates](Dates.md) page. `.timestamp` does not read a float64, and `.secondsSince1970` does not read a timestamp.

## Data

| Strategy | `Data([0x00, 0x01, 0xFF])` |
| --- | --- |
| `.binary` | `10 03 00 01 FF` |
| `.base64` | `0D 04 41 41 48 2F` |
| `.deferredToData` | `13 03 07 00 07 01 07 FF` |

Details and the empty-closure result are on the [Data](Data.md) page.

## Non-finite floats

`.passThrough` writes IEEE bits, including NaN, `+Inf`, and `-Inf`. `.throw` fails instead of writing them. `.convertToString` writes the configured strings; `+inf` is `0D 04 2B 69 6E 66`. The decoder needs `.convertFromString` with the same spellings. See [Floating point](Floating-Point.md).
