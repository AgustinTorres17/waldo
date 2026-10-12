import AppKit
import SwiftUI

/// Hosts a SwiftUI view in a plain NSWindow. SwiftUI's `Settings` scene is
/// unreliable to open from a menu bar–only app on macOS 13, and the window is
/// released on close so it costs no memory while hidden.
@MainActor
final class HostedWindowController: NSObject, NSWindowDelegate {
    private let title: String
    /// Content runs under a transparent title bar (the settings sidebar does this).
    private let fullSizeContent: Bool
    private var window: NSWindow?

    init(title: String, fullSizeContent: Bool = false) {
        self.title = title
        self.fullSizeContent = fullSizeContent
    }

    func show<Content: View>(_ content: () -> Content) {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: content()))
            window.title = title
            window.styleMask = [.titled, .closable]
            if fullSizeContent {
                window.styleMask.insert(.fullSizeContentView)
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.isMovableByWindowBackground = true
            }
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
