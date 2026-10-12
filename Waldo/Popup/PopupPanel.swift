import AppKit
import SwiftUI

/// A floating panel that never takes keyboard focus, so the app being typed in
/// keeps its caret and selection (RESEARCH popup P5).
final class PopupPanel: NSPanel {
    init() {
        // .nonactivatingPanel must be set at init; toggling it later breaks key handling.
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        // .floating sits below other apps' full-screen spaces; .screenSaver doesn't.
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// SwiftUI buttons in an inactive window ignore the first click before macOS 15.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
