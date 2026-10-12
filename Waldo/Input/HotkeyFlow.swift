import AppKit

/// The hotkey fast path: copy, process, paste back, restore the clipboard
/// (RESEARCH §4.8). The popup shows the text being written, without a preview
/// step: the result replaces the text as soon as it's done.
@MainActor
final class HotkeyFlow {
    enum Scope {
        case wholeField
        case selection
    }

    /// Slack-tuned delay from RESEARCH §4.8 (paste delays live in TextReplacer).
    private static let afterSelectAll = Duration.milliseconds(80)

    private let model: AppModel
    private var isRunning = false

    init(model: AppModel) {
        self.model = model
    }

    func run(_ scope: Scope, mode: ProcessingMode = .automatic) async {
        guard !isRunning else { return }
        isRunning = true
        model.beginAutomation()
        defer {
            isRunning = false
            model.endAutomation()
        }

        model.permission.refresh()
        guard model.permission.isGranted else {
            model.showOnboarding()
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        if KeystrokeSimulator.isSecureInputEnabled {
            Notifier.show(title: "Waldo can't read this field",
                          body: "Secure input is on (for example in a password field).")
            return
        }

        await KeystrokeSimulator.waitForModifiersReleased()
        if scope == .wholeField {
            KeystrokeSimulator.postCommand(.a)
            try? await Task.sleep(for: Self.afterSelectAll)
        }
        guard let text = await TextReplacer.copySelection() else { return } // nothing copied: abort silently

        let selection = await Task.detached { SelectionReader.read(pid: app.processIdentifier, hint: nil) }.value
        let anchor = Self.anchor(for: selection)
        // Its own task, so closing the popup cancels the generation and nothing is pasted.
        var work: Task<ProcessingResult, Error>?
        let onProgress = model.beginHotkeyProgress(anchor: anchor) { work?.cancel() }
        work = Task { [model] in
            try await model.process(text, mode: mode, appBundleID: app.bundleIdentifier, onProgress: onProgress)
        }
        guard let work else { return }
        let result: ProcessingResult
        do {
            result = try await work.value
        } catch {
            if !work.isCancelled { model.endHotkeyProgress(error: error.localizedDescription) }
            return
        }
        guard !work.isCancelled else { return }
        guard result.changed else {
            model.endHotkeyProgress(note: result.summary)
            return
        }

        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
            model.endHotkeyProgress()
            ClipboardService.writeString(result.text)
            Notifier.show(title: "Result copied", body: "You switched apps, so Waldo copied the result instead of pasting it.")
            return
        }
        model.endHotkeyProgress()
        await TextReplacer.paste(result.text)
        model.replacementUndo.record(.init(pid: app.processIdentifier, original: text, replacement: result.text,
                                           element: selection?.element, location: selection?.range?.location,
                                           isWebContent: selection?.isWebContent ?? true))
    }

    /// Where the selection is, to show progress next to it: its bounds when the
    /// app reports them, else the mouse.
    private static func anchor(for snapshot: SelectionSnapshot?) -> CGRect {
        if let snapshot { return PopupPositioner.anchor(for: snapshot, mouseLocation: nil) }
        let mouse = NSEvent.mouseLocation
        return CGRect(x: mouse.x, y: mouse.y - 10, width: 0, height: 20)
    }
}
