import CoreGraphics
import Foundation

/// A screen capture: the pixels as the vision projector wants them (8-bit RGB,
/// row by row) and the image itself for previews.
struct ChatImage: @unchecked Sendable, Equatable { // CGImage is immutable
    let id: UUID
    let width: Int
    let height: Int
    let rgb: [UInt8]
    let preview: CGImage

    static func == (lhs: ChatImage, rhs: ChatImage) -> Bool { lhs.id == rhs.id }

    init?(_ image: CGImage, id: UUID = UUID()) {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var rgb = [UInt8](repeating: 0, count: width * height * 3)
        for pixel in 0..<(width * height) {
            rgb[pixel * 3] = rgba[pixel * 4]
            rgb[pixel * 3 + 1] = rgba[pixel * 4 + 1]
            rgb[pixel * 3 + 2] = rgba[pixel * 4 + 2]
        }
        self.id = id
        self.width = width
        self.height = height
        self.rgb = rgb
        preview = image
    }
}

/// One question and its answer (empty while unanswered). Answers are kept
/// exactly as generated, reasoning included: they're in the model's context as is.
struct ChatTurn: Sendable, Equatable, Codable {
    var question: String
    var answer: String
    /// A capture sent with the question. Saved apart as a PNG (`imageID`) and
    /// loaded when the chat is opened.
    var image: ChatImage? {
        didSet { imageID = image?.id }
    }
    private(set) var imageID: UUID?
    /// Text the user selected and asked about (the popup's Ask).
    var quote: String?
    /// Set when the question is answered with a web search first.
    var search: SearchStep?
    /// Qwen3.5 reasons before answering: slower, better on hard questions.
    var thinks: Bool

    init(question: String, answer: String = "", image: ChatImage? = nil, quote: String? = nil,
         search: SearchStep? = nil, thinks: Bool = false) {
        self.question = question
        self.answer = answer
        self.image = image
        imageID = image?.id
        self.quote = quote
        self.search = search
        self.thinks = thinks
    }

    private enum CodingKeys: String, CodingKey {
        case question, answer, imageID, quote, search, thinks
    }

    /// Has a capture, loaded or not.
    var hasImage: Bool { imageID != nil }

    /// Frees the capture's pixels; it loads again from disk when needed.
    mutating func unloadImage() {
        let id = imageID
        image = nil
        imageID = id
    }

