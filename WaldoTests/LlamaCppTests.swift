import Foundation
import Testing
@testable import Waldo

struct PromptFormatterTests {
    /// Expected output of Qwen3.5's chat_template.jinja with enable_thinking=false
    /// for one system and one user message (RESEARCH §9.2).
    @Test func qwen35MatchesOfficialTemplate() {
        let request = GenerationRequest(instructions: "  Be brief.\n", prompt: "\nHello\n", maxOutputTokens: 64, greedy: false)
        #expect(PromptFormatter.format(request, family: .qwen35) == """
            <|im_start|>system
            Be brief.<|im_end|>
            <|im_start|>user
            Hello<|im_end|>
            <|im_start|>assistant
            <think>

            </think>


            """)
    }
}

extension PromptFormatterTests {
    /// Earlier assistant turns have no think block; only the generation prompt does.
    @Test func qwen35RendersExamplesAsPriorTurns() {
        let request = GenerationRequest(instructions: "Fix it.", prompt: "b", maxOutputTokens: 64, greedy: false,
                                        examples: [FewShotExample(prompt: "a", reply: "A\n")])
        #expect(PromptFormatter.format(request, family: .qwen35) == """
            <|im_start|>system
            Fix it.<|im_end|>
            <|im_start|>user
            a<|im_end|>
            <|im_start|>assistant
            A<|im_end|>
            <|im_start|>user
            b<|im_end|>
            <|im_start|>assistant
            <think>

            </think>


            """)
    }
}

struct ModelCatalogTests {
    @Test func urlsArePinnedToACommit() {
        for model in ModelCatalog.all {
            #expect(model.revision.count == 40)
            #expect(model.sha256.count == 64)
            #expect(model.downloadURL.absoluteString.hasSuffix("/resolve/\(model.revision)/\(model.fileName)"))
        }
    }
}

/// Runs the real model end to end. Skipped unless the 4B model is downloaded.
/// Serialized: each test loads its own copy of the model, and three at once run out of memory.
@Suite(.serialized, .enabled(if: ModelCatalog.isInstalled(ModelCatalog.qwen35_4B)))
struct LlamaCppIntegrationTests {
    private static let email = """
        Hi Mark,

        I hope you are doing good. I write you because yesterday we was testing the new feature of competitions in staging and we find some problems that I want to comment you before the deploy.

        First, the endpoint /api/competitions/teams is returning duplicated teams when the cluster_id is null. I think the problem is in the query, because it dont filter correctly. I already make a fix in the branch fix/teams-duplicated but I need that somebody review it.

        Second, the page of results take a lot of time to charge, more or less 8 seconds. Actually we are not sure if is a problem of the backend or the frontend, so maybe we can make a call tomorrow for discuss it.

        Let me know if you have availability in the morning. If not, we can postpone the deploy for friday, I think is better than deploy with errors.

        Thanks you so much,
        Agustín
        """

    private func process(_ text: String, target: TargetLanguage) async throws -> ProcessingResult {
        let engine = LlamaCppEngine()
        await engine.configure(model: ModelCatalog.qwen35_4B, idleUnloadSeconds: 30)
        return try await TextProcessor().process(text, target: target, engines: [engine])
    }

    @Test func correctsEnglishEmail() async throws {
        let result = try await process(Self.email, target: .english)
        print("---- corrected ----\n\(result.text)\n-------------------")
        #expect(result.engine == .llamaCpp)
        #expect(result.text.contains("/api/competitions/teams"))
        #expect(result.text.contains("fix/teams-duplicated"))
        #expect(!result.text.contains("we was"))
        // Known miss of the 4B model: "Thanks you so much" usually survives.
        #expect(result.text.components(separatedBy: "\n").count == Self.email.components(separatedBy: "\n").count)
    }

    @Test func translatesSpanishToEnglish() async throws {
        let result = try await process("che, ¿me podés pasar el link del PR? @juan dice que ya está aprobado", target: .english)
        print("---- translated ----\n\(result.text)\n--------------------")
        #expect(result.text.contains("@juan"))
        #expect(result.text.localizedCaseInsensitiveContains("PR"))
    }

    /// Partials grow paragraph by paragraph and end at the validated result.
    @Test func streamsPartialResults() async throws {
        let engine = LlamaCppEngine()
        await engine.configure(model: ModelCatalog.qwen35_4B, idleUnloadSeconds: 30)
        let partials = Partials()
        let result = try await TextProcessor().process(Self.email, target: .english, engines: [engine]) {
            partials.append($0)
        }
        let seen = partials.all
        print("---- streamed \(seen.count) partials ----")
        #expect(seen.count > 50)
        #expect(seen.last == result.text.trimmingCharacters(in: .whitespacesAndNewlines))
        // Finished paragraphs never change while later ones are written.
        let firstParagraph = result.text.components(separatedBy: "\n\n")[0]
        #expect(seen.filter { $0.count > firstParagraph.count + 10 }.allSatisfy { $0.hasPrefix(firstParagraph) })
    }
}

private final class Partials: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    var all: [String] { lock.withLock { values } }
    func append(_ value: String) { lock.withLock { values.append(value) } }
}
