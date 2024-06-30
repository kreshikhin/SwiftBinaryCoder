# Booleans

[Home](Home.md)

`Bool` is one tag and nothing else.

| Value | Bytes |
| --- | --- |
| `false` | `01` |
| `true` | `02` |

```swift
let data = try BinaryEncoder().encode(true)
// 02
```

```swift
let data = try BinaryEncoder().encode(false)
// 01
```

`BinaryDecoder` accepts only these two tags as `Bool`. A string, an integer, or null is a type mismatch. Null decoded as `Bool` is `valueNotFound`.

`Bool` properties of a struct are ordinary map values. On the [Decimal](Decimal.md) page, `isNegative: true` is the single byte `02` stored under that key.
