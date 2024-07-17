# Nested values

[Home](Home.md)

A property that is itself `Codable` is one value under that property's key. A nested struct is a nested map. A nested array is a nested array. Nothing flattens the tree.

```swift
struct Address: Codable {
    var city: String
    var zip: Int
}

struct User: Codable {
    var name: String
    var address: Address
    var tags: [String]
    var subtitle: String?
}

let user = User(
    name: "Ada",
    address: Address(city: "London", zip: 1),
    tags: ["a"],
    subtitle: nil
)
try BinaryEncoder().encode(user)
```

`subtitle` is omitted because it is `nil`. The map has three pairs:

```text
16 03
   0D 04 6E 61 6D 65                         name
   0D 03 41 64 61                            "Ada"
   0D 07 61 64 64 72 65 73 73                address
   16 02
      0D 04 63 69 74 79                      city
      0D 06 4C 6F 6E 64 6F 6E                "London"
      0D 03 7A 69 70                         zip
      03 01                                  1
   0D 04 74 61 67 73                         tags
   13 01
      0D 01 61                               "a"
```

The same user with `subtitle: "x"` and an empty `tags` array has four pairs. The address map is unchanged. The tags array is empty, and the subtitle string is present:

```text
16 04
   0D 04 6E 61 6D 65                         name
   0D 03 41 64 61                            "Ada"
   0D 07 61 64 64 72 65 73 73                address
   16 02
      0D 04 63 69 74 79                      city
      0D 06 4C 6F 6E 64 6F 6E                "London"
      0D 03 7A 69 70                         zip
      03 01                                  1
   0D 04 74 61 67 73                         tags
   13 00
   0D 08 73 75 62 74 69 74 6C 65             subtitle
   0D 01 78                                  "x"
```

`13 00` is an empty array. Decoding either document rebuilds the struct, including `subtitle: nil` for the first one.

See [Maps](Maps.md), [Arrays](Arrays.md), and [Optionals](Optionals.md).
