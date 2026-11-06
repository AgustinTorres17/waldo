import Foundation
import llama
import os

/// A downloaded open model run in-process with llama.cpp (RESEARCH §1.4, §9.1).
/// All C pointers stay inside this actor. The model loads on first use (or when
/// the popup prewarms) and unloads after the configured idle time.
actor LlamaCppEngine: InferenceEngine {
    nonisolated let kind = EngineKind.llamaCpp

    /// Context sizes are rounded up to this and capped at `maxContext` (decided defaults).
    private static let contextStep = 512
    private static let maxContext = 4_096
    private static let seed: UInt32 = 42
    /// Chat answers in detail; this is a long one (~50 s at 20 tokens/s).
    private static let maxChatOutput = 1_024
    /// Thinking writes its reasoning first, often longer than the answer.
    private static let maxThinkingOutput = 4_096

    private var model: ModelInfo?
    /// The model's vision projector, for captures in chats.
    private var vision: ModelInfo?
    private var idleUnloadSeconds = 120
    private var loaded: LoadedModel?
    private var unloadTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.agustintorres.waldo", category: "llama")

    init() {
        LlamaBackend.initialize()
    }

    /// The model to use (nil: none installed) and how long it may stay loaded unused.
    func configure(model: ModelInfo?, idleUnloadSeconds: Int) {
        self.idleUnloadSeconds = idleUnloadSeconds
        vision = model.flatMap(ModelCatalog.vision(for:))
        guard model != self.model else { return }
        self.model = model
        unload()
    }

    func availability() -> EngineAvailability {
        guard let model else {
            return .unavailable("No llama.cpp model is installed. Download one in Settings › Engine.")
        }
        guard ModelCatalog.isInstalled(model) else {
            return .unavailable("\(model.name) isn't downloaded. Download it in Settings › Engine.")
        }
        return .available
    }

    /// Loads the model and decodes the request's instructions and examples into the
    /// prefix cache: most of a short request's wait, so the click only decodes the text.
    func prewarm(_ request: GenerationRequest) {
        guard case .available = availability() else { return }
        defer { scheduleUnload() }
        guard let loaded = try? loadIfNeeded(), let plan = try? plan(request, loaded: loaded) else { return }
        let start = ContinuousClock.now
        // One step of headroom so the next prewarm (the other popup action) or the
        // click fits in this context instead of replacing it and its cache.
        let contextSize = min(Self.maxContext, plan.contextSize + Self.contextStep)
        if (try? loaded.warmPrefix(plan.prefix, contextSize: contextSize)) == true {
            log.info("Prewarmed \(plan.prefix.count, privacy: .public) prefix tokens in \(ContinuousClock.now - start, privacy: .public)")
        }
    }

    func generate(_ request: GenerationRequest, onPartial: PartialHandler?) throws -> String {
        if case .unavailable(let reason) = availability() {
            throw EngineError.unavailable(reason)
        }
        defer { scheduleUnload() }
        let loaded = try loadIfNeeded()
        let plan = try plan(request, loaded: loaded)
        let start = ContinuousClock.now
        let output = try loaded.generate(prefix: plan.prefix, suffix: plan.suffix, maxOutput: plan.maxOutput,
                                         contextSize: plan.contextSize, greedy: request.greedy, seed: Self.seed,
                                         onPartial: onPartial)
        log.info("Generated \(output.tokenCount, privacy: .public) tokens from \(plan.suffix.count, privacy: .public)+\(plan.prefix.count, privacy: .public)\(output.prefixCached ? " (cached)" : "", privacy: .public) in \(ContinuousClock.now - start, privacy: .public)")
        return output.text
    }

    // MARK: Chat

    /// Chat needs a downloaded model, whatever engine handles text; images also
    /// need its vision add-on.
    func chatAvailability(needsVision: Bool) -> EngineAvailability {
        if case .unavailable(let reason) = availability() { return .unavailable(reason) }
        if needsVision, !(vision.map(ModelCatalog.isInstalled) ?? false) {
            return .unavailable("Reading captures needs \(model?.name ?? "the model")'s vision add-on. Download it in Settings › Engine.")
        }
        return .available
    }

    /// Writes the next step of the last turn of `conversation`.
    func chat(_ conversation: ChatConversation, instructions: String, onPartial: PartialHandler?) throws -> String {
        let needsVision = conversation.turns.contains(where: \.hasImage)
        if case .unavailable(let reason) = chatAvailability(needsVision: needsVision) { throw ChatError.noVisionModel(reason) }
        defer { scheduleUnload() }
        let loaded = try loadIfNeeded()
        let start = ContinuousClock.now
        let thinks = conversation.turns.last?.thinks == true
        let output = try loaded.chat(conversation, projector: needsVision ? vision : nil, instructions: instructions,
                                     maxOutput: thinks ? Self.maxThinkingOutput : Self.maxChatOutput, onPartial: onPartial)
        log.info("Chat turn \(conversation.turns.count, privacy: .public): \(output.tokenCount, privacy: .public) tokens in \(ContinuousClock.now - start, privacy: .public)")
        return output.text
    }

    /// Frees the chat's memory when its panel closes.
    func endChat(_ id: UUID) {
        loaded?.endChat(id)
    }

    private struct Plan {
        let prefix: [llama_token]
        let suffix: [llama_token]
        let maxOutput: Int
        let contextSize: Int
    }

    /// Tokens and context size for a request. Prewarm uses the same context size as
    /// the request it predicts: a larger context would drop the cached prefix.
    private func plan(_ request: GenerationRequest, loaded: LoadedModel) throws -> Plan {
        let (prefixText, suffixText) = PromptFormatter.parts(request, family: loaded.info.family)
        let prefix = loaded.tokenize(prefixText, addSpecial: true)
        let suffix = loaded.tokenize(suffixText, addSpecial: false)
        let promptCount = prefix.count + suffix.count
        let maxOutput = min(request.maxOutputTokens, Self.maxContext - promptCount)
        guard !prefix.isEmpty, !suffix.isEmpty, maxOutput >= 32 else { throw EngineError.textTooLong }
        let needed = promptCount + maxOutput
        let contextSize = min(Self.maxContext, (needed + Self.contextStep - 1) / Self.contextStep * Self.contextStep)
        return Plan(prefix: prefix, suffix: suffix, maxOutput: maxOutput, contextSize: contextSize)
    }

    // MARK: Loading

    private func loadIfNeeded() throws -> LoadedModel {
        if let loaded { return loaded }
        guard let model else { throw EngineError.unavailable("No llama.cpp model is selected.") }
        let start = ContinuousClock.now
        guard let loaded = LoadedModel(info: model) else {
            throw EngineError.failed("Couldn't load \(model.name). Try deleting and downloading it again.")
        }
        log.info("Loaded \(model.id, privacy: .public) in \(ContinuousClock.now - start, privacy: .public)")
        self.loaded = loaded
        return loaded
    }

    private func unload() {
        unloadTask?.cancel()
        unloadTask = nil
        if loaded != nil {
            log.info("Unloading model")
            loaded = nil
        }
    }

    private func scheduleUnload() {
        unloadTask?.cancel()
        let seconds = idleUnloadSeconds
        unloadTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.unload()
        }
    }
}

