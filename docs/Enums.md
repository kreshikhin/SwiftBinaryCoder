# Enums

[Home](Home.md)

An enum uses the `Codable` implementation Swift synthesizes, and that implementation is written with ordinary maps, strings, and integers. There is no extra enum tag.

## A case with no associated value

The case name is a map key. The associated payload is an empty map.

```swift
enum Event: Codable {
    case started
    case message(String)
    case moved(x: Int, y: Int)
}

try BinaryEncoder().encode(Event.started)
```

```text
16 01
   0D 07 73 74 61 72 74 65 64    "started"
   16 00                         empty map
```

## One unlabeled associated value

The payload is a map with the key `_0`.

```swift
try BinaryEncoder().encode(Event.message("hi"))
```

```text
16 01
   0D 07 6D 65 73 73 61 67 65    "message"
   16 01
      0D 02 5F 30                "_0"
      0D 02 68 69                "hi"
```

## Labeled associated values

The labels become the keys of the inner map, in source order.

```swift
try BinaryEncoder().encode(Event.moved(x: 3, y: -1))
```

```text
16 01
   0D 05 6D 6F 76 65 64    "moved"
   16 02
      0D 01 78             "x"
      03 03                3
      0D 01 79             "y"
      03 FF                -1
```

`-1` fits in int8, so the byte is `FF`.

## Raw values

A `String` raw value is that string and nothing else. An `Int` raw value is that integer, compacted to the smallest signed width.

```swift
enum Color: String, Codable {
    case red
    case blue
}

enum Code: Int, Codable {
    case a = 3
    case b = 9
}

try BinaryEncoder().encode(Color.blue)
// 0D 04 62 6C 75 65

try BinaryEncoder().encode(Code.b)
// 03 09
```

`62 6C 75 65` is `blue`. `03 09` is the signed int8 value 9, which is the raw value, not the case name.

Key strategies apply to the synthesized keys (`started`, `_0`, `x`, `y`) the same way they apply to struct properties. A raw-value enum has no keys.
