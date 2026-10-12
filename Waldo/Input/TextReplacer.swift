import AppKit
import ApplicationServices

/// Replaces a selection captured by the popup (RESEARCH popup P6): re-validate,
/// then AX set for native text views or ⌘V for web content, then verify.
@MainActor
enum TextReplacer {
    enum ReplaceError: LocalizedError {
        case appChanged
        case selectionChanged
        case notConfirmed

        var errorDescription: String? {
            switch self {
            case .appChanged: "The app with your selection is no longer in front. Nothing was replaced."
            case .selectionChanged: "Your selection changed. Nothing was replaced."
            case .notConfirmed: "Waldo couldn't confirm the replacement. The result is on your clipboard: press ⌘V to paste it."
            }
        }
    }

    static func replace(_ snapshot: SelectionSnapshot, with text: String) async throws {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == snapshot.pid else {
            throw ReplaceError.appChanged
        }
        switch await Task.detached(operation: { SelectionReader.revalidate(snapshot) }).value {
        case .unchanged:
            break
        case .collapsed:
            // Same field, selection lost: put it back before replacing.
            guard let range = snapshot.range else { throw ReplaceError.selectionChanged }
            let restored = await Task.detached {
                snapshot.element.setRange(kAXSelectedTextRangeAttribute, range)
                    && SelectionReader.revalidate(snapshot) == .unchanged
            }.value
            guard restored else { throw ReplaceError.selectionChanged }
        case .changed:
            throw ReplaceError.selectionChanged
        }

        // Chromium and WebKit ignore AX writes to the selected text (and may still
        // report success), so web content always goes through paste.
        if !snapshot.isWebContent, await setViaAccessibility(snapshot, text) {
            return
        }
        let pasted = await paste(text) {
            await Task.detached { SelectionReader.revalidate(snapshot) != .unchanged }.value
        }
        if !pasted { throw ReplaceError.notConfirmed }
    }

    private static func setViaAccessibility(_ snapshot: SelectionSnapshot, _ text: String) async -> Bool {
        guard let start = snapshot.range?.location,
              await Task.detached(operation: { snapshot.element.set(kAXSelectedTextAttribute, text as CFString) }).value
        else { return false }
        try? await Task.sleep(for: .milliseconds(200))
        return await Task.detached {
            snapshot.element.string(forRange: CFRange(location: start, length: text.utf16.count)) == text
        }.value
    }

    /// ⌘C with clipboard save and immediate restore (RESEARCH §4.8 steps 4–8).
    /// Returns nil if nothing was copied.
    static func copySelection() async -> String? {
        let backup = ClipboardService.snapshot()
        let baseline = ClipboardService.changeCount
        KeystrokeSimulator.postCommand(.c)
        guard await ClipboardService.waitForChange(from: baseline) else { return nil }

        let copiedCount = ClipboardService.changeCount
        let text = ClipboardService.readString()
        if ClipboardService.changeCount == copiedCount {
            ClipboardService.restore(backup)
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// ⌘V with clipboard save and restore (RESEARCH §4.8 steps 11–15). If `verify`
    /// fails, the result is left on the clipboard for the user and `false` is returned.
    @discardableResult
    static func paste(_ text: String, verify: (() async -> Bool)? = nil) async -> Bool {
        let backup = ClipboardService.snapshot()
        let written = ClipboardService.writeTransient(text)
        try? await Task.sleep(for: .milliseconds(100))
        await KeystrokeSimulator.waitForModifiersReleased()
        KeystrokeSimulator.postCommand(.v)
        try? await Task.sleep(for: .milliseconds(250))
        if let verify, !(await verify()) {
            ClipboardService.writeString(text)
            return false
        }
        // 500 ms in total before restoring: Electron reads the pasteboard asynchronously.
        try? await Task.sleep(for: .milliseconds(250))
        if ClipboardService.changeCount == written {
            ClipboardService.restore(backup)
        }
        return true
    }
}
