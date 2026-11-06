import Foundation

/// Spans that must survive byte-for-byte (RESEARCH §7.2.1): code blocks, inline
/// code, Slack tokens, URLs, emails, @mentions, #channels and :emoji:.
///
/// They are sent to the model as-is, not masked: with Apple's model, `⟦n⟧`-style
/// placeholders were dropped in 4 of 8 test messages, while verbatim spans plus
/// an explicit "keep exactly" rule survived in 7 of 8. The validator then checks
/// that every span is still present.
enum ProtectedSpans {
    // One alternation, matched left to right; earlier alternatives win at the same position.
    private static let regex = try! NSRegularExpression(pattern: [
        "```[\\s\\S]*?```",                                    // fenced code block
        "`[^`\\n]+`",                                          // inline code
        "<(?:[@#!]|https?://)[^>\\s]+(?:\\|[^>]*)?>",          // raw Slack tokens and links
        "(?:https?://|www\\.)[^\\s<>]*[^\\s<>.,;:!?)\\]}'\"]", // URLs
        "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}",     // emails
        "(?<![\\w@])@[\\w.\\-]*\\w",                           // @mentions
        "(?<![\\w#&])#[\\w\\-]*\\w",                           // #channels
        ":(?=[a-z0-9_+\\-]*[a-z])[a-z0-9_+\\-]+:",             // :emoji: (needs a letter, so 10:30:45 is safe)
    ].joined(separator: "|"))

    static func find(in text: String) -> [String] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    /// The text with protected spans blanked out, used for language detection.
    static func stripped(_ text: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
    }

    /// False when only protected spans, spaces and symbols remain.
    static func hasTranslatableContent(_ text: String) -> Bool {
        stripped(text).unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    /// Spans from `input` that `output` no longer contains (respecting repeats).
    static func missing(from output: String, input: String) -> [String] {
        var remaining = output
        var missing: [String] = []
        for span in find(in: input) {
            if let range = remaining.range(of: span) {
                remaining.replaceSubrange(range, with: "\u{0}")
            } else {
                missing.append(span)
            }
        }
        return missing
    }

    /// Puts back the @mentions and #channels a model changed, since they have to
    /// reach the app as they were written:
    /// - "@maria" turned into "Maria": a bare word that appears exactly once.
    /// - "@aquí" translated to "@here": as many new mentions as lost ones.
    /// - A mention opening the text dropped altogether.
    static func restoringSigils(in output: String, input: String) -> String {
        let bareWordsRestored = restoringBareWords(in: output, input: input)
        let replaced = ["@", "#"].reduce(bareWordsRestored) { undoingReplacements(in: $0, input: input, sigil: $1) }
        return restoringOpeningSpan(in: replaced, input: input)
    }

    private static func undoingReplacements(in output: String, input: String, sigil: String) -> String {
        let lost = missing(from: output, input: input).filter { $0.hasPrefix(sigil) }
        let inputSpans = Set(find(in: input))
        let added = find(in: output).filter { $0.hasPrefix(sigil) && !inputSpans.contains($0) }
        guard !lost.isEmpty, lost.count == added.count else { return output }
        var result = output
        for (original, changed) in zip(lost, added) {
            if let range = result.range(of: changed) { result.replaceSubrange(range, with: original) }
        }
        return result
    }

    private static func restoringOpeningSpan(in output: String, input: String) -> String {
        guard !output.isEmpty else { return output }
        let opening = missing(from: output, input: input).first { span in
            (span.hasPrefix("@") || span.hasPrefix("#"))
                && input.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(span)
        }
        return opening.map { "\($0) \(output)" } ?? output
    }

    private static func restoringBareWords(in output: String, input: String) -> String {
        var result = output
        for span in missing(from: output, input: input) where span.count > 1 && (span.hasPrefix("@") || span.hasPrefix("#")) {
            let bare = NSRegularExpression.escapedPattern(for: String(span.dropFirst()))
            guard let regex = try? NSRegularExpression(pattern: "(?<![\\w@#])\(bare)(?!\\w)", options: [.caseInsensitive]) else { continue }
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            if matches.count == 1, let range = Range(matches[0].range, in: result) {
                result.replaceSubrange(range, with: span)
            }
        }
        return result
    }

    private static let fencedCode = try! NSRegularExpression(pattern: "```[\\s\\S]*?```")

    /// Splits text into prose and fenced code blocks, in order. Code blocks are
    /// never sent to a model: Apple's model rearranged their lines in testing.
    static func segments(_ text: String) -> [(text: String, isCode: Bool)] {
        var result: [(String, Bool)] = []
        var cursor = text.startIndex
        for match in fencedCode.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            if cursor < range.lowerBound { result.append((String(text[cursor..<range.lowerBound]), false)) }
            result.append((String(text[range]), true))
            cursor = range.upperBound
        }
        if cursor < text.endIndex { result.append((String(text[cursor...]), false)) }
        return result
    }
}
