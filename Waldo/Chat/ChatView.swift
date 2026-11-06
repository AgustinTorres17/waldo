import AppKit
import KeyboardShortcuts
import SwiftUI

/// The chat on the right of Waldo's window: its title, the conversation (or a
/// welcome when it's new), and the composer.
struct ChatScreen: View {
    @ObservedObject var library: ChatLibrary
    @ObservedObject var settings: SettingsStore
    /// Takes a capture for the next message (true: the whole screen).
    let onCapture: (Bool) -> Void

    static let columnWidth: CGFloat = 720

    var body: some View {
        let chat = library.current
        VStack(spacing: 0) {
            header(chat)
            SettingsDivider()
            Group {
                if !chat.turns.isEmpty {
                    ChatTranscript(turns: turns(of: chat), phase: library.currentPhase,
                                   onCopy: { ClipboardService.writeString($0) })
                } else if let image = library.pendingImage {
                    CapturePreview(image: image.preview)
                        .frame(maxWidth: Self.columnWidth, maxHeight: .infinity)
                        .padding(.horizontal, 24)
                } else {
                    Welcome(onCapture: onCapture)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Composer(library: library, settings: settings, onCapture: { onCapture(false) })
                .frame(maxWidth: Self.columnWidth)
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .surface(.window)
    }

    /// The chat's turns, the one being answered with its text so far.
    private func turns(of chat: ChatConversation) -> [ChatTurn] {
        var turns = chat.turns
        if library.runningID == chat.id, let live = library.liveAnswer, !turns.isEmpty {
            turns[turns.count - 1].answer = live
        }
        return turns
    }

    private func header(_ chat: ChatConversation) -> some View {
        HStack(spacing: 8) {
            Text(chat.displayTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            if let status {
                Text(status)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
        .background(WindowDragArea())
    }

    private var status: String? {
        switch library.currentPhase {
        case .searching(nil): "Thinking of a search…"
        case .searching(let query?): "Searching the web for “\(query)”…"
        case .reading: library.current.turns.last?.hasImage == true ? "Reading your capture…" : "Reading…"
        case .thinking: "Thinking…"
        case .writing: "Writing…"
        case .asking, .done, .error: nil
        }
    }
}

/// A new chat's empty state: what Waldo can do, with the shortcuts.
private struct Welcome: View {
    let onCapture: (Bool) -> Void

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Text("How can I help?")
                    .font(Theme.display(26, weight: Theme.current == .editorial ? .regular : .bold))
                    .foregroundStyle(Theme.text)
                Text("Waldo runs on this Mac. Nothing you write leaves it, unless you turn on web search.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.secondaryText)
            }
            VStack(spacing: 8) {
                action("Capture a region", detail: "Drag over anything on screen and ask about it",
                       icon: "rectangle.dashed", shortcut: .explainScreen) { onCapture(false) }
                action("Capture the whole screen", detail: "The screen under the mouse, right away",
                       icon: "macwindow", shortcut: .explainWholeScreen) { onCapture(true) }
                hint("Ask about selected text", detail: "Select text in any app and click Ask in Waldo's popup",
                     icon: "text.cursor")
            }
            .frame(width: 420)
        }
        .padding(24)
    }

    private func action(_ title: String, detail: String, icon: String, shortcut: KeyboardShortcuts.Name,
                        perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            row(title, detail: detail, icon: icon) {
                if let keys = KeyboardShortcuts.getShortcut(for: shortcut)?.description { KeyCap(keys) }
            }
        }
        .buttonStyle(WelcomeRowStyle())
    }

    private func hint(_ title: String, detail: String, icon: String) -> some View {
        row(title, detail: detail, icon: icon) { EmptyView() }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
    }

    private func row<Trailing: View>(_ title: String, detail: String, icon: String,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Theme.accentFill)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

private struct WelcomeRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(configuration.isPressed ? Theme.pressed : isHovered ? Theme.hover : Theme.card,
                            in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.divider))
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }
    }
}

