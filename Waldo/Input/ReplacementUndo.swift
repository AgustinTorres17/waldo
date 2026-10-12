import AppKit
import ApplicationServices

/// Remembers Waldo's last replacement so it can be undone (one level).
///
/// Native text views: the replacement is found by its AX range, checked, and
/// swapped back. Web content (Chromium, Electron, WebKit) can't be checked that
/// way, so it gets ⌘Z: Waldo's paste is a single undo step there. Typing after
/// the replacement cancels the undo, so ⌘Z never undoes the user's own edits.
@MainActor
final class ReplacementUndo {
    struct Record {
        let pid: pid_t
        let original: String
        let replacement: String
        /// The field and where the replacement starts (UTF-16), when the app reports them.
        let element: AXElement?
        let location: Int?
        let isWebContent: Bool
        let date = ContinuousClock.now
    }

    enum Outcome {
        case restored(near: CGRect?)
        case nothingToUndo
        case wrongApp(String)
    }

    static let lifetime = Duration.seconds(600)

    private let state: AppState
    private let isAutomating: () -> Bool
    private var keyMonitor: Any?

    private(set) var last: Record? {
        didSet {
            state.canUndoReplacement = last != nil
            if last == nil { stopWatchingKeys() } else { watchKeys() }
        }
    }

    init(state: AppState, isAutomating: @escaping () -> Bool) {
        self.state = state
        self.isAutomating = isAutomating
    }

    func record(_ record: Record) {
        last = record
    }

    func undo() async -> Outcome {
        guard let record = last, ContinuousClock.now - record.date < Self.lifetime else {
            last = nil
            return .nothingToUndo
        }
        guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier == record.pid else {
            let name = NSRunningApplication(processIdentifier: record.pid)?.localizedName ?? "the app"
            return .wrongApp(name)
        }
        last = nil
        let frame = await Task.detached { record.element?.frame }.value.map(PopupPositioner.appKitRect(fromAX:))

        if !record.isWebContent, let element = record.element, let location = record.location {
            let restored = await Task.detached {
                Self.restoreViaAccessibility(element: element, location: location,
                                             replacement: record.replacement, original: record.original)
            }.value
            if restored { return .restored(near: frame) }
        }
        await KeystrokeSimulator.waitForModifiersReleased()
        KeystrokeSimulator.postCommand(.z)
        return .restored(near: frame)
    }

    /// Only if the replacement is still where Waldo put it.
    nonisolated private static func restoreViaAccessibility(element: AXElement, location: Int,
                                                            replacement: String, original: String) -> Bool {
        let range = CFRange(location: location, length: replacement.utf16.count)
        guard element.string(forRange: range) == replacement,
              element.setRange(kAXSelectedTextRangeAttribute, range),
              element.set(kAXSelectedTextAttribute, original as CFString) else { return false }
        return element.string(forRange: CFRange(location: location, length: original.utf16.count)) == original
    }

    // Typing (any key without ⌘) after the replacement makes ⌘Z unsafe.
    private func watchKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, !self.isAutomating(), !event.modifierFlags.contains(.command) else { return }
                self.last = nil
            }
        }
    }

    private func stopWatchingKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
