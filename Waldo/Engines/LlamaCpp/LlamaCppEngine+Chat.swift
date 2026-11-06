import Foundation
import llama

/// The vision projector (libmtmd), loaded the first time a chat has an image.
/// Owned by a LoadedModel; freed before it.
final class VisionProjector {
    let id: String
    let context: OpaquePointer

    init(id: String, context: OpaquePointer) {
        self.id = id
        self.context = context
    }

    deinit {
        mtmd_free(context)
    }
}

/// One chat's context. Follow-ups append to it, so images and earlier turns
/// aren't read again. Qwen3.5's recurrent layers can only append, never roll
/// back: anything unexpected (a cancelled answer, another chat) starts over.
final class ChatSession {
    let context: OpaquePointer
    let conversationID: UUID
    /// Everything in the context as text (images as their marker). A prompt
    /// that starts with it only needs the rest decoded.
    var transcript = ""
    /// Next position (with M-RoPE an image takes fewer positions than tokens).
    var nextPosition: llama_pos = 0
    var usedTokens = 0
    /// Set while a turn is being added; still set afterwards means it didn't finish.
    var isIncomplete = false

    init(context: OpaquePointer, conversationID: UUID) {
        self.context = context
        self.conversationID = conversationID
    }

    deinit {
        llama_free(context)
    }
}

extension LoadedModel {
    /// Room for a long chat with detailed answers (~570 MB on the 4B model;
    /// 8k took ~310 MB, 32k ~1 GB).
    static let chatContextSize = 16_384
    private static let chatBatchSize = 2_048
    /// More image tokens read small text better but take longer to process
    /// (~2 s per 1,000 on an M4). A whole screen at this size still reads 13 pt text.
    private static let maxImageTokens: Int32 = 1_024
    /// A search query is one short line.
    private static let maxQueryTokens = 48
    /// Qwen3.5 can reason for minutes over a trivial question (133 s for 12 − 5).
    /// Past this many tokens (~50 s) its reasoning is closed for it, with the
    /// wording Qwen documents for thinking budgets, and it answers.
    private static let thinkingBudget = 1_024
    private static let thinkingCutoff = "\n\nConsidering the limited time by the user, I have to give the solution based on the thinking directly now.\n</think>\n\n"

    /// Writes the next step of the last turn of `conversation` (its search query,
    /// or its answer), streaming the text so far to `onPartial`. `projector` is
    /// needed only when the conversation has images.
    func chat(_ conversation: ChatConversation, projector: ModelInfo?, instructions: String, maxOutput: Int,
              onPartial: PartialHandler?) throws -> Output {
        guard !conversation.turns.isEmpty else { throw ChatError.conversationTooLong }
        let marker = String(cString: mtmd_default_marker())
        let (prompt, step) = PromptFormatter.chat(instructions: instructions, turns: conversation.turns,
                                                  marker: marker, family: info.family)
        // A saved chat's captures load from disk when it's opened; a missing one
        // would leave its marker without an image.
        guard conversation.hasAllImages else { throw EngineError.failed("A capture in this chat couldn't be loaded.") }
        let images = conversation.turns.compactMap(\.image)

        let session: ChatSession
        let text: String
        let newImages: [ChatImage]
        if let current = chatSession, current.conversationID == conversation.id, !current.isIncomplete,
           prompt.hasPrefix(current.transcript) {
            session = current
            text = String(prompt.dropFirst(current.transcript.count))
            newImages = Array(images.dropFirst(current.transcript.components(separatedBy: marker).count - 1))
        } else {
            chatSession = nil // free the old context first
            session = try makeChatSession(for: conversation.id)
            chatSession = session
            text = prompt
            newImages = images
        }

        session.isIncomplete = true
        if newImages.isEmpty {
            try decodeText(text, addSpecial: session.usedTokens == 0, in: session)
        } else {
            guard let projector else { throw ChatError.noVisionModel("Reading captures needs the vision add-on. Download it in Settings › Engine.") }
            try decodeWithImages(text, images: newImages, in: session, projector: try loadProjector(projector))
        }
        session.transcript = prompt

        let thinks = step == .answer && conversation.turns.last?.thinks == true
        let limit = step == .searchQuery ? Self.maxQueryTokens : maxOutput
        let output = try generate(in: session, maxOutput: limit,
                                  stopsAtNewline: step == .searchQuery, thinks: thinks, onPartial: onPartial)
        session.transcript += output.text
        session.isIncomplete = false
        return output
    }

