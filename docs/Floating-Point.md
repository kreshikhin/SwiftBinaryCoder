# Floating point

[Home](Home.md)

`Float` is tag `0B` plus 4 IEEE 754 bytes. `Double` is tag `0C` plus 8 IEEE 754 bytes. The bytes use the encoder's endianness. The default keeps the sign bit, so `-0.0` stays distinct from `0.0`, and the default also keeps NaN and the infinities.

```swift
try BinaryEncoder().encode(Float(1))
// 0B 3F 80 00 00

try BinaryEncoder().encode(Float(-2.5))
// 0B C0 20 00 00

try BinaryEncoder().encode(Double(1.25))
// 0C 3F F4 00 00 00 00 00 00

try BinaryEncoder().encode(-0.0)
// 0C 80 00 00 00 00 00 00 00

try BinaryEncoder().encode(Double.infinity)
// 0C 7F F0 00 00 00 00 00 00

try BinaryEncoder().encode(-Double.infinity)
// 0C FF F0 00 00 00 00 00 00

try BinaryEncoder().encode(Double.nan)
// 0C 7F F8 00 00 00 00 00 00
```

Little-endian moves the payload and leaves the tag:

```swift
var encoder = BinaryEncoder()
encoder.endianness = .little
try encoder.encode(Float(1))
// 0B 00 00 80 3F
```

## Reading a different width

A float32 decodes as `Double`. A float64 decodes as `Float` when the value still fits; a finite number that overflows `Float` throws. Signed and unsigned integers also decode as floats. A float does not decode as an integer.

## Values that are not finite

`nonConformingFloatEncodingStrategy` changes NaN and the infinities. Finite numbers stay float32 or float64.

`.passThrough` is the default and writes the IEEE bits shown above.

`.throw` fails with `EncodingError.invalidValue` before any bytes are produced. The coding path points at the property. For a value nested as `inner.value`, that path is `["inner", "value"]`.

`.convertToString` writes one of three strings instead of a float:

```swift
var encoder = BinaryEncoder()
encoder.nonConformingFloatEncodingStrategy = .convertToString(
    positiveInfinity: "+inf",
    negativeInfinity: "-inf",
    nan: "nan"
)
try encoder.encode(Double.infinity)
```

```text
0D 04 2B 69 6E 66
```

That is the string `+inf`. The decoder needs `.convertFromString` with the same three strings. With any other float strategy, a string is not a float.

On decode, `.throw` rejects a non-finite float32 or float64. `.passThrough` returns it, including the NaN payload.
