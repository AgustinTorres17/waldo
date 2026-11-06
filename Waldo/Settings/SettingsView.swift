import KeyboardShortcuts
import SwiftUI

/// A section of Settings. Settings shows in Waldo's window in place of the chats.
enum SettingsPane: String, CaseIterable, Identifiable {
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
        case .general: "gearshape.fill"
        case .modes: "theatermasks.fill"
        case .glossary: "character.book.closed.fill"
        case .popup: "text.bubble.fill"
        case .hotkeys: "command"
        case .engine: "cpu.fill"
        case .tryIt: "text.cursor"
        }
    }

    var tint: NSColor {
        switch self {
        case .general: Theme.rgb(0x8E8E93)
        case .modes: Theme.rgb(0xAF52DE)
        case .glossary: Theme.rgb(0xFF9F0A)
        case .popup: Theme.rgb(0x0A84FF)
        case .hotkeys: Theme.rgb(0xFF375F)
        case .engine: Theme.rgb(0x30D158)
        case .tryIt: Theme.rgb(0x5E5CE6)
        }
    }
}

/// The pane's page, on the right of Waldo's window.
struct SettingsPaneView: View {
    let model: AppModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permission: AccessibilityPermission
    let models: ModelDownloader
    let pane: SettingsPane

    var body: some View {
        Group {
            switch pane {
            case .general:
                GeneralSettingsView(model: model, settings: settings, permission: permission,
                                    launchAtLogin: model.launchAtLogin)
            case .modes: ModesSettingsView(settings: settings)
            case .glossary: GlossarySettingsView(settings: settings)
            case .popup: PopupSettingsView(settings: settings)
            case .hotkeys: HotkeySettingsView()
            case .engine: EngineSettingsView(settings: settings, models: models)
            case .tryIt: TryItSettingsView(model: model, settings: settings)
            }
        }
        .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .surface(.window)
    }
}

/// Settings' sidebar: back to the chats, then the panes.
struct SettingsSidebar: View {
    @Binding var selection: SettingsPane
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Chats")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 7)
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to your chats")
            .padding(.bottom, 8)
            ForEach(SettingsPane.allCases) { item in
                SidebarItem(page: item, isSelected: selection == item) { selection = item }
            }
            Spacer()
            AppSignature()
                .padding(.horizontal, 8)
                .padding(.bottom, 14)
        }
        .padding(.horizontal, 10)
        // Leaves room for the traffic lights in the transparent title bar.
        .padding(.top, 46)
        .frame(width: 240)
        .frame(maxHeight: .infinity)
        .surface(.sidebar)
        .overlay(alignment: .top) { WindowDragArea().frame(height: 40) }
    }
}