    /// Frees the chat's context; the projector stays until the model unloads.
    func endChat(_ id: UUID) {
        if chatSession?.conversationID == id { chatSession = nil }
    }

    private func loadProjector(_ info: ModelInfo) throws -> VisionProjector {
        if let projector, projector.id == info.id { return projector }
        projector = nil
        var params = mtmd_context_params_default()
        params.use_gpu = true
        params.n_threads = Self.performanceCores
        params.warmup = false
        params.image_max_tokens = Self.maxImageTokens
        guard let context = mtmd_init_from_file(ModelCatalog.fileURL(for: info).path, model, params) else {
            throw EngineError.failed("Couldn't load \(info.name). Try deleting and downloading it again.")
        }
        let loaded = VisionProjector(id: info.id, context: context)
        projector = loaded
        return loaded
    }

    private func makeChatSession(for id: UUID) throws -> ChatSession {
        var params = llama_context_default_params()
        params.n_ctx = UInt32(Self.chatContextSize)
        params.n_batch = UInt32(Self.chatBatchSize)
        params.n_ubatch = 512
        params.n_threads = Self.performanceCores
        params.n_threads_batch = Self.performanceCores
        guard let context = llama_init_from_model(model, params) else {
            throw EngineError.failed("Couldn't create a llama.cpp context.")
        }
        return ChatSession(context: context, conversationID: id)
    }

    /// Text only: no projector needed.
    private func decodeText(_ text: String, addSpecial: Bool, in session: ChatSession) throws {
        let tokens = tokenize(text, addSpecial: addSpecial)
        guard session.usedTokens + tokens.count + 64 <= Self.chatContextSize else { throw ChatError.conversationTooLong }
        var batch = llama_batch_init(Int32(Self.chatBatchSize), 0, 1)
        defer { llama_batch_free(batch) }
        for start in stride(from: 0, to: tokens.count, by: Self.chatBatchSize) {
            let slice = tokens[start..<min(start + Self.chatBatchSize, tokens.count)]
            batch.n_tokens = Int32(slice.count)
            for (offset, token) in slice.enumerated() {
                batch.token[offset] = token
                batch.pos[offset] = session.nextPosition + llama_pos(start + offset)
                batch.n_seq_id[offset] = 1
                batch.seq_id[offset]![0] = 0
                batch.logits[offset] = start + offset == tokens.count - 1 ? 1 : 0
            }
            let status = llama_decode(session.context, batch)
            guard status == 0 else { throw EngineError.failed("llama_decode returned \(status)") }
        }
        session.nextPosition += llama_pos(tokens.count)
        session.usedTokens += tokens.count
    }

    /// Text with the images in place of their markers, in order.
    private func decodeWithImages(_ text: String, images: [ChatImage], in session: ChatSession,
                                  projector: VisionProjector) throws {
        let chunks = mtmd_input_chunks_init()!
        defer { mtmd_input_chunks_free(chunks) }
        var bitmaps: [OpaquePointer?] = images.map { image in
            image.rgb.withUnsafeBufferPointer { mtmd_bitmap_init(UInt32(image.width), UInt32(image.height), $0.baseAddress) }
        }
        defer { bitmaps.forEach { mtmd_bitmap_free($0) } }
        let status = text.withCString { cText in
            var input = mtmd_input_text(text: cText, text_len: strlen(cText), add_special: session.usedTokens == 0,
                                        parse_special: true)
            return bitmaps.withUnsafeMutableBufferPointer {
                mtmd_tokenize(projector.context, chunks, &input, $0.baseAddress, $0.count)
            }
        }
        guard status == 0 else { throw EngineError.failed("mtmd_tokenize returned \(status)") }

        let count = mtmd_helper_get_n_tokens(chunks)
        guard session.usedTokens + count + 64 <= Self.chatContextSize else { throw ChatError.conversationTooLong }
        var position = session.nextPosition
        let evaluated = mtmd_helper_eval_chunks(projector.context, session.context, chunks, position, 0,
                                                Int32(Self.chatBatchSize), true, &position)
        guard evaluated == 0 else { throw EngineError.failed("mtmd_helper_eval_chunks returned \(evaluated)") }
        session.nextPosition = position
        session.usedTokens += count
    }

