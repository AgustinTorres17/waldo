import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os

/// A selection inside an editable field, captured when the popup is shown.
struct SelectionSnapshot: Sendable {
    let pid: pid_t
    let element: AXElement
    let text: String
    let range: CFRange?
    /// Web content (Chromium, Electron, WebKit) exposes text markers; native Cocoa views don't.
    let isWebContent: Bool
    /// Bounds of the selection in AX coordinates, best first.
    let selectionRects: [CGRect]
    /// The field's frame in AX coordinates, the last-resort anchor.
    let fieldFrame: CGRect?

    /// Identifies "the same selection" so a dismissed popup doesn't come back.
    var identity: String {
        "\(pid)|\(range?.location ?? -1)|\(range?.length ?? -1)|\(text.hashValue)"
    }
}

/// Reads the current selection of an app through AX. Every call is blocking IPC,
/// so this only runs off the main thread.
enum SelectionReader {
    static let minimumCharacters = 2
    static let maximumCharacters = 10_000

    private static let log = Logger(subsystem: "com.agustintorres.waldo", category: "selection")

    /// `hint` is the element from the app's last AX notification, a fallback
    /// for apps whose kAXFocusedUIElement is unreliable.
    static func read(pid: pid_t, hint: AXElement?) -> SelectionSnapshot? {
        guard !IsSecureEventInputEnabled() else {
            log.debug("Skip: secure input is on")
            return nil
        }
        guard let focused = focusedElement(pid: pid, hint: hint) else {
            log.debug("Skip: no focused element")
            return nil
        }
        guard case .editable(let field) = EditableFieldDetector.classify(focused) else {
            log.debug("Skip: not editable (role \(focused.string(kAXRoleAttribute) ?? "?", privacy: .public), subrole \(focused.string(kAXSubroleAttribute) ?? "-", privacy: .public))")
            return nil
        }

        // Dead keys and IMEs show uncommitted "marked" text (WebKit exposes it).
        if let marked = field.range("AXTextInputMarkedRange"), marked.length > 0 {
            log.debug("Skip: IME composition in progress")
            return nil
        }

        guard let text = field.string(kAXSelectedTextAttribute) ?? focused.string(kAXSelectedTextAttribute),
              isWorthShowing(text) else {
            log.debug("Skip: no selection worth showing (role \(field.string(kAXRoleAttribute) ?? "?", privacy: .public))")
            return nil
        }

        let range = field.range(kAXSelectedTextRangeAttribute)
        let isWeb = field.attributeNames.contains("AXSelectedTextMarkerRange")
        return SelectionSnapshot(pid: pid, element: field, text: text, range: range, isWebContent: isWeb,
                                 selectionRects: selectionRects(field: field, range: range, text: text),
                                 fieldFrame: field.frame)
    }

    /// Chromium/Electron (Slack) often answer "no value" for the focused element
    /// even when a text area is focused (seen in Slack 4.51 / Electron 43). Fall back
    /// to the element from the last notification, then to the window's focused text area.
    static func focusedElement(pid: pid_t, hint: AXElement?) -> AXElement? {
        let app = AXElement.application(pid)
        if let focused = app.element(kAXFocusedUIElementAttribute) { return focused }
        if let hint, hint.value(kAXFocusedAttribute) as? Bool == true { return hint }
        return app.element(kAXFocusedWindowAttribute)?.firstDescendant { element in
            element.value(kAXFocusedAttribute) as? Bool == true
                && element.string(kAXRoleAttribute).map { [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole].contains($0) } == true
        }
    }

    /// ≥ 2 non-whitespace characters including a letter, ≤ 10,000 characters.
    static func isWorthShowing(_ text: String) -> Bool {
        let meaningful = text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
        return meaningful.count >= minimumCharacters && text.count <= maximumCharacters
            && meaningful.contains { CharacterSet.letters.contains($0) }
    }

    /// Re-reads the field to confirm the selection hasn't changed since `snapshot`.
    enum Revalidation {
        case unchanged
        case collapsed
        case changed
    }

    static func revalidate(_ snapshot: SelectionSnapshot) -> Revalidation {
        guard let focused = focusedElement(pid: snapshot.pid, hint: snapshot.element),
              case .editable(let field) = EditableFieldDetector.classify(focused),
              field == snapshot.element else { return .changed }
        let text = field.string(kAXSelectedTextAttribute) ?? ""
        if text == snapshot.text { return .unchanged }
        return text.isEmpty ? .collapsed : .changed
    }

    /// Bounds chain (RESEARCH popup "Reconciliation" 2): last selected character,
    /// then text-marker bounds (contenteditable, e.g. Slack).
    private static func selectionRects(field: AXElement, range: CFRange?, text: String) -> [CGRect] {
        var candidates: [CGRect] = []
        if let range, range.length > 0 {
            var last = range.location + range.length - 1
            if text.hasSuffix("\n"), range.length > 1 { last -= 1 }
            if let rect = field.bounds(forRange: CFRange(location: last, length: 1)) {
                candidates.append(rect)
            }
        }
        if let markers = field.value("AXSelectedTextMarkerRange"),
           let rect = field.rect("AXBoundsForTextMarkerRange", markers) {
            candidates.append(rect)
        }
        return candidates
    }
}
