import Foundation
import NaturalLanguage
import os

struct ProcessingResult: Sendable {
    let text: String
    let task: ProcessingTask
    let engine: EngineKind?
    let changed: Bool
    var modeName: String?
    /// Parts that failed validation and were left as the user wrote them.
    var keptParts = 0

    var summary: String {
        guard let engine else { return "Nothing to translate or correct." }
        let action = switch task {
        case .translate(let source?): "Translated from \(source)"
        case .translate(nil): "Translated"
        case .correct: changed ? "Corrected" : "Already correct"
        case .translateOrCorrect: changed ? "Rewritten" : "Unchanged"
        case .rephrase: changed ? "Rephrased" : "Unchanged"
        }
        let mode = modeName.map { " · \($0)" } ?? ""
        let kept = switch keptParts {
        case 0: ""
        case 1: " 1 part was left as you wrote it."
        default: " \(keptParts) parts were left as you wrote them."
        }
        return "\(action) with \(engine.displayName)\(mode).\(kept)"
    }
}

enum ProcessingError: LocalizedError, Sendable {
    case noEngine(String)
    case textTooLong
    case engine(EngineKind, EngineError)
    case validation(String)

    var errorDescription: String? {
        switch self {
        case .noEngine(let reason): reason
        case .textTooLong: "The text is too long. Try a shorter selection."
        case .engine(let kind, let error): "\(kind.displayName): \(error.localizedDescription)"
        case .validation(let reason): "\(reason) Your text was left unchanged."
        }
    }
}

/// The full pipeline (RESEARCH §7.5): detect → prompt → generate → validate
/// (one greedy retry). Runs off the main actor.
struct TextProcessor: Sendable {
    private static let log = Logger(subsystem: "com.agustintorres.waldo", category: "processing")

    /// How the parts of one request went; a long text survives a part that fails.
    private struct PartStats {
        var processed = 0
        var kept = 0
        var lastFailure: ProcessingError?
    }

