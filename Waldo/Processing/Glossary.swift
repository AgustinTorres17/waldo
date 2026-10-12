import Foundation

/// Terms the model must never change: product names, team jargon, people's names.
/// Matched as whole words, ignoring case; the output uses the glossary's spelling.
enum Glossary {
    /// One term per line; blank lines and surrounding spaces are ignored.
    static func terms(from text: String) -> [String] {
        var seen = Set<String>()
        return text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// The glossary terms that appear in `text`.
    static func terms(in text: String, glossary: [String]) -> [String] {
        glossary.filter { pattern(for: $0)?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
    }

    /// Terms from `terms` that `output` no longer contains.
    static func missing(_ terms: [String], from output: String) -> [String] {
        terms.filter { pattern(for: $0)?.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)) == nil }
    }

    /// Writes every occurrence of each term with the glossary's spelling.
    static func applySpelling(_ terms: [String], to text: String) -> String {
        terms.reduce(text) { result, term in
            guard let regex = pattern(for: term) else { return result }
            return regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result),
                                                  withTemplate: NSRegularExpression.escapedTemplate(for: term))
        }
    }

    /// Whole words only: "Go" must not match "good".
    private static func pattern(for term: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}_])\(NSRegularExpression.escapedPattern(for: term))(?![\\p{L}\\p{N}_])",
                                 options: [.caseInsensitive])
    }
}
