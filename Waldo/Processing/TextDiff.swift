import Foundation

/// Word-level diff between the user's text and the result, to show what changed.
enum TextDiff {
    struct Segment: Equatable, Sendable {
        enum Kind: Equatable, Sendable { case same, removed, inserted }
        let kind: Kind
        let text: String
    }

    /// Below this share of the result's words kept from the input, a diff is
    /// mostly noise (a translation or a full rewrite), so none is shown.
    static let minimumKeptShare = 0.4

    /// Segments that rebuild `old` (same + removed) and `new` (same + inserted),
    /// or nil when the texts are too different for a diff to help.
    static func segments(from old: String, to new: String) -> [Segment]? {
        let a = tokens(old), b = tokens(new)
        let difference = b.difference(from: a)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        let words = b.indices.filter { isWord(b[$0]) }
        guard !words.isEmpty else { return nil }
        let kept = words.filter { !inserted.contains($0) }.count
        guard Double(kept) / Double(words.count) >= minimumKeptShare else { return nil }

        var raw: [Segment] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, removed.contains(i) {
                raw.append(Segment(kind: .removed, text: a[i])); i += 1
            } else if j < b.count, inserted.contains(j) {
                raw.append(Segment(kind: .inserted, text: b[j])); j += 1
            } else {
                raw.append(Segment(kind: .same, text: b[j])); i += 1; j += 1
            }
        }
        return grouped(wholeWords(raw))
    }

    /// A kept token glued to a change ("I" before an inserted "'m") becomes part of
    /// it, so changes never start or end in the middle of a word.
    private static func wholeWords(_ segments: [Segment]) -> [Segment] {
        var raw = segments
        var changed = true
        while changed {
            changed = false
            var result: [Segment] = []
            for (index, segment) in raw.enumerated() {
                if segment.kind == .same, !isSpace(segment.text), isGlued(raw, at: index) {
                    result.append(Segment(kind: .removed, text: segment.text))
                    result.append(Segment(kind: .inserted, text: segment.text))
                    changed = true
                } else {
                    result.append(segment)
                }
            }
            raw = result
        }
        return raw
    }

    /// Whether the kept token at `index` continues a changed word in either text:
    /// "I" + "'m" does, "up" + ":" doesn't.
    private static func isGlued(_ raw: [Segment], at index: Int) -> Bool {
        for kind in [Segment.Kind.removed, .inserted] {
            let other: Segment.Kind = kind == .removed ? .inserted : .removed
            if let next = raw[(index + 1)...].first(where: { $0.kind != other }),
               next.kind == kind, next.text.first.map(isWordCharacter) == true { return true }
            if let previous = raw[..<index].last(where: { $0.kind != other }),
               previous.kind == kind, previous.text.last.map(isWordCharacter) == true { return true }
        }
        return false
    }

    /// Merges each run of changes into one removal followed by one insertion. A lone
    /// space between two changes joins the run, so "write you" → "'m writing to you"
    /// reads as one replacement rather than word by word. Line breaks never join:
    /// they would show twice.
    private static func grouped(_ raw: [Segment]) -> [Segment] {
        var result: [Segment] = []
        var removed = "", inserted = ""
        func flush() {
            if !removed.isEmpty { result.append(Segment(kind: .removed, text: removed)) }
            if !inserted.isEmpty { result.append(Segment(kind: .inserted, text: inserted)) }
            removed = ""; inserted = ""
        }
        for (index, segment) in raw.enumerated() {
            switch segment.kind {
            case .removed: removed += segment.text
            case .inserted: inserted += segment.text
            case .same:
                let inRun = !(removed.isEmpty && inserted.isEmpty)
                let nextChanges = index + 1 < raw.count && raw[index + 1].kind != .same
                if inRun, nextChanges, !segment.text.contains(where: \.isNewline), isSpace(segment.text) {
                    removed += segment.text
                    inserted += segment.text
                } else {
                    flush()
                    if let last = result.last, last.kind == .same {
                        result[result.count - 1] = Segment(kind: .same, text: last.text + segment.text)
                    } else {
                        result.append(segment)
                    }
                }
            }
        }
        flush()
        return result
    }

    private static let tokenPattern = try! NSRegularExpression(pattern: "[\\p{L}\\p{N}_]+|\\s+|[^\\p{L}\\p{N}_\\s]")

    /// Words, runs of whitespace, and single punctuation marks.
    static func tokens(_ text: String) -> [String] {
        tokenPattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    private static func isWord(_ token: String) -> Bool {
        token.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "'" || character == "’"
    }

    private static func isSpace(_ token: String) -> Bool {
        token.allSatisfy(\.isWhitespace)
    }
}