    /// `onProgress` receives the whole result so far while it's generated; it is
    /// unvalidated, so only for display. It may restart (a retry, another engine).
    func process(_ input: String, mode: ProcessingMode = .automatic, target: TargetLanguage,
                 customMode: CustomMode? = nil, glossary: [String] = [], engines: [any InferenceEngine],
                 onProgress: PartialHandler? = nil) async throws -> ProcessingResult {
        let customMode = customMode.flatMap { $0.isEmpty ? nil : $0 }
        let normalized = input.replacingOccurrences(of: "\r\n", with: "\n")
        let (leading, core, trailing) = Self.splitOuterWhitespace(normalized)

        guard ProtectedSpans.hasTranslatableContent(core) else {
            return ProcessingResult(text: input, task: .correct, engine: nil, changed: false)
        }
        guard PromptBuilder.estimatedTokens(core) <= PromptBuilder.maxInputTokens else {
            Self.log.error("Text too long: \(core.count, privacy: .public) characters")
            throw ProcessingError.textTooLong
        }
        guard !engines.isEmpty else {
            throw ProcessingError.noEngine("No engine is available.")
        }

        let task = Self.task(for: core, mode: mode, target: target)

        var lastError: ProcessingError?
        for (index, engine) in engines.enumerated() {
            do {
                var output = ""
                var stats = PartStats()
                let progress = onProgress.map { ProgressReporter(prefix: leading, handler: $0) }
                for segment in ProtectedSpans.segments(core) {
                    output += try await processSegment(segment, task: task, target: target, customMode: customMode,
                                                       glossary: glossary, engine: engine, progress: progress,
                                                       stats: &stats)
                }
                // Nothing usable came back: report why instead of returning the input.
                if stats.kept == stats.processed, let failure = stats.lastFailure { throw failure }
                let text = leading + output + trailing
                return ProcessingResult(text: text, task: task, engine: engine.kind, changed: text != normalized,
                                        modeName: customMode?.name, keptParts: stats.kept)
            } catch let error as EngineError {
                Self.log.error("\(engine.kind.displayName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                lastError = .engine(engine.kind, error)
                let isLast = index == engines.count - 1
                if !error.allowsFallback || isLast { break }
            }
        }
        throw lastError ?? ProcessingError.noEngine("No engine is available.")
    }

    /// Prepares the first engine for the request `process` will most likely make.
    func prewarm(_ input: String, mode: ProcessingMode = .automatic, target: TargetLanguage,
                 customMode: CustomMode? = nil, engines: [any InferenceEngine]) async {
        let customMode = customMode.flatMap { $0.isEmpty ? nil : $0 }
        guard let engine = engines.first else { return }
        let core = input.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard ProtectedSpans.hasTranslatableContent(core),
              PromptBuilder.estimatedTokens(core) <= PromptBuilder.maxInputTokens,
              let segment = ProtectedSpans.segments(core).filter({ !$0.isCode })
                  .flatMap({ Self.chunks($0.text) })
                  .first(where: { !$0.isSeparator && ProtectedSpans.hasTranslatableContent($0.text) })
        else { return }
        let text = Self.splitOuterWhitespace(segment.text).1
        await engine.prewarm(PromptBuilder.request(for: Self.task(for: core, mode: mode, target: target), text: text,
                                                   target: target, customMode: customMode,
                                                   engine: engine.kind, greedy: false))
        // The popup offers both actions. llama.cpp keeps both prefixes cached; Apple's
        // model keeps one prewarmed session, so it stays on the likelier action.
        if mode == .automatic, engine.kind == .llamaCpp, !Task.isCancelled {
            await engine.prewarm(PromptBuilder.request(for: .rephrase, text: text, target: target,
                                                       customMode: customMode, engine: engine.kind, greedy: false))
        }
    }

    /// Rephrase works on any input language, so it skips detection.
    static func task(for core: String, mode: ProcessingMode, target: TargetLanguage) -> ProcessingTask {
        switch mode {
        case .automatic: LanguageDetector.task(for: ProtectedSpans.stripped(core), target: target)
        case .rephrase: .rephrase
        }
    }

    /// Code blocks and symbol-only prose pass through untouched. Prose goes in
    /// chunks of whole paragraphs: in a whole email the 4B model followed the
    /// prompt's rules (calques) less than in short texts, while a lone sign-off
    /// lost its context and got reformatted.
    private func processSegment(_ segment: (text: String, isCode: Bool), task: ProcessingTask,
                                target: TargetLanguage, customMode: CustomMode?, glossary: [String],
                                engine: any InferenceEngine, progress: ProgressReporter?,
                                stats: inout PartStats) async throws -> String {
        guard !segment.isCode else {
            progress?.append(segment.text)
            return segment.text
        }
        var output = ""
        for (text, isSeparator) in Self.chunks(segment.text) {
            guard !isSeparator, ProtectedSpans.hasTranslatableContent(text) else {
                output += text
                progress?.append(text)
                continue
            }
            let (leading, core, trailing) = Self.splitOuterWhitespace(text)
            progress?.append(leading)
            stats.processed += 1
            let result: String
            do {
                result = try await generateValidated(task: task, text: core, target: target, customMode: customMode,
                                                     keepTerms: Glossary.terms(in: core, glossary: glossary),
                                                     engine: engine, progress: progress)
            } catch let failure as ProcessingError {
                // One rejected part keeps its original text; the rest still goes through.
                let part = stats.processed
                Self.log.error("Part \(part, privacy: .public) (\(core.count, privacy: .public) characters) kept: \(failure.localizedDescription, privacy: .public)")
                stats.kept += 1
                stats.lastFailure = failure
                result = core
            }
            progress?.append(result + trailing)
            output += leading + result + trailing
        }
        return output
    }

    /// Target size of a chunk; only a single longer sentence goes whole.
    static let chunkCharacters = 500

    /// Packs consecutive paragraphs into chunks of up to `chunkCharacters`; the
    /// blank lines between chunks are separate pieces. A longer paragraph is split
    /// at line breaks (WhatsApp and Slack messages rarely have blank lines), and a
    /// longer line at sentence ends.
    static func chunks(_ text: String) -> [(text: String, isSeparator: Bool)] {
        var result: [(String, Bool)] = []
        var current = ""
        var pendingSeparator = ""
        let pieces = paragraphs(text).flatMap { piece, isSeparator in
            isSeparator ? [(piece, true)] : split(piece, at: lineBreaks).flatMap { line, isBreak in
                isBreak ? [(line, true)] : sentences(line)
            }
        }
        for (piece, isSeparator) in pieces {
            if isSeparator {
                pendingSeparator = piece
                continue
            }
            if !current.isEmpty, current.count + pendingSeparator.count + piece.count > chunkCharacters {
                result.append((current, false))
                result.append((pendingSeparator, true))
                current = piece
            } else {
                current += pendingSeparator + piece
            }
            pendingSeparator = ""
        }
        if !current.isEmpty { result.append((current, false)) }
        if !pendingSeparator.isEmpty { result.append((pendingSeparator, true)) }
        return result
    }

    private static let blankLines = try! NSRegularExpression(pattern: "\\n[ \\t]*\\n\\s*")
    private static let lineBreaks = try! NSRegularExpression(pattern: "\\n")

    /// `text` unchanged if it fits in a chunk, else split at `separator`.
    private static func split(_ text: String, at separator: NSRegularExpression) -> [(String, Bool)] {
        guard text.count > chunkCharacters else { return [(text, false)] }
        var result: [(String, Bool)] = []
        var cursor = text.startIndex
        for match in separator.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            if cursor < range.lowerBound { result.append((String(text[cursor..<range.lowerBound]), false)) }
            result.append((String(text[range]), true))
            cursor = range.upperBound
        }
        if cursor < text.endIndex { result.append((String(text[cursor...]), false)) }
        return result
    }

