import Foundation
import Testing
@testable import Waldo

struct LongTextTests {
    private static let sentence = "We tested the new dashboard yesterday and found a few problems with the export. "

    @Test func splitsLongParagraphsAtLineBreaks() {
        let lines = (1...8).map { "Line \($0): " + Self.sentence.trimmingCharacters(in: .whitespaces) }
        let text = lines.joined(separator: "\n")
        let pieces = TextProcessor.chunks(text)
        #expect(pieces.map(\.text).joined() == text)
        #expect(pieces.filter { !$0.isSeparator }.count > 1)
        #expect(pieces.filter { !$0.isSeparator }.allSatisfy { $0.text.count <= TextProcessor.chunkCharacters })
        #expect(pieces.filter(\.isSeparator).allSatisfy { $0.text == "\n" })
    }

    @Test func splitsLongLinesAtSentences() {
        let text = String(repeating: Self.sentence, count: 12).trimmingCharacters(in: .whitespaces)
        let pieces = TextProcessor.chunks(text)
        #expect(pieces.map(\.text).joined() == text)
        #expect(pieces.filter { !$0.isSeparator }.count > 1)
        #expect(pieces.filter { !$0.isSeparator }.allSatisfy { $0.text.count <= TextProcessor.chunkCharacters })
    }

    @Test func shortTextStaysWhole() {
        #expect(TextProcessor.chunks("one line\ntwo lines").map(\.text) == ["one line\ntwo lines"])
    }

    @Test func aFailingPartKeepsItsTextAndTheRestGoesThrough() async throws {
        let first = String(repeating: "this are the first paragraph. ", count: 10).trimmingCharacters(in: .whitespaces)
        let second = String(repeating: "this are BREAK paragraph. ", count: 10).trimmingCharacters(in: .whitespaces)
        let result = try await TextProcessor().process(first + "\n\n" + second, target: .english, engines: [FakeEngine()])
        #expect(result.keptParts == 1)
        #expect(result.text == first.replacingOccurrences(of: "this are", with: "these are") + "\n\n" + second)
        #expect(result.summary.hasSuffix("1 part was left as you wrote it."))
    }

    @Test func failsWhenEveryPartFails() async {
        await #expect(throws: ProcessingError.self) {
            try await TextProcessor().process("this are BREAK", target: .english, engines: [FakeEngine()])
        }
    }
}

/// Fixes "this are" in the text it's sent, and returns nothing for text containing BREAK.
private struct FakeEngine: InferenceEngine {
    let kind = EngineKind.llamaCpp
    func availability() async -> EngineAvailability { .available }
    func generate(_ request: GenerationRequest, onPartial: PartialHandler?) async throws -> String {
        guard let start = request.prompt.range(of: "<text>\n"), let end = request.prompt.range(of: "\n</text>") else { return "" }
        let text = String(request.prompt[start.upperBound..<end.lowerBound])
        return text.contains("BREAK") ? "" : text.replacingOccurrences(of: "this are", with: "these are")
    }
}
