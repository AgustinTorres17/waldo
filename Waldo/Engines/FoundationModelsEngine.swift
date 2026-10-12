// Compiled only with the macOS 26 SDK; older Command Line Tools build llama.cpp only.
#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// Apple's on-device model (macOS 26+). A new session is created per request,
/// so nothing is held between requests. Only the popup prewarms: the user needs
/// at least a second to click, which is the window Apple recommends; the hotkey
/// flow is faster than that, so it doesn't.
@available(macOS 26.0, *)
actor FoundationModelsEngine: InferenceEngine {
    nonisolated let kind = EngineKind.foundationModels

    /// Permissive guardrails only apply to String output, which is all we use.
    private let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)

    /// A session prewarmed for one specific request, used at most once.
    private var prepared: (key: String, session: LanguageModelSession)?

    func prewarm(_ request: GenerationRequest) {
        guard case .available = availability() else { return }
        let session = LanguageModelSession(model: model, instructions: request.instructions)
        session.prewarm(promptPrefix: Prompt(request.prompt))
        prepared = (Self.key(for: request), session)
    }

    func discardPrewarm() {
        prepared = nil
    }

    private static func key(for request: GenerationRequest) -> String {
        request.instructions + "\u{0}" + request.prompt
    }

    func availability() -> EngineAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Apple Intelligence is turned off. Turn it on in System Settings › Apple Intelligence & Siri.")
        case .unavailable(.deviceNotEligible):
            return .unavailable("This Mac doesn't support Apple Intelligence.")
        case .unavailable(.modelNotReady):
            return .unavailable("Apple Intelligence is still getting ready (its model may be downloading). Try again later.")
        case .unavailable:
            return .unavailable("Apple Intelligence is unavailable.")
        }
    }

    func generate(_ request: GenerationRequest, onPartial: PartialHandler?) async throws -> String {
        if case .unavailable(let reason) = availability() {
            throw EngineError.unavailable(reason)
        }
        let session: LanguageModelSession
        if let prepared, prepared.key == Self.key(for: request) {
            session = prepared.session
        } else {
            session = LanguageModelSession(model: model, instructions: request.instructions)
        }
        prepared = nil
        let options = request.greedy
            ? GenerationOptions(sampling: .greedy, maximumResponseTokens: request.maxOutputTokens)
            : GenerationOptions(temperature: PromptBuilder.temperature, maximumResponseTokens: request.maxOutputTokens)
        do {
            guard let onPartial else {
                return try await session.respond(to: request.prompt, options: options).content
            }
            // Each snapshot holds the whole response so far.
            var content = ""
            for try await snapshot in session.streamResponse(to: request.prompt, options: options) {
                content = snapshot.content
                onPartial(content)
            }
            return content
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.engineError(for: error)
        }
    }

    private static func engineError(for error: LanguageModelSession.GenerationError) -> EngineError {
        switch error {
        case .exceededContextWindowSize: .textTooLong
        case .unsupportedLanguageOrLocale: .unsupportedLanguage
        case .guardrailViolation, .refusal: .contentBlocked
        case .assetsUnavailable: .unavailable("Apple Intelligence model assets are unavailable right now.")
        case .rateLimited, .concurrentRequests: .busy
        default: .failed(error.localizedDescription)
        }
    }
}
#endif
