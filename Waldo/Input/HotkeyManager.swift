import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let replaceField = Self("replaceField", initial: .init(.t, modifiers: [.option, .command]))
    static let replaceSelection = Self("replaceSelection", initial: .init(.t, modifiers: [.option, .shift, .command]))
    static let rephraseField = Self("rephraseField", initial: .init(.r, modifiers: [.option, .command]))
    static let rephraseSelection = Self("rephraseSelection", initial: .init(.r, modifiers: [.option, .shift, .command]))
    static let undoReplacement = Self("undoReplacement", initial: .init(.z, modifiers: [.option, .command]))
    static let explainScreen = Self("explainScreen", initial: .init(.e, modifiers: [.option, .command]))
    static let explainWholeScreen = Self("explainWholeScreen", initial: .init(.e, modifiers: [.option, .shift, .command]))
    static let newChat = Self("newChat", initial: .init(.k, modifiers: [.option, .command]))
}

/// Registers the global hotkeys (Carbon via KeyboardShortcuts: no permission needed,
/// and the keystroke never reaches the frontmost app).
@MainActor
final class HotkeyManager {
    /// `explain` gets whether to capture the whole screen instead of a dragged region.
    init(flow: HotkeyFlow, undo: @escaping () -> Void, explain: @escaping (Bool) -> Void, newChat: @escaping () -> Void) {
        KeyboardShortcuts.onKeyUp(for: .newChat, action: newChat)
        KeyboardShortcuts.onKeyUp(for: .undoReplacement, action: undo)
        KeyboardShortcuts.onKeyUp(for: .explainScreen) { explain(false) }
        KeyboardShortcuts.onKeyUp(for: .explainWholeScreen) { explain(true) }
        // Key-up, so the main key is already released when we post ⌘A/⌘C (RESEARCH §3.3).
        KeyboardShortcuts.onKeyUp(for: .replaceField) {
            Task { await flow.run(.wholeField) }
        }
        KeyboardShortcuts.onKeyUp(for: .replaceSelection) {
            Task { await flow.run(.selection) }
        }
        KeyboardShortcuts.onKeyUp(for: .rephraseField) {
            Task { await flow.run(.wholeField, mode: .rephrase) }
        }
        KeyboardShortcuts.onKeyUp(for: .rephraseSelection) {
            Task { await flow.run(.selection, mode: .rephrase) }
        }
    }
}
