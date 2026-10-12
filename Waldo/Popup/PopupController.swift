import AppKit
import Combine
import os
import SwiftUI

/// Owns the floating panel: lazily created, reused, and doing no work while hidden.
@MainActor
final class PopupController {
    private unowned let app: AppModel
    private let log = Logger(subsystem: "com.agustintorres.waldo", category: "popup")
    private let model = PopupModel()
    private var panel: PopupPanel?
    private var hostingView: FirstMouseHostingView<PopupView>?

    private(set) var snapshot: SelectionSnapshot?
    private var anchor = CGRect.zero
    private var placement = PopupPositioner.Placement.below
    /// The last selection the user dismissed; it isn't shown again.
    private var dismissedIdentity: String?
    private var task: Task<Void, Never>?
    /// Identifies the current request so partial text from an older one is dropped.
    private var requestID = 0
    private var hotkeyCancel: (() -> Void)?
    /// The text the current result was made from (for web content, the copied
    /// text, which keeps emoji as :shortcodes:), for undo.
    private var processedInput: String?
    private var visibleOnlyMonitors: [Any] = []
    private var spaceObserver: NSObjectProtocol?
    private var stateObserver: AnyCancellable?
    private var preferencesObserver: AnyCancellable?

    var isVisible: Bool { panel?.isVisible == true }

    /// Hidden while the user is in another app or desktop, keeping its result
    /// (or the generation in progress) for when they come back.
    private(set) var isSuspended = false
    private var resumedAt: ContinuousClock.Instant?
    /// Reactivating an app moves its focus (and a browser's AX tree wakes up); that
    /// shouldn't dismiss a popup just brought back.
    private static let resumeGrace = Duration.milliseconds(1_500)

