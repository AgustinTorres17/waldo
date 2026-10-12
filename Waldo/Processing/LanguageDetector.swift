import Foundation
import NaturalLanguage

/// What the model should do with the text.
enum ProcessingTask: Sendable, Equatable {
    case translate(sourceName: String?)
    case correct
    /// Detection was not confident (short or mixed text): the model decides.
    case translateOrCorrect
    /// Asked for explicitly: rewrite into natural, clear text in the target language.
    case rephrase
}

/// What the user asked for: the automatic translate/correct, or a rephrase.
enum ProcessingMode: Sendable, Equatable {
    case automatic
    case rephrase
}

/// Decides translate vs. correct in code, not in the model (RESEARCH §7.2.2).
enum LanguageDetector {
    /// Minimum probability to trust the top hypothesis (RESEARCH §7.2.2; tune on data).
    static let confidenceThreshold = 0.80

    static func task(for text: String, target: TargetLanguage) -> ProcessingTask {
        let hypotheses = hypotheses(for: text, target: target)
        guard let (language, probability) = hypotheses.max(by: { $0.value < $1.value }),
              probability >= confidenceThreshold else {
            return .translateOrCorrect
        }
        if language == target.nlLanguage {
            return .correct
        }
        let name = Locale(identifier: "en").localizedString(forLanguageCode: language.rawValue)
        return .translate(sourceName: name)
    }

    static func hypotheses(for text: String, target: TargetLanguage) -> [NLLanguage: Double] {
        let recognizer = NLLanguageRecognizer()
        var hints = Dictionary(uniqueKeysWithValues: TargetLanguage.allCases.map { ($0.nlLanguage, 0.1) })
        hints[target.nlLanguage] = 0.3
        recognizer.languageHints = hints
        recognizer.processString(text)
        return recognizer.languageHypotheses(withMaximum: 3)
    }
}
