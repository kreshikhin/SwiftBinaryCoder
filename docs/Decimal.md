# Decimal

[Home](Home.md)

`Decimal` is not a float and it does not have its own tag. `BinaryEncoder` calls Foundation's `encode(to:)`, which writes a map of five fields: `exponent`, `length`, `isNegative`, `isCompact`, and `mantissa`. The integer fields then go through the normal width rules, so a small limb is a uint8 rather than a wider integer.

`-12.50` is `-125` with an exponent of `-1`.

```swift
try BinaryEncoder().encode(Decimal(string: "-12.50")!)
```

```text
16 05
   0D 08 65 78 70 6F 6E 65 6E 74          exponent
   03 FF                                  -1
   0D 06 6C 65 6E 67 74 68                length
   07 01                                  1
   0D 0A 69 73 4E 65 67 61 74 69 76 65    isNegative
   02                                     true
   0D 09 69 73 43 6F 6D 70 61 63 74       isCompact
   02                                     true
   0D 08 6D 61 6E 74 69 73 73 61          mantissa
   13 08                                  8 limbs
      07 7D                               125
      07 00
      07 00
      07 00
      07 00
      07 00
      07 00
      07 00
```

`03 FF` is signed int8 for the exponent. `07 01` and `07 7D` are unsigned, because Foundation writes those fields as unsigned integers. `02` is `true`. The mantissa array always has eight limbs in this encoding; unused limbs are zero.

Decoding reads that map back with `Decimal.init(from:)`. The field names are Foundation's names, so a key strategy that renames keys will not round-trip a `Decimal` unless the decoder uses the matching reverse strategy.