    /// A line longer than a chunk, split into sentences with the spaces between
    /// them as separators.
    private static func sentences(_ line: String) -> [(String, Bool)] {
        guard line.count > chunkCharacters else { return [(line, false)] }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = line
        var result: [(String, Bool)] = []
        tokenizer.enumerateTokens(in: line.startIndex..<line.endIndex) { range, _ in
            let sentence = String(line[range])
            let core = sentence.trimmingCharacters(in: .whitespaces)
            guard let coreRange = sentence.range(of: core), !core.isEmpty else {
                result.append((sentence, true))
                return true
            }
            let before = String(sentence[..<coreRange.lowerBound])
            let after = String(sentence[coreRange.upperBound...])
            if !before.isEmpty { result.append((before, true)) }
            result.append((core, false))
            if !after.isEmpty { result.append((after, true)) }
            return true
        }
        return result
    }

    /// Splits prose at blank lines, keeping each separator as its own piece.
    static func paragraphs(_ text: String) -> [(text: String, isSeparator: Bool)] {
        var result: [(String, Bool)] = []
        var cursor = text.startIndex
        for match in blankLines.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            if cursor < range.lowerBound { result.append((String(text[cursor..<range.lowerBound]), false)) }
            result.append((String(text[range]), true))
            cursor = range.upperBound
        }
        if cursor < text.endIndex { result.append((String(text[cursor...]), false)) }
        return result
    }

    /// Validation failures retry once with greedy decoding, then fail without fallback.
    private func generateValidated(task: ProcessingTask, text: String, target: TargetLanguage,
                                   customMode: CustomMode?, keepTerms: [String], engine: any InferenceEngine,
                                   progress: ProgressReporter?) async throws -> String {
        var failure = ""
        for greedy in [false, true] {
            let request = PromptBuilder.request(for: task, text: text, target: target, customMode: customMode,
                                                keepTerms: keepTerms, engine: engine.kind, greedy: greedy)
            var onPartial: PartialHandler?
            if let progress {
                onPartial = { progress.show(partial: OutputValidator.clean($0, input: text)) }
            }
            let raw = try await engine.generate(request, onPartial: onPartial)
            switch OutputValidator.validate(raw, input: text, task: task, target: target,
                                            allowsRewording: customMode != nil, requiredTerms: keepTerms) {
            case .valid(let text): return Glossary.applySpelling(keepTerms, to: text)
            case .invalid(let reason): failure = reason
            }
        }
        throw ProcessingError.validation(failure)
    }

    /// The finished part of the result plus the chunk being generated.
    final class ProgressReporter: @unchecked Sendable {
        private let lock = NSLock()
        private var done: String
        private let handler: PartialHandler

        init(prefix: String, handler: @escaping PartialHandler) {
            done = prefix
            self.handler = handler
        }

        func append(_ text: String) {
            guard !text.isEmpty else { return }
            handler(lock.withLock { done += text; return done })
        }

        func show(partial: String) {
            handler(lock.withLock { done + partial })
        }
    }

    static func splitOuterWhitespace(_ text: String) -> (String, String, String) {
        let core = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !core.isEmpty, let range = text.range(of: core) else { return (text, "", "") }
        return (String(text[..<range.lowerBound]), core, String(text[range.upperBound...]))
    }
}