/// The message box: what's attached, the text, and the capture, web search
/// and thinking toggles. Return sends, Option-Return starts a new line.
private struct Composer: View {
    @ObservedObject var library: ChatLibrary
    @ObservedObject var settings: SettingsStore
    let onCapture: () -> Void
    @State private var textHeight: CGFloat = 18
    @State private var pasteMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if library.pendingQuote != nil || (library.pendingImage != nil && !library.current.turns.isEmpty) {
                attachments
            }
            ComposerTextField(text: $library.draft, height: $textHeight, focusID: library.current.id,
                              onSubmit: library.send)
                .frame(height: textHeight)
                .overlay(alignment: .topLeading) {
                    if library.draft.isEmpty {
                        Text(placeholder)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.tertiaryText)
                            .allowsHitTesting(false)
                    }
                }
            HStack(spacing: 2) {
                Button(action: onCapture) {
                    Image(systemName: "camera.viewfinder")
                        .foregroundStyle(library.pendingImage != nil ? AnyShapeStyle(Theme.accentFill) : AnyShapeStyle(Theme.secondaryText))
                }
                .buttonStyle(.icon)
                .help("Add a capture of your screen to the next message")
                Button(action: library.chooseImage) {
                    Image(systemName: "paperclip")
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.icon)
                .help("Add an image from your Mac. You can also paste one.")
                toggle($settings.chatSearchesWeb, icon: "globe", title: "Search",
                       on: "Searching the web is on: only the search query leaves your Mac. Click to turn it off.",
                       off: "Search the web before answering")
                toggle($settings.chatThinks, icon: "brain", title: "Think",
                       on: "Thinking is on: slower (up to a minute), better on hard questions. Click to turn it off.",
                       off: "Think before answering (slower, better on hard questions)")
                Spacer(minLength: 8)
                if library.runningID == library.current.id {
                    Button(action: library.cancelRun) {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.monoSecondary)
                    .help("Stop")
                } else {
                    Button(action: library.send) {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.monoPrimary)
                    .disabled(!canSend)
                    .help(library.isRunning ? "Waldo is answering in another chat" : "Send")
                }
            }
        }
        .padding(12)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border))
        .shadow(color: .black.opacity(Theme.isGlass ? 0.06 : 0), radius: 6, y: 2)
        .onAppear(perform: startWatchingPaste)
        .onDisappear(perform: stopWatchingPaste)
    }

    /// A text field ignores a pasted image, so ⌘V is looked at before it gets there.
    private func startWatchingPaste() {
        guard pasteMonitor == nil else { return }
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [library] event in
            let isPaste = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
                && event.charactersIgnoringModifiers?.lowercased() == "v"
            guard isPaste, event.window is MainWindow else { return event }
            let pasted = MainActor.assumeIsolated { library.pasteImage() }
            return pasted ? nil : event
        }
    }

    private func stopWatchingPaste() {
        if let pasteMonitor { NSEvent.removeMonitor(pasteMonitor) }
        pasteMonitor = nil
    }

    private var canSend: Bool {
        !library.isRunning && (library.hasAttachment || !library.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var placeholder: String {
        if library.hasAttachment && library.current.turns.isEmpty { return "Ask about it… (Return alone explains it)" }
        return library.current.turns.isEmpty ? "Ask anything…" : "Ask a follow-up…"
    }

    private func toggle(_ isOn: Binding<Bool>, icon: String, title: String, on: String, off: String) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(title).font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(isOn.wrappedValue ? AnyShapeStyle(Theme.accentFill) : AnyShapeStyle(Theme.secondaryText))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(isOn.wrappedValue ? Theme.accentSoft : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isOn.wrappedValue ? on : off)
    }

    /// What goes with the next message, each removable.
    private var attachments: some View {
        HStack(alignment: .top, spacing: 8) {
            if let image = library.pendingImage {
                AttachmentChip(onRemove: { library.pendingImage = nil }) {
                    Image(nsImage: NSImage(cgImage: image.preview, size: .zero))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 54, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            if let quote = library.pendingQuote {
                AttachmentChip(onRemove: { library.pendingQuote = nil }) {
                    Text(quote)
                        .font(.system(size: 11.5))
                        .italic()
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// An attachment of the next message, with a button to remove it.
private struct AttachmentChip<Content: View>: View {
    let onRemove: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            content
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.icon)
            .help("Remove")
        }
        .padding(.leading, 6)
        .padding(.vertical, 4)
        .background(Theme.control, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.border))
    }
}

/// The conversation, in a centered column. While an answer is written it
/// follows the end, unless the user scrolls up to read.
private struct ChatTranscript: View {
    let turns: [ChatTurn]
    let phase: ChatLibrary.Phase
    let onCopy: (String) -> Void

    @State private var followsText = true
    @State private var scrollMonitor: Any?
    private static let end = "end"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(turns.enumerated()), id: \.offset) { index, turn in
                        let isLast = index == turns.count - 1
                        UserMessage(turn: turn)
                        if let search = turn.search, search.rawQuery != nil, !search.isSkipped {
                            SearchLine(search: search)
                        }
                        if let reasoning = turn.reasoning, !reasoning.isEmpty {
                            Reasoning(text: reasoning, isActive: isLast && phase == .thinking)
                        }
                        if !turn.reply.isEmpty {
                            MarkdownText(turn.reply, sources: turn.search?.results?.map(\.url) ?? [])
                        }
                        if let results = turn.search?.results, !results.isEmpty, !turn.reply.isEmpty {
                            SourceList(results: results)
                        }
                        if !turn.reply.isEmpty, !(isLast && phase == .writing) {
                            Button { onCopy(turn.reply) } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.tertiaryText)
                            .help("Copy this answer")
                        }
                    }
                    if let waiting {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small).scaleEffect(0.8)
                            Text(waiting)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    if case .error(let message) = phase {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Color.clear.frame(height: 1).id(Self.end)
                }
                .frame(maxWidth: ChatScreen.columnWidth)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
            .onAppear { proxy.scrollTo(Self.end, anchor: .bottom) }
            .onChange(of: turns) { _ in
                if followsText { proxy.scrollTo(Self.end, anchor: .bottom) }
            }
            .onChange(of: turns.count) { _ in
                followsText = true // a new question follows its answer again
            }
        }
        .onAppear(perform: watchScrolling)
        .onDisappear {
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
            scrollMonitor = nil
        }
    }

    private var waiting: String? {
        switch phase {
        case .searching(nil): "Thinking of a search…"
        case .searching(let query?): "Searching the web for “\(query)”…"
        case .reading: turns.last?.hasImage == true ? "Reading your capture…" : "Reading…"
        case .thinking where (turns.last?.reasoning ?? "").isEmpty: "Thinking…"
        default: nil
        }
    }

    /// Scrolling up stops following the text; scrolling back down resumes.
    private func watchScrolling() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            if event.window is MainWindow, event.scrollingDeltaY > 0 { followsText = false }
            return event
        }
    }
}