private struct SidebarItem: View {
    let page: SettingsPane
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                IconTile(symbol: page.icon, color: page.tint)
                Text(page.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.text : Theme.text.opacity(0.85))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .frame(height: 30)
            .background(isSelected ? Theme.selection : isHovered ? Theme.hover : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.radius + 1, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

/// The app's icon, name and version, at the bottom of the sidebar.
struct AppSignature: View {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("Waldo")
                    .font(Theme.display(13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Version \(Self.version) · On-device")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
    }
}

private struct ChatsRow: View {
    @ObservedObject var library: ChatLibrary
    @State private var confirming = false

    var body: some View {
        SettingsRow(title: "Saved chats", detail: library.chats.isEmpty ? "None yet." : "\(library.chats.count) saved.") {
            Button("Delete All…", role: .destructive) { confirming = true }
                .buttonStyle(.monoDestructive)
                .disabled(library.chats.isEmpty)
        }
        .confirmationDialog("Delete all \(library.chats.count) chats?", isPresented: $confirming) {
            Button("Delete All Chats", role: .destructive) { library.deleteAll() }
        } message: {
            Text("Their messages and captures are removed from this Mac. This can't be undone.")
        }
    }
}

private struct GeneralSettingsView: View {
    let model: AppModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permission: AccessibilityPermission
    @ObservedObject var launchAtLogin: LaunchAtLogin

    var body: some View {
        SettingsPage(title: "General", subtitle: "Language, appearance, and how Waldo starts.") {
            SettingsSection(title: "Appearance") {
                HStack(spacing: 12) {
                    ForEach(AppTheme.allCases) { theme in
                        ThemeCard(theme: theme, isSelected: settings.appTheme == theme) {
                            settings.appTheme = theme
                        }
                    }
                }
                .padding(.vertical, 12)
            }

            SettingsSection(title: "Language") {
                SettingsRow(title: "Default language",
                            detail: "Text in another language is translated into this one. Text already in it is corrected. Apps can have their own in Modes › Per app.") {
                    MonoMenuPicker(selection: $settings.targetLanguage, options: TargetLanguage.allCases) { $0.displayName }
                }
                SettingsDivider()
                SettingsRow(title: "Explanation language",
                            detail: "Chats and explanations are answered in this language. A message in another language is answered in that one.") {
                    MonoMenuPicker(selection: $settings.chatLanguage, options: TargetLanguage.allCases) { $0.displayName }
                }
            }

            SettingsSection(title: "Web search",
                            footer: "Turn it on with the globe button in a chat. Only the search query the model writes leaves your Mac, never your capture or your messages.") {
                SettingsRow(title: "Search with",
                            detail: settings.searchProvider == .duckDuckGo
                                ? "Nothing to set up. If DuckDuckGo starts asking for a captcha, use SearXNG."
                                : "Your own SearXNG, with JSON results allowed in its settings.yml.") {
                    MonoMenuPicker(selection: $settings.searchProvider, options: SearchProvider.allCases) { $0.title }
                }
                if settings.searchProvider == .searXNG {
                    SettingsDivider()
                    SettingsRow(title: "SearXNG address") {
                        TextField("http://localhost:8888", text: $settings.searXNGURL)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5))
                            .padding(.horizontal, 8)
                            .frame(width: 220, height: 27)
                            .fieldBox()
                    }
                }
            }

            SettingsSection(title: "Chats",
                            footer: "Chats and their captures are saved only on this Mac, in ~/Library/Application Support/Waldo/Chats.") {
                ChatsRow(library: model.library)
            }

            SettingsSection(title: "Startup") {
                SettingsRow(title: "Show in menu bar",
                            detail: "An icon at the top of the screen with Waldo's status, modes and quick actions.") {
                    Toggle(isOn: $settings.showsMenuBarIcon) { EmptyView() }
                        .toggleStyle(.mono)
                }
                SettingsDivider()
                SettingsRow(title: "Open at login",
                            detail: launchAtLogin.needsApproval
                                ? "Turned off in System Settings › General › Login Items. Turn it on there."
                                : "Waldo starts in the background when you log in; open its window from the Dock.") {
                    if launchAtLogin.needsApproval {
                        Button("Open Login Items…") { launchAtLogin.openLoginItems() }
                            .buttonStyle(.monoSecondary)
                    } else {
                        Toggle(isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.set($0) })) { EmptyView() }
                            .toggleStyle(.mono)
                    }
                }
            }

            SettingsSection(title: "Permissions") {
                SettingsRow(title: "Accessibility",
                            detail: "Needed to read selections and to press ⌘A, ⌘C and ⌘V for you.") {
                    if permission.isGranted {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.success)
                            Text("Granted")
                        }
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                    } else {
                        Button("Grant Access…") { model.showOnboarding() }
                            .buttonStyle(.monoPrimary)
                    }
                }
            }
        }
        .onAppear(perform: launchAtLogin.refresh)
    }
}

