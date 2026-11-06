import AppKit
import os
import SwiftUI

/// The chats in Waldo's window: the saved ones, the one on screen, what's
/// attached to the next message, and the answer being written (one at a time).
/// Nothing runs until the user sends something.
@MainActor
final class ChatLibrary: ObservableObject {
    enum Phase: Equatable {
        /// Waiting for the user's message.
        case asking
        /// Writing a search query (nil) or searching for it.
        case searching(String?)
        /// The message (and its capture) is being read; nothing written yet.
        case reading
        /// Reasoning before the answer (thinking on).
        case thinking
        case writing
        case done
        case error(String)
    }

    /// Saved chats, most recently updated first.
    @Published private(set) var chats: [ChatConversation] = []
    /// The chat on screen; nil for a new one, which is saved once it has a message.
    @Published private(set) var selectedID: UUID?
    @Published private(set) var newChat = ChatConversation()
    @Published var searchText = ""
    @Published var draft = ""
    /// Sent with the next message.
    @Published var pendingImage: ChatImage?
    @Published var pendingQuote: String?
    /// The chat an answer is being written in, how far along, and its text so far.
    @Published private(set) var runningID: UUID?
    @Published private(set) var phase = Phase.asking
    @Published private(set) var liveAnswer: String?
    /// The phase of the last run, kept for the chat it ran in.
    private var lastRun: (id: UUID, phase: Phase)?

    private unowned let app: AppModel
    private let store: ChatStore
    private let selector = RegionSelector()
    private let saving = DispatchQueue(label: "com.agustintorres.waldo.chat-save", qos: .utility)
    private let log = Logger(subsystem: "com.agustintorres.waldo", category: "chat")
    private var task: Task<Void, Never>?

    init(app: AppModel, store: ChatStore = .standard) {
        self.app = app
        self.store = store
        chats = store.loadAll()
    }

    // MARK: What's on screen

    var current: ChatConversation {
        guard let selectedID, let chat = chats.first(where: { $0.id == selectedID }) else { return newChat }
        return chat
    }

    var isRunning: Bool { runningID != nil }

    /// The phase of the chat on screen.
    var currentPhase: Phase {
        if runningID == current.id { return phase }
        if let lastRun, lastRun.id == current.id, case .error = lastRun.phase { return lastRun.phase }
        return .asking
    }

    var hasAttachment: Bool { pendingImage != nil || pendingQuote != nil }

