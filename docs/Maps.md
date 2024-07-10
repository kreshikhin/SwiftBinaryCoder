# Maps

[Home](Home.md)

A keyed container is a map: a count, then that many pairs. Each pair is a key value followed by a value. Keys are not a separate string table. A struct field is usually a string, and an integer coding key can be an integer.

| Pair count | Tag | Count field |
| --- | --- | --- |
| 0...255 | `16` | 1 byte |
| 256...65535 | `17` | 2 bytes |
| 65536...4294967295 | `18` | 4 bytes |

Pairs are written in the order the encoder inserts them. A synthesized struct writes stored properties from top to bottom. A `Dictionary` writes keys in its iteration order, which is not a stable document order, so the examples below use structs or an explicit `encode(to:)`.

An empty struct and an empty `[String: Int]` are the same bytes:

```swift
struct Empty: Codable {}

try BinaryEncoder().encode(Empty())
// 16 00

try BinaryEncoder().encode([String: Int]())
// 16 00
```

## A struct

```swift
struct Pair: Codable {
    var x: Int8
    var name: String
}

try BinaryEncoder().encode(Pair(x: 7, name: "ab"))
```

```text
16 02
   0D 01 78                "x"
   03 07                   7
   0D 04 6E 61 6D 65       "name"
   0D 02 61 62             "ab"
```

Decoding looks up fields by key, not by position. The same two pairs in the opposite order still decode as `Pair(x: 7, name: "ab")`:

```text
16 02
   0D 04 6E 61 6D 65  0D 02 61 62
   0D 01 78           03 07
```

A missing key throws `DecodingError.keyNotFound` when the property is non-optional. The [Player](Home.md) example is the same shape with three fields: `name`, `score`, and `avatar`.

## Integer keys

With `.useDefaultKeys`, a coding key is written as an integer when it has an `intValue` and its `stringValue` is the decimal spelling of that integer. `Dictionary<Int, String>` uses keys of that form. This encoder writes them in a fixed order:

```swift
struct IntKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(intValue: Int) {
        self.intValue = intValue
        self.stringValue = String(intValue)
    }
    init?(stringValue: String) { nil }
}

struct IntMap: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: IntKey.self)
        try container.encode("zero", forKey: IntKey(intValue: 0))
        try container.encode("neg", forKey: IntKey(intValue: -4))
        try container.encode("wide", forKey: IntKey(intValue: 300))
    }
}
```

```text
16 03
   03 00                   key 0
   0D 04 7A 65 72 6F       "zero"
   03 FC                   key -4
   0D 03 6E 65 67          "neg"
   04 01 2C                key 300
   0D 04 77 69 64 65       "wide"
```

The key `0` is int8. The key `-4` is int8 `FC`. The key `300` does not fit in int8, so it is int16 `01 2C`. A string key `"0"` is not the same entry as the integer key `0`.

`.convertToSnakeCase` and `.custom` always write string keys, so those strategies turn an integer key into its decimal text. See [Strategies](Strategies.md).

## Two properties

```swift
struct Snake: Codable {
    var userName: String
    var myURLProperty: Int
}

var encoder = BinaryEncoder()
encoder.keyEncodingStrategy = .convertToSnakeCase
try encoder.encode(Snake(userName: "Ada", myURLProperty: 2))
```

```text
16 02
   0D 09 75 73 65 72 5F 6E 61 6D 65                   "user_name"
   0D 03 41 64 61                                     "Ada"
   0D 0F 6D 79 5F 75 72 6C 5F 70 72 6F 70 65 72 74 79 "my_url_property"
   03 02                                              2
```

The conversion matches `JSONEncoder`: `userName` becomes `user_name`, and `myURLProperty` becomes `my_url_property`. Decode with `.convertFromSnakeCase`. Acronyms follow the JSONEncoder rule, so `my_url_property` comes back as `myUrlProperty` and does not round-trip into a property named `myURLProperty`. `userName` does round-trip.
