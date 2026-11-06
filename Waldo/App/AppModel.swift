import AppKit
import Combine
import Foundation

/// Composition root: owns the long-lived services and wires them together.
@MainActor
final class AppModel: ObservableObject {
    let settings = SettingsStore()
    let state = AppState()
    let permission = AccessibilityPermission()
    let models = ModelDownloader()
    let launchAtLogin = LaunchAtLogin()
    private lazy var engineSelector = EngineSelector(settings: settings)
    private let processor = TextProcessor()
    private var hotkeys: HotkeyManager?
    private lazy var popup = PopupController(app: self)
    private(set) lazy var library = ChatLibrary(app: self)
    /// What Waldo's window shows: the chats, or a Settings pane.
    let route = WindowRoute()
    private lazy var mainWindow = MainWindowController(app: self)
    private lazy var selectionMonitor = SelectionMonitor(app: self, popup: popup)
    private(set) lazy var replacementUndo = ReplacementUndo(state: state) { [weak self] in
        self?.isAutomatingInput ?? false
    }

    private var automationDepth = 0
    private var automationQuietUntil = ContinuousClock.now

    /// True while Waldo posts ⌘A/⌘C/⌘V itself, and briefly after: the target app's
    /// AX notifications and our monitors' copies of those events arrive late.
    var isAutomatingInput: Bool {
        automationDepth > 0 || ContinuousClock.now < automationQuietUntil
    }

    func beginAutomation() {
        automationDepth += 1
    }

    func endAutomation() {
        automationDepth -= 1
        automationQuietUntil = .now + .milliseconds(400)
    }

    private let onboardingWindow = HostedWindowController(title: "Welcome to Waldo", fullSizeContent: true)
    private var cancellables: Set<AnyCancellable> = []
    private var prewarmTask: Task<Void, Never>?