/// The user's message on the right: its capture, the text it's about, the question.
private struct UserMessage: View {
    let turn: ChatTurn

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let image = turn.image {
                Image(nsImage: NSImage(cgImage: image.preview, size: .zero))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 200, maxHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.border))
            }
            if let quote = turn.quote {
                Text(quote)
                    .font(.system(size: 12))
                    .italic()
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(4)
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.divider).frame(width: 2) }
                    .frame(maxWidth: 360, alignment: .trailing)
            }
            if turn.question != ChatPrompts.firstQuestion {
                Text(turn.question)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// The model's reasoning, folded unless opened; the last lines show while it thinks.
private struct Reasoning: View {
    let text: String
    let isActive: Bool
    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { isOpen.toggle() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "brain")
                    Text(isActive ? "Thinking…" : "Reasoning")
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen || isActive {
                Text(isOpen ? text : Self.lastLines(of: text))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.divider).frame(width: 2) }
                    .textSelection(.enabled)
            }
        }
    }

    private static func lastLines(of text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: true).suffix(3).joined(separator: "\n")
    }
}

/// What the model searched for, or why the search didn't work.
private struct SearchLine: View {
    let search: SearchStep

    var body: some View {
        Label {
            if let failure = search.failure {
                Text("Search didn't work: \(failure)")
            } else {
                Text("Searched the web for “\(search.query)”")
            }
        } icon: {
            Image(systemName: search.failure == nil ? "globe" : "exclamationmark.triangle")
        }
        .font(.system(size: 11.5))
        .foregroundStyle(search.failure == nil ? Theme.secondaryText : Theme.danger)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The results an answer could cite, numbered like its citations.
private struct SourceList: View {
    let results: [SearchResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sources")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                Link(destination: result.url) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(index + 1)")
                            .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 14, alignment: .trailing)
                        Text(result.title)
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Text(result.url.host ?? "")
                            .foregroundStyle(Theme.tertiaryText)
                            .lineLimit(1)
                            .layoutPriority(-1)
                    }
                    .font(.system(size: 11.5))
                }
                .buttonStyle(.plain)
                .help(result.url.absoluteString)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fieldBox()
    }
}

