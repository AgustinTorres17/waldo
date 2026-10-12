import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permission: AccessibilityPermission
    let models: ModelDownloader

    @State private var page = Page.general

    enum Page: String, CaseIterable, Identifiable {
        case general, modes, glossary, popup, hotkeys, engine, tryIt

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .modes: "Modes"
            case .glossary: "Glossary"
            case .popup: "Popup"
            case .hotkeys: "Hotkeys"
            case .engine: "Engine"
            case .tryIt: "Try It"
            }
        }

        var icon: String {
            switch self {
            case .general: "gearshape"
            case .modes: "slider.horizontal.3"
            case .glossary: "character.book.closed"
            case .popup: "text.bubble"
            case .hotkeys: "keyboard"
            case .engine: "cpu"
            case .tryIt: "text.cursor"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.divider).frame(width: 1)
            Group {
                switch page {
                case .general: GeneralSettingsView(model: model, settings: settings, permission: permission)
                case .modes: ModesSettingsView(settings: settings)
                case .glossary: GlossarySettingsView(settings: settings)
                case .popup: PopupSettingsView(settings: settings)
                case .hotkeys: HotkeySettingsView()
                case .engine: EngineSettingsView(settings: settings, models: models)
                case .tryIt: TryItSettingsView(model: model, settings: settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.background)
        }
        .frame(width: 700, height: 540)
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Waldo")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.tertiaryText)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            ForEach(Page.allCases) { item in
                SidebarItem(title: item.title, icon: item.icon, isSelected: page == item) { page = item }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        // Leaves room for the traffic lights in the transparent title bar.
        .padding(.top, 48)
        .frame(width: 190)
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar)
    }
}

private struct SidebarItem: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Theme.text : Theme.secondaryText)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Theme.text : Theme.secondaryText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(isSelected ? Theme.pressed : isHovered ? Theme.hover : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.radius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct GeneralSettingsView: View {
    let model: AppModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permission: AccessibilityPermission

    var body: some View {
        SettingsPage(title: "General") {
            SettingsSection(title: "Language") {
                SettingsRow(title: "Default language",
                            detail: "Text in another language is translated into this language. Text already in it is corrected. Apps can have their own in Modes › Per app.") {
                    MonoMenuPicker(selection: $settings.targetLanguage, options: TargetLanguage.allCases) { $0.displayName }
                }
            }
            SettingsSection(title: "Permissions") {
                SettingsRow(title: "Accessibility",
                            detail: "Needed to read selections and to press ⌘A, ⌘C and ⌘V for you.") {
                    if permission.isGranted {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                            Text("Granted")
                        }
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.secondaryText)
                    } else {
                        Button("Grant Access…") { model.showOnboarding() }
                            .buttonStyle(.monoPrimary)
                    }
                }
            }
        }
    }
}

private struct HotkeySettingsView: View {
    var body: some View {
        SettingsPage(title: "Hotkeys") {
            SettingsSection(title: "Shortcuts") {
                SettingsRow(title: "Replace whole field", detail: "Selects everything in the focused field (⌘A) first.") {
                    KeyboardShortcuts.Recorder(for: .replaceField)
                }
                Rectangle().fill(Theme.divider).frame(height: 1)
                SettingsRow(title: "Replace selection", detail: "Works on the text you have selected.") {
                    KeyboardShortcuts.Recorder(for: .replaceSelection)
                }
            }
            SettingsSection(title: "Rephrase") {
                SettingsRow(title: "Rephrase whole field", detail: "Rewrites it so it sounds natural, not just correct.") {
                    KeyboardShortcuts.Recorder(for: .rephraseField)
                }
                Rectangle().fill(Theme.divider).frame(height: 1)
                SettingsRow(title: "Rephrase selection", detail: "Works on the text you have selected.") {
                    KeyboardShortcuts.Recorder(for: .rephraseSelection)
                }
            }
            SettingsSection(title: "Undo") {
                SettingsRow(title: "Undo last replacement",
                            detail: "Puts back what you wrote. Works until you type again, for up to 10 minutes.") {
                    KeyboardShortcuts.Recorder(for: .undoReplacement)
                }
            }
            SettingsCaption("All hotkeys replace the text directly, without a preview; the popup shows the text as it's written.")
        }
    }
}