    /// Chats whose title or messages contain the search text.
    var filteredChats: [ChatConversation] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return chats }
        return chats.filter { chat in
            chat.displayTitle.localizedCaseInsensitiveContains(query) || chat.turns.contains {
                $0.question.localizedCaseInsensitiveContains(query) || $0.reply.localizedCaseInsensitiveContains(query)
                    || ($0.quote?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
    }

    func select(_ id: UUID?) {
        guard id != selectedID else { return }
        unloadImages(except: id)
        selectedID = id
        draft = ""
        pendingImage = nil
        pendingQuote = nil
        if let id, let index = index(of: id), !chats[index].hasAllImages {
            chats[index] = store.loadImages(of: chats[index])
        }
    }

    /// A fresh chat on screen. `openedFrom` is the app the user came from.
    func startNewChat(openedFrom: String?, quote: String? = nil, image: ChatImage? = nil) {
        select(nil)
        newChat = ChatConversation(openedFrom: openedFrom)
        pendingQuote = quote
        pendingImage = image
    }

    /// Only the chat on screen (and one being answered) keep their captures in memory.
    private func unloadImages(except id: UUID?) {
        for index in chats.indices where chats[index].id != id && chats[index].id != runningID {
            guard chats[index].turns.contains(where: { $0.image != nil }) else { continue }
            for turn in chats[index].turns.indices { chats[index].turns[turn].unloadImage() }
        }
    }

    private func index(of id: UUID) -> Int? {
        chats.firstIndex { $0.id == id }
    }

    // MARK: Editing

    func rename(_ id: UUID, to title: String) {
        guard let index = index(of: id) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        chats[index].title = trimmed.isEmpty ? nil : trimmed
        save(chats[index])
    }

    func delete(_ id: UUID) {
        if runningID == id { cancelRun() }
        if selectedID == id { select(nil) }
        chats.removeAll { $0.id == id }
        app.endChat(id)
        saving.async { [store] in store.delete(id) }
    }

    func deleteAll() {
        cancelRun()
        select(nil)
        chats.forEach { app.endChat($0.id) }
        chats.removeAll()
        saving.async { [store] in store.deleteAll() }
    }

    private func save(_ chat: ChatConversation) {
        saving.async { [store] in store.save(chat) }
    }

    // MARK: Captures

    /// Lets the user drag over the screen (or takes the whole screen) with
    /// Waldo's window out of the way. Says why not next to the mouse if it can't.
    func capture(wholeScreen: Bool, hiding window: NSWindow?) async -> ChatImage? {
        guard await canCapture() else { return nil }
        // A window on another desktop is already out of the way, and showing it
        // again would switch to that desktop.
        let hidden = window?.isVisible == true && window?.isOnActiveSpace == true
        if hidden { window?.orderOut(nil) }
        defer { if hidden { window?.makeKeyAndOrderFront(nil) } }
        guard #available(macOS 14.0, *) else { return nil }
        let selection: RegionSelector.Selection
        if wholeScreen {
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
            else { return nil }
            selection = .init(rect: screen.frame, screen: screen)
        } else {
            guard let selected = await selector.select() else { return nil }
            selection = selected
        }
        do {
            let image = try await ScreenCapture.capture(selection.rect, on: selection.screen)
            return ChatImage(image)
        } catch {
            log.error("Capture failed: \(error.localizedDescription, privacy: .public)")
            app.flash(note: "Couldn't capture the screen: \(error.localizedDescription)", anchor: Self.mouseAnchor, isError: true)
            return nil
        }
    }

    /// Attaches the image on the clipboard. False when there's none, so that
    /// the paste goes on as usual.
    func pasteImage() -> Bool {
        guard let image = ImageImport.imageOnClipboard() else { return false }
        Task { await attach(image) }
        return true
    }

    func chooseImage() {
        guard let url = ImageImport.chooseFile() else { return }
        guard let image = ImageImport.image(fromFile: url) else {
            app.flash(note: "Couldn't read that image. Try a PNG or JPEG.", anchor: Self.mouseAnchor, isError: true)
            return
        }
        Task { await attach(image) }
    }

    private func attach(_ image: ChatImage) async {
        if let reason = await app.chatUnavailableReason(needsVision: true) {
            app.flash(note: reason, anchor: Self.mouseAnchor, isError: true)
            return
        }
        pendingImage = image
    }

    private static var mouseAnchor: CGRect {
        let mouse = NSEvent.mouseLocation
        return CGRect(x: mouse.x, y: mouse.y - 10, width: 0, height: 20)
    }

    private func canCapture() async -> Bool {
        let anchor = Self.mouseAnchor
        guard #available(macOS 14.0, *) else {
            app.flash(note: "Captures need macOS 14 or later.", anchor: anchor, isError: true)
            return false
        }
        if let reason = await app.chatUnavailableReason(needsVision: true) {
            app.flash(note: reason, anchor: anchor, isError: true)
            return false
        }
        guard ScreenCapture.hasPermission else {
            ScreenCapture.requestPermission()
            app.flash(note: "Waldo needs to see your screen. Turn it on in System Settings › Privacy & Security › Screen Recording, then quit and reopen Waldo.",
                      anchor: anchor, isError: true)
            return false
        }
        return true
    }

    // MARK: Sending

    /// Sends the draft with what's attached. A capture or selection alone asks for an explanation.
    func send() {
        guard !isRunning else { return }
        // The image marker in a message would be taken for another image.
        var question = draft.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "<__media__>", with: "")
        if question.isEmpty, hasAttachment { question = ChatPrompts.firstQuestion }
        guard !question.isEmpty else { return }
        let settings = app.settings
        let turn = ChatTurn(question: question, image: pendingImage, quote: pendingQuote,
                            search: settings.chatSearchesWeb ? SearchStep() : nil, thinks: settings.chatThinks)
        draft = ""
        pendingImage = nil
        pendingQuote = nil

        var chat = current
        chat.turns.append(turn)
        chat.updatedAt = .now
        if let index = index(of: chat.id) {
            chats.remove(at: index)
        }
        chats.insert(chat, at: 0) // the newest chat goes first
        selectedID = chat.id
        save(chat)
        run(chat)
    }

    func cancelRun() {
        task?.cancel()
        task = nil
        if let runningID, let index = index(of: runningID), chats[index].turns.last?.answer.isEmpty == true {
            chats[index].turns.removeLast()
            save(chats[index])
        }
        runningID = nil
        liveAnswer = nil
        phase = .asking
    }

    /// Answers the chat's last question. With search on, the model first writes a
    /// query, Waldo searches, and the model answers from the results.
    private func run(_ chat: ChatConversation) {
        var chat = chat
        let index = chat.turns.count - 1
        runningID = chat.id
        liveAnswer = nil
        phase = chat.turns[index].search == nil ? .reading : .searching(nil)
        let onPartial: PartialHandler = { [weak self] partial in
            DispatchQueue.main.async { self?.show(partial, in: chat.id, thinks: chat.turns[index].thinks) }
        }
        task = Task { [weak self, app] in
            do {
                if chat.turns[index].search != nil {
                    let rawQuery = try await app.chat(chat, onPartial: nil).text
                    chat.turns[index].search?.rawQuery = rawQuery
                    let query = chat.turns[index].search?.query ?? ""
                    if chat.turns[index].search?.isSkipped == true {
                        // The model decided this question doesn't need the web.
                    } else if query.isEmpty {
                        chat.turns[index].search?.failure = "the model didn't write a query"
                    } else {
                        self?.update(chat, phase: .searching(query))
                        do {
                            let results = try await app.webSearch(query)
                            chat.turns[index].search?.results = results
                        } catch {
                            guard !Task.isCancelled else { return }
                            self?.log.error("Search failed: \(error.localizedDescription, privacy: .public)")
                            chat.turns[index].search?.failure = error.localizedDescription
                        }
                    }
                    guard !Task.isCancelled else { return }
                    self?.update(chat, phase: .reading)
                }
                let answer = try await app.chat(chat, onPartial: onPartial)
                guard !Task.isCancelled, let self else { return }
                chat.turns[index].answer = answer.text
                if answer.reachedLimit { chat.turns[index].wasCut = true }
                chat.updatedAt = .now
                self.update(chat, phase: .done)
                self.finishRun(chat)
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.log.error("Chat failed: \(error.localizedDescription, privacy: .public)")
                // The failed question stays out of the chat the next message continues.
                chat.turns.removeLast()
                self.update(chat, phase: .error(error.localizedDescription))
                self.finishRun(chat)
            }
        }
    }

    private func update(_ chat: ChatConversation, phase: Phase) {
        guard runningID == chat.id, let index = index(of: chat.id) else { return }
        chats[index] = chat
        self.phase = phase
        liveAnswer = nil
    }

    private func finishRun(_ chat: ChatConversation) {
        lastRun = (chat.id, phase)
        runningID = nil
        liveAnswer = nil
        task = nil
        save(chat)
        if chat.title == nil, chat.turns.count == 1, !chat.turns[0].answer.isEmpty {
            Task { await nameChat(chat.id) }
        }
        if selectedID != chat.id { unloadImages(except: selectedID) }
    }

    private func show(_ partial: String, in id: UUID, thinks: Bool) {
        guard runningID == id else { return }
        liveAnswer = partial
        let isThinking = thinks && !partial.contains("</think>")
        let next: Phase = isThinking ? .thinking : .writing
        if phase != next { phase = next }
    }

    /// The model titles a chat after its first answer, in the background.
    private func nameChat(_ id: UUID) async {
        guard let chat = chats.first(where: { $0.id == id }),
              let title = await app.chatTitle(for: chat),
              let index = index(of: id), chats[index].title == nil else { return }
        chats[index].title = title
        save(chats[index])
    }
}
