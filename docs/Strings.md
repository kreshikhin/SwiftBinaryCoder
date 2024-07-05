# Strings

[Home](Home.md)

A `String` is UTF-8 plus a length. It is not a [binary blob](Data.md): the tags are `0D`, `0E`, and `0F`. The length counts bytes, not `Character`s. A string that does not fit in `UInt32` bytes cannot be encoded.

| Byte length | Tag | Length field |
| --- | --- | --- |
| 0...255 | `0D` | 1 byte |
| 256...65535 | `0E` | 2 bytes |
| 65536...4294967295 | `0F` | 4 bytes |

The length uses the encoder's endianness. The UTF-8 bytes are copied in order.

```swift
try BinaryEncoder().encode("")
// 0D 00

try BinaryEncoder().encode("A")
// 0D 01 41

try BinaryEncoder().encode("Ada")
// 0D 03 41 64 61

try BinaryEncoder().encode("hi")
// 0D 02 68 69
```

`привет` is six characters and 12 UTF-8 bytes:

```swift
try BinaryEncoder().encode("привет")
```

```text
0D 0C
   D0 BF          п
   D1 80          р
   D0 B8          и
   D0 B2          в
   D0 B5          е
   D1 82          т
```

A 256-byte string no longer fits in str8. The header is str16 and a big-endian length of 256, then the bytes:

```text
0E 01 00
   78 78 78 ...    256 bytes of "x"
```

The same string written little-endian keeps the tag and swaps the length:

```text
0E 00 01
   78 78 78 ...
```

Decoding checks that the length is still inside the document and that the bytes are valid UTF-8. `0D 01 FF` throws `DecodingError.dataCorrupted`. A binary value, an integer, or null does not decode as `String`.

`URL` and `UUID` are also strings on the wire. Their pages show the exact bytes: [URL](URL.md), [UUID](UUID.md).
