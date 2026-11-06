import AppKit
import SwiftUI

@main
struct WaldoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// SettingsStore.showsMenuBarIcon writes the same default.
    @AppStorage(SettingsStore.showsMenuBarIconKey) private var showsMenuBarIcon = false

    var body: some Scene {
        let model = appDelegate.model
        MenuBarExtra(isInserted: $showsMenuBarIcon) {
            MenuContent(model: model, settings: model.settings, state: model.state, permission: model.permission)
        } label: {
            MenuBarIcon(state: model.state)
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.openSettings() }
                    .keyboardShortcut(",")
            }
            CommandGroup(replacing: .newItem) {
                Button("New Chat") { model.startChat() }
                    .keyboardShortcut("n")
                Button("Explain Screen Region…") { model.startExplain() }
                Button("Explain Whole Screen") { model.startExplain(wholeScreen: true) }
            }
            CommandGroup(after: .windowArrangement) {
                Button("Waldo") { model.showMainWindow() }
                    .keyboardShortcut("0")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let model = AppModel()
    /// Opened by macOS at login: stay in the background (hotkeys and popup work).
    private var launchedAtLogin = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAtLogin = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        terminateOtherInstances()
        model.launch()
        if !launchedAtLogin, model.permission.isGranted { model.showMainWindow() }
    }

    /// Clicking the Dock icon (or opening Waldo again) brings the window back.
    @MainActor func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.showMainWindow()
        return false
    }

    /// Closing the window keeps Waldo running for its hotkeys and popup.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
