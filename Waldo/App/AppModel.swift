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

    private let settingsWindow = HostedWindowController(title: "Waldo Settings", fullSizeContent: true)
    private let onboardingWindow = HostedWindowController(title: "Welcome to Waldo", fullSizeContent: true)
    private var cancellables: Set<AnyCancellable> = []
    private var prewarmTask: Task<Void, Never>?

    func launch() {
        AXElement.configureTimeout()
        hotkeys = HotkeyManager(flow: HotkeyFlow(model: self)) { [weak self] in
            Task { await self?.undoLastReplacement() }
        }

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

    func openSettings() {
        settingsWindow.show { SettingsView(model: self, settings: settings, permission: permission, models: models) }
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
