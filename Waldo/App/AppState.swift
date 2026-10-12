import Foundation

/// Runtime state shown in the menu bar.
@MainActor
final class AppState: ObservableObject {
    @Published var isProcessing = false
    /// Short description of the engine that will handle the next request.
    @Published var engineDescription = "Checking…"
    /// Waldo's last replacement can still be undone.
    @Published var canUndoReplacement = false
}