/// One theme in the Appearance picker: a miniature window drawn in that theme's
/// colors (not the current theme's), its name, and a check when chosen.
private struct ThemeCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ThemeMiniature(theme: theme, dark: colorScheme == .dark)
                    .frame(height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Theme.border)
                    )
                    .padding(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(isSelected ? Theme.accent : isHovered ? Theme.border : .clear,
                                          lineWidth: isSelected ? 2 : 1)
                    )
                HStack(spacing: 5) {
                    Text(theme.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .padding(.leading, 3)
                Text(theme.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .accessibilityLabel("\(theme.title) theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A sidebar, two rows and a button, in `theme`'s palette.
private struct ThemeMiniature: View {
    let theme: AppTheme
    let dark: Bool

    var body: some View {
        let palette = Palette(theme: theme, dark: dark)
        ZStack {
            palette.backdrop
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(0..<4) { index in
                        Capsule().fill(palette.line.opacity(index == 0 ? 1 : 0.55))
                            .frame(width: index == 0 ? 26 : 20, height: 4)
                    }
                }
                .padding(.top, 14)
                .padding(.leading, 8)
                .frame(width: 44, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(palette.sidebar)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Aa")
                        .font(theme == .editorial
                              ? .system(size: 15, weight: .regular, design: .serif)
                              : .system(size: 13, weight: .bold))
                        .foregroundStyle(palette.text)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(palette.card)
                        .frame(height: 18)
                        .overlay(alignment: .leading) {
                            Capsule().fill(palette.line).frame(width: 30, height: 3.5).padding(.leading, 6)
                        }
                        .overlay(alignment: .trailing) {
                            Capsule().fill(palette.accent).frame(width: 16, height: 8).padding(.trailing, 5)
                        }
                    HStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(palette.accent)
                            .frame(width: 30, height: 10)
                    }
                }
                .padding(9)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(palette.content)
            }
        }
    }

    private struct Palette {
        var backdrop: AnyView
        var sidebar: Color
        var content: Color
        var card: Color
        var text: Color
        var line: Color
        var accent: AnyShapeStyle

        init(theme: AppTheme, dark: Bool) {
            func c(_ light: UInt32, _ darkHex: UInt32, _ alpha: Double = 1) -> Color {
                Color(nsColor: Theme.rgba(dark ? darkHex : light, alpha))
            }
            switch theme {
            case .glass:
                backdrop = AnyView(LinearGradient(colors: dark ? [c(0, 0x2B2F6B), c(0, 0x4A2466)]
                                                               : [c(0xB9C6FF, 0), c(0xE7C3F5, 0)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                sidebar = dark ? .black.opacity(0.25) : .white.opacity(0.35)
                content = dark ? .black.opacity(0.35) : .white.opacity(0.6)
                card = dark ? .white.opacity(0.08) : .white.opacity(0.85)
                text = c(0x1D1D1F, 0xF2F2F2)
                line = dark ? .white.opacity(0.35) : .black.opacity(0.22)
                accent = AnyShapeStyle(LinearGradient(colors: [c(0x5E5CE6, 0x8E8CFF), c(0x9B4FE8, 0xB88BFF)],
                                                      startPoint: .leading, endPoint: .trailing))
            case .mono:
                backdrop = AnyView(c(0xFFFFFF, 0x141414))
                sidebar = c(0xF4F4F4, 0x1C1C1C)
                content = c(0xFFFFFF, 0x141414)
                card = c(0xF7F7F7, 0x222222)
                text = c(0x111111, 0xEDEDED)
                line = dark ? .white.opacity(0.3) : .black.opacity(0.2)
                accent = AnyShapeStyle(c(0x111111, 0xEDEDED))
            case .editorial:
                backdrop = AnyView(c(0xFBF8F2, 0x1C1A17))
                sidebar = c(0xF0EADD, 0x24211C)
                content = c(0xFBF8F2, 0x1C1A17)
                card = c(0xFFFDF9, 0x2A2621)
                text = c(0x2B2722, 0xE9E3D7)
                line = c(0x2B2722, 0xE9E3D7, 0.25)
                accent = AnyShapeStyle(c(0x284B7A, 0x93B3DD))
            }
        }
    }
}

private struct HotkeySettingsView: View {
    var body: some View {
        SettingsPage(title: "Hotkeys", subtitle: "Run Waldo from anywhere, without the popup.") {
            SettingsSection(title: "Translate / Correct") {
                SettingsRow(title: "Whole field", detail: "Selects everything in the focused field (⌘A) first.") {
                    KeyboardShortcuts.Recorder(for: .replaceField)
                }
                SettingsDivider()
                SettingsRow(title: "Selection", detail: "Works on the text you have selected.") {
                    KeyboardShortcuts.Recorder(for: .replaceSelection)
                }
            }
            SettingsSection(title: "Rephrase") {
                SettingsRow(title: "Whole field", detail: "Rewrites it so it sounds natural, not just correct.") {
                    KeyboardShortcuts.Recorder(for: .rephraseField)
                }
                SettingsDivider()
                SettingsRow(title: "Selection", detail: "Works on the text you have selected.") {
                    KeyboardShortcuts.Recorder(for: .rephraseSelection)
                }
            }
            SettingsSection(title: "Chat",
                            footer: "Chats run on the downloaded model. Captures need its vision add-on (Settings › Engine) and Screen Recording permission.") {
                SettingsRow(title: "New chat", detail: "Ask anything; add captures from the chat.") {
                    KeyboardShortcuts.Recorder(for: .newChat)
                }
                SettingsDivider()
                SettingsRow(title: "Explain screen region",
                            detail: "Then drag a rectangle; Esc cancels.") {
                    KeyboardShortcuts.Recorder(for: .explainScreen)
                }
                SettingsDivider()
                SettingsRow(title: "Explain whole screen",
                            detail: "Captures the screen under the mouse right away, without dragging.") {
                    KeyboardShortcuts.Recorder(for: .explainWholeScreen)
                }
            }
            SettingsSection(title: "Undo",
                            footer: "Hotkeys replace the text directly, without a preview. The popup shows the text as it's written.") {
                SettingsRow(title: "Undo last replacement",
                            detail: "Puts back what you wrote. Works until you type again, for up to 10 minutes.") {
                    KeyboardShortcuts.Recorder(for: .undoReplacement)
                }
            }
        }
    }
}
