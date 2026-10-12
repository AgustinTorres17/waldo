import AppKit
import SwiftUI

@main
struct WaldoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        let model = appDelegate.model
        MenuBarExtra {
            MenuContent(model: model, settings: model.settings, state: model.state, permission: model.permission)
        } label: {
            MenuBarIcon(state: model.state)
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let model = AppModel()

    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        terminateOtherInstances()
        model.launch()
    }

    /// Two copies would both register the hotkeys and show two popups; the newest
    /// launch (e.g. a fresh build) wins.
    @MainActor private func terminateOtherInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let current = ProcessInfo.processInfo.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        where app.processIdentifier != current {
            app.terminate()
        }
    }
}

private struct MenuBarIcon: View {
    @ObservedObject var state: AppState

    var body: some View {
        Image(systemName: state.isProcessing ? "ellipsis.bubble.fill" : "character.bubble")
            .accessibilityLabel(state.isProcessing ? "Waldo is processing" : "Waldo")
    }
}