    func launch() {
        AXElement.configureTimeout()
        hotkeys = HotkeyManager(flow: HotkeyFlow(model: self), undo: { [weak self] in
            Task { await self?.undoLastReplacement() }
        }, explain: { [weak self] wholeScreen in
            self?.startExplain(wholeScreen: wholeScreen)
        }, newChat: { [weak self] in
            self?.startChat()
        })

        // Event-driven: refresh the menu's engine line when the mode changes (and once now).
        settings.$engineMode.map { _ in () }
            .merge(with: settings.$llamaModelID.map { _ in () })
            .sink { [weak self] in Task { await self?.refreshEngineStatus() } }
            .store(in: &cancellables)
        models.onChange = { [weak self] in Task { await self?.refreshEngineStatus() } }
        // The popup runs only while it's enabled and Accessibility is granted.
        settings.$popupEnabled.combineLatest(permission.$isGranted)
            .map { $0 && $1 }
            .removeDuplicates()
            .sink { [weak self] active in
                guard let self else { return }
                active ? self.selectionMonitor.start() : self.selectionMonitor.stop()
            }
            .store(in: &cancellables)
        settings.$excludedBundleIDs.combineLatest(settings.$accessibleBrowserBundleIDs)
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.selectionMonitor.refresh() }
            }
            .store(in: &cancellables)

        if !permission.isGranted {
            showOnboarding()
        }
    }

    /// Settings take the place of the chats in Waldo's window.
    func openSettings(_ pane: SettingsPane? = nil) {
        route.settingsPane = pane ?? route.settingsPane ?? .general
        mainWindow.show()
    }

    func showOnboarding() {
        onboardingWindow.show { [onboardingWindow, permission, settings, launchAtLogin] in
            OnboardingView(permission: permission, settings: settings, launchAtLogin: launchAtLogin) {
                onboardingWindow.close()
            }
        }
    }

    func refreshEngineStatus() async {
        state.engineDescription = await engineSelector.statusDescription()
    }

    /// Runs the full pipeline on `text`. Inference runs off the main actor.
    /// `appBundleID` is the app the text comes from, which picks its mode.
    func process(_ text: String, mode: ProcessingMode = .automatic,
                 appBundleID: String? = nil, onProgress: PartialHandler? = nil) async throws -> ProcessingResult {
        prewarmTask?.cancel()
        state.isProcessing = true
        defer {
            state.isProcessing = false
            Task { await refreshEngineStatus() }
        }
        let (engines, reason) = await engineSelector.candidates()
        guard !engines.isEmpty else {
            throw ProcessingError.noEngine(reason ?? "No engine is available.")
        }
        return try await processor.process(text, mode: mode, target: settings.language(for: appBundleID),
                                            customMode: settings.mode(for: appBundleID), glossary: settings.glossary,
                                            engines: engines,
                                            onProgress: onProgress)
    }

    /// Called when the popup appears, never while idle.
    func prewarm(_ text: String, appBundleID: String?) {
        prewarmTask?.cancel()
        let target = settings.language(for: appBundleID)
        let customMode = settings.mode(for: appBundleID)
        prewarmTask = Task { [engineSelector, processor] in
            let (engines, _) = await engineSelector.candidates()
            guard !Task.isCancelled else { return }
            await processor.prewarm(text, target: target, customMode: customMode, engines: engines)
        }
    }

    /// Puts back the text Waldo last replaced, and says so next to the field.
    func undoLastReplacement() async {
        beginAutomation()
        defer { endAutomation() }
        let mouse = NSEvent.mouseLocation
        let mouseAnchor = CGRect(x: mouse.x, y: mouse.y - 10, width: 0, height: 20)
        switch await replacementUndo.undo() {
        case .restored(let frame):
            popup.flash(note: "Restored your original text.", anchor: frame ?? mouseAnchor)
        case .nothingToUndo:
            popup.flash(note: "Nothing to undo. Typing after a replacement, or 10 minutes, ends the undo.",
                        anchor: mouseAnchor, isError: true)
        case .wrongApp(let name):
            popup.flash(note: "Go back to \(name) to undo Waldo's last replacement.", anchor: mouseAnchor, isError: true)
        }
    }

    /// Hotkey runs show their progress in the popup; see PopupController.
    func beginHotkeyProgress(anchor: CGRect, onCancel: @escaping () -> Void) -> PartialHandler {
        popup.beginHotkeyRun(anchor: anchor, onCancel: onCancel)
    }

    func endHotkeyProgress(error: String? = nil, note: String? = nil) {
        popup.endHotkeyRun(error: error, note: note)
    }

    // MARK: Chat

    func showMainWindow() {
        mainWindow.show()
    }

    /// The app the user is in, unless it's Waldo itself.
    private var frontmostAppName: String? {
        let app = NSWorkspace.shared.frontmostApplication
        return app?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : app?.localizedName
    }

    /// A new chat in Waldo's window.
    func startChat() {
        popup.hide(reason: "chat")
        route.settingsPane = nil
        library.startNewChat(openedFrom: frontmostAppName)
        mainWindow.show()
    }

    /// A new chat that starts with a capture: a dragged region or the whole screen.
    func startExplain(wholeScreen: Bool = false) {
        popup.hide(reason: "explain")
        let openedFrom = frontmostAppName
        Task {
            guard let image = await library.capture(wholeScreen: wholeScreen, hiding: mainWindow.window) else { return }
            route.settingsPane = nil
            library.startNewChat(openedFrom: openedFrom, image: image)
            mainWindow.show()
        }
    }

    /// A new chat about text selected in another app (the popup's Ask).
    func startChat(about text: String) {
        route.settingsPane = nil
        library.startNewChat(openedFrom: frontmostAppName, quote: text)
        mainWindow.show()
    }

    /// A capture for the next message of the chat on screen.
    func addCapture(wholeScreen: Bool) {
        Task {
            guard let image = await library.capture(wholeScreen: wholeScreen, hiding: mainWindow.window) else { return }
            library.pendingImage = image
            mainWindow.show()
        }
    }

    /// Why chatting (with captures, if `needsVision`) can't run now, or nil.
    func chatUnavailableReason(needsVision: Bool) async -> String? {
        await engineSelector.chatEngine(needsVision: needsVision).reason
    }

    func chat(_ conversation: ChatConversation, onPartial: PartialHandler?) async throws -> LoadedModel.Output {
        let needsVision = conversation.turns.contains(where: \.hasImage)
        guard let engine = await engineSelector.chatEngine(needsVision: needsVision).engine else {
            throw ChatError.noVisionModel(await chatUnavailableReason(needsVision: needsVision) ?? "Chat is unavailable.")
        }
        state.isProcessing = true
        defer { state.isProcessing = false }
        return try await engine.chat(conversation, instructions: ChatPrompts.instructions(language: settings.chatLanguage,
                                                                                conversation: conversation),
                                     onPartial: onPartial)
    }

    /// A few words naming the chat, written by the model; nil if it can't.
    func chatTitle(for chat: ChatConversation) async -> String? {
        guard let first = chat.turns.first,
              let engine = await engineSelector.chatEngine(needsVision: false).engine else { return nil }
        let request = GenerationRequest(instructions: ChatPrompts.titleInstructions(language: settings.chatLanguage),
                                        prompt: ChatPrompts.titlePrompt(for: first), maxOutputTokens: 32, greedy: true)
        guard let raw = try? await engine.generate(request) else { return nil }
        let line = raw.split(separator: "\n").first.map(String.init) ?? ""
        let title = line.trimmingCharacters(in: CharacterSet(charactersIn: " \"'“”*.#").union(.whitespaces))
        return title.isEmpty ? nil : String(title.prefix(60))
    }

    /// Only the query leaves the Mac.
    func webSearch(_ query: String) async throws -> [SearchResult] {
        try await WebSearch.search(query, provider: settings.searchProvider, searXNGURL: settings.searXNGURL)
    }

    func endChat(_ id: UUID) {
        Task { [engineSelector] in await engineSelector.chatEngine(needsVision: false).engine?.endChat(id) }
    }

    /// A short message next to `anchor` that closes by itself.
    func flash(note: String, anchor: CGRect, isError: Bool = false) {
        popup.flash(note: note, anchor: anchor, isError: isError)
    }

    func discardPrewarm() {
        let pending = prewarmTask
        prewarmTask = nil
        // Wait for an in-flight prewarm so it can't leave a session behind.
        Task { [engineSelector] in
            await pending?.value
            for engine in await engineSelector.candidates().engines {
                await engine.discardPrewarm()
            }
        }
    }
}
