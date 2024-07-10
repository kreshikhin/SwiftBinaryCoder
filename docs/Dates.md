# Dates

[Home](Home.md)

`Date` is a timestamp unless `dateEncodingStrategy` says otherwise. The default tag is `19`: one byte followed by a float64 count of seconds since 1970-01-01T00:00:00Z. The float64 uses the encoder's endianness. This is not tag `0C`. A plain `Double` and a timestamp can hold the same bits and still be different values.

The examples use `Date(timeIntervalSince1970: 1_700_000_000)`, which is 2023-11-14T22:13:20Z, and the half-second instant `1_700_000_000.5` where a strategy needs a fraction.

## Timestamp

```swift
let date = Date(timeIntervalSince1970: 1_700_000_000)
try BinaryEncoder().encode(date)
```

```text
19 41 D9 54 FC 40 00 00 00
```

The eight payload bytes are the IEEE 754 bits of `1700000000.0`. The half-second instant keeps the fraction in the low bits:

```swift
try BinaryEncoder().encode(Date(timeIntervalSince1970: 1_700_000_000.5))
// 19 41 D9 54 FC 40 20 00 00
```

Decode with `.timestamp`, which is the default. A float64 tag is not accepted as a timestamp.

## Seconds and milliseconds

`.secondsSince1970` writes a float64 instead of a timestamp. The bits match the timestamp payload, and the tag is `0C`:

```text
0C 41 D9 54 FC 40 00 00 00
```

`.millisecondsSince1970` writes a float64 of `timeIntervalSince1970 * 1000`. For `1_700_000_000.5` that number is `1700000000500`:

```text
0C 42 78 BC FE 56 9F 40 00
```

The decoder strategy has to be the same one. `.secondsSince1970` reads the float64 as seconds. `.millisecondsSince1970` divides it by 1000. Both accept a float32 or an integer as well, because they decode through the normal number rules.

## ISO 8601

`.iso8601` writes a string in internet date-time form, UTC, without a fractional second on encode:

```text
0D 14 32 30 32 33 2D 31 31 2D 31 34 54 32 32 3A 31 33 3A 32 30 5A
```

Those 20 bytes are `2023-11-14T22:13:20Z`. Decoding accepts that form and the same form with a fractional second.

## Deferred to `Date`

`.deferredToDate` calls `Date.encode(to:)`. Foundation writes `timeIntervalSinceReferenceDate` as a float64, so the instant is seconds since 2001-01-01T00:00:00Z. For `1_700_000_000` that is `721692800`:

```text
0C 41 C5 82 14 40 00 00 00
```

Decode with `.deferredToDate`.

## Custom

`.custom` is a closure. Whatever it writes becomes the date. Encoding the whole second as `Int64` produces an int32, because 1700000000 fits in 32 bits:

```swift
var encoder = BinaryEncoder()
encoder.dateEncodingStrategy = .custom { value, encoder in
    var container = encoder.singleValueContainer()
    try container.encode(Int64(value.timeIntervalSince1970))
}
try encoder.encode(date)
```

```text
05 65 53 F1 00
```

`65 53 F1 00` is 1700000000. The decoder closure has to read the same shape. A custom closure that writes nothing produces an empty map, `16 00`.
