# Optionals

[Home](Home.md)

An optional is not a wrapper tag. `nil` is [null](Null.md). A present optional is the encoding of the wrapped value, with no extra byte in front of it.

```swift
try BinaryEncoder().encode(Optional<Int>.none)
// 00

try BinaryEncoder().encode(Optional(1))
// 03 01
```

`03 01` is the same document as `Int(1)`. The decoder recovers `Optional(1)` because the value is not null, and it recovers `nil` from `00`.

## Properties

A synthesized `Codable` optional property uses `encodeIfPresent`. A `nil` property is left out of the map. It is not stored as `00`.

```swift
struct Note: Codable {
    var required: Int
    var note: String?
}

try BinaryEncoder().encode(Note(required: 1, note: nil))
```

```text
16 01
   0D 08 72 65 71 75 69 72 65 64    required
   03 01                            1
```

There is one pair. `note` is absent, and decoding the struct still produces `note: nil`.

A present string is a second pair:

```swift
try BinaryEncoder().encode(Note(required: 1, note: "x"))
```

```text
16 02
   0D 08 72 65 71 75 69 72 65 64    required
   03 01                            1
   0D 04 6E 6F 74 65                note
   0D 01 78                         "x"
```

## Null and a missing key

`encodeNil(forKey:)` writes a real null. `decodeIfPresent` returns `nil` for both a missing key and a null value. `decode` of a non-optional type throws `keyNotFound` when the key is missing and `valueNotFound` when the key is present and null.

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
   0D 04 6E 6F 74 65                note
   00                               null
   0D 08 72 65 71 75 69 72 65 64    required
   03 01                            1
```

An array element has no key to omit, so a `nil` element stays in the array as `00`. See [Arrays](Arrays.md).