/// The capture, large, while the panel waits for the first question.
private struct CapturePreview: View {
    let image: CGImage

    var body: some View {
        Image(nsImage: NSImage(cgImage: image, size: .zero))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: 240)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border))
            .padding(12)
    }
}

/// The subset of Markdown the model writes: headings, bold/italic/code inline,
/// lists and fenced code blocks. An unclosed fence (still being written) is code.
struct MarkdownText: View {
    private let blocks: [Block]
    /// Web results the text cites as [1], [2]…: those become links.
    private let sources: [URL]

    init(_ text: String, sources: [URL] = []) {
        blocks = Self.parse(text)
        self.sources = sources
    }

    enum Block: Hashable, Sendable {
        case heading(String)
        case paragraph(String)
        case code(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let text):
                    Text(inline(text))
                        .font(.system(size: 13.5, weight: .semibold))
                        .padding(.top, 2)
                case .paragraph(let text):
                    Text(inline(text))
                        .font(Theme.resultFont)
                        .lineSpacing(3)
                case .code(let text):
                    Text(text)
                        .font(.system(size: 12, design: .monospaced))
                        .lineSpacing(2)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fieldBox()
                }
            }
        }
        .foregroundStyle(Theme.text)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let linked = Self.linkingCitations(in: text, to: sources)
        return (try? AttributedString(markdown: linked, options: options)) ?? AttributedString(text)
    }

    /// "[2]" becomes a Markdown link to the second source; numbers without a source stay text.
    nonisolated static func linkingCitations(in text: String, to sources: [URL]) -> String {
        guard !sources.isEmpty else { return text }
        let pattern = try! NSRegularExpression(pattern: #"\[(\d{1,2})\](?!\()"#)
        var result = text
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: result), let digits = Range(match.range(at: 1), in: result),
                  let number = Int(result[digits]), sources.indices.contains(number - 1) else { continue }
            result.replaceSubrange(whole, with: "[[\(number)]](\(sources[number - 1].absoluteString))")
        }
        return result
    }

    nonisolated static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String]?

        func flushParagraph() {
            let joined = paragraph.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
            paragraph = []
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let lines = code {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    flushParagraph()
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(line)
            } else if trimmed.hasPrefix("#") {
                flushParagraph()
                blocks.append(.heading(String(trimmed.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
            } else if trimmed.isEmpty || trimmed == "---" {
                flushParagraph()
            } else {
                paragraph.append(bullet(line))
            }
        }
        if let lines = code, !lines.isEmpty { blocks.append(.code(lines.joined(separator: "\n"))) }
        flushParagraph()
        return blocks
    }

    /// "- item" and "* item" become "• item", keeping the indentation.
    private nonisolated static func bullet(_ line: String) -> String {
        let indent = line.prefix { $0 == " " }
        let rest = line.dropFirst(indent.count)
        guard rest.hasPrefix("- ") || rest.hasPrefix("* ") else { return line }
        return String(indent) + "•  " + rest.dropFirst(2)
    }
}
