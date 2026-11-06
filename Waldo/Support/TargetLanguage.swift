import Foundation
import NaturalLanguage

/// Languages the user can pick as the output language.
/// Limited to languages that Apple's on-device model and Qwen3.5 both handle.
enum TargetLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case english = "en-US"
    case spanish = "es"
    case portuguese = "pt-BR"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case japanese = "ja"
    case korean = "ko"
    case chineseSimplified = "zh-Hans"

    var id: String { rawValue }

    /// Name shown in the UI and used in llama.cpp prompts.
    var displayName: String {
        switch self {
        case .english: "English"
        case .spanish: "Spanish"
        case .portuguese: "Portuguese"
        case .french: "French"
        case .german: "German"
        case .italian: "Italian"
        case .japanese: "Japanese"
        case .korean: "Korean"
        case .chineseSimplified: "Simplified Chinese"
        }
    }

    /// Regional name used in "You MUST respond in …" instructions.
    var instructionName: String {
        switch self {
        case .english: "U.S. English"
        case .portuguese: "Brazilian Portuguese"
        default: displayName
        }
    }

    var nlLanguage: NLLanguage {
        switch self {
        case .english: .english
        case .spanish: .spanish
        case .portuguese: .portuguese
        case .french: .french
        case .german: .german
        case .italian: .italian
        case .japanese: .japanese
        case .korean: .korean
        case .chineseSimplified: .simplifiedChinese
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    /// The first of the Mac's preferred languages that Waldo offers.
    static var preferred: TargetLanguage? {
        for identifier in Locale.preferredLanguages {
            let code = identifier.lowercased()
            if code.hasPrefix("zh-hans") { return .chineseSimplified }
            if let match = allCases.first(where: { $0 != .chineseSimplified && code.hasPrefix(String($0.rawValue.prefix(2)).lowercased()) }) {
                return match
            }
        }
        return nil
    }
}
