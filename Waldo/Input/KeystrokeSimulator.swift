import Carbon.HIToolbox
import CoreGraphics

/// Posts ⌘-shortcuts to the frontmost app (RESEARCH §4.1).
/// Key codes are ANSI positions; non-QWERTY layouts are a known limitation.
enum KeystrokeSimulator {
    enum Key: CGKeyCode {
        case a = 0x00 // kVK_ANSI_A
        case c = 0x08 // kVK_ANSI_C
        case v = 0x09 // kVK_ANSI_V
        case z = 0x06 // kVK_ANSI_Z
    }

    static func postCommand(_ key: Key) {
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: keyDown)
            // Explicit flags replace whatever modifiers the user is still holding.
            event?.flags = .maskCommand
            event?.post(tap: .cgSessionEventTap)
        }
    }

    /// Waits until the user releases the hotkey's modifiers, so ⌘C isn't seen as ⌥⌘C.
    /// Only runs during an active hotkey flow, never while idle.
    static func waitForModifiersReleased(timeout: Duration = .milliseconds(1000)) async {
        let mask: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift, .maskControl, .maskSecondaryFn]
        let deadline = ContinuousClock.now + timeout
        while !CGEventSource.flagsState(.hidSystemState).intersection(mask).isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Password fields and some apps enable secure input, which blocks synthetic events.
    static var isSecureInputEnabled: Bool {
        IsSecureEventInputEnabled()
    }
}
