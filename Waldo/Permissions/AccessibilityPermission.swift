import AppKit
import ApplicationServices

/// Tracks the Accessibility permission. Both the hotkeys (posting ⌘A/⌘C/⌘V)
/// and the selection popup (reading other apps' text) depend on it.
@MainActor
final class AccessibilityPermission: ObservableObject {
    @Published private(set) var isGranted = AXIsProcessTrusted()

    private var observer: NSObjectProtocol?

    init() {
        // The system broadcasts this when any app's Accessibility trust changes,
        // so we can react without polling. The new value lands shortly after.
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                self?.refresh()
            }
        }
    }

    func refresh() {
        isGranted = AXIsProcessTrusted()
    }

    /// Adds Waldo to the Accessibility list (with the system prompt) and opens the pane.
    func request() {
        // Value of kAXTrustedCheckOptionPrompt; the C global isn't concurrency-safe in Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isGranted = AXIsProcessTrustedWithOptions(options)
        if !isGranted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
