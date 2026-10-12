import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permission: AccessibilityPermission
    let models: ModelDownloader

    @State private var page: Page

    init(model: AppModel, settings: SettingsStore, permission: AccessibilityPermission, models: ModelDownloader,
         initialPage: Page = .general) {
        self.model = model
        self.settings = settings
        self.permission = permission
        self.models = models
        _page = State(initialValue: initialPage)
    }

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

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.divider).frame(width: 1)
            Group {
                switch page {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .surface(.window)
        }
        .frame(width: 760, height: 560)
        .ignoresSafeArea()
        .tint(Theme.accent)
        // Theme colors resolve when drawn: a new theme rebuilds the window.
        .id(settings.appTheme)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Page.allCases) { item in
                SidebarItem(page: item, isSelected: page == item) { page = item }
            }
            Spacer()
            AppSignature()
                .padding(.horizontal, 8)
                .padding(.bottom, 14)
        }
        .padding(.horizontal, 10)
        // Leaves room for the traffic lights in the transparent title bar.
        .padding(.top, 50)
        .frame(width: 206)
        .frame(maxHeight: .infinity)
        .surface(.sidebar)
    }
}

private struct SidebarItem: View {
    let page: SettingsView.Page
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
            }

            SettingsSection(title: "Startup") {
                SettingsRow(title: "Open at login",
                            detail: launchAtLogin.needsApproval
                                ? "Turned off in System Settings › General › Login Items. Turn it on there."
                                : "Waldo starts in the menu bar when you log in.") {
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