    /// The reasoning of a thinking answer (also while it's still being written).
    var reasoning: String? {
        guard thinks else { return nil }
        let text = answer.components(separatedBy: "</think>").first ?? answer
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The answer without its reasoning; empty while the model still thinks.
    var reply: String {
        guard thinks else { return answer }
        guard let end = answer.range(of: "</think>") else { return "" }
        return String(answer[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A web search inside a turn: the model writes a query, Waldo searches, the
/// model answers from the results.
struct SearchStep: Sendable, Equatable, Codable {
    /// The model's reply when asked for a query, exactly; nil until it writes one.
    var rawQuery: String?
    var results: [SearchResult]?
    /// Why the search didn't run, told to the model so it says so.
    var failure: String?
    /// Fixed when searched, so a rebuilt prompt reads the same.
    var date = Date()

    /// The model said the question doesn't need the web.
    var isSkipped: Bool { query.uppercased() == "NONE" }

    /// The query to send: one line, no quotes or label.
    var query: String {
        var query = (rawQuery ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let colon = query.firstIndex(of: ":"), query[..<colon].lowercased().contains("query") {
            query = String(query[query.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        return query.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”«»`"))
    }
}

/// The questions asked so far, with what came with them. The engine answers the last turn.
struct ChatConversation: Sendable, Identifiable, Codable {
    var id = UUID()
    var turns: [ChatTurn] = []
    /// Fixed when the chat starts, so its instructions read the same all along
    /// (the engine only decodes what's new while the prompt starts the same).
    var startedAt = Date()
    /// The app in front when the chat was opened.
    var openedFrom: String?
    /// Written by the model after the first answer, or by the user.
    var title: String?
    var updatedAt = Date()

    /// The sidebar's name for it.
    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        guard let first = turns.first else { return "New chat" }
        let text = first.question == ChatPrompts.firstQuestion ? (first.quote ?? "Capture") : first.question
        return String(text.prefix(48))
    }

    /// Every capture is loaded (an opened chat).
    var hasAllImages: Bool { turns.allSatisfy { !$0.hasImage || $0.image != nil } }
}

enum ChatError: LocalizedError {
    case noVisionModel(String)
    case conversationTooLong

    var errorDescription: String? {
        switch self {
        case .noVisionModel(let reason): reason
        case .conversationTooLong: "This chat is too long for the model's memory. Start a new one to keep going."
        }
    }
}

enum ChatPrompts {
    /// The question sent when a capture is sent without one.
    static let firstQuestion = "Explain this."

    /// Appended to a question that is answered with a web search. The model's own
    /// sense of "now" is its training date, so it gets today's.
    static func queryRequest(_ step: SearchStep) -> String {
        "Before answering, write the web search query that would find what you need for this. Today is \(day(step.date)): " +
            "only put a year in the query if the question is about a specific one. Reply with only the query, on one line. " +
            "If the answer doesn't need the web (a question about you, about this conversation, or only about the capture " +
            "or the selected text), reply with only NONE."
    }

    private static func day(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day())
    }

    /// The results (or why there are none) and the request to answer from them.
    static func searchResults(_ step: SearchStep) -> String {
        let today = day(step.date)
        let header: String
        if step.isSkipped {
            return "OK, no search. Now answer my question."
        } else if let failure = step.failure {
            header = "The web search failed (\(failure))."
        } else if let results = step.results, !results.isEmpty {
            let list = results.enumerated().map { index, result in
                "[\(index + 1)] \(result.title)\n\(result.url.absoluteString)\n\(result.snippet)"
            }
            header = "Web search results for \"\(step.query)\" (today is \(today)):\n\n" + list.joined(separator: "\n\n")
        } else {
            header = "The web search for \"\(step.query)\" found nothing."
        }
        return header + """


            Now answer my question. Use the results for anything they cover and cite them as [1], [2] right after \
            the facts they support; they are newer than what you know. If they don't answer it, say so, then answer \
            from your own knowledge and say that part isn't from the search.
            """
    }

    static func titleInstructions(language: TargetLanguage) -> String {
        """
        Write a short title (3 to 6 words) for a chat that starts with the message below. Write it in \
        \(language.instructionName), unless the user's message is clearly in another language: then in that one. \
        Reply with only the title: no quotes, no period, no "Title:".
        """
    }

    static func titlePrompt(for turn: ChatTurn) -> String {
        var message = turn.question
        if let quote = turn.quote { message = "About this text: \(quote.prefix(300))\n\(message)" }
        if turn.hasImage { message = "(with a screen capture) " + message }
        return "User: \(message)\n\nAssistant: \(turn.reply.prefix(600))"
    }

    static func instructions(language: TargetLanguage, conversation: ChatConversation) -> String {
        let opened = conversation.openedFrom.map { " They opened this chat while using \($0)." } ?? ""
        return """
        You are Waldo, an assistant in the menu bar of the user's Mac. You run entirely on their Mac (an open \
        Qwen3.5 model), so nothing they write leaves it, except web searches they turn on with the globe button. \
        Besides this chat, Waldo corrects, translates and rephrases text in any app, and explains captures of the screen. \
        Don't introduce yourself or say your name unless they ask who you are or what you can do.

        Today is \(day(conversation.startedAt)).\(opened) A message may come with a capture of their screen \
        (an image: an error, code, a chart, a document, a post, a part of an app…) or with text they selected; \
        their question is then about it.

        Answer the question directly in your first sentence, then give the details that support it. \
        No greeting, no introduction, don't say who you are, don't repeat the question. \
        When the question is just "Explain this.", say what it is in one sentence, then explain what it means, \
        and end with what the user can do about it when that applies.

        Be accurate:
        - Quote text from images and selections exactly. If part of an image is cut off, blurry or ambiguous, \
        say so instead of guessing.
        - Only say "the image shows" for things that are actually in it. Knowledge of your own is fine, \
        but present it as yours, and say when it may be outdated.
        - For opinions or decisions, give the main pros and cons and what the answer depends on, not a sales pitch.
        - Never invent APIs, attributes, commands, prices or features; say when you're not sure.

        Use bold, short lists and code blocks where they help; keep it as long as the question needs, no padding.

        Answer in \(language.instructionName), unless the user writes in another language: then answer in that language.
        """
    }
}
