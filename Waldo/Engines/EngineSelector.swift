import Foundation

/// Picks the engines to try for a request, in order, based on the user's mode.
@MainActor
final class EngineSelector {
    private let settings: SettingsStore
    private let foundationModels: (any InferenceEngine)?
    private let llamaCpp = LlamaCppEngine()

    init(settings: SettingsStore) {
        self.settings = settings
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            foundationModels = FoundationModelsEngine()
        } else {
            foundationModels = nil
        }
        #else
        foundationModels = nil
        #endif
    }

    /// The chosen model if it's downloaded, otherwise any downloaded model.
    var activeModel: ModelInfo? {
        if let chosen = ModelCatalog.model(id: settings.llamaModelID), ModelCatalog.isInstalled(chosen) {
            return chosen
        }
        return ModelCatalog.all.first(where: ModelCatalog.isInstalled)
    }

    /// Engines to try, in order. Empty with a reason when none can run.
    func candidates() async -> (engines: [any InferenceEngine], reason: String?) {
        await llamaCpp.configure(model: activeModel, idleUnloadSeconds: settings.llamaIdleUnloadSeconds)
        let llama = await usable(llamaCpp)
        let apple: (engine: (any InferenceEngine)?, reason: String?)
        if let foundationModels {
            apple = await usable(foundationModels)
        } else {
            apple = (nil, "Apple Intelligence requires macOS 26 or later.")
        }

        switch settings.engineMode {
        case .auto:
            // Apple first; a downloaded model is the fallback for languages or content it refuses.
            let engines = [apple.engine, llama.engine].compactMap { $0 }
            let reason = "\(apple.reason ?? "Apple Intelligence is unavailable.") You can also download a model in Settings › Engine."
            return (engines, engines.isEmpty ? reason : nil)
        case .foundationModels:
            return (apple.engine.map { [$0] } ?? [], apple.reason)
        case .llamaCpp:
            return (llama.engine.map { [$0] } ?? [], llama.reason)
        }
    }

    private func usable(_ engine: any InferenceEngine) async -> (engine: (any InferenceEngine)?, reason: String?) {
        if case .unavailable(let reason) = await engine.availability() {
            return (nil, reason)
        }
        return (engine, nil)
    }

    /// The engine for chats, which always use the downloaded model (with its vision
    /// add-on for captures), whatever handles text. Nil with a reason when it can't run.
    func chatEngine(needsVision: Bool) async -> (engine: LlamaCppEngine?, reason: String?) {
        await llamaCpp.configure(model: activeModel, idleUnloadSeconds: settings.llamaIdleUnloadSeconds)
        if case .unavailable(let reason) = await llamaCpp.chatAvailability(needsVision: needsVision) {
            return (nil, "Chat runs on a downloaded model. \(reason)")
        }
        return (llamaCpp, nil)
    }

    /// Short text for the menu.
    func statusDescription() async -> String {
        let (engines, _) = await candidates()
        guard let engine = engines.first else {
            return switch settings.engineMode {
            case .llamaCpp: "llama.cpp (no model)"
            default: "Apple Intelligence (unavailable)"
            }
        }
        if engine.kind == .llamaCpp, let model = activeModel {
            return "\(model.name) (llama.cpp)"
        }
        return engine.kind.displayName
    }
}
