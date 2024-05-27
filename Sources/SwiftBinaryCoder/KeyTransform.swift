import Foundation

/// Camel-case and snake_case conversions compatible with `JSONEncoder` and
/// `JSONDecoder`.
enum KeyTransform {
    /// Converts `oneTwoThree` to `one_two_three` and `myURLProperty` to `my_url_property`.
    ///
    /// The rules match Foundation: words split on a lower-to-upper transition,
    /// a run of capitals is its own word, the result is lowercased, and leading
    /// or trailing underscores are preserved.
    static func camelToSnake(_ stringKey: String) -> String {
        guard !stringKey.isEmpty else { return stringKey }

        var words: [Range<String.Index>] = []
        // Swift names start with a lowercase letter. Searching from the second
        // character keeps a leading capital group attached to the first word
        // the same way JSONEncoder does (`URL` becomes `u_rl`).
        var wordStart = stringKey.startIndex
        var searchRange = stringKey.index(after: wordStart)..<stringKey.endIndex

        while let upperCaseRange = stringKey.rangeOfCharacter(
            from: .uppercaseLetters,
            options: [],
            range: searchRange
        ) {
            words.append(wordStart..<upperCaseRange.lowerBound)

            searchRange = upperCaseRange.lowerBound..<searchRange.upperBound
            guard let lowerCaseRange = stringKey.rangeOfCharacter(
                from: .lowercaseLetters,
                options: [],
                range: searchRange
            ) else {
                wordStart = searchRange.lowerBound
                break
            }

            let nextCharacterAfterCapital = stringKey.index(after: upperCaseRange.lowerBound)
            if lowerCaseRange.lowerBound == nextCharacterAfterCapital {
                // A single capital followed by a lower-case letter is not a boundary.
                wordStart = upperCaseRange.lowerBound
            } else {
                // A run of capitals. The capital immediately before the lower-case
                // letter starts the next word (`URLProperty` -> `url` + `property`).
                let beforeLowerIndex = stringKey.index(before: lowerCaseRange.lowerBound)
                words.append(upperCaseRange.lowerBound..<beforeLowerIndex)
                wordStart = beforeLowerIndex
            }
            searchRange = lowerCaseRange.upperBound..<searchRange.upperBound
        }

        words.append(wordStart..<searchRange.upperBound)
        return words.map { stringKey[$0].lowercased() }.joined(separator: "_")
    }

    /// Converts `one_two_three` to `oneTwoThree` and `_one_two_three_` to `_oneTwoThree_`.
    static func snakeToCamel(_ stringKey: String) -> String {
        guard !stringKey.isEmpty else { return stringKey }

        guard let firstNonUnderscore = stringKey.firstIndex(where: { $0 != "_" }) else {
            return stringKey
        }

        var lastNonUnderscore = stringKey.index(before: stringKey.endIndex)
        while lastNonUnderscore > firstNonUnderscore && stringKey[lastNonUnderscore] == "_" {
            stringKey.formIndex(before: &lastNonUnderscore)
        }

        let keyRange = firstNonUnderscore...lastNonUnderscore
        let leading = stringKey[stringKey.startIndex..<firstNonUnderscore]
        let trailing = stringKey[stringKey.index(after: lastNonUnderscore)..<stringKey.endIndex]
        let components = stringKey[keyRange].split(separator: "_")

        let joined: String
        if components.count <= 1 {
            joined = String(stringKey[keyRange])
        } else {
            let tail = components.dropFirst().map { word -> String in
                guard let first = word.first else { return "" }
                return String(first).uppercased() + word.dropFirst().lowercased()
            }
            joined = components[0].lowercased() + tail.joined()
        }

        return String(leading) + joined + String(trailing)
    }
}
