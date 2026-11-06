import AppKit
import Foundation
import Testing
@testable import Waldo

/// Chats end to end with the real model. Skipped unless the 4B model and its vision add-on are downloaded.
@Suite(.serialized, .enabled(if: ModelCatalog.isInstalled(ModelCatalog.qwen35_4B)
    && ModelCatalog.isInstalled(ModelCatalog.qwen35_4BVision)))
struct ChatIntegrationTests {
    @Test func explainsACaptureAndAnswersAFollowUp() async throws {
        let engine = LlamaCppEngine()
        await engine.configure(model: ModelCatalog.qwen35_4B, idleUnloadSeconds: 60)
        let image = try #require(ChatImage(Self.render("""
            $ swift build
            Sources/App/Store.swift:42:17: error: main actor-isolated property 'items'
            can not be mutated from a nonisolated context
                    self.items.append(item)
            """)))
        var conversation = ChatConversation(turns: [ChatTurn(question: ChatPrompts.firstQuestion, image: image)])
        let instructions = ChatPrompts.instructions(language: .spanish, conversation: ChatConversation())

        var start = ContinuousClock.now
        let first = try await engine.chat(conversation, instructions: instructions, onPartial: nil).text
        print("---- first answer (\(ContinuousClock.now - start)) ----\n\(first)")
        #expect(first.contains("items"))

        conversation.turns[0].answer = first
        conversation.turns.append(ChatTurn(question: "¿En qué línea está el error? Respondé solo el número."))
        start = .now
        let second = try await engine.chat(conversation, instructions: instructions, onPartial: nil).text
        let followUpTime = ContinuousClock.now - start
        print("---- follow-up (\(followUpTime)) ----\n\(second)")
        #expect(second.contains("42"))
        // The image and first answer stay in the context: no re-encoding.
        #expect(followUpTime < .seconds(4))
        await engine.endChat(conversation.id)
    }

    /// A question about the capture gets a direct answer: no greeting, no "I'm Waldo".
    @Test func answersTheQuestionDirectly() async throws {
        let engine = LlamaCppEngine()
        await engine.configure(model: ModelCatalog.qwen35_4B, idleUnloadSeconds: 60)
        let image = try #require(ChatImage(Self.render("""
            @devtools · 2h
            Zed 1.0 is out: native, written in Rust, with AI built in.
            Free for individuals. Pro plan: $20/month.
            """)))
        var conversation = ChatConversation(turns: [ChatTurn(question: "que dices, vale la pena usar zed?", image: image)])
        let instructions = ChatPrompts.instructions(language: .spanish, conversation: ChatConversation())
        for followUp in ["y comparado con cursor?", "cual me recomendas para empezar?"] {
            let answer = try await engine.chat(conversation, instructions: instructions, onPartial: nil).text
            print("---- turn \(conversation.turns.count) ----\n\(answer)")
            #expect(!answer.lowercased().contains("waldo"))
            #expect(!answer.lowercased().hasPrefix("¡hola") && !answer.lowercased().hasPrefix("hola"))
            conversation.turns[conversation.turns.count - 1].answer = answer
            conversation.turns.append(ChatTurn(question: followUp))
        }
        await engine.endChat(conversation.id)
    }

    /// Query, real DuckDuckGo search, answer with citations. Needs the network: WALDO_NETWORK=1.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WALDO_NETWORK"] != nil))
    func searchesTheWebAndCites() async throws {
        let engine = LlamaCppEngine()
        await engine.configure(model: ModelCatalog.qwen35_4B, idleUnloadSeconds: 60)
        let image = try #require(ChatImage(Self.render("""
            @devtools · 2h
            Cursor changed its plans again this month.
            """)))
        var conversation = ChatConversation(turns: [
            ChatTurn(question: "cuanto sale hoy el plan pro de cursor?", image: image, search: SearchStep()),
        ])
        let instructions = ChatPrompts.instructions(language: .spanish, conversation: ChatConversation())
        var start = ContinuousClock.now
        let rawQuery = try await engine.chat(conversation, instructions: instructions, onPartial: nil).text
        conversation.turns[0].search?.rawQuery = rawQuery
        let query = try #require(conversation.turns[0].search?.query)
        print("---- query (\(ContinuousClock.now - start)): \(query)")
        start = .now
        let results = try await WebSearch.search(query, provider: .duckDuckGo, searXNGURL: "")
        print("---- \(results.count) results (\(ContinuousClock.now - start))")
        results.forEach { print("  \($0.title) — \($0.url)") }
        conversation.turns[0].search?.results = results
        start = .now
        let answer = try await engine.chat(conversation, instructions: instructions, onPartial: nil).text
        print("---- answer (\(ContinuousClock.now - start)) ----\n\(answer)")
        #expect(!results.isEmpty)
        #expect(answer.range(of: #"\[\d\]"#, options: String.CompareOptions.regularExpression) != nil)
        await engine.endChat(conversation.id)
    }

    /// A text-only chat (no vision add-on involved), then a capture added mid-way:
    /// only the new turn with its image is read, the earlier context stays.
    @Test func chatsWithoutAnImageThenAddsOne() async throws {
        let engine = LlamaCppEngine()
        await engine.configure(model: ModelCatalog.qwen35_4B, idleUnloadSeconds: 60)
        let instructions = ChatPrompts.instructions(language: .spanish, conversation: ChatConversation())
        var conversation = ChatConversation(turns: [ChatTurn(question: "Mi perro se llama Toby. Respondé solo: ok.")])
        conversation.turns[0].answer = try await engine.chat(conversation, instructions: instructions, onPartial: nil).text
        print("---- text turn: \(conversation.turns[0].answer)")

        let image = try #require(ChatImage(Self.render("Order #8812 shipped on 2026-10-13 via DHL")))
        conversation.turns.append(ChatTurn(question: "¿Qué número de pedido aparece? ¿Y cómo se llama mi perro?", image: image))
        let start = ContinuousClock.now
        let answer = try await engine.chat(conversation, instructions: instructions, onPartial: nil).text
        print("---- with capture (\(ContinuousClock.now - start)) ----\n\(answer)")
        #expect(answer.contains("8812"))
        #expect(answer.contains("Toby"))
        await engine.endChat(conversation.id)
    }

    /// It knows it's Waldo when asked, and doesn't search the web for that.
    @Test func knowsWhoItIsWithoutSearching() async throws {
        let engine = LlamaCppEngine()
        await engine.configure(model: ModelCatalog.qwen35_4B, idleUnloadSeconds: 60)
        var conversation = ChatConversation(openedFrom: "Slack")
        conversation.turns = [ChatTurn(question: "quien eres?", search: SearchStep())]
        let instructions = ChatPrompts.instructions(language: .spanish, conversation: conversation)
        let rawQuery = try await engine.chat(conversation, instructions: instructions, onPartial: nil).text
        conversation.turns[0].search?.rawQuery = rawQuery
        print("---- query: \(rawQuery)")
        #expect(conversation.turns[0].search?.isSkipped == true)
        let answer = try await engine.chat(conversation, instructions: instructions, onPartial: nil).text
        print("---- answer: \(answer)")
        #expect(answer.contains("Waldo"))
        conversation.turns[0].answer = answer
        conversation.turns.append(ChatTurn(question: "ultimas noticias sobre el iphone 18", search: SearchStep()))
        let newsQuery = try await engine.chat(conversation, instructions: instructions, onPartial: nil).text
        print("---- news query: \(newsQuery)")
        conversation.turns[1].search?.rawQuery = newsQuery
        #expect(conversation.turns[1].search?.isSkipped == false)
        await engine.endChat(conversation.id)
    }

    /// Thinking writes its reasoning, closes it, then answers.
    @Test func thinksBeforeAnswering() async throws {
        let engine = LlamaCppEngine()
        await engine.configure(model: ModelCatalog.qwen35_4B, idleUnloadSeconds: 60)
        var conversation = ChatConversation(turns: [
            ChatTurn(question: "Tengo 3 cajas con 4 manzanas cada una y me como 5. ¿Cuántas quedan?", thinks: true),
        ])
        let start = ContinuousClock.now
        conversation.turns[0].answer = try await engine.chat(conversation, instructions: ChatPrompts.instructions(language: .spanish, conversation: ChatConversation()),
                                                             onPartial: nil).text
        let turn = conversation.turns[0]
        print("---- thinking (\(ContinuousClock.now - start)) ----\nREASONING: \(turn.reasoning ?? "")\nREPLY: \(turn.reply)")
        #expect(!(turn.reasoning ?? "").isEmpty)
        #expect(turn.reply.contains("7"))
        await engine.endChat(conversation.id)
    }

    /// Light text on a dark background, like a terminal.
    private static func render(_ text: String) -> CGImage {
        let size = NSSize(width: 760, height: 140)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor(white: 0.12, alpha: 1).setFill()
            rect.fill()
            (text as NSString).draw(at: NSPoint(x: 16, y: 20), withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: NSColor(white: 0.9, alpha: 1),
            ])
            return true
        }
        var rect = CGRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: NSAffineTransform(transform: .init(scale: 2))])!
    }
}

struct ChatFormattingTests {
    private static let image = ChatImage(CGImage.pixel)!

    private func prompt(_ turns: [ChatTurn]) -> (String, PromptFormatter.ChatStep) {
        PromptFormatter.chat(instructions: "Explain.", turns: turns, marker: "<m>", family: .qwen35)
    }

    @Test func imageGoesBeforeTheQuestion() {
        let (text, step) = prompt([ChatTurn(question: "Explain this.", image: Self.image)])
        #expect(step == .answer)
        #expect(text == """
            <|im_start|>system
            Explain.<|im_end|>
            <|im_start|>user
            <m>
            Explain this.<|im_end|>
            <|im_start|>assistant
            <think>

            </think>


            """)
    }

    @Test func selectedTextIsQuotedBeforeTheQuestion() {
        let (text, _) = prompt([ChatTurn(question: "What does it mean?", quote: "per se")])
        #expect(text.contains("<|im_start|>user\nSelected text:\n\"\"\"\nper se\n\"\"\"\n\nWhat does it mean?<|im_end|>"))
    }

    @Test func thinkingLeavesTheThinkBlockOpen() {
        let (text, _) = prompt([ChatTurn(question: "Hard one", thinks: true)])
        #expect(text.hasSuffix("<|im_start|>assistant\n<think>\n"))
        var turn = ChatTurn(question: "Hard one", thinks: true)
        turn.answer = "Let me see.\n12 - 5 = 7.\n</think>\n\nQuedan **7**."
        #expect(turn.reasoning == "Let me see.\n12 - 5 = 7.")
        #expect(turn.reply == "Quedan **7**.")
        turn.answer = "Still thinking"
        #expect(turn.reply.isEmpty)
    }

    /// Each step's prompt starts with the previous prompt plus what the model wrote,
    /// so the engine only decodes the rest instead of re-reading the images.
    @Test func everyStepContinuesThePreviousOne() {
        var turns = [ChatTurn(question: "Explain this.", image: Self.image)]
        let first = prompt(turns)
        turns[0].answer = "It's an error.\n"
        turns.append(ChatTurn(question: "Is it fixed in the latest version?", search: SearchStep()))
        let query = prompt(turns)
        #expect(query.1 == .searchQuery)
        #expect(query.0.hasPrefix(first.0 + "It's an error.\n<|im_end|>"))
        #expect(query.0.contains("Before answering, write the web search query"))

        turns[1].search?.rawQuery = "swift main actor error fix"
        turns[1].search?.results = [SearchResult(title: "Swift docs", url: URL(string: "https://swift.org")!, snippet: "Use await.")]
        let answer = prompt(turns)
        #expect(answer.1 == .answer)
        #expect(answer.0.hasPrefix(query.0 + "swift main actor error fix<|im_end|>"))
        #expect(answer.0.contains("[1] Swift docs\nhttps://swift.org\nUse await."))

        turns[1].answer = "Yes [1]."
        turns.append(ChatTurn(question: "And this one?", image: Self.image, thinks: true))
        let third = prompt(turns)
        #expect(third.0.hasPrefix(answer.0 + "Yes [1].<|im_end|>"))
        #expect(third.0.components(separatedBy: "<m>").count == 3)
    }

    @Test func searchQueryIsCleanedUp() {
        #expect(SearchStep(rawQuery: " \"cursor pro plan price 2026\" ").query == "cursor pro plan price 2026")
        #expect(SearchStep(rawQuery: "Search query: zed vs cursor").query == "zed vs cursor")
        #expect(SearchStep(rawQuery: "error: main actor").query == "error: main actor")
    }

    @Test func failedSearchIsToldToTheModel() {
        let text = ChatPrompts.searchResults(SearchStep(rawQuery: "x", failure: "offline"))
        #expect(text.hasPrefix("The web search failed (offline)."))
    }

    @Test func citationsBecomeLinks() {
        let sources = [URL(string: "https://a.com")!, URL(string: "https://b.com/x")!]
        #expect(MarkdownText.linkingCitations(in: "Yes [1], and [2][3].", to: sources)
            == "Yes [[1]](https://a.com), and [[2]](https://b.com/x)[3].")
        #expect(MarkdownText.linkingCitations(in: "See [1].", to: []) == "See [1].")
    }

    /// Two results as DuckDuckGo's HTML page returned them (2026-10-14), plus an ad and a redirect link.
    @Test func parsesDuckDuckGoResults() {
        let html = """
            <div class="serp__results"><div class="result results_links results_links_deep result--ad ">
              <a rel="nofollow" class="result__a" href="https://ad.example/">Ad</a></div>
            <div class="result results_links results_links_deep web-result ">
              <h2 class="result__title">
                <a rel="nofollow" class="result__a" href="https://cursor.com/pricing">Cursor · Pricing</a>
              </h2>
              <a class="result__snippet" href="https://cursor.com/pricing">Is the Grok API included in my <b>plan</b>? \
            ↓ Paid <b>plans</b> include Grok API access and doesn&#x27;t draw from your <b>plan&#x27;s</b> pool.</a>
            </div>
            <div class="result results_links results_links_deep web-result ">
              <a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fa%3Fb%3D1&amp;rut=x">A &amp; B</a>
            </div></div>
            """
        let results = WebSearch.parseDuckDuckGo(html)
        #expect(results.map(\.url.absoluteString) == ["https://cursor.com/pricing", "https://example.com/a?b=1"])
        #expect(results.first?.title == "Cursor · Pricing")
        #expect(results.first?.snippet == "Is the Grok API included in my plan? ↓ Paid plans include Grok API access and doesn't draw from your plan's pool.")
        #expect(results.last?.title == "A & B")
        #expect(results.last?.snippet == "")
    }

    @Test func projectorsArePinnedAndNamedAfterTheirModel() {
        for model in ModelCatalog.all {
            let vision = try? #require(ModelCatalog.vision(for: model))
            #expect(vision?.revision == model.revision)
            #expect(vision?.downloadURL.absoluteString.hasSuffix("/resolve/\(model.revision)/mmproj-F16.gguf") == true)
            #expect(vision?.fileName != "mmproj-F16.gguf")
        }
    }

    @Test func markdownBlocks() {
        let blocks = MarkdownText.parse("""
            **Title** line
            - one
              * two

            ## Heading
            ```swift
            let x = 1
            ```
            after
            ```
            unclosed
            """)
        #expect(blocks == [
            .paragraph("**Title** line\n•  one\n  •  two"),
            .heading("Heading"),
            .code("let x = 1"),
            .paragraph("after"),
            .code("unclosed"),
        ])
    }
}

private extension CGImage {
    /// A 1×1 image, for prompts that only need an image to be there.
    static var pixel: CGImage {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        return context.makeImage()!
    }
}

struct ChatStoreTests {
    private func temporaryStore() -> ChatStore {
        ChatStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("waldo-test-\(UUID().uuidString)"))
    }

    /// Chats load without their captures; opening one loads them from the PNGs.
    @Test func savesChatsAndLoadsCapturesOnDemand() throws {
        let store = temporaryStore()
        defer { store.deleteAll() }
        let image = try #require(ChatImage(CGImage.pixel))
        var chat = ChatConversation(openedFrom: "Slack")
        chat.title = "A chat"
        chat.turns = [ChatTurn(question: "Explain this.", answer: "It's a pixel.", image: image,
                               search: SearchStep(rawQuery: "pixel", results: []), thinks: true)]
        store.save(chat)

        let loaded = try #require(store.loadAll().first)
        #expect(loaded.id == chat.id && loaded.title == "A chat" && loaded.openedFrom == "Slack")
        #expect(loaded.turns[0].hasImage && loaded.turns[0].image == nil && !loaded.hasAllImages)
        #expect(loaded.turns[0].search?.rawQuery == "pixel" && loaded.turns[0].thinks)
        let opened = store.loadImages(of: loaded)
        #expect(opened.hasAllImages)
        #expect(opened.turns[0].image?.id == image.id && opened.turns[0].image?.width == 1)

        store.delete(chat.id)
        #expect(store.loadAll().isEmpty)
    }

    @Test func unloadingKeepsTheReference() throws {
        var turn = ChatTurn(question: "q", image: ChatImage(CGImage.pixel))
        turn.unloadImage()
        #expect(turn.hasImage && turn.image == nil)
    }

    @Test func groupsByDate() {
        let now = Date()
        func chat(daysAgo: Double) -> ChatConversation {
            var chat = ChatConversation()
            chat.updatedAt = now.addingTimeInterval(-daysAgo * 86_400)
            return chat
        }
        let groups = ChatGroup.groups(for: [chat(daysAgo: 0), chat(daysAgo: 1), chat(daysAgo: 3), chat(daysAgo: 30)], now: now)
        #expect(groups.map(\.title) == ["Today", "Yesterday", "Previous 7 days", "Older"])
    }

    @Test func untitledChatsAreNamedAfterTheirFirstMessage() {
        var chat = ChatConversation()
        #expect(chat.displayTitle == "New chat")
        chat.turns = [ChatTurn(question: "Explain this.", quote: "per se")]
        #expect(chat.displayTitle == "per se")
        chat.title = "Latin phrases"
        #expect(chat.displayTitle == "Latin phrases")
    }
}

struct ChatTurnDecodingTests {
    @Test func aChatSavedBeforeCutAnswersExistedStillOpens() throws {
        let json = #"{"question":"Hi","answer":"Hello","thinks":false}"#
        let turn = try JSONDecoder().decode(ChatTurn.self, from: Data(json.utf8))
        #expect(turn.wasCut == nil)
    }

    @Test func aCutAnswerStaysMarkedAfterSaving() throws {
        var turn = ChatTurn(question: "Hi", answer: "Hel")
        turn.wasCut = true
        let saved = try JSONDecoder().decode(ChatTurn.self, from: JSONEncoder().encode(turn))
        #expect(saved.wasCut == true)
    }
}
