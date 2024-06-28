# Null

[Home](Home.md)

Null is a single byte, `00`. It has no payload.

`Optional.none` encodes as null when the optional itself is the value being encoded. `encodeNil()` on a single-value container does the same. Inside a keyed container, `encodeNil(forKey:)` stores a null under that key. `encodeIfPresent` does not: a `nil` argument leaves the key out of the map. See [Optionals](Optionals.md).

## `Optional<Int>.none`

```swift
let data = try BinaryEncoder().encode(Optional<Int>.none)
```

```text
00
```

Decoding that byte as `Optional<Int>` produces `nil`. Decoding it as `Int` throws `DecodingError.valueNotFound`, because a non-optional value cannot be null.

## A key stored as null

```swift
struct Row: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNil(forKey: .note)
        try container.encode(1, forKey: .required)
    }

    enum CodingKeys: String, CodingKey { case required, note }
}
```

```text
16 02
   0D 04 6E 6F 74 65             note
   00                            null
   0D 08 72 65 71 75 69 72 65 64 required
   03 01                         1
```

`decodeIfPresent` treats this null the same as a missing key and returns `nil`. `decodeNil(forKey:)` returns `true` only when the key is present and its value is `00`.

See also [Optionals](Optionals.md) and [Maps](Maps.md).