/// llama_backend_init must run once per process; llama.cpp's own logging is
/// reduced to errors, routed to the unified log.
private enum LlamaBackend {
    private static let once: Void = {
        let logErrors: ggml_log_callback = { level, text, _ in
            guard level == GGML_LOG_LEVEL_ERROR, let text else { return }
            llamaLog.error("\(String(cString: text), privacy: .public)")
        }
        llama_log_set(logErrors, nil)
        mtmd_log_set(logErrors, nil)
        mtmd_helper_log_set(logErrors, nil)
        llama_backend_init()
    }()

    static func initialize() {
        _ = once
    }
}

private let llamaLog = Logger(subsystem: "com.agustintorres.waldo", category: "llama")

/// A loaded model plus its context. Not thread-safe: owned by LlamaCppEngine.
final class LoadedModel {
    let info: ModelInfo
    let model: OpaquePointer
    let vocab: OpaquePointer
    /// Loaded for the first chat with a capture (LlamaCppEngine+Chat.swift).
    var projector: VisionProjector?
    var chatSession: ChatSession?
    private var context: OpaquePointer?
    private var contextSize = 0
    /// Evaluated prefix states (system prompt + examples), most recent last.
    /// About 80 MB each for the 4B model; two cover translate and correct.
    private var prefixCache: [(tokens: [llama_token], state: [UInt8])] = []
    private static let prefixCacheLimit = 2

    init?(info: ModelInfo) {
        var params = llama_model_default_params()
        params.n_gpu_layers = -1 // everything on Metal
        guard let model = llama_model_load_from_file(ModelCatalog.fileURL(for: info).path, params),
              let vocab = llama_model_get_vocab(model) else { return nil }
        self.info = info
        self.model = model
        self.vocab = vocab
    }

    deinit {
        chatSession = nil // both reference the model
        projector = nil
        if let context { llama_free(context) }
        llama_model_free(model)
    }