    init(app: AppModel) {
        self.app = app
        model.onProcess = { [weak self] mode in self?.process(mode) }
        model.onReplace = { [weak self] text in self?.replace(text) }
        model.onCopy = { [weak self] text in
            ClipboardService.writeString(text)
            self?.hide(reason: "copy")
        }
        model.onClose = { [weak self] in self?.hide(reason: "close button") }
        // Resize after SwiftUI has rendered the new state.
        stateObserver = model.$state.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.relayout() }
        }
        // The pickers change the global settings: resize for the new names and prewarm
        // for the new prompt. Delivered after the change, since @Published fires on willSet.
        preferencesObserver = app.settings.$targetLanguage.map { _ in () }
            .merge(with: app.settings.$activeModeID.map { _ in () }, app.settings.$customModes.map { _ in () },
                   app.settings.$appModeRules.map { _ in () }, app.settings.$showChanges.map { _ in () })
            .dropFirst(5)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.preferencesChanged() }
    }

    func show(_ snapshot: SelectionSnapshot, anchor: CGRect) {
        guard snapshot.identity != dismissedIdentity else { return }
        if isSuspended, snapshot.identity == self.snapshot?.identity {
            resume()
            return
        }
        isSuspended = false
        task?.cancel()
        self.snapshot = snapshot
        model.state = .compact
        model.isReplacing = false
        model.isHotkeyRun = false
        model.appBundleID = NSRunningApplication(processIdentifier: snapshot.pid)?.bundleIdentifier
        present(at: anchor)
        app.prewarm(snapshot.text, appBundleID: model.appBundleID)
    }

    private func present(at anchor: CGRect) {
        self.anchor = anchor
        let panel = makePanelIfNeeded()
        let size = fittingSize()
        placement = PopupPositioner.placement(for: size, anchor: anchor)
        panel.setFrame(PopupPositioner.frame(for: size, anchor: anchor, placement: placement), display: true)
        fadeIn(panel)
        installVisibleOnlyMonitors()
    }

    /// A quick fade when the panel appears; changes while it's up aren't animated.
    private func fadeIn(_ panel: PopupPanel) {
        guard !panel.isVisible else { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    /// A short message next to `anchor` that closes by itself.
    func flash(note: String, anchor: CGRect, isError: Bool = false) {
        hide(reason: "flash")
        isSuspended = false
        snapshot = nil
        model.isHotkeyRun = true
        model.state = isError ? .error(note) : .note(note)
        present(at: anchor)
        requestID += 1
        let id = requestID
        DispatchQueue.main.asyncAfter(deadline: .now() + (isError ? 4 : 2)) { [weak self] in
            guard let self, self.requestID == id else { return }
            self.hide(reason: "flash done")
        }
    }

    // MARK: Hotkey runs

    /// Shows the text being written during a hotkey run, which replaces it itself.
    /// Returns the handler for the run's partial results.
    /// `onCancel` runs if the user closes the popup before the run ends.
    func beginHotkeyRun(anchor: CGRect, onCancel: @escaping () -> Void) -> PartialHandler {
        hide(reason: "hotkey")
        hotkeyCancel = onCancel
        isSuspended = false
        snapshot = nil
        model.isHotkeyRun = true
        model.state = .streaming("")
        present(at: anchor)
        requestID += 1
        let id = requestID
        return { [weak self] partial in
            DispatchQueue.main.async { self?.showPartial(partial, requestID: id) }
        }
    }

    /// Closes the progress popup; or shows why the run failed, or a short note
    /// (nothing to change) that closes by itself.
    func endHotkeyRun(error: String? = nil, note: String? = nil) {
        hotkeyCancel = nil
        guard model.isHotkeyRun, isVisible else { return }
        requestID += 1 // late partials are dropped
        if let error {
            model.state = .error(error)
        } else if let note {
            model.state = .note(note)
            let id = requestID
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.requestID == id, self.model.isHotkeyRun else { return }
                self.hide(reason: "hotkey note")
            }
        } else {
            hide(reason: "hotkey done")
        }
    }

    /// `keepsResult`: the user only left (another app or desktop), so a result or
    /// a generation in progress is suspended instead of discarded.
    func hide(reason: String, keepsResult: Bool = false) {
        guard isVisible else { return }
        if keepsResult, hasResult {
            suspend(reason: reason)
            return
        }
        if ["focus changed", "selection changed"].contains(reason), let resumedAt,
           ContinuousClock.now - resumedAt < Self.resumeGrace {
            log.info("Kept resumed popup despite: \(reason, privacy: .public)")
            return
        }
        log.info("Hiding popup: \(reason, privacy: .public)")
        if let hotkeyCancel {
            self.hotkeyCancel = nil
            hotkeyCancel()
        }
        dismissedIdentity = snapshot?.identity
        task?.cancel()
        task = nil
        panel?.orderOut(nil)
        removeVisibleOnlyMonitors()
        snapshot = nil
        app.discardPrewarm()
    }

    private var hasResult: Bool {
        switch model.state {
        case .streaming, .result: true
        case .compact, .error, .note: false
        }
    }

    private func suspend(reason: String) {
        log.info("Suspending popup: \(reason, privacy: .public)")
        isSuspended = true
        panel?.orderOut(nil)
        removeScrollMonitor() // the space observer stays, to notice the user coming back
    }

    /// Brings a suspended popup back when its app is frontmost again, if the window
    /// with the selection is on this desktop (else the desktop switch brings it back).
    func resumeIfSuspended(in pid: pid_t) {
        guard isSuspended, snapshot?.pid == pid, Self.hasOnScreenWindow(pid: pid, containing: anchor) else { return }
        resume()
    }

    private func resume() {
        guard let panel else { return }
        log.info("Resuming popup")
        isSuspended = false
        resumedAt = .now
        relayout(force: true)
        fadeIn(panel)
        installVisibleOnlyMonitors()
    }

    /// A different field or app: a dismissed selection may be shown again later.
    func forgetDismissed() {
        dismissedIdentity = nil
    }

    private func preferencesChanged() {
        guard isVisible, let snapshot else { return }
        relayout()
        if model.state == .compact { app.prewarm(snapshot.text, appBundleID: model.appBundleID) }
    }

    // MARK: Actions

    private func process(_ mode: ProcessingMode) {
        guard let snapshot else { return }
        // Straight to the result card: text appears there as it's written.
        model.state = .streaming("")
        let appBundleID = model.appBundleID
        requestID += 1
        let id = requestID
        // Partials arrive on the engine's thread; the main queue keeps them in order.
        let onProgress: PartialHandler = { [weak self] partial in
            DispatchQueue.main.async { self?.showPartial(partial, requestID: id) }
        }
        task = Task { [weak self, app] in
            do {
                let text = await Self.fullText(of: snapshot, app: app)
                self?.processedInput = text
                let result = try await app.process(text, mode: mode, appBundleID: appBundleID, onProgress: onProgress)
                guard !Task.isCancelled else { return }
                self?.model.state = .result(text: result.text, summary: result.summary, changed: result.changed,
                                            changes: Self.changes(from: text, to: result))
            } catch {
                guard !Task.isCancelled else { return }
                self?.model.state = .error(error.localizedDescription)
            }
        }
    }

    private func showPartial(_ text: String, requestID id: Int) {
        guard id == requestID, isVisible || isSuspended, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        switch model.state {
        case .streaming: model.state = .streaming(text)
        default: break
        }
    }

    /// What a correction or same-language rephrase changed; translations have no useful diff.
    private static func changes(from input: String, to result: ProcessingResult) -> [TextDiff.Segment]? {
        guard result.changed else { return nil }
        if case .translate = result.task { return nil }
        return TextDiff.segments(from: input, to: result.text)
    }

    /// Web editors leave non-text content out of AX text: Slack exposes emoji as
    /// images, so the AX selection drops them. Copying keeps them as :shortcodes:.
    /// The user clicked, so a ⌘C into the still-focused app is expected here.
    private static func fullText(of snapshot: SelectionSnapshot, app: AppModel) async -> String {
        guard snapshot.isWebContent else { return snapshot.text }
        app.beginAutomation()
        defer { app.endAutomation() }
        return await TextReplacer.copySelection() ?? snapshot.text
    }

    private func replace(_ text: String) {
        guard let snapshot else { return }
        model.isReplacing = true
        let original = processedInput ?? snapshot.text
        task = Task { [weak self, app] in
            app.beginAutomation()
            defer { app.endAutomation() }
            do {
                try await TextReplacer.replace(snapshot, with: text)
                app.replacementUndo.record(.init(pid: snapshot.pid, original: original, replacement: text,
                                                 element: snapshot.element, location: snapshot.range?.location,
                                                 isWebContent: snapshot.isWebContent))
                self?.hide(reason: "replaced")
            } catch {
                self?.model.isReplacing = false
                self?.model.state = .error(error.localizedDescription)
            }
        }
    }

    // MARK: Panel

    private func makePanelIfNeeded() -> PopupPanel {
        if let panel { return panel }
        let panel = PopupPanel()
        let hostingView = FirstMouseHostingView(rootView: PopupView(model: model, settings: app.settings))
        panel.contentView = hostingView
        self.panel = panel
        self.hostingView = hostingView
        return panel
    }

    private func fittingSize() -> CGSize {
        hostingView?.layoutSubtreeIfNeeded()
        return hostingView?.fittingSize ?? CGSize(width: 200, height: 40)
    }

    private func relayout(force: Bool = false) {
        guard isVisible || force, let panel else { return }
        panel.setFrame(PopupPositioner.frame(for: fittingSize(), anchor: anchor, placement: placement), display: true)
    }

    // Monitors that only exist while the popup is on screen. Clicks, typing and Esc
    // are handled by SelectionMonitor, which is already watching those events.
    private func installVisibleOnlyMonitors() {
        if spaceObserver == nil {
            spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                // The window list catches up after the switch animation.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    MainActor.assumeIsolated { self?.activeSpaceChanged() }
                }
            }
        }
        guard visibleOnlyMonitors.isEmpty else { return }
        if let scroll = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.hide(reason: "scroll") }
        }) {
            visibleOnlyMonitors.append(scroll)
        }
    }

    /// Leaving the desktop suspends a result; coming back to it brings it back. The
    /// app may be frontmost on both desktops, so what counts is whether the window
    /// with the selection is on screen.
    private func activeSpaceChanged() {
        guard let pid = snapshot?.pid else { return }
        let selectionVisible = Self.hasOnScreenWindow(pid: pid, containing: anchor)
        if isSuspended, selectionVisible {
            resume()
        } else if isVisible, !selectionVisible {
            hide(reason: "space changed", keepsResult: true)
        }
    }

    /// Window owners and bounds don't need Screen Recording permission; only titles do.
    private static func hasOnScreenWindow(pid: pid_t, containing anchor: CGRect) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return true }
        // Window bounds use a top-left origin on the primary screen; the anchor is AppKit's.
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        let point = CGPoint(x: anchor.midX, y: primaryMaxY - anchor.midY)
        return windows.contains { info in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
            return rect.contains(point)
        }
    }

    private func removeScrollMonitor() {
        visibleOnlyMonitors.forEach(NSEvent.removeMonitor)
        visibleOnlyMonitors.removeAll()
    }

    private func removeVisibleOnlyMonitors() {
        removeScrollMonitor()
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
            self.spaceObserver = nil
        }
    }
}
