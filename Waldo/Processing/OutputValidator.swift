import Foundation
import NaturalLanguage

/// Cleans model output and rejects anything that may not be the user's text
/// (RESEARCH §7.2.1 plus checks added after testing against injected inputs).
enum OutputValidator {
    enum Outcome: Equatable {
        case valid(String)
        case invalid(String)
    }

    /// `allowsRewording`: a custom mode may reword the text freely (more formal, no profanity),
    /// so removed swear words and a low word overlap are fine.
    /// `requiredTerms`: glossary terms from the input that the output must keep.
    static func validate(_ raw: String, input: String, task: ProcessingTask, target: TargetLanguage,
                         allowsRewording: Bool = false, requiredTerms: [String] = []) -> Outcome {
        let output = ProtectedSpans.restoringSigils(in: clean(raw, input: input), input: input)

        if output.isEmpty {
            return .invalid("The model returned an empty result.")
        }
        if output.hasPrefix("<think>") {
            return .invalid("The model returned reasoning instead of text.")
        }
        if !ProtectedSpans.missing(from: output, input: input).isEmpty {
            return .invalid("The result lost or changed mentions, links, emoji or code.")
        }
        if !Glossary.missing(requiredTerms, from: output).isEmpty {
            return .invalid("The result changed a glossary term.")
        }
        if output.count > 3 * input.count + 40 {
            return .invalid("The result is much longer than the original text.")
        }
        if lineCount(output) != lineCount(input) {
            return .invalid("The result changed the line breaks.")
        }
        if looksLikeRefusal(output, input: input) {
            return .invalid("The model declined to process this text.")
        }
        if !allowsRewording, keepsInputWords(task, input: input, target: target), !censoredWords(output, input: input).isEmpty {
            return .invalid("The result removed words you wrote.")
        }
        if looksLikeAnswer(output, input: input, task: allowsRewording ? .rephrase : task) {
            return .invalid("The model replied to the text instead of processing it.")
        }
        if isInWrongLanguage(output, target: target) {
            return .invalid("The result isn't in \(target.displayName).")
        }
        return .valid(output)
    }

    // MARK: Cleaning