    func tokenize(_ text: String, addSpecial: Bool) -> [llama_token] {
        let utf8Count = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(utf8Count) + 16)
        // parse_special: the chat template's <|im_start|> etc. must become control tokens.
        let count = llama_tokenize(vocab, text, utf8Count, &tokens, Int32(tokens.count), addSpecial, true)
        return count > 0 ? Array(tokens.prefix(Int(count))) : []
    }

    struct Output {
        let text: String
        let tokenCount: Int
        let prefixCached: Bool
    }

    func generate(prefix: [llama_token], suffix: [llama_token], maxOutput: Int, contextSize: Int,
                  greedy: Bool, seed: UInt32, onPartial: PartialHandler?) throws -> Output {
        let context = try prepareContext(size: contextSize)
        let memory = llama_get_memory(context)
        llama_memory_clear(memory, true)

        let prefixCached = restorePrefix(prefix, context: context)
        if !prefixCached {
            llama_memory_clear(memory, true)
            try decode(prefix, context: context)
            savePrefix(prefix, context: context)
        }
        try decode(suffix, context: context)

        let sampler = Self.makeSampler(greedy: greedy, seed: seed)
        defer { llama_sampler_free(sampler) }

        var bytes: [UInt8] = []
        var produced = 0
        var piece = [CChar](repeating: 0, count: 256)
        while produced < maxOutput {
            if Task.isCancelled { throw CancellationError() }
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            produced += 1

            let length = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            if length > 0 {
                bytes.append(contentsOf: piece.prefix(Int(length)).map { UInt8(bitPattern: $0) })
                // nil while the bytes end mid-character: wait for the next piece.
                if let onPartial, let text = String(bytes: bytes, encoding: .utf8) { onPartial(text) }
            }
            let status = llama_decode(context, llama_batch_get_one(&token, 1))
            guard status == 0 else { throw EngineError.failed("llama_decode returned \(status)") }
        }
        // Pieces can split multi-byte characters, so decode once at the end.
        return Output(text: String(decoding: bytes, as: UTF8.self), tokenCount: produced, prefixCached: prefixCached)
    }

    /// Decodes `prefix` into the cache unless it's already there. Returns whether it did work.
    func warmPrefix(_ prefix: [llama_token], contextSize: Int) throws -> Bool {
        let context = try prepareContext(size: contextSize)
        guard !prefixCache.contains(where: { $0.tokens == prefix }) else { return false }
        llama_memory_clear(llama_get_memory(context), true)
        try decode(prefix, context: context)
        savePrefix(prefix, context: context)
        return true
    }

    private func decode(_ tokens: [llama_token], context: OpaquePointer) throws {
        var tokens = tokens
        let status = tokens.withUnsafeMutableBufferPointer {
            llama_decode(context, llama_batch_get_one($0.baseAddress, Int32($0.count)))
        }
        guard status == 0 else { throw EngineError.failed("llama_decode returned \(status)") }
    }

    // MARK: Prefix cache

    private func restorePrefix(_ prefix: [llama_token], context: OpaquePointer) -> Bool {
        guard let index = prefixCache.firstIndex(where: { $0.tokens == prefix }) else { return false }
        let entry = prefixCache.remove(at: index)
        let restored = entry.state.withUnsafeBufferPointer {
            llama_state_seq_set_data(context, $0.baseAddress, $0.count, 0)
        }
        guard restored > 0 else { return false }
        prefixCache.append(entry)
        return true
    }

    private func savePrefix(_ prefix: [llama_token], context: OpaquePointer) {
        var state = [UInt8](repeating: 0, count: llama_state_seq_get_size(context, 0))
        let written = state.withUnsafeMutableBufferPointer {
            llama_state_seq_get_data(context, $0.baseAddress, $0.count, 0)
        }
        guard written > 0 else { return }
        prefixCache.append((prefix, Array(state.prefix(written))))
        if prefixCache.count > Self.prefixCacheLimit { prefixCache.removeFirst() }
    }

    /// Reuses the context unless a larger one is needed.
    private func prepareContext(size: Int) throws -> OpaquePointer {
        if let context, contextSize >= size { return context }
        if let context { llama_free(context) }
        context = nil
        prefixCache.removeAll() // states belong to the old context's layout

        var params = llama_context_default_params()
        params.n_ctx = UInt32(size)
        params.n_batch = UInt32(size) // the whole prompt is decoded in one call
        params.n_ubatch = 512
        params.n_threads = Self.performanceCores
        params.n_threads_batch = Self.performanceCores
        guard let created = llama_init_from_model(model, params) else {
            throw EngineError.failed("Couldn't create a llama.cpp context.")
        }
        context = created
        contextSize = size
        return created
    }

    /// Sampling from RESEARCH §7.4.3: penalties off, low temperature, greedy retry.
    private static func makeSampler(greedy: Bool, seed: UInt32) -> UnsafeMutablePointer<llama_sampler> {
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        if greedy {
            llama_sampler_chain_add(chain, llama_sampler_init_greedy())
        } else {
            llama_sampler_chain_add(chain, llama_sampler_init_top_k(20))
            llama_sampler_chain_add(chain, llama_sampler_init_top_p(0.8, 1))
            llama_sampler_chain_add(chain, llama_sampler_init_min_p(0.05, 1))
            llama_sampler_chain_add(chain, llama_sampler_init_temp(Float(PromptBuilder.temperature)))
            llama_sampler_chain_add(chain, llama_sampler_init_dist(seed))
        }
        return chain
    }

    static let performanceCores: Int32 = {
        var cores: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.physicalcpu", &cores, &size, nil, 0) == 0, cores > 0 { return cores }
        return Int32(max(1, ProcessInfo.processInfo.activeProcessorCount / 2))
    }()
}
