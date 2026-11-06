import AppKit
import SwiftUI

/// The chat's text box. SwiftUI's vertical TextField measures all its text in every
/// layout pass, which froze the window for seconds after pasting a long text.
/// Return sends and Shift-Return starts a new line.
struct ComposerTextField: NSViewRepresentable {
    @Binding var text: String
    /// Its content's height, at most `maxLines` tall.
    @Binding var height: CGFloat
    /// Takes the keyboard focus when this changes.
    let focusID: UUID
    let onSubmit: () -> Void

    private static let maxLines: CGFloat = 8
    private static let font = NSFont.systemFont(ofSize: 13.5)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none

        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = Self.font
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        context.coordinator.focusID = focusID
        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            textView.window?.makeFirstResponder(textView)
            context.coordinator.fitHeight(of: textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        coordinator.parent = self
        let color = NSColor(Theme.text)
        textView.textColor = color
        textView.insertionPointColor = color
        if textView.string != text {
            textView.string = text
            DispatchQueue.main.async { coordinator.fitHeight(of: textView) }
        }
        if coordinator.focusID != focusID {
            coordinator.focusID = focusID
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
        if coordinator.width != textView.bounds.width {
            coordinator.width = textView.bounds.width
            DispatchQueue.main.async { coordinator.fitHeight(of: textView) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextField
        var focusID: UUID?
        var width: CGFloat = 0

        init(_ parent: ComposerTextField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            fitHeight(of: textView)
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                parent.onSubmit()
            }
            return true
        }

        func fitHeight(of textView: NSTextView) {
            guard let layout = textView.layoutManager, let container = textView.textContainer else { return }
            layout.ensureLayout(for: container)
            let line = ceil(layout.defaultLineHeight(for: ComposerTextField.font))
            let used = ceil(layout.usedRect(for: container).height)
            let fitted = min(max(used, line), line * ComposerTextField.maxLines)
            if parent.height != fitted { parent.height = fitted }
        }
    }
}
