import Foundation

/// A single regular-expression match with its capture groups resolved to Swift strings.
struct PatternMatch {
    let range: Range<String.Index>
    let groups: [String?]

    /// Capture group `index` (1-based like NSRegularExpression), or nil when it did not participate.
    func group(_ index: Int) -> String? {
        guard index < groups.count else { return nil }
        return groups[index]
    }
}

enum Pattern {
    private static var cache: [String: NSRegularExpression] = [:]
    private static let lock = NSLock()

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[pattern] { return cached }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        cache[pattern] = regex
        return regex
    }

    static func first(_ pattern: String, in text: String) -> PatternMatch? {
        guard let regex = regex(pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let result = regex.firstMatch(in: text, options: [], range: nsRange),
              let range = Range(result.range, in: text) else { return nil }
        var groups: [String?] = [String(text[range])]
        for index in 1..<max(1, result.numberOfRanges) {
            let groupRange = result.range(at: index)
            if groupRange.location == NSNotFound {
                groups.append(nil)
            } else if let swiftRange = Range(groupRange, in: text) {
                groups.append(String(text[swiftRange]))
            } else {
                groups.append(nil)
            }
        }
        return PatternMatch(range: range, groups: groups)
    }

    static func matches(_ pattern: String, in text: String) -> Bool {
        first(pattern, in: text) != nil
    }

    /// Replaces every match of `pattern` with `replacement`.
    static func replacing(_ pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = regex(pattern) else { return text }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: nsRange, withTemplate: replacement)
    }
}

extension String {
    /// Removes `range` and tidies the whitespace left behind.
    func removing(_ range: Range<String.Index>) -> String {
        var copy = self
        copy.removeSubrange(range)
        return copy.collapsingWhitespace()
    }

    func collapsingWhitespace() -> String {
        Pattern.replacing("\\s+", in: self, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Trims whitespace and the punctuation that speech recognizers like to add.
    func trimmingEdgePunctuation() -> String {
        var set = CharacterSet.whitespacesAndNewlines
        set.formUnion(CharacterSet(charactersIn: ".,;:!?-–—\"'“”‘’"))
        return trimmingCharacters(in: set)
    }

    func capitalizingFirstLetter() -> String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }

    func hasWordPrefix(_ prefix: String) -> Bool {
        let lower = lowercased()
        let p = prefix.lowercased()
        if lower == p { return true }
        guard lower.hasPrefix(p) else { return false }
        let next = lower[lower.index(lower.startIndex, offsetBy: p.count)]
        return !(next.isLetter || next.isNumber)
    }

    func hasAnyWordPrefix(_ prefixes: [String]) -> Bool {
        prefixes.contains { hasWordPrefix($0) }
    }

    func containsAny(_ needles: [String]) -> Bool {
        let lower = lowercased()
        return needles.contains { lower.contains($0.lowercased()) }
    }
}
