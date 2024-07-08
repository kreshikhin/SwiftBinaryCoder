# Arrays

[Home](Home.md)

An `Array`, and any type that uses an unkeyed container, is a count followed by that many values. Each element is a complete value with its own tag. There is no separator between elements.

| Count | Tag | Count field |
| --- | --- | --- |
| 0...255 | `13` | 1 byte |
| 256...65535 | `14` | 2 bytes |
| 65536...4294967295 | `15` | 4 bytes |

```swift
try BinaryEncoder().encode([Int]())
// 13 00

try BinaryEncoder().encode([1, 2])
// 13 02 03 01 03 02
```

`13 02` is an array of two values. `03 01` and `03 02` are the int8 values 1 and 2.

An optional element can be null without changing the count:

```swift
try BinaryEncoder().encode([1, nil, 2] as [Int?])
```

```text
13 03
   03 01    1
   00       nil
   03 02    2
```

Arrays nest. `[[1, 2], [3]]` is an array whose elements are arrays:

```text
13 02
   13 02
      03 01
      03 02
   13 01
      03 03
```

The count field grows the same way a string length does. An array of 256 zeros starts with array16 and a big-endian count, then an int8 zero for the first element:

```text
14 01 00
   03 00
   ...
```

Decoding reads exactly `count` values. A count that runs past the end of the document throws. Extra bytes after the finished array throw when that array is the root value, because a document is only one value.

A struct property that is an array is one value inside the parent map. The [nested value](Nested-Values.md) example stores `tags` that way.
