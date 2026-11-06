import SwiftUI

struct MenuContent: View {
    let model: AppModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var state: AppState
    @ObservedObject var permission: AccessibilityPermission

    var body: some View {
        if state.isProcessing {
            Text("Processing…")
            Divider()
        }
        Text("Engine: \(state.engineDescription)")
        Text("Default Language: \(settings.targetLanguage.displayName)")
        if !settings.customModes.isEmpty {
            Picker("Default Mode", selection: $settings.activeModeID) {
                Text("No mode").tag(UUID?.none)
                ForEach(settings.customModes) { mode in
                    Text(mode.name).tag(UUID?.some(mode.id))
                }
            }
        }
        Divider()
        Button("Open Waldo") { model.showMainWindow() }
        Button("New Chat") { model.startChat() }
        Button("Explain Screen Region…") { model.startExplain() }
        Button("Explain Whole Screen") { model.startExplain(wholeScreen: true) }
        Button("Undo Last Replacement") { Task { await model.undoLastReplacement() } }
            .disabled(!state.canUndoReplacement)
        Toggle("Show Popup on Selection", isOn: $settings.popupEnabled)
        if !permission.isGranted {
            Button("Grant Accessibility Access…") { model.showOnboarding() }
        }
        Divider()
        Button("Settings…") { model.openSettings() }
            .keyboardShortcut(",")
        Button("Quit Waldo") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
