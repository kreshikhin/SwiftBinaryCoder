# UUID

[Home](Home.md)

`UUID` is not a separate wire type and it is not a 16-byte blob. `BinaryEncoder` does not special-case it, so Foundation's `Codable` implementation runs. That implementation writes the canonical 36-character string: 8-4-4-4-12 hexadecimal digits with hyphens.

```swift
let id = UUID(uuidString: "123E4567-E89B-12D3-A456-426614174000")!
try BinaryEncoder().encode(id)
```

```text
0D 24
   31 32 33 45 34 35 36 37 2D     123E4567-
   45 38 39 42 2D                 E89B-
   31 32 44 33 2D                 12D3-
   41 34 35 36 2D                 A456-
   34 32 36 36 31 34 31 37 34 30 30 30
                                  426614174000
```

`24` is the length 36. The letters are the uppercase characters Foundation uses in `uuidString`. Decoding reads a string and asks `UUID` to decode it. A 16-byte binary value is not a UUID in this format.