    /// Samples until end of turn (or a line break, for a query), decoding each
    /// token at an explicit position (M-RoPE). The text returned is exactly what's
    /// now in the context: a token with a line break that stops it isn't kept.
    /// `maxOutput` counts the answer alone, so reasoning can't use up its room.
    private func generate(in session: ChatSession, maxOutput: Int, stopsAtNewline: Bool, thinks: Bool,
                          onPartial: PartialHandler?) throws -> Output {
        let sampler = Self.makeChatSampler(thinks: thinks)
        defer { llama_sampler_free(sampler) }
        var batch = llama_batch_init(1, 0, 1)
        defer { llama_batch_free(batch) }

        var bytes: [UInt8] = []
        var produced = 0
        var answerTokens = 0
        var reachedLimit = false
        var piece = [CChar](repeating: 0, count: 256)
        var isThinking = thinks
        let closeTag = Array("</think>".utf8)
        while true {
            if Task.isCancelled { throw CancellationError() }
            if answerTokens >= maxOutput || session.usedTokens >= Self.chatContextSize {
                reachedLimit = true
                break
            }
            if isThinking, produced >= Self.thinkingBudget {
                try decodeText(Self.thinkingCutoff, addSpecial: false, in: session)
                bytes.append(contentsOf: Self.thinkingCutoff.utf8)
                isThinking = false
            }
            let token = llama_sampler_sample(sampler, session.context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            produced += 1
            if !isThinking { answerTokens += 1 }

            let length = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            let pieceBytes = length > 0 ? piece.prefix(Int(length)).map { UInt8(bitPattern: $0) } : []
            if stopsAtNewline, pieceBytes.contains(UInt8(ascii: "\n")), !bytes.isEmpty { break }
            if !pieceBytes.isEmpty {
                bytes.append(contentsOf: pieceBytes)
                if let onPartial, let text = String(bytes: bytes, encoding: .utf8) { onPartial(text) }
                if isThinking, bytes.suffix(closeTag.count + 8).containsSequence(closeTag) { isThinking = false }
            }
            batch.n_tokens = 1
            batch.token[0] = token
            batch.pos[0] = session.nextPosition
            batch.n_seq_id[0] = 1
            batch.seq_id[0]![0] = 0
            batch.logits[0] = 1
            let status = llama_decode(session.context, batch)
            guard status == 0 else { throw EngineError.failed("llama_decode returned \(status)") }
            session.nextPosition += 1
            session.usedTokens += 1
        }
        return Output(text: String(decoding: bytes, as: UTF8.self), tokenCount: produced, prefixCached: false,
                      reachedLimit: reachedLimit)
    }

    /// Qwen3.5's recommended sampling, with and without thinking: long free-form
    /// answers loop under greedy or very low temperatures.
    private static func makeChatSampler(thinks: Bool) -> UnsafeMutablePointer<llama_sampler> {
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(20))
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(thinks ? 0.95 : 0.8, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(thinks ? 0.6 : 0.7))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))
        return chain
    }
}

private extension Collection where Element: Equatable {
    func containsSequence(_ sequence: [Element]) -> Bool {
        guard count >= sequence.count else { return false }
        let elements = Array(self)
        return (0...(elements.count - sequence.count)).contains { Array(elements[$0..<($0 + sequence.count)]) == sequence }
    }
}
