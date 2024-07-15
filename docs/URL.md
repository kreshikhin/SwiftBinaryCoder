# URL

[Home](Home.md)

`URL` is a string. `BinaryEncoder` writes `absoluteString` and does not give URLs a tag of their own. `BinaryDecoder` reads a string and builds a `URL` from it. A string that `URL(string:)` rejects throws `DecodingError.dataCorrupted`.

```swift
let link = URL(string: "https://example.com/a b")!
try BinaryEncoder().encode(link)
```

`absoluteString` percent-encodes the space, so the stored text is `https://example.com/a%20b`, 25 bytes:

```text
0D 19
   68 74 74 70 73 3A 2F 2F     https://
   65 78 61 6D 70 6C 65 2E     example.
   63 6F 6D 2F                 com/
   61 25 32 30 62              a%20b
```

Decoding that string returns a `URL` whose `absoluteString` is the same text. A binary blob, an integer, or null is not a URL.
