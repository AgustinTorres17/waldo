import SwiftUI

/// Create and edit the user's modes: preferences layered on top of every task.
struct ModesSettingsView: View {
    @ObservedObject var settings: SettingsStore

    @State private var editingID: UUID?

    var body: some View {
        SettingsPage(title: "Modes",
                     subtitle: "How you want to sound: formal, casual, for work, for a friend. A mode applies to Translate / Correct, Rephrase and the hotkeys.") {
            SettingsSection(title: "Your modes",
                            footer: "The default mode is used everywhere, except in apps that have their own.") {
                VStack(spacing: 0) {
                    ForEach(settings.customModes) { mode in
                        modeRow(mode)
                        SettingsDivider()
                    }
                    HStack {
                        Button(action: addMode) {
                            HStack(spacing: 5) {
                                Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                                Text("New mode")
                            }
                        }
                        .buttonStyle(.monoGhost)
                        .padding(.leading, -9)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }

            if let index = settings.customModes.firstIndex(where: { $0.id == editingID }) {
                ModeEditor(mode: $settings.customModes[index])
                    .id(editingID)
            }

            SettingsSection(title: "Per app",
                            footer: "These apps use their own mode and language instead of the defaults. Changing them in the popup changes them for that app.") {
                VStack(spacing: 0) {
                    ForEach(settings.appModeRules) { rule in
                        HStack {
                            AppRow(bundleID: rule.bundleID)
                            Spacer()
                            MonoMenuPicker(selection: ruleBinding(rule.bundleID, \.modeID),
                                           options: [nil] + settings.customModes.map(\.id)) { id in
                                settings.customModes.first { $0.id == id }?.name ?? "No mode"
                            }
                            .help("Mode")
                            MonoMenuPicker(selection: ruleBinding(rule.bundleID, \.language),
                                           options: [nil] + TargetLanguage.allCases) { language in
                                language?.displayName ?? "Default language"
                            }
                            .help("Language")
                            Button {
                                settings.appModeRules.removeAll { $0.bundleID == rule.bundleID }
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.icon)
                            .help("Use the defaults")
                        }
                        .padding(.vertical, 6)
                        SettingsDivider()
                    }
                    HStack {
                        Button(action: addApps) {
                            HStack(spacing: 5) {
                                Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                                Text("Add app")
                            }
                        }
                        .buttonStyle(.monoGhost)
                        .padding(.leading, -9)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
            .disabled(settings.customModes.isEmpty)
        }
        .onAppear {
            if editingID == nil { editingID = settings.activeModeID ?? settings.customModes.first?.id }
        }
    }

    private func modeRow(_ mode: CustomMode) -> some View {
        let isEditing = mode.id == editingID
        let isActive = mode.id == settings.activeModeID
        return HStack(spacing: 8) {
            Button { editingID = mode.id } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isEditing ? Theme.accent : Theme.border)
                        .frame(width: 6, height: 6)
                    Text(mode.name.isEmpty ? "Untitled" : mode.name)
                        .font(.system(size: 13, weight: isEditing ? .semibold : .regular))
                        .foregroundStyle(Theme.text)
                    if isActive {
                        Badge("Default", prominent: true)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isActive {
                Button("Turn off") { settings.activeModeID = nil }
                    .buttonStyle(.monoGhost)
            } else {
                Button("Make default") { settings.activeModeID = mode.id }
                    .buttonStyle(.monoGhost)
            }
            Button {
                delete(mode)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.icon)
            .help("Delete")
        }
        .padding(.vertical, 6)
    }

    /// Edits one field of an app's rule; nil means the default.
    private func ruleBinding<Value>(_ bundleID: String, _ keyPath: WritableKeyPath<AppRule, Value?>) -> Binding<Value?> {
        Binding(
            get: { settings.appModeRules.first { $0.bundleID == bundleID }?[keyPath: keyPath] },
            set: { value in
                guard let index = settings.appModeRules.firstIndex(where: { $0.bundleID == bundleID }) else { return }
                settings.appModeRules[index][keyPath: keyPath] = value
            }
        )
    }

    /// New apps start with the editing mode, the likeliest reason to add them.
    private func addApps() {
        let existing = Set(settings.appModeRules.map(\.bundleID))
        let modeID = editingID ?? settings.customModes.first?.id
        for bundleID in AppRow.chooseApps() where !existing.contains(bundleID) {
            settings.appModeRules.append(AppRule(bundleID: bundleID, modeID: modeID))
        }
    }

    private func addMode() {
        let mode = CustomMode(name: "New mode")
        settings.customModes.append(mode)
        editingID = mode.id
    }

    private func delete(_ mode: CustomMode) {
        settings.customModes.removeAll { $0.id == mode.id }
        if editingID == mode.id { editingID = settings.customModes.first?.id }
    }
}

private struct ModeEditor: View {
    @Binding var mode: CustomMode

    var body: some View {
        SettingsSection(title: mode.name.isEmpty ? "Edit mode" : "Edit “\(mode.name)”") {
            VStack(alignment: .leading, spacing: 14) {
                field("Name") {
                    TextField("", text: limited(\.name, to: CustomMode.maxNameLength))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .fieldBox()
                }
                textArea("Guidelines",
                         hint: "How Waldo should write: tone, formality, length, words to use or avoid.",
                         text: \.guidelines, height: 90)
                textArea("Examples you like",
                         hint: "Messages written the way you want to sound. Waldo copies their style, not their content.",
                         text: \.likedExamples, height: 80)
                textArea("Examples you don't like",
                         hint: "Messages that sound wrong to you. Waldo avoids their style.",
                         text: \.dislikedExamples, height: 80)
            }
            .padding(.vertical, 14)
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            content()
        }
    }

    private func textArea(_ title: String, hint: String, text: WritableKeyPath<CustomMode, String>,
                          height: CGFloat) -> some View {
        field(title) {
            VStack(alignment: .leading, spacing: 4) {
                TextEditor(text: limited(text, to: CustomMode.maxFieldLength))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: height)
                    .fieldBox()
                HStack(alignment: .top) {
                    SettingsCaption(hint)
                    Spacer(minLength: 12)
                    Text("\(mode[keyPath: text].count)/\(CustomMode.maxFieldLength)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiaryText)
                        .monospacedDigit()
                }
            }
        }
    }

    private func limited(_ keyPath: WritableKeyPath<CustomMode, String>, to limit: Int) -> Binding<String> {
        Binding(
            get: { mode[keyPath: keyPath] },
            set: { mode[keyPath: keyPath] = String($0.prefix(limit)) }
        )
    }
}
