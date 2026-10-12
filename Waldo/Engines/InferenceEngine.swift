import Foundation

enum EngineKind: Sendable {
    case foundationModels
    case llamaCpp

    var displayName: String {
        switch self {
        case .foundationModels: "Apple Intelligence"
        case .llamaCpp: "llama.cpp"
        }
    }
}

/// One fully prepared model call. PromptBuilder adapts it to each engine.
struct GenerationRequest: Sendable {
    var instructions: String
    var prompt: String
    var maxOutputTokens: Int
    /// Greedy decoding, used for the single retry after a failed validation.
    var greedy: Bool
    /// Few-shot turns sent before `prompt`: (user prompt, assistant reply).
    var examples: [FewShotExample] = []
}

struct FewShotExample: Sendable, Equatable {
    var prompt: String
    var reply: String
}

enum EngineAvailability: Sendable, Equatable {
    case available
    case unavailable(String)
}

protocol InferenceEngine: Sendable {
    var kind: EngineKind { get }
    func availability() async -> EngineAvailability
    /// `onPartial` receives the whole output so far, as it grows, when the engine can stream.
    func generate(_ request: GenerationRequest, onPartial: PartialHandler?) async throws -> String
    /// Load resources for a request that is likely to come soon (the popup is open).
    func prewarm(_ request: GenerationRequest) async
    /// Release whatever `prewarm` prepared.
    func discardPrewarm() async
}

typealias PartialHandler = @Sendable (String) -> Void

extension InferenceEngine {
    func generate(_ request: GenerationRequest) async throws -> String {
        try await generate(request, onPartial: nil)
    }

    func prewarm(_ request: GenerationRequest) async {}
    func discardPrewarm() async {}
}

enum EngineError: LocalizedError, Sendable {
    case unavailable(String)
    case unsupportedLanguage
    case contentBlocked
    case textTooLong
    case busy
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        case .unsupportedLanguage: "The model doesn't support the language of this text."
        case .contentBlocked: "The model declined to process this text."
        case .textTooLong: "The text is too long to process at once."
        case .busy: "The model is busy. Try again in a moment."
        case .failed(let detail): "The model failed: \(detail)"
        }
    }

    /// Errors after which Auto mode may try the next engine.
    var allowsFallback: Bool {
        switch self {
        case .unavailable, .unsupportedLanguage, .contentBlocked: true
        case .textTooLong, .busy, .failed: false
        }
    }
}
