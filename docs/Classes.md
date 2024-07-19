# Classes

[Home](Home.md)

A class is a map, like a struct. Inheritance uses `superEncoder()` and `superDecoder()`. The subclass writes its own keys, then asks for a nested encoder under the string `"super"`. That string is used even when the subclass's `CodingKey` enum has no `super` case. With `.convertToSnakeCase` the key is still `super`. A custom key strategy receives the coding path and can rename it.

`superEncoder()` inserts an empty map immediately. The superclass encoder fills that same map, so the parent document already contains the superclass fields when `encode(to:)` returns. If the superclass writes nothing, the stored value stays `16 00`.

```swift
class Base: Codable {
    var a: Int

    init(a: Int) { self.a = a }

    enum CodingKeys: String, CodingKey { case a }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        a = try container.decode(Int.self, forKey: .a)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(a, forKey: .a)
    }
}

final class Child: Base {
    var b: String

    init(a: Int, b: String) {
        self.b = b
        super.init(a: a)
    }

    enum ChildKeys: String, CodingKey { case b }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ChildKeys.self)
        b = try container.decode(String.self, forKey: .b)
        try super.init(from: container.superDecoder())
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ChildKeys.self)
        try container.encode(b, forKey: .b)
        try super.encode(to: container.superEncoder())
    }
}

try BinaryEncoder().encode(Child(a: 4, b: "dog"))
```

```text
16 02
   0D 01 62                "b"
   0D 03 64 6F 67          "dog"
   0D 05 73 75 70 65 72    "super"
   16 01
      0D 01 61             "a"
      03 04                4
```

`superDecoder()` looks up the key `"super"` after the decoder's key strategy has been applied. The superclass then decodes `a` from that nested map.