    private static let thinkBlock = try! NSRegularExpression(pattern: "<think>[\\s\\S]*?</think>")
    /// Only a whole first line ending in a colon: "Here's the link: https://…" is content.
    private static let preamble = try! NSRegularExpression(
        pattern: "^(here(’|')?s|here is|sure|certainly|corrected( text)?|translation|translated text)\\b[^\\n]*:[ \\t]*\\n\\s*",
        options: [.caseInsensitive])
    private static let quotePairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("'", "'"), ("«", "»")]

    static func clean(_ raw: String, input: String) -> String {
        var text = thinkBlock.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("<text>") { text.removeFirst("<text>".count) }
        if text.hasSuffix("</text>") { text.removeLast("</text>".count) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if !matches(preamble, input) {
            text = preamble.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }

        for (open, close) in quotePairs where text.count >= 2
            && text.first == open && text.last == close
            && !(input.first == open && input.last == close) {
            text = String(text.dropFirst().dropLast())
            break
        }

        return PromptBuilder.unescape(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Refusals

    /// Phrases a model uses to decline, not ones that appear in normal messages
    /// ("I can't make it" is a valid translation; "I can't help with" is not).
    private static let refusalPhrases = [
        "i'm sorry, but", "i am sorry, but", "i can't help with", "i cannot help with", "i can't assist",
        "i cannot assist", "i'm unable to help", "i am unable to help", "i'm unable to assist", "i can't comply",
        "i cannot comply", "i can't fulfill", "i cannot fulfill", "i can't provide", "i cannot provide",
        "i'm not able to help", "as an ai", "as a language model",
        "lo siento, pero", "no puedo ayudar", "no puedo cumplir", "como modelo de lenguaje", "como ia",
        "desculpe, mas", "não posso ajudar", "je suis désolé, mais", "je ne peux pas aider",
        "es tut mir leid, aber", "ich kann dabei nicht helfen", "mi dispiace, ma", "non posso aiutare",
    ]

    /// A refusal phrase the input didn't contain, either at the start of the
    /// output or in an output much shorter than the input.
    static func looksLikeRefusal(_ output: String, input: String) -> Bool {
        let out = normalized(output)
        let original = normalized(input)
        for phrase in refusalPhrases where out.contains(phrase) && !original.contains(phrase) {
            let startsWithIt = out.prefix(40).contains(phrase)
            let muchShorter = output.count < input.count / 2
            if startsWithIt || muchShorter { return true }
        }
        return false
    }

    // MARK: Censorship

    /// Apple's model tends to delete swear words even with permissive guardrails.
    private static let swearWords: Set<String> = [
        "fuck", "fucking", "fucked", "fucker", "motherfucker", "shit", "shitty", "bullshit", "damn", "crap",
        "ass", "asshole", "bitch", "bastard", "dick", "piss", "pissed", "wtf",
        "mierda", "puta", "puto", "carajo", "coño", "joder", "boludo", "pelotudo", "pendejo", "cabrón", "verga",
    ]

    /// A rephrase of text already in the target language must keep its swear words too.
    private static func keepsInputWords(_ task: ProcessingTask, input: String, target: TargetLanguage) -> Bool {
        switch task {
        case .correct: true
        case .rephrase: LanguageDetector.task(for: ProtectedSpans.stripped(input), target: target) == .correct
        default: false
        }
    }

    /// Swear words in a same-language correction that the output no longer contains.
    static func censoredWords(_ output: String, input: String) -> [String] {
        let kept = normalized(output)
        return Set(normalized(input).components(separatedBy: CharacterSet.letters.inverted))
            .filter { swearWords.contains($0) && !kept.contains($0) }
            .sorted()
    }

    // MARK: Answers instead of edits

    /// Minimum share of the input's words a correction must keep.
    static let minimumCorrectionOverlap = 0.4

    /// Catches outputs that answer or obey the text: a question that lost its
    /// question mark, or a "correction" that shares few words with the input.
    static func looksLikeAnswer(_ output: String, input: String, task: ProcessingTask) -> Bool {
        let questionMarks = CharacterSet(charactersIn: "?¿？")
        let inputAsks = input.unicodeScalars.contains { questionMarks.contains($0) }
        let outputAsks = output.unicodeScalars.contains { questionMarks.contains($0) }
        if inputAsks && !outputAsks { return true }

        guard task == .correct else { return false }
        let inputWords = words(in: input)
        guard inputWords.count >= 3 else { return false }
        let outputWords = words(in: output)
        let kept = inputWords.filter { outputWords.contains($0) }.count
        return Double(kept) / Double(inputWords.count) < minimumCorrectionOverlap
    }

    private static func words(in text: String) -> Set<String> {
        Set(normalized(ProtectedSpans.stripped(text))
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count > 1 })
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "’", with: "'")
    }

    private static func lineCount(_ text: String) -> Int {
        text.components(separatedBy: "\n").count
    }

    // MARK: Language

    /// Below this many letters, language identification is unreliable (RESEARCH §7.2.2).
    static let minimumLettersForLanguageCheck = 20

    static func isInWrongLanguage(_ output: String, target: TargetLanguage) -> Bool {
        let text = ProtectedSpans.stripped(output)
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letters >= minimumLettersForLanguageCheck else { return false }

        let hypotheses = LanguageDetector.hypotheses(for: text, target: target)
        guard let (top, probability) = hypotheses.max(by: { $0.value < $1.value }) else { return false }
        let targetProbability = hypotheses[target.nlLanguage] ?? 0
        return top != target.nlLanguage && probability >= 0.6 && targetProbability < 0.2
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
